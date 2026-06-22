# Metodologia — pesquisa de mercado e benchmark (por mercado)

> **Estado:** discovery / fundamentação. Antes de codar o modelo próprio (Pilar B), este doc
> levanta **como o mercado e a academia modelam cada mercado de aposta**, quais **variáveis**
> realmente movem o resultado, como se **valida** um modelo, e o que disso **temos vs. falta**.
> Vamos **por partes, um mercado por vez**. Mercado 1 = **Resultado (1X2)**.
> Relacionado: `docs/futebol-metodologia.md` (design), `docs/futebol-direcao-produto.md` (tese),
> `src/utils/futebol-value.ts` (Pilar A), `src/utils/futebol-tendencias.ts` (v0 do Pilar B).

## Por que este trabalho prévio
Pulamos pra execução com a metodologia ainda no nível de hipótese (Poisson de médias + devig). Antes
de seguir, precisamos ancorar em **benchmarks reais**: o que sharps/quants/academia fazem, com que
variáveis, e como provam que funciona. A conclusão geral da pesquisa: **nossa direção (Dixon-Coles +
xG + devig sharp) está certa, mas faltam o rigor de validação (RPS/CLV), a disciplina de benchmark
(bater o FECHAMENTO da Pinnacle, não casa mole) e o ranqueamento honesto das variáveis.**

---

# Mercado 1 — Resultado (1X2): casa / empate / fora

Mecânica: 3 saídas ordenadas (fora < empate < casa). É o mercado mais analisado e o mais difícil de
bater no preço sharp.

## 1.1 Como o mercado modela o 1X2 (abordagens + benchmark)

Duas filosofias + sistemas de rating que alimentam as duas:

| Abordagem | O que faz | Força p/ 1X2 | Fraqueza | Referência |
|---|---|---|---|---|
| **Poisson independente** | λ casa/fora → matriz de placar → soma 1X2 | baseline, gera TODOS os mercados de um λ só | subestima **empate** e placares baixos; estático | Maher (1982) |
| **Dixon-Coles** | Poisson + correção **τ** (placares baixos) + **decaimento temporal** | **padrão de fato**; corrige o empate; pega forma | só patcha placares pequenos; 1 mando global; só gols | Dixon & Coles (1997) |
| **Poisson bivariado** | adiciona correlação entre os gols + inflação da diagonal (empates) | corrige empate de forma teoricamente mais limpa | correlação real é baixa → ganho marginal vs DC | Karlis & Ntzoufras (2003) |
| **Probit/logit ordenado** | regressão direta no 1X2 (sem matriz) | otimiza o que se aposta; aceita features arbitrárias | só dá 1X2 (não gera O/U, placar) | Goddard (2005); Koopman & Lit (2015) |
| **Ratings** (Elo, **pi-ratings**, SPI, clubelo) | strength escalar → mapeia p/ 1X2 | features baratos, online, fortes; pi-ratings > Elo | rating único não tem mecanismo nativo de empate | Hvattum & Arntzen (2010); Constantinou & Fenton (2013) |
| **Bayesiano/híbrido** (pi-football, Dolores) | engine estatístico + conhecimento causal (lesão, motivação) | feito **pra bater o mercado**; lida com dado esparso | engenharia de conhecimento cara; difícil escalar | Constantinou, Fenton & Neil (2012); Constantinou (2019) |

**Consenso:**
1. **Nenhum modelo domina em acurácia; as diferenças são pequenas.** Goddard mostrou que goals-based
   (λ→matriz) e ordenado-direto empatam no 1X2. A escolha é por **necessidade de produto**, não acurácia.
2. **O núcleo recomendado é goals-based (família Dixon-Coles):** um engine só cospe 1X2 **e** todos os
   derivados (O/U, BTTS, handicap, placar) — essencial pra um produto multi-mercado.
