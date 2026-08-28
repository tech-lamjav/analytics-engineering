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

⚠️ **E o zero não é de raspão.** A versão mais atrasada da janela está em **16,28 h** — **7,72 h
de folga** até a fronteira da carência —, e **nenhuma** das 45 passa de 20 h. Importa porque um
resultado colado na fronteira mudaria de lado com uma remarcação de jogo ou um arredondamento;
este não muda.

⚠️ **`PST`/`SUSP`/`INT` não entram na faixa de defeito**, pelo mesmo motivo que não entram no
expurgo: a ADR 0009 os preserva **inclusive além da carência**. Jogo adiado fica adiado por
semanas e nasceria versão nova o tempo todo — contá-lo como defeito faria esta medição acusar o
expurgo justamente onde ele está obedecendo. Eles saem **contados à parte**, nunca apagados
(coluna `acima_24h_sobrevivente`), e a lista vem de `futebol_status_sobrevivem()`, o mesmo macro
do mart e da guarda 1. **Deu zero nos três cortes** — janela, 17/08 e 20/08 —, então a ressalva é
de instrumento e não muda nenhum número desta seção: os 14.674 do baseline são todos defeito de
verdade.

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

- as **43** de 0–10 h são a **task [C]** (frequência da coleta de placar), e a #85 já as atribuiu
  a ela **antes** do deploy: *"Quem move isso é a task [C], não este ticket nem a #78."* Elas
  **não ficam penduradas aqui**: viraram **`data-engineering#60`**, com o número, a distribuição
  por atraso e o custo da cadência medido (`/fixtures` não é paginado — 1 chamada por alvo, e
  `FIXTURES_CURRENT` tem 14). Foi aberto lá porque a alavanca inteira é de ingestão: cron do
  Scheduler, `FIXTURES_CURRENT` e workflows. Nada no `dbt_futebol` move este número;
- as **2** de 10–24 h são o preço de `expurgo_carencia_horas = 24`, fixada pela ADR 0009. Mexer
  nela é decisão de produto;
- as **0** acima de 24 h são o que a #78 receberia. Não há o que registrar.

*(A #78 foi, aliás, **fechada em 2026-08-17 20:59 UTC**, quando a causa raiz saiu do adjetivo: o
`AVG()` do BigQuery não é bit-reproduzível entre execuções — a fusão das médias parciais de cada
shard leva o último bit junto —, e são 6 premissas, não 1. Mesmo que houvesse resíduo de churn
acima de 24 h, ele precisaria de casa nova.)*

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

---

# Issues #120 / #121 — Quando o Valencia × Betis foi publicado

**Análise:** `dbt_futebol/analyses/board_reconstrucao_de_publicacao.sql`
**Fontes:** `fact_value_funnel` (veredito por janela) e `fact_value_opportunities_hist` (o painel)
**Rodada publicada:** **2026-08-28 14:41 UTC**
**Caso:** fixture `1570342`, Valencia × Real Betis, `goals_over_under` / `Over` / linha `3.5`,
apito em **25/08/2026 16:00 BRT**

## A resposta

**Publicada às 15:03:09 BRT de 25/08 — 56 minutos ANTES do apito.** Comportamento **válido**, e
disponibilidade **contínua**: não houve sumiço nem reativação.

| versão no painel | de (BRT) | até (BRT) | antes do apito | transição |
|---|---|---|---|---|
| `t1h` (detecção `t1h`) | **15:03:09** | 15:48:00 | **+56 min** | **primeira publicação** |
| `t15m` (detecção `t1h`) | 15:48:00 | 20:48:39 | +11 min | atualização (contígua) |
| `t15m` | 20:48:39 | 21:04:35 | −288 min | atualização (contígua) |
| `t15m` | 21:04:35 | 21:32:54 | −304 min | atualização (contígua) |
| `t15m` | 21:32:54 | 26/08 09:14:45 | −332 min | atualização (contígua) |

Odd, edge e nota **não se moveram** em nenhuma das cinco versões: 4,00 / +6,94% / 44 / faixa
`Média`, com 11 casas e `valor_fonte = pinnacle`.

## Por que parecia t15m — e por que isso é uma armadilha de leitura, não um defeito

