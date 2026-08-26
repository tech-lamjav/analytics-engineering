---
status: accepted
---

# O preço sai da nota

O Score do Motor soma quatro blocos: valor (`pts_valor`, 0–30, derivado do edge),
premissas de contexto, corroboração externa e penalidades. Três dos quatro leem **preço** —
o valor é o edge arredondado por faixa, uma das duas parcelas da corroboração é movimento
de odd da Pinnacle, e as quatro penalidades globais são todas sobre a odd. A nota que o
produto publica é, em boa parte, uma releitura do mercado.

Decidimos que **a nota não tem preço dentro**. Nasce no funil uma **nota de contexto** —
pontos de premissa menos as penalidades de contexto, com piso em zero — e nada mais: sem
`pts_valor`, sem corroboração e sem as quatro penalidades de odd.

O preço não some do Motor. Ele continua decidindo, e decide onde sempre decidiu de
verdade: nas **portas** (ADR 0006) — a de edge, a de liquidez, a de odd da Dupla Chance, a
de completude do conjunto. O que muda é que ele para de fingir que é evidência sobre o
jogo.

## O que isso compra

**A nota volta a responder uma pergunta só.** "Quanta evidência de contexto acendeu neste
jogo" e "quanto o mercado está pagando por isso" são duas perguntas, e somá-las num número
só destrói as duas: uma linha com contexto fraco e preço ótimo fica indistinguível de uma
com contexto forte e preço medíocre. Separadas, a régua de nota e a régua de preço podem
ser calibradas cada uma contra o que ela mede.

**A nota passa a ser reproduzível.** Enquanto o preço estava dentro dela, a nota de uma
mesma linha mudava a cada rebuild sem que nada do jogo mudasse. É isso que faz a
`assert_funil_paridade_com_board` e a medição da task [F] terem de conviver com uma
tolerância — e é o que a #78 já tinha diagnosticado do outro lado.

