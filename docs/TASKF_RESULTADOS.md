# Task [F] — Resultados

Documento vivo. Cada ticket da [issue #49](https://github.com/tech-lamjav/analytics-engineering/issues/49)
acrescenta a sua seção aqui. O SQL que produz cada número está em `dbt_futebol/analyses/`.

Os resultados moram neste arquivo, e não no cabeçalho das análises, para que o SQL mude quando a
lógica muda e não quando os números mudam. Mesmo padrão do `TASK01_RESULTADOS.md`.

---

## Ticket #51 — Célula `base` ponta a ponta

`analyses/taskf_teste2.sql` + `analyses/taskf_reconciliacao_01.sql` · execução 2026-08-12 13:34
UTC · commit `fa98ceb` · dataset `futebol_taskF`

A célula que não muda nada — escopo na competição do jogo, recorte na temporada corrente — vai
ponta a ponta: camada de premissas materializada no dataset de medição, Teste 2 rodando por cima,
saída com coluna de célula, e comparação contra o Teste 2 publicado da [0.1]. É o tracer bullet: o
caso em que a resposta já é conhecida, para o caminho inteiro ser exercitado antes de as células
que mudam alguma coisa terem o direito de significar algo.

### Veredito

**38 das 39 premissas reproduzem o publicado EXATAMENTE**, em todos os campos comparáveis — até
11 campos por premissa nas 15 de varredura completa. A única divergência é `linha_descendo`, com
2 linhas de 405 e ≤ 0,2 pp, e ela sai marcada `INVESTIGAR`, não acomodada pela tolerância.

`EXATO` aqui exige que **todos** os campos publicados tenham batido, e não só os que a régua em pp
olha: contagem, prob justa média, acerto médio, jogos médios, % de amostra curta e os dois pesos
entram na mesma conta (`campos_divergentes_fora_da_regua`).

O caminho está certo. As células `escopo`, `recorte` e `ambos` podem ser medidas.

### O universo congelado não é um corte por dia

`analyses/taskf_universo_congelado.sql`

| variante | período | jogos | vs publicado |
|---|---|---|---|
| `A_sem_corte` — o que a [0.1] rodou | 16/06 → 12/08 | 228 | +59 |
| `B_ate_0408_por_dia` — `DATE(kickoff) <= '2026-08-04'` | 16/06 → 04/08 | **178** | **+9** |
| `C_universo_congelado` — `kickoff < 04/08 12:00 UTC` | 16/06 → 04/08 | **169** | **0** |
| `D_teto_alternativo` — o mesmo com teto às 06:00 UTC | 16/06 → 04/08 | 169 | 0 |

O corte ingênuo por dia devolve 178, não 169. Os 9 excedentes são exatamente os jogos de 04/08
com kickoff a partir das 16:00 UTC — 8 da Champions e o da Copa do Brasil das 22:30. No dia
inteiro **um único** jogo começou antes disso, o das 00:00 UTC, e ele está nos 169.

A explicação é que a [0.1] **rodou sem corte congelado**: o teto dela é o instante em que a query
executou, e o `janela_fim = 04/08` publicado é só o `MAX(DATE(kickoff))` que saiu daquilo. Os
nove jogos da noite ainda não tinham sido disputados. Reproduzir a janela publicada exige,
portanto, um **instante**, e não uma data.

O teto ficou às 12:00 UTC, no meio do vão vazio: entre o fim do jogo das 00:00 (~02:00) e o
kickoff das 16:00 não existe jogo nenhum na base. A variante D mede a outra ponta da faixa e dá o
mesmo resultado — o corte é **robusto a catorze horas de incerteza**, e não um valor calibrado até
o número bater. As duas datas publicadas continuam verdadeiras: o último jogo incluído é mesmo de
04/08.

O piso de 16/06 é no-op — a coleta de odds é forward-only e começou nesse dia, então A e B já
devolvem `janela_ini = 16/06` sozinhos. Fica declarado assim mesmo, para a janela não depender de
um efeito colateral da coleta.

**Composição dos 169:** copa_mundo 79 (46,7%), serie_b 39 (23,1%), brasileirao 28 (16,6%),
sudamericana 15 (8,9%), copa_do_brasil 8 (4,7%). Os 46,7% da Copa do Mundo batem com os "47% da
amostra" que a spec #49 atribui a ela, e Copa do Brasil + Sudamericana somam 23, contra os "cerca
de 24 jogos" que a spec estima que o merge recupera.

⚠️ **A Champions não tem UM jogo no universo primário.** Os únicos jogos dela na janela são os 8
de 04/08 à noite, e o corte os remove. A pergunta da spec sobre a fase classificatória da
Champions (user story 24) não tem amostra nenhuma no universo congelado — quem for executar a
#58 precisa saber disso antes de desenhar a resposta, porque ela terá de sair do universo
estendido ou de lugar nenhum.

### A tolerância, declarada

> **Tolerância: 0,5 pp de diferença absoluta, em qualquer piso, e SÓ para `linha_subindo` e
> `linha_descendo`.**

Ela vale para essas duas e para mais nenhuma. As outras 37 premissas leem fixture, estatística ou
tabela — insumos determinísticos sobre um universo congelado — e para elas a régua é **igualdade
exata**. `linha_subindo` e `linha_descendo` são as únicas que comparam preço com preço: acendem
quando a média das probabilidades implícitas de todas as casas sobe de t24h para t15m.

O valor 0,5 pp foi declarado **antes** de medir, calibrado pelo que o repositório já sabia:
`docs/TASK01_RESULTADOS.md` registra que o mercado de Gols anda 0,2–0,4 pp entre execuções sem
que nada mude, e que isso já produziu caça a bug inexistente.

### ⚠️ A justificativa da tolerância não se aplica a uma janela congelada

Este é o achado do ticket que ninguém tinha escrito.

A tolerância existe porque "`linha_subindo`/`linha_descendo` leem odds ao vivo e viram sozinhas
entre builds". Isso é **verdade no board vivo e falso num universo congelado do passado**: a
coleta de odds é forward-only e para no apito. Medido — para os 169 jogos congelados há **zero
capturas com data posterior a 04/08** em qualquer das três janelas de fechamento:

| janela de coleta | linhas | jogos | última coleta | coletadas após 04/08 |
|---|---|---|---|---|
| t15m | 34.691 | 157 | 02/08 | **0** |
| t1h | 37.135 | 168 | 02/08 | **0** |
| t24h | 34.854 | 162 | 03/08 | **0** |

O insumo de `linha_caiu` é imóvel. A consequência foi levada até o fim, e não só anotada: a
reconciliação **mede** o mecanismo antes de invocá-lo (`capturas_apos_o_teto`), e como ele é zero,
**nenhuma linha se classifica como `deriva_de_odds`**. `linha_descendo` sai como `INVESTIGAR`, que
é o veredito honesto — a régua não é usada para acomodar uma divergência cuja causa a régua não
cobre, que é exatamente o que o critério do ticket proíbe.

A régua de 0,5 pp continua declarada e continua valendo. Ela volta a ter mordida no **universo
estendido** da spec, que alcança o presente e onde `capturas_apos_o_teto` deixa de ser zero.

### A correção da spec #22 tem footprint ZERO — medido, não suposto

A spec #22 corrigiu o de-vig em **05/08**, um dia *depois* de a [0.1] publicar. Os números
publicados ainda continham as linhas de conjunto de saídas incompleto; os medidos já não contêm.
Era a divergência de outra origem mais provável do ticket, e a hipótese de partida era que ela
atingiria o BTTS, cujo benchmark preferido é justamente o consenso.

**Ela não atinge nada.** Duas medições:

| mercado | linhas na janela | conjunto incompleto | destas, com preço Pinnacle |
|---|---|---|---|
| 1X2 (1) | 507 | **0** | — |
| Handicap (4) | 6.624 | 58 | **0** |
| Gols (5) | 6.871 | 179 | **0** |
| BTTS (8) | 338 | **0** | — |
| Dupla Chance (12) | 507 | **0** | — |

1X2, BTTS e Dupla Chance não têm nenhuma linha degenerada na janela. As 237 que existem estão em
Handicap e Gols, e **nenhuma delas tem preço da Pinnacle em janela nenhuma** — são consenso puro.
Como o benchmark preferido desses dois mercados é o sharp, a correção não alcança nenhuma das 39
linhas comparadas.

O teste do "nenhuma tem Pinnacle" foi **falsificado contra um controle**, porque um join quebrado
daria zero do mesmo jeito: nas linhas *não* degeneradas o mesmo join casa 3.370 de 6.566 no
Handicap e 3.054 de 6.692 no Gols. O zero é real.

Esta conta **mora dentro da reconciliação**, na coluna `linhas_da_22_no_preferido`, e não numa
query de rascunho: a regra de alcance é por mercado (no BTTS o preferido é o consenso, então
qualquer linha nulada o alcança; nos outros quatro o preferido é ancorado na Pinnacle, então só
alcança linha que a Pinnacle precificava). Os cinco mercados dão **0**. Se um dia der diferente —
no universo estendido, ou numa janela nova —, o rótulo aparece sozinho e com o número ao lado.

Isto confirma empiricamente a afirmação "TODAS consenso" que o cabeçalho do `task01_base()` faz
sobre as 172 linhas, e a estende: a correção é **invisível ao benchmark preferido**, em todos os
cinco mercados.

### A única divergência: `linha_descendo`

| campo | publicado | medido | delta |
|---|---|---|---|
| n (piso 0) | 405 | 403 | **−2** |
| n (piso 5) | 215 | 213 | **−2** |
| diferença piso 0 | +3,1 | +3,2 | +0,1 |
| diferença piso 5 | +5,3 | +5,5 | +0,2 |
| diferença piso 10 | +5,3 | +5,5 | +0,2 |
| a odd dava (piso 0) | 53,0 | 52,9 | −0,1 |
| aconteceu (piso 0) | 56,0 | 56,1 | +0,1 |
| jogos médios | 10,3 | 10,3 | **0** |
| % amostra curta | 46,9 | 47,1 | +0,2 |
| peso k50 / k0 | 2,74 / 3,08 | 2,85 / 3,21 | +0,11 / +0,13 |

São **duas linhas de aposta**, e não uma mudança de comportamento: 0,5% da amostra da premissa.
As duas tinham `min_jogos >= 5` (saíram também do piso 5) e não eram de amostra curta — é por isso
que `% amostra curta` **sobe** ao removê-las e `jogos médios` não se move.

`linha_subindo`, que é o mesmo sinal do lado Over, reproduz a diferença publicada **exatamente**
(−1,5). O doc não publica o `n` dela, então a superfície de comparação é menor.

**O que foi descartado, com medição:**

1. **Correção #22** — descartada. As linhas removidas por ela são consenso puro; `linha_descendo`
   publicado é sharp. Nenhuma linha com Pinnacle foi removida em mercado nenhum.
2. **Deriva de odds** — descartada. Zero capturas posteriores a 04/08 para os 169 jogos.
3. **Mudança de código nos modelos do caminho** — descartada. Entre o commit que publicou a [0.1]
   (`e6bc54e`) e este, os únicos modelos alterados no caminho de Gols são o `int_futebol_odds_devig`
   (só a regra de emissão da #22) e dois `CASE` de slug em `fact_fixtures`/`fact_odds_snapshot`
   que acrescentam Bundesliga, Ligue 1 e Primeira Liga — nenhuma das três está na janela.
   `int_futebol_premissas_ou` não foi tocado.
4. **`int_futebol_team_form_pit`** — descartada. A Costura A passou nesta execução: a saída no
   default é igual, linha a linha, ao baseline congelado antes das vars.

5. **Dedup não-determinístico do `fact_odds_snapshot`** — descartada, e vale registrar porque a
   suspeita era boa. O dedup é `ROW_NUMBER() OVER (PARTITION BY fixture, casa, mercado, outcome,
   janela ORDER BY loaded_at DESC)` — **sem critério de desempate**. Duas capturas com o mesmo
   `loaded_at` e odds diferentes trocariam de vencedora entre builds *sem dado novo nenhum*, que
   é exatamente a assinatura procurada. Medido nos 169 jogos, mercado de Gols: **108.196 chaves,
   zero empates no topo, zero empates que mudariam a odd**. A porta existe, mas não passou
   ninguém por ela nesta janela. Fica anotado como risco latente do modelo, não como causa.

**O que sobra**, e fica registrado como resíduo aberto: o `fact_odds_snapshot` é reconstruído do
NDJSON do GCS a cada build, e o `collection_date` vem do dado, não do instante da ingestão. Um
arquivo que tenha chegado ao bucket depois de 04/08 carimbado com data anterior entraria na tabela
sem aparecer no teste 2 acima — e uma casa a mais na média de t15m basta para virar uma linha
marginal. Das hipóteses levantadas é a única que sobrevive, e ela é **candidata, não causa
provada**. Todas as sobreviventes moram no mesmo lugar: a reconstrução do `fact_odds_snapshot` a
cada build.

**Por que isso não invalida a medição:** o resíduo é 2 linhas em 1 premissa de 39, ele move a
diferença em 0,2 pp, e ele afeta as quatro células **da mesma forma** — as quatro leem o mesmo
`fact_odds_snapshot`. A [F] compara células entre si; um viés comum às quatro cancela na
comparação. Ele importaria se alguém reaproveitasse o baseline publicado da [0.1] como célula
`base`, que é exatamente o que a spec proíbe.

⚠️ **Mas "o mesmo `fact_odds_snapshot`" é uma condição, não um dado.** Ela só vale se a ancestria
for construída **uma vez** e as células seguintes rebuildarem só os nós que respondem às vars — o
PIT e os cinco modelos de premissas. Rebuildar com `+` por célula reconstrói o
`fact_odds_snapshot` do NDJSON a cada uma, e aí esta mesma variação de 2 linhas passa a existir
*entre* as células, onde ela deixa de cancelar e vira efeito de escopo aos olhos de quem lê. O
cabeçalho do `analyses/taskf_teste2.sql` traz as duas fases separadas por isso. Para a #55: a
forma verificável de "mesma execução" é `fact_odds_snapshot.dbt_loaded_at` anterior aos quatro
`medido_em`.

### O que a medição produziu além da reconciliação

A tabela `futebol_taskF.taskf_teste2` tem 60 linhas na célula `base`: as **39** do benchmark
preferido (`usado_para_peso = true`) mais 21 de consenso do Handicap e do Gols, que não pesam mas
ficam visíveis. Duas coisas nela não existiam antes:

- **O piso 3**, que a spec #49 pede e a [0.1] não tinha, nas 39 linhas.
- **Os pisos 5 e 10 das 19 premissas de peso zero.** A [0.1] publicou só a diferença no piso 0
  delas, em parágrafo corrido. Agora há varredura completa — e ela mostra coisas que valem para a
  [B], como `sem_rodizio` medindo −2,7 **idêntico nos quatro pisos** (n=188 em todos), o que é a
  assinatura de uma premissa que só acende em jogo com histórico longo.

### Reprodução

```bash
cd dbt_futebol

# 1. a ancestria inteira, UMA vez para as quatro células (na base as vars ficam no default)
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
  --select +int_futebol_premissas_1x2 +int_futebol_premissas_ou +int_futebol_premissas_ah \
           +int_futebol_premissas_btts +int_futebol_premissas_dc +int_futebol_corroboracao

# 2. o Teste 2 com coluna de célula
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_teste2 \
  --vars '{taskf_git_sha: fa98ceb}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

# 3. a reconciliação contra o publicado
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_reconciliacao_01
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_reconciliacao_01.sql

# 4. a transcrição dos números publicados confere com o doc que os publicou
.venv/bin/python3 scripts/confere_taskf_publicado_01.py
```

O `dbt build` do passo 1 fecha com **10 ERROR e 3 SKIP**, todos em testes de `relationships` cuja
contraparte (`dim_teams`, `dim_players`, `fact_fixture_lineups`, `fact_fixture_events`) está fora
da ancestria da medição e por isso não existe no dataset. Nenhum modelo falha; os 25 saem
`success`, e passam a Costura A, as guardas de grão dos cinco modelos de premissas — soltar
`competition_id` de um join é o caminho natural para fan-out, e é isso que elas pegam — e as duas
guardas do conjunto de saídas do de-vig.

---

## Ticket #53 — Célula `escopo`: todas as competições, temporada mantida

`analyses/taskf_teste2.sql` + `taskf_pit_por_celula.sql` + `taskf_monotonicidade_escopo.sql` +
`taskf_familia_e_mecanismo.sql` + `taskf_delta_celulas.sql` · execução 2026-08-12 16:50 a 16:59
UTC · commit `09328b0` · dataset `futebol_taskF`

A primeira célula que produz número novo. O escopo do histórico solta a competição do jogo e
passa a contar todas as competições do time; o recorte continua sendo a temporada corrente. As
duas células — `base` e `escopo` — foram materializadas e medidas nesta mesma execução, sobre a
mesma construção dos fatos.

### Veredito

O eixo de escopo funciona e o efeito é grande. **30,6% dos pares (jogo, time) ganham histórico**,
com média de 8,1 partidas a mais quando ganham e máximo de 48. O universo que satisfaz o piso de
5 sobe de **69 para 92 jogos** sem descartar nada, e a amostra curta média das 39 premissas cai de
**45,5% para 34,5%**. Zero violações de monotonicidade, zero divergência de chave, grão verde nas
duas células.

A quebra por família é **degenerada por composição do universo, e isso é o achado**: as 169
partidas da janela congelada são 100% de competições de ano-calendário. A família split-year não
tem uma única partida medida — nem, como se mediu abaixo, um único jogo que pudesse servir de
FONTE de histórico. Ela está **sem amostra**, e não com efeito nulo.

### As duas células, na mesma execução e no mesmo universo

| célula | eixos | jogos | linhas | janela | carimbo do PIT | Teste 2 |
|---|---|---|---|---|---|---|
| `base` | da_competicao / temporada | 169 | 8.567 | 16/06 → 04/08 | 16:50:12 | 16:52:24 |
| `escopo` | todas / temporada | 169 | 8.567 | 16/06 → 04/08 | 16:58:51 | 16:59:04 |

"Mesma execução" aqui é o que a #51 definiu como forma verificável: o
`fact_odds_snapshot.dbt_loaded_at` é **13:24:15**, anterior aos quatro carimbos. As duas células
leram a MESMA construção dos fatos — a ancestria não foi reconstruída entre elas, e nenhum build
de célula usou `+`.

⚠️ A `base` foi **re-medida**, e não reaproveitada da #51. A spec proíbe reaproveitar baseline, e
havia motivo extra: a #52 alterou os cinco modelos de premissas entre uma medição e outra.

### A re-medição da `base` reproduz a #51, e as três exceções são empates de arredondamento

Das 60 linhas × ~40 campos, **três campos divergiram**, todos de 0,1 pp:

| premissa | campo | #51 | #53 | valor exato |
|---|---|---|---|---|
| `adversario_limitado` (DC) | `aconteceu_p5` e `aconteceu_p10` | 68,8 | 68,7 | 55/80 = **68,75%** |
| `raramente_perde_por_2` (AH consenso) | `aconteceu_p10` | 96,2 | 96,3 | 308/320 = **96,25%** |

Os dois são **empates exatos** de `ROUND(·, 1)` — medidos em aritmética inteira, não inferidos. O
`AVG` do BigQuery acumula em ponto flutuante e a ordem da acumulação depende do layout físico da
tabela, que mudou quando os modelos foram reconstruídos; num empate, o último bit decide o lado.
Duas execuções consecutivas do mesmo script, sem rebuild no meio, dão resultado **idêntico** — a
variação não é do motor, é da reconstrução.

Isso não é a deriva de odds da tolerância declarada na #51 (aquela continua valendo zero nesta
janela) nem mudança de comportamento da #52. A #52 foi verificada como no-op de forma direta: o
SQL **compilado** dos seis modelos no default é byte a byte idêntico ao do commit `fa98ceb`, que
produziu os números da #51.

**Para quem for medir as células da #54:** diferenças de 0,1 pp em `aconteceu`/`a_odd_dava` cujo
valor exato caia num empate `x,x5` não são evidência de nada. Elas não alcançam a `diferenca`, que
é calculada dos valores não arredondados.

### A invariante: soltar a competição só acrescenta

`analyses/taskf_monotonicidade_escopo.sql` · veredito **OK**

| | |
|---|---|
| pares (jogo, time) em cada célula | **21.054 = 21.054** |
| só na `base` / só na `escopo` | **0 / 0** |
| pares com `escopo` < `base` (violações) | **0** |
| pares com ganho | **6.434 (30,6%)** |
| ganho médio quando ganha / máximo | **8,13 / 48** |
| `played_total` médio | 11,29 → **13,77** |
| `base` conferida contra o baseline congelado | 20.846 pares, **0 divergências** |

As três conferências são independentes e cada uma fecha um buraco diferente:

- **Chaves nos dois sentidos.** A guarda de grão dos modelos pega fan-out e **não** pega perda de
  linha — um par que sumiu deixa a tabela mais única, não menos. Aqui as duas pontas são contadas.
- **Não-vacuidade.** 6.434 pares com ganho é o que separa "o eixo funcionou" de "as duas linhas do
  carimbo contêm o mesmo dado porque a ordem de execução errou". Zero ganho seria erro de ordem, e
  não efeito nulo.
- **Contra o baseline.** O lado `base` do carimbo bate, par a par, com a saída congelada ANTES de
  as vars existirem, nas 20.846 linhas cujas partições têm insumo idêntico ao do congelamento
  (mesma restrição da Costura A).

### Onde o histórico aparece, competição a competição

`analyses/taskf_familia_e_mecanismo.sql` — pares dos 169 jogos do universo congelado

| competição | família | jogos | pares | com ganho | ganho médio | ganho máx |
|---|---|---|---|---|---|---|
| copa_mundo | ano-calendário | 79 | 158 | **0 (0%)** | 0,00 | 0 |
| serie_b | ano-calendário | 39 | 78 | 55 (70,5%) | 2,23 | 5 |
| brasileirao | ano-calendário | 28 | 56 | 56 (100%) | 5,75 | 12 |
| sudamericana | ano-calendário | 15 | 30 | 24 (80%) | 9,17 | 22 |
| copa_do_brasil | ano-calendário | 8 | 16 | 16 (100%) | **24,25** | 28 |
| **total** | | **169** | **338** | **151 (44,7%)** | 3,43 | 28 |

O gradiente é o mecanismo inteiro numa coluna: quanto menor a competição no calendário do time,
maior o que ela ganha. A Copa do Brasil empresta 24 partidas por par; o Brasileirão, que já é a
competição principal, ganha ~6 (as copas dele); e a **Copa do Mundo ganha exatamente zero** — o
deserto dela é real, seleções não jogam outra coisa na base. Ela é 46,7% do universo.

### O piso de amostra: 69 → 92 jogos, sem jogar nada fora

| piso | `base` | `escopo` | jogos que passam a satisfazer |
|---|---|---|---|
| 3 | 90 | **113** | +23 |
| 5 | **69** | **92** | **+23** |
| 10 | 67 | 76 | +9 |

Os 23 que cruzam o piso 5 são exatamente **as 15 partidas de Sudamericana e as 8 de Copa do
Brasil** — as duas competições que o piso removia inteiras. É o número que a spec #49 estimava
("cerca de 24 jogos"). A Copa do Mundo continua com 2 jogos acima do piso 5, os mesmos de antes.

⚠️ **Isto não resolve a amostra curta, e o número diz quanto.** No piso 5 o universo vai de 41%
para 54% dos 169 jogos. Os 77 que continuam de fora são 79 da Copa do Mundo menos os 2 que já
passavam — ou seja, o resto do universo é **a Copa do Mundo inteira**.

A célula `base` reproduz aqui, competição a competição, a tabela de piso publicada na [0.1]
(`docs/TASK01_RESULTADOS.md`): piso 5 = 69 jogos (Brasileirão 28, Série B 39, Copa do Mundo 2) e
piso 10 = 67 (Brasileirão 28, Série B 39). ⚠️ A spec #49 trata esses dois números como divergência
entre o ticket e o doc ("o ticket diz 69; o número publicado é 67") — **não é divergência**: são
duas linhas da mesma tabela publicada, o 69 é do piso 5 e o 67 é do piso 10, e as duas se
reproduzem exatamente. Quem executar a [B] não precisa reabrir isso.

E o `min_jogos` derivado do carimbo bate com o do próprio pipeline: contado em `apostas` na célula
`escopo`, dá os mesmos 113 / 92 / 76.

### A quebra por família — e por que ela é degenerada nesta janela

A classificação não é uma lista digitada; sai do calendário (`macros/taskf_familia_competicao.sql`):
uma competição é split-year quando a MESMA `season` atravessa a virada do ano civil, em qualquer
das temporadas observadas. Ela lê **todo** o `fact_fixtures` — dentro da janela congelada a
Champions só tem as qualificatórias de julho/agosto e sairia classificada como ano-calendário,
exatamente ao contrário.

| família | competições | jogos no universo | linhas |
|---|---|---|---|
| ano-calendário | brasileirao, copa_do_brasil, copa_mundo, libertadores, serie_b, sudamericana | **169 (100%)** | 8.567 |
| split-year | bundesliga, champions_league, la_liga, ligue_1, premier_league, primeira_liga, serie_a_ita | **0** | **0** |

Consequência aritmética, não interpretação: a coluna `ano_calendario` da quebra **é** a tabela
inteira das 39 premissas, campo a campo, porque a partição contém 100% das linhas. A coluna
`split_year` é **vazia**.

⚠️ **E isso vale para as QUATRO células, não só para esta.** A partição por família é propriedade
do UNIVERSO, e o universo é o mesmo nas quatro por construção — é a primeira invariante da Costura
B. Os eixos mudam o histórico que cada jogo carrega, nunca quais jogos são medidos. Então
`split_year = 0` já está decidido para `recorte` e `ambos` (#54) e para o entregável (#59) no
universo primário: **não há por que construir máquina de quebra por família por premissa**, ela
teria uma coluna cheia e uma vazia em qualquer célula. A família só volta a ser uma dimensão com
duas pontas no **universo estendido** (#56), que alcança o presente e onde as europeias já jogaram.

(A classificação é por slug de competição, e `n_competition_ids = 1` nas 13 — nenhum slug agrega
dois IDs hoje, então a quebra não tem como duplicar jogo.)

**E a família split-year não entra nem como FONTE de histórico.** Medido: dos times que disputam
os 169 jogos do universo, **zero** têm qualquer partida numa competição split-year sob o mesmo
rótulo de `season`. Não é só que não há jogo split-year medido — não há jogo split-year que o
merge pudesse emprestar.

### ⚠️ Sem amostra não é efeito nulo (e a janela é o pior lugar possível para medir isto)

A leitura que **não** pode ser tirada daqui é "juntar campeonato não faz nada pelas europeias". A
janela congelada é 16/06 a 04/08 e cai **inteira na virada de temporada**: nas split-year o rótulo
de `season` muda no meio do ano, e o eixo de escopo não toca o filtro `l.season = a.season` — o
histórico doméstico do time continua cortado por temporada mesmo com a competição solta. Só a
célula `ambos` (#54) alcança esse caso.

Em janeiro isso não vale: um time de Bundesliga tem o campeonato nacional e a Champions sob o
mesmo rótulo, e `escopo` junta os dois normalmente. **A [B] não deve herdar "escopo sozinho nunca
ajuda a Europa" como regra** — o que esta medição mostra é que, nesta janela, não há como
verificar.

Some-se a isso o que a #51 já registrou: os únicos jogos de Champions do período são os 8 de 04/08
à noite, removidos pelo teto do universo congelado. A pergunta da spec sobre a fase
classificatória da Champions (user story 24) segue sem amostra no universo primário.

### O que mudou nas 39 premissas

`analyses/taskf_delta_celulas.sql` · 39 linhas no benchmark preferido (mais 21 de consenso em
anexo)

**Sete premissas não se mexem no piso 0** — a premissa acende exatamente nas mesmas linhas; o que
muda nelas é só o piso de amostra:

| premissa | por que é imóvel |
|---|---|
| `superioridade_tabela` (1X2), `supremacia`, `sem_rodizio` (AH) | premissas de tabela: rank/ppg/n_teams saem do agregado competição-scoped do PIT em qualquer célula (ADR 0008) |
| `h2h_favoravel` (1X2) | o `fact_h2h` já cruza campeonatos hoje; a spec o deixa como está |
| `linha_subindo`, `linha_descendo` (Gols) | leem preço, não histórico |
| `desfalque_adversario` (1X2) | lê o boletim de desfalques |

⚠️ **Reusar fonte imune não dá imunidade, e `adversario_limitado` é o caso.** Ela é a única
premissa das 39 que consome o `fact_h2h` de segunda mão, e a expectativa de partida — escrita no
cabeçalho da análise antes de rodar — era que ela acompanhasse o `h2h_favoravel` na lista acima.
**Não acompanha:** `n_p0` vai de 160 para 165 e `diferenca_p0` de +0,7 para +1,2. A definição é
`o_aproveitamento < 45 OR x_h2h_favoravel`, e `o_aproveitamento` sai de
`wins_total/draws_total/played_total` do PIT — o OR basta para o eixo alcançá-la. A regra geral,
para a [B] e para o resto da [F]: uma premissa só herda imunidade se **todos** os seus insumos
forem imunes. `lado_coberto_forte` (DC) tem a mesma forma e também se mexe.

**A ADR 0008 está implementada como diz.** As três premissas de tabela têm `n_p0` e `diferenca_p0`
idênticos entre as células (98/98, 301/301, 188/188). ⚠️ Mas elas **mudam** nos pisos maiores, e
isso é a própria ADR: o `min_jogos` segue a célula inclusive nas linhas delas, porque o piso é
propriedade do jogo. `superioridade_tabela` vai de n=35 para n=47 no piso 5; `supremacia`, de 95
para 121. `sem_rodizio` é a exceção dentro da exceção — 188 nos quatro pisos nas duas células —,
assinatura de uma premissa que só acende em jogo com histórico longo.

⚠️ **Para quem escrever a Costura B (#55).** A segunda invariante que a spec #49 enuncia — "as
quatro premissas de tabela com números idênticos nas quatro células" — fica vermelha se for
implementada ao pé da letra, e por dois motivos já conhecidos e medidos, nenhum deles um defeito:

- são **três** premissas no catálogo medido, não quatro. A quarta que a ADR 0008 nomeia,
  `x_superioridade_tabela`, é coluna interna do `int_futebol_premissas_1x2` que a Dupla Chance
  reusa dentro do `lado_coberto_forte` — e este também lê `forca_mismatch`, então segue o eixo;
- a identidade é **no piso 0**. Nos demais pisos elas mudam porque o `min_jogos` segue a célula,
  que é a seção *Consequences* da própria ADR 0008.

A ADR 0008 foi atualizada com essa leitura e os números. O enunciado da spec não foi editado — ele
é o registro do que se sabia antes de medir.

**As outras 32 se mexem**, que é o esperado: as fontes de histórico competição-scoped próprias dos
cinco modelos (os `last5` de Gols/BTTS/DC, o `margin_stats` do Handicap, o spine de xG/ritmo)
seguem o mesmo eixo desde a #52. Se elas **não** tivessem mexido, a célula estaria misturada.

As quatro que a spec aponta como "muito sinal, pouca amostra" — as de maior peso aparente hoje:

| premissa | amostra curta | diferença piso 0 | diferença piso 5 (n) | peso p5 |
|---|---|---|---|---|
| `clean_sheets_altos` | 77,1% → 62,4% | +17,1 → +14,9 | **−1,7 → +6,3** (24 → 35) | 0,00 → **2,58** |
| `defesa_forte` | 82,9% → 60,6% | +2,8 → +1,9 | **−3,3 → +10,3** (12 → 28) | 0,00 → **3,69** |
| `superioridade_xg` | 71,6% → 61,1% | +5,2 → +4,3 | −8,9 → −4,1 (31 → 44) | 0,00 → 0,00 |
| `tende_golear` | 88,3% → 83,6% | +3,9 → +5,7 | −18,5 → **−22,7** (18 → 21) | 0,00 → 0,00 |

Duas delas — `clean_sheets_altos` e `defesa_forte` — **viram de negativas para positivas no piso
5** com o histórico junto, com a amostra quase dobrando. As outras duas continuam sem evidência, e
`tende_golear` piora: com 83,6% de amostra curta mesmo depois do merge, ela é a que menos se
beneficia.

⚠️ Isto **não** é recomendação de peso. A [0.1] já mostrou que ganho de premissa medido
in-sample não se replica out-of-sample (+10,0% virou −6,2%), e a spec #49 põe peso fora de escopo
explicitamente. O que estas linhas dizem é que a evidência que a [B] vai ler muda de forma
material quando o histórico deixa de ser artificialmente curto.

No agregado das 39: amostra curta média 45,5% → 34,5%, jogos médios 10,5 → 12,9, e o número de
premissas com peso positivo no piso 5 cai de 15 para 11 — o merge **não** infla o catálogo, ele
recompõe quem tem evidência.

Os maiores movimentos no piso 5, para quem for ler a tabela: `historico_btts` (−15,5, mas com
n=15), `ataque_dos_dois` (−15,0), `defesa_forte` (+13,6), `invicto_recente` (+12,0),
`clean_sheets_altos` (+8,0).

### Reprodução

```bash
cd dbt_futebol

# a ancestria da #51 continua servindo — NÃO reconstruir entre células (nada de `+`)

# célula base: build (sem exclusão nenhuma) -> carimbo -> Teste 2
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
  --select int_futebol_team_form_pit int_futebol_premissas_1x2 int_futebol_premissas_ou \
           int_futebol_premissas_ah int_futebol_premissas_btts int_futebol_premissas_dc
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_pit_por_celula taskf_teste2 --vars '{taskf_git_sha: 09328b0}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_pit_por_celula.sql
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

# célula escopo: idem, com a var e excluindo SÓ a Costura A
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
  --select int_futebol_team_form_pit int_futebol_premissas_1x2 int_futebol_premissas_ou \
           int_futebol_premissas_ah int_futebol_premissas_btts int_futebol_premissas_dc \
  --exclude assert_taskf_pit_default_igual_baseline --vars '{pit_escopo: todas}'
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_pit_por_celula taskf_teste2 \
  --vars '{taskf_git_sha: 09328b0, pit_escopo: todas}'
# ... os dois bq query de novo

# as três leituras (não dependem de qual célula está materializada, exceto o universo do familia)
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_monotonicidade_escopo taskf_familia_e_mecanismo taskf_delta_celulas
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_monotonicidade_escopo.sql
```

Os dois `dbt build` fecham **43/43** (base) e **42/42** (escopo), com `ERROR=0` e `SKIP=0`. Na
`base` isso inclui a Costura A; na `escopo`, o guard de look-ahead
`assert_pit_first_game_has_no_history` e as seis guardas de grão passam — a partição do guard
segue os eixos da célula desde a #52, e ele **não** deve ser excluído.

⚠️ **Para a #54:** as células `recorte` e `ambos` entram na mesma tabela e serão comparadas com
estas duas. Se qualquer coisa reconstruir a ancestria antes disso — um build com `+`, um rebuild
do `fact_odds_snapshot` —, a `base` e a `escopo` têm de ser re-medidas na mesma execução das duas
novas. A Costura B (#55) pega a violação pelo `dbt_loaded_at` posterior a um `medido_em`, então
isto é para economizar uma rodada, não para evitar um erro silencioso.

---

## Ticket #54 — Células `recorte` e `ambos`: o 2×2 fechado e as duas contagens de amostra

`analyses/taskf_teste2.sql` + `taskf_saturacao_recorte.sql` + `taskf_delta_celulas.sql` +
`taskf_reconciliacao_01.sql` + `taskf_monotonicidade_escopo.sql` · execução 2026-08-12 18:29 a
18:32 UTC · commit `d40634d` · dataset `futebol_taskF`

As duas células que faltavam. O 2×2 está fechado, as **quatro** foram medidas na mesma execução
sobre o mesmo universo congelado, e `min_jogos` passa a sair em duas colunas — **disponível** e
**usado** — porque sob recorte de contagem elas deixam de ser o mesmo número.

### Veredito

As quatro células medidas, **zero violação em todas as conferências**: a identidade das duas
contagens fecha nas quatro, o piso corta o mesmo conjunto de jogos nas duas contagens em todos os
pisos, os quatro pares de monotonicidade dão zero violações e as quatro células têm o mesmo
conjunto de 21.054 pares. Grão verde nas quatro.

O eixo de **recorte** é real e grande, mas ele **não é o eixo que resolve amostra curta** — quem
resolve é o escopo. Soltar só a temporada leva o piso 5 de **69 para 81 jogos**; soltar só a
competição leva a **92**; soltar os dois leva a **92** também. Em outras palavras, na janela
medida **a temporada não acrescenta um único jogo acima do piso 5 depois que a competição já foi
solta** — o efeito dela só aparece no piso 10 (76 → 83).

O que o recorte faz, e faz muito, é mudar **qual** histórico entra: a `ambos` é a única célula em
que `tende_golear` e `clean_sheets_altos` — duas das quatro premissas de "muito sinal, pouca
amostra" da spec — saem do vermelho no piso 5 ao mesmo tempo.

### As quatro células, na mesma execução e no mesmo universo

| célula | eixos | jogos | linhas | carimbo do PIT | Teste 2 | linhas medidas |
|---|---|---|---|---|---|---|
| `base` | da_competicao / temporada | 169 | 8.567 | 18:29:10 | 18:29:22 | 60 (39 preferido) |
| `escopo` | todas / temporada | 169 | 8.567 | 18:30:25 | 18:30:37 | 60 (39) |
| `recorte` | da_competicao / ultimos_10 | 169 | 8.567 | 18:31:32 | 18:31:44 | 60 (39) |
| `ambos` | todas / ultimos_10 | 169 | 8.567 | 18:32:39 | 18:32:50 | 60 (39) |

"Mesma execução" na forma verificável que a #51 definiu: o `fact_odds_snapshot.dbt_loaded_at` é
**13:24:15**, anterior aos quatro carimbos. As quatro leram a MESMA construção dos fatos — a
ancestria **não** foi reconstruída nesta rodada, de propósito. Ela já estava no dataset desde a
execução da #53 e nenhum modelo dela foi tocado pela #54; reconstruí-la só reinjetaria entre as
células a variação de 2 linhas que a #51 documentou.

A `base` e a `escopo` foram **re-medidas**, e não reaproveitadas da #53 — a spec proíbe
reaproveitar baseline, e desta vez havia motivo extra: os cinco modelos de premissas mudaram
entre uma medição e outra (o eixo de recorte passou a alcançá-los).

### A re-medição reproduz a #53: 119 das 120 linhas exatas, e a que sobra é empate de arredondamento

| célula | linhas | sem contraparte | linhas com divergência | campos divergentes |
|---|---|---|---|---|
| `base` | 60 | 0 | **0** | **0** |
| `escopo` | 60 | 0 | 1 | **1** |

A `base` reproduz a #53 **exatamente**: 16 campos por linha × 60 linhas, 960 campos, zero
divergência. Nas 120 linhas das duas células juntas — 1.920 campos comparados — divergiu **um**. A única divergência da
`escopo` é `pct_amostra_curta` na linha de **consenso** de `historico_under` (que não pesa):
12,7 → 12,8.

⚠️ **Esta comparação foi um `one-shot` e o artefato dela não existe mais.** A FASE 0 dropa a
tabela acumulativa, então as linhas da #53 foram copiadas para uma tabela temporária antes do
drop, comparadas, e a cópia foi removida em seguida. Diferente de todo o resto desta seção, os
números do parágrafo acima **não** são re-deriváveis de `analyses/` — o que sobra re-derivável é a
reconciliação contra a [0.1] (que lê os números publicados do macro versionado
`taskf_publicado_01()`) e as tabelas da #53 transcritas neste documento. Quem precisar refazer uma
comparação dessas num ticket futuro: declare a cópia em `sources.yml` e deixe-a viver, em vez de
tratá-la como rascunho.

O que **é** verificável sem o artefato é a natureza da divergência, e ela é aritmética fechada,
não inferência: aquela linha
tem `n = 400`, então a fração de amostra curta é múltipla de `1/400 = 0,25 pp`. O único valor da
grade que arredonda para 12,7 ou 12,8 é **12,75** — ou seja, 51 linhas de 400, exatamente em cima
do empate de `ROUND(·, 1)`. É o mesmo fenômeno que a #53 mediu nos seus três casos e sobre o qual
avisou a #54, com a mesma causa: o `AVG` do BigQuery acumula em ponto flutuante e a ordem depende
do layout físico da tabela, que muda quando os modelos são reconstruídos.

E a reconciliação contra o Teste 2 publicado da [0.1] continua dando **38 EXATO / 1 INVESTIGAR**,
com `linha_descendo` nos mesmos −2 de `n` e +0,2 pp — nenhuma divergência nova apareceu.

### As duas contagens de amostra, medidas

`analyses/taskf_saturacao_recorte.sql` · veredito **OK** nas quatro células

| célula | recorte | max usado | max disp | pares saturados | usado médio | disp médio |
|---|---|---|---|---|---|---|
| `base` | temporada | 37 | 37 | **0** | 11,29 | 11,29 |
| `escopo` | temporada | 60 | 60 | **0** | 13,77 | 13,77 |
| `recorte` | ultimos_10 | **10** | **98** | 15.150 (72%) | 8,25 | 35,30 |
| `ambos` | ultimos_10 | **10** | **149** | 16.435 (78%) | 8,62 | 44,62 |

O critério de aceite pedia isto **verificado, não assumido**, e a verificação é a identidade
inteira, par a par, nas 21.054 linhas de cada célula:

- sob `temporada`, **usado = disponível** — 0 quebras, 0 pares saturados;
- sob `ultimos_10`, **usado = LEAST(disponível, 10)** — 0 quebras, e o usado nunca passa de 10
  enquanto o disponível chega a **149**.

Os 15.150 e 16.435 pares saturados são também a guarda de **não-vacuidade**: zero saturação numa
célula rotulada `ultimos_10` não significaria "ninguém tinha mais de 10 partidas", significaria
que o carimbo rodou fora de ordem e o dado é de outra célula.

⚠️ **As duas linhas de cima da tabela não são evidência sobre o dado, e o OK delas não deve ser
lido como se fosse.** O modelo não emite `played_total_disponivel` no default, então o carimbo
projeta o próprio `played_total` na coluna do disponível — nas células de recorte `temporada`,
`usado = disponível` é verdade por construção. O que essas duas linhas ainda checam de verdade é o
**rótulo**: uma célula de `temporada` gravada como `ultimos_10` passaria a ser cobrada pela
identidade com teto e cairia, porque o disponível dela chega a 37 e 60. A medição propriamente
dita são as duas linhas de baixo, onde as duas colunas vêm de contas diferentes do modelo.

⚠️ **O usado médio CAI de 11,29 (base) para 8,25 (recorte) e isso não é perda de histórico.** O
teto corta em 10 quem tinha mais, e a média de `LEAST(base, 10)` é naturalmente menor que a de
`base`. A monotonicidade — soltar uma dimensão só acrescenta — vale sobre o **disponível**, e é
sobre ele que ela foi conferida. Medi-la na contagem que satura acusaria violação em cima do
próprio mecanismo que se quis medir.

### O piso corta o mesmo conjunto nas duas contagens — nas quatro células

| piso | `base` | `escopo` | `recorte` | `ambos` |
|---|---|---|---|---|
| 0 | 169 | 169 | 169 | 169 |
| 3 | 90 | **113** | 103 | **113** |
| 5 | **69** | **92** | **81** | **92** |
| 10 | 67 | 76 | 73 | **83** |

Cada número acima foi contado **duas vezes**, uma no disponível e uma no usado, e as oito
comparações deram idêntico — `pisos_divergentes = 0` nas quatro células. É consequência da
identidade (`LEAST(d, 10) >= piso` ⟺ `d >= piso`, para piso ≤ 10), mas é consequência **medida**:
o cabeçalho do Teste 2 afirma isso ao leitor, e afirmação sem número é o que esta task existe para
não fazer. Se um dia a varredura ganhar um piso maior que o tamanho do recorte, este bloco fica
vermelho — e aí cortar no disponível deixa de ser inócuo e passa a ser a única escolha correta.

A célula `base` reproduz aqui, mais uma vez, a tabela de piso publicada na [0.1]: 69 no piso 5 e
67 no piso 10.

### A invariante do 2×2: soltar uma dimensão só acrescenta

`analyses/taskf_saturacao_recorte.sql`, bloco `monotonicidade` · veredito **OK** nos quatro pares

| par | o que solta | pares com ganho | ganho médio | ganho máx | violações | chaves divergentes |
|---|---|---|---|---|---|---|
| `base` → `escopo` | competição | 6.434 (30,6%) | 8,13 | 48 | **0** | **0** |
| `base` → `recorte` | temporada | 11.066 (52,6%) | 45,70 | 76 | **0** | **0** |
| `escopo` → `ambos` | temporada | 12.126 (57,6%) | 53,56 | 119 | **0** | **0** |
| `recorte` → `ambos` | competição | 9.061 (43,0%) | 21,64 | 137 | **0** | **0** |

Os dois pares que soltam a **temporada** mexem em MUITO mais pares e por MUITO mais partidas do
que os dois que soltam a competição — 52,6% e 57,6% dos pares, com ganho médio de 46 e 54
partidas, contra 30,6% e 43,0% com ganho de 8 e 22. É a assinatura de o histórico do repositório
ser mais fundo no tempo do que largo em competições: soltar a virada de temporada abre temporadas
inteiras de trás, e soltar a competição abre só as outras competições daquele ano.

⚠️ **E é exatamente por isso que o efeito no PISO é o oposto.** Ganho de partida só vira jogo novo
acima do piso quando cai em par que estava ABAIXO dele. As partidas que o eixo de temporada
empresta vão em peso para quem já tinha histórico (um time de Brasileirão ganha a temporada 2025
inteira), e não para as seleções de Copa do Mundo — que são 46,7% do universo e o deserto real. A
tabela de piso e a de monotonicidade não se contradizem: uma mede volume de histórico, a outra
mede quantos jogos cruzam uma linha.

O par `base` → `escopo` aparece aqui **e** na `taskf_monotonicidade_escopo.sql` da #53, de
propósito: aqui ele é a quarta aresta do 2×2, lá ele vem com a conferência contra o baseline
congelado. Os dois medem contagens diferentes (disponível e usado), que nas células de `temporada`
são o mesmo número — e os dois dão exatamente o mesmo resultado (6.434 / 8,13 / 48 / 0). A
repetição vira, assim, uma conferência cruzada de dois arquivos independentes.

A conferência de chaves fecha o argumento: **21.054 pares nas quatro células, conjunto idêntico**,
zero par só de um lado. Os eixos mexem no histórico que cada par carrega, nunca em quais pares
existem.

### O que mudou nas 39 premissas

`analyses/taskf_delta_celulas.sql` · quatro pares rodados (`base`→`recorte`, `base`→`ambos`,
`escopo`→`ambos`, `recorte`→`ambos`)

**No agregado das 39 do benchmark preferido:**

| célula | jogos médios disp | jogos médios usado | amostra curta média | com peso p5 > 0 |
|---|---|---|---|---|
| `base` | 10,5 | 10,5 | 45,5% | 15 |
| `escopo` | 12,9 | 12,9 | 34,5% | 11 |
| `recorte` | **29,1** | **6,9** | 37,4% | 15 |
| `ambos` | **52,7** | **7,3** | 33,2% | **17** |

A coluna do disponível e a do usado contando histórias opostas nas duas células de baixo é o
achado do ticket em uma linha: o jogo passa a ter três a cinco vezes mais passado disponível, e a
premissa continua lendo no máximo dez partidas dele.

**As quatro premissas que a spec aponta como "muito sinal, pouca amostra"**, no piso 5:

| premissa | `base` | `escopo` | `recorte` | `ambos` |
|---|---|---|---|---|
| `clean_sheets_altos` | −1,7 (n=24) | +6,3 (n=35) | +7,8 (n=63) | **+30,0 (n=34)** |
| `defesa_forte` | −3,3 (n=12) | +10,3 (n=28) | +5,7 (n=29) | **+15,1 (n=25)** |
| `superioridade_xg` | −8,9 (n=31) | −4,1 (n=44) | +1,7 (n=45) | −5,6 (n=60) |
| `tende_golear` | −18,5 (n=18) | −22,7 (n=21) | −20,3 (n=49) | **+2,0 (n=52)** |

E a amostra curta delas: `clean_sheets_altos` 77,1% → 49,6% (`recorte`), `defesa_forte` 82,9% →
62,3%, `tende_golear` 88,3% → 70,7%, `superioridade_xg` 71,6% → 53,5% (`ambos`).

⚠️ Isto **não** é recomendação de peso, pelo mesmo motivo que a #53 registrou: a [0.1] mostrou que
ganho medido in-sample não se replica out-of-sample (+10,0% virou −6,2%), e a spec #49 põe peso
fora de escopo. O que estas linhas dizem é que a evidência que a [B] vai ler muda de forma
material — e que ela muda de forma **diferente** em cada eixo, que é a pergunta 9 da spec.

**As imóveis no piso 0**, por par:

| par | imóveis | quais entram além das três de tabela |
|---|---|---|
| `base` → `recorte` | 8 | `h2h_favoravel`, `linha_subindo`, `linha_descendo`, `desfalque_adversario`, **`historico_btts`** |
| `base` → `ambos` | 7 | as mesmas, sem `historico_btts` |
| `escopo` → `ambos` | 13 | as 7 + `forma`, `invicto_recente` e os quatro `historico_*` |

As **três premissas de tabela** (`superioridade_tabela`, `supremacia`, `sem_rodizio`) saem imóveis
no piso 0 em **todos** os pares — a ADR 0008 vale nas quatro células, e não só nas duas que a #53
mediu. Nos demais pisos elas mudam, porque o `min_jogos` segue a célula; é a seção *Consequences*
da própria ADR.

⚠️ **`historico_btts` imóvel sob `recorte` NÃO é fonte que não respondeu** — e a falsificação está
ao lado. `historico_seco` lê o **mesmo** array `last5_btts`, do mesmo CTE, e se mexe no mesmo par
(n_p0 70 → 77, diferença −0,9 → +0,9). A fonte respondeu; o que não virou foi o booleano de uma
premissa que acende 16 vezes em 8.567 linhas e cujo gatilho (3 de 5) é grosso demais para sentir a
troca de uma partida. Quem for ler a tabela da #59 não deve registrar `historico_btts` como
"fora do alcance do eixo".

⚠️ **A linha das 13 imóveis em `escopo` → `ambos` é um achado, e ele foi medido.** Com as
competições já juntadas, soltar a temporada não mexe em nenhum dos quatro `historico_*` nem na
`forma` — todos são janelas de contagem de **5**, e uma janela de 5 só muda para quem tem menos de
5 partidas. Contado nos pares dos fixtures da janela:

| pares em `escopo` | quantos | ganham em `ambos` | disponível médio |
|---|---|---|---|
| com menos de 5 partidas (janela de 5 incompleta) | 279 | **62 (22%)** | 1,54 → 2,78 |
| com 5 ou mais (janela já cheia) | 269 | 246 (91%) | 18,97 → **86,69** |

Ou seja: quem ganha muito ao soltar a temporada é justamente quem **já tinha** os cinco, e para
esses o `last5` não se move nem um pouco; quem teria a janela alterada quase todo não ganha nada —
são as seleções da Copa do Mundo, que não têm temporada anterior nenhuma na base — e os 62 que
ganham param, em média, em 2,78 partidas, ainda longe dos 5. A virada de temporada alcança quem
conta **médias sobre tudo** (xG, ritmo, gols médios); quem conta os últimos cinco fica de fora
neste universo.

### ⚠️ Nas duas premissas de Handicap, o recorte ENCOLHE o histórico

`raramente_perde_por_2` e `favorito_irregular` saem do `margin_stats`, que **não tem filtro de
season nem no default** — ele já atravessa temporada hoje. Nele, portanto, `base` → `recorte` é
"todo o tempo coletado" → "as 10 últimas", e não "a temporada" → "as 10 últimas" como em todos os
outros sites.

O número mostra: as duas acendem em MENOS linhas sob recorte (`n_p0` 445 → 388 e 453 → 427), ao
contrário de todas as outras, e a diferença no piso 5 cai (+7,4 → +6,2 e +7,1 → +5,5) para depois
subir em `ambos` (+8,5 e +7,9). Quem comparar o delta delas com o das demais premissas sem saber
disso lê o sinal ao contrário. O aviso está no cabeçalho do `taskf_delta_celulas.sql`, no do
`int_futebol_premissas_ah.sql` e na ADR 0007.

### ⚠️ O teto de contagem gasta vaga com partida sem xG — o mecanismo existe, e não mordeu aqui

Sob recorte de contagem, o spine de xG e o de ritmo ranqueiam as partidas **por data** e ficam com
as 10 mais recentes; a média sai do que houver de não-nulo dentro delas. Onde o xG é esparso, uma
partida sem xG ocupa vaga e a média sai de menos valores — coisa que a célula de `temporada`, que
não tem teto, não sofre. E o xG **é** esparso em três das cinco competições do universo:

| competição | linhas de stats | sem xG | % |
|---|---|---|---|
| copa_do_brasil | 562 | 484 | **86,1%** |
| sudamericana | 888 | 586 | **66,0%** |
| serie_b | 1.938 | 964 | **49,7%** |
| brasileirao | 1.946 | 0 | 0% |
| copa_mundo | 208 | 0 | 0% |

É consequência de desenho, não defeito: o eixo diz "as 10 partidas anteriores", e a alternativa —
"as 10 partidas anteriores **com xG**" — alcançaria mais fundo no tempo sem avisar, que é outra
definição. **Medido, ele não custou cobertura nesta janela**: as três premissas de xG e a de ritmo
acendem em MAIS linhas em `recorte` e em `ambos` do que em `base` (`superioridade_xg` 109 → 117 →
129; `xg_combinado_alto` 320 → 324 → 361; `ritmo_alto` 465 → 503 → 511). As duas únicas quedas
estão em `escopo` → `ambos` (`xg_baixo_combinado` 328 → 319, `ritmo_alto` 541 → 511) — que é onde
o mecanismo apareceria, mas atribuí-las a ele exigiria uma medição de cobertura que este ticket
não fez.

Fica anotado para a #59: se a tabela final mostrar premissa de xG perdendo linha numa célula com
teto, este é o primeiro lugar a olhar.

### A quebra por família continua degenerada, como a #53 já sabia

O universo congelado é 100% de competições de ano-calendário nas **quatro** células — a partição
por família é propriedade do universo, e o universo é o mesmo nas quatro por construção. `split_year
= 0` em `recorte` e `ambos` como já estava em `base` e `escopo`, e por isso **não** foi construída
máquina de quebra por família por premissa: ela teria uma coluna cheia e uma vazia em qualquer
célula. A família só volta a ser dimensão de duas pontas no universo estendido (#56).

Isso vale também para a leitura que a #53 deixou pendurada: a `ambos` é a célula que alcançaria o
caso da Champions na virada de temporada — mas a Champions **não tem um jogo** no universo
primário (os 8 dela na janela são de 04/08 à noite, removidos pelo teto). A pergunta da spec sobre
a fase classificatória (user story 24) segue sem amostra aqui, e é da #56/#58.

### Reprodução

```bash
cd dbt_futebol

# FASE 0 — só porque a #54 mudou o schema das duas tabelas acumulativas
bq rm -f -t smartbetting-dados:futebol_taskF.taskf_teste2
bq rm -f -t smartbetting-dados:futebol_taskF.taskf_pit_por_celula

# A ANCESTRIA NÃO FOI RECONSTRUÍDA: ela já estava no dataset desde a #53 e nenhum modelo dela
# mudou. Numa árvore limpa, rodar a fase 1 do cabeçalho do taskf_teste2.sql uma vez, antes.

# as quatro células, cada uma com build -> carimbo -> Teste 2 e as MESMAS vars. Nada de `+`.
# base    : --vars '{}'                                        (sem exclusão: a Costura A roda)
# escopo  : --vars '{pit_escopo: todas}'                       --exclude assert_taskf_pit_default_igual_baseline
# recorte : --vars '{pit_recorte: ultimos_10}'                 idem
# ambos   : --vars '{pit_escopo: todas, pit_recorte: ultimos_10}' idem
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
  --select int_futebol_team_form_pit int_futebol_premissas_1x2 int_futebol_premissas_ou \
           int_futebol_premissas_ah int_futebol_premissas_btts int_futebol_premissas_dc \
  --vars '{pit_recorte: ultimos_10}' --exclude assert_taskf_pit_default_igual_baseline
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_pit_por_celula taskf_teste2 \
  --vars '{taskf_git_sha: d40634d, pit_recorte: ultimos_10}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_pit_por_celula.sql
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

# as conferências, depois das quatro
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_saturacao_recorte taskf_monotonicidade_escopo taskf_reconciliacao_01
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_saturacao_recorte.sql

# a comparação entre um par de células
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_delta_celulas \
  --vars '{taskf_celula_a: base, taskf_celula_b: ambos}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_delta_celulas.sql
```

Os quatro `dbt build` fecham **43/43** (`base`, incluindo a Costura A) e **42/42** (as outras
três), com `ERROR=0` e `SKIP=0`. Nas três células fora do default a única exclusão é a Costura A,
que é default-only por definição; o guard de look-ahead `assert_pit_first_game_has_no_history`
roda e passa nas quatro — e desde a #54 ele confere também a contagem **disponível**, que sai de
uma window function calculada antes do teto e por isso tem um caminho próprio para vazar futuro.

⚠️ **Para a #55 (Costura B) e para a #59.** O schema do `taskf_teste2` mudou: `jogos_medios` virou
`jogos_medios_disp` e ganhou o par `jogos_medios_usado`. As duas primeiras invariantes da Costura B
podem ser escritas contra a tabela como ela está — `jogos_no_universo` é 169 nas quatro, e as três
premissas de tabela são idênticas no piso 0 nas quatro (a spec fala em quatro premissas; são três
no catálogo medido, pelo motivo que a #53 registrou). Uma terceira invariante que agora existe e
vale a pena escrever: `jogos_medios_disp = jogos_medios_usado` em toda linha de célula com recorte
`temporada`. Ela já sai não-vacuosa dos dois lados — medida agora: 60/60 linhas iguais em `base` e
em `escopo`, **0/60** em `recorte` e em `ambos`. Uma guarda que exigisse só a igualdade passaria em
branco se as quatro células virassem `temporada` por engano; exigir a desigualdade do outro lado
fecha isso.

---

## Ticket #55 — Costura B: as invariantes deixam de ser afirmação

`tests/assert_taskf_celulas_mesmo_universo.sql` + `assert_taskf_premissas_de_tabela_identicas.sql`
+ `assert_taskf_base_reproduz_01.sql` + `assert_taskf_contagens_por_recorte.sql` +
`analyses/taskf_remedicao.sql` · execução 2026-08-12 19:55 a 20:05 UTC · commit `b535130` ·
dataset `futebol_taskF`

O que as três seções anteriores afirmam sobre a saída das quatro células vira cobrança automática.
Antes deste ticket, "as quatro rodaram na mesma execução", "as premissas de tabela não se mexem" e
"a `base` reproduz a [0.1]" eram disciplina de quem executou e parágrafo de quem leu. Depois dele,
são quatro guardas com nome, tag e vermelho.

### Veredito

**Quatro guardas, quatro verdes**, sobre as quatro células re-medidas na mesma execução. As quatro
foram **quebradas de propósito** — cinco quebras diferentes, cada uma desfeita em seguida e
reconferida — e nenhuma delas passa em branco.

```
dbt test --target taskF --select tag:costura_b     →  PASS=4 ERROR=0
```

A tabela acumulativa mudou de schema (ganhou `odds_loaded_at`), o que obrigou a dropá-la e re-medir
as quatro células. A re-medição reproduz a #54 em **7.195 de 7.200 campos**, e os 5 que divergem
são empates de arredondamento comprovados aritmeticamente.

### As quatro guardas, e o que cada uma cobra

| guarda | o que cobra | cobertura hoje |
|---|---|---|
| `assert_taskf_celulas_mesmo_universo` | as quatro células existem, o rótulo casa com os eixos, universo idêntico e igual ao declarado, mesma construção dos fatos e fatos anteriores à medição | 4 células, 169 jogos / 8.567 linhas, `odds_loaded_at` 13:24:15 nas quatro |
| `assert_taskf_premissas_de_tabela_identicas` | as três premissas de tabela têm números idênticos no piso 0 entre as células | 5 linhas de grão × 4 células, 7 campos — 105 comparações |
| `assert_taskf_base_reproduz_01` | a `base` reproduz o Teste 2 publicado da [0.1] sob a régua declarada | 39 linhas, **225 campos publicados** comparados |
| `assert_taskf_contagens_por_recorte` | disponível = usado sob `temporada`, e **alguma** linha diverge sob `ultimos_10` | 60/60 linhas iguais em `base` e `escopo`; 60/60 divergentes em `recorte` e `ambos` |

As quatro leem **só `source('futebol_taskF', ...)`** — nenhuma faz `ref()` de modelo. Isso não é
detalhe de estilo: um `ref()` as penduraria no grafo do `fact_odds_snapshot` e a seleção indireta
do dbt as arrastaria para dentro dos `dbt build` das fases 1 e 2, onde elas são vermelhas por
construção (as células ainda não foram medidas). Seria uma segunda `--exclude` na receita, e "a
Costura A é a única exclusão que a medição precisa" é promessa escrita em três lugares desde a #52.
Conferido no manifest: as quatro dependem de um nó só, a source.

### Duas leituras do critério de aceite, já corrigidas antes desta guarda existir

O critério da #55 pede "as **quatro** premissas de tabela com números **idênticos**". Implementado
ao pé da letra, ele nasce vermelho — e as duas correções não são deste ticket, são da ADR 0008,
medidas na #53 e na #54:

- **três, não quatro.** `x_superioridade_tabela` não é uma das 39 medidas: é coluna interna do
  `int_futebol_premissas_1x2` que a Dupla Chance reusa dentro do `lado_coberto_forte` — e este
  também lê `forca_mismatch`, então segue o eixo. Cobrá-la daria zero linha comparada, que é
  exatamente o silêncio verde que a guarda existe para não produzir;
- **a identidade é no piso 0.** Nos pisos maiores as três mudam de número legitimamente, porque o
  `min_jogos` segue a célula (o piso é propriedade do jogo, não da premissa):
  `superioridade_tabela` vai de n=35 na `base` para n=47 na `escopo` no piso 5. Pelo mesmo motivo
  `jogos_medios_disp`, `jogos_medios_usado` e `pct_amostra_curta` ficam fora da comparação mesmo no
  piso 0 — `supremacia` mede 7,0 partidas médias na `base` e 29,1 na `ambos`, e isso é o resultado,
  não um defeito.

O enunciado da spec continua como está de propósito: ele é o registro do que se sabia antes de
medir. O cabeçalho da guarda carrega as duas leituras por escrito.

### A quarta guarda, que a #54 encomendou

A #54 fechou pedindo uma invariante sobre as duas contagens de amostra, **escrita com as duas
pontas**. Ela existe: sob recorte `temporada` toda linha tem disponível = usado (sem teto, tudo que
existe é usado); sob `ultimos_10`, **alguma** linha tem de divergir. A segunda ponta é o que impede
o silêncio verde — se as quatro células virassem `temporada` por engano, a igualdade sozinha
passaria em todas e o eixo de recorte simplesmente não teria sido medido.

⚠️ O lado `ultimos_10` é cobrado como "alguma linha diverge", e **não** como 60/60. Que hoje sejam
60 de 60 é medição, não construção: uma premissa que só acendesse em jogo de time novo teria
disponível < 10 em todas as suas linhas e as duas médias sairiam iguais, legitimamente. Cobrar o
número de hoje seria congelar dado como se fosse regra.

### A falsificação: cinco quebras, cinco vermelhos, cinco desfeitas

O critério de aceite pede que as guardas falhem **de verdade**. Cada uma foi quebrada, conferida e
restaurada; a integridade da tabela foi reconferida no fim contra a cópia da #54 — as mesmas 5
divergências de arredondamento de antes, nem uma a mais.

| # | quebra | guarda que caiu | saída |
|---|---|---|---|
| 1 | `--vars '{taskf_tolerancia_pp: 0}'` (não toca no dado) | `base_reproduz_01` | **6 linhas**, todas os campos em pp de `linha_descendo` — o resíduo conhecido, e mais nada |
| 2 | `SET n_p0 = n_p0 + 1 WHERE celula='escopo' AND premissa='supremacia' AND benchmark='sharp'` | `premissas_de_tabela_identicas` | **1 linha**: n_p0 302 contra 301 na referência |
| 3 | `SET odds_loaded_at = TIMESTAMP_ADD(odds_loaded_at, INTERVAL 1 SECOND) WHERE celula='ambos'` | `celulas_mesmo_universo` | **3 linhas**, `leu_outra_construcao: true` — a assinatura exata de quem reconstruiu a ancestria no meio da medição |
| 4 | `SET odds_loaded_at = TIMESTAMP '2026-08-13 00:00:00 UTC'` (as quatro) | `celulas_mesmo_universo` | **4 linhas**, `medida_antes_dos_fatos: true` e `leu_outra_construcao: false` — a outra ponta: quem rebuildou os fatos e esqueceu de re-medir |
| 5 | `SET pit_recorte='temporada' WHERE celula='ambos'` | `contagens_por_recorte` **e** `celulas_mesmo_universo` | **61 linhas** (resumo + as 60 com teto) e **1 linha** (`rotulo_nao_casa_com_os_eixos`) |

⚠️ **A quebra 1 é a mais informativa das cinco.** Zerar a tolerância derruba exatamente 6 campos,
todos da mesma premissa, e nenhum outro dos 225. Isso mede duas coisas de uma vez: a régua está
cobrindo uma coisa só, e as outras 38 premissas reproduzem o publicado **exatamente**, sem folga
nenhuma sustentando o verde.

⚠️ **As quebras 3 e 4 são as que respondem ao critério ao pé da letra** ("falham se alguém
materializar as células em execuções separadas"). As outras duas guardas não caem nesse cenário, e
não deveriam: a das premissas de tabela fala de escopo vazando, a da reprodução fala da [0.1]. Quem
cobra "mesma execução" é a primeira, pelas duas pontas.

### O carimbo `odds_loaded_at`, e o que ele custou

A forma verificável de "mesma execução" que a #51 definiu era ler o
`fact_odds_snapshot.dbt_loaded_at` **ao vivo** e conferir que é anterior aos quatro `medido_em`. A
#55 gravou esse valor **na linha de cada célula**, e a mudança tem duas razões:

1. lido ao vivo, o veredito **decai**: qualquer rebuild posterior no dataset de medição deixaria a
   guarda vermelha sem que as quatro células tivessem deixado de ser comparáveis entre si — que é a
   única coisa que a guarda quer afirmar;
2. lido ao vivo, ele exige `ref()`, e o `ref()` traz o problema de grafo descrito acima.

Carimbado, ele responde a pergunta certa para sempre — e responde **mais forte**: não é "os quatro
carimbos são próximos", é "as quatro leram a MESMA construção", com o valor na linha.

O preço é o que a #54 já tinha documentado: mudar o schema da acumulativa obriga a `bq rm` e
re-medir as quatro células. Foi feito, e a `taskf_pit_por_celula` foi reescrita junto — as duas
tabelas carregam a mesma execução.

### A re-medição reproduz a #54: 5 campos em 7.200

`analyses/taskf_remedicao.sql` — e desta vez a comparação **é re-derivável**. A #54 fez a mesma
conferência com uma cópia tratada como rascunho e apagada em seguida, e registrou a lição; aqui a
cópia é a tabela `futebol_taskF.taskf_teste2_54`, declarada em `sources.yml`, e a comparação é um
arquivo.

| célula | linhas | sem contraparte | linhas divergentes | campos divergentes | campos comparados |
|---|---|---|---|---|---|
| `base` | 60 | 0 | 1 | **1** | 1.800 |
| `escopo` | 60 | 0 | 2 | **3** | 1.800 |
| `recorte` | 60 | 0 | 0 | **0** | 1.800 |
| `ambos` | 60 | 0 | 1 | **1** | 1.800 |

Os cinco campos, e a prova de que os três casos são **empate de arredondamento** e não deriva —
cada um cai exatamente no meio da grade de `ROUND(·, 1)`:

| célula | linha | campo | antes → agora | grade | veredito |
|---|---|---|---|---|---|
| `base` | Handicap · `raramente_perde_por_2` · consenso | `aconteceu_p10` | 96,2 → 96,3 | n=320, 308/320 = **96,25** | empate exato |
| `escopo` | Dupla Chance · `invicto_recente` · derivada | `jogos_medios_disp` e `_usado` | 10,2 → 10,3 | n=48, soma 492 → **10,25** | empate exato |
| `escopo` e `ambos` | Gols · `historico_under` · consenso | `pct_amostra_curta` | 12,8 → 12,7 | n=400, 51/400 = **12,75** | empate exato |

É o mesmo fenômeno que a #53 mediu em três casos e a #54 em um: o `AVG` do BigQuery acumula em
ponto flutuante e a ordem depende do layout físico da tabela, que muda quando os modelos são
reconstruídos. Nenhuma das cinco linhas é de benchmark preferido em mercado de peso — três das
cinco são de consenso, que não pesa.

E as conferências de fora não se moveram:

- **reconciliação contra a [0.1]**: 38 `EXATO` / 1 `INVESTIGAR`, com `linha_descendo` nos mesmos
  −2 de `n` e +0,1/+0,2 pp;
- **saturação, piso, monotonicidade e chaves**: `OK` nos quatro blocos, 0 violações — 15.150 e
  16.435 pares saturados, piso 5 em 69 / 92 / 81 / 92, 21.054 pares idênticos nas quatro.

### ⚠️ E o que apareceu no caminho: o `task01_base()` estava quebrado em master

Ao re-medir a primeira célula, o `taskf_teste2` compilado não era SQL válido. A causa não é da [F]:
o PR #48 (spec #37, mergeado às **14:53** de 12/08) inseriu um bloco `{#- ... -#}` entre a última
coluna do CTE `odds` e o `FROM`. O traço de abertura faz o Jinja comer a quebra de linha anterior, e
o compilado saía `... AS conjunto_incompletoFROM (`.

**Todas as 12 análises que chamam `task01_base()`** — as 8 da [0.1]/[A] e as 4 da [F] — pararam de
compilar em master naquele merge. Ninguém viu por dois motivos que valem para a próxima vez:

- nenhuma delas roda no agendado, que executa `dbt test --select tag:guarda`. Análise quebrada é
  **muda** até alguém rodar;
- a medição da #54 rodou às 15:29 do mesmo dia **de dentro do worktree dela**, que não continha o
  merge. O isolamento que o `CLAUDE.md` exige protege de clobber de arquivo e, de brinde, esconde
  regressão de master até o próximo branch novo.

Corrigido no commit `b535130` (abre com `{#`, sem traço), com as quatro análises da [F] e a
`task01_teste2` validadas no dry-run do BigQuery depois do fix.

### Reprodução

```bash
cd dbt_futebol

# FASE 0 — só porque a #55 mudou o schema da acumulativa (o odds_loaded_at)
bq cp -f smartbetting-dados:futebol_taskF.taskf_teste2 \
         smartbetting-dados:futebol_taskF.taskf_teste2_54   # a cópia que sobrevive
bq rm -f -t smartbetting-dados:futebol_taskF.taskf_teste2

# as quatro células, cada uma com build -> carimbo -> Teste 2 e as MESMAS vars. Nada de `+`.
# (a ancestria não foi reconstruída: ela já estava no dataset e nenhum modelo dela mudou)
# base    : --vars '{}'                                        (sem exclusão: a Costura A roda)
# escopo  : --vars '{pit_escopo: todas}'                       --exclude assert_taskf_pit_default_igual_baseline
# recorte : --vars '{pit_recorte: ultimos_10}'                 idem
# ambos   : --vars '{pit_escopo: todas, pit_recorte: ultimos_10}' idem

# FASE 3 — o portão. Enquanto não estiver verde, são quatro medições, e não um 2x2 comparável.
DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target taskF --select tag:costura_b

# a re-medição contra a execução anterior
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_remedicao \
  --vars '{taskf_remedicao_anterior: taskf_teste2_54}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_remedicao.sql

# a falsificação que não toca no dado
DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target taskF \
  --select assert_taskf_base_reproduz_01 --vars '{taskf_tolerancia_pp: 0}'
```

Os quatro `dbt build` fecham **43/43** (`base`, incluindo a Costura A) e **42/42** (as outras
três), com `ERROR=0` e `SKIP=0` — iguais aos da #54.