O PIT devolve a versão **viva no apito**, que é a de 15:48:00, cujo `janela_usada` é `t15m`. Mas
`janela_usada` é a **janela de odds da versão**, não o horário de nascimento: às 15:48 houve uma
*atualização contígua* (o `dbt_valid_to` de uma versão é o `dbt_valid_from` da seguinte, sem
buraco), não uma republicação.

Quem responde a pergunta certa já existe: **`janela_deteccao` = `t1h`** nas cinco versões — a
coluna que a **#40** criou. A leitura de "apareceu em t15m" vinha de olhar `janela_usada`.

## O Motor de fato não passou antes — e o que mudou foi o preço

Não é caso de publicação atrasada. Nas janelas anteriores a candidata **reprovava de verdade**:

| janela | odd | edge | nota | passou? | porta que barrou |
|---|---|---|---|---|---|
| `daily` | 3,60 | +1,34% | 21 | não | `nota_abaixo_da_regua` |
| `t24h` | 3,52 | **−4,00%** | 14 | não | `sem_edge` |
| **`t1h`** | **4,00** | **+6,94%** | **44** | **sim** | — |
| `t15m` | 4,00 | +6,94% | 44 | sim | — |

A Pinnacle abriu a odd de 3,52 para 4,00 entre `t24h` e `t1h`. O edge virou de −4,0% para +6,9% e
a nota saltou de 14 para 44. **O sinal nasceu tarde porque o preço nasceu tarde**, e o pipeline o
publicou 56 minutos depois — não é atraso de serving.

## ⚠️ A lacuna de telemetria, medida: o funil não data janela

A spec #120 propõe reconstruir as transições "usando o funil append-only". **O funil não sustenta
essa reconstrução**, e isto foi medido, não suposto:

> Dos **7.660** candidatos com mais de uma janela na semana de 20–26/08, **7.660** — todos, sem
> uma exceção — têm um `gravado_em` **único**, compartilhado por todas as suas janelas.

No caso do Valencia × Betis, as **oito** linhas do funil (4 janelas × 2 lados) carimbam
`2026-08-25 15:46:34`, treze minutos antes do apito. O `gravado_em` data a **execução que
escreveu**, não a janela que a linha descreve.

O funil, portanto, responde **o que o Motor disse em cada janela** — e é insubstituível nisso,
como a tabela acima mostra. **Não** responde *quando* ele disse, nem quando o assinante viu. Quem
data a tela é o `dbt_valid_from` do `hist`, e só ele.

Que a ausência antes das 15:03 é ausência de verdade, e não falta de execução, o próprio `hist`
prova: o snapshot rodou às 13:32:54 e abriu uma versão de outra chave, **sem** nenhuma deste
fixture.

## "Disponível desde": o campo que falta, e o que ele não pode ser

O contrato de dados pedido pela #120 é: **`disponivel_desde` = o início do período contínuo
ATUAL**, com reativação reiniciando o relógio. Ele se calcula do `hist` — o `dbt_valid_from` da
versão que abre a corrida contígua corrente, exatamente como o bloco B da análise faz.

Três avisos que precisam ir junto do campo, senão ele mente:

1. **Não é `MIN(dbt_valid_from)` da chave.** Isso data o *primeiro* nascimento e ignora
   reativação, que é justamente a distinção que a spec pede.
2. **Não é `janela_usada`.** É o erro que originou esta investigação.
3. ⚠️ **O `hist` estreou em 27/07/2026.** Para chave anterior, `MIN(dbt_valid_from)` data a
   estreia do snapshot, não a oportunidade — é o pico falso já registrado no `CONTEXT.md`. A
   análise emite `anterior_a_estreia_do_hist` para que isso não passe em silêncio, e o campo no
   app precisa do mesmo cuidado: **melhor vazio do que um horário inventado**.

## Um achado colateral: três versões nasceram DEPOIS do apito

As versões de 20:48:39, 21:04:35 e 21:32:54 nasceram **4h48, 5h04 e 5h32 após o apito** — o jogo já
tinha acabado. É o resíduo que a **#86** mediu e nomeou: a faixa **0–10 h**, que não é do mart e sim
da latência de coleta de placar, e que virou **`data-engineering#60`**. Este fixture é um caso dela,
com número. O expurgo fechou a chave às 09:14:45 de 26/08, quando o `FT` finalmente entrou.

Nada a fazer aqui: já está rastreado, e no repositório certo.

## Como rerodar

