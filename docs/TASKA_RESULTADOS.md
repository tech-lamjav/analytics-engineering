# Task [A] — Resultados

Documento vivo. Cada subtask da [issue #15](https://github.com/tech-lamjav/analytics-engineering/issues/15)
acrescenta a sua seção aqui. O SQL que produz cada número está em `dbt_futebol/analyses/`.

Os resultados moram neste arquivo, e não no cabeçalho das análises, para que o SQL mude quando a
lógica muda e não quando os números mudam. Mesmo padrão do `TASK01_RESULTADOS.md` e do
`TASKF_RESULTADOS.md`.

**A [A] tem seis subtasks e todas comparam contra o mesmo *antes*. Ele está na
[seção do #106](#ticket-106--a-linha-de-base-remedida).** Citar de memória é como a
`taskA_linha_de_base.sql` acumulou três invalidações sem ninguém notar.

---

# Ticket #106 — A linha de base remedida

**Análise:** `dbt_futebol/analyses/taskA_linha_de_base_funil.sql`
**Fonte:** `fact_value_funnel` (ADR 0011), janela fixada em `janela_e_corrente`
**Rodada publicada:** **2026-08-25 19:30:24 UTC**

## O predicado de corte (é ele que está congelado, não os números)

O funil é append-only e congela no apito: a fatia que produziu os números abaixo fica preservada
para sempre. Não há seed — o append-only **é** o congelamento. Para reproduzir esta rodada exata:

```sql
FROM fact_value_funnel
WHERE janela_e_corrente
  AND gravado_em < TIMESTAMP '2026-08-25 19:30:24'   -- o teto desta rodada
```

Para reler o mesmo *antes* com N maior na véspera da A1, sobe-se o teto e não se muda mais nada.
A A1 herda a cláusula.

## Veredito

**Cinco linhas publicadas de 7.024 candidatas no escopo vivo — 0,1%. E duas portas fazem quase
todo o trabalho: a cobertura da Pinnacle e o edge.**

O caminho inteiro, escopo vivo, todos os mercados (`marginal` = quantas a porta ainda remove
depois das anteriores):

| # | porta | entra | remove (marginal) | sai | remove sozinha |
|---|---|---:|---:|---:|---:|
| 00 | universo (com lado apostado) | 6.941 | — | 6.941 | — |
| 01 | saída catalogada | 6.941 | 83 | 6.858 | 83 |
| 02 | **cobertura da Pinnacle** (`pin_n_outcomes`) | 6.858 | **3.808** | 3.050 | 3.819 |
| 03 | valor estimável (ADR 0002) | 3.050 | **0** | 3.050 | 111 |
| 04 | linha meia (AH/Gols) | 3.050 | 1.858 | 1.192 | 4.165 |
| 05 | liquidez ≥ 3 casas | 1.192 | 12 | 1.180 | 2.019 |
| 06 | odd mínima da DC (≥ 1,25) | 1.180 | 31 | 1.149 | 55 |
| 07 | **edge acima do piso** | 1.149 | **1.028** | 121 | 6.381 |
| 08 | nota ≥ 40 | 121 | 116 | **5** | 6.842 |

Fora da fila, com os números inteiros: **83 empates de 1X2** (seção 2) e **83 saídas "12" de Dupla
Chance** (a porta 01). Cada um é exatamente um por fixture — 83 fixtures vivos.

Três leituras que a fila entrega e a cópia à mão não entregava:

**1. A porta de nota não é a que corta o board.** Ela recebe 121 linhas e devolve 5. As 6.820
linhas que nunca chegaram até ela caíram em portas ESTRUTURAIS — cobertura, linha meia, edge. Toda
subtask que se propõe a "afrouxar a régua" (A1, A4) está mexendo numa porta que vê 1,7% do universo.

**2. A `porta_valor_estimavel` é redundante hoje — marginal ZERO em todos os mercados e nos dois
escopos.** Nenhuma linha reprova nela sem já ter reprovado na cobertura da Pinnacle: medido,
**19.449 linhas reprovam na cobertura e passam no valor, e ZERO no sentido inverso**. Isso é o
oposto do aninhamento declarado no cabeçalho do mart, e é o corpo de delito da #118 (abaixo).

**3. O BTTS publica zero no escopo vivo.** Das 166 candidatas, 164 chegam ao edge e **as 164
morrem lá**. O BTTS só tem preço de consenso (a Pinnacle não o cobre) e por isso enfrenta piso de
edge `0,03` contra `0` — 3× maior. No histórico ele publica 17 de 938.

## As três descontinuidades da série

Declaradas antes da medição, como a #86 fez com o `.25`.

| descontinuidade | instante | efeito |
|---|---|---|
| **#91** (`887a1f9`) — histórico do time solto da competição | 25/08 **16:31:32** UTC | Parte a série, e **só na `porta_nota`**: a #91 tocou apenas `int_futebol_premissas_*` e `int_futebol_team_form_pit`. As outras sete portas são idênticas antes e depois. Sai como coluna `nota_valida_no_escopo`. |
| **`.25`** (#101) — linha de quarto deixa de contar como meia | 21/08 **19:05** UTC | Real contra os números **publicados** na rodada anterior. **Inexistente dentro da série**: o backfill que criou o funil rodou 21/08 **21:21** UTC, depois dele, e `COUNTIF(gravado_em < '2026-08-21 19:05') = 0`. |
| **`origem = 'backfill'`** | 21/08 21:21 UTC | 27.993 das 40.672 linhas do escopo histórico na janela corrente — **68,8%**. A ADR 0011 as chama de "a única parte do funil que NÃO é registro de época". Não afeta o escopo vivo (**0%**). |

## Os dois escopos, e qual deles é "a linha de base"

| | escopo vivo | escopo histórico |
|---|---:|---:|
| fixtures | 83 | 469 |
| linhas (janela corrente) | 7.024 | 40.672 |
| linhas publicadas | 5 | 98 |
| `origem = backfill` | 0% | 68,8% |
| gravadas pós-#91 | **100%** | 18,0% |

**Nenhuma linha de kickoff futuro carrega carimbo pré-#91 — 0 de 7.787.** Como o merge reescreve
toda linha de jogo por acontecer a cada ciclo de odds, o board ao vivo **já é pós-#91 por
construção**. É essa propriedade — linha ainda gravável é linha reescrita a cada ciclo, logo linha
com o código de hoje — que define o escopo vivo, e é ela que satisfaz o critério do ticket sem
custo nenhum.

⚠️ **Mas "escopo vivo" e "população já expurgada" NÃO são o mesmo conjunto.** O expurgo da ADR 0009
corta por **status**, com o relógio apenas como rede de 24 h, e `PST`/`SUSP`/`INT` sobrevivem ao
kickoff no passado de propósito — "um corte por relógio a mataria", diz o `futebol_expurgo.sql`.
Medido nesta rodada:

| | linhas | |
|---|---:|---|
| não expurgadas do board (ADR 0009) | **7.489** | o que o board de fato mostra |
| escopo vivo (`futebol_funil_e_gravavel`) | **7.024** | a linha de base |
| no board e **fora** da linha de base | **465** (5 fixtures: 4 `NS`, 1 `PST`) | ~6% |
| na linha de base e **expurgadas** | **0** | — |

⚠️ **Estas quatro linhas são a única conferência deste documento que a análise NÃO reproduz**,
e é de propósito: o funil não carrega `status` (ADR 0011, D10 — status muda depois do apito e
uma coluna congelada com o status de antes mentiria), então medir o expurgo exige juntar
`fact_fixtures` e inlinar o `futebol_expurga_do_board`. É conferência de uma vez, feita em
25/08, e não parte da entrega recorrente. Todo o resto sai da `taskA_linha_de_base_funil.sql`.

O escopo vivo é **subconjunto estrito**: nada de expurgado entra — o critério do ticket está
cumprido — mas ele é mais estrito que o board por 465 linhas, que são jogo passado do apito ainda
dentro da carência e jogo adiado. Quem comparar a linha de base contra uma contagem do board vai
encontrar essa diferença, e a causa é esta, não defeito.

**Recomendação: o vivo é a linha de base; o histórico é o contexto.** O *antes* existe para ser
comparado com o *depois* da A1, e a A1 muda exatamente a `porta_nota` — a única coluna que o
histórico não pode sustentar. Para as outras sete portas o histórico é ganho puro de N (5,8× as
linhas, 5,7× os fixtures) e deve ser citado. **Qual número a [A] cita é escolha do PM; os dois
saem da mesma análise, na mesma coluna `escopo`.**

⚠️ O histórico **contém** o vivo — são duas leituras da mesma tabela, não uma partição. Somar as
duas linhas conta as linhas vivas duas vezes.

## A janela: 1,11×, não 4×

O ticket avisa que contar as quatro janelas (`daily` < `t24h` < `t1h` < `t15m`) infla todo número
até 4×. Medido: no funil inteiro a redução é **120.510 → 40.672 (2,96×)**; **no escopo vivo é
7.787 → 7.024, ou 1,11×**. Jogo futuro quase só tem `daily` — as outras três janelas só existem
para jogo que já começou. O 4× é o teto teórico, não o número.

## A fila por mercado (escopo vivo, `marginal / saída`)

| porta | 1X2 | Handicap | Gols | BTTS | Dupla Chance |
|---|---:|---:|---:|---:|---:|
| 00. universo | 0 / 166 | 0 / 3.058 | 0 / 3.302 | 0 / 166 | 0 / 249 |
| 01. saída catalogada | 0 / 166 | 0 / 3.058 | 0 / 3.302 | 0 / 166 | **83 / 166** |
| 02. cobertura da Pinnacle | 22 / 144 | **1.712 / 1.346** | **2.052 / 1.250** | 0 / 166 | 22 / 144 |
| 03. valor estimável | 0 / 144 | 0 / 1.346 | 0 / 1.250 | 0 / 166 | 0 / 144 |
| 04. linha meia | 0 / 144 | **1.004 / 342** | **854 / 396** | 0 / 166 | 0 / 144 |
| 05. liquidez ≥ 3 | 0 / 144 | 10 / 332 | 0 / 396 | 2 / 164 | 0 / 144 |
| 06. odd mínima da DC | 0 / 144 | 0 / 332 | 0 / 396 | 0 / 164 | 31 / 113 |
| 07. edge | 104 / 40 | 304 / 28 | 351 / 45 | **164 / 0** | 105 / 8 |
| 08. nota ≥ 40 | 40 / **0** | 27 / **1** | 41 / **4** | 0 / **0** | 8 / **0** |

Handicap e Gols perdem **56% e 62%** na cobertura da Pinnacle e outros **75% e 68%** na linha meia
— antes de qualquer régua. Os 5 publicados do dia são 4 de Gols e 1 de Handicap.

## O empate do 1X2, separado — e ele não sobrevive até a porta de nota

O empate é um terço do universo do 1X2 **por construção**: não tem lado apostado, nenhuma premissa
se aplica (ADR 0005/0006). Ele **sai da fila** e o corte é a primeira linha do funil do 1X2 —
pôr uma população estruturalmente sem candidatura dentro de uma fila que mede severidade de porta
infla o denominador de toda porta a montante e some no numerador da que interessa.

| | vivo | histórico |
|---|---:|---:|
| empates (universo) | **83** | **469** |
| reprovam **antes** do edge | 11 (13,3%) | 11 (2,3%) |
| reprovam **no edge** | **62 (74,7%)** | **314 (67,0%)** |
| chegam à nota e reprovam nela | 10 (12,0%) | 144 (30,7%) |
| passariam em tudo | 0 | 0 |

⚠️ **O critério de aceite, na letra, seria cumprido e falho por um fator de 3.** "O empate aparece
separado, pelo motivo próprio `sem_lado_apostado`" só descreveria **144** dos 469 — porque o
`motivo_primario` marca a PRIMEIRA porta reprovada e o edge vem antes da nota. Os outros 325 já
tinham caído. Publicar os 469 inteiros com a quebra de onde eles caem é mais forte do que o
critério pede, e é a única leitura em que os dois números querem dizer o que parecem.

Nota máxima de um empate na rodada: **31** — abaixo dos 40 mesmo quando o edge deixa passar. Os
pontos vêm de valor e corroboração; o teto de premissa é zero, e será zero explicitamente quando a
A6 introduzir o denominador.

## A nota por faixa: decis, e o topo da escala está vazio

Denominador = quem **chega** à porta de nota (121 no vivo, 1.175 no histórico).

| decil | faixa de hoje | vivo | histórico |
|---|---|---:|---:|
| D0 (0–9) | fora da régua | 56 (46,3%) | 588 (50,0%) |
| D1 (10–19) | fora da régua | 22 (18,2%) | 182 (15,5%) |
| D2 (20–29) | fora da régua | 20 (16,5%) | 179 (15,2%) |
| D3 (30–39) | fora da régua | 18 (14,9%) | 128 (10,9%) |
| D4 (40–49) | BAIXA | 3 (2,5%) | 62 (5,3%) |
| D5 (50–59) | BAIXA | 2 (1,7%) | 27 (2,3%) |
| D6 (60–69) | MÉDIA | **0** | 8 (0,7%) |
| D7 (70–79) | MÉDIA | **0** | 1 (0,1%) |
| D8–D9 (80+) | ALTA | **0** | **0** |

⚠️ Nenhuma linha ALTA CONFIANÇA em nenhum dos dois escopos, e **metade de quem chega à nota tira
menos de 10**. Com as três faixas de hoje a leitura seria "quase tudo é Baixa" e não diria onde; o
decil diz. E ele sobrevive à A4 (#107), que tem mandato para mover as fronteiras — as faixas de
hoje saem ao lado para a comparação com o board continuar possível.

## As barreiras propostas pela A5 — e a direção depende de qual nota se lê

⚠️ **Nenhuma das três está em produção.** Elas ficam **fora da fila e fora do cumulativo**: uma
porta que não existe não pode remover linha do *antes*, ou o antes/depois da A5 mede zero contra
zero. O ticket pede este bloco e ele está aqui, separado.

Taxa de aprovação da faixa de odd (1,50–4,00; 1,25–2,00 na DC), escopo vivo:

Taxa de aprovação da faixa de odd (1,50–4,00; 1,25–2,00 na DC). Os três eixos saem da coluna
`corte` da seção 4 — nenhum destes números vem de query fora da análise:

| faixa | 1. `pts_premissas` | 2. **nota publicada** | 3. `pts_premissas`, **só Pinnacle** |
|---|---:|---:|---:|
| **escopo vivo** | | | |
| zero | 45,5% (530/1.166) | 20,0% (649/3.249) | 72,1% (404/560) |
| 1–29 | 40,9% (1.777/4.344) | 52,4% (1.672/3.191) | 70,9% (1.379/1.946) |
| ≥ 30 | **19,9%** (268/1.348) | **60,8%** (254/418) | **46,4%** (222/478) |
| **escopo histórico** | | | |
| zero | 37,7% (3.749/9.939) | 17,8% (3.694/20.759) | 63,4% (3.224/5.086) |
| 1–29 | 38,7% (9.273/23.940) | 53,4% (8.726/16.340) | 65,4% (7.793/11.913) |
| ≥ 30 | **19,1%** (1.121/5.855) | **65,4%** (1.723/2.635) | **44,9%** (1.059/2.359) |

**O ticket tem razão no eixo em que ele mediu, e a direção se inverte no outro.** Por pontos de
premissa a faixa corta mais forte justo onde há mais premissa acesa (19,9% contra 45,5% no vivo);
**pela nota publicada ela corta mais forte onde a nota é ZERO** (20,0% contra 60,8%).

O número literal do ticket — "62% das linhas com zero premissa e só 47% das com ≥30 pontos, entre
linhas com preço da Pinnacle" — é o **eixo 3, escopo histórico**: **63,4% contra 44,9%**. Reproduz
dentro de um ponto percentual, e a diferença é o funil ter crescido desde a medição original. As
três leituras são a mesma tabela vista por eixos diferentes, e **a A5 precisa declarar qual delas
está usando antes de defender a barreira** — a mesma barreira parece corte de ruído num eixo e
corte de sinal no outro.

As outras duas, escopo vivo, por `pts_premissas` (zero / 1–29 / ≥30): `n_casas >= 4` aprova
61,6% / 57,6% / 50,5% e `NOT pen_odd_outlier` aprova 86,1% / 91,2% / 98,6%.

## Reconciliação contra a cópia à mão — uma vez, e ela se aposenta

As duas rodaram **entre dois ciclos de odds** (última escrita do funil 19:01:46 UTC; as duas
consultas às 19:16 e 19:18), sobre o mesmo escopo vivo e a mesma janela corrente. Sem isso o
de-vig se moveria debaixo delas: a cópia à mão lê `int_futebol_odds_devig` ao vivo e o funil lê a
tabela congelada.

O funil foi lido duas vezes — 19:16:58 e a rodada publicada, 19:30:24 — e **as duas saem
idênticas linha a linha na fila, no empate e na procedência**; a conferência abaixo vale para as
duas. (Entre elas só se moveram as barreiras da A5, porque preço novo da Pinnacle troca o
`valor_fonte` de linhas que já existiam sem inserir linha nenhuma.)

**O universo bate exato (6.941 = 6.941) e a saída bate exata (5 = 5).** As duas divergências
intermediárias são as **estruturais declaradas de antemão**, e nenhuma outra apareceu:

| mercado | cópia à mão | funil | causa |
|---|---:|---:|---|
| `match_winner` | 249 | 166 | a cópia à mão inclui o **empate** (83); o funil o tira da fila |
| `double_chance` | 166 | 249 | o `INNER JOIN` com as premissas some com a **"12"** (83); o funil a carimba `porta_saida_catalogada = FALSE` |

Os dois blocos têm 83 linhas — um por fixture — e por isso os totais coincidem por acidente
aritmético, com conjuntos diferentes. Porta a porta, nos três mercados que as duas leem igual:

| porta | Handicap | Gols | BTTS |
|---|---|---|---|
| completude / cobertura | 18 + 1.694 = **1.712** ✅ | 60 + 1.992 = **2.052** ✅ | 0 = 0 ✅ |
| linha meia | 1.004 = **1.004** ✅ | 854 = **854** ✅ | — |
| liquidez | 10 = **10** ✅ | 0 = 0 ✅ | 2 = **2** ✅ |
| edge | 304 = **304** ✅ | 351 = **351** ✅ | 164 = **164** ✅ |
| nota | 27 = **27** ✅ | 41 = **41** ✅ | 0 = 0 ✅ |

A soma `de-vig válido + completude` da cópia à mão dá exatamente a `cobertura da Pinnacle` do funil
porque as linhas sem prob justa também não têm cobertura — é a mesma leitura em outra ordem, e é a
medição que prova o item 2 do veredito.

Na Dupla Chance, a `porta_odd_dc` do funil (31) mais o edge (105) dão os **136** que a cópia à mão
atribui inteiros ao edge: ela não tem a porta de odd da DC, e as 31 linhas que caem nela também
cairiam no edge. No 1X2, os 166 do edge da cópia à mão são os 104 do funil mais os 62 empates, e os
50 que ela leva à nota são os 40 do funil mais os 10 empates. Fecha nos dois.

**Contra os números publicados na rodada anterior, não há tabela — cinco causas mudaram entre as
duas** (a porta de odd que aquela medição incluía e não existe em produção; o `.25` da #101; o
histórico da #91; a #71; e o próprio dia do board). A direção é a única coisa comparável, e é a
esperada: as mudanças do `.25` só **apertam**, monotonicamente. Aqui vale a precisão — a cópia à
mão **já foi corrigida** pelo `.25` (commit `c33608c`), e é por isso que os marginais de linha meia
batem byte a byte hoje. A descontinuidade do `.25` é contra os **números publicados**, não contra o
arquivo como ele está.

A partir daqui `analyses/taskA_linha_de_base.sql` está **aposentada** — marcada no cabeçalho, não
apagada: ela é a outra metade desta reconciliação e carrega o esboço do regime `novo` que a A3+A5
vai querer. Ela some com a A5.

## Achado fora do escopo: a `porta_conjunto_completo` não é a regra da ADR 0002

O cabeçalho do `fact_value_funnel` diz que `porta_conjunto_completo` e `porta_valor_estimavel` são
**aninhadas** ("conjunto incompleto implica prob justa ausente") e avisa contra somá-las. Medido, o
aninhamento existe **no sentido contrário**: reprovar em valor implica reprovar em cobertura, e
nunca o inverso — **19.449 linhas de um lado, 0 do outro**. `valor_estimavel` tem marginal **zero**
em todos os mercados e nos dois escopos. A tabela abaixo é a janela corrente inteira (= escopo
histórico); as três primeiras linhas somam os 19.449.

| mercado | `valor_fonte` | cobertura | valor | linhas |
|---|---|---|---|---:|
| asian_handicap | consenso | **false** | **true** | **8.948** |
| goals_over_under | consenso | **false** | **true** | **10.468** |
| match_winner | consenso | **false** | **true** | 33 |
| asian_handicap | pinnacle | true | true | 8.902 |
| goals_over_under | pinnacle | true | true | 7.982 |
| btts | consenso | true | true | 938 |

A causa: a regra da ADR 0002 (`n_outcomes_valor = conjunto_esperado`) mora no de-vig e no funil é a
`porta_valor_estimavel`. A `porta_conjunto_completo` é outra coisa — é o `WHERE d.pin_n_outcomes >= N`
dos ramos do board, a versão **anterior à #22**, que nunca saiu. Ela pergunta *"a Pinnacle
cobriu?"*, não *"o conjunto está completo?"*. E é **assimétrica entre mercados**: o ramo do BTTS
gateia em `n_outcomes_valor` e admite consenso; Handicap e Gols gateiam na Pinnacle e não admitem.

**Dentro da #106 isto é só rótulo** — a fila publica as duas com nomes diferentes e nada em
produção muda. **Fora dela mexe numa decisão já tomada**: o item 3 da spec-mãe (#15) decidiu que a
completude "continua exatamente como está", e essa confirmação foi dada sobre o **nome**. O
predicado que existe barra **19.449 linhas** de Handicap, Gols e 1X2 precificadas só por consenso —
e linha de consenso ainda enfrenta piso de edge 3× maior, o que **acopla a porta de cobertura à
régua de edge por um caminho que ninguém desenhou**. Se é conserto, emenda de ADR ou comportamento
correto mal documentado é grelha própria: **#118**.

## Como rerodar

```bash
cd dbt_futebol
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_linha_de_base_funil
bq query --use_legacy_sql=false --format=csv \
  < target/compiled/dbt_futebol/analyses/taskA_linha_de_base_funil.sql
```

Nada em produção muda: é `compile` + `bq query`, nunca `dbt run`.

---

# Ticket #86 — A remedição de churn D+7

**Análise:** `dbt_futebol/analyses/taskA_churn_pos_apito.sql`
**Fonte:** `fact_value_opportunities_hist` × `fact_fixtures` (ADR 0009)
**Deploy do expurgo (#85) em produção:** **2026-08-20 16:41:25 UTC**
**Medição:** **2026-08-28 12:40:53 UTC** — **7,83 dias corridos** depois (a trava de relógio
expirava em 27/08 16:41 UTC)

## Veredito

**O alvo literal do aceite — *zero versão nova pós-apito* — não foi atingido: sobraram 45, sobre
9 chaves. O alvo que decide foi: das 45, ZERO nasceu depois da carência de 24 h.**

A distinção não é conveniência retroativa. Ela foi pré-declarada na #85 **antes** do deploy,
justamente para esta medição atribuir em vez de investigar: a versão que nasce nas primeiras 24 h
depois do apito não está ao alcance do expurgo (o status ainda não chegou, ou a carência ainda não
venceu). A que nasce **depois** das 24 h está, e é a única que seria defeito.

| | Baseline (17/08) | Janela pós-deploy |
|---|---|---|
| Versões pós-apito **> 24 h** — *o número do aceite* | **14.674** | **0** |
| Versões pós-apito, total | 14.946 | **45** |
| …sobre quantas chaves | 172 | **9** (8 fixtures) |
| % das versões da janela que são pós-apito | 96,7% | **9,0%** |
| Versões pós-apito por dia | 709 | **5,8** |
| Versões pós-apito por lote de snapshot | 53,4 | **0,28** |
| Maior atraso observado | 1.409 h (59 dias) | **16,3 h** |

## A janela, e o que ela contém

| | |
|---|---|
| Piso | `dbt_valid_from > 2026-08-20 16:41:25 UTC` (o deploy) |
| Teto | `dbt_valid_from <= 2026-08-28 12:40:53 UTC` (esta medição) |
| Versões nascidas na janela | **498** |
| Chaves | **48** |
| Lotes de snapshot | **162** |
| Versões sem `kickoff` (fixture ausente) | **0** |

⚠️ **162 lotes em 7,8 dias não é o relógio, é o calendário de jogos.** A fase de `dbt run` do
`workflow_futebol_odds.yml` tem gate `saved_count > 0`: o cron dispara a *coleta*, e o board só é
reconstruído quando a coleta traz arquivo novo de odds. Dia sem jogo tem menos reconstruções — e
menos oportunidades de nascer versão nova. "Uma semana" aqui vale 162 chances, não 672.

## As três faixas — a atribuição, com número

| Faixa após o apito | Baseline (17/08) | 20/08 (deploy) | **Janela pós-deploy** | Dono |
|---|---|---|---|---|
| 0–10 h — o status ainda não chegou | 83 | 121 | **43** | task **[C]** (coleta de placar) |
| 10–24 h — resíduo da carência | 189 | 208 | **2** | decisão de produto (`expurgo_carencia_horas`) |
| **> 24 h — defeito** | **14.674** | **17.390** | **0** | — |

- As **43** de 0–10 h são a latência de `fact_fixtures`, que é reconstruída uma vez por dia
  (`workflow-futebol-daily`, `0 9 * * *`) enquanto o board é reconstruído a cada ciclo de odds.
  Entre o apito e as 09:00 UTC seguintes o status ainda não é `FT` e a linha continua no board.
  **Nenhuma carência resolve** — a linha não passou de 24 h, então a rede de segurança não a
  alcança por construção. É a dependência **[A]→[C]** que a ADR 0009 pré-declarou.
- As **2** de 10–24 h são o preço corrente de `expurgo_carencia_horas = 24`. Baixar a var derruba
  esse número; é decisão de produto, não defeito.
- **Zero acima de 24 h.** O expurgo faz exatamente o que a ADR 0009 desenhou.

### Quem são as 45

Oito fixtures, todos `FT`, todos com o atraso dentro das primeiras 16,3 h:

| Fixture | Competição | Kickoff (UTC) | Versões pós-apito | Chaves | Maior atraso |
|---|---|---|---|---|---|
| 1570348 | la_liga | 2026-08-23 17:30 | 26 | 2 | 6,5 h |
| 1520835 | serie_b | 2026-08-25 22:30 | 5 | 1 | 2,0 h |
| 1570345 | la_liga | 2026-08-21 19:00 | 4 | 1 | **16,3 h** |
| 1570342 | la_liga | 2026-08-25 19:00 | 3 | 1 | 5,5 h |
| 1623070 | copa_do_brasil | 2026-08-27 23:00 | 3 | 1 | 12,6 h |
| 1520836 | serie_b | 2026-08-23 21:00 | 2 | 1 | 1,3 h |
| 1547769 | libertadores | 2026-08-26 00:30 | 1 | 1 | 0,0 h |
| 1570340 | la_liga | 2026-08-26 19:00 | 1 | 1 | 4,0 h |

Um fixture responde por 26 das 45. O padrão é o esperado: jogo de fim de tarde/noite, cujo status
só vira `FT` na varredura das 09:00 UTC do dia seguinte, continua recebendo preço enquanto a
coleta de odds ainda o enxerga.

## A descontinuidade do `.25` (#101), 2026-08-21 19:05:23 UTC

O aceite exige as contagens absolutas dos dois lados do corte. Elas estão abaixo — **com os lotes
e os dias de cada lado**, sem os quais a comparação seria entre 26 horas e uma semana:

| | **A · antes do `.25`** | **B · depois do `.25`** |
|---|---|---|
| Intervalo | 20/08 16:41 → 21/08 19:05 | 21/08 19:05 → 28/08 12:40 |
| Dias observados | 1,04 | 6,70 |
| Lotes de snapshot | 24 | 138 |
| Versões | **44** | **454** |
| Chaves | **8** | **43** |
| Versões pós-apito | **0** | **45** |
| Chaves pós-apito | 0 | 9 |
| 0–10 h / 10–24 h / **> 24 h** | 0 / 0 / **0** | 43 / 2 / **0** |
| Apitos dentro do intervalo | **2** | **14** |

⚠️ **O zero do lado A não é evidência sobre o `.25`, e não deve ser lido como tal.** O lado A tem
26 horas, 24 lotes e **2 apitos**; o lado B tem quase sete dias, 138 lotes e 14. Com 2 jogos
encerrando dentro do intervalo, "nenhuma versão pós-apito" é o que se esperaria de qualquer
regime. O que os dois lados dizem juntos, e isso sim é o aceite: **`> 24 h` é zero dos dois
lados**.

O conserto do `.25` é monotônico — nenhum candidato anda de quarto para meia, então nada passou a
ser publicado que não era. Ele muda **volume para baixo** (o board perde 37,7% das oportunidades
de Handicap e Gols), não taxa de nascimento de versão pós-apito. É por isso que as contagens
absolutas caem a partir de 21/08 19:05 e o veredito não se move.

## O critério, e como ele foi provado ser o mesmo do congelamento

```sql
-- versão pós-apito ⇔
h.dbt_valid_from > f.kickoff_utc
FROM fact_value_opportunities_hist h
LEFT JOIN fact_fixtures f USING (fixture_id)   -- LEFT, nunca INNER (fail-open, ADR 0003)
```

**O congelamento de 17/08 publicou os números sem guardar a query.** O critério acima foi
reconstruído e depois **calibrado contra os dois checkpoints congelados**, que ele reproduz ao
número — rodando o próprio arquivo de análise, só movendo o teto:

| Teto | Reproduz | Publicado em |
|---|---|---|
| 2026-08-17 16:32:17.191019 UTC | 15.452 versões / 210 chaves / 14.946 pós-apito / média **668,2 h** | ADR 0009 e #80 |
| 2026-08-20 16:41:25 UTC | 17.719 pós-apito, faixas **121 / 208 / 17.390** | #85, no dia do deploy |

O teto de 17/08 não foi escolhido a dedo: é a última versão do lote das 16:32 daquele dia, o único
instante em que o `hist` tem exatamente 15.452 linhas. Reproduzir **dois** pontos, faixas
inclusive, é o que torna esta remedição comparável ao baseline em vez de uma métrica nova — e é o
aceite "mesma query do congelamento", satisfeito por reprodução em vez de por afirmação.

O SQL agora mora em `dbt_futebol/analyses/taskA_churn_pos_apito.sql`, para que a próxima remedição
não pague a reconstrução de novo.

## Três ressalvas do instrumento, declaradas

1. **`dbt_valid_to` não é imutável.** Ele é reescrito quando a versão seguinte nasce. A linha do
   baseline *"89 chaves mortas, 54 depois do apito, em média 464 h"* **não é replayável**: relendo
   o `hist` hoje com o teto de 17/08, as 210 chaves aparecem fechadas, porque elas fecharam
   depois. Quem quiser essa métrica tem de medi-la no dia. Só `dbt_valid_from` sustenta replay —
   e é só com ele que a janela desta medição foi escrita.
2. **`kickoff_utc` é lido no instante da medição, não no da versão.** Jogo remarcado move o próprio
   apito e uma versão pode trocar de lado da fronteira retroativamente. O `hist` não carrega
   kickoff, e carimbá-lo seria coluna nova em tabela sincronizada — o que a ADR 0009 recusou de
   propósito.
3. **A janela vale 162 lotes, não 672.** Ver o gate `saved_count > 0` acima.

## Resíduo: o que vai para onde

O aceite manda registrar o resíduo na **#78**. **Nada vai para lá, e o motivo é o resultado:** a
#78 é a task de churn, e o único resíduo que seria churn — versão nascida **depois** da carência
de 24 h — deu **zero**. Registrar lá as 45 seria mandar para a task errada um número que já tem
dono declarado.

- as **43** de 0–10 h são a **task [C]** (frequência da coleta de placar). Não há hoje ticket
  aberto da [C] para recebê-las; o número fica aqui e na #86, e entra na [C] quando ela for
  escrita — é insumo dela, não pendência da [A];
- as **2** de 10–24 h são o preço de `expurgo_carencia_horas = 24`, fixada pela ADR 0009. Mexer
  nela é decisão de produto;
- as **0** acima de 24 h são o que a #78 receberia. Não há o que registrar.

*(A #78 foi, aliás, **fechada em 26/08** pela A1/#103 — as duas premissas de odd que instabilizavam
a nota saíram do Score. Mesmo que houvesse resíduo de churn, ele precisaria de casa nova.)*

## Estado do produto no instante da medição

| | |
|---|---|
| Linhas no board | **8** |
| Chaves abertas no `hist` | **8** |
| `hist` — total de versões | **18.819** (era 15.452 em 17/08: cresceu, não encolheu) |
| Guarda 1 (`assert_board_sem_jogo_encerrado`) | **PASS** |
| Guarda 2 (`assert_hist_aberto_existe_no_board`) | **PASS** |

O `hist` maior é a outra metade da ADR 0009 funcionando: **expurgar não é apagar**. As 45 versões
pós-apito desta janela estão todas lá, fechadas e datadas — é por isso que esta medição existe.

## Como rerodar

```bash
cd dbt_futebol
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --select taskA_churn_pos_apito
bq query --use_legacy_sql=false --format=csv \
  < target/compiled/dbt_futebol/analyses/taskA_churn_pos_apito.sql
```

Para remedir mais tarde, mover `corte_fim` no cabeçalho da análise. Para replayar um congelamento,
mover os dois cortes. Nada em produção muda: é `compile` + `bq query`, nunca `dbt run`.
