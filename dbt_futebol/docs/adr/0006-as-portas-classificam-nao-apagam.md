---
status: accepted
---

# As portas classificam, não apagam

O mart guarda **só o que passa**. A `fact_value_opportunities` tem nota mínima 40 e zero linhas
abaixo, e o histórico é uma foto da mesma tabela, então herda o mesmo recorte. Tudo que é
rejeitado desaparece sem registro.

A consequência é que toda decisão de régua é tomada sobre um backtest que recalcula o passado
inteiro a cada execução — e cuja janela é "tudo que liquidou até hoje", que cresce. A mesma
query, três dias depois e sem mudar um byte, moveu a faixa 20–40 de **−3,6% para +9,7%**. Não é
bug. É que a régua está sendo escolhida sobre um número com validade de dias.

Decidimos que **toda linha candidata é gravada**, com a nota, os componentes e o veredito de
cada porta, e que o board lê só as que passam. As portas deixam de ser um `WHERE` que apaga e
passam a ser colunas que classificam.

É o mesmo conserto que já resolveu uma dor uma camada abaixo — o snapshot da oportunidade que
não guardava histórico — aplicado agora ao funil, que continua sem memória de tudo que
descartou.

## O que é um candidato

Um `(fixture, mercado, saída, linha, janela)` que **teve preço naquela janela**.

A fronteira importa porque os modelos de premissa não têm filtro nenhum: rodam sobre a
`fact_fixtures` inteira e geram linhas canônicas mesmo para jogo que nunca foi precificado — um
piso de 21 linhas por fixture, sem recorte de data, crescendo para sempre. Gravar essas como
"rejeitadas" seria registrar ausência de mercado como decisão nossa.

"Ninguém precificou este jogo" é **coleta**, e a subtask C6 está construindo a sentinela de
vazio exatamente para isso. Com a fronteira no preço, a divisão fica limpa: **a [C] responde
"houve preço?", a [A] responde "o preço que houve passou nas portas?"** — e a pergunta "por que
essa linha não publicou" deixa de ter duas respostas em dois lugares.

Linha cujo conjunto de saídas veio incompleto **continua candidata**: pela ADR 0002 ela existe
no de-vig, só perdeu a probabilidade justa. É a maior rejeição do funil — 4.735 linhas, 49% do
universo — e sob qualquer fronteira mais larga esse número se diluiria até deixar de significar
alguma coisa.

Jogo encerrado também continua no universo, e tem que continuar: é ele que responde a pergunta
que justifica esta decisão inteira — quanto rendeu a faixa que a gente descartou.

## Por que o grão é a janela

O mart reconstrói a cada 15 minutos. A leitura literal de "gravar todas as linhas candidatas"
daria 96 fotos por dia do universo inteiro.

O grão por janela colapsa isso em **três registros por candidato**, sem perder nada, e o motivo
é uma consequência da A1 que não estava escrita: **depois que o preço sai da nota, a nota para
de depender de preço**. Os modelos de premissa leem `fact_odds_snapshot` em três lugares, e só
um deles é valor de premissa — `linha_subindo`/`linha_descendo`, que a A1 remove. Os outros dois
apenas decidem **quais linhas existem**. Sobrando só esses, a nota vira função pura do contexto
do jogo e muda no ritmo dele, não no do mercado.

O que se move a cada 15 minutos, portanto, não é a nota: é o veredito das portas. E veredito
muda quando a janela muda.

Esse é também o grão que a subtask C5 está introduzindo no de-vig. Adotá-lo aqui transforma uma
colisão entre duas frentes em convergência.

## O board não herda esse grão

São três camadas, e só as duas de baixo são por janela: **de-vig por janela** (ADR 0004),
**funil por janela** (esta), e o **board continua com uma linha por linha**, avaliada na janela
corrente e carregando `janela_deteccao` — a janela mais cedo em que a linha passou.

A ADR 0004 rejeitou o board por janela com razão: quebraria a `opportunity_key` do snapshot,
triplicaria o que o sync materializa no Postgres e empurraria para o front uma decisão de
produto, qual das três mostrar. Nada disso muda aqui. **O board lê o funil e colapsa para a
janela corrente**; quem guarda as três é o funil, que é onde a pergunta de CLV vive.

⚠️ E fica registrada uma interação entre as duas frentes que nenhuma das duas ADRs tinha: a ADR
0004 escreve *"oportunidade que perdeu edge sai do board"*, e dimensiona o que a mudança compra
com **931 / 1.350 / 368 linhas** recomputando o gate de valor por janela. Esses números — e a
própria frase — assumem o gate de hoje, em que `edge > 0` elimina. **A A2 tira o edge do gate.**

Depois da A1 e da A2 a nota não se move entre janelas, então uma linha não sai mais do board por
perder evidência: sai por preço — a porta de odd, a liquidez, a completude do conjunto. As 368
linhas que "passam em t24h e já não passam em t15m" continuam existindo como pergunta de CLV,
mas passam a ser um conjunto **diferente**, definido por outras portas. Quem for medir aquilo
depois da [A] precisa remedir, não reaproveitar o número.

## Por que um booleano por porta, e não um motivo

Uma linha reprova em várias portas ao mesmo tempo. Um campo único de motivo é vitória do
primeiro da fila, e destrói a distinção que dá valor à tabela: quantas linhas cada porta remove
**sozinha**, e quantas ela ainda remove **depois** das anteriores. É a diferença entre a leitura
isolada e a marginal — e é literalmente a análise para a qual esta tabela existe.

Um `motivo_primario` derivado por cima dos booleanos é conveniência de leitura, não a fonte.

## O empate carrega motivo próprio

O empate é **um terço do universo de candidatos do 1X2 por construção** — os modelos emitem três
linhas por fixture — e está estruturalmente em zero, porque sem lado apostado nenhuma premissa
dispara.

Sob o motivo genérico, esse terço apareceria como "nota abaixo da régua", e a porta de nota
pareceria mais severa no 1X2 do que é. O número que já circula é a queda de **235 para 23
linhas, −90%**, e parte dela é o empate sendo zero, não a régua agindo. Com motivo próprio, a
linha de base separa as duas coisas sozinha.

## O custo, e as duas armadilhas

O custo é volume, e ele fica sem número por decisão: agora que a fronteira está no preço e o
grão colapsa os rebuilds, dá para **medir** a retenção em vez de chutar seis meses. A política
sai declarada junto com o primeiro número real.

A tabela não vai para o Supabase. Fica no BigQuery: o app não lê funil, o sync é tabela a tabela
e aborta em divergência de esquema, e já derrubou o workflow por falta de memória.

⚠️ A linha de base refeita passa a ler **desta tabela** em vez de reimplementar os cinco ramos à
mão, e por isso precisa **fixar uma janela por candidato antes de contar**. Contando as três,
todo número infla até 3× — é o mesmo erro do "2,87× quase triplica a amostra", que já foi
derrubado uma vez do outro lado do projeto.

⚠️ E uma tabela que ninguém lê é uma tabela que ninguém percebe estar errada. O aceite de que a
soma das rejeições mais as publicadas fecha com o universo de candidatos é o que impede isso —
mas ele é uma guarda, e guarda em dbt hoje não alarma (ver ADR 0005 e a subtask C4).
