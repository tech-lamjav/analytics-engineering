# Proposta — Fantasy de Futebol (SmartBetting)

> **Status:** rascunho para avaliação do time
> **Data:** 2026-06-30
> **Escopo:** (1) como calcular *fantasy points* de futebol com o que já ingerimos; (2) proposta de implementação; (3) precedente já existente na NBA (campo `nba_fantasy_pts` da balldontlie).
> **TL;DR:** Não existe endpoint de "fantasy points" pronto na API-Football. Mas *fantasy points* não é um dado — é uma **fórmula** sobre estatística por jogador, e essa estatística **já está 100% ingerida** em `fact_fixture_player_stats` (vinda de `/fixtures/players`). Construir o fantasy de futebol é **uma camada dbt nova**, sem nova ingestão. Na NBA o cenário é ainda mais favorável: a balldontlie **já entrega o campo `nba_fantasy_pts` pronto** (hoje ingerido no raw, mas descartado no staging).

---

## Sumário executivo

- **Futebol — API-Football v3 não tem endpoint de fantasy.** Varremos o inventário completo da v3: não há `/fantasy` nem campo `fantasy_points` em endpoint algum.
- **A matéria-prima já é nossa.** O endpoint `/fixtures/players` (que a própria API-Football documenta como *"core data source for fantasy football scoring systems"*) já é ingerido e modelado em `fact_fixture_player_stats` — 1 linha por jogador por jogo, com `rating` + ~40 colunas de scout (gols, assistências, desarmes, finalizações, faltas, cartões, pênaltis, defesas…).
- **Calcular fantasy = `Σ (evento × peso)` por jogador-jogo, sensível à posição.** A regra de pesos (Cartola FC, FPL, ou própria) é a única coisa que a API nunca dá — é regra de produto, não dado.
- **~90% dos scouts saem direto das colunas que já temos.** Só 2 scouts do Cartola não saem limpos de `/fixtures/players`: **gol contra (GC)** — está em `/fixtures/events`, que também já ingerimos — e **finalização na trave (FT)** — não existe na API (omitir).
- **Precedente NBA (importante):** a balldontlie **entrega `nba_fantasy_pts` pronto** no endpoint `season_averages` (category `general`, type `base`), junto de `dd2` (duplo-duplo) e `td3` (triplo-duplo). Confirmado no nosso BigQuery (`raw_season_averages_general_base.stats.nba_fantasy_pts`). Hoje é ingerido por autodetect mas **descartado no staging** — está "de graça" parado no raw.
- **Recomendação:** aprovar um piloto dbt-mart-first (`int_futebol_fantasy_scouts` + `fact_fixture_player_fantasy`), com os pesos num **seed** versionado; decidir o *ruleset* (recomendado: **ruleset próprio SmartBetting** alinhado ao dado, usando Cartola como benchmark). Esforço estimado: **2–4 dias** de analytics-engineering, **zero** nova ingestão.

---

## 1. O que é "fantasy points" (e por que não é um endpoint)

*Fantasy points* é um **placar derivado**: para cada jogador num jogo, você conta eventos (gol, assistência, desarme, cartão…), multiplica cada um por um **peso** definido pela regra do jogo, e soma. O placar depende da **posição** do jogador (zagueiro ganha por não sofrer gol; goleiro ganha por defesa; atacante ganha por gol).

```
fantasy_points(jogador, jogo) = Σ_scout  contagem(scout) × peso(scout, posição)
```

A API só fornece as **contagens**. Os **pesos** são regra de produto (Cartola FC, FPL, DraftKings, ou a sua própria). Por isso nenhuma API esportiva "entrega fantasy do futebol pronto" de forma genérica — não existe um fantasy canônico do futebol como existe na NBA.

**Inventário da API-Football v3 (confirmado) — não há endpoint de fantasy:**

```
timezone · countries · leagues · seasons · venues · standings
fixtures · fixtures/rounds · fixtures/headtohead · fixtures/statistics
fixtures/events · fixtures/lineups · fixtures/players
teams · teams/statistics · injuries · sidelined · predictions · coachs
players · players/squads · players/profiles · players/topscorers · players/topassists · transfers · trophies
odds · odds/live · odds/bookmakers · odds/bets · odds/mapping
```

