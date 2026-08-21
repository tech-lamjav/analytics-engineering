---
status: accepted
---

# O funil é append-only e congela no apito

A ADR 0006 decidiu **o que** gravar — toda linha candidata, com a nota e o veredito de cada
porta — e deixou aberto **como**. As duas leituras de "gravar o funil" não são variações de
implementação, são tabelas diferentes:

- **tabela reconstruída**: o que o código de hoje diria sobre as odds que ainda estão em disco;
- **registro append-only**: o que o motor de fato disse, no dia em que disse.

O custo não decide. Medido em 19/08/2026, o universo inteiro de candidatos — cinco mercados
pontuados, quatro janelas, de 16/06 (primeira odd coletada) até hoje — são **91.385 linhas** em
**384 fixtures**, e o `int_futebol_odds_devig` de onde elas saem ocupa **18,4 MB**. Cerca de
**45 mil linhas por mês**. Qualquer das duas cabe em qualquer orçamento que este projeto tenha.

Quem decide é o motivo pelo qual a A7 entra **antes** das outras subtasks da [A]: *"senão
perde-se o funil antigo"*. Uma tabela reconstruída não preserva funil nenhum. No dia em que a
A1 tirar o preço da nota, o rebuild seguinte reescreve 16/06 em diante sob as regras novas, e o
funil antigo — a coisa inteira que a A7 existe para salvar — deixa de existir sem deixar rastro.

Decidimos que o funil é **append-only**: cada `(candidato, janela)` é escrito uma vez, atualizado
enquanto o jogo ainda não começou, e **congelado no apito**. Depois disso a linha não é
reescrita por build nenhum, nem por deploy nenhum.

## Por que o congelamento é no apito, e não no status final

A alternativa era congelar quando o jogo termina (`FT`/`AET`/`PEN`/…), aproveitando a mesma
fronteira que a ADR 0009 usa no expurgo do board. Ela abre exatamente a fresta que a 0009
existe para fechar: entre o apito inicial e o final há duas horas em que os modelos de premissa
continuam rodando, e tudo que fosse escrito ali seria **nota nascida depois de a bola rolar**.
O funil serve para responder quanto rendeu a faixa descartada — uma nota que ninguém podia ter
lido antes de apostar não responde essa pergunta, contamina ela.

Status terminal continua governando outra coisa, e só ela: **até quando a fonte emite** aquele
fixture. É parâmetro de coleta e vai mudar com a [C]; o congelamento não depende dele.

⚠️ **Jogo adiado reabre.** `PST`/`SUSP` mantêm o jogo por acontecer e o kickoff muda de lugar.
Com o congelamento amarrado ao kickoff de registro, as linhas daquele fixture voltam a ser
graváveis quando a nova data entra — e é o comportamento certo: o jogo voltou a ser apostável,
as janelas são recoletadas, e o que estava escrito descrevia uma partida que não aconteceu.

## A fronteira do universo tem duas bordas, não uma

A ADR 0006 fixou a borda de fora: candidato é linha que **teve preço**. Faltavam as duas de
dentro, e elas se separam:

**Mercado não modelado fica fora.** O de-vig emite Gols do 1º tempo (mercado 6) — **22.363
linhas** hoje — e não existe modelo de premissa para ele. Gravar isso como "rejeitado" seria
registrar como decisão nossa a ausência de um modelo que nunca escrevemos. O universo do funil
são os **cinco mercados pontuados** (1, 4, 5, 8, 12), e é contra eles que a guarda reconcilia.

**Saída não catalogada fica dentro.** Dentro de um mercado que o Motor pontua pode haver uma
saída precificada que ele não avalia: a Dupla Chance tem três saídas cotadas (1X, 12, X2) e o
mart só publica 1X e X2. São **1.059 linhas**, um terço exato do universo de DC, hoje
invisíveis — o `INNER JOIN` com as premissas as descarta antes de qualquer porta. Elas tiveram
preço, então são candidatas, e a decisão de não pontuá-las é nossa: viram uma **porta própria**
(`porta_saida_catalogada`), não um sumiço.

Medido: nas outras quatro combinações a cobertura é exata — 3.177/3.177 no 1X2, 40.393/40.393
no Handicap, 42.520/42.520 no Gols, 2.118/2.118 no Ambos Marcam. A DC é o único vazamento, e é
estrutural.

