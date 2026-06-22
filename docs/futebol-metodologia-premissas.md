# Playbook de premissas por mercado → Score de Confiabilidade

> **Para o dev (Mateus):** isto é uma especificação de **regras e contas** — nada de modelo
> estatístico. Cada "premissa" é um sinal booleano (verdadeiro/falso) que você calcula direto da
> base. Cada premissa tem um **peso em pontos**. O Score (0–100) é a soma ponderada. Onde o dado não
> existir (ex.: xG fora do Brasileirão), a premissa simplesmente **não dispara** (não é erro) — o
> Score fica menor, o que é honesto.
> Base conceitual: `docs/futebol-metodologia-benchmark.md`.

## 1. Fórmula do Score (igual para todos os mercados)

```
Score = clamp( PTS_VALOR + PTS_PREMISSAS + PTS_CORROBORACAO − PENALIDADES , 0 , 100 )
```

- **PTS_VALOR (0–30)** — tamanho do valor (edge). `edge = melhor_odd × prob_justa_fechamento − 1`,
  onde `prob_justa_fechamento` = de-vig da **odd de fechamento da Pinnacle** (janela t15m; cai p/ t1h/t24h).
  `PTS_VALOR = round( min(edge%, 6) / 6 × 30 )` → 6%+ = 30 pts; 3% = 15; 1% = 5; ≤0 = não é oportunidade (ver Gate).
- **PTS_PREMISSAS (0–55)** — soma dos pesos das **premissas de contexto** do mercado que dispararam (teto 55).
- **PTS_CORROBORACAO (0–15)** — confirmação externa (igual p/ todos):
  - `modelo_api_concorda` (+7): o modelo da API aponta o mesmo lado/tendência da aposta.
  - `linha_sharp_confirma` (+8): a odd da Pinnacle do lado apostado **caiu** de t24h→t15m (mercado migrou pro nosso lado).
- **PENALIDADES (subtraem)** — red flags (iguais p/ todos, + específicas do mercado):
  - `odd_outlier` (−30): `melhor_odd ≥ 1,10 × média_das_casas` → provável erro/limite de 1 casa mole (linha suspeita).
  - `poucas_casas` (−12): `n_casas < 4`.
  - `odd_longshot` (−15): `melhor_odd > 4,5`.
  - `odd_juice` (−10): `melhor_odd < 1,40` (retorno baixo; só compensa com premissas muito fortes).

**Gate (eliminatório — se falhar, não é oportunidade):** `edge > 0` **e** `n_casas ≥ 3`. Sem isso, nem calcula Score.

**Faixas de confiabilidade:**
- **≥ 60 — Alta** → vira oportunidade em destaque (hero/board).
- **40–59 — Média** → monitorada (aparece, sem destaque).
- **< 40 — Baixa** → não sinaliza como oportunidade (some do board; só no "explorar mercados").

**No front (o "por quê"):** as premissas que **dispararam** viram bullets de evidência (linguagem mastigada),
ordenadas por peso. As penalidades viram aviso ("⚠ só uma casa paga isso" / "⚠ odd muito alta").

**Fontes de dado (tabelas já materializadas em `futebol.*`):** `fact_team_season_stats` (médias gols casa/fora,
clean sheet, failed-to-score, forma), `fact_fixtures` (resultados/últimos 5, dias de descanso), `fact_fixture_stats`
(xG, finalizações, escanteios — Brasileirão), `fact_injuries_snapshot` + `fact_fixture_lineups_players` (desfalques),
`fact_standings_snapshot` (rank/pontos), odds (melhor/média/Pinnacle, `pin_open`=t24h, `pin_close`=t15m, n_casas, line_value),
`fact_predictions_api` (modelo da API).

---

## 2. Mercado: RESULTADO (1X2)
**Quando tem valor:** quando um lado é mais forte do que a odd sugere, e o contexto (mando, desfalque, tabela) reforça.
`S` = lado apostado (mandante ou visitante); `O` = adversário. Para empate, ver penalidade.

| Premissa | O que mede | Regra (threshold inicial) | Peso |
|---|---|---|---|
| `forca_mismatch` | ataque de S supera defesa de O | gols feitos de S no seu campo ≥ 1,4 **e** gols sofridos de O no campo dele ≥ 1,3 | **12** |
| `superioridade_xg` | qualidade real (não só gols) | (xG médio de S − xG sofrido de O) ≥ +0,3 *(Brasileirão)* | **8** |
| `mando` | manda com bom aproveitamento | S é mandante **e** % de pontos em casa ≥ 55% *(se visitante: aprov. fora ≥ 45% → peso 4)* | **8** |
| `desfalque_adversario` | O perde titular importante | O com ≥1 desfalque de titular **e** S sem desfalque de titular | **8** |
| `superioridade_tabela` | S claramente acima | diferença de rank ≥ 6 posições **ou** pontos/jogo de S ≥ 1,3× O | **6** |
| `forma` | S em alta *(peso baixo: duplica força)* | S com ≥ 3 vitórias nos últimos 5 | **5** |
| `h2h_favoravel` | histórico contra O | S venceu ≥ metade dos últimos confrontos diretos | **4** |