Nenhum `/fantasy`. (Nosso pipeline já integra 13 desses endpoints — ver Apêndice A.)

---

## 2. Precedente NBA — a balldontlie **já entrega** `nba_fantasy_pts`

Isto é o oposto do futebol e vale como referência forte para a proposta: **na NBA o fantasy point já vem calculado da API.**

### 2.1 Onde está
- **Endpoint:** `season_averages` da balldontlie, com `category=general`, `type=base` (o `SeasonAveragesExtractor` roda com esses defaults — `data-engineering/src/extractors/season_averages_extractor.py:12`).
- **External table:** `smartbetting-dados.nba.raw_season_averages_general_base` (criada em `data-engineering/scripts/sql/create_external_tables.sql:39`).
- **Campo:** `stats.nba_fantasy_pts` (FLOAT64). Junto vêm `stats.dd2` (duplo-duplos na temporada, INT64) e `stats.td3` (triplo-duplos, INT64), além de `nba_fantasy_pts_rank` (ranking do jogador na liga).

> ⚠️ **Por que ninguém "viu" esse campo no código:** a external table é `format="JSON"` com **autodetect** (sem schema explícito). O objeto `stats` é dinâmico — no OpenAPI da balldontlie ele é tipado como `additionalProperties: true`, ou seja, **os nomes dos campos não aparecem na spec nem em nenhum arquivo do repo**. O `nba_fantasy_pts` existe apenas **no dado** (e no schema que o BigQuery inferiu). Por isso um `grep fantasy` no código retorna zero, mesmo o campo estando lá.

### 2.2 A fórmula (NBA.com oficial — verificada no nosso dado)
`season_averages/general/base` espelha a tabela *Base* do NBA.com (`leaguedashplayerstats`), cujo `NBA_FANTASY_PTS` usa:

```
nba_fantasy_pts = PTS + 1.2·REB + 1.5·AST + 3·STL + 3·BLK − 1·TOV
```

Validação contra `raw_season_averages_general_base` (temporada 2024-25, Jokić):
`27.7 + 1.2×12.9 + 1.5×10.7 + 3×1.4 + 3×0.8 − 1×3.7 = 62.1` → bate exatamente com `stats.nba_fantasy_pts = 62.1`. ✔️

Amostra real (top-8 da liga por `nba_fantasy_pts`, 2024-25, do nosso BigQuery):

| Jogador | fantasy_pts | PTS | REB | AST | STL | BLK | TOV |
|---|--:|--:|--:|--:|--:|--:|--:|
| Nikola Jokić | 62.1 | 27.7 | 12.9 | 10.7 | 1.4 | 0.8 | 3.7 |
| Luka Dončić | 57.7 | 33.5 | 7.7 | 8.3 | 1.6 | 0.5 | 4.0 |
| Victor Wembanyama | 53.4 | 25.0 | 11.5 | 3.1 | 1.0 | 3.1 | 2.4 |
| Shai Gilgeous-Alexander | 50.4 | 31.1 | 4.3 | 6.6 | 1.4 | 0.8 | 2.2 |
| Giannis Antetokounmpo | 49.1 | 27.6 | 9.8 | 5.4 | 0.9 | 0.7 | 3.2 |

> Obs.: esse `nba_fantasy_pts` é **média da temporada por jogo** (não por partida). O endpoint per-jogo (`/stats`) **não** traz fantasy — para fantasy por jogo na NBA, basta aplicar a mesma fórmula sobre a linha de boxscore.

### 2.3 Status no nosso pipeline (oportunidade parada)
- **Ingerido?** Sim — está no raw (`raw_season_averages_general_base.stats.nba_fantasy_pts`).
- **Usado?** **Não.** O staging `stg_season_averages_general_base` seleciona `points/rebounds/assists/...` e até `double_doubles`/`triple_doubles`, mas **não** carrega `nba_fantasy_pts`. Ele morre no raw.
- **Para ativar:** 1 linha no staging (`CAST(stat.nba_fantasy_pts AS FLOAT64) AS nba_fantasy_points`) e propagar ao mart. Custo ~zero.