## O filtro de completude tem que virar coluna

Isto não é preferência de estilo, é condição de existência da tabela. Hoje cada ramo do mart
carrega `WHERE d.pin_n_outcomes >= N` **dentro do join**, antes de qualquer nota. A maior
rejeição do funil — conjunto incompleto, que a ADR 0006 dimensionou em 49% do universo — nunca
chegaria ao funil se essa estrutura fosse mantida. A tabela nasceria respondendo uma pergunta
diferente da que foi encomendada, e o número que ela publicasse pareceria certo.

O mesmo vale, em grau menor, para o gate de odd próprio da Dupla Chance (`best_odd >= 1.25`),
que também mora no `WHERE` do ramo.

## O expurgo não é porta do funil

Tentador, e errado. Uma coluna `porta_expurgo` gravada sob esta ADR seria **FALSE para sempre**:
no instante do congelamento nenhum fixture está encerrado, por construção. Coluna morta no dia
do deploy.

O expurgo continua onde a ADR 0009 o colocou — no board, sobre o status vindo de
`fact_fixtures`. E daí sai a consequência que precisa estar escrita antes de alguém tentar o
atalho: quando o board passar a ler o funil, **`WHERE janela_e_corrente AND passou_no_gate` não
basta**. O funil guarda o jogo encerrado de propósito; um board que só filtrasse essas duas
colunas voltaria a emitir jogo velho para sempre — reintroduzindo, pela porta dos fundos, o
defeito de 121 linhas com 2 jogos futuros. A junção com o status vai junto no flip.

## A entrega é em dois passos, e o segundo espera a #85

1. **O funil, com o board intacto.** Modelo novo, backfill de 16/06 em diante, guarda de
   reconciliação, e uma guarda de paridade que exige `board == funil filtrado`. Nada em
   produção muda de comportamento; o que a paridade compra é a prova de que o funil descreve o
   board de verdade, antes de qualquer um depender disso.
2. **O flip**: o board passa a ler o funil, a lógica sai duplicada e a guarda de paridade vira
   tautologia e é aposentada no mesmo commit.

O passo 2 vai **depois** do passo do mart da #85 (expurgo). Os dois reescrevem o mesmo arquivo e
os dois mudam o conjunto que o sync leva para o Postgres; empilhá-los na mesma janela é trocar
duas mudanças de comportamento por um único diagnóstico.

O funil **não vai para o Supabase** (ADR 0006), então nenhum dos dois passos toca migração,
`check_schema_parity` ou RPC. É não-objetivo declarado, não omissão.

## A guarda lê a fonte

A reconciliação é *candidatos no de-vig (cinco mercados) = linhas no funil*, contada **contra o
de-vig**, nunca contra o próprio funil. Uma guarda que soma as rejeições do funil e compara com
o total do funil fecha sempre — é a mesma armadilha que a costura B da task [F] já pagou uma
vez: guarda que lê o próprio produto não é guarda, é uma segunda cópia da exclusão.

⚠️ Ela herda o ponto cego conhecido: teste em dbt só alarma pela seleção `tag:guarda`, e mesmo
lá o job devolve sucesso até a C4 fechar (ADR 0005).

## Retenção, agora com número

A ADR 0006 deixou a política sem número de propósito, esperando medir. O número existe: **~45
mil linhas/mês**. Dez anos de operação, com o dobro de ligas, não chegam a 10 milhões de linhas
nem a 5 GB. **Não há expurgo do funil**, e a política se revisita se a tabela passar de 10
milhões de linhas — que é uma forma de dizer que ela não se revisita.

## A virada é um passo só, e ele derruba a tabela

O passo 1 entregou o funil como tabela reconstruída. Virá-lo append-only não é uma mudança que
o próximo build absorve sozinho: a `unique_key` do merge inclui `line_key`, que não existe nas
linhas de lá, e num `MERGE ... ON` NULL nunca casa com NULL — a primeira execução sobre a tabela
velha **duplicaria** toda linha de jogo futuro em vez de atualizá-la, e as linhas antigas ficariam
com `origem` NULL para sempre.

A cutover, então, é: **derrubar a tabela e deixar o primeiro build recriá-la**. Ele roda o ramo
de full refresh, carimba `backfill` em 16/06 em diante — que é exatamente o que o carimbo quer
dizer — e a partir daí toda escrita é incremental e congelada. O selo (`fact_value_funnel_selo`)
nasce na mesma execução, sobre esses números.

