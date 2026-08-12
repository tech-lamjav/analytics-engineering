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

**A ADR 0008 está implementada como diz.** As três premissas de tabela têm `n_p0` e `diferenca_p0`
idênticos entre as células (98/98, 301/301, 188/188). ⚠️ Mas elas **mudam** nos pisos maiores, e
isso é a própria ADR: o `min_jogos` segue a célula inclusive nas linhas delas, porque o piso é
propriedade do jogo. `superioridade_tabela` vai de n=35 para n=47 no piso 5; `supremacia`, de 95
para 121. `sem_rodizio` é a exceção dentro da exceção — 188 nos quatro pisos nas duas células —,
assinatura de uma premissa que só acende em jogo com histórico longo.

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
