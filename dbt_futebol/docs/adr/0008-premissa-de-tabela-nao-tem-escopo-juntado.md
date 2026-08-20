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

⚠️ **Emenda de 2026-08-19 — "adiada para a [B]" não faz da [B] pré-requisito de nada.** Ler o
parágrafo acima como se a [B] precisasse decidir *antes* de o escopo ser juntado em produção cria
uma circularidade: parte de (c) esperando a task que (c) bloqueia. A **ADR 0010** cortou isso, e o
corte é uma releitura desta ADR, não uma exceção a ela. Como esta ADR já decidiu que as quatro
**permanecem competição-scoped** — *"essa imobilidade é o resultado reportado"* —, o pipeline
juntado sobe **sem tocar nelas**, e a remedição entrega para as três medidas evidência sob
`da_competicao`, por construção. A [B] as julga nessa evidência, como julga as outras 36. A
"competição principal" é, portanto, um **resultado candidato da [B]** — que muda a definição da
premissa e exige medição própria depois —, nunca um insumo dela.

## Consequences

O `min_jogos` **continua seguindo a célula**, inclusive nas linhas dessas quatro premissas. O
piso de amostra é propriedade do jogo, não da premissa — um jogo com PIT juntado suficiente
é o mesmo jogo, independentemente de qual premissa está sendo avaliada nele.

⚠️ **Consequência disso, e a leitura exata de "idêntico por construção": a igualdade entre células
é no PISO 0.** Nos pisos maiores as três premissas de tabela do catálogo medido mudam de número,
porque o piso corta um conjunto diferente de jogos — e isso é o parágrafo acima em ação, não uma
falha da decisão. Medido entre `base` e `escopo` (#53, `docs/TASKF_RESULTADOS.md`): `n_p0`
idêntico nas três (98, 301, 188), enquanto no piso 5 `superioridade_tabela` vai de 35 para 47 e
`supremacia` de 95 para 121. `sem_rodizio` fica em 188 nos quatro pisos das duas células — ela só
acende em jogo que já tem histórico longo.

A quarta premissa que esta ADR nomeia, `x_superioridade_tabela`, **não é uma das 39 medidas**: é
coluna interna do `int_futebol_premissas_1x2` que a Dupla Chance reusa dentro do
`lado_coberto_forte`, o qual também lê `forca_mismatch` e portanto segue o eixo. Quem for conferir
a ADR na tabela do entregável procura três linhas, não quatro.

Desde a #55 essa conferência não é manual: `tests/assert_taskf_premissas_de_tabela_identicas.sql`
cobra as três, no piso 0, no grão (mercado, premissa, benchmark) — com as duas leituras acima
escritas no cabeçalho e com guarda de não-vacuidade, para "idêntico" nunca significar "não havia o
que comparar". Roda com `dbt test --target taskF --select tag:costura_b`, depois das quatro
células.