```bash
cd dbt_futebol
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target prod \
  --select board_reconstrucao_de_publicacao \
  --vars '{pub_fixture_id: 1570342, pub_market: goals_over_under, pub_outcome: Over, pub_line: 3.5}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/board_reconstrucao_de_publicacao.sql
```

A análise é **parametrizada** — serve para qualquer candidato, não só para este. `pub_line` aceita
`NULL` nos mercados sem linha (1X2, BTTS, Dupla Chance): a comparação é NULL-safe. Nada em produção
muda: é `compile` + `bq query`, nunca `dbt run`. E como o `hist` fecha versões em vez de apagá-las,
rerodar para este jogo passado devolve as mesmas transições — hoje e daqui a um ano.

---

# Ticket #107 — As duas fronteiras de faixa, na escala pós-A6

**Análises:** `dbt_futebol/analyses/taskA_a4_fronteiras.sql` (a medição) e
`dbt_futebol/analyses/taskA_a4_reconciliacao.sql` (a resposta conhecida, que roda antes)
**Fonte:** `fact_value_funnel` (ADR 0011), nota **recomputada**, denominador do **seed**
**Rodada publicada:** **2026-08-28**, teto `gravado_em` e `kickoff_utc` em `2026-08-28 21:00:00 UTC`

## As duas fronteiras

**`Baixa` < 25 ≤ `Média` < 55 ≤ `Alta`**, na escala normalizada 0–100. Fronteira pertence à
faixa **de cima**, nas duas — declarado porque este repositório já teve bug de knife-edge de float.

**E o número que importa mais que as fronteiras: elas NÃO saíram do ROI, porque o ROI não
discrimina.** Dos oito pares candidatos, os oito passam nas três restrições de forma e **nenhum**
separa `Alta` de `Baixa` além de um erro-padrão. O ramo E1 da regra fixada de antemão foi o que
disparou, e ele manda escolher por equilíbrio de distribuição — o par que deixa a maior faixa
menor. É o 25/55, com a maior faixa em 36,4%.

## A regra, que foi fixada antes de olhar

Está no cabeçalho da `taskA_a4_fronteiras.sql` e no commit `1136f48`, **anterior a qualquer
execução** — a ordem do histórico é a prova, como o cabeçalho da `taskA_a40_transporte.sql` foi a
da A4.0. Em resumo: grade de oito pares inteiros; três restrições duras (cada faixa ≥ 10%, nenhuma
> 65%, e nenhuma faixa vazia em nenhum dos nove lados com p95 > 0); objetivo de maior `ROI(Alta) −
ROI(Baixa)`; desempate pelo par mais redondo; e três ramos de saída declarados, entre eles o que
de fato ocorreu.

O ramo **é derivado em SQL, não a olho** (bloco `0. RAMO DA REGRA` da saída): a análise conta
quantos pares passam e quantos discriminam, e a ordenação da escolha troca de critério sozinha.

## A curva de ROI do par escolhido

Erro-padrão agrupado por fixture, como o aceite pede.

| faixa | linhas | jogos | share | ROI | EP |
|---|---:|---:|---:|---:|---:|
| `Alta` (≥ 55) | 1.306 | 350 | 33,2% | **−4,6** | 2,7 |
| `Média` (25–55) | 1.192 | 361 | 30,3% | **−8,4** | 2,6 |
| `Baixa` (< 25) | 1.432 | 368 | 36,4% | **−2,6** | 3,3 |

**Três leituras, e as três desagradáveis:**

**1. A ordenação está invertida, e a `Média` é o fundo.** `Baixa` (−2,6) rende melhor que `Alta`
(−4,6), e a `Média` é pior que as duas pontas. Isso é **reportado e não corrigido**, pelo ramo E3
da regra: desde a decisão do PM de 20/08 a nota **informa e não barra**, então faixa é rótulo e não
porta — ela não precisa de ROI monotônico para existir. Mexer na grade para "consertar" a monotonia
seria escolher depois de olhar, que é o que a regra existe para impedir.

**2. Nenhuma faixa é positiva, em par nenhum da grade.** Os 24 valores de ROI medidos (oito pares ×
três faixas) vão de −1,6 a −8,8. Isto é o **board pós-virada** — a população que a #109 vai
publicar, com as três barreiras de preço já em vigor.

