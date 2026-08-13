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
| `assert_taskf_celulas_mesmo_universo` | as quatro células existem, o rótulo casa com os eixos, universo idêntico e igual ao declarado, mesma construção dos fatos, fatos anteriores à medição e mesmo commit nas quatro | 4 células, 169 jogos / 8.567 linhas, `odds_loaded_at` 13:24:15 e `git_sha` `b535130` nas quatro |
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

⚠️ **A quebra 8 é a que justifica a existência das outras.** Ela veio da revisão de standards, que
achou um buraco no código antes de qualquer teste rodar: o `git_sha` tinha entrado no `ANY_VALUE`
da CTE mas **não** na chave de `versoes_na_celula`, então uma célula com duas procedências dentro
dela era achatada antes de a conferência de commit comparar coisa alguma — a cobrança passava
justamente no caso para o qual foi escrita. Corrigido, a quebra 8 devolve `versoes_na_celula: 2`.
Vale como aviso ao próximo: acrescentar campo à CTE de agregação **e** à chave de versão são dois
passos, e esquecer o segundo é silencioso.

| # | quebra | guarda que caiu | saída |
|---|---|---|---|
| 1 | `--vars '{taskf_tolerancia_pp: 0}'` (não toca no dado) | `base_reproduz_01` | **6 linhas**, todas os campos em pp de `linha_descendo` — o resíduo conhecido, e mais nada |
| 2 | `SET n_p0 = n_p0 + 1 WHERE celula='escopo' AND premissa='supremacia' AND benchmark='sharp'` | `premissas_de_tabela_identicas` | **1 linha**: n_p0 302 contra 301 na referência |
| 3 | `SET odds_loaded_at = TIMESTAMP_ADD(odds_loaded_at, INTERVAL 1 SECOND) WHERE celula='ambos'` | `celulas_mesmo_universo` | **3 linhas**, `leu_outra_construcao: true` — a assinatura exata de quem reconstruiu a ancestria no meio da medição |
| 4 | `SET odds_loaded_at = TIMESTAMP '2026-08-13 00:00:00 UTC'` (as quatro) | `celulas_mesmo_universo` | **4 linhas**, `medida_antes_dos_fatos: true` e `leu_outra_construcao: false` — a outra ponta: quem rebuildou os fatos e esqueceu de re-medir |
| 5 | `SET pit_recorte='temporada' WHERE celula='ambos'` | `contagens_por_recorte` **e** `celulas_mesmo_universo` | **61 linhas** (resumo + as 60 com teto) e **1 linha** (`rotulo_nao_casa_com_os_eixos`) |
| 6 | `SET git_sha='cafebabe' WHERE celula='recorte'` | `celulas_mesmo_universo` | **1 linha**, `outro_commit: true` com os fatos iguais — a célula medida de outro código |
| 7 | `SET git_sha='desconhecido'` (as quatro) | `celulas_mesmo_universo` | **4 linhas**, `sem_procedencia: true` — as quatro concordam entre si e nenhuma diz de onde veio |
| 8 | `SET git_sha='cafebabe' WHERE celula='base' AND mercado='Gols'` | `celulas_mesmo_universo` | **1 linha**, `versoes_na_celula: 2` — duas procedências DENTRO de uma célula |

⚠️ **A quebra 1 é a mais informativa das cinco.** Zerar a tolerância derruba exatamente 6 campos,
todos da mesma premissa, e nenhum outro dos 225. Isso mede duas coisas de uma vez: a régua está
cobrindo uma coisa só, e as outras 38 premissas reproduzem o publicado **exatamente**, sem folga
nenhuma sustentando o verde.

⚠️ **O critério de aceite pede que "os três" falhem se as células forem materializadas em execuções
separadas, e isso não é o que acontece — nem deveria ser.** Quem cobra "mesma execução" é a
primeira guarda, sozinha, pelas três pontas (mesma construção dos fatos, fatos antes da medição,
mesmo commit). As outras não caem nesse cenário porque falam de outra coisa: a das premissas de
tabela fala de escopo vazando, a da reprodução fala da [0.1], a das contagens fala do recorte.
Espalhar a mesma cobrança pelas quatro daria redundância, não cobertura.

⚠️ **E o que nenhuma das quatro alcança, dito antes que alguém descubra do jeito caro.** As quatro
células são sempre materializadas por quatro `dbt build` separados — isso é da receita, não um
desvio. O que a #51 fixou como "mesma execução" é **as quatro terem lido a mesma construção dos
fatos**, e é isso que a guarda cobra. Logo: re-medir uma célula amanhã, sobre fatos intocados e do
mesmo commit, sai **verde**.

O que escapa nesse caso é a **deriva de reconstrução dos modelos** — e ela é real e está medida
aqui mesmo: 5 campos em 7.200 mudaram entre duas medições sobre os mesmos fatos, todos empates de
arredondamento do `AVG`. Nenhuma guarda distingue esse empate de um efeito de 0,1 pp, porque no
número eles são idênticos. Quem quiser a diferença mede com `analyses/taskf_remedicao.sql`, que é
onde ela é visível — e é por isso que a comparação da re-medição virou arquivo em vez de rascunho.
O carimbo `git_sha` fecha a parte disso que **é** decidível sem régua arbitrária: duas células do
mesmo commit ou não.

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

---

## Ticket #56 — A reconciliação do diagnóstico de 180 dias

`analyses/taskf_reconciliacao_180d.sql` + `analyses/taskf_partida_da_fronteira.sql` · execução
2026-08-13 13:13–13:14 UTC · commit `f27f79b` · dataset `futebol` (produção)

A tabela de quatro linhas que abre o ticket de origem — a que diz que o time de Copa do Brasil tem
10,2 jogos na própria competição e 25,5 contando tudo — reproduzida da nossa base. É o que dá ao
autor motivo para confiar no resto dos números: se os 25,5 não saem, nada do que as células
mediram depois merece crédito.

Esta é a única seção da [F] que não encosta no dataset de medição. A análise desce até
`fact_fixtures` e refaz a contagem de partidas anteriores por conta própria — não passa pelo
`int_futebol_team_form_pit`, nem pela camada de premissas, nem pelo `task01_base()`. Era critério
de aceite da #56, e o motivo é direto: uma conferência que passasse pela máquina conferida não
conferiria coisa alguma.

### Veredito

**15 dos 16 campos da tabela do ticket reproduzem EXATAMENTE**, por uma receita só, nas quatro
competições. O décimo sexto diverge em 0,1 jogo, e a divergência tem nome, sobrenome e horário:
uma partida que cai **30 minutos** dentro da fronteira dos 180 dias.

O diagnóstico do ticket está certo, e as três leituras que ele tira da tabela se sustentam. Mas a
tabela tem uma armadilha de construção que o próprio ticket não viu, e ela muda o que a linha da
Champions significa: **as duas primeiras colunas não contam o mesmo trecho do passado**.

### A tabela do ticket, reproduzida

Variante `A_ticket`. Cada campo sai como `medido / ticket`.

| competição | jogos-âncora | pares | jogos na própria competição | jogos em tudo, 180 dias | % com < 5 na competição | % com < 5 contando tudo |
|---|---|---|---|---|---|---|
| Copa do Brasil | 8 | 16 | **10,2** / 10,2 | **25,6** / 25,5 ⚠️ | **19%** / 19% | **0%** / 0% |
| Sudamericana | 15 | 30 | **8,9** / 8,9 | **12,5** / 12,5 | **27%** / 27% | **0%** / 0% |
| Copa do Mundo | 80 | 160 | **2,0** / 2,0 | **2,0** / 2,0 | **96%** / 96% | **96%** / 96% |
| Champions | 51 | 102 | **4,0** / 4,0 | **1,0** / 1,0 | **69%** / 69% | **100%** / 100% |

### A receita, e o que cada pedaço dela vale

Nenhum dos quatro pedaços é escolha de gosto: trocar qualquer um deles quebra a reprodução. Três
deles têm o número da troca medido nas variantes; o quarto — o corte das âncoras — não ganhou
variante própria porque herda o argumento já publicado do universo congelado.

- **O corte de tempo das âncoras é o universo congelado** (`taskf_universo()`), com o teto no
  instante de 04/08 12:00 UTC. O ticket foi aberto às **22:52 UTC** daquele dia; entre ~02:00 e
  16:00 UTC não há jogo nenhum na base, então qualquer instante do vão devolve o mesmo conjunto.
  É o mesmo argumento de "instante, não dia" que o universo congelado já fazia para os 169 jogos.
- **As âncoras são só os jogos ENCERRADOS**, `status_short = 'FT'` (variante `D`). Sem isso a Copa
  do Mundo sai 2,1 e 94% em vez de 2,0 e 96% — os 9 jogos de mata-mata decididos na prorrogação ou
  nos pênaltis entram como âncora e puxam a conta.
- **A unidade é o par (jogo, time)**, não o time distinto (variante `G`). O cabeçalho do ticket
  diz "times com < 5 jogos", mas um time entra uma vez por jogo que disputa. Por time distinto a
  Champions vai a 74% e a Copa do Mundo a 100%, e só **5 dos 16 campos** continuam batendo.
- **As duas colunas contam trechos diferentes do passado** — ver abaixo. É o pedaço que não se
  adivinha.