**O grão por janela do funil passa a fazer sentido** (ADR 0006, "por que o grão é a
janela"): sobrando só contexto, a nota muda no ritmo do jogo e não no do mercado. O que se
move a cada 15 minutos é o veredito das portas.

## As duas premissas de Gols que saem junto, e o clamp

`linha_subindo` e `linha_descendo` (6 pontos cada) liam movimento de odd — consenso das
probabilidades implícitas de todas as casas, t24h→t15m. São preço com nome de premissa, e
sobreviver a esta decisão não seria coerente com ela. São também **as duas premissas que
faziam a nota do Gols não ser reproduzível entre builds**: o valor virava sozinho quando as
odds andavam, e a medição da [F] teve de declarar uma régua de tolerância por causa delas.

O `clamp` em 55 do Gols cai junto. Ele existia para aproximar dois lados de teto diferente
(Over Σ56, Under Σ52) — que é exatamente o que a normalização por lado da **A6** resolve,
e melhor —, e o lado Under nunca o alcançava, então ele nem chegava a aproximar: só cortava
o topo do Over. Os tetos do Gols passam a ser **50/46**.

Com isso o `int_futebol_premissas_ou` deixa de ler preço. Ele continua lendo
`fact_odds_snapshot`, mas só na CTE que decide **quais linhas existem** para avaliar —
decidir o universo de linhas não é pontuar preço.

## As quatro penalidades que ficam

`pick_empate` (−10), `desfalque_proprio` (−15), `linha_extrema` (−10, Gols) e
`handicap_alto` (−12, Handicap). Nenhuma lê preço: `linha_extrema` e `handicap_alto` leem a
**linha**, que é característica do mercado apostado e não do preço dele — "Over 5,5" é uma
aposta diferente de "Over 2,5" mesmo que as duas fossem pagas igual.

E elas ajudam, medido na A4.0: **0,119 com, 0,105 sem**.

## A alternativa medida que foi rejeitada

Manter `linha_subindo`/`linha_descendo` na nota, tratando-as como evidência de contexto
sob o argumento de que "o mercado sabe coisas sobre o jogo". Ela tem um registro em
contrário do próprio Victor, desfeito por ele em 05/08 — e tem número: a variante **sem** as
duas mede **0,112** contra **0,119** da variante com elas (`analyses/taskA_linha_de_base.sql`,
`analyses/taskA_a40_transporte.sql` fonte F). É diferença dentro do ruído, e neutra em
volume.

Ou seja: manter as duas custa a coerência da decisão inteira e a reprodutibilidade da nota
do Gols, e compra 0,007 que a própria medição não consegue distinguir de zero.

## O que esta entrega NÃO muda

**O board não muda de gate nem de número.** A nota de contexto nasce **ao lado** da nota de
hoje, como coluna do funil, e o `fact_value_opportunities` continua com o `score` e a régua
de sempre. É o desenho da [A] inteira: cada passo é medível no funil enquanto o produto
segue no gate antigo, e existe **uma virada só**, no fim.

A diferença visível é consequência da remoção das duas premissas, e ela foi **medida em
26/08 15:00 UTC**, não estimada — comparando o modelo de Gols de produção com o pós-A1
compilado e materializado no mesmo instante, sobre os mesmos fatos:

| | |
|---|---|
| linhas de Gols no modelo | 80.130 |
| linhas que **caem** | 6.342 (**7,91%**) |
| linhas que sobem | 0 |
| **maior queda** | **6 pontos** |
| queda média | 0,47 ponto |
| linhas no `clamp` de 55 hoje | 95 — caem 5, e não 6, porque o clamp já lhes tirava 1 |
| teto observado | 55 → **50** |
| **linhas de jogo AINDA NÃO INICIADO que mudam** | **0** |

E no que o produto publica, no mesmo instante: **6 linhas** de Gols no board, **nenhuma** se
move; **3.471** candidatos de Gols no funil da janela corrente, **nenhum** se move, 90 passam
na porta de nota antes e depois, 6 publicam antes e depois.

⚠️ **A spec da issue previa "até 12 pontos", e a aritmética não permite 12.** `linha_subindo`
só pode acender no Over e `linha_descendo` só no Under: uma linha é de um lado só, então
perde **uma** das duas, nunca as duas. O número é 6.

⚠️ **E a queda não alcança o board, por construção.** As duas premissas comparam a janela
`t24h` com a `t15m`, e a `t15m` só existe depois que a coleta de quinze-minutos-antes
aconteceu — ou seja, nos últimos minutos antes do apito. Até lá `prob_t15m` é NULL e as duas
estão estruturalmente apagadas. Elas acendem em 7,91% das linhas do histórico e em **zero**
das 16.782 de jogo por começar. A faixa em que elas pontuavam é justamente a que o board
expurga (ADR 0009) e o funil congela (ADR 0011).

Isso é achado, não conveniência: **as duas premissas cobravam preço numa janela em que a
aposta já quase não existe**, e é mais um argumento para tirá-las do que qualquer coisa
escrita na issue.

### A diferença visível de verdade é OUTRA, e o code review a pegou

A issue diz *"a única diferença visível é a queda da nota do Gols"*. Não é: o board publica
também o **contador de cegueira** `premissas_sem_dado` (#41, ADR 0003), e o renderiza em
`avisos[]` como *"a nota não levou N premissas em conta"*. Removida uma premissa, some junto
a cegueira dela.

Medido no mesmo instante:

| | |
|---|---|
| linhas de Gols cujo contador **cai** | 65.545 de 80.130 (**81,8%**) |
| queda | sempre exatamente **1** |
| linhas com alguma cegueira | 69.234 → **13.006** |
| cegueira média por linha | 1,22 → **0,41** |
| linhas de jogo por começar cujo contador cai | **16.782 de 16.782 — todas** |

E no board de hoje, nas 6 linhas de Gols: **todas** carregam `premissas_sem_dado = 1`, e em
**todas** a única premissa cega listada em `premissas_cegas[]` é a que está sendo removida
(`linha_subindo` em cinco, `linha_descendo` numa). Depois da A1 as seis vão a **zero**.

⚠️ **E a diferença vai no sentido OPOSTO ao que a issue previu.** A nota não se move; o que
muda é o board **parar de avisar** que não pôde avaliar uma premissa. O aviso era honesto e
virou desnecessário: ele reportava cegueira sobre a premissa que só enxerga na janela `t15m`,
que é a mesma razão pela qual ela nunca acendia no que o board publica. O contador não entra
na nota (ADR 0003), então **nenhum número do produto muda** — muda um texto, para menos.

Isso não estava na issue e é o segundo efeito visível. Fica registrado aqui para que o
próximo leitor não o descubra como surpresa num board que "não devia ter mudado".

O funil não vai para o Supabase, então nada aqui toca migração, RPC ou
`check_schema_parity`.

## O custo, e as guardas

O custo é que a composição da nota passa a viver em **dois** arquivos até o flip (A2/#97):
o mart, que continua com a aritmética antiga, e o funil, que ganha a nova ao lado dela. É
duplicação por uma janela declarada, não descuido, e quem mantém os dois honestos é a
`assert_funil_paridade_com_board` — que compara o `score`, não a nota de contexto, porque é
o `score` que existe dos dois lados.

A decisão em si é cara de reverter (muda o produto e quebra a série histórica do board) e
surpreendente sem contexto — um leitor futuro vai perguntar por que um motor de value
betting ignora valor no seu próprio rating. Por isso ela vem com **três** defesas, e nenhuma
delas cobre sozinha o que as outras cobrem:

| defesa | o que prova | o que ela NÃO alcança |
|---|---|---|
| `assert_nota_contexto_sem_preco` | não há componente de preço no TEXTO da composição | não prova que o modelo usa essa composição |
| `assert_funil_nota_contexto_reconstroi` | a coluna gravada bate com a recomposta pelo macro | não vê preço que esteja DENTRO do macro (entraria nos dois lados) |
| unit test `funil_nota_de_contexto_ignora_o_preco` | dois candidatos de mesmo contexto e preços opostos têm a MESMA nota | é linha construída, não produção |

A composição mora num lugar só — `macros/futebol_nota_contexto.sql`, sem argumento —, e é
de propósito que ela não aceita parâmetro: parâmetro seria a porta por onde o preço voltaria
sem que o arquivo que a sentinela vigia mudasse uma linha.

## O que fica NULL para sempre, e por quê

O funil é append-only e congela no apito (ADR 0011). A coluna nova chega por
`append_new_columns` e só é escrita em linha de jogo ainda futuro: **toda linha de jogo já
apitado antes deste deploy fica com `nota_contexto` NULL, para sempre**. Não é defeito — é a
história congelada fazendo o que a #96 construiu para ela fazer, e é o que torna o dia da
virada legível na série sem ninguém precisar lembrar a data.

É por isso que a guarda de reconstrução é escopada ao que ainda é gravável, e não "em toda
linha" como o aceite da issue pede ao pé da letra: a leitura literal nasceria vermelha sobre
o funil inteiro de antes de hoje, contra o aceite irmão de que **guarda nova nasce em zero**
(precedente da #33).

## O deploy

Não há modelo novo, então **nada muda no `--select` dos workflows** e nada precisa ser
redeployado do lado da DE — as duas guardas novas entram pela `tag:guarda`, que o agendado
já roda inteira (`dbt ls --select tag:guarda --resource-type test` passa de **42** para
**44**).

1. mergear;
2. `./build-and-push.sh dbt_futebol`;
3. disparar o `workflow-futebol-odds` à mão e conferir: `nota_contexto` preenchida nas
   linhas de jogo futuro, e as duas guardas novas verdes.

⚠️ **Entre (1) e (3), DUAS guardas ficam vermelhas, e as duas são esperadas.** As duas são o
mesmo fenômeno — código novo lendo tabela velha —, e as duas passam sozinhas no (3):

- `assert_funil_nota_contexto_reconstroi` dá **erro de compilação**: a coluna só existe na
  tabela depois que o primeiro build pós-deploy roda o `append_new_columns`, e até lá o
  BigQuery devolve *Unrecognized name: nota_contexto*;
- `assert_premissas_insumo_declarado` **falha com 2 linhas**: o mapa já não declara
  `linha_subindo`/`linha_descendo`, e a tabela de produção ainda tem as duas colunas. É a
  direção "mapa envelhecido" da guarda acendendo ao contrário — o mapa está novo e a tabela
  velha —, e ela é literalmente a guarda funcionando. Conferido em 26/08: verde no
  `--target taskF`, onde o modelo já tinha sido reconstruído com o código novo.

Está escrito aqui porque a alternativa é alguém gastar um dia rediagnosticando um alarme que
a própria ordem do deploy produziu — mesmo padrão que a #96 registrou entre a imagem e o
`bq rm`.

⚠️ **O SELO NÃO SE MOVE, e isto foi conferido, não suposto.** O `fact_value_funnel_selo` e a
`assert_funil_imutavel_por_dia_de_kickoff` guardam `COUNT(*)` e `SUM(score)` por
(fixture, dia de kickoff) — nenhum dos dois lê `nota_contexto`, e coluna nula nova não move
contagem nem soma. Fosse o selo uma impressão digital da linha inteira
(`TO_JSON_STRING`, um hash), o `append_new_columns` teria mudado todo hash congelado e a
guarda de imutabilidade nasceria **permanentemente vermelha sobre a história inteira** — que
é o modo de falha que este repositório documenta em todo lugar. Não é o caso, e é por isso
que **não há passo de derrubar funil e selo juntos neste deploy**.

⚠️ **Não há `bq rm` neste deploy, e não pode haver.** Derrubar o funil recalcularia a
história inteira com o código pós-A1, que é exatamente a coisa que a #96 existe para
impedir. As linhas antigas ficam como estão, com `nota_contexto` NULL — ver a seção acima.

## A interação com a medição, que estava sem dono

`macros/task01_base.sql` — o catálogo que define o universo dos Testes 2, 3 e 4 — listava as
duas premissas removidas, e o `int_futebol_premissas_ou` é um dos cinco modelos que a
**âncora da remedição (#82)** exige imóveis. As 39 premissas do catálogo viram **37**, e a
âncora foi **re-rodada no mesmo PR** — a versão anterior preservada em
`futebol_taskF.taskf_teste2_ancora_pre_a1`, o carimbo novo em `docs/TASKF_RESULTADOS.md`,
seção "#103".

O delta é exatamente o previsto e nada além dele: mesmo universo (169 jogos, 5.605 linhas,
mesmo `odds_loaded_at`), **4 linhas sem contraparte** — `Gols · linha_subindo` e
`Gols · linha_descendo` nos dois benchmarks, e só elas — e **3 campos divergentes em 1.680**,
todos de 0,1 pp, dentro da régua de 0,25 pp da #92 e sem mecanismo pela A1. Fora as quatro que
sumiram de propósito, a âncora reproduziu a si mesma.

`penalidades_globais_pts` **permanece** no `int_futebol_odds_devig`. A regra do aceite é "o
que sai do de-vig é só o que ninguém mais soma", e o `task01_base` soma — então nada sai.
Ela fica como coluna sem consumidor de pontuação na nota de contexto, exatamente como o
`int_futebol_corroboracao` fica como modelo sem consumidor de pontuação.

E as análises que mediram esta decisão — `taskA_linha_de_base.sql`,
`taskA_a40_transporte.sql`, `task01_estabilidade.sql` — **não são reescritas**. Elas leem
colunas que já não existem e param de rodar; reescrevê-las para "consertar" mudaria o que
elas mediram, e o registro de uma medição executada não se reescreve. Cada uma diz isso de
si mesma no cabeçalho.
