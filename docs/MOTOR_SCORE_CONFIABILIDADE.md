# Motor de Score de Confiabilidade — value bet (futebol)

Documento de contexto e plano para a **camada de produto** do futebol: um motor que, para cada **jogo × mercado × resultado possível**, calcula um **Score de Confiabilidade (0–100)** dizendo se aquela aposta é uma oportunidade de valor confiável. O front mostra as oportunidades ordenadas por Score e explica **por quê** cada uma faz sentido.

Sobe **em cima** do pipeline de ingestão já concluído (`data-engineering/docs/PIPELINE_APIFOOTBALL.md` — 15 tabelas raw/mart em `smartbetting-dados.futebol`). Aqui não há ingestão nova: o motor é **regras e contas** (não modelo estatístico) sobre os marts que já existem.

> **Status**: planejamento. A fórmula, o gate, as faixas e a corroboração/penalidades estão **fechados** (abaixo). As **premissas por mercado** (PTS_PREMISSAS) **agora também estão especificadas**: o playbook `futebol-metodologia-premissas.md` está no repo (em `analytics-engineering/docs/`, auditado 2026-06-18) e está transcrito na **seção 12** (1X2, O/U, Handicap, BTTS, Dupla chance — com pesos, thresholds, gates e penalidades por mercado); a fundamentação (benchmark) está destilada na **seção 13**. O que falta em S1–S5 passa a ser **implementação em dbt**, não definição. Este doc é **vivo**: cada subtarefa preenche sua linha na tabela da seção 8 quando implementada.

---

## 0. Docs de referência (source of truth da metodologia)

| Doc | Conteúdo | Situação |
|---|---|---|
| `analytics-engineering/docs/futebol-metodologia-premissas.md` | Playbook completo — **premissas + pesos + thresholds + gates/penalidades + fontes de dado por mercado** | ✅ **no repo** (auditado 2026-06-18) — transcrito na §12 |
| `analytics-engineering/docs/futebol-metodologia-benchmark.md` | Fundamentação (pesquisa de mercado/academia, variáveis ranqueadas, validação) | ✅ **no repo** — destilado na §13 |

> ✅ **Pendência resolvida**: os dois docs **agora vivem em `analytics-engineering/docs/`** (movidos do front em 2026-06-22), co-locados com o dbt que os implementa. A **§12/§13 transcrevem/destilam** o conteúdo para leitura rápida, mas a **fonte autoritativa são os próprios `.md` aqui** (ao calibrar pesos, atualizar o `.md` e re-sincronizar a §12). Os pesos/thresholds são **ponto de partida** (a calibrar com RPS/calibração/CLV — §13).
>
> ⚠️ **Cuidado com os "✅" do playbook**: ele referencia `src/utils/futebol-value.ts` (Pilar A) e `futebol-tendencias.ts` (Pilar B) e marca "devig Pinnacle ✅" — mas **esses arquivos TS não existem** (verificado 2026-06-18) e **não há nenhuma implementação de de-vig** (nem TS no front, nem SQL no dbt; `dbt_futebol` ainda nem tem pasta `intermediate/`). O ✅ do playbook significa "o **dado bruto** pra calcular devig está em `fact_odds_snapshot`", não que o devig esteja pronto. **A Fase 0 (`int_futebol_odds_devig`) continua de pé.**

---

## 1. Contexto e objetivo

- **Produto**: value betting sério no **Brasileirão Série A** (dado rico) + complemento **Copa do Mundo 2026** (dado magro).
- **O que entrega**: para um `fixture_id`, por mercado, a lista de `outcomes` com **Score + faixa + evidências (o "por quê") + avisos (penalidades)**.
- **Natureza**: **regras determinísticas** — cada "premissa" é um sinal booleano (V/F) calculado direto da base; cada premissa tem peso em pontos; o Score é a soma ponderada. **Não** é ML/estatística. Logo, **cabe naturalmente em SQL/dbt** (ver seção 6). É a **camada de valor/regras ("Pilar A")**; um modelo estatístico próprio (Dixon-Coles + xG = "Pilar B") fica **fora deste escopo** (ver §13).
- **Precedente direto no repo**: o NBA já faz isto em `dbt_nba/models/marts/dim_daily_opportunities.sql` — mart que soma componentes ponderados → Score 0–100 → faixas `ALTA/MEDIA/BAIXA CONFIANCA` → gate `WHERE score >= 40`. O motor de futebol é o **análogo** (mesma arquitetura, mercados de futebol).

---

## 2. Fórmula do Score (igual para todos os mercados)

```
Score = clamp( PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES , 0 , 100 )
```

### PTS_VALOR (0–30) — tamanho do valor (edge)

```
edge = melhor_odd × prob_justa_fechamento − 1
prob_justa_fechamento = de-vig da odd de FECHAMENTO da Pinnacle
                        (janela t15m → cai p/ t1h → t24h se não houver)
PTS_VALOR = round( min(edge%, 6) / 6 × 30 )      # 6%+ = 30; 3% = 15; 1% = 5
```

- `melhor_odd` = maior `odd_decimal` entre as casas para aquele outcome, na janela de avaliação.
- `prob_justa_fechamento` = de-vig **market-aware** das odds da **Pinnacle** (`bookmaker_id = 4`): normaliza o overround sobre o **conjunto completo de outcomes** daquele mercado×fixture (3-way em 1X2; 2-way em O/U, BTTS, Dupla chance; par por linha em Handicap asiático).
- ⚠️ **DEPENDÊNCIA DURA — de-vig ainda NÃO existe.** O kickoff diz "reaproveita o devig da task *Pipeline: Integrar odds de mercado e EV%*", mas essa task **não foi implementada** (`analytics-engineering/docs/analise_player_props.md` lista EV% como "⚠️ Falta implementar — requer algoritmo de devig"). **Sem de-vig não há `prob_justa_fechamento` → não há PTS_VALOR → não há gate.** Por isso o de-vig/EV é a **Fase 0** (seção 7): construído aqui como modelo compartilhado `int_futebol_odds_devig`, a menos que o usuário queira fazê-lo na task de odds/EV separada. *(Confirmado 2026-06-18: não existe de-vig pronto em lugar nenhum — nem SQL no dbt, nem TS no front.)*

### PTS_PREMISSAS (0–55) — contexto do mercado

Soma dos pesos das premissas de contexto **que dispararam** (teto 55). Cada premissa = 1 booleano calculável dos marts (seção 5). **Especificadas por mercado na §12** (transcrição do playbook): 1X2, O/U (Over/Under espelhados), Handicap (Favorito/Azarão), BTTS (Sim/Não), Dupla chance. A soma bruta dos pesos por lado vai de ~28 (BTTS Não) a 56 (Over — o único que encosta no teto 55; os demais ficam abaixo, então o clamp raramente morde). O clamp `LEAST(soma, 55)` está implementado no `int_futebol_premissas_ou` (S2) — primeiro modelo de premissas que pode atingir 56 (o 1X2 maxa em 51 e não precisa). Cada premissa que dispara vira um **bullet de evidência** no front (ordenado por peso).

### PTS_CORROBORACAO (0–15) — confirmação externa (igual p/ todos)

| Sinal | Pontos | Definição | Fonte |
|---|---|---|---|
| `modelo_api_concorda` | **+7** | o modelo da própria API (`/predictions`) aponta o **mesmo lado/tendência** do outcome | `fact_predictions_api` |
| `linha_sharp_confirma` | **+8** | a odd da **Pinnacle** do lado apostado **caiu** de `t24h → t15m` (mercado migrou pro nosso lado) | `fact_odds_snapshot` (Pinnacle, 2 janelas) |

### PENALIDADES globais (subtraem — iguais p/ todos os mercados)

| Penalidade | Pontos | Gatilho | Fonte |
|---|---|---|---|
| `odd_outlier` | **−30** | `melhor_odd ≥ 1,10 × média_das_casas` (linha suspeita / 1 casa mole) | `fact_odds_snapshot` |
| `poucas_casas` | **−12** | `n_casas < 4` | `fact_odds_snapshot` |
| `odd_longshot` | **−15** | `melhor_odd > 4,5` | `fact_odds_snapshot` |
| `odd_juice` | **−10** | `melhor_odd < 1,40` | `fact_odds_snapshot` |

### Penalidades específicas por mercado (somam às globais — detalhe na §12)

| Mercado | Penalidade | Pts | Gatilho |
|---|---|---|---|
| 1X2 | `pick_empate` | **−10** | outcome = empate (saída mais difícil de bater — §13) |
| 1X2 | `desfalque_proprio` | **−15** | S sem titular importante |
| O/U | `linha_extrema` | **−10** | `L ≤ 0,5` ou `L ≥ 4,5` (odd vira juice/longshot) |
| Handicap | `handicap_alto` | **−12** | `mód(H) ≥ 2,5` (raramente confiável) |
| Dupla chance | `odd_muito_baixa` | **−10** | `melhor_odd < 1,20` |

### Gate (eliminatório)

> Regra geral: só calcula Score se **`edge > 0` E `n_casas ≥ 3`**. Senão **não é oportunidade** (não entra no board). Espelha o `WHERE score >= 40 AND line_value IS NOT NULL` do `dim_daily_opportunities`.
>
> ⚠️ **Exceção — Dupla chance** (odds estruturalmente baixas): aceitar `melhor_odd ≥ 1,25` e **não** aplicar `odd_juice` (<1,40); a única penalidade de odd baixa nesse mercado é `odd_muito_baixa` (<1,20). Ou seja: **gate/penalidades não são 100% uniformes** — a Dupla chance tem regra própria (implementar como ramo no modelo).

