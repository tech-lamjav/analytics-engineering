# O contrato de serving: quem lê as tabelas sincronizadas, e com que suposição de grão

**Levantado em 2026-08-10, lendo as funções do Postgres PRD vivo** (`pg_get_functiondef`), não o
`prop-play-predictor/docs/futebol-prod-deploy.sql` — aquele arquivo não é migration, é registro, e
já ficou obsoleto antes.

## Por que este documento existe

O sync BQ→Postgres tem uma verificação de esquema (`check_schema_parity`) que responde uma
pergunta só: **o sync sobrevive?** Ele compara coluna a coluna e aborta as 21 tabelas se qualquer
uma divergir.

Ele não responde a pergunta que quebra o produto: **os leitores sobrevivem?** As RPCs
`public.get_futebol_*` leem essas tabelas e várias assumem o GRÃO delas. Mudar o grão de uma
tabela sincronizada **passa o parity inteiro e ainda entrega dado errado ao app.**

Isso já custou duas vezes:

| Quando | O quê |
|---|---|
| 2026-08-07 | A janela `daily` entra na coleta. O desempate de janela das duas RPCs de odds não a conhece, e `daily` empata com `t24h`. Ninguém notou por 3 dias |
| 2026-08-10 | A #37 põe a janela no grão do de-vig. `get_futebol_fixture_value` não tem desempate de janela e passa a escolher arbitrariamente os avisos de penalidade. Chegou a produção e foi revertido no mesmo dia |

Duas specs desta fila declararam esta camada verificada quando não estava: a **C1** afirma "a
aplicação não os consulta" (falso, ver abaixo) e a **C5** não a mencionou.

## A matriz

20 das 22 tabelas da allowlist são lidas por alguma RPC. **`dim_leagues` e
`fact_value_opportunities_hist` não são lidas por nenhuma** — mudança de grão nelas não alcança o
app (o `hist` é consumido só por análise).

⚠️ **A segunda metade dessa frase morre com a ADR 0009.** Quando o board passar a expurgar jogo
encerrado, o passado do app passa a ser servido pelo `hist`, em leitura point-in-time no apito —
e ele deixa de ser tabela de análise para virar fonte de duas telas.

| Tabela sincronizada | RPCs que leem | Suposição de grão | Estado |
|---|---|---|---|
| `fact_fixtures` | 9 (incl. `_futebol_team_form`) | 1 linha por `fixture_id` | ✅ |
| `dim_teams` | 4 | `get_futebol_teams` faz `distinct on (team_id)` **sem desempate** | ✅ inofensivo — a tabela é única por `team_id` (591/591 medido) |
| `fact_odds_snapshot` | 2 | `distinct on (…, bookmaker_name)` com desempate por janela | ⛔ **DEFEITO VIVO** — ver abaixo |
| `fact_value_opportunities` | 2 | 1 linha por (fixture, market, outcome, line) | ✅ hoje; ⚠️ #40/#41/A1 mexem nas COLUNAS |
| `int_futebol_odds_devig` | 1 (`get_futebol_fixture_value`) | `distinct on (fixture_id, outcome_side, line_value)` **sem desempate** | ⛔ bloqueia a #37 — e é DEFEITO VIVO por si só (#87): a chave não tem `market_id` nem `janela_usada`, então as 4 flags de penalidade que a RPC remonta saem de uma linha sorteada. Medido em 19/08: 76 das 126 linhas do board com janela diferente da publicada, 34 com as flags contradizendo o `penalidades_globais_pts` da própria linha. A #87 publica as flags no mart para que o CTE possa morrer |
| `fact_fixture_lineups` + `_players` | 1 (`get_futebol_fixture_extras`) | `jsonb_agg` de TODAS as linhas do fixture, sem filtro de fase | ⛔ bloqueia a #38 |
| `fact_injuries_snapshot` | 1 | `distinct on (player_id)` + `order by snapshot_date desc` | ✅ desempate correto e semântico |
| 5 × `int_futebol_premissas_*` | 2 cada | join por (fixture, outcome[, line]) | ✅ hoje; ⚠️ #41 pode adicionar coluna |
| `fact_h2h`, `fact_predictions_api`, `fact_standings_snapshot`, `fact_team_season_stats`, `fact_fixture_stats`, `fact_fixture_events`, `fact_fixture_player_stats` | 1–2 cada | leitura direta, sem suposição de unicidade além da chave natural | ✅ |
| `fact_value_opportunities_hist` | **nenhuma hoje**; passa a ter 1 (`get_futebol_value_history`) | leitura **point-in-time no apito**: 1 linha por `opportunity_key`, a versão viva quando o jogo começou | ⚠️ o grão dele vira **contrato de serving** com o expurgo do board (ADR 0009) |
| `dim_leagues` | **nenhuma** | — | ✅ fora do alcance do app |

## ⛔ Defeito vivo: o desempate de janela das RPCs de odds não conhece a `daily`

`get_futebol_fixture_odds` e `get_futebol_odds_board` escolhem a janela corrente assim:

