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