**Penalidades específicas:** `pick_empate` (−10, empate é a saída mais difícil) · `desfalque_proprio` (−15, S sem titular importante).

---

## 3. Mercado: GOLS (Over/Under, linha L)
**Quando tem valor:** Over → jogo aberto, dois times que atacam e/ou se defendem mal. Under → defesas firmes, jogo travado.

**Over L:**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `ataque_combinado` | os dois somam gols | gols feitos mandante(casa) + gols feitos visitante(fora) ≥ L+0,5 | **12** |
| `defesas_vazaveis` | os dois sofrem | gols sofridos mandante(casa) + sofridos visitante(fora) ≥ L | **10** |
| `xg_combinado_alto` | gols esperados altos | soma do xG médio dos dois ≥ L+0,3 *(Brasileirão)* | **8** |
| `ritmo_alto` | jogo de muita chance | média de finalizações/escanteios dos dois ≥ mediana da liga | **8** |
| `ambos_vazam` | poucos jogos zerados | clean sheet% dos dois < 35% | **6** |
| `historico_over` | recente goleador | ≥ 60% dos últimos 5 de cada foram Over L | **6** |
| `linha_subindo` | mercado puxando Over | odd do Over caiu de t24h→t15m | **6** |

**Under L (espelho):**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `defesas_firmes` | os dois seguram | gols sofridos mandante(casa) + visitante(fora) ≤ L−0,3 | **12** |
| `clean_sheets_altos` | costumam zerar | clean sheet% dos dois ≥ 40% | **10** |
| `xg_baixo_combinado` | poucas chances criadas | soma do xG médio dos dois ≤ L−0,3 | **10** |
| `ataques_fracos` | failed-to-score alto | algum dos dois passa em branco ≥ 35% dos jogos | **8** |
| `historico_under` | recente travado | ≥ 60% dos últimos 5 de cada foram Under L | **6** |
| `linha_descendo` | mercado puxando Under | odd do Under caiu de t24h→t15m | **6** |

**Penalidade específica:** `linha_extrema` (−10, quando L ≤ 0,5 ou L ≥ 4,5 — odd vira juice/longshot).

---

## 4. Mercado: HANDICAP ASIÁTICO (meia-linha; H = handicap na ótica do mandante)
**Quando tem valor:** quando a supremacia real difere do que a linha pede. Dois casos: favorito dando handicap (H negativo) ou azarão recebendo (cobrir +H).

**Favorito (ex.: Mandante −1,5):**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `supremacia` | S muito superior | diferença de rank ≥ 8 **ou** pontos/jogo ≥ 1,5× O | **12** |
| `tende_golear` | vence por margem | S com gols feitos ≥ 2,0 **e** sofridos ≤ 1,0 nos últimos jogos | **10** |
| `adversario_fragil_fora` | O leva gols fora | gols sofridos de O (fora) ≥ 1,6 | **8** |
| `mando_forte` | impõe em casa | aproveitamento em casa de S ≥ 60% | **6** |
| `sem_rodizio` | não tende a poupar | jogo importante p/ S, sem decisão na semana | **4** |

**Azarão (cobrir +1,5 etc.):**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `raramente_perde_por_2` | margem pequena | O perdeu por 2+ gols em < 30% dos jogos | **12** |
| `defesa_fora_solida` | segura fora | gols sofridos de O (fora) ≤ 1,1 | **10** |
| `favorito_irregular` | S não goleia | S venceu por 2+ em < 35% dos jogos | **8** |

**Penalidade específica:** `handicap_alto` (−12, quando |H| ≥ 2,5 — raramente confiável).

---

## 5. Mercado: AMBOS MARCAM (BTTS — Sim/Não)
**Quando tem valor:** Sim → dois ataques ativos e defesas vazáveis. Não → uma defesa forte ou um ataque que trava.

**Sim:**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `ambos_marcam` | os dois fazem gol quase sempre | failed-to-score% dos dois < 30% | **12** |
| `ataque_dos_dois` | ataque ativo dos dois | gols feitos médios dos dois ≥ 1,2 | **8** |
| `defesas_vazaveis` | os dois sofrem | clean sheet% dos dois < 35% | **8** |
| `historico_btts` | recente | ≥ 60% dos últimos 5 de cada com BTTS | **6** |

**Não (espelho):**
| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `defesa_forte` | uma defesa segura | clean sheet% de um dos times ≥ 45% | **12** |
| `ataque_trava` | um ataque fraco | failed-to-score% de um dos times ≥ 35% | **10** |
| `historico_seco` | recente | ≥ 60% dos últimos 5 de um dos times sem BTTS | **6** |