### 2.4 Lições que a NBA dá para o futebol
1. **Fantasy é derivável de boxscore** — exatamente o que faremos no futebol com `/fixtures/players`.
2. **NBA é o caso fácil** (1 fórmula padronizada, sem dependência de posição, todos os ingredientes num lugar). **Futebol é o caso difícil** (pesos dependem de posição, ~2 scouts faltam) — a proposta precisa tratar isso explicitamente.
3. **Já temos cultura de "score por jogador mart-first"** — o `dim_daily_opportunities` (NBA) calcula score 0-100 de confiança de aposta com a mesma filosofia de camadas. O fantasy de futebol é o mesmo padrão, outro objetivo.

---

## 3. Futebol — a matéria-prima que já temos

Fonte: `/fixtures/players` → `fact_fixture_player_stats` (projeto `dbt_futebol`, dataset `futebol`). Grão: **1 linha por `(fixture_id, player_id)`**, ~22-30 linhas por jogo, dedup *latest-wins* por `loaded_at`, só jogos finalizados.

Colunas relevantes para fantasy (todas já existentes, tipadas):

| Categoria | Colunas em `fact_fixture_player_stats` |
|---|---|
| Identificação | `fixture_id`, `player_id`, `player_name`, `team_id`, `team_side` (`home`/`away`), `position` (`G`/`D`/`M`/`F`), `date_utc`, `competition`, `season` |
| Participação | `minutes`, `rating` (já castado p/ FLOAT64), `is_captain`, `is_substitute`, `shirt_number` |
| Gols/finalização | `goals_total`, `assists`, `shots_total`, `shots_on`, `offsides` |
| Goleiro | `goals_conceded`, `saves`, `penalty_saved` |
| Passe | `passes_total`, `passes_key`, `passes_accuracy` |
| Defesa/duelo | `tackles_total`, `tackles_blocks`, `interceptions`, `duels_total`, `duels_won`, `dribbles_attempts`, `dribbles_success`, `dribbles_past` |
| Disciplina | `fouls_drawn`, `fouls_committed`, `yellow_cards`, `red_cards` |
| Pênaltis | `penalty_won`, `penalty_committed`, `penalty_scored`, `penalty_missed` |

Para *clean sheet*/gols sofridos pelo time há duas vias já joináveis: `goals_conceded` (direto, ótimo p/ goleiro) e o placar `goals_home`/`goals_away` de `fact_fixtures` (via `fixture_id` + `team_side`, para zagueiros).

---

## 4. Como calcular — método + mapeamento (benchmark: Cartola FC)

Usamos o Cartola FC como referência por ser o fantasy de futebol mais conhecido no Brasil. A tabela oficial de pontuação (confira a da temporada vigente antes de fixar pesos):

| Scout (Cartola) | Peso | Coluna `/fixtures/players` | Cobertura |
|---|--:|---|---|
| **G** — Gol | +8,0 | `goals_total` | ✅ direto |
| **A** — Assistência | +5,0 | `assists` | ✅ direto¹ |
| **DS** — Desarme | +1,2 | `tackles_total` | ✅ direto |
| **FS** — Falta sofrida | +0,5 | `fouls_drawn` | ✅ direto |
| **FC** — Falta cometida | −0,3 | `fouls_committed` | ✅ direto |
| **CA** — Cartão amarelo | −1,0 | `yellow_cards` | ✅ direto |
| **CV** — Cartão vermelho | −3,0 | `red_cards` | ✅ direto |
| **I** — Impedimento | −0,1 | `offsides` | ✅ direto |
| **PS** — Pênalti sofrido | +1,0 | `penalty_won` | ✅ direto |
| **PC** — Pênalti cometido | −1,0 | `penalty_committed` | ✅ direto |
| **PP** — Pênalti perdido | −4,0 | `penalty_missed` | ✅ direto |
| **GS** — Gol sofrido *(GOL)* | −1,0 | `goals_conceded` | ✅ direto (goleiro) |
| **DE** — Defesa difícil *(GOL)* | +1,0 | `saves` | 🟡 aprox² |
| **DP** — Defesa de pênalti *(GOL)* | +7,0 | `penalty_saved` | ✅ direto (goleiro) |
| **SG** — Jogo sem sofrer gol *(GOL/ZAG/LAT)* | +5,0 | derivado: `position ∈ {G,D}` + `minutes>0` + time sofreu 0 gols | ✅ derivável |
| **FD** — Finalização defendida | +1,2 | `shots_on − goals_total` | 🟡 aprox³ |
| **FF** — Finalização para fora | +0,8 | `shots_total − shots_on` | 🟡 aprox³ |
| **PE** — Passe incompleto | −0,1 | `passes_total − round(passes_total × passes_accuracy/100)` | 🟡 aprox⁴ |
| **GC** — Gol contra | −3,0 | **não está em `/fixtures/players`** → `/fixtures/events` (`type='Goal'`, `detail='Own Goal'`) | 🟠 outro endpoint⁵ |
| **FT** — Finalização na trave | +3,0 | **não existe na API** | 🔴 indisponível |

