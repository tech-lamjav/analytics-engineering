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

A única diferença visível é consequência da remoção das duas premissas: **a nota do Gols no
board de hoje cai até 12 pontos**, e algumas linhas somem por não alcançarem mais o corte de
40. É para menos, nunca para mais.

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

⚠️ **Entre (1) e (3) a `assert_funil_nota_contexto_reconstroi` dá ERRO, e é esperado.** A
coluna só existe na tabela depois que o primeiro build pós-deploy roda o
`append_new_columns`; antes disso a guarda não acha `nota_contexto` e o BigQuery devolve
*Unrecognized name*. É erro de compilação, não guarda vermelha, e passa sozinho no (3) —
mesmo padrão que a #96 registrou entre a imagem e o `bq rm`. Está escrito aqui porque a
alternativa é alguém gastar um dia rediagnosticando um alarme que a própria ordem do deploy
produziu.

⚠️ **Não há `bq rm` neste deploy, e não pode haver.** Derrubar o funil recalcularia a
história inteira com o código pós-A1, que é exatamente a coisa que a #96 existe para
impedir. As linhas antigas ficam como estão, com `nota_contexto` NULL — ver a seção acima.

## A interação com a medição, que estava sem dono

`macros/task01_base.sql` — o catálogo que define o universo dos Testes 2, 3 e 4 — listava as
duas premissas removidas, e o `int_futebol_premissas_ou` é um dos cinco modelos que a
**âncora da remedição (#82)** exige imóveis. As 39 premissas do catálogo viram **37**, e a
âncora foi **re-rodada no mesmo PR**, com o carimbo novo em `docs/TASKF_RESULTADOS.md`.

`penalidades_globais_pts` **permanece** no `int_futebol_odds_devig`. A regra do aceite é "o
que sai do de-vig é só o que ninguém mais soma", e o `task01_base` soma — então nada sai.
Ela fica como coluna sem consumidor de pontuação na nota de contexto, exatamente como o
`int_futebol_corroboracao` fica como modelo sem consumidor de pontuação.

E as análises que mediram esta decisão — `taskA_linha_de_base.sql`,
`taskA_a40_transporte.sql`, `task01_estabilidade.sql` — **não são reescritas**. Elas leem
colunas que já não existem e param de rodar; reescrevê-las para "consertar" mudaria o que
elas mediram, e o registro de uma medição executada não se reescreve. Cada uma diz isso de
si mesma no cabeçalho.