---

## 6. Mercado: DUPLA CHANCE (combina 2 das 3 saídas — ex.: "S ou empate")
**Quando tem valor:** aposta de proteção — valor quando o mercado **superprecifica a zebra** do lado descoberto.
**Gate diferente:** odd costuma ser baixa → aceitar `melhor_odd ≥ 1,25` e **não** aplicar `odd_juice` (<1,40); usar só `odd_muito_baixa` (<1,20).

| Premissa | O que mede | Regra | Peso |
|---|---|---|---|
| `lado_coberto_forte` | S dificilmente perde | reusa `forca_mismatch` + `superioridade_tabela` do 1X2 | **12** |
| `equilibrio_defensivo` | empate plausível | os dois com gols sofridos moderados e poucos jogos goleados | **8** |
| `adversario_limitado` | O raramente vence esse confronto | O com baixo aproveitamento e/ou histórico ruim vs S | **8** |
| `invicto_recente` | S não perde há vários jogos | S sem derrota nos últimos 5 | **6** |

**Penalidade específica:** `odd_muito_baixa` (−10, quando melhor_odd < 1,20).

---

## 7. Resumo do que o backend precisa entregar
Para cada jogo × mercado × resultado possível, o backend calcula:
1. `edge` (melhor odd vs de-vig do fechamento Pinnacle) → **PTS_VALOR**;
2. cada premissa de contexto (booleano + peso) → **PTS_PREMISSAS** + lista das que dispararam (pro "por quê");
3. corroboração (API + movimento sharp) → **PTS_CORROBORACAO**;
4. penalidades → subtrai;
5. **Score** final + faixa (Alta/Média/Baixa) + lista de evidências e avisos.

O front consome isso e mostra: a oportunidade, a frequência ("se paga em ~X de 10"), o Score, e os bullets do "por quê".
Pesos/thresholds aqui são **ponto de partida** — calibrar com dado real (RPS/calibração) e com o **CLV** quando o t15m acumular.

## 8. Disponibilidade de dado e tarefas de coleta (auditado em 2026-06-18)

Auditoria contra `futebol.*` (dev) + doc da API-Sports. **Maioria das premissas roda já** com dado das
duas competições; 2 dependem de coleta nova (endpoints existem, só não rodam para jogos futuros).

**✅ Disponível agora (Brasileirão + Copa):** `fact_team_season_stats` (gols casa/fora, clean sheet,
failed-to-score, forma) · `fact_standings_snapshot` (rank/pontos/forma) · `fact_fixtures` (resultados,
últimos 5, margens) · `fact_h2h` (949 jogos) · odds (edge, devig fechamento t15m, movimento, n_casas).

**🟡 Só Brasileirão (rico: 2024+2025 completos, 2026 ~177 jogos; Copa só ~12):** `fact_fixture_stats`
(xG `expected_goals` 100% preenchido; finalizações/escanteios) → premissas `superioridade_xg`,
`xg_combinado`, `ritmo_alto`. Copa pontua só nas premissas baseadas em gols (degrada graciosamente).

**🔧 Gaps = coleta (endpoints existem):**
- **`modelo_api_concorda`** — hoje só 3 jogos em `fact_predictions_api`. Endpoint `GET /predictions?fixture=ID`
  (independente do mercado: "bookmakers odds are not used"; atualiza 1×/h). **Tarefa:** coletar predictions
  de cada fixture futuro (1 call/jogo). Bônus: serve de **benchmark** do nosso modelo (1X2 e Gols).
- **`desfalque_*`** — hoje só histórico (até 31/05) e só Brasileirão. Endpoint `GET /injuries?fixture=ID`
  (ou `?date` / `?league&season`; tipos "Missing Fixture"=fora, "Questionable"=dúvida; atualiza 4×/h).
  **Tarefa:** coletar injuries dos fixtures futuros. **Proxy de importância** (pra não ficar binário):
  `GET /players?team&season` traz **rating de temporada + minutos**, ou `GET /fixtures/lineups` traz o
  **Start XI** (~20–40 min antes) — cruzar com o `player_id` lesionado pra pesar "titular importante".
- **Cobertura por liga:** checar o objeto `coverage` em `GET /leagues` (flags `predictions`, `injuries`,
  `statistics_fixtures`, `odds`). Copa provavelmente tem `predictions/injuries=false` → tratar ausência
  como "premissa não dispara", nunca como erro.

**Limitação estrutural (confirmada):** odds pré-jogo só 1–14 dias antes, histórico de 7 dias → **sem
backfill** de odds antigas; CLV só acumula pra frente (t15m). Backtest de calibração/RPS usa resultados
históricos (que temos); CLV vem com o tempo.