¹ A definição de assistência da API (`goals.assists`) é próxima, mas não idêntica, à do Cartola (último passe). Divergências pontuais são esperadas.
² A API só conta `saves` (defesas), sem distinguir "difícil". Mapear `saves → DE` trata toda defesa como difícil (superestima). Alternativa: usar um peso médio menor.
³ `shots_on` inclui os gols; por isso `FD ≈ shots_on − goals_total`. São aproximações de scout, não valores oficiais Cartola.
⁴ Reconstruído da taxa de acerto (`passes_accuracy` %). Aproximação.
⁵ `GC` exige join em `fact_fixture_events` (já ingerimos `/fixtures/events`). Confirmar nomes de coluna do fato antes de codar.

**Resultado:** **15 dos 20 scouts saem direto** das colunas que já temos; 4 são aproximações razoáveis; **1 (FT) é impossível** com a API atual; **1 (GC)** exige um join num endpoint que já ingerimos. Nenhuma nova ingestão é necessária.

---

## 5. Arquitetura proposta (dbt — sem nova ingestão)

Reaproveita 100% o pipeline existente. Duas camadas novas em `dbt_futebol`, seguindo a convenção do projeto (`int_futebol_*` → `fact_*`), mais um **seed** de pesos para tunar sem deploy.

```
fact_fixture_player_stats ─┐
fact_fixtures (placar) ─────┼─→ int_futebol_fantasy_scouts ─→ fact_fixture_player_fantasy ─→ (agg) mart_futebol_fantasy_rodada
fact_fixture_events (GC) ──┘            (normaliza scouts)        (aplica pesos do seed)         (ranking por rodada/time)
                                                ▲
                          seed_fantasy_pesos.csv (scout, peso, posicao_aplicavel)
```

### 5.1 `int_futebol_fantasy_scouts.sql` (normaliza os scouts por jogador-jogo)

```sql
with stats as (
    select * from {{ ref('fact_fixture_player_stats') }}
),
fixtures as (
    select fixture_id, goals_home, goals_away from {{ ref('fact_fixtures') }}
),
base as (
    select
        s.fixture_id, s.date_utc, s.competition, s.season,
        s.team_id, s.team_side, s.player_id, s.player_name,
        s.position, s.minutes, s.rating,

        -- gols sofridos pelo TIME do jogador (para SG / clean sheet de zagueiro)
        case s.team_side when 'home' then f.goals_away
                         when 'away' then f.goals_home end as team_goals_conceded,

        -- scouts diretos (1:1 com colunas existentes)
        s.goals_total       as sc_g,
        s.assists           as sc_a,
        s.tackles_total     as sc_ds,
        s.fouls_drawn       as sc_fs,
        s.fouls_committed   as sc_fc,
        s.yellow_cards      as sc_ca,
        s.red_cards         as sc_cv,
        s.offsides          as sc_i,
        s.penalty_won       as sc_ps,
        s.penalty_committed as sc_pc,
        s.penalty_missed    as sc_pp,
        s.saves             as sc_de,   -- pontua só p/ goleiro
        s.penalty_saved     as sc_dp,   -- pontua só p/ goleiro
        s.goals_conceded    as sc_gs,   -- pontua só p/ goleiro

        -- scouts derivados (aproximações — ver §4)
        greatest(s.shots_on - s.goals_total, 0)                                     as sc_fd,
        greatest(s.shots_total - s.shots_on, 0)                                     as sc_ff,
        greatest(s.passes_total
                 - cast(round(s.passes_total * s.passes_accuracy / 100.0) as int64), 0) as sc_pe
    from stats s
    left join fixtures f using (fixture_id)
)
select
    *,
    -- SG (jogo sem sofrer gol): só G/D que entraram e cujo time não sofreu gol
    case when position in ('G','D') and minutes > 0 and team_goals_conceded = 0
         then 1 else 0 end as sc_sg
from base
-- GC (gol contra): LEFT JOIN opcional em fact_fixture_events (type='Goal' AND detail='Own Goal')
-- FT (finalização na trave): indisponível na API → não modelado
```

