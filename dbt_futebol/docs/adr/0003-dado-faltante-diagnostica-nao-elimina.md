---
status: accepted
---

# Dado faltante diagnostica, não elimina

A ADR 0002 decidiu que conjunto de saídas incompleto **não emite valor nenhum** — fail-closed.
A pergunta natural em seguida é por que a mesma régua não vale para premissa sem insumo, que
é o mesmo formato de problema. Decidimos que **não vale**: premissa sem insumo continua não
acendendo, o score não muda, e o que entra é um contador — `premissas_sem_dado` — mais o aviso
correspondente no board.

A distinção que sustenta as duas decisões opostas é entre **número fabricado** e **número
incompleto**. O de-vig sobre uma saída só devolvia `prob = 1,0` onde a verdade era 0,3, e um
edge de +14.900%: o número estava *errado*, e um número errado carimbado como benchmark sharp
é pior que número nenhum. Premissa que não acende por falta de insumo devolve um score de 45
onde poderia ser 53: o número está *incompleto*, e incompleto é auditável — desde que alguém
conte.

O tamanho de aplicar o fail-closed aqui decide sozinho. Dos **8.355 fixtures** que passam pelo
Motor, **28** têm lista de desfalque coletada antes do apito — **0,34%**. Barrar a linha cuja
premissa não pôde ser avaliada apagaria o board inteiro, e ele só voltaria conforme a base
pré-jogo acumulasse, a ~5–10 fixtures por dia, forward-only. Uma regra correta que zera o
produto por dois meses não é uma regra que sobrevive; é uma regra que alguém desliga.

## O que muda mesmo com o score intacto

Três insumos chegam ao CTE de métricas já COALESCEados para zero — `s_missing`,
`n_wins_last5`, `h2h_total`. Enquanto isso for verdade, `IS NULL` não detecta cegueira nenhuma
e o contador nasceria zerado. **Remover esses COALESCE é o trabalho**; o contador é a
consequência.

Dois dos três só suprimem: zero nunca satisfaz `>= 3` nem `>= 1`, então a premissa já não
acendia e continua não acendendo. O terceiro fabrica: `desfalque_adversario` é
`o_missing >= 1 AND s_missing = 0`, e o zero forçado do nosso lado é **condição para a premissa
acender**. Cegueira habilitando premissa é o caso que a ADR 0002 chamaria de número fabricado,
e é o único aqui. Atinge no máximo **7 linhas em 25.065** — o que torna "score intacto" uma
afirmação verificável, não uma esperança.

## A dependência que não é opcional

O `s_missing` só pode virar NULL se existir de onde tirar o NULL, e hoje não existe. O
extractor de injuries, ao receber resposta vazia, não grava arquivo — com a justificativa
escrita no código de que "gravar vazio travaria o skip-if-exists e viraria linha NULL". O
efeito é que **"perguntamos e a fonte não tinha" e "nunca perguntamos" são o mesmo estado no
armazenamento**, e nenhum modelo a jusante consegue distinguir os dois por mais correto que
seja.

Logo esta decisão depende de a coleta passar a registrar o vazio. A mesma mudança paga a si
mesma: sem arquivo, o skip-if-exists não trava e o poll horário repergunta o vazio até o
kickoff — ~648 chamadas por dia, 8,6% da cota diária, para reconfirmar de hora em hora que a
fonte ainda não publicou.

## Por que declarar o insumo, e não contar NULL na mão

O contador escrito à mão em cada modelo de premissa fica correto no dia em que é escrito e
apodrece na premissa seguinte: quem acrescentar uma premissa nova precisa lembrar de somá-la,
e esquecer é silencioso — o contador segue verde, só que menor do que a verdade. É exatamente
o modo de falha que a ADR 0002 já tratou no mercado órfão.

Então o insumo de cada premissa é **declarado num macro que é a fonte única**, e uma guarda
compara o declarado com as premissas que os modelos realmente produzem. Premissa presente no
modelo e ausente do mapa deixa a guarda vermelha, em vez de nascer muda.

## Alternativas consideradas

- **Fail-closed, igual à 0002.** Rejeitada pelo tamanho: 99,66% do board hoje. A consistência
  seria real, e o produto pararia — e a régua voltaria a ser afrouxada sob pressão, o que é
  pior que nunca tê-la apertado.
- **Score normalizado sobre o que dava para saber** (pontos ganhos ÷ pontos disponíveis).
  Rejeitada por inverter o incentivo: infla a nota justamente onde se sabe menos, que é o
  contrário do que o contador existe para comunicar. E mexeria na escala das faixas (Alta ≥ 60,
  Média 40–59), forçando recalibrar tudo por causa de um diagnóstico.
- **Só consertar o `s_missing`**, que é o que o ticket pedia. Rejeitada porque o contador
  continuaria mentindo, só que sobre outra premissa: `superioridade_xg` (+8) não tem insumo em
  90,5% da Copa do Brasil e 50,3% da Série B — cegueira maior em volume que a de desfalque.
- **Heurística de janela** ("é NULL se o jogo estava a mais de 72h da coleta"). Rejeitada por
  ser o mesmo conhecimento fabricado com outro nome, derivado de 28 fixtures observados, e por
  não economizar chamada nenhuma.

## Consequência conhecida e aceita

Ampliar o horizonte do board para além de 24h aumenta `premissas_sem_dado` por construção: a
lista de desfalque não existe a 7 dias do apito, e a escalação confirmada só aparece a ~40
minutos. O board mais cedo é, necessariamente, o board que sabe menos — e a decisão aqui é que
ele **diga isso**, em vez de exibir um score mais baixo que se parece com evidência contrária.