**3. Nenhum corte de publicação é proposto**, em ramo nenhum, como o aceite manda. O que a leitura 2
sugere vai ao PM **como pergunta**, não ao modelo como porta.

## A grade inteira

| par | share Baixa / Média / Alta | ROI Baixa / Média / Alta | gap A−B | EP do gap | discrimina? |
|---|---|---|---:|---:|---|
| 20/50 | 30,4 / 31,1 / 38,5 | −1,6 / −8,7 / −4,8 | −3,2 | 4,5 | não |
| **25/55** | **36,4 / 30,3 / 33,2** | **−2,6 / −8,4 / −4,6** | **−2,0** | **4,3** | **não** |
| 25/60 | 36,4 / 36,6 / 26,9 | −2,6 / −8,4 / −3,6 | −1,0 | 4,5 | não |
| 30/60 | 47,2 / 25,9 / 26,9 | −4,1 / −8,1 / −3,6 | +0,5 | 4,0 | não |
| 33/67 | 48,8 / 28,1 / 23,1 | −3,7 / −8,8 / −3,2 | +0,5 | 4,2 | não |
| 35/65 | 52,4 / 24,5 / 23,1 | −5,7 / −5,3 / −3,2 | +2,5 | 4,1 | não |
| 40/70 | 56,3 / 25,7 / 18,0 | −5,5 / −3,1 / −6,3 | −0,8 | 4,7 | não |
| 50/75 | 61,5 / 24,9 / 13,7 | −5,2 / −4,1 / −6,0 | −0,8 | 5,2 | não |

O 35/65 é o par de **maior gap** (+2,5) e teria sido o escolhido pelo objetivo principal. Ele não
foi escolhido porque 2,5 está dentro do EP de 4,1 — e porque ele deixa a `Baixa` com 52,4% do
board, contra 36,4% do 25/55.

⚠️ **O EP do gap ignora a covariância.** Um mesmo fixture pode ter linha na `Alta` e na `Baixa`, e
a raiz da soma dos quadrados trata os dois clusters como independentes. A aproximação não
**inventa** discriminação, e a leitura alternativa — comparar o gap contra o maior dos dois EP de
faixa, sem somar — devolve o mesmo veredito nos oito pares. Medido, não suposto.

## A distribuição por (mercado, lado), que o aceite manda entrar na decisão

A nota é **absoluta** (ADR 0005), então fronteira única não significa volume igual — e isso precisa
estar dito junto do número.

| mercado / lado | linhas | ROI | nota média | p10 | mediana | p90 |
|---|---:|---:|---:|---:|---:|---:|
| asian_handicap / Azarao | 460 | −8,7 | 49,4 | 0 | 67 | 100 |
| asian_handicap / Favorito | 628 | −1,0 | 37,8 | 0 | 33 | 92 |
| btts / No | 372 | −1,9 | 45,5 | 0 | 57 | 100 |
| btts / Yes | 369 | −6,7 | 34,1 | 0 | 29 | 79 |
| double_chance / unico | 395 | −0,2 | 43,7 | 0 | 29 | 93 |
| goals_over_under / Over | 625 | −8,9 | 35,2 | 0 | 32 | 73 |
| goals_over_under / Under | 656 | −5,2 | 32,0 | 0 | 22 | 72 |
| match_winner / Away | 157 | +1,2 | 39,3 | 0 | 36 | 91 |
| match_winner / Home | 268 | −11,4 | 32,9 | 0 | 24 | 76 |

**O p10 é ZERO nos NOVE lados.** Pelo menos um décimo de cada lado tem nota de contexto zerada —
não é peculiaridade de um mercado, é o formato da distribuição inteira. É o que faz a `Baixa`
existir com folga em qualquer par da grade, e é por isso que a restrição C3 nunca mordeu.

O `Azarao` do Handicap é o lado de nota mais alta (média 49,4, mediana 67) **e** o segundo pior de
ROI (−8,7). Os dois lados de melhor ROI — `match_winner/Away` (+1,2) e `double_chance/unico` (−0,2)
— têm nota média no meio da tabela. É a leitura 1 acontecendo lado a lado, e não só no agregado.

## Os dois lados sem lado apostado, à parte

Ficam fora das restrições de propósito: têm p95 = 0 e nota 0 **por construção** — nenhuma premissa
se aplica —, e contá-los dentro faria a restrição ler severidade de régua onde há ausência de lado
(ADR 0005/0006).

