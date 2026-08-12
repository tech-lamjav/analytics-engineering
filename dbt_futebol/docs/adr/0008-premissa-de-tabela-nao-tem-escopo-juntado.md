---
status: accepted
---

# Premissa de tabela não tem escopo juntado

Quatro premissas do catálogo leem a **classificação** do time, não a performance dele:
`superioridade_tabela` (1X2), `supremacia` e `sem_rodizio` (Handicap) e
`x_superioridade_tabela` (Dupla Chance, reusada do 1X2). Os insumos são `rank`, `ppg` e — no
caso do `sem_rodizio` — `n_teams`, o tamanho da liga.

Decidimos que essas quatro **permanecem competição-scoped em todas as células de medição**, e
que essa imobilidade é o resultado reportado, não uma lacuna a preencher.

## Por quê

Classificação existe dentro de uma competição. Não há posição de um time num PIT de escopo juntado,
porque não há tabela juntada: `rank` exige o conjunto completo de adversários no mesmo recorte,
e `sem_rodizio` compara o rank contra o tamanho da liga (`s_rank <= 6 OR s_rank >= n_teams - 3`)
— um número que simplesmente não existe quando o PIT atravessa competições de tamanhos
diferentes.

Consequência prática: nas quatro células, o número dessas premissas é **idêntico por
construção**. A linha delas na tabela do entregável não é um resultado nulo; é a resposta da
coluna 3 ("dá para juntar, e o que impede se não der").

## Considered options

**Competição principal.** Cada time ganharia uma liga de referência (a nacional), e a tabela
sairia sempre de lá, mesmo num jogo de copa. É a alternativa séria, e não foi descartada por ser
ruim: foi adiada. Ela **muda a definição da premissa** — `supremacia` passaria a comparar
posições de uma competição que não é a do jogo — e a [F] é uma task de medição, com instrução
explícita de não mexer em premissa. Fica registrada como candidata para a [B], onde o
`sem_rodizio` merece atenção por ser do Handicap, o mercado com ROI positivo.

**Proxy sem tabela** (percentil de `ppg` entre todos os times da base). Rejeitada pelo mesmo
motivo, com o agravante de que o percentil mistura ligas de níveis diferentes sem nada que
sinalize isso no número.

## Consequences

O `min_jogos` **continua seguindo a célula**, inclusive nas linhas dessas quatro premissas. O
piso de amostra é propriedade do jogo, não da premissa — um jogo com PIT juntado suficiente
é o mesmo jogo, independentemente de qual premissa está sendo avaliada nele.