### 5.2 `fact_fixture_player_fantasy.sql` (aplica os pesos)

```sql
{{ config(materialized='table',
          partition_by={'field': 'date_utc', 'data_type': 'date'},
          cluster_by=['fixture_id', 'player_id']) }}

with sc as ( select * from {{ ref('int_futebol_fantasy_scouts') }} )
select
    fixture_id, date_utc, competition, season,
    team_id, team_side, player_id, player_name, position, minutes, rating,

    round(
          sc_g  *  8.0
        + sc_a  *  5.0
        + sc_ds *  1.2
        + sc_fs *  0.5
        + sc_fc * -0.3
        + sc_ca * -1.0
        + sc_cv * -3.0
        + sc_i  * -0.1
        + sc_ps *  1.0
        + sc_pc * -1.0
        + sc_pp * -4.0
        + sc_fd *  1.2
        + sc_ff *  0.8
        + sc_pe * -0.1
        + sc_sg *  5.0
        -- exclusivos de goleiro
        + case when position = 'G'
               then sc_de * 1.0 + sc_dp * 7.0 + sc_gs * -1.0
               else 0 end
    , 2) as fantasy_points_cartola
from sc
```

> **Produção:** extrair os literais de peso para `seed_fantasy_pesos.csv` (colunas `scout, peso, posicao`) e cruzar via `{{ ref('seed_fantasy_pesos') }}` — assim o time tuna pesos/temporada sem mexer no modelo. O bloco inline acima é só para leitura.

### 5.3 Agregações (opcional)
- `mart_futebol_fantasy_rodada` — soma por jogador por rodada/temporada → ranking, "seleção da rodada", forma recente.
- Serve tanto **produto** (um fantasy próprio) quanto **feature de modelo** (fantasy como proxy de forma/qualidade do jogador no Motor de Score).

---

## 6. Opções de *ruleset* (decisão do time)

| Critério | A) Replicar **Cartola FC** | B) Estilo **FPL** | C) **Ruleset próprio** (recomendado) |
|---|---|---|---|
| Familiaridade do público BR | ★★★ | ★ | ★★ |
| Aderência ao dado disponível | 🟡 (faltam FT; GC via events; 3 aprox.) | ★★ (mapeia limpo; só "bônus BPS" falta) | ★★★ (desenhado só com campos limpos) |
| Esforço | Médio | Baixo | Baixo |
| Risco de "clonar" produto de terceiro | 🟠 sim | 🟠 sim | ✅ não |
| Controle/diferenciação | Baixo | Baixo | Alto |

- **A — Cartola:** ótimo como *benchmark* e para validar contra um placar conhecido, mas amarra a um produto de terceiro e herda 2 scouts problemáticos.
- **B — FPL (Fantasy Premier League):** mapeamento mais limpo (pontos por aparência ≥60min, gol por posição, *clean sheet*, defesas, cartões, pênaltis) — só o "bônus BPS" é proprietário. Bom se o público for internacional.
- **C — Próprio (recomendado):** pesos definidos por nós, usando **apenas campos limpos** de `/fixtures/players` (sem FT/aprox.), calibrados para o nosso objetivo (engajamento e/ou sinal preditivo). Usar Cartola/FPL como referência de magnitude. Zero risco jurídico, máxima diferenciação.

---

## 7. Lacunas, riscos e decisões em aberto