```sql
case when collection_window = 't15m' then 3
     when collection_window = 't1h'  then 2
     else 1 end
```

**`t24h` e `daily` caem os dois no `else 1` e empatam.** Com empate, o `DISTINCT ON` do Postgres
resolve arbitrariamente — e pode virar entre chamadas, sem nenhuma mudança de dado.

Medido em 2026-08-10 no PRD: **27.066 chaves (fixture, casa, mercado, saída) empatadas, em 25
fixtures** — as que já têm `daily` e `t24h` e ainda não têm `t1h`/`t15m`. Para elas, a tela de odds
e o board de odds podem exibir uma odd de até 7 dias atrás em vez da de 24h.

**Não foi causado pela #37.** Nasceu em 07/08 com `tech-lamjav/data-engineering#34`, quando a
`daily` entrou na coleta e este `CASE` não acompanhou. É o mesmo formato do defeito da #37, três
dias mais velho.

Conserto: acrescentar `when collection_window = 't24h' then 2` deslocando os demais, ou melhor,
derivar a prioridade de um lugar só. No dbt esse lugar já existe — o macro
`futebol_janela_prioridade` — mas ele não atravessa para o Postgres, então aqui é duplicação
inevitável e o que resta é **manter as duas listas juntas na mesma mudança**.

## A regra que vale daqui pra frente

Antes de mudar **grão** ou **colunas** de qualquer tabela da allowlist:

1. `SELECT p.proname, pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE '%futebol%'` — no banco vivo.
2. Procure `distinct on`, `jsonb_agg`/`array_agg`, `limit 1` e joins por subconjunto da chave. São as quatro impressões digitais de "assumo uma linha por chave".
3. **Coluna nova ou removida** → migration no Postgres ANTES do deploy da imagem, senão o parity aborta as 21 tabelas. Coluna que a RPC declara no `RETURNS TABLE` exige `DROP FUNCTION` e recriar (Postgres não faz `CREATE OR REPLACE` mudando assinatura).
4. **Tabela nova** → ignorada pelo sync (a allowlist é explícita), então é livre.

## O que isto diz sobre o trabalho na fila

| Ticket | O que faz | Consequência nesta camada |
|---|---|---|
| **#37** (C5) | Janela no grão do de-vig | Precisa de desempate por `janela_usada` em `get_futebol_fixture_value` |
| **#38** (C1) | Duas fases da escalação coexistem | `get_futebol_fixture_extras` duplicaria cada time e cada jogador; a projeção nem expõe `lineup_phase`. `lineup_phase` **já é coluna** nos dois fatos, então não há drift de esquema — só de grão |
| **#40** (C5b) | Coluna `janela_deteccao` no mart | Coluna nova → migration antes do deploy, em **DUAS** tabelas: `futebol.fact_value_opportunities` e `futebol.fact_value_opportunities_hist` (o snapshot copia a linha inteira, então a coluna chega lá no primeiro `dbt snapshot` e o parity acusa as duas). `ALTER TABLE ... ADD COLUMN janela_deteccao text;` nos dois bancos (dev e prd). Nenhuma RPC muda: `get_futebol_value_board` declara o `RETURNS TABLE` coluna a coluna e não lista a nova — o board só passa a exibi-la quando o front pedir |
| **#41** (C3b) | Contador de premissas sem dado | Coluna nova → migration antes do deploy |
| **#87** | Quatro flags de penalidade (`pen_odd_outlier`, `pen_poucas_casas`, `pen_odd_longshot`, `pen_odd_juice`) como `BOOLEAN` no mart | Colunas novas → mesmo caminho da #40: `ALTER TABLE ... ADD COLUMN <flag> boolean;` nas **duas** tabelas (`fact_value_opportunities` e `_hist`) × **dois** bancos, antes do deploy da imagem. **Nenhuma RPC quebra** — verificado no prd em 19/08: as duas que leem o mart o aliasam como `v` e enumeram coluna a coluna, sem `v.*`. E a #87 é o pré-requisito do conserto do lado do app: só com estas colunas no prd o CTE `d` de `get_futebol_fixture_value` (linha ⛔ da tabela acima) vira leitura direta e morre |
| **A1** | Remove `pts_valor`/`pts_corroboracao`/`penalidades` do mart | Colunas removidas **e** declaradas no `RETURNS TABLE` das duas RPCs → `DROP FUNCTION` + recriar |
| **A7** | Tabela nova de funil | Livre — fora da allowlist |
| **Expurgo do board** (ADR 0009) | Mart para de emitir linha de jogo encerrado; passado vem do `hist` | **Nenhuma coluna muda** — o filtro é por join com `fact_fixtures`, de propósito. O risco aqui é o outro: o parity passa, as RPCs devolvem 200 e o Histórico esvazia em silêncio. Por isso a RPC nova (`get_futebol_value_history`) e o front vão **antes** do expurgo, e `get_futebol_value_board` **não é alterada**. `get_futebol_fixture_value` muda só o corpo (assinatura idêntica → `CREATE OR REPLACE`) |