3. **Ratings (pi-ratings/clubelo) são o melhor "tijolo barato"** — ótimos como feature/prior, fracos sozinhos.
4. **Pra bater o mercado é preciso informação que o mercado subprecifica.** Modelos estatísticos puros
   batem benchmarks ingênuos mas **perdem pro fechamento da casa**. Quem lucrou (DC explorando mercado
   inicial; Bayesianos com sinal causal) adicionou informação além de gols históricos.

## 1.2 Variáveis que movem o 1X2 (ranqueadas por força de evidência)

| # | Variável | Evidência | Já está no preço? | Como quantificar |
|---|---|---|---|---|
| 1 | **Força ataque/defesa via xG/xGA** | **Forte** (a fundação) | é o nosso modelo | xG por jogo → taxas do time → λ Poisson |
| 2 | **Odd de fechamento (Pinnacle) como feature** | **Forte** (o benchmark) | é a referência | de-vig do fechamento |
| 3 | **Mando de campo** | **Forte, mas caindo / varia por liga** | sim | termo de mando por liga/time, recalibrado pós-2020 |
| 4 | **Forma via decaimento temporal / ratings dinâmicos** | **Moderada** (já capturada por bom rating) | sim | pesos com meia-vida; pi-ratings/Elo |
| 5 | **Disponibilidade de titular (lesão/suspensão)** | **Moderada→Forte** p/ craque | quase (reage rápido à escalação) | minutos × qualidade do jogador |
| 6 | **Fadiga / descanso / congestionamento** | **Moderada** | parcialmente | dias de descanso, jogo de meio de semana, viagem |
| 7 | **Motivação / importância do jogo** | **Moderada** (situacional; ponto cego) | parcialmente | flags de contexto (rebaixamento, vaga, jogo "morto"), rotação |
| 8 | **Tendência de árbitro** | **Moderada** (atua via mando) | sim | embutir no termo de mando |
| 9 | **Promovido / efeito novo técnico** | **Fraca→Moderada** | sim / ilusório | prior p/ recém-chegado; ignorar a maior parte do "efeito técnico" |
| 10 | **Clima / gramado / altitude** | **Fraca** (nicho) | quase | flags de condição (mais p/ totais que 1X2) |

Pontos-chave:
- **xG > gols crus**: gol é raro (~2,7/jogo) → variância alta; xG estabiliza mais rápido e prevê melhor.
- **Mando encolheu** (experimento natural dos jogos sem público na COVID — queda significativa, parte
  via viés de árbitro que some sem torcida). Recalibrar pós-2020.
- **"Forma" em grande parte DUPLICA o rating** — `últimos 5` cru adiciona pouco se já há rating ponderado
  no tempo e ajustado por adversário. (Implicação direta pro nosso "4 vitórias nas últimas 5".)
- **Lesão de craque** move, mas a casa repõe rápido na notícia de escalação → edge mora em **casa mole
  lenta** ou em ausência provável **antes** da escalação.
- **O empate é a saída mais difícil**: ninguém "torce" pelo empate, a prob fica numa faixa estreita
  (~22–28%) e quase não varia com a força; Poisson ingênuo prevê quase nenhum. A correção τ do
  Dixon-Coles existe exatamente pra isso.

## 1.3 Como se VALIDA um modelo de 1X2 (o que torna honesto)

- **RPS (Ranked Probability Score)** — métrica-padrão no futebol (Constantinou & Fenton 2012): recompensa
  acertar a **ordem** (errar pra empate pune menos que errar pro lado oposto). *Contestado* por
  Wheatcroft (2021), que defende a log-loss. → **usar RPS como principal, reportar log-loss junto.**
- **Calibração (curva de confiabilidade)**: quando dizemos 30% de empate, empata ~30%? É o que o value
  bet depende. **Métrica complementar obrigatória.**
- **Benchmark contra o FECHAMENTO da Pinnacle (de-vig)**: a barra real é bater a linha de **fechamento**
  (não a de abertura nem casa mole). Pinnacle de-vig ≈ 0,997 de correlação com a frequência real.