A ordem, e ela é apertada porque o `workflow-futebol-odds` dispara com frequência:

1. mergear a AE e **deployar o workflow da DE** — editar o `workflow_futebol_odds.yml` local não
   muda o workflow live, então é `./scripts/deploy_workflows.sh workflow-futebol-odds` na DE. Vem
   antes porque o `--select` enumera modelo a modelo e modelo fora da lista nasce parado; nome
   desconhecido no `--select` é só warning, então o workflow pode ir na frente da imagem;
2. `./build-and-push.sh dbt_futebol`;
3. **imediatamente** `bq rm -f -t smartbetting-dados:futebol.fact_value_funnel`;
4. disparar o workflow à mão e conferir: nenhuma linha com `origem` NULL, e o selo com linhas.

Se uma execução agendada couber entre (2) e (3) e fizer o merge ruim, o conserto é o mesmo (3) e
(4) de novo — o estado não é absorvente.

⚠️ **Entre (2) e (3) as QUATRO guardas do funil dão ERRO, e é esperado.** Elas rodam da imagem
nova contra a tabela velha: as duas novas não acham `origem` nem o selo, e as duas do passo 1 não
acham `line_key`. É erro de compilação, não guarda vermelha, e passa sozinho no (4). Está escrito aqui porque a alternativa é alguém gastar um dia
rediagnosticando um alarme que a própria ordem do deploy produziu — já aconteceu duas vezes com o
board t24h.

⚠️ E daqui sai uma regra permanente: **funil e selo caem juntos, ou nenhum dos dois cai.** Um
selo reconstruído a partir do funil de agora é um selo que concorda com qualquer coisa; um funil
reconstruído sob um selo velho deixa a guarda vermelha para sempre — e guarda permanentemente
vermelha morre ignorada.

## As guardas mudam de escopo, e é por estarem certas

Duas guardas do passo 1 ficariam vermelhas **por acerto** depois do congelamento, e por isso
passam a ser escopadas ao que ainda não começou:

- **reconciliação** — o funil nunca expurga e a fonte só emite enquanto a coleta emite aquele
  fixture. No primeiro dia em que o de-vig soltar um jogo velho, o funil guarda mais história do
  que a fonte. Ela passa a comparar o conjunto de que o modelo é responsável nesta execução:
  candidato de kickoff futuro (ou desconhecido, que é gravável para sempre por fail-open);
- **paridade com o board** — as duas tabelas param de andar juntas no instante do apito. O funil
  congela ali; o board continua recalculando até o expurgo levá-lo, relendo premissas que a #78
  já mostrou não serem reprodutíveis entre builds. Ela passa a comparar só o jogo por acontecer,
  que é também o único conjunto em que a paridade interessa — é o que o assinante ainda pode
  apostar.

O que sai junto com os dois escopos é a história já congelada. Quem cobre essa metade é a guarda
de imutabilidade, e ela consegue porque compara contra um registro escrito **fora** do funil.

## Os carimbos, e o que eles tornam legível

Cada linha carrega `gravado_em` e `origem` (`backfill` | `corrente`). O backfill recalcula
16/06 em diante sob o código de hoje: é a única parte do funil que **não** é registro do que
foi dito na época, e tem que dizer isso de si mesma. Com o carimbo, o dia da virada da A1 fica
legível na série sem ninguém precisar lembrar a data.

## O que esta decisão NÃO compra

**Não conserta a irreprodutibilidade das premissas.** A issue #78 mostrou premissa que acende
em número diferente de linhas a cada build com o insumo congelado. O congelamento no apito
guarda o valor que existia no apito e para de reescrevê-lo — o que torna a oscilação **inócua
para o histórico** e, ao mesmo tempo, **invisível nele**. Quem for medir reprodutibilidade
continua medindo antes do apito, não aqui.

**Não muda a nota de ninguém.** O funil de hoje é o mart de hoje com os `WHERE` virados coluna.
Se a primeira linha de base tirada dele não bater com a cópia à mão, o errado é o funil.

⚠️ E uma correção de fato na ADR 0006, que a citava de memória: são **quatro** janelas por
candidato, não três — a `daily` entrou em 07/08/2026 e o de-vig já emite nas quatro.