1. **FT (finalização na trave)** não existe na API-Football → omitir (impacto pequeno; scout raro).
2. **GC (gol contra)** exige join em `/fixtures/events` (já ingerido) — confirmar schema de `fact_fixture_events`.
3. **DE/FD/FF/PE são aproximações** — alinhar com o time se entram, e com que peso, ou se o ruleset próprio (C) simplesmente não usa scouts aproximados.
4. **`position` é grosseira** (`G`/`D`/`M`/`F`): Cartola separa LAT de ZAG e tem TEC (técnico) — não temos LAT vs ZAG nem técnico. O bônus SG (que no Cartola vale p/ GOL/ZAG/LAT) usaríamos para `position ∈ {G, D}`.
5. **Definição de assistência** difere levemente da do Cartola.
6. **Cobertura por liga:** mesma do `/fixtures/players` atual (Brasileirão + competições já integradas). Expandir liga = config de ingestão, não muda o fantasy.
7. **Granularidade:** já temos por jogo (`fact_fixture_player_stats`); ao vivo/parcial exigiria poll de `/fixtures/players` durante a partida (fora do escopo deste piloto).

---

## 8. Esforço e próximos passos

| # | Entrega | Camada | Esforço |
|---|---|---|---|
| S1 | Ativar `nba_fantasy_pts` no staging/mart NBA (quick win, valida o conceito ponta-a-ponta) | dbt_nba | ~2h |
| S2 | Decidir *ruleset* (§6) e fixar tabela de pesos → `seed_fantasy_pesos.csv` | produto + AE | ~0,5 dia |
| S3 | `int_futebol_fantasy_scouts` + `fact_fixture_player_fantasy` | dbt_futebol | ~1 dia |
| S4 | Join de GC (`/fixtures/events`) + testes dbt (grão, ranges, não-nulo) | dbt_futebol | ~0,5 dia |
| S5 | `mart_futebol_fantasy_rodada` (ranking/seleção da rodada) + validação vs Cartola real | dbt_futebol | ~1 dia |

**Total:** ~2–4 dias de analytics-engineering. **Nova ingestão: nenhuma.** Tudo roda sobre tabelas que já existem.

---

## Apêndice A — Endpoints já integrados

**API-Football v3 (futebol) — 13 endpoints** (`data-engineering/src/clients/api_football_client.py`):
`/leagues`, `/teams`, `/teams/statistics`, `/standings`, `/injuries`, `/players`, `/fixtures`, `/fixtures/statistics`, `/fixtures/events`, `/fixtures/lineups`, **`/fixtures/players`** ⭐, `/odds`, `/predictions`. Plano **Pro** (7.500 req/dia). Sem endpoint de fantasy.

**balldontlie (NBA)** (`data-engineering/src/clients/balldontlie_client.py`):
`games`, `stats`, `stats/advanced`, **`season_averages`** ⭐ (entrega `nba_fantasy_pts`), `team_season_averages`, `players/active`, `player_injuries`, `standings`, `odds`, `odds/player_props`.

## Apêndice B — Fórmulas NBA de referência

| Stat | NBA.com (`nba_fantasy_pts`) / FanDuel | DraftKings |
|---|--:|--:|
| Ponto | 1,0 | 1,0 |
| Rebote | 1,2 | 1,25 |
| Assistência | 1,5 | 1,5 |
| Roubo | 3,0 | 2,0 |
| Toco | 3,0 | 2,0 |
| Turnover | −1,0 | −0,5 |
| Cesta de 3 (extra) | — | +0,5 |
| Duplo-duplo (`dd2`) | — | +1,5 |
| Triplo-duplo (`td3`) | — | +3,0 |

`nba_fantasy_pts` da balldontlie usa a coluna NBA.com (= pesos FanDuel). DK exigiria recálculo (temos `dd2`/`td3` no raw e os ingredientes no `/stats`).

## Apêndice C — Fontes

- API-Football v3 — documentação: https://api-sports.io/documentation/football/v3
- balldontlie — OpenAPI (NBA): https://www.balldontlie.io/openapi/nba.yml
- Cartola FC — pontuação dos scouts: https://www.cartolafcbrasil.com.br/tutoriais/7/como-funciona-o-sistema-de-pontuacao-do-cartola-fc
- DraftKings — regras NBA: https://www.draftkings.com/help/rules/4/113
- Evidência interna: `raw_season_averages_general_base.stats.nba_fantasy_pts` (BigQuery `smartbetting-dados.nba`), validado 2026-06-30.