- **CLV (Closing Line Value)** = **KPI-rei**. Pegar preço melhor que o fechamento é o sinal mais estável
  de edge — mais confiável que ROI de curto prazo. **Instrumentar desde o dia 1** (já temos t15m chegando).

## 1.4 O que temos vs. o que falta (mapa pro nosso dado)

**Temos (no BQ → `futebol.*`):**
- **xG/xGA por jogo** (validado no Brasileirão) → base do λ. ✅
- Gols, resultados, forma, **splits casa/fora**, H2H, classificação. ✅
- **Desfalques** (`fact_injuries_snapshot`) + escalações (`fact_fixture_lineups_players`). ✅ (falta peso por jogador)
- **Odds forward** com janelas t24h/t1h/**t15m** (fechamento) + devig Pinnacle. ✅ (CLV vira possível quando t15m acumular)
- **Predictions da API** como benchmark/segunda opinião. ✅

**Falta / fraco:**
- **Sistema de rating próprio** (pi-ratings/Elo) — não temos; é tijolo barato e forte. ⬜
- **Peso de jogador** (minutos × qualidade) pro ajuste de desfalque — hoje seria binário. ⬜
- **Descanso/congestionamento** — **derivável** dos próprios fixtures (dias desde o último jogo). 🟡
- **Importância/motivação** — derivável de classificação + rodada (rebaixamento, vaga, jogo morto). 🟡
- **xG fora do Brasileirão** (Copa/seleções = pouca base) → modelo fraco lá; assumir e sinalizar. ⬜
- **Mando por liga recalibrado** (pós-2020) — hoje usamos fator genérico. 🟡

## 1.5 Recomendação para o 1X2 (a fechar com o time)
1. **Núcleo:** Dixon-Coles (Poisson + correção de placar baixo + decaimento temporal), λ a partir de
   **xG-based** ataque/defesa + **mando** + **ajuste de escalação/desfalque**.
2. **Ratings como prior/feature** (pi-ratings/clubelo-style) — ancora times com pouca base.
3. **Valor:** só sinalizar onde **batemos a prob de-vig do FECHAMENTO da Pinnacle** (não casa mole).
4. **Validação:** RPS + log-loss + **calibração**; **CLV** como KPI-rei. Nada de expor "valor" de modelo
   não calibrado (rotular estimativa até validar).
5. **Não reinventar o que o mercado já precifica** (forma crua, efeito técnico): foco onde há sinal
   subprecificado (escalação cedo, motivação/rotação, dado local que a casa global ignora).

---

# Próximos mercados (a pesquisar, por partes)
- **Gols (Over/Under)** — sai do mesmo λ/matriz; variáveis: ritmo, estilos, mando, clima; benchmark de totais.
- **Handicap asiático** — supremacia (distribuição de i−j); relação com o 1X2; linha de quarto/push.
- **Ambos marcam (BTTS)** — P(i≥1 e j≥1); correlação com O/U e força ofensiva/defensiva.
- **Dupla chance** — derivado do 1X2 (combina 2 das 3 saídas).
- (Fora de escopo por ora: **cartões e escanteios** — sem odds na base.)

## Referências principais
- Maher (1982); **Dixon & Coles (1997)**; Karlis & Ntzoufras (2003); Goddard (2005); Koopman & Lit (2015).
- **Ratings:** Hvattum & Arntzen (2010, Elo); **Constantinou & Fenton (2013, pi-ratings)**; 538 SPI; clubelo.com.
- **Bayesiano:** Constantinou, Fenton & Neil (2012, pi-football); Constantinou (2019, Dolores).
- **Validação:** Constantinou & Fenton (2012, RPS); Wheatcroft (2021, contra RPS); Štrumbelj (2014, odds→prob).
- **Mercado/valor:** Levitt (2004); Kuypers (2000); Miller & Davidow, *The Logic of Sports Betting* (CLV);
  Pinnacle (margem/fechamento, ~0,997); estudos de mando na COVID (PMC8670806).