⚠️ O corte é aplicado a `fact_fixtures`, e **não** ao universo de 169 jogos das células. São
conjuntos diferentes de propósito: as células medem jogo liquidado COM preço nos 5 mercados do
Motor, e a Champions não tem um único jogo lá dentro (a #51 mediu isso). A tabela do ticket é
sobre jogos, não sobre apostas — é por isso que a Champions pode ser diagnosticada aqui e não pôde
ser medida nas células, e é por isso que o `jogos_esperados = 169` não se aplica a nada nesta
seção. Nas duas copas os conjuntos coincidem (8 e 15 jogos, os mesmos das células); na Copa do
Mundo são 80 âncoras contra 79 jogos medidos.

### ⚠️ As duas colunas do ticket não contam o mesmo passado — e a Champions é a prova

"Jogos na própria competição" conta o histórico **inteiro** do time naquela competição, todas as
temporadas, sem limite de tempo. "Jogos em tudo, 180 dias" conta todas as competições, mas só nos
180 dias anteriores ao jogo.

Sob um recorte comum, `tudo` ⊇ `própria` e a segunda coluna **nunca** poderia ser menor que a
primeira. A linha da Champions tem 4,0 e 1,0. Não é erro de medição do autor nem falha de
reprodução nossa: é a assinatura de dois recortes diferentes na mesma tabela, e a decomposição
mostra onde a diferença mora. Os 102 pares contam **405** partidas de Champions no total
(`soma_propria` da `A`), das quais só **96 são da temporada corrente** (`soma_propria` da `F`, que
escopa por temporada) — as outras 309 são de 2024 e 2025, e nenhuma delas cabe em 180 dias. Dentro
dos 180 dias sobram **101** partidas contando todas as competições (`soma_tudo` da `A`), e 96
delas são as mesmas partidas de Champions desta temporada: o campeonato nacional daqueles times
rende **cinco** partidas na base inteira. O 4,0 é histórico antigo da mesma competição; o 1,0 é o
presente em tudo.

Consequência para quem for ler a tabela de novo: **a leitura do ticket sobre a Champions se
sustenta pelo lado do 1,0**, que é real e é o que interessa ("aqueles times têm 1 jogo na nossa
base em 180 dias, porque não coletamos o campeonato nacional deles"). O que não se sustenta é a
comparação dos dois números entre si — "é pior do que a conta por competição sugere" está certo
pelo motivo errado, e a mesma frase aplicada às outras três linhas induziria a erro.

### A única divergência: uma partida, 30 minutos dentro da fronteira

Copa do Brasil, coluna "em tudo, 180 dias": medimos 25,6 e o ticket publicou 25,5. São 16 pares,
então a média é uma fração de denominador 16 — e a diferença inteira é **409 partidas contadas
contra 408**. Uma.

Ela está identificada:

| | |
|---|---|
| jogo-âncora | `1546843` — Atlético Paranaense × **Vitória**, Copa do Brasil, 04/08/2026 00:00 UTC |
| fronteira dos 180 dias | 05/02/2026 **00:00** UTC |
| partida na fronteira | `1492126` — Palmeiras × **Vitória**, Brasileirão 2026, 05/02/2026 **00:30** UTC |

A identificação não é dedução: `analyses/taskf_partida_da_fronteira.sql` lista todo par (âncora,
partida do histórico) em que as duas réguas discordam, sobre as mesmas âncoras da reconciliação.
A saída tem **uma linha**, e é esta, com `distancia_da_fronteira_min = 30`.

A partida cai meia hora dentro da fronteira — ela é a **marginal** sob qualquer régua de 180 dias,
e é por isso que uma diferença de régua aparece nela e em mais nada.

| régua da fronteira | conta a partida? | Copa do Brasil "em tudo" | campos exatos |
|---|---|---|---|
| `A` — instante, inclusiva (`kickoff >= âncora − 180 dias`) | sim | 25,6 (409) | 15 / 16 |
| `C` — data, inclusiva (`DATE(l) >= DATE(a) − 180`) | sim | 25,6 (409) | 15 / 16 |
| `B` — data, **estrita** (`DATE(l) > DATE(a) − 180`) | não | **25,5** (408) | 16 / 16 |

⚠️ **Não é a granularidade, é a estriteza** — e isso está medido, não deduzido. Trocar instante por
data sem mexer no sinal (`C`) devolve os mesmos números da `A`, campo a campo: a partida das 00:30
continua dentro. Quem a exclui é o `>` da `B`, que descarta o dia inteiro da fronteira e por isso
é até 24 horas mais apertada que a régua por instante.

⚠️ **A `B` não é a receita, e isto é deliberado.** Ela não é a convenção alternativa natural — é a
convenção *mais apertada*, e adotá-la porque o último número bate seria calibrar até o resultado
sair, o oposto do que o universo congelado fez com o teto (lá a robustez veio de o vão de catorze
horas devolver o mesmo conjunto). A fronteira inclusiva fica, com o resíduo explicado. Os outros
quinze campos são **insensíveis** às três réguas: nenhum deles se mexe entre `A`, `B` e `C`.

Não dá para saber, de fora, qual régua o autor usou — e não precisa: a divergência inteira é uma
partida em 409.

### As sete variantes, e o que cada uma troca

Cada uma mexe em **uma** coisa em relação à `A`, para a diferença ser atribuível. Uma variante que
mexesse em duas mediria a soma dos dois efeitos e não falsificaria nenhum — é por isso que a
leitura literal de "partidas encerradas" (AET e PEN dos dois lados) não tem variante própria: ela é
a composição de `D` com `E`.

| variante | campos exatos | o que ela troca |
|---|---|---|
| `A_ticket` | **15 / 16** | a receita |
| `B_fronteira_estrita_por_data` | 16 / 16 | a fronteira dos 180 dias em data e estrita (`>`) |
| `C_fronteira_inclusiva_por_data` | 15 / 16 | a fronteira em data e inclusiva (`>=`) — igual à `A` |
| `D_ancoras_com_pen_aet` | 7 / 16 | AET e PEN entram como âncora, e só como âncora |
| `E_historico_com_pen_aet` | 8 / 16 | AET e PEN entram no histórico, e só nele |
| `F_como_o_pit_conta` | 7 / 16 | a contagem que o PIT de produção realmente faz |
| `G_por_time_distinto` | 5 / 16 | a unidade: time distinto no lugar do par (jogo, time) |

### ⚠️ A coluna 1 do ticket é mais generosa que produção — o artefato é maior do que ele mediu

A variante `F` responde uma pergunta que o ticket não faz: o que o Motor **de fato** enxerga.
Produção escopa por competição **e temporada** (é o join do `int_futebol_team_form_pit`, e é a
célula `base`), enquanto a coluna 1 do ticket conta todas as temporadas daquela competição.

| competição | coluna 1 do ticket | o que o PIT conta | % < 5 no ticket | % < 5 no PIT |
|---|---|---|---|---|
| Copa do Brasil | 10,2 | **2,2** | 19% | **94%** |
| Sudamericana | 8,9 | **3,5** | 27% | **50%** |
| Champions | 4,0 | **0,9** | 69% | **100%** |
| Copa do Mundo | 2,0 | 2,0 | 96% | 96% |

O time de Copa do Brasil não é tratado como um time de 10,2 jogos: é tratado como um time de
**2,2**. A tese do ticket sai reforçada, não enfraquecida — o vão entre o que o Motor usa (2,2) e
o que existe (25,6 em 180 dias, 26,4 na temporada corrente contando tudo) é maior do que os
10,2 → 25,5 da tabela publicada.

E a Copa do Mundo tem uma invariante própria, visível nas **sete** variantes: as duas colunas dela
são sempre **iguais entre si** — 2,0 e 2,0 na `A`, 2,1 e 2,1 na `D`, 1,8 e 1,8 na `G`. Juntar
competição não acrescenta nada porque não há outra competição, e mudar de temporada não acrescenta
nada porque não há outra temporada. O deserto dela não é artefato de escopo, de recorte, de
temporada nem de convenção de fronteira: é o dado. O que move a linha da Copa do Mundo é só quem
entra na conta (âncora e unidade), e isso move todas as linhas.

### O diagnóstico e as células dizem a mesma coisa

O ticket previu, a partir desta tabela, que juntar o histórico recuperaria Copa do Brasil e
Sudamericana inteiras. A célula `escopo` mediu exatamente isso na #53: o piso 5 sobe de 69 para 92
jogos, e os 23 que cruzam são **as 15 partidas de Sudamericana e as 8 de Copa do Brasil** — as
mesmas 15 e 8 âncoras que aparecem na tabela desta seção. Aqui, a coluna "% com < 5 contando tudo"
dá **0% nas duas**, e a variante `F` mostra que a contagem que a célula `escopo` usa (todas as
competições, temporada corrente) também dá 0% nas duas.

A terceira leitura do ticket — "a Copa do Mundo é 47% da amostra de medição" — bate com os 46,7%
(79 de 169) que a #51 publicou na composição do universo congelado.

### Observação de passagem: 142 partidas encerradas que não entram no histórico de ninguém

A variante `E` foi construída para falsificar o lado do histórico da leitura literal de "partidas
encerradas", e mediu, de passagem, um efeito que não é da [F] mas fica registrado. O `team_log` de
todo o pipeline filtra `status_short = 'FT'`, e jogo decidido na prorrogação (`AET`) ou nos
pênaltis (`PEN`) não é `FT`. Contagem sobre a `fact_fixtures` inteira (a query está na Reprodução),
com `status_short IN ('FT','AET','PEN')` como denominador:

| competição | encerradas | fora do histórico (AET+PEN) | % |
|---|---|---|---|
| Copa do Brasil | 386 | 55 | **14,2%** |
| Copa do Mundo | 104 | 9 | 8,7% |
| Sudamericana | 446 | 30 | 6,7% |
| Libertadores | 439 | 19 | 4,3% |
| Champions | 636 | 26 | 4,1% |
| **base inteira** | **8.094** | **142** | 1,8% |

As três que faltam para 142 são de Ligue 1 (2) e Bundesliga (1), e as três são jogo de
acesso/rebaixamento — `Relegation Round`, `Semi-finals` e `Final` no campo `round`. Liga de pontos
corridos não produz prorrogação; as copas produzem.

No agregado é 1,8% e ninguém veria; nas copas de mata-mata é uma partida em sete. Sob a contagem
`E`, a média da Copa do Brasil na própria competição vai de 10,2 para **11,4**. Não é para mexer
aqui — a #56 e a #49 proíbem mudar pipeline. **Virou a issue #71** (`needs-triage`), com a medição
junto e a decisão de desenho explicitada: ligar AET/PEN exige trocar `goals_*` por
`score_fulltime_*`, porque nos 21 jogos `AET` da base as duas colunas diferem em 21 de 21 e gol de
prorrogação entraria em média que alimenta mercado precificado em 90 minutos. E `PEN` **não** é
sinônimo de empate — só 83 dos 121 terminaram empatados no tempo normal, o resto é confronto de ida
e volta decidido no agregado.

⚠️ Mexer nisso **muda as quatro células da [F]**. Se for para fazer, é depois que a [F] fechar, ou
as células deixam de compartilhar a base comum que as torna comparáveis.

### Por que esta seção não vira guarda

As outras seções da [F] viraram invariante cobrada (#55). Esta não, e o motivo é o mesmo que
justifica as outras: guarda que fica vermelha por trabalho alheio deixa de ser sinal.

- A coluna 1 **não tem limite de tempo**. Backfill de temporada antiga — o passo padrão de todo
  rollout de liga — move o número legitimamente.
- O conjunto de âncoras é jogo `FT` dentro do corte, e há **4 jogos `PST` do Brasileirão** lá
  dentro. Remarcação ou resultado ingerido depois muda âncora e histórico ao mesmo tempo.

O gabarito de 16 números mora **dentro da análise**, com coluna de delta e um contador
`campos_exatos` por linha. Quem rodar vê a divergência sem conferir de olho, e nada fica vermelho
em quem não pediu.

### Reprodução

```bash
cd dbt_futebol

DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target dev \
  --select taskf_reconciliacao_180d taskf_partida_da_fronteira

bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_reconciliacao_180d.sql
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_partida_da_fronteira.sql

# as duas contagens de passagem desta seção: o rodapé de AET/PEN e os PST dentro do corte
bq query --use_legacy_sql=false --project_id=smartbetting-dados <<'SQL'
SELECT COALESCE(competition, 'TOTAL') AS competicao,
       COUNTIF(status_short IN ('FT','AET','PEN'))                     AS encerradas,
       COUNTIF(status_short IN ('AET','PEN'))                          AS fora_do_historico,
       COUNTIF(status_short = 'PST'
               AND kickoff_utc >= TIMESTAMP('2026-06-16')
               AND kickoff_utc <  TIMESTAMP('2026-08-04 12:00:00'))    AS pst_no_corte
FROM `smartbetting-dados.futebol.fact_fixtures`
GROUP BY ROLLUP(competition)
HAVING fora_do_historico > 0 OR pst_no_corte > 0
ORDER BY fora_do_historico DESC
SQL
```

O target é indiferente: `fact_fixtures` é a mesma tabela de produção em `dev`, `prod` e `taskF`, e
nenhuma das duas análises lê o dataset de medição. A reconciliação sai com **28 linhas** — sete
variantes × quatro competições —, e a soma de `campos_exatos` na variante `A_ticket` é **15**. A
análise da fronteira sai com **uma** linha.

⚠️ `bq query` com o SQL como argumento trava nesta máquina; por redirecionamento ou heredoc,
funciona.

---

## Ticket #57 — Os dois confundidores, medidos

`analyses/taskf_forca_do_adversario.sql` + `analyses/taskf_rodizio_de_elenco.sql` · execução
2026-08-13 14:55–14:57 UTC · commit `d6ad236` · dataset `futebol_taskF`

Os dois confundidores que podem inverter a recomendação da task: se o ganho de amostra do merge
vier com viés de nível, ou descrever um elenco que não entra em campo, juntar deixa de ser
gratuito. O ticket de origem registrou o segundo como ressalva sem número e não mencionou o
primeiro; a spec #49 pediu os dois com número.

### Veredito

**Força do adversário — efeito PEQUENO no que dá para medir, e o achado é o que não dá.** Na
única régua comparável entre competições — o `ppg` de liga do adversário — a partida emprestada
vale **1,387** contra **1,341** da nativa: 0,046 de diferença, nada. A mistura de nível que a
spec teme existe e é fina: 27 das 1.364 partidas do histórico fundido de um time de Brasileirão
são contra Série B (2,0%), e 40 das 1.542 de um time de Série B são contra Série A (2,6%). O que é
grande é o buraco: **40,7% das partidas emprestadas são contra adversário que a coleta não
alcança**, contra 3,5% das nativas — e é justamente nelas que o perfil de gols é outro.

**Rodízio de elenco — efeito REAL e MODERADO, 1,46 titular de 11.** Entre dois jogos consecutivos
de liga o mesmo time repete **8,34** dos 11 titulares; entre um jogo de liga e um de copa, apenas
**6,88**. A diferença sobrevive ao controle de calendário, então não é congestionamento. Mas não é
elenco reserva: entre dois jogos de liga o XI já troca 2,66 titulares sozinho, e a copa acrescenta
1,46 a isso — uma troca e meia a mais, não outro time.

Nenhum dos dois inverte a recomendação. Os dois entram na [B] como ressalva com tamanho: o merge
não é gratuito, mas o que ele cobra é 1,5 titular de elenco e uma fração de 2% a 3% de histórico
de nível diferente — e não o viés estrutural que o desenho temia.

### A conferência vem antes de tudo

A análise de força **reconstrói** o join de histórico do `int_futebol_team_form_pit`, porque
precisa da partida individual e o carimbo guarda só a contagem. Reconstrução é cópia, e cópia
deriva do original em silêncio — bastaria esquecer o `l.season = a.season` para o número sair
maior e com cara de certo.

Por isso a primeira linha da saída não é resultado, é conferência, par a par contra o carimbo das
células (#53):

| pares | batem a `base` | batem o `escopo` | veredito |
|---|---|---|---|
| 338 | **338** | **338** | `EXATA` |

As partidas classificadas como `nativa` são exatamente o `played_total` que a célula `base`
gravou, e o total (nativa + emprestada) exatamente o da `escopo`. O universo sai com **169** jogos,
o gabarito da macro. Sem essa linha verde, nada abaixo dela significa o que diz.

### O histórico, e de onde vem a parte emprestada

4.021 partidas alimentam as 338 âncoras do universo congelado. O merge acrescenta 1.159 delas
(28,8%) — e a composição não é a mesma nas duas metades:

| origem | partidas | adversário com `ppg` | fora da base | seleção |
|---|---|---|---|---|
| nativa | 2.862 | 2.306 | 101 (**3,5%**) | 313 (10,9%) |
| emprestada | 1.159 | 598 | 472 (**40,7%**) | 0 |

Por competição-âncora, só a parte emprestada:

| âncora | partidas emprestadas | fora da base | de onde vêm |
|---|---|---|---|
| brasileirao | 322 | **71,7%** | libertadores 121, copa_do_brasil 107, sudamericana 94 |
| serie_b | 174 | 54,6% | copa_do_brasil 174 |
| sudamericana | 275 | 31,3% | brasileirao 156, libertadores 103, copa_do_brasil 16 |
| copa_do_brasil | 388 | 15,5% | brasileirao 288, serie_b 40, libertadores 30, sudamericana 30 |
| copa_mundo | **0** | — | — |

⚠️ **O merge corta nos dois sentidos, e isso ninguém tinha escrito.** Para âncora de LIGA ele
piora a visibilidade do adversário: o histórico nativo de um time de Brasileirão é 100% contra
adversário que enxergamos, e o emprestado é 71,7% contra adversário que não. Para âncora de COPA
ele **melhora**: o histórico nativo da Copa do Brasil tem 31,4% de adversário fora da base e o
emprestado tem 15,5%, porque o que ele empresta é jogo de campeonato nacional. Para a Copa do
Mundo não há o que emprestar — zero partidas, o que reproduz por outro caminho o que a #53 já
sabia.

E o peso importa: para âncora de copa o histórico emprestado é a MAIOR PARTE do fundido — 388 de
423 na Copa do Brasil (91,7%) e 275 de 379 na Sudamericana (72,6%). O merge não complementa o
passado dessas âncoras, ele praticamente o constitui.

⚠️ **A spec supôs que o buraco era Série C e D. É maior.** O adversário invisível de um time de
Brasileirão não vem da Copa do Brasil (só 16 das 235 partidas dele contra time fora da base): vem
da **Libertadores e da Sudamericana**, 121 e 94 partidas, 100% contra clube sul-americano cuja
liga nacional não coletamos. A Série C e D existem e são o caso da Série B (95 partidas), mas no
agregado o continente pesa mais que a divisão de acesso.

### ⚠️ `ppg` de copa de mata-mata é sobrevivência, não força

A leitura ingênua do `ppg` PIT diz que a partida emprestada foi contra adversário **mais forte**:
1,622 contra 1,366 da nativa. É artefato, e a régua que o denuncia está na própria saída
(`nivel = 'ppg_referencia'` — a média de `ppg` sobre todas as linhas do PIT de cada competição):

| competição | média de `ppg` |
|---|---|
| Copa do Brasil | **2,609** |
| Champions (qualifs) | 1,750 |
| Copa do Mundo | 1,661 |
| Sudamericana | 1,565 |
| Libertadores | 1,438 |
| Brasileirão | 1,364 |
| Série B | 1,333 |

Numa liga de pontos corridos a média é quase constante por construção, e medido é isso: 1,364 e
1,333. Numa copa de mata-mata quem perde é eliminado e para de jogar, então quem chega à rodada
seguinte é quem venceu — e a média sobe para 2,609. A Libertadores, que tem fase de grupos, volta
para 1,438 e confirma o mecanismo.

Consequência prática: **o `ppg` que o modelo calcula não serve para comparar adversários entre
competições.** O `ppg_liga_medio` corrige a sobrevivência — é sempre calculado sobre jogos de
pontos corridos — e é ele que dá o 1,387 contra 1,341 do veredito. Mas nem ele mede NÍVEL: continua
relativo à liga do adversário, e um time de Série B com 1,40 não vale o mesmo que um de Série A
com 1,40. Nível só sai da liga a que o adversário pertence, que é o nível `liga_do_adversario`.

⚠️ E a régua corrigida **cobre pouco justamente onde importa**: só 632 das 1.159 partidas
emprestadas (54,5%) têm `ppg` de liga, contra 2.312 das 2.862 nativas (80,8%). O 1,387 descreve a
metade visível da amostra emprestada e é silencioso sobre a outra.

### O canal por onde o viés chega: os gols

As premissas leem médias de gols, não `ppg`. É ali que o efeito aparece:

| âncora | origem | gols pró | gols contra |
|---|---|---|---|
| brasileirao | nativa | 1,333 | 1,321 |
| | emprestada | 1,457 | 0,826 |
| | **fundida** | **1,362** | **1,205** |
| serie_b | nativa | 1,149 | 1,139 |
| | emprestada | 1,649 | 0,615 |
| | **fundida** | **1,206** | **1,080** |

O merge move a média de gols sofridos em **−0,116** no Brasileirão (−8,8%) e **−0,059** na Série B
(−5,2%), e a de gols marcados em +0,029 e +0,057. É pouco em valor absoluto, e é sempre no mesmo
sentido: o time fundido parece marcar um pouco mais e sofrer bem menos.

O extremo mostra por quê. As 95 partidas em que um time de Série B enfrentou adversário fora da
base — Copa do Brasil, fases iniciais — têm **2,221 gols pró e 0,168 contra**. Nenhum jogo de
campeonato se parece com isso. São 6,2% do histórico fundido da Série B, e é essa fração que puxa.
As premissas que leem defesa (`defesa_forte`, `clean_sheets_altos`, `defesas_firmes`) são as
expostas.

### Rodízio: é o controle que dá sentido ao número

"6,88 dos 11 titulares se repetem entre a liga e a copa" não quer dizer nada sozinho — lesão,
suspensão e desgaste mexem no XI o tempo todo. O que responde é a comparação com o par liga↔liga
dos mesmos times, medida na mesma execução:

| estrato | pares | sobreposição média | % dos 11 | mediana | dias entre |
|---|---|---|---|---|---|
| liga ↔ liga (**controle**) | 635 | **8,34** | 75,8% | 9 | 7,7 |
| liga ↔ copa (**tratamento**) | 300 | **6,88** | 62,5% | 7 | 3,2 |
| copa ↔ copa | 243 | 8,32 | 75,6% | 9 | 9,1 |

Duas leituras. A primeira: o rodízio é da TRANSIÇÃO entre competições, não da copa — dois jogos de
copa seguidos repetem tanto quanto dois de liga (8,32 contra 8,34). A segunda: a diferença é
**−1,46 titular**, ou 13,3 pp.

### O rodízio não é calendário — e isso foi medido, não suposto

Par liga↔copa tem 3,2 dias no meio e par liga↔liga tem 7,7. Rodízio por congestionamento e rodízio
por prioridade de competição são coisas diferentes, e só a segunda é a pergunta do ticket.
Cortando os dois estratos pela mesma distância entre jogos:

| dias entre os jogos | liga ↔ liga | liga ↔ copa | diferença |
|---|---|---|---|
| até 3 | 8,17 (n=127) | 6,81 (n=215) | **−1,36** |
| 4 a 5 | 8,58 (n=119) | 6,96 (n=77) | **−1,62** |
| 6 a 7 | 8,61 (n=211) | 8,00 (n=3) | −0,61 |
| 8 ou mais | 7,98 (n=178) | 7,80 (n=5) | −0,18 |

Nas duas faixas com amostra dos dois lados a diferença sobrevive inteira. As duas de baixo têm 3 e
5 pares no tratamento e não sustentam leitura — ficam na tabela porque escondê-las faria o corte
parecer mais limpo do que é.

### Por time: 24 dos 33 caem, e o topo é quem joga continental

| time | liga ↔ copa | liga ↔ liga | delta |
|---|---|---|---|
| Vasco da Gama | 4,58 (n=19) | 9,20 (n=10) | **−4,62** |
| São Bernardo | 6,00 (n=1) | 8,89 (n=19) | −2,89 |
| Mirassol | 5,59 (n=17) | 8,09 (n=11) | −2,50 |
| Flamengo | 5,21 (n=14) | 7,67 (n=12) | −2,46 |
| Athletic Club | 6,80 (n=5) | 8,71 (n=17) | −1,91 |
| Atletico-MG | 6,60 (n=15) | 8,50 (n=12) | −1,90 |
| … 18 times entre −1,68 e −0,01 … | | | |
| Santos | 7,68 (n=19) | 7,00 (n=10) | +0,68 |
| Vitoria | 9,20 (n=5) | 8,17 (n=18) | +1,03 |
| Londrina | 10,00 (n=1) | 8,84 (n=19) | +1,16 |
| Corinthians | 7,00 (n=17) | 5,83 (n=12) | **+1,17** |

Os 33 times com par liga↔copa têm todos os dois estratos: **24 caem e 9 sobem**. O rodízio não é
regra de campeonato, é escolha de clube — e os que mais poupam são os que disputam Libertadores e
Sudamericana.

Os outros **67** não têm nenhum par liga↔copa, e "não jogam as duas coisas" só explica a maioria
deles. O nível `times_do_universo` mede quem são, porque a leitura preguiçosa dessa linha é
exatamente o tipo de coisa que a [B] herdaria como verdade:

| categoria | times | jogos no pool | com par liga↔copa |
|---|---|---|---|
| seleção (Copa do Mundo) | 48 | 190 | 0 |
| clube cuja liga nacional não coletamos | 12 | 102 | 0 |
| clube de liga sem jogo de copa dentro do teto | 6 | 120 | 0 |
| joga os dois | 34 | 878 | **33** |

São **100 times no universo**, e 100 − 33 = 67 fecha. Os 6 da terceira linha não são time que não
joga copa: são time de liga que, dentro do teto congelado, não teve jogo de copa — outro caso, e
não pertence a nenhum dos dois primeiros. E um dos 34 que jogam os dois nunca teve dois jogos
consecutivos de tipos diferentes, então não produziu par.

⚠️ O `times_sem_par_liga_copa` é contado sobre quem tem PELO MENOS UM par de qualquer tipo, então
time com um único jogo no pool escaparia dele. Hoje não escapa ninguém — `times_sem_par_nenhum` é
**0** nas quatro categorias —, e é por isso que a conta fecha em 100. A coluna existe para que o
dia em que deixar de fechar seja visível em vez de calado.

### ⚠️ A cobertura de lineups NÃO é de 100% em todas as competições

O critério de aceite do ticket parte dessa afirmação. Ela é falsa, e falha exatamente onde o
próprio ticket manda olhar:

| competição | lados encerrados na temporada | com XI utilizável | % |
|---|---|---|---|
| Copa do Brasil | 202 | 141 | **69,8%** |
| Libertadores | 236 | 231 | 97,9% |
| Sudamericana | 242 | 240 | 99,2% |
| Brasileirão | 410 | 410 | 100,0% |
| Série B | 400 | 400 | 100,0% |
| Copa do Mundo | 190 | 190 | 100,0% |
| Champions | 102 | 102 | 100,0% |

Os 61 lados de Copa do Brasil sem XI utilizável — 46 sem escalação nenhuma e 15 com escalação
incompleta — estão nas fases iniciais, as mesmas em que o adversário está fora da base. **Os dois
confundidores têm o mesmo ponto cego**, e ele é estrutural: nas primeiras rodadas o adversário é
de Série C ou D, e a API não traz nem a classificação dele nem a escalação do jogo.

Dentro do pool que esta medição usa o estrago é menor — 94,8% a 100% —, porque o pool só tem times
do universo e o time de Série C não está lá. Nenhum lado sem XI utilizável entrou num par: foram
contados e descartados — **11 pares no `copa_copa`, 1 no `liga_copa`, 0 no `liga_liga`** —, nunca
completados. A conta fecha nos três estratos (254 = 243 + 11, 301 = 300 + 1, 635 = 635 + 0), e o
fechamento não é decorativo: ver o quarto achado de percurso.

### O que a fase `real` da escalação evitou

`fact_fixture_lineups_players` dedupa por (fixture_id, player_id) com latest-wins, e não por
(fixture_id, team_id, fase). Quando a escalação `confirmed` (~T-30min) e a `real` (pós-jogo)
discordam sobre um jogador, as duas sobrevivem — uma por jogador — e o time aparece com 12 ou 13
"titulares". O escopo `temporada_sem_filtro_de_fase` do nível `cobertura` repete a contagem sem o
filtro, e a diferença é o tamanho do artefato:

| competição | sem filtro de fase | com filtro `real` | lados que o artefato criaria |
|---|---|---|---|
| Série B | 383 de 400 | 400 de 400 | 17 |
| Copa do Mundo | 178 de 190 | 190 de 190 | 12 |
| Sudamericana | 238 de 242 | 240 de 242 | 2 |
| Brasileirão | 409 de 410 | 410 de 410 | 1 |
| Copa do Brasil | 140 de 202 | 141 de 202 | 1 |

Sem o filtro, 33 lados entrariam na medição com XI de tamanho errado — e "sobreposição de 11"
estaria comparando conjuntos de tamanhos diferentes, inflando o número sem ninguém ver. O que
sobra depois do filtro é falha de coleta, não dedup, e é o que a tabela anterior mostra.

### ⚠️ Quatro achados de percurso, os quatro sobre a própria maquinaria

Corrigidos antes de qualquer número desta seção ser publicado. Ficam registrados porque nenhum
deles é específico da #57 — os quatro voltam a morder na próxima análise que alguém escrever neste
repositório.

1. **`APPROX_QUANTILES` é um sketch.** Duas execuções seguidas, dado idêntico e query idêntica,
   devolveram **1,313 e depois 1,294** para a mediana de `ppg` do histórico nativo do Brasileirão,
   e **1,333 e depois 1,0** para a da Copa do Mundo. `macros/taskf_mediana.sql` ordena o grupo e
   indexa — exata e determinística.

2. **`AVG` sobre inteiro empata no arredondamento.** O estrato `copa_copa` na faixa de 4 a 5 dias
   saiu **8,43 e depois 8,42**: a média verdadeira é 8,425, cai em cima do desempate do `ROUND`, e
   o `AVG` do BigQuery combina médias parciais em ponto flutuante. Onde o somando é INT64
   (sobreposição, dias entre jogos, gols) a média passou a sair de `SUM/COUNT`. Os dois `ppg_*`
   seguem em `AVG`, porque o somando já é FLOAT64 e não há soma exata a recuperar — está declarado
   no comentário da análise, não escondido.

3. **`bq query` trunca em 100 linhas por padrão, calado.** A análise de rodízio tem 121 linhas: o
   nível `time` perdia os últimos times em ordem alfabética, e a contagem saiu **29 times quando
   são 33** — com Vasco da Gama, que é o maior efeito de rodízio da tabela, entre os cortados. A
   saída sai com cara de completa. `--max_rows` está agora nos dois cabeçalhos, ao lado da
   armadilha que já se conhecia (SQL como argumento trava a máquina).

4. **`NULL AND TRUE` é NULL, e o contador de descarte pulava esses pares.** O critério de par
   utilizável era `xa.n_titulares = 11 AND xb.n_titulares = 11`, e lado SEM escalação nenhuma sai
   do LEFT JOIN com `n_titulares` NULL — logo o critério dava NULL, não FALSE, e o
   `COUNTIF(NOT utilizavel)` o pulava. Esses pares ficavam em `pares_no_estrato` e em NENHUMA das
   duas colunas, quebrando `pares_no_estrato = pares + pares_descartados` em silêncio e
   **exatamente onde a cobertura é pior** — que é a única coisa que `pares_descartados` existe para
   mostrar. Os descartes iam de 7 para os 12 reais. As médias não se mexeram (o `IF(NULL, x, 0)` já
   dava 0 e o `COUNTIF` já não contava), mas a frase "foram contados e descartados" estava errada
   sobre 5 pares antes desta correção.

### O que ficou de fora, e por quê

- **O rótulo `fora_da_base` do nível `liga_do_adversario` não bate exatamente com a coluna
  `adv_fora_da_base`**: 583 partidas contra 573, 10 em 4.021. A coluna é por base inteira (o time
  tem liga em ALGUMA temporada?) e o rótulo é por temporada (tem liga NAQUELA?). São 40 times nessa
  situação, quase todos rebaixados ou promovidos entre o backfill de 24/25 e agora — Amazonas,
  Brusque, Ferroviária, Burnley, Empoli. Fica declarado em vez de reconciliado: as duas perguntas
  são legítimas e a diferença entre elas é informação.
- **Nenhuma medida ABSOLUTA de nível foi construída.** Um rating cross-liga responderia "Série B
  vale quanto de Série A?", não existe na base e não cabe numa task de medição. O que existe é a
  liga a que o adversário pertence, que é observável, e é com ela que o veredito é dado.
- **`dim_leagues`, `dim_teams` e `fact_fixture_lineups_players` entraram no dataset de medição.** A
  ancestria das quatro células não passava por eles. Nenhum dos seis nós de premissas os
  referencia, então materializá-los no `futebol_taskF` não toca célula nenhuma — mas quem
  reproduzir precisa rodá-los antes, e o comando está na Reprodução.

### Por que esta seção não vira guarda

Mesmo argumento da #56: guarda que fica vermelha por trabalho alheio deixa de ser sinal.

- A cobertura de escalação **melhora sozinha** quando a API preenche um jogo antigo, e piora quando
  uma liga nova entra sem lineups. Nos dois casos o vermelho não seria da [F].
- O conjunto de partidas do histórico **não tem limite inferior de tempo dentro da temporada**, e
  backfill de temporada corrente move as contagens legitimamente.
- A conferência que de fato precisa ser cobrada — reconstrução contra carimbo — **já está dentro da
  análise**, como primeira linha e com veredito próprio. Quem rodar vê `EXATA` ou vê o número
  divergente, sem conferir de olho e sem deixar nada vermelho para quem não pediu.

### Reprodução

```bash
cd dbt_futebol

# uma vez: os três nós que faltavam no dataset de medição (não tocam célula nenhuma)
DBT_PROFILES_DIR=.. ../.venv/bin/dbt run --target taskF \
  --select dim_leagues stg_futebol_leagues dim_teams stg_futebol_teams \
           fact_fixture_lineups_players stg_futebol_fixture_lineups_players

DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF \
  --select taskf_forca_do_adversario taskf_rodizio_de_elenco

bq query --use_legacy_sql=false --max_rows=100000 --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_forca_do_adversario.sql
bq query --use_legacy_sql=false --max_rows=100000 --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_rodizio_de_elenco.sql

# os dois números de passagem desta seção que não saem das análises
bq query --use_legacy_sql=false --project_id=smartbetting-dados <<'SQL'
-- (a) o `ppg` é invariante de célula? (ADR 0008) — a produção contra a última célula
--     materializada no dataset de medição, que é a `ambos`
WITH p AS (
  SELECT fixture_id, team_id, ppg FROM `smartbetting-dados.futebol.int_futebol_team_form_pit`
  WHERE season = 2026 AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')
),
t AS (
  SELECT fixture_id, team_id, ppg FROM `smartbetting-dados.futebol_taskF.int_futebol_team_form_pit`
  WHERE season = 2026 AND kickoff_utc < TIMESTAMP('2026-08-04 12:00:00')
)
SELECT COUNT(*) AS pares, COUNTIF(COALESCE(p.ppg,-1) = COALESCE(t.ppg,-1)) AS ppg_igual
FROM p JOIN t USING (fixture_id, team_id)
SQL

bq query --use_legacy_sql=false --project_id=smartbetting-dados <<'SQL'
-- (b) quem tem liga na base mas NÃO em 2026 — explica o descasamento de 583 contra 573
WITH tipos AS (
  SELECT DISTINCT league_id AS competition_id, league_type
  FROM `smartbetting-dados.futebol_taskF.dim_leagues`
),
lados AS (
  SELECT home_team_id AS team_id, competition_id, season FROM `smartbetting-dados.futebol.fact_fixtures`
  UNION ALL
  SELECT away_team_id, competition_id, season FROM `smartbetting-dados.futebol.fact_fixtures`
),
liga_por_time_season AS (
  SELECT DISTINCT l.team_id, l.season
  FROM lados l JOIN tipos t USING (competition_id)
  WHERE t.league_type = 'League'
)
SELECT
  COUNT(DISTINCT team_id) AS times_na_base,
  COUNT(DISTINCT IF(team_id NOT IN (SELECT team_id FROM liga_por_time_season WHERE season = 2026),
                    team_id, NULL)) AS na_base_mas_sem_liga_em_2026
FROM liga_por_time_season
SQL
```

A análise de força sai com **55 linhas** (1 de conferência, 3 de total, 14 de competição, 11 de
fonte, 19 de liga do adversário e 7 de referência de `ppg`) e a de rodízio com **121** (20 de
cobertura, 3 de total, 12 de estrato × dias, 82 de time e 4 de times do universo). As duas leem o
carimbo das células `base` e `escopo`, que precisa estar gravado — já estava, da #53. A consulta
(a) devolve **1.916 de 1.916** e a (b), **40 de 194**.

Rodadas duas vezes seguidas no commit carimbado, as duas devolvem CSV **idêntico linha a linha** —
é assim que o segundo e o terceiro achados de percurso ficam fechados por medição e não por
argumento.

⚠️ `bq query` com o SQL como argumento trava nesta máquina; por redirecionamento ou heredoc,
funciona. E sem `--max_rows` ele corta em 100 linhas sem avisar.

---

## Ticket #58 — As três respostas fechadas, e a Champions medida onde ela existe

`analyses/taskf_exclusao.sql` + `taskf_sobrevivencia.sql` + `taskf_saturacao_recorte.sql` +
`taskf_universo_congelado.sql` · execução 2026-08-13 17:49–18:13 UTC · **células** do commit
`7fdd1a3`, **análises** do `f293962` · dataset `futebol_taskF`

As três perguntas que a spec #49 cobra fechadas, mais a extensão que o grilling acrescentou. Duas
delas — a da Copa do Mundo e a da Champions — são perguntas sobre **quais jogos entram na conta**,
e não sobre o histórico que cada jogo carrega. Por isso o universo passou a ser um terceiro eixo da
medição, e as quatro células foram re-medidas com ele.

### Veredito

**Nenhuma das duas exclusões se sustenta na medição.** A da Copa do Mundo é imaterial em três das
quatro células no piso 5 e **idêntica** (ρ = 1,000) no piso 10; a da fase classificatória da
Champions é **idêntica** no piso 5 e no 10 nas duas células que refletem produção. Nos dois casos o
piso de amostra já faz o trabalho que a exclusão faria: dos 79 jogos de Copa do Mundo, **2** estão
acima do piso 5; dos 18 de Champions, **zero** — em `base` e em `escopo`.

Das quatro premissas de amostra curta, **duas sobrevivem** quando o histórico é real
(`clean_sheets_altos` e `defesa_forte`) e duas continuam sem evidência (`superioridade_xg` e
`tende_golear`).

E o eixo que a [F] mede continua sendo muito maior que as duas exclusões juntas: no piso 5, soltar
a competição move a ordenação para ρ = 0,648, enquanto a maior das exclusões a move para 0,964.

### O universo é um terceiro eixo — e não uma quinta célula

| | o que varia | onde mora |
|---|---|---|
| **célula** | qual HISTÓRICO cada jogo carrega | `macros/taskf_celula.sql` (escopo × recorte) |
| **universo** | quais JOGOS são medidos | `macros/taskf_universos.sql` (#58) |
| **janela** | qual coleta de ODDS foi lida | glossário do `CONTEXT.md` — nada a ver com a [F] |

Os quatro universos de uma célula saem do **mesmo INSERT**. Se `completo` e `sem_copa_mundo`
fossem duas execuções, a diferença entre elas carregaria uma reconstrução dos modelos dentro de si
— e a #55 mediu que uma reconstrução move 5 campos em 7.200 sozinha. Como a comparação COM/SEM
**é** o entregável, esse ruído entraria no lugar da resposta.

| universo | jogos | linhas | janela | por que existe |
|---|---|---|---|---|
| `completo` | **169** | 8.567 | 16/06 → 04/08 | o congelado da [0.1], o primário |
| `sem_copa_mundo` | **90** | 4.428 | **10/07** → 04/08 | o lado SEM da pergunta 7 da spec |
| `estendido` | **228** | 11.554 | 16/06 → 12/08 | o secundário, e o único onde a Champions existe |
| `estendido_sem_champions_classif` | **210** | 10.606 | 16/06 → 12/08 | o lado SEM da pergunta 24 |

Os quatro carregam o mesmo `odds_loaded_at` (12/08 13:24:15) e o mesmo `git_sha` — conferido pela
Costura B, que desde este ticket cobra por (universo × célula).

### Resposta 1 — quantos jogos passam a satisfazer o piso de 5, célula a célula

`analyses/taskf_saturacao_recorte.sql`, bloco `piso` · re-derivado nesta execução

| piso | `base` | `escopo` | `recorte` | `ambos` |
|---|---|---|---|---|
| 0 | 169 | 169 | 169 | 169 |
| 3 | 90 | **113** | 103 | **113** |
| 5 | **69** | **92** | **81** | **92** |
| 10 | 67 | 76 | 73 | **83** |

Com o histórico junto, o piso 5 vai de **69 para 92 jogos** — 41% → 54% do universo — sem
descartar nada. O eixo de escopo faz sozinho todo esse ganho; soltar só a temporada leva a 81, e
soltar os dois não acrescenta nem um jogo ao que a competição já tinha aberto. A tabela reproduz a
#54 e a #55 número a número, agora sobre células re-medidas com o eixo de universo dentro.

⚠️ **Os 77 jogos que continuam abaixo do piso 5 na `base` são a Copa do Mundo inteira menos dois.**
Isso não é leitura da tabela acima — é o bloco `excluido` do `taskf_exclusao.sql`: dos 79 jogos de
Copa do Mundo, **2** têm `min_jogos` ≥ 5 em qualquer das quatro células, e o maior `min_jogos` do
conjunto é **6**. É esse número que decide a resposta 3.

### Resposta 2 — quais das quatro premissas sobrevivem quando o histórico é real

`analyses/taskf_sobrevivencia.sql` · universo `completo`, piso 5

A regra foi escrita antes de olhar: **sobrevive** quem tem `diferenca_p5` > 0 nas **duas** células
de escopo solto (`escopo` e `ambos`) com n ≥ 25 nas duas. As duas células, e não uma, porque uma
premissa que só melhora sob `ambos` melhora quando os dois eixos se soltam — e aí não dá para
dizer qual deles a salvou, que é a pergunta 9 da spec. O n = 25 é o ponto em que o encolhimento
`n/(n+50)` do próprio Teste 2 passa de 1/3; ele sai da constante que já existe, não de uma régua
nova.

| premissa | `base` | `escopo` | `recorte` | `ambos` | veredito |
|---|---|---|---|---|---|
| `clean_sheets_altos` | −1,7 (24) | **+6,3** (35) | +7,8 (63) | **+30,0** (34) | **SOBREVIVE** |
| `defesa_forte` | −3,3 (12) | **+10,3** (28) | +5,7 (29) | **+15,1** (25) | **SOBREVIVE** |
| `superioridade_xg` | −8,9 (31) | −4,1 (44) | +1,7 (45) | −5,6 (60) | SEM EVIDÊNCIA |
| `tende_golear` | −18,5 (18) | −22,7 (21) | −20,3 (49) | +2,0 (52) | SEM EVIDÊNCIA |

E a amostra curta delas, de `base` para as três outras células: `clean_sheets_altos` 77,1% →
62,4% / 49,6% / 63,0%; `defesa_forte` 82,9% → 60,6% / 62,3% / 63,2%; `superioridade_xg` 71,6% →
61,1% / 61,5% / 53,5%; `tende_golear` 88,3% → 83,6% / 70,7% / **67,3%**.

As duas que caem, caem por motivos diferentes: `superioridade_xg` é **negativa nas duas** células
de escopo solto (o sinal não aparece, ele some), e `tende_golear` é positiva **só em `ambos`**
(+2,0), depois de −22,7 em `escopo` — exatamente o caso que a regra das duas células existe para
não deixar passar.

⚠️ **`defesa_forte` passa com n = 25 exatamente na `ambos`** — em cima da borda da régua. Uma linha
a menos e ela sairia com ressalva. Fica dito porque a borda é da regra deste documento, não do
dado.

**A régua discrimina**: aplicada às 39 linhas do benchmark preferido, **10 sobrevivem** e 29 ficam
sem evidência — nenhuma com ressalva. Se metade do catálogo "sobrevivesse", sobreviver não
significaria nada. As dez: `adversario_limitado`, `clean_sheets_altos`, `defesa_forte`,
`defesas_firmes`, `defesas_vazaveis` (BTTS), `favorito_irregular`, `historico_under`,
`linha_descendo`, `raramente_perde_por_2`, `xg_baixo_combinado`.

⚠️ Isto **não** é recomendação de peso, pelo mesmo motivo das seções anteriores: a [0.1] mediu que
ganho in-sample não se replica out-of-sample (+10,0% virou −6,2%). "Sobrevive" quer dizer que a
evidência que a [B] vai ler continua de pé quando o histórico deixa de ser artificialmente curto.

### Resposta 3 — a Copa do Mundo, medida com e sem

`analyses/taskf_exclusao.sql` · `completo` × `sem_copa_mundo`

**A régua foi declarada antes de medir**, no cabeçalho da análise: a exclusão é MATERIAL num
(célula, piso) quando `rho < 0,90` **ou** `trocas_no_topo ≥ 2` **ou** `trocas_de_sinal ≥ 4`. E
junto vem o **contraste de referência** — as mesmas três métricas para `base` → `escopo` dentro do
universo COM —, porque um ρ de 0,93 não diz nada sozinho: a referência é o efeito que a [F] existe
para medir.

| contraste | piso 0 | piso 3 | piso 5 | piso 10 |
|---|---|---|---|---|
| exclusão na `base` | 0,753 · MAT | 0,555 · MAT | **0,964 · IMAT** | **1,000 · IMAT** |
| exclusão na `escopo` | 0,563 · MAT | 0,618 · MAT | **0,982 · IMAT** | **1,000 · IMAT** |
| exclusão na `recorte` | 0,806 · MAT | 0,830 · MAT | **0,992 · MAT** | **1,000 · IMAT** |
| exclusão na `ambos` | 0,858 · MAT | 0,884 · MAT | **0,986 · IMAT** | **1,000 · IMAT** |
| **referência** `base`→`escopo` | 0,813 · MAT | 0,747 · MAT | **0,648 · MAT** | 0,644 · MAT |

A leitura é uma linha: **a exclusão decide muito no piso 0 e 3, e não decide nada no piso 5 e 10 —
onde o eixo que a task mede continua decidindo tudo.** No piso 3 da `base` a exclusão chega a mexer
MAIS na ordenação (ρ = 0,555) do que o próprio eixo de escopo (0,747); no piso 5 a relação se
inverte por completo (0,964 contra 0,648).

**O mecanismo não é estatístico, é aritmético.** Dos 79 jogos removidos, **2** estão acima do piso
5 e **nenhum** acima do piso 10 — `min_jogos` médio de 1,94 e máximo de 6. No piso 10 os dois
universos são literalmente a mesma medição, e é por isso que ρ dá 1,000 exato com zero de
diferença em todos os campos: não é uma correlação alta, é a mesma tabela. Excluir a Copa do Mundo
e usar piso 5 fazem, em 77 dos 79 jogos, **o mesmo trabalho** — e o piso o faz sem precisar nomear
competição nenhuma. Em número de jogos medidos, a exclusão custa 2 em cada célula: 69 → 67 na
`base`, 92 → 90 na `escopo` e na `ambos`, 81 → 79 na `recorte`.

⚠️ **A célula `recorte` sai MATERIAL no piso 5, e ela fica assim.** A régua disparou por uma das
três pontas (`trocas_no_topo = 2`), com as outras duas limpas (ρ = 0,992, zero trocas de sinal). O
que a troca é, medido: **uma permuta adjacente na fronteira do top 5** —

| | 5º | 6º |
|---|---|---|
| `completo` | `clean_sheets_altos` (peso 4,36) | `defesas_firmes` (3,32) |
| `sem_copa_mundo` | `defesas_firmes` (3,84) | `clean_sheets_altos` (3,18) |

O veredito não é suavizado: a régua caiu **em cima** do corte, e amaciar um MATERIAL depois de
vê-lo é exatamente o pós-hoc que o cabeçalho da análise proíbe. O que sustenta a recomendação
apesar dele são as outras duas pernas, que a própria régua fornece: a referência de eixo (0,648
contra 0,992) e o mecanismo dos 2 jogos em 79. **Se alguém quiser litigar essa célula**, o passo
declarado é o universo de placebo — remover 79 jogos sorteados por hash e comparar a exclusão real
contra a distribuição do placebo. Ele continua não tendo sido rodado, e continua sendo a única
coisa que mudaria a leitura desta linha.

⚠️ **E a exclusão não é aleatória no tempo.** Tirar a Copa do Mundo não tira 47% dos jogos
espalhados pela janela: tira **os primeiros 24 dias dela**. O universo `sem_copa_mundo` começa em
**10/07**, não em 16/06 — de 16/06 a 09/07 não há na base um único jogo que não seja de seleção.
Quem for comparar as duas colunas em qualquer outro corte precisa saber que elas não cobrem o
mesmo pedaço de calendário.

**Recomendação: manter a Copa do Mundo na base de medição**, com uma condição explícita — que a
[B] leia no piso 5 ou acima. É onde a exclusão não decide nada. Se a [B] optar por ler no piso 0 ou
3, a exclusão passa a mudar a ordenação de forma material em todas as quatro células, e aí ela
deve sair; mas nesse cenário a decisão que importa é **o piso**, não a competição. O argumento de
princípio fica declarado como reserva, e ele é real: o deserto da Copa do Mundo não é acidente de
amostra, as seleções não jogam outra coisa na nossa base, e a #53 mediu que o merge lhes empresta
**exatamente zero** partida. Ele diz por que esses jogos são estruturalmente diferentes; o piso é o
instrumento que já os remove.

### Resposta 4 — a Champions, no único universo em que ela existe

`analyses/taskf_exclusao.sql` · `estendido` × `estendido_sem_champions_classif`

A #51 já tinha registrado que a Champions **não tem um jogo** no universo congelado. Ela existe no
estendido: **18 jogos, 7,9% dos 228**.

**Excluir a fase classificatória é, nesta janela, excluir a competição — e isso é medido.** O
bloco `fases` devolve **uma única linha** de Champions no universo estendido:

| competição · fase | jogos | removidos | período | veredito |
|---|---|---|---|---|
| `champions_league` · 3rd Qualifying Round | 18 | **18** | 04/08 → 11/08 | FASE_INTEIRA |

Não há fase de liga na janela (ela começa em setembro), então o predicado de fase e o de competição
selecionam o mesmo conjunto. O predicado continua escrito por **semântica de fase**, e não por
competição, porque a coincidência é da janela e não da definição — e porque `'Play-offs'` (agosto,
classificatória) e `'Knockout Round Play-offs'` (fevereiro, mata-mata) convivem no mesmo campo
`round` nas temporadas 2024 e 2025. Casar o primeiro por igualdade, e não por `LIKE '%Play-off%'`,
é o que impede a mesma consulta de mentir numa janela de fevereiro.

| contraste | piso 0 | piso 3 | piso 5 | piso 10 |
|---|---|---|---|---|
| exclusão na `base` | 0,947 · MAT | 0,934 · MAT | **1,000 · IMAT** | **1,000 · IMAT** |
| exclusão na `escopo` | 0,966 · MAT | 0,933 · MAT | **1,000 · IMAT** | **1,000 · IMAT** |
| exclusão na `recorte` | 0,968 · MAT | 0,958 · MAT | 0,970 · MAT | 0,992 · MAT |
| exclusão na `ambos` | 0,965 · MAT | 0,958 · MAT | **0,984 · IMAT** | 0,992 · MAT |
| **referência** `base`→`escopo` | 0,790 · MAT | 0,745 · MAT | **0,696 · MAT** | 0,608 · MAT |

Em `base` e em `escopo` o ρ de 1,000 no piso 5 tem a mesma origem do caso da Copa do Mundo no piso
10: **nenhum** dos 18 jogos passa o piso ali, então os dois universos são a mesma medição. Nas duas
células com recorte de contagem a exclusão mexe em alguma coisa — e mexe porque ali esses jogos
**passam** a ter histórico:

| célula | `min_jogos` médio dos 18 | máximo | acima do piso 3 | acima do piso 5 |
|---|---|---|---|---|
| `base` | 1,78 | 4 | 5 de 123 | **0 de 91** |
| `escopo` | **1,78** | **4** | 5 de 150 | **0 de 124** |
| `recorte` | 3,89 | 10 | 11 de 153 | 6 de 123 |
| `ambos` | **5,44** | **15** | 13 de 165 | **8 de 139** |

**Recomendação: manter a fase classificatória da Champions na base de medição.** Onde ela poderia
importar — o piso que a [B] vai usar, nas células que refletem produção — a exclusão é literalmente
sem efeito. E onde ela tem efeito (`recorte` e `ambos`), removê-la jogaria fora justamente os jogos
que o merge acabou de resgatar, que é o oposto do que a [F] existe para fazer. A reserva de
princípio também é real e fica declarada: a qualificatória traz clubes de ligas que **não
coletamos**, e por isso o adversário deles é invisível — se uma janela futura tiver a Champions com
peso maior que 7,9%, a pergunta se re-mede, e o par de universos já está construído para isso.

⚠️ **7,9% e não 22% — as duas contas não medem a mesma coisa.** A spec #49 atribui à fase
classificatória "22% da janela". A diferença tem mecanismo, não é erro de ninguém: a spec contou
**fixtures** do calendário, e o universo de medição exige **preço coletado**. A coleta de odds da
UCL entrou no ar em **31/07** (rollout da liga 2), então as 56 partidas de Q1 e Q2, de julho,
existem no `fact_fixtures` e não existem em `apostas` — que é também a razão de a Champions ter
zero jogo no universo congelado. É o mesmo tipo de reconciliação do "69 contra 67" da #53: nenhum
dos dois números está errado, eles contam populações diferentes.

⚠️ **18 de 20: os dois que faltam são AET.** A Q3 de 2026 tem 20 partidas encerradas com odds nos
nossos dados; duas delas — as de 11/08 — terminaram na prorrogação. O `jogos_encerrados` do
`task01_base()` filtra `status_short = 'FT'`, então AET e PEN não entram no universo. É o achado
de passagem da #56, que virou a [issue #71](https://github.com/tech-lamjav/analytics-engineering/issues/71);
aqui ele aparece com nome e sobrenome num conjunto de 20.

### ⚠️ A previsão da spec sobre `escopo` e a Champions virou medição

Este é o achado incidental mais forte do ticket.

A spec #49 afirma, na seção "o que já se sabe antes de rodar", que **`escopo` não conserta a
Champions na janela medida** — porque os rótulos de `season` se sucedem, e um jogo de
qualificatória em agosto está sob a temporada nova enquanto o histórico doméstico daquele time
ainda está sob a anterior. A #53 e a #54 registraram isso como **não verificável**: sem jogo de
Champions no universo primário, não havia o que medir.

No estendido, há. E a previsão se confirma **no número exato**: `base` e `escopo` dão o **mesmo**
`min_jogos` médio para os 18 jogos — 1,78 —, o mesmo máximo — 4 — e os mesmos zero jogos acima do
piso 5. Soltar a competição sem soltar a temporada não empresta **uma única partida** a esses
times. Quem alcança o caso é `ambos`, que triplica a média (5,44) e leva 8 dos 18 acima do piso 5.

⚠️ E a leitura que continua **não** podendo ser tirada daqui é "escopo sozinho nunca ajuda a
Europa". Isto é específico da virada de temporada: em janeiro, um time de Bundesliga tem o
campeonato nacional e a Champions sob o mesmo rótulo de `season`, e `escopo` junta os dois
normalmente. A janela desta medição cai inteira na virada.

### O universo estendido, reportado à parte

`analyses/taskf_universo_congelado.sql`, variante `E_estendido`

| variante | período | jogos | vs publicado |
|---|---|---|---|
| `C_universo_congelado` | 16/06 → 04/08 | 169 | 0 |
| `E_estendido` | 16/06 → **12/08** | **228** | **+59** |

⚠️ **O que limita o estendido não é uma data, é a construção dos fatos.** Ele alcança 12/08 00:30
UTC porque é até ali que vai o `fact_odds_snapshot` que as quatro células leram (`odds_loaded_at`
12/08 13:24:15). Rebuildar a ancestria para ele alcançar "hoje" custaria re-medir tudo e quebraria
a única coisa que faz a comparação entre células significar algo. O universo é, por construção, "o
que os fatos contêm" — e o `janela_fim` na linha diz até onde ele foi.

| competição | jogos | % do estendido |
|---|---|---|
| copa_mundo | 79 | **34,6%** |
| serie_b | 49 | 21,5% |
| brasileirao | 38 | 16,7% |
| champions_league | 18 | **7,9%** |
| sudamericana | 17 | 7,5% |
| copa_do_brasil | 16 | 7,0% |
| primeira_liga | 9 | 3,9% |
| libertadores | 2 | 0,9% |

**Ele acrescenta pouco, e o pouco é mensurável.** A spec estimava "~37 jogos"; foram **59** — a
estimativa envelheceu, e o número medido é o que vale. Mas o efeito que se poderia esperar dele
**não** acontece: a Copa do Mundo continua sendo mais de um terço da amostra (34,6%, contra 46,7%
no congelado), e das seis ligas europeias do portfólio **uma única** aparece — a Primeira Liga, com
9 jogos. Bundesliga, La Liga, Ligue 1, Premier League e Serie A ITA seguem em **zero**. A família
split-year, que a #53 e a #54 deixaram registrada como "sem amostra", continua sem amostra
suficiente para deixar de ser degenerada.

E aqui a tolerância de 0,5 pp declarada na #51 **volta a ter mordida**: no congelado, a coleta de
odds já tinha parado (zero capturas após 04/08, medido); no estendido, não. Toda leitura de
`linha_subindo`/`linha_descendo` nas linhas de universo estendido está sujeita a ela.

### ⚠️ `defesas_vazaveis` é a única premissa em dois mercados — e os dois vereditos são opostos

O cabeçalho do `taskf_sobrevivencia.sql` diz, antes de rodar, que agrupa por mercado "porque supor
unicidade de nome é como se descobre que ela não valia". Valeu a pena:

| mercado · benchmark | `base` | `escopo` | `recorte` | `ambos` | veredito |
|---|---|---|---|---|---|
| BTTS · consenso | +8,7 (31) | +1,6 (36) | +7,3 (32) | +6,3 (44) | **SOBREVIVE** |
| Gols · sharp | −5,8 (158) | −5,8 (201) | −6,2 (181) | −7,7 (214) | SEM EVIDÊNCIA |

As "39 premissas" do entregável são **39 linhas de (mercado, premissa, benchmark) sobre 38 nomes
distintos**. Quem ler a tabela final da #59 por nome de premissa vai encontrar `defesas_vazaveis`
duas vezes, com sinais opostos, e isso não é duplicata: são dois mercados, dois benchmarks
preferidos e duas medições legítimas.

### As guardas: quatro verdes, e duas quebras novas

```
dbt test --target taskF --select tag:costura_b     →  PASS=4 ERROR=0
```

Três das quatro mudaram de grão nesta task — passaram a cobrar por (universo × célula) — e ficaram
**mais fortes**, não mais fracas: são quatro vezes mais comparações. A quarta,
`assert_taskf_base_reproduz_01`, foi recortada no universo `completo` de propósito: o lado esquerdo
dela são os números publicados da [0.1], que existem para um recorte só. Não há [0.1] "sem Copa do
Mundo" contra a qual reproduzir.

Que os quatro universos tenham passado com contagens **diferentes** (169, 90, 228, 210) já é a
prova viva de que a referência é por universo — uma referência global teria ficado vermelha nas
três últimas. As duas cobranças que esse argumento não alcança foram quebradas de propósito:

| quebra | guarda que caiu | saída |
|---|---|---|
| `SET jogos_no_universo = +1 WHERE universo='sem_copa_mundo' AND celula='ambos'` | `celulas_mesmo_universo` | **4 linhas**: 1 `jogos_fora_do_gabarito` (91 contra o gabarito 90) e 3 `universo_divergente` — as outras três células daquele universo denunciando a quarta |
| `SET universo='completo_v2' WHERE universo='estendido' AND celula='recorte'` | `celulas_mesmo_universo` **e** `premissas_de_tabela_identicas` | **2 linhas** (`celulas_faltando`, nos dois sentidos: o universo que não devia existir e o par que sumiu) e **10 linhas** de grão incompleto |

As duas foram desfeitas e as quatro guardas voltaram ao verde; a tabela foi reconferida depois, e
os 16 pares (universo × célula) devolvem exatamente os mesmos números de antes das quebras.

### A re-medição reproduz a #55: 6 campos em 7.200

`analyses/taskf_remedicao.sql` contra `taskf_teste2_55` — a cópia declarada em `sources.yml` antes
de a acumulativa ser dropada para ganhar a coluna de universo.

| célula | linhas | sem contraparte | linhas divergentes | campos divergentes | campos comparados |
|---|---|---|---|---|---|
| `base` | 60 | 0 | 2 | 3 | 1.800 |
| `escopo` | 60 | 0 | 1 | 1 | 1.800 |
| `recorte` | 60 | 0 | **0** | **0** | 1.800 |
| `ambos` | 60 | 0 | 2 | 2 | 1.800 |

Cinco dos seis campos são os **mesmos** empates de arredondamento que a #53, a #54 e a #55 já
tinham medido e provado (55/80 = 68,75; 308/320 = 96,25; 51/400 = 12,75). O sexto é novo —
`clean_sheets_altos` · `jogos_medios_usado` na `ambos`, 5,2 → 5,3 — e foi provado do mesmo jeito, e
não presumido: **92 linhas, soma 483, média exata 483/92 = 5,25**, em cima do meio da grade de
`ROUND(·, 1)`.

A comparação é só do universo `completo`, e não é lacuna: os três universos novos nasceram nesta
execução e não têm lado esquerdo. Comparar 240 linhas de hoje contra 60 de ontem produziria 180
`SEM_CONTRAPARTE` que esconderiam a divergência real.

E as conferências de fora não se moveram: a reconciliação contra a [0.1] segue **38 EXATO / 1
INVESTIGAR**, com `linha_descendo` nos mesmos −2 de `n`; saturação, piso, monotonicidade e chaves
seguem `OK` nos quatro blocos, com os mesmos 21.054 pares nas quatro células.

### Reprodução

```bash
cd dbt_futebol

# FASE 0 — só porque a #58 mudou o schema da acumulativa (a coluna `universo`)
bq cp -f smartbetting-dados:futebol_taskF.taskf_teste2 \
         smartbetting-dados:futebol_taskF.taskf_teste2_55   # a cópia que sobrevive
bq rm -f -t smartbetting-dados:futebol_taskF.taskf_teste2

# as quatro células, cada uma com build -> carimbo -> Teste 2 e as MESMAS vars. Nada de `+`.
# (a ancestria NÃO foi reconstruída: ela já estava no dataset e nenhum modelo dela mudou —
#  e é ela que fixa até onde o universo estendido alcança)
# base    : --vars '{}'                                        (sem exclusão: a Costura A roda)
# escopo  : --vars '{pit_escopo: todas}'                       --exclude assert_taskf_pit_default_igual_baseline
# recorte : --vars '{pit_recorte: ultimos_10}'                 idem
# ambos   : --vars '{pit_escopo: todas, pit_recorte: ultimos_10}' idem

# FASE 3 — o portão
DBT_PROFILES_DIR=.. ../.venv/bin/dbt test --target taskF --select tag:costura_b

# resposta 1 (o piso célula a célula)
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_saturacao_recorte

# resposta 2 (a sobrevivência das quatro)
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_sobrevivencia

# resposta 3 (Copa do Mundo) — o default do taskf_exclusao
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao

# resposta 4 (Champions) — o mesmo arquivo, outro par de universos
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_exclusao \
  --vars '{taskf_universo_com: estendido, taskf_universo_sem: estendido_sem_champions_classif}'

# o universo estendido, à parte
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_universo_congelado

bq query --use_legacy_sql=false --project_id=smartbetting-dados --max_rows=500 \
  < target/compiled/dbt_futebol/analyses/<a análise>.sql
```

Os quatro `dbt build` fecham **43/43** (`base`, incluindo a Costura A) e **42/42** (as outras
três), com `ERROR=0` e `SKIP=0` — iguais aos da #54 e da #55.

⚠️ **Sem `--max_rows` o `bq query` corta em 100 linhas sem avisar**, e o `taskf_exclusao` emite
mais do que isso. É o mesmo corte silencioso que a #57 documentou.
