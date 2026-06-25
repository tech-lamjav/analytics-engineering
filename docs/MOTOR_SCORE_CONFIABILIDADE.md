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
  - 🔧 **Gaps = coleta nova (extractors existem, mas não rodam p/ jogos futuros)**: **predictions hoje só 3 fixtures** (→ S6) e **injuries só histórico até 31/05** (→ S7). Ver §8.
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
| **S1** | Premissas — **Resultado (1X2)** | mercado | 1 | **§12.1** — 7 premissas (Σ51) + penalidades `pick_empate`/`desfalque_proprio`; `int_futebol_premissas_1x2` (3 outcomes/fixture; empate fiel ao playbook; desfalque na versão SIMPLES — ver S7) | ✅ **feito 2026-06-22** (validado no Brasileirão fix 1180448: Home pp=47 coerente §12.1; Score ponta-a-ponta no mart `fact_value_opportunities`. Mart hoje só rende Copa — Brasileirão sem odds 1X2 na pausa FIFA; odds são forward-only) |
| **S2** | Premissas — **Gols (Over/Under)** | mercado | 5 | **§12.2** — Over (7, Σ56) + Under (6, Σ52) espelhados; pen. `linha_extrema`; xG só Brasileirão; `int_futebol_premissas_ou` (2 outcomes/linha; universo de linhas = canônicas {1.5,2.5,3.5} ∪ linhas das odds; `historico_over/under` = últimos 5 FT mesma liga; `ritmo_alto` = mediana da liga via APPROX_QUANTILES; movimento de linha = **consenso do mercado**, §10.8) | ✅ **feito 2026-06-23** (validado no Brasileirão: Over satura nas linhas baixas / Under nas altas; `fact_value_opportunities` refatorado p/ **UNION 1X2+O/U** com join por `line_key` STRING e gate `pin_n_outcomes` por ramo (≥3 1X2 / ≥2 O/U); **clamp teto 55 implementado aqui** — só o Over chega a 56; dbt build/test verdes (mart rende 1X2+O/U, O/U com faixa Alta até 85); **deploy**: imagem `dbt-futebol` rebuildada + `gcloud run jobs update --region` + `int_futebol_premissas_ou` adicionada ao `--select` do **`workflow_futebol_odds.yml`** (onde o Motor recalc por janela de odds, sem `+`) e redeploy — execuções `dbt-futebol-fnbj7`/`z8nvc` OK) |
| **S3** | Premissas — **Handicap asiático** | mercado | 4 | **§12.3** — Favorito (5, Σ40) + Azarão (3, Σ30), pareável por `line_value`; pen. `handicap_alto` | ✅ **feito 2026-06-24** — `int_futebol_premissas_ah` (2 outcomes Home/Away por `(fixture, line_value)`; `side_handicap = IF(Home, line, -line)` decide favorito(<0)/azarão(>0)/pick(=0); só o lado certo dispara → Σ40 fav / Σ30 dog; pen. `handicap_alto` −12 em \|line\|≥2,5). **Descoberta-chave**: a API-Football traz `line_value` na **ótica do mandante, IGUAL p/ Home e Away** (`Home -1.5`/`Away -1.5` = par complementar), então o **de-vig da Fase 0 já parea o AH** por `(fixture, market, line_key)` — sem mudança no `int_futebol_odds_devig` (só ajustei a doc-string do warning). Mart com **3º ramo `joined_ah`** (gate Pinnacle ≥2, igual O/U) → UNION 1X2+O/U+AH; accepted_values atualizados. **dbt build/test verdes** (17 OK). **Validado**: Brasileirão fav −1,5 dispara as 5 premissas (40 pts, evidências coerentes: superior na tabela, marca 2,2/cede 0,9 em casa, adv. cede 1,9 fora, 75% mando, jogo importante); azarão dispara `raramente_perde_por_2`/`defesa_fora_solida`/`favorito_irregular`; `handicap_alto` confirmado em \|line\|≥2,5 (Copa). Mart hoje só rende Copa (Brasileirão sem odds AH na pausa FIFA — odds forward-only, igual S1/S2). **⚠️ Reconciliação §12.3**: o bloco "Azarão" do playbook troca rótulos S/O; implementei por **nome/intenção** (`raramente_perde_por_2`+`defesa_fora_solida` = azarão S; `favorito_irregular` = favorito O) — alinhar o `.md` a isto na calibração. **Deploy feito 2026-06-24**: imagem `dbt-futebol` rebuildada (digest `2bdc3e5`) + `gcloud run jobs update --region us-east1` + `int_futebol_premissas_ah` adicionada ao `--select` do `workflow_futebol_odds.yml` e `deploy_workflows.sh workflow-futebol-odds` redeployado (imagem confirmada contendo o modelo + ramo `joined_ah`). |
| **S4** | Premissas — **Ambos marcam (BTTS)** | mercado | 8 | **§12.4** — Sim (4, Σ34) + Não (3, Σ28) | ✅ **feito 2026-06-25** — `int_futebol_premissas_btts` (2 outcomes Yes/No por fixture, **sem line_value**; Sim gated por `outcome='Yes'`, Não por `='No'`; **sem clamp**, Σ34/Σ28 < 55). Convenções herdadas do S2: clean sheet%/failed-to-score% sobre o **total** da temporada, gols por **venue** (mandante casa/visitante fora), `historico_btts/seco` via últimos 5 FT de cada (≥3 ~ 60%). **Descoberta-chave (dados)**: a **Pinnacle NÃO precifica BTTS** (0/44 fixtures; idem HT/FT=7 e Dupla Chance=12 — mercados "recreativos") → sem âncora de de-vig. **Decisão (usuário)**: **de-vig de CONSENSO** (mediana das casas) como fallback na Fase 0 (`int_futebol_odds_devig`), **guardado por COALESCE** (não altera 1X2/O/U/AH) + coluna `valor_fonte` ('pinnacle'\|'consenso') p/ o front rotular "estimativa"; ramo `joined_btts` no mart gateia por `n_outcomes_valor >= 2`. **dbt build/test verdes** (26 OK). **Validado**: Brasileirão fix `1492277` dispara as 4 premissas Yes (Σ34: marca 22%/12% em branco, 1.8/1.6 gol/jogo, clean sheet 22%/6%, 4-5 dos últimos 5 com BTTS); fix `1351123` dispara as 3 Não (Σ28: clean sheet 47%, ataque trava 37%, 4-4 sem BTTS). Mart rende 7 linhas BTTS (Copa, `valor_fonte='consenso'`, edges 0.001-0.044, 1 Média — edge de consenso é naturalmente pequeno); **sem regressão** (1X2/O/U/AH seguem 'pinnacle'). **⚠️ Reconciliação §12.4**: lado Não = "de um dos times" ⇒ **OR**; gols feitos por **venue** (não total). **Deploy feito 2026-06-25**: imagem `dbt-futebol` rebuildada + `gcloud run jobs update --region us-east1` + `int_futebol_premissas_btts` no `--select` do `workflow_futebol_odds.yml` + `deploy_workflows.sh workflow-futebol-odds`. |
| **S5** | Premissas — **Dupla chance** | mercado | 12 | **§12.5** — 4 premissas (Σ34), **reusa premissas do 1X2**; **gate próprio** (≥1,25, sem `odd_juice`) | pendente |
| **S6** | Dado — **coletar Predictions (futuros)** | dado | — | extractor existe (`fact_predictions_api`, tabela 14) mas **só 3 fixtures**; falta **agendar coleta pré-jogo** (1 call/jogo, `GET /predictions?fixture`) → daí derivar `modelo_api_concorda` por outcome | pendente |
| **S7** | Dado — **Injuries pré-jogo + proxy de importância** | dado | — | extractor existe (`fact_injuries_snapshot`, tabela 12, **só Brasileirão**) mas **só histórico até 31/05**; falta **coletar pré-jogo** (`GET /injuries?fixture`) + **proxy de importância** (`/players` rating+minutos **ou** `/fixtures/lineups` Start XI ~20–40 min antes) p/ só desfalque relevante disparar | pendente — **⚠️ revisitar a S1**: `desfalque_adversario` (+8) e `desfalque_proprio` (−15) em `int_futebol_premissas_1x2` estão na versão SIMPLES (conta `Missing Fixture` sem pesar titularidade; ver `-- TODO(S7)` no SQL) → trocar pelo proxy de importância |

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
10. ✅ **De-vig de consenso p/ mercados sem Pinnacle (RESOLVIDO 2026-06-25, S4)** — descoberto nos dados que a **Pinnacle não precifica BTTS(8)/HT-FT(7)/Dupla Chance(12)** (0/44 fixtures; mercados "recreativos"). Sem Pinnacle não há `prob_justa` → sem edge → sem gate. **Decisão**: `int_futebol_odds_devig` ganha um **fallback de consenso** (de-vig sobre a **mediana das casas**, `med_odd`) quando a Pinnacle falta, **guardado por COALESCE** (1X2/O/U/AH com Pinnacle ficam intactos) e marcado por `valor_fonte` ('pinnacle'|'consenso'); o ramo BTTS do mart gateia por `n_outcomes_valor`. **Trade-off**: consenso carrega a margem/viés das casas (§13 ancora no fechamento da Pinnacle) → expor BTTS como **"estimativa"**, não valor calibrado. Vale também p/ a S5 (Dupla Chance) e p/ HT/FT se entrarem.

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