- **`match_winner/Draw` — 257 linhas, ROI +15,1.** É a **única célula positiva de toda esta
  medição**, e ela é o empate, cuja nota é sempre zero. Não é recomendação de nada: é o aviso de
  que a nota, nesta janela, não está capturando o que ordena resultado. Vai ao PM junto da
  leitura 2.
- **`asian_handicap/Pick` — ZERO linhas.** Não é amostra pequena, é ausência total, e a causa foi
  isolada: nesta janela existem **762 linhas de `Pick` liquidadas**, e **nenhuma** passa na porta de
  linha meia — a linha 0 não é meia (`MOD(ROUND(0×4), 4) = 0`). As outras portas não são o gargalo:
  **642 das 762** passariam na liquidez de 4 casas e **390** na faixa de odd. É a porta de linha
  meia sozinha que apaga o lado inteiro, antes de qualquer nota. É o defeito que a B3 chama de "a
  linha de handicap zero fica invisível", medido aqui pelo outro lado — e é a razão de o `Pick` ter
  entrado no seed da A6 (952 candidatos na janela dela) sem nunca aparecer no board.

## Ressalvas de validade — o que esta medição herda e o que ela deixa armado

**1. O recorte é congelado, e é reproduzível.** Para reler exatamente esta rodada:

```sql
FROM fact_value_funnel
WHERE janela_e_corrente
  AND gravado_em  < TIMESTAMP '2026-08-28 21:00:00'
  AND kickoff_utc < TIMESTAMP '2026-08-28 21:00:00'
```

É o padrão da #106, e é a resposta ao vício que matou o 40 e o 60: a mesma query de backtest, três
dias depois e sem mudar um byte, moveu a faixa 20–40 de −3,6% para +9,7%. O funil é append-only,
então esta fatia fica preservada.

**2. A nota vem recomputada, e herda a #78.** Universo do funil, pontos dos cinco modelos como
estão hoje — a rota da A6. Premissa recomputada acende em número ligeiramente diferente a cada
build com o insumo congelado. A reconciliação mede o tamanho disso: dez dos onze p95 reproduzem o
seed **exatamente**, e o `match_winner/Home` fica em **−2** (31 contra 33), dentro do ±2 declarado
antes de rodar. É o único lado que se moveu, e é o de menor amostra dos que pontuam.

**3. A liquidação é `status_short = 'FT'`, e não o `futebol_jogo_encerrado()`.** O
`task01_liquidacao()` liquida mercado de 90 minutos; `goals_home`/`goals_away` de jogo decidido na
prorrogação já trazem o placar depois dela, e liquidar um Over 2.5 de mata-mata por ele daria
vitória a uma aposta que perdeu. Consequência declarada: **jogo de mata-mata que foi para a
prorrogação ou para os pênaltis está fora desta medição**, como está fora da [0.1].

**4. O gate pós-virada é recomposto, não lido.** `porta_liquidez_estrita`, `porta_outlier` e
`porta_faixa_odd` chegaram por `append_new_columns` na #104 e são NULL para sempre nas linhas de
jogo já apitado — que são exatamente as liquidadas. Recompor dos insumos congelados
(`n_casas`, `pen_odd_outlier`, `best_odd`, `line_value`) é a única leitura que cobre a série
inteira.

**5. `best_odd` é o máximo entre casas** e enviesa o ROI para cima, uniformemente nas três faixas.
Não afeta a comparação entre faixas, que é o que a decisão usa.

**6. O que invalida estas fronteiras.** Elas são medidas sobre a escala do seed
`futebol_p95_nota_contexto`. Mudança no seed, no catálogo de premissas, no
`macros/futebol_nota_contexto.sql` ou no conjunto de barreiras da #109 **remede as duas
fronteiras**. Em particular: **a B3 (a linha zero do Handicap) muda o par `Pick`** de zero linhas
publicáveis para até 642 nesta janela — se ela entrar entre esta medição e a virada, invalida o que
está escrito aqui. A B3 vai **depois** da #109, ou estas fronteiras são remedidas.

## O que ainda não é decisão

O `accepted_values` de `faixa` e as duas RPCs recebem `Alta` / `Média` / `Baixa` com estas
fronteiras **na virada (#109)**, não aqui. Nada em produção muda nesta entrega.