### Faixas de confiabilidade

| Faixa | Score | Tratamento no front |
|---|---|---|
| **Alta** | ≥ 60 | oportunidade em destaque (hero/board) |
| **Média** | 40–59 | monitorada (aparece sem destaque) |
| **Baixa** | < 40 | **não** sinaliza como oportunidade |

> Nota: as faixas do futebol (60 / 40) **diferem** das do NBA (80 / 60 / 40) — o teto efetivo do Score muda porque PTS_PREMISSAS aqui vai a 55. São **ponto de partida**, a recalibrar (seção 10).

---

## 3. Saída esperada (por `fixture_id` × mercado × outcome)

Uma linha por `(fixture_id, market, outcome)` com:

`edge` · `PTS_VALOR` · `PTS_PREMISSAS` · `PTS_CORROBORACAO` · `penalidades` (total subtraído) · `Score` · `faixa` · **lista das premissas que dispararam** (vira o "por quê" no front) · **avisos** (penalidades aplicadas) · `melhor_odd` · `melhor_casa` · `n_casas` · `prob_justa_fechamento` · janela usada.

---

## 4. Regras transversais

- **Degradação graciosa**: dado faltando = premissa **não dispara** (NÃO é erro). Ex.: Copa sem xG → premissas de xG ficam falsas, Score menor (honesto). Implementar como `COALESCE(... , FALSE)` — nunca propagar NULL pro Score.
- **Cobertura por liga** (herdada do pipeline):

| Insumo | Brasileirão (71) | Copa (1) | Implicação |
|---|---|---|---|
| xG / finalizações (`fact_fixture_stats`) | 100% | **magra** | premissas de xG/chutes só pegam forte no Brasileirão |
| `/predictions` (`fact_predictions_api`) | ✅ TRUE | ✅ TRUE | corroboração `modelo_api_concorda` vale nas duas |
| `/injuries` (`fact_injuries_snapshot`) | ✅ TRUE | ❌ **FALSE** | premissas de desfalque **nunca** disparam na Copa (degradação graciosa) |
| `/odds` (`fact_odds_snapshot`) | ✅ TRUE | ✅ TRUE | gate/valor/penalidades valem nas duas |

- **Auditoria de disponibilidade de dado** (do playbook §8, 2026-06-18) — o que **roda já** vs. o que **depende de coleta**:
  - ✅ **Pronto p/ as duas ligas**: `fact_team_season_stats` (gols casa/fora, clean sheet, failed-to-score, forma) · `fact_standings_snapshot` (rank/pontos/forma) · `fact_fixtures` (resultados, últimos 5, margens, descanso) · `fact_h2h` (**949 jogos**) · odds (melhor/média/Pinnacle, janelas, n_casas, line_value).
  - 🟡 **Só Brasileirão (rico)**: `fact_fixture_stats` — xG `expected_goals` **100% preenchido** (2024+2025 completos, 2026 ~177 jogos; **Copa só ~12**) → alimenta `superioridade_xg`, `xg_combinado_alto`/`xg_baixo_combinado`, `ritmo_alto`. Copa pontua só nas premissas baseadas em gols.
  - 🔧 **Gaps = coleta nova (extractors existem)**: **predictions** ✅ resolvido (S6, 2026-06-29 — janela `daily` varre jogos futuros até 14d, date-stampada; deploy pendente) e **injuries** ✅ resolvido (S7, 2026-06-30 — pré-jogo `/injuries?fixture` modo `pregame` + proxy de importância `int_futebol_player_importance`/`int_futebol_desfalques`; deployado). Ver §8.
  - **Limitação estrutural**: odds pré-jogo só 1–14 dias antes, histórico de 7 dias → **sem backfill** de odds antigas; **CLV só acumula pra frente** (t15m). Backtest de calibração/RPS usa resultados históricos (que temos).

---

## 5. Mapeamento premissa/insumo → fonte de dado (BigQuery)

Tudo derivável dos marts `smartbetting-dados.futebol.*` já populados. Colunas reais conferidas no código dbt.

| Componente do Score | Mart(s) fonte | Colunas-chave |
|---|---|---|
| **edge / melhor_odd / n_casas / penalidades / linha_sharp** | `fact_odds_snapshot` | `market_id`, `outcome_side`, `line_value`, `odd_decimal`, `bookmaker_id`(Pinnacle=4), `collection_window` (t24h/t1h/t15m; aliases do playbook: `pin_open`=t24h, `pin_close`=t15m), `fixture_id` |
| **prob_justa_fechamento (de-vig)** | `fact_odds_snapshot` (Pinnacle) | idem ↑ — **modelo de-vig a construir** (`int_futebol_odds_devig`) |
| **modelo_api_concorda** | `fact_predictions_api` | `prob_home/draw/away_pct`, `predicted_winner_*`, `predicted_win_or_draw`, `predicted_under_over`, `advice`, `comparison_*` |
| **Força ataque/defesa, médias casa/fora, clean sheets, failed-to-score** (premissas O/U, BTTS, 1X2, DC) | `fact_team_season_stats` | `goals_for_avg_home/away/total`, `goals_against_avg_*`, `clean_sheet_*`, `failed_to_score_*`, `wins_/draws_/loses_*`, `form` |
| **Forma recente / xG / finalizações** (premissas de momento) | `fact_fixture_stats` | `expected_goals` (xG), `total_shots`, `shots_on_goal`, `ball_possession`, `corner_kicks` (1 linha/time/jogo, `team_side`) |
| **Posição/motivação/contexto de tabela** | `fact_standings_snapshot` | `rank`, `points`, `goals_diff`, `form`, `rank_description` (G4/rebaixamento) |
| **Histórico do confronto** | `fact_h2h` | `h2h_pair_key`, placares (`goals_home/away`, `score_*`) — só FT/AET/PEN |
| **Desfalques + proxy de importância** (S7) | `fact_injuries_snapshot` + `fact_fixture_player_stats` + `fact_fixture_lineups_players` | injuries: `player_id`, `fixture_id`, `injury_type/reason`; importância: minutos/`rating`/`is_starter` agregados por jogador |
| **Eixo do jogo (mando, status, placar, kickoff)** | `fact_fixtures` | `home/away_team_id`, `status_short`, `kickoff_utc`, `competition`, `season` |

Mercados-alvo (de `fact_odds_snapshot`, `market_id`): **1**=Match Winner (1X2) · **5**=Goals O/U · **4**=Asian Handicap · **8**=BTTS · **12**=Double Chance. *(Ingeridos mas fora do escopo inicial: 6=O/U 1ºT, 7=HT/FT, 10=Exact Score.)*

---

## 6. Arquitetura proposta no repo

**Decisão de arquitetura (a confirmar): dbt-mart-first**, espelhando `dim_daily_opportunities` do NBA. Como o motor é 100% regras/contas sobre marts BigQuery, é SQL — não precisa de serviço Python de cálculo. O "serviço que recebe `fixture_id`" vira **leitura** do mart já calculado, filtrada por `fixture_id`.

### 6.1 Camada nova: `intermediate/`

`dbt_futebol/` hoje só tem `staging/` + `marts/` (sem `intermediate/`). O motor **introduz** a camada `int_` (o `dbt_project.yml` já a declara como `+materialized: view`), igual ao NBA.

### 6.2 Grafo de modelos proposto

```
fact_odds_snapshot ─┐
                    ├─► int_futebol_odds_devig      (Fase 0: prob_justa + EV/edge + n_casas + penalidades + linha_sharp)
fact_predictions ───┼─► int_futebol_corroboracao    (modelo_api_concorda + linha_sharp_confirma)
team_season_stats ──┤
fixture_stats ──────┼─► int_futebol_premissas_1x2   (S1)  ┐
standings / h2h ────┤   int_futebol_premissas_ou    (S2)  │  PTS_PREMISSAS por mercado
injuries (+proxy) ──┤   int_futebol_premissas_ah    (S3)  │  (1 booleano por premissa)
fixtures ───────────┘   int_futebol_premissas_btts  (S4)  │
                        int_futebol_premissas_dc    (S5)  ┘
                                   │
                                   ▼
                        fact_value_opportunities    (mart: 1 linha por fixture×market×outcome,
                                                     Score, faixa, evidências[], avisos[]; gate aplicado)
```

- **Granularidade do mart (a confirmar)**: **um mart unificado long** `fact_value_opportunities` com coluna `market` (recomendado — espelha o `fact_odds_snapshot`, que já vem long por outcome; o front filtra por `market`), **vs.** um mart por mercado. Recomendo o unificado.
- **`evidências`/`avisos`**: `ARRAY<STRING>` (premissas que dispararam / penalidades aplicadas) — vira o "por quê" e os avisos no front sem parse.

### 6.3 Serving (o "serviço por `fixture_id`")

- Validação imediata: `dbt show`/query BQ `WHERE fixture_id = ...` no `fact_value_opportunities` (atende o aceite "validável num jogo do Brasileirão").
- Para o app: reusar o caminho **BQ → Supabase Postgres** (hoje **postergado** — ver `PIPELINE_APIFOOTBALL.md` §9.7; ativar quando houver UI consumidora) **ou** FDW, igual ao NBA. Não construir serviço Python de cálculo à parte.

---

## 7. Plano de execução (fases)

| Fase | Escopo | Entrega |
|---|---|---|
| **Fase 0 — Núcleo de valor** | de-vig market-aware da Pinnacle + edge/EV + `n_casas` + penalidades + gate + corroboração (`int_futebol_odds_devig`, `int_futebol_corroboracao`) | PTS_VALOR + PTS_CORROBORACAO + PENALIDADES + gate funcionando, **agnóstico de mercado** |

> ⚠️ **Regra de emissão do de-vig (2026-08-05, spec #22):** o de-vig só emite valor quando o
> **conjunto de saídas** bate exatamente com o declarado por mercado; conjunto incompleto não
> gera estimativa pior, gera ausência de estimativa. A regra e o porquê da comparação exata
> vivem em `dbt_futebol/docs/adr/0002-conjunto-de-saidas-declarado-por-mercado.md` — **não
> copiada aqui de propósito**: cada cópia da regra é mais uma chance de este documento divergir
> de produção, como já divergiu antes.
| **Fase 1 — Premissas por mercado** | S1–S5 (1X2 primeiro = mais rico), 1 modelo `int_` por mercado, conforme §12 | PTS_PREMISSAS por mercado |
| **Fase 2 — Dado/coleta** | S6 (predictions: extractor existe mas só 3 fixtures → **agendar coleta pré-jogo dos fixtures futuros**, 1 call/jogo) + S7 (injuries: só histórico até 31/05 → **coletar pré-jogo** + **proxy de importância**) | corroboração + premissas de desfalque |
| **Fase 3 — Mart de Score** | `fact_value_opportunities` (soma ponderada, clamp, faixa, evidências[], avisos[]) | saída da seção 3 |
| **Fase 4 — Serving + validação** | leitura por `fixture_id`; validar num jogo do Brasileirão (dado rico) | aceite |
| **Fase 5 — Calibração** | **RPS** (principal) + **log-loss** + **curva de calibração** sobre resultados históricos; **CLV** (KPI-rei) quando o `t15m` acumular; benchmark = bater a prob de-vig do **fechamento da Pinnacle** (§13) | pesos/thresholds ajustados; "valor" só exposto após calibrar (senão rotular "estimativa") |

---

## 8. Subtarefas (tabela viva)

Preencher a coluna **Status/Notas** in-place quando cada uma for implementada — igual à tabela das 15 tabelas no `PIPELINE_APIFOOTBALL.md`. Premissas/pesos/penalidades por mercado: **§12**.

| # | Subtarefa | Tipo | `market_id` | Escopo (resumo) | Status |
|---|---|---|---|---|---|
| **S0** | Núcleo de valor (de-vig/EV + penalidades + gate + corroboração) | infra | — | `int_futebol_odds_devig` (de-vig multiplicativo Pinnacle + edge + PTS_VALOR + penalidades globais + linha_sharp) + `int_futebol_corroboracao` (modelo_api_concorda +7 / linha_sharp +8) | ✅ **feito 2026-06-22** (de-vig 1X2 soma 1.0; gate aplicado no mart; 20 testes verdes) |
| **S1** | Premissas — **Resultado (1X2)** | mercado | 1 | **§12.1** — 7 premissas (Σ51) + penalidades `pick_empate`/`desfalque_proprio`; `int_futebol_premissas_1x2` (3 outcomes/fixture; empate fiel ao playbook; desfalque importance-gated via S7) | ✅ **feito 2026-06-22** (validado no Brasileirão fix 1180448: Home pp=47 coerente §12.1; Score ponta-a-ponta no mart `fact_value_opportunities`. Mart hoje só rende Copa — Brasileirão sem odds 1X2 na pausa FIFA; odds são forward-only) |
| **S2** | Premissas — **Gols (Over/Under)** | mercado | 5 | **§12.2** — Over (7, Σ56) + Under (6, Σ52) espelhados; pen. `linha_extrema`; xG só Brasileirão; `int_futebol_premissas_ou` (2 outcomes/linha; universo de linhas = canônicas {1.5,2.5,3.5} ∪ linhas das odds; `historico_over/under` = últimos 5 FT mesma liga; `ritmo_alto` = mediana da liga via APPROX_QUANTILES; movimento de linha = **consenso do mercado**, §10.8) | ✅ **feito 2026-06-23** (validado no Brasileirão: Over satura nas linhas baixas / Under nas altas; `fact_value_opportunities` refatorado p/ **UNION 1X2+O/U** com join por `line_key` STRING e gate `pin_n_outcomes` por ramo (≥3 1X2 / ≥2 O/U); **clamp teto 55 implementado aqui** — só o Over chega a 56; dbt build/test verdes (mart rende 1X2+O/U, O/U com faixa Alta até 85); **deploy**: imagem `dbt-futebol` rebuildada + `gcloud run jobs update --region` + `int_futebol_premissas_ou` adicionada ao `--select` do **`workflow_futebol_odds.yml`** (onde o Motor recalc por janela de odds, sem `+`) e redeploy — execuções `dbt-futebol-fnbj7`/`z8nvc` OK) |
| **S3** | Premissas — **Handicap asiático** | mercado | 4 | **§12.3** — Favorito (5, Σ40) + Azarão (3, Σ30), pareável por `line_value`; pen. `handicap_alto` | ✅ **feito 2026-06-24** — `int_futebol_premissas_ah` (2 outcomes Home/Away por `(fixture, line_value)`; `side_handicap = IF(Home, line, -line)` decide favorito(<0)/azarão(>0)/pick(=0); só o lado certo dispara → Σ40 fav / Σ30 dog; pen. `handicap_alto` −12 em \|line\|≥2,5). **Descoberta-chave**: a API-Football traz `line_value` na **ótica do mandante, IGUAL p/ Home e Away** (`Home -1.5`/`Away -1.5` = par complementar), então o **de-vig da Fase 0 já parea o AH** por `(fixture, market, line_key)` — sem mudança no `int_futebol_odds_devig` (só ajustei a doc-string do warning). Mart com **3º ramo `joined_ah`** (gate Pinnacle ≥2, igual O/U) → UNION 1X2+O/U+AH; accepted_values atualizados. **dbt build/test verdes** (17 OK). **Validado**: Brasileirão fav −1,5 dispara as 5 premissas (40 pts, evidências coerentes: superior na tabela, marca 2,2/cede 0,9 em casa, adv. cede 1,9 fora, 75% mando, jogo importante); azarão dispara `raramente_perde_por_2`/`defesa_fora_solida`/`favorito_irregular`; `handicap_alto` confirmado em \|line\|≥2,5 (Copa). Mart hoje só rende Copa (Brasileirão sem odds AH na pausa FIFA — odds forward-only, igual S1/S2). **⚠️ Reconciliação §12.3**: o bloco "Azarão" do playbook troca rótulos S/O; implementei por **nome/intenção** (`raramente_perde_por_2`+`defesa_fora_solida` = azarão S; `favorito_irregular` = favorito O) — alinhar o `.md` a isto na calibração. **Deploy feito 2026-06-24**: imagem `dbt-futebol` rebuildada (digest `2bdc3e5`) + `gcloud run jobs update --region us-east1` + `int_futebol_premissas_ah` adicionada ao `--select` do `workflow_futebol_odds.yml` e `deploy_workflows.sh workflow-futebol-odds` redeployado (imagem confirmada contendo o modelo + ramo `joined_ah`). |
| **S4** | Premissas — **Ambos marcam (BTTS)** | mercado | 8 | **§12.4** — Sim (4, Σ34) + Não (3, Σ28) | ✅ **feito 2026-06-25** — `int_futebol_premissas_btts` (2 outcomes Yes/No por fixture, **sem line_value**; Sim gated por `outcome='Yes'`, Não por `='No'`; **sem clamp**, Σ34/Σ28 < 55). Convenções herdadas do S2: clean sheet%/failed-to-score% sobre o **total** da temporada, gols por **venue** (mandante casa/visitante fora), `historico_btts/seco` via últimos 5 FT de cada (≥3 ~ 60%). **Descoberta-chave (dados)**: a **Pinnacle NÃO precifica BTTS** (0/44 fixtures; idem HT/FT=7 e Dupla Chance=12 — mercados "recreativos") → sem âncora de de-vig. **Decisão (usuário)**: **de-vig de CONSENSO** (mediana das casas) como fallback na Fase 0 (`int_futebol_odds_devig`), **guardado por COALESCE** (não altera 1X2/O/U/AH) + coluna `valor_fonte` ('pinnacle'\|'consenso') p/ o front rotular "estimativa"; ramo `joined_btts` no mart gateia por `n_outcomes_valor >= 2`. **dbt build/test verdes** (26 OK). **Validado**: Brasileirão fix `1492277` dispara as 4 premissas Yes (Σ34: marca 22%/12% em branco, 1.8/1.6 gol/jogo, clean sheet 22%/6%, 4-5 dos últimos 5 com BTTS); fix `1351123` dispara as 3 Não (Σ28: clean sheet 47%, ataque trava 37%, 4-4 sem BTTS). Mart rende 7 linhas BTTS (Copa, `valor_fonte='consenso'`, edges 0.001-0.044, 1 Média — edge de consenso é naturalmente pequeno); **sem regressão** (1X2/O/U/AH seguem 'pinnacle'). **⚠️ Reconciliação §12.4**: lado Não = "de um dos times" ⇒ **OR**; gols feitos por **venue** (não total). **Deploy feito 2026-06-25**: imagem `dbt-futebol` rebuildada + `gcloud run jobs update --region us-east1` + `int_futebol_premissas_btts` no `--select` do `workflow_futebol_odds.yml` + `deploy_workflows.sh workflow-futebol-odds`. |
| **S5** | Premissas — **Dupla chance** | mercado | 12 | **§12.5** — 4 premissas (Σ34), **reusa premissas do 1X2**; **gate próprio** (≥1,25, sem `odd_juice`) | ✅ **feito 2026-06-26** — `int_futebol_premissas_dc` (2 outcomes **1X**/**X2** por fixture; o **12** "sem empate" não casa com o padrão S/O da §12.5 → fora). `lado_coberto_forte` **reusa** `forca_mismatch`/`superioridade_tabela` e `adversario_limitado` reusa `h2h_favoravel` do `int_futebol_premissas_1x2` (join no lado S: Home p/ 1X, Away p/ X2); `equilibrio_defensivo` (ga_total≤1,3 dos dois **e** <30% goleados) e `invicto_recente` (S sem derrota em ≥3 dos últimos 5) derivam de `fact_team_season_stats` + jogos FT. Sem clamp (Σ≤34). **Descoberta-chave (de-vig)**: as 3 saídas da DC **não são exaustivas** (1X+12+X2 somam ~2) → o de-vig de consenso da S4 **quebraria** (normaliza p/ 1 → prob ~metade). **Decisão (usuário 2026-06-26)**: a `prob_justa` da DC é **DERIVADA do de-vig 1X2 da Pinnacle** (P(1X)=P(Home)+P(Draw), P(X2)=P(Draw)+P(Away)) em `dc_devig` no `int_futebol_odds_devig`; `valor_fonte='pinnacle'` (âncora sharp, §13), `n_outcomes_valor=3` (gate = conjunto 1X2 completo); o consenso passa a **excluir** o market 12. `fact_odds_snapshot` mapeia os labels (`Home/Draw`→1X, `Home/Away`→12, `Draw/Away`→X2; antes NULL). Mart com **ramo `joined_dc`** (UNION) e **gate próprio**: `best_odd≥1,25` **e** sem `odd_juice` (penalidades globais recalculadas s/ juice), penalidade específica `odd_muito_baixa` (<1,20, −10) + aviso. **dbt run/test verdes** (19 OK). **Validado** (Copa, Brasileirão na pausa FIFA): `dc_prob == P(Home/Draw/Away)` exato p/ todas as saídas (somam 2.0, confirmando não-exclusividade); 12 linhas DC no mart, todas `valor_fonte='pinnacle'`, `edge>0`, `min(best_odd)=1,28`, `0` avisos de juice, longshot ainda aplica (fix 1489415 odd 5,85 → −15 sem juice); `1X` da fix 1489381 (odd 1,10) corretamente barrado pelo gate ≥1,25; sem regressão (1X2/O/U/AH/BTTS intactos, juice segue em AH/OU/1X2). **⚠️ Reconciliação §12.5**: gate ≥1,25 torna `odd_muito_baixa` (<1,20) **inerte** (nunca dispara junto do gate) — implementado fiel ao spec; revisitar na calibração. **Deploy feito 2026-06-26**: imagem `dbt-futebol` rebuildada (digest `975a688`) + `gcloud run jobs update --region us-east1` + `int_futebol_premissas_dc` no `--select` do `workflow_futebol_odds.yml` + `deploy_workflows.sh workflow-futebol-odds` (workflow live confirmado contendo o modelo). |
| **S6** | Dado — **coletar Predictions (futuros)** | dado | — | extractor existe (`fact_predictions_api`, tabela 14) mas **só 3 fixtures**; falta **agendar coleta pré-jogo** (1 call/jogo, `GET /predictions?fixture`) → daí derivar `modelo_api_concorda` por outcome | ✅ **código feito + validado 2026-06-29 (deploy pendente)** — **causa raiz**: o extractor já rodava (poll ~15min) mas só capturava 1 janela estreita **T-2h** com **1 arquivo único/fixture + skip-if-exists** → só pegava jogos a ~2h do kickoff; jogos futuros nunca ganhavam previsão. **Fix (reusa padrão date-stampado de standings/injuries)**: (a) `config.py` — `FUTEBOL_PREDICTIONS_WINDOWS` ganha janela **`daily` (131..20160 min = ~2h a 14d)** ao lado da `t2h` (refresh perto do jogo), bandas disjuntas; (b) `get_gcs_path` branch per-fixture passa a reconhecer janelas de predictions **e anexar `date`** → path `raw_futebol_predictions_{fixture}_{janela}_{YYYY-MM-DD}.json` (skip-if-exists vira **por (fixture, janela, DIA)** → recaptura 1x/dia); (c) `predictions_extractor` passa `mode=window, date=today`. O **mart não muda lógica** — já dedup latest-wins por `loaded_at DESC` (agora load-bearing: várias capturas/jogo → fica a mais fresca). **Cobertura**: gate hardcoded `[71,1]` (ambos `coverage.predictions=TRUE`) + degradação graciosa (resposta vazia ⇒ não grava; ex.: mata-mata Copa com times TBD) — **sem** checagem ao vivo de `/leagues` (decisão do usuário). **Horizonte 14d** (alinha com janela de odds). **dbt**: único ajuste funcional = `accepted_values` de `collection_window` → `['t2h','daily']` (senão quebra); +descrições. **Validado 2026-06-29**: extractor capturou **15 fixtures** futuros (era ~3), 0 erro/0 vazio, date-stampados `_daily_2026-06-29.json`; `dbt run` + **18 testes verdes** (accepted_values, unique fixture_id pós-dedup, relationships, prob ranges); aceite OK — 15 jogos futuros (Copa, Brasileirão em pausa FIFA) com `prob_home/draw/away` preenchidos (somam 100). Nota: a API devolve previsão **genérica** (45/45/10, 50/50/0) p/ mata-mata da Copa — confirmado no raw GCS (não é bug; flatten ok); previsões variadas voltam com o Brasileirão. **Sem mudança de workflow YAML** (já chama `extract-predictions` + rebuilda stg+fact; `modelo_api_concorda` recomputa no workflow de odds). **Deploy pendente (produção — requer go-ahead do usuário)**: `deploy_cloud_run.sh futebol extract-predictions` + `build-and-push.sh dbt_futebol` + `gcloud run jobs update dbt-futebol --image …:latest --region us-east1`. **⚠️ Sem novo scheduler**: a varredura diária emerge do poll ~15min já existente via date-stamp. |
| **S7** | Dado — **Injuries pré-jogo + proxy de importância** | dado | — | extractor existe (`fact_injuries_snapshot`, tabela 12, **só Brasileirão**) mas **só histórico até 31/05**; falta **coletar pré-jogo** (`GET /injuries?fixture`) + **proxy de importância** (`/players` rating+minutos **ou** `/fixtures/lineups` Start XI ~20–40 min antes) p/ só desfalque relevante disparar | ✅ **feito + deployado 2026-06-30** — **causa raiz**: a única coleta era o snapshot season-log diário (`/injuries?league&season`), que congela na pausa FIFA (log parado em 31/05) e não traz desfalques de jogos FUTUROS. **Fix (espelha o forward-only da S6)**: novo modo `pregame` do `InjuriesExtractor` varre os NS futuros (janela única `daily` 0–14d, `FUTEBOL_INJURIES_WINDOWS`), bate `GET /injuries?fixture` (novo `get_injuries_by_fixture`), grava date-stampado por (fixture, dia) com skip-if-exists; **mesmo shape de linha** do season-log (sem coluna nova → `stg`/`fact` intactos; `injuries` já em `array_keys`). **Cadência custo-ótima** (decisão do usuário): scheduler `futebol-injuries-pregame` **horário** (não 4×/h — `fact_injuries_snapshot` é daily-grained; notícia final fica p/ os lineups confirmed). **Proxy de importância**: novo `int_futebol_player_importance` (1 linha/(player, competição), pooling de seasons; `is_important = total_minutes≥450 AND start_share≥0.5`) sobre `fact_fixture_player_stats` (já materializado, sem consumidor) → novo `int_futebol_desfalques` (1 linha/(fixture,team,player) com **tipo + `is_important`**; dedup preferindo `Missing Fixture`) = **artefato do aceite**. **S1 revisitada**: o `-- TODO(S7)` do `int_futebol_premissas_1x2` virou o CTE `desf` (conta só `Missing Fixture AND is_important`) → `desfalque_adversario`/`desfalque_proprio` importance-gated; `Questionable` guardado/exibido mas **não dispara** (decisão do usuário, fiel à §12.1). **Writer disjunto**: `workflow_futebol_injuries.yml` (poll horário) refresca só o lado injuries; o Score recalcula no `workflow_futebol_odds.yml` (ganhou `int_futebol_player_importance`+`int_futebol_desfalques` no `--select`). **Validado 2026-06-30**: dbt run/test verdes (17 PASS, 2 warn herdados de relationships do fact_injuries); proxy confere (442 importantes, min 456min/0,5 start_share); probe `/injuries?fixture` OK (fix 1492219 → 38 desfalques, mesma estrutura do season-log); gate de importância filtra **297 desfalques de não-titulares** (1604→1307 (fixture,time)); job dbt prod (`dbt-futebol-w9tpl`) + workflows (injuries/odds) executados OK; scheduler ENABLED. **⚠️ Na pausa FIFA a coleta pregame fica ociosa** (Brasileirão >14d à frente; Copa excluída — injuries=FALSE) → ativa quando o Brasileirão entra na janela 14d; o season-log diário segue. **⚠️ Calibração (Fase 5)**: `is_important` é AND estrito → super-sub de muitos minutos com start_share<0.5 (ex.: Deyverson, 2471min) fica FALSE; thresholds tunáveis (§13). **Lineups (`is_starter`) near-KO = enhancement futuro.** |
| **S8** | Infra — **Histórico append-only de `fact_value_opportunities`** | infra | — | `fact_value_opportunities` é `materialized='table'` full-refresh por janela de odds (t24h/t1h/t15m) → o pick da manhã (t24h) some quando a linha fecha em t15m e o mart é sobrescrito; sem histórico não dá pra medir CLV nem auditar o que foi recomendado antes do jogo | ✅ **feito + deployado 2026-07-27** — novo snapshot dbt `fact_value_opportunities_hist` (`analytics-engineering/dbt_futebol/snapshots/fact_value_opportunities_hist.sql`), `strategy='check'`, `unique_key='opportunity_key'` (`fixture_id|market|outcome|line_value` NULL-safe, mesmo padrão do `line_key`), `invalidate_hard_deletes=True` (fecha `dbt_valid_to` quando a oportunidade sai do gate). `check_cols` cobre os campos que mudam por janela (`janela_usada`, `edge`, `score`, `faixa`, `valor_fonte`, odds, penalidades, corroboração) — **exclui** `evidencias`/`avisos` (BigQuery não suporta `IS DISTINCT FROM` em `ARRAY`, `check_cols='all'` quebraria a SQL) e `dbt_loaded_at` (mudaria a cada run). **Workflow**: novo `phase3_dbt_snapshot` no `workflow_futebol_odds.yml`, gateado por `workflow_status=="SUCCESS"` da Fase 2 (não versiona mart potencialmente stale se o rebuild falhou); erro no snapshot vira `PARTIAL_FAILURE` mas não bloqueia. **Sync**: `fact_value_opportunities_hist` adicionada ao `FUTEBOL_SYNC_TABLES_ORDERED` (`data-engineering/src/config.py`) → tabela 22 no Supabase `futebol.*` (`prop-play-predictor/docs/futebol-prod-deploy.sql`), colunas `evidencias`/`avisos` puladas pelo sync (mesma convenção do resto do schema). **Validado 2026-07-27**: `dbt snapshot` local 2x seguidas sem duplicar (114 linhas, 114 `opportunity_key` distintos, todas com `dbt_valid_to IS NULL`); imagem `dbt-futebol` rebuildada + `gcloud run jobs update` + execução manual `dbt-futebol-rblvd` OK; `sync-bq-to-postgres` redeployado (pegou a tabela nova no `config.py`); `workflow-futebol-odds` redeployado (`phase3_dbt_snapshot` confirmado no source live); sync rodado e validado **sem drift** em DEV e PROD (114 linhas cada, `open_rows=114`). **Nota de ambiente**: Homebrew Python (`python@3.13`/`3.14`) nesta máquina estava com `pyexpat` quebrado (símbolo faltando na `libexpat` do sistema, macOS 26.2) — contornado com `DYLD_LIBRARY_PATH=/opt/homebrew/opt/expat/lib` na recriação do `.venv` do `analytics-engineering`; não é um problema do projeto, é local à máquina. |

---

## 9. Aceite / Definição de pronto

- [ ] de-vig market-aware da Pinnacle + EV/edge calculados sobre `fact_odds_snapshot` (Fase 0)
- [ ] `fact_value_opportunities`: 1 linha por `fixture × mercado × outcome` com `edge, PTS_*, penalidades, Score, faixa, evidências[], avisos[]`
- [ ] Gate aplicado (`edge > 0` E `n_casas ≥ 3`; **exceção Dupla chance** ≥1,25) e faixas (≥60 / 40–59 / <40)
- [ ] Premissas dos 5 mercados (S1–S5) implementadas conforme §12 (`futebol-metodologia-premissas.md`)
- [ ] Corroboração (predictions + linha sharp) e proxy de importância de lesões (S6–S7)
- [ ] Serviço/leitura por `fixture_id` validado num jogo do **Brasileirão** (dado rico)
- [ ] dbt run/test verdes
- [ ] Pesos/thresholds calibrados depois com RPS/log-loss/calibração + CLV (quando o t15m acumular) — §13

---

## 10. Decisões a confirmar (pontos em aberto)

1. ✅ **Docs de metodologia (resolvido 2026-06-22)** — **movidos para `analytics-engineering/docs/`** (co-locados com o dbt; fonte autoritativa aqui). Premissas/pesos transcritos na §12, fundamentação na §13 (espelhos datados — ao calibrar, atualizar o `.md` e re-sincronizar a §12). **Não bloqueia S1–S5.**
2. **De-vig: construir aqui (Fase 0) ou na task separada "odds/EV%"?** — recomendo construir aqui como `int_futebol_odds_devig` reutilizável (a task de EV% do NBA não tocou futebol). **Confirmado 2026-06-18: não há de-vig pronto em lugar nenhum** — nem SQL no dbt, nem TS no front (os `futebol-value.ts`/`futebol-tendencias.ts` citados no playbook **não existem ainda**). Logo a Fase 0 é mesmo o caminho crítico.
3. **Granularidade do mart** — 1 mart unificado long (`fact_value_opportunities` com coluna `market`, recomendado) vs. 1 por mercado.
4. **Janela de avaliação de `melhor_odd`/`n_casas`** — usar a mesma janela do `prob_justa_fechamento` (t15m→t1h→t24h) para consistência interna; confirmar.
5. **Local deste doc** — colocado em `analytics-engineering/docs/` (onde vive `dbt_futebol`); mover p/ `data-engineering/docs/` (junto do pipeline) se preferir.
6. **Serving** — reusar BQ→Postgres (postergado) / FDW quando houver UI; sem serviço Python de cálculo.
7. **Pesos/faixas são ponto de partida** — calibrar com RPS/calibração + CLV quando o `t15m` acumular.
8. ✅ **Dupla contagem de movimento de linha (O/U) — RESOLVIDO 2026-06-23 (S2): fontes diferentes.** A premissa `linha_subindo`/`linha_descendo` (+6) mede o **consenso do mercado** (média de TODAS as casas t24h→t15m, em `int_futebol_premissas_ou`); a corroboração global `linha_sharp_confirma` (+8) mede **só a Pinnacle** (em `int_futebol_odds_devig`). Sinais distintos → sem somar o mesmo evento duas vezes; +14 só quando mercado **e** sharp movem juntos.
9. **Modelo próprio (Pilar B) fica fora deste motor** — o benchmark (§13) recomenda um Dixon-Coles + xG ("Pilar B") como evolução. Este motor é o **"Pilar A" (valor/regras)** e usa o de-vig da Pinnacle + `/predictions` da API como "modelo de referência". Quando/se o Pilar B existir, vira mais uma fonte de corroboração (ou substitui `modelo_api_concorda`). **Não** está no escopo de S0–S7.
10. ✅ **De-vig de consenso p/ mercados sem Pinnacle (RESOLVIDO 2026-06-25, S4)** — descoberto nos dados que a **Pinnacle não precifica BTTS(8)/HT-FT(7)/Dupla Chance(12)** (0/44 fixtures; mercados "recreativos"). Sem Pinnacle não há `prob_justa` → sem edge → sem gate. **Decisão**: `int_futebol_odds_devig` ganha um **fallback de consenso** (de-vig sobre a **mediana das casas**, `med_odd`) quando a Pinnacle falta, **guardado por COALESCE** (1X2/O/U/AH com Pinnacle ficam intactos) e marcado por `valor_fonte` ('pinnacle'|'consenso'); o ramo BTTS do mart gateia por `n_outcomes_valor`. **Trade-off**: consenso carrega a margem/viés das casas (§13 ancora no fechamento da Pinnacle) → expor BTTS como **"estimativa"**, não valor calibrado. Vale p/ HT/FT se entrar. **⚠️ Atualização (S5, 2026-06-26)**: a **Dupla Chance NÃO usa consenso** — descoberto que suas 3 saídas (1X/12/X2) **não são exaustivas** (somam ~2), então a normalização do consenso p/ 1 daria prob ~metade da real. A DC é **derivada do de-vig 1X2 da Pinnacle** (P(1X)=P(Home)+P(Draw) etc.) → `valor_fonte='pinnacle'` (âncora sharp, melhor que consenso); o consenso passa a **excluir o market 12** (`AND market_id <> 12`).

---

## 11. Decisões já tomadas (referência rápida)

| Decisão | Valor |
|---|---|
| Natureza | Regras determinísticas (V/F ponderados), **não** ML — cabe em dbt/SQL ("Pilar A") |
| Arquitetura | **dbt-mart-first**, espelhando `dim_daily_opportunities` (NBA); nova camada `intermediate/` em `dbt_futebol` |
| Mart de saída | `fact_value_opportunities` (proposto), long por `fixture × mercado × outcome` |
| Fonte de odds/valor | `fact_odds_snapshot` (Pinnacle=4 sharp p/ de-vig; janelas t24h/t1h/t15m) |
| Fórmula / faixas | Fechados (seção 2): Score = clamp(VALOR+PREMISSAS+CORROB−PEN,0,100); faixas 60/40 |
| Gate / penalidades | Globais (§2) + **específicas por mercado** (§12); **Dupla chance tem gate próprio** (≥1,25, sem `odd_juice`) — não 100% uniforme |
| Metodologia (premissas/pesos) | `analytics-engineering/docs/futebol-metodologia-premissas.md` → snapshot na §12; pesos = ponto de partida |
| Mercados (v1) | 1X2 (1), O/U (5), Asian Handicap (4), BTTS (8), Double Chance (12) |
| Degradação graciosa | dado faltando ⇒ premissa FALSE (nunca erro/NULL no Score) |
| Liga de validação | Brasileirão (dado rico); Copa entra com degradação graciosa |
| Validação (Fase 5) | RPS (principal) + log-loss + calibração; **CLV = KPI-rei**; benchmark = de-vig do **fechamento da Pinnacle** (§13) |
| Modelo próprio (Dixon-Coles + xG) | "Pilar B" — **fora de escopo** deste motor |
| Dependência crítica | **de-vig/EV inexistente** — é a Fase 0 |

---

## 12. Premissas por mercado (spec do playbook)

> **Snapshot datado (2026-06-18)** de `analytics-engineering/docs/futebol-metodologia-premissas.md` — **fonte autoritativa é esse `.md`**. Pesos/thresholds são **ponto de partida** (calibrar — §13). Convenções: `S` = lado apostado, `O` = adversário; cada premissa é 1 booleano; dado faltando ⇒ FALSE (degradação graciosa). As premissas que **disparam** viram bullets de evidência no front (ordenadas por peso).

**Fontes de dado (todas já materializadas em `futebol.*`):** `fact_team_season_stats` (médias gols casa/fora, clean sheet, failed-to-score, forma) · `fact_fixtures` (resultados/últimos 5, dias de descanso) · `fact_fixture_stats` (xG, finalizações, escanteios — **Brasileirão**) · `fact_injuries_snapshot` + `fact_fixture_lineups_players` (desfalques) · `fact_standings_snapshot` (rank/pontos) · odds (`pin_open`=t24h, `pin_close`=t15m, n_casas, line_value) · `fact_predictions_api`.

### 12.1 — Resultado 1X2 (`market_id` 1)
**Valor quando** um lado é mais forte do que a odd sugere e o contexto (mando, desfalque, tabela) reforça.

| Premissa | Regra (threshold inicial) | Peso |
|---|---|---|
| `forca_mismatch` | gols feitos de S no seu campo ≥ 1,4 **e** gols sofridos de O no campo dele ≥ 1,3 | **12** |
| `superioridade_xg` | (xG médio de S − xG sofrido de O) ≥ +0,3 *(Brasileirão)* | **8** |
| `mando` | S mandante **e** % de pontos em casa ≥ 55% *(se visitante: aprov. fora ≥ 45% → peso 4)* | **8** |
| `desfalque_adversario` | O com ≥1 desfalque de titular **e** S sem desfalque de titular | **8** |
| `superioridade_tabela` | diferença de rank ≥ 6 posições **ou** pontos/jogo de S ≥ 1,3× O | **6** |
| `forma` | S com ≥ 3 vitórias nos últimos 5 *(peso baixo de propósito: duplica força — §13)* | **5** |
| `h2h_favoravel` | S venceu ≥ metade dos últimos confrontos diretos | **4** |

**Penalidades específicas:** `pick_empate` (−10, empate é a saída mais difícil) · `desfalque_proprio` (−15, S sem titular importante).

> **Reconciliação (S7, 2026-06-30)** — `desfalque_adversario` (+8) e `desfalque_proprio` (−15) agora são **importance-gated**: contam só `Missing Fixture` de jogador `is_important` (titular regular: `total_minutes ≥ 450 AND start_share ≥ 0.5`, via `int_futebol_player_importance` sobre `fact_fixture_player_stats`), não mais todo `Missing Fixture` cru. Fonte intermediária: `int_futebol_desfalques` (1 linha por (fixture, time, jogador) com **tipo** fora/dúvida + flag de importância — artefato do aceite). `Questionable` (dúvida) é **guardado/exibido** mas **não dispara** a premissa (conservador, fiel ao "desfalque de titular" desta seção; decisão do usuário). Coleta pré-jogo via `/injuries?fixture` (modo `pregame` do `InjuriesExtractor`, poll horário `futebol-injuries-pregame`). Threshold de importância = ponto de partida, tunável na calibração (§13) — hoje é AND estrito (minutos **e** titularidade), então super-sub de muitos minutos com `start_share < 0.5` não conta.

### 12.2 — Gols Over/Under, linha L (`market_id` 5)
**Valor quando** Over → jogo aberto, dois times que atacam e/ou se defendem mal; Under → defesas firmes, jogo travado.

**Over L:**
| Premissa | Regra | Peso |
|---|---|---|
| `ataque_combinado` | gols feitos mandante(casa) + gols feitos visitante(fora) ≥ L+0,5 | **12** |
| `defesas_vazaveis` | gols sofridos mandante(casa) + sofridos visitante(fora) ≥ L | **10** |
| `xg_combinado_alto` | soma do xG médio dos dois ≥ L+0,3 *(Brasileirão)* | **8** |
| `ritmo_alto` | média de finalizações/escanteios dos dois ≥ mediana da liga | **8** |
| `ambos_vazam` | clean sheet% dos dois < 35% | **6** |
| `historico_over` | ≥ 60% dos últimos 5 de cada foram Over L | **6** |
| `linha_subindo` | odd do Over caiu de t24h→t15m | **6** |

**Under L (espelho):**
| Premissa | Regra | Peso |
|---|---|---|
| `defesas_firmes` | gols sofridos mandante(casa) + visitante(fora) ≤ L−0,3 | **12** |
| `clean_sheets_altos` | clean sheet% dos dois ≥ 40% | **10** |
| `xg_baixo_combinado` | soma do xG médio dos dois ≤ L−0,3 | **10** |
| `ataques_fracos` | algum dos dois passa em branco ≥ 35% dos jogos | **8** |
| `historico_under` | ≥ 60% dos últimos 5 de cada foram Under L | **6** |
| `linha_descendo` | odd do Under caiu de t24h→t15m | **6** |

**Penalidade específica:** `linha_extrema` (−10, quando L ≤ 0,5 ou L ≥ 4,5 — odd vira juice/longshot).

#### 12.2.1 — Baseline de calibração por liga (medido 2026-08-03; Bundesliga em 2026-08-05)

Regras com **thresholds absolutos** calibrados no **Brasileirão** existem em três mercados, não só
no Gols (ver o escopo corrigido no item aberto, abaixo). Num ambiente de gols deslocado, todas as
premissas de um mesmo lado disparam juntas e inflam o `PTS_PREMISSAS` de um outcome que **o mercado
já precifica** — dupla contagem, não edge. As premissas que já são relativas à liga (`ritmo_alto`,
via `league_pace_median`) não sofrem disso.

Ambiente real por liga-temporada (`/fixtures`, seasons 2024 e 2025 — 760 jogos FT nas ligas de 20
times, 616 na Bundesliga, que tem 18):

⚠️ A coluna `clean sheet` desta tabela é **por jogo** (% de jogos em que ao menos um dos times
não sofreu gol) — NÃO é a mesma métrica dos thresholds das premissas, que são **por time-jogo**
(`clean_sheet_total / played_total`). As duas convivem no mesmo texto e não são comparáveis entre
si: Brasileirão dá 49,7% por jogo e 29,9% por time-jogo. Ao conferir um threshold, use a de time-jogo.

| liga | gols/jogo | Δ vs baseline | Over 2.5 | Δ | clean sheet (por jogo) | viés esperado |
|---|---|---|---|---|---|---|
| **Bundesliga (78)** | **3,18** | **+0,70** | **61,9%** | **+15,2pp** | 40,4% | superpontua **Over** — o maior desvio do portfólio |
| **Ligue 1 (61)** | **2,90** | **+0,42** | **54,1%** | **+7,4pp** | — | superpontua **Over** — e é o caso que SEPARA as hipóteses, ver abaixo |
| Premier League (39) | 2,84 | **+0,36** | 55,8% | **+9,1pp** | 43,3% | superpontua **Over** |
| Primeira Liga (94) | 2,62 | +0,14 | 51,5% | +4,8pp | — | leve, pró-Over |
| La Liga (140) | 2,66 | +0,17 | 49,3% | +2,6pp | 44,6% | leve, pró-Over |
| Serie A ITA (135) | 2,49 | +0,01 | 47,0% | +0,3pp | 51,6% | — (na baseline) |
| **Brasileirão (71)** | **2,48** | — | **46,7%** | — | 49,7% | *baseline* |
| Série B (72) | 2,20 | **−0,28** | 38,6% | **−8,2pp** | 53,3% | superpontua **Under** |

Observação contraintuitiva registrada no rollout da Serie A ITA: a fama de "liga de poucos gols"
é folclore do catenaccio — a Serie A moderna é a liga **mais próxima da baseline** de todo o
portfólio. O desvio real está em Premier League e Série B, ambas em produção.

O rollout da Bundesliga (2026-08-05) é o caso **oposto**: ali o briefing pedia "liga de muitos gols,
ajustar O/U pra cima" e a medição **confirmou e subestimou** — +0,70 gol/jogo e +15,2pp de Over 2.5,
quase o dobro do desvio da Premier League. Com clean sheet de **23,1% por time-jogo** (o menor do
portfólio, contra 29,9% do Brasileirão) e ~1,59 gol por time-jogo, as premissas do lado "muitos
gols" disparam quase sempre nessa liga: `ambos_vazam` (Over), `ambos_marcam` + `ataque_dos_dois` +
`defesas_vazaveis` (BTTS-Sim) e `adversario_fragil_fora` (AH). A liga entrou em produção **sem gate**,
como as demais europeias — a decisão foi registrar o viés, não segurar a liga.

**A dupla contagem, medida (2026-08-05).** Deixou de ser argumento: `int_futebol_premissas_ou`,
linha 2.5, seasons 2024+2025, por liga —

| liga | gols/jogo | `ataque_combinado` | `defesas_vazaveis` | **PTS Over** | **PTS Under** |
|---|---|---|---|---|---|
| bundesliga | 3,18 | 53,9% | 77,6% | **29,3** | 6,2 |
| **ligue_1** | **2,90** | — | — | **25,7** | — |
| premier_league | 2,84 | 40,4% | 61,6% | 24,7 | 7,9 |
| la_liga | 2,66 | 29,5% | 51,6% | 20,6 | 11,1 |
| serie_a_ita | 2,49 | 25,3% | 47,8% | 17,7 | 13,3 |
| **brasileirao** *(baseline)* | 2,48 | 17,9% | 42,1% | **15,2** | 14,2 |
| serie_b | 2,20 | 8,8% | 24,9% | 11,9 | 17,9 |

**A ordem de `PTS Over` é idêntica à ordem de gols/jogo, liga a liga** — e a de `PTS Under` é o
espelho invertido. O `PTS_PREMISSAS` do lado Over não está medindo confiança naquela aposta; está
medindo o ambiente de gols da liga, que é exatamente o que o mercado já precificou na odd. Uma liga
extrema entra com ~2× o crédito de premissa da liga onde os limiares foram calibrados (29,3 vs 15,2),
sem nenhum edge adicional. Como a faixa Alta começa em 60, o efeito prático é que um Over de
Bundesliga alcança Alta com menos edge real que um Over de Brasileirão equivalente.

**O caso que SEPARA as hipóteses: a Ligue 1 (medido 2026-08-07).** A evidência da Bundesliga tinha
um limite lógico que vale nomear. Ali a ordem de gols/jogo e a de acerto de Over **coincidiam**,
então as duas leituras possíveis do `PTS Over` — "mede o ambiente da liga" e "mede o acerto da
aposta" — faziam a **mesma** previsão, e o dado não distinguia uma da outra.

A Ligue 1 é o primeiro caso da carteira em que as duas ordens **divergem**, e por isso ela decide:

| liga | gols/jogo | `PTS Over` | Over 2.5 real |
|---|---|---|---|
| bundesliga | 3,18 (1º) | 29,3 (1º) | 61,9% (1º) |
| **ligue_1** | **2,90 (2º)** | **25,7 (2º)** | **54,1% (3º)** |
| premier_league | 2,84 (3º) | 24,7 (3º) | **55,8% (2º)** |

O `PTS Over` seguiu **gols/jogo**, não o acerto. Consequência direcional: a Ligue 1 recebe **+1,0
ponto mais** que a Premier League enquanto **acerta 1,7pp menos** Over que ela — ou seja, para esse
par a pontuação de Over ordena na **direção errada**. Não é ruído de amostra (618 e 760 linhas), e
não é aproximação: é a mesma sequência exata de gols/jogo, agora contra uma ordem de acerto que
discorda dela. A assinatura da Ligue 1 é de **goleada** (mais gols concentrados em menos partidas),
e as premissas de O/U, que leem médias, não distinguem isso de jogo aberto.

O baseline da Bundesliga reproduziu dígito a dígito nesta medição (29,3 · 24,7 · 20,6 · 17,7 ·
15,2 · 11,9), então a instabilidade entre builds registrada para o board não afeta esta série.

**Item aberto (Fase 5):** tornar os thresholds absolutos relativos à mediana da própria
liga-temporada, replicando o padrão do `league_pace_median` que já existe em
`int_futebol_premissas_ou`. Isso autocalibra qualquer liga futura e dispensa tabela de constantes
por liga. Validar com backtest RPS/CLV antes de aplicar — muda o comportamento de ligas já em
produção.

**Escopo real do item (corrigido em 2026-08-05):** não são cinco regras do Gols O/U — são ≈11, em
**três mercados**. A varredura feita no rollout da Bundesliga encontrou o mesmo padrão em:

| mercado | regras com threshold absoluto |
|---|---|
| Gols O/U (5) | `ambos_vazam` (cs < 35%), `clean_sheets_altos` (cs ≥ 40%), `ataques_fracos` (fts ≥ 35%), + os offsets `+0,5` / `±0,3` de `gf_comb`/`ga_comb`/`xg_comb` contra a linha |
| BTTS (8) | `ambos_marcam` (fts < 30%), `ataque_dos_dois` (gf ≥ 1,2), `defesas_vazaveis` (cs < 35%), `ataque_trava` (fts ≥ 35%) |
| Handicap (4) | `tende_golear` (gf ≥ 2,0 **e** ga ≤ 1,0), `adversario_fragil_fora` (ga ≥ 1,6), `defesa_fora_solida` (ga ≤ 1,1) |

Todas se movem junto com o ambiente de gols da liga, e nenhuma delas é relativa hoje. Dimensionar a
Fase 5 pelos cinco thresholds do O/U subestima o trabalho por um fator de ~2.

### 12.3 — Handicap asiático, meia-linha (`market_id` 4)
`H` = handicap na ótica do mandante. **Valor quando** a supremacia real difere do que a linha pede (favorito dando handicap; azarão recebendo).

**Favorito (ex.: Mandante −1,5):**
| Premissa | Regra | Peso |
|---|---|---|
| `supremacia` | diferença de rank ≥ 8 **ou** pontos/jogo ≥ 1,5× O | **12** |
| `tende_golear` | S gols feitos ≥ 2,0 **e** sofridos ≤ 1,0 nos últimos jogos | **10** |
| `adversario_fragil_fora` | gols sofridos de O (fora) ≥ 1,6 | **8** |
| `mando_forte` | aproveitamento em casa de S ≥ 60% | **6** |
| `sem_rodizio` | jogo importante p/ S, sem decisão na semana | **4** |

**Azarão (cobrir +1,5 etc.):**
| Premissa | Regra | Peso |
|---|---|---|
| `raramente_perde_por_2` | O perdeu por 2+ gols em < 30% dos jogos | **12** |
| `defesa_fora_solida` | gols sofridos de O (fora) ≤ 1,1 | **10** |
| `favorito_irregular` | S venceu por 2+ em < 35% dos jogos | **8** |

**Penalidade específica:** `handicap_alto` (−12, quando `mód(H) ≥ 2,5` — raramente confiável).

### 12.4 — Ambos Marcam / BTTS (`market_id` 8)
**Valor quando** Sim → dois ataques ativos e defesas vazáveis; Não → uma defesa forte ou um ataque que trava.

**Sim:**
| Premissa | Regra | Peso |
|---|---|---|
| `ambos_marcam` | failed-to-score% dos dois < 30% | **12** |
| `ataque_dos_dois` | gols feitos médios dos dois ≥ 1,2 | **8** |
| `defesas_vazaveis` | clean sheet% dos dois < 35% | **8** |
| `historico_btts` | ≥ 60% dos últimos 5 de cada com BTTS | **6** |

**Não (espelho):**
| Premissa | Regra | Peso |
|---|---|---|
| `defesa_forte` | clean sheet% de um dos times ≥ 45% | **12** |
| `ataque_trava` | failed-to-score% de um dos times ≥ 35% | **10** |
| `historico_seco` | ≥ 60% dos últimos 5 de um dos times sem BTTS | **6** |

*(Sem penalidade específica além das globais.)*

> **Reconciliação (S4, 2026-06-25)** — implementado em `int_futebol_premissas_btts`: (a) "dos dois" (Sim) ⇒ **AND**; "de um dos times" (Não) ⇒ **OR** (fiel ao texto). (b) `ataque_dos_dois`/gols feitos médios = por **venue** (mandante em casa `goals_for_avg_home`, visitante fora `goals_for_avg_away`), espelhando o `gf_comb` do S2; clean sheet%/failed-to-score% sobre o **total** da temporada. (c) `historico_btts`/`historico_seco`: `≥3 de 5` aproxima "≥60%" (mesma simplificação do S2). (d) **VALOR via consenso**: a **Pinnacle não precifica BTTS** (0/44 fixtures) → o de-vig usa a **mediana das casas** (`valor_fonte='consenso'`), não o fechamento da Pinnacle (§13) — expor como **"estimativa"**, não valor calibrado.

### 12.5 — Dupla Chance (`market_id` 12)
Combina 2 das 3 saídas (ex.: "S ou empate"). **Valor quando** o mercado **superprecifica a zebra** do lado descoberto (aposta de proteção).

| Premissa | Regra | Peso |
|---|---|---|
| `lado_coberto_forte` | reusa `forca_mismatch` + `superioridade_tabela` do 1X2 (§12.1) | **12** |
| `equilibrio_defensivo` | os dois com gols sofridos moderados e poucos jogos goleados | **8** |
| `adversario_limitado` | O com baixo aproveitamento e/ou histórico ruim vs S | **8** |
| `invicto_recente` | S sem derrota nos últimos 5 | **6** |

**Gate próprio (não usa o global):** aceitar `melhor_odd ≥ 1,25`; **não** aplicar `odd_juice` (<1,40). **Penalidade específica:** `odd_muito_baixa` (−10, quando `melhor_odd < 1,20`).

> **Reconciliação (S5, 2026-06-26)** — implementado em `int_futebol_premissas_dc` + ramo `joined_dc`: (a) só **1X** (S=Home) e **X2** (S=Away) são produzidos; o **12** ("sem empate") não tem lado S/O claro → fora. (b) `lado_coberto_forte` = `forca_mismatch` **OR** `superioridade_tabela` do 1X2 (lado S); `adversario_limitado` = aproveitamento de O < 45% **OR** `h2h_favoravel` do 1X2. (c) **De-vig DERIVADO do 1X2 da Pinnacle**, não consenso (as 3 saídas somam ~2, não são exaustivas → consenso quebraria); `valor_fonte='pinnacle'`. (d) o gate `≥1,25` torna `odd_muito_baixa` (<1,20) **inerte** na prática (nunca dispara junto do gate) — implementado fiel ao spec; revisitar na calibração.

---

## 13. Fundamentação (benchmark)

> Destilado de `analytics-engineering/docs/futebol-metodologia-benchmark.md` — só o que **muda decisão de design/calibração** aqui. O benchmark é, no geral, uma pesquisa para o **modelo próprio (Pilar B)**; abaixo, o que importa para o **motor de regras (Pilar A)**.

**Variáveis que movem o 1X2 (ranqueadas por força de evidência) e o que cada uma implica aqui:**

| Variável | Evidência | Implicação no motor |
|---|---|---|
| Força ataque/defesa via **xG/xGA** | **Forte** (a fundação) | premissas de xG são as mais fortes; só pegam no Brasileirão (Copa degrada) |
| **Odd de fechamento (Pinnacle) de-vig** | **Forte** (é o benchmark) | é o PTS_VALOR; bater a linha de **fechamento** (não casa mole) |
| **Mando** | **Forte mas caindo** (encolheu pós-2020, parte via árbitro sem torcida) | **recalibrar** o peso de `mando`; não tratar como fator genérico fixo |
| **Forma** (rating dinâmico) | **Moderada** — já capturada por bom rating | "forma" crua (`≥3 de 5`) **duplica** o rating → por isso peso baixo (5); não supervalorizar |
| **Disponibilidade de titular** | **Moderada→Forte** p/ craque | a casa repõe rápido na escalação → edge mora em **casa mole lenta** ou ausência **antes** da escalação → S7 coletar cedo (lineups só ~20–40 min antes) |
| Fadiga/descanso/congestionamento | **Moderada** | derivável dos fixtures (dias de descanso) — 🟡 candidato a premissa futura |
| Motivação/importância | **Moderada** (situacional) | derivável de classificação+rodada (rebaixamento, vaga, jogo morto, rotação) — usado em `sem_rodizio` |
| Árbitro / promovido / clima | Moderada→Fraca | em grande parte já no preço (ou ilusório, no caso de "efeito técnico") — não reinventar |

**Princípios que viram regra:**
- **xG > gols crus**: gol é raro (~2,7/jogo) → variância alta; xG estabiliza mais rápido e prevê melhor.
- **Empate é a saída mais difícil**: ninguém "torce" pelo empate; a prob fica ~22–28% e quase não varia com a força → justifica a penalidade `pick_empate` (−10).
- **Não reinventar o que o mercado já precifica** (forma crua, "efeito técnico"); focar onde há sinal **subprecificado** (escalação cedo, motivação/rotação, dado local que a casa global ignora).
- **Não expor "valor" de modelo não calibrado** — rotular como **"estimativa"** até validar.

**Como se valida (vira a Fase 5):**
- **RPS** (Ranked Probability Score) — métrica-padrão no futebol; premia acertar a **ordem**. Usar como principal.
- **log-loss** — reportar junto (contestação do Wheatcroft 2021 ao RPS).
- **Calibração** (curva de confiabilidade) — obrigatória: quando dizemos 30%, sai ~30%? É do que o value bet depende.
- **Benchmark = de-vig do FECHAMENTO da Pinnacle** (não abertura nem casa mole); Pinnacle de-vig ≈ **0,997** de correlação com a frequência real.
- **CLV (Closing Line Value) = KPI-rei** — pegar preço melhor que o fechamento é o sinal mais estável de edge (mais que ROI de curto prazo). **Instrumentar desde o dia 1** (t15m já chegando).

**Pilar A vs Pilar B:** este motor é o **Pilar A (valor/regras)** — usa de-vig da Pinnacle + premissas + `/predictions` da API como "modelo de referência". O benchmark recomenda como evolução um **Pilar B (modelo próprio)**: núcleo **Dixon-Coles** (Poisson + correção de placar baixo + decaimento temporal), λ a partir de **xG** ataque/defesa + mando + ajuste de escalação, com **ratings (pi-ratings/Elo)** como prior. **Hoje não existe** (os `src/utils/futebol-value.ts`/`futebol-tendencias.ts` citados no playbook são referências aspiracionais — não estão no repo). Quando existir, vira corroboração adicional (ou substitui `modelo_api_concorda`).

**Gaps apontados (úteis de saber):** rating próprio ⬜ (tijolo barato e forte — fortaleceria `superioridade_tabela`/`supremacia`, hoje crus via rank/pontos); **peso de jogador** (minutos×qualidade) ⬜ = exatamente o proxy de importância de **S7**; xG fora do Brasileirão ⬜ (Copa fraca — degradação graciosa); mando por liga recalibrado pós-2020 🟡.

---

## 14. Correção do look-ahead (Task 0) — 2026-08-03

A auditoria da **Task 0** (ClickUp `wdx6zev64w`) encontrou que **27 das 39 premissas liam dado posterior
ao jogo**. As correções abaixo estão implementadas e testadas; **ainda não deployadas** (exige rebuild da
imagem `dbt-futebol`, ver `.claude/skills/deploy-dbt-changes`).

### O que mudou

| Item | Fonte contaminada | Correção |
|---|---|---|
| A + B2 | `fact_team_season_stats` (1 snapshot/season = temporada FECHADA em 24/25) e `standings_latest` (`MAX(snapshot_date)` = tabela final) | Novo `int_futebol_team_form_pit`, grão (fixture_id, team_id), reconstruído de `fact_fixtures` só com jogos anteriores ao kickoff. Traz também rank/points/ppg/n_wins_last5/n_teams |
| C | xG e pace do O/U em média da season inteira | `fixture_team_spine` + `date_utc < DATE(kickoff)` — o mesmo padrão que o `_1x2` já usava |
| D | `int_futebol_desfalques` com `MAX(snapshot_date)` | `extracted_at < kickoff_utc`. **99,6% das ~174 mil linhas de `/injuries` foram coletadas depois do apito** |
| E | `int_futebol_player_importance` com pool de todas as seasons | `is_important` virou point-in-time (window cumulativa) dentro de `int_futebol_desfalques`; `is_important_pooled` fica exposto |

**Guards de regressão:** `assert_pit_first_game_has_no_history` (na estreia, `played_total`=0 e rank NULL)
e `assert_desfalques_pregame_only` (todo desfalque vem de coleta pré-apito).

### Validação

- `int_futebol_team_form_pit` bate com a tabela real da API (Brasileirão 2026): **56/63 pontos e 55/63 ranks
  exatos**, erro médio de 0,27 posição. As diferenças são o snapshot diário estar defasado do kickoff — o PIT
  é mais preciso.
- **Produção não muda**: em jogos futuros o PIT é ~idêntico ao antigo (diferença média de **0,003 gol/jogo**).
  Faz sentido: para um jogo que ainda não aconteceu, "tudo antes do kickoff" = "temporada até agora".
- **Prova cruzada**: as 11 premissas que a auditoria classificou como limpas mudaram **exatamente 0%**; todas
  as 27 contaminadas mudaram.

### Re-run dos Testes 1 e 3 (o que sobrou)

Teste 1 (acerto vs. a média da mesma linha), maiores quedas: `tende_golear` +32,8 → +8,1 · `defesa_forte`
+19,4 → +3,3 · `mando` +19,3 → +5,8 · `clean_sheets_altos` +20,0 → +5,6 · `superioridade_tabela` +23,5 →
+12,1. Toda premissa limpa: delta 0,0.

Teste 3 (ROI da porta "2+ premissas", 168 jogos com odds, 16/06 a 02/08/2026):

| Porta | ROI antes | ROI depois |
|---|---|---|
| 2+ premissas | **+9,2%** (reproduz o "+9,7%") | **−7,6%** |
| 3+ premissas | +17,1% | −6,0% |
| edge>0 + 2 premissas | +18,6% | −15,4% |

Antes, o ROI subia monotonicamente com o nº de premissas — assinatura de vazamento. Depois, fica plano em
−6% a −9%: **a porta de contexto não ordena nada**.

**Achado adicional que muda a leitura:** com piso de 5 jogos disputados, **a base contaminada já dava
negativo** (−3,9%). Os +9,7% vinham inteiramente das linhas de amostra curta — Copa do Mundo (39% do
universo, média de **2,4 jogos**), Sudamericana (0,8) e Copa do Brasil (1,9), onde o snapshot de temporada
cobre um punhado de jogos e o próprio jogo pesa ~1/3 da "média". Brasileirão e Série B (17–18 jogos) nunca
sustentaram o resultado.

⚠️ **Amostra**: 168 jogos / ~1,5 mês (a odd só existe desde julho/2026) e apostas correlacionadas dentro do
mesmo jogo. A direção é inequívoca; os números negativos **não** devem ser lidos como estimativa precisa.

### Aberto para decisão

`played_total` foi exposto **sem** piso de amostra embutido: com 1–3 jogos, `superioridade_tabela` acende
mais (37,6%) do que com 11+ (32,2%) — um time que venceu a estreia tem PPG 3,0 contra 0,0. Definir o piso é
decisão de calibragem, não de correção de vazamento, e ficou para a recalibragem.
