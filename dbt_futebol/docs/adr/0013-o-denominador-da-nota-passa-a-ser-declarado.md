---
status: accepted
---

# O denominador da nota passa a ser declarado, não medido

A ADR 0005 congelou o denominador da `score_normalizado` como o p95 **observado** da nota
de contexto por (mercado, lado), medido uma vez sobre uma janela declarada. A régua ficou
certa no dia em que foi medida, mas o `PPP#365` (aberta pelo Victor, cc @MateusKasuya) achou
o efeito colateral dela: uma nota **100** convive na tela com o aviso "não atingiu o corte",
e cem é lido como "completo". Nas linhas de Handicap do board, 16,7% batiam no teto — não
porque a evidência fosse máxima, mas porque o p95 é um quantil e ~5% de cada lado o supera
por construção, e o Handicap concentrava mais desses casos que os outros mercados.

## A decisão

O denominador passa a ser o **teto de pontos do catálogo**: a soma dos pesos máximos de
TODAS as premissas do lado, lida à mão dos cinco modelos `int_futebol_premissas_*.sql` e
conferida contra eles — não medida sobre janela nenhuma. Congelado no seed
`futebol_teto_nota_contexto`, no lugar de `futebol_p95_nota_contexto`. Os cortes de faixa
(30/60) **não mudam** — é decisão separada do Victor, de significado e não de volume (ver
"O que isto NÃO decide" abaixo).

A aritmética da `futebol_score_normalizado()` não muda: continua
`LEAST(100, ROUND(nota_contexto / <denominador> × 100))`, com os mesmos dois ramos
explícitos (nota NULL, denominador zero/ausente). Só a origem do número que entra no lugar
de `<denominador>` muda.

## Por que isto não contradiz a ADR 0005

A ADR 0005 rejeitou "um teto estrutural, função dos pesos" citando um exemplo específico: a
soma dos **três maiores** pesos. Essa forma errava nos dois sentidos — Gols Over tinha p95
44 contra um top-3 de 30 (linhas reais passariam de 100) e o Handicap favorito tinha p95 26
contra um top-3 de 30 (o teto nunca seria alcançado). A conclusão de 2026-08-06 foi que
"para funcionar, o teto declarado teria que ser calibrado lado a lado — que é medir com
outro nome".

O que a PPP#365 propõe não é essa forma. É a soma de **TODOS** os pesos do lado — o número
que já vinha sendo calculado e conferido contra o código desde a própria medição do A6
(coluna `teto_catalogo` de `analyses/taskA_a6_p95.sql`), só que nunca tinha sido usado como
denominador vivo. A diferença importa: a soma de todos os pesos não precisa de calibração
porque ela não é uma aproximação do que a nota alcança — é o limite matemático dela. Uma
linha NUNCA soma mais pontos do que a soma de todas as suas premissas, por construção do
próprio catálogo. Já a soma dos três maiores é uma estimativa de "quanto normalmente
acontece", e é aí que ela precisa de calibração e erra.

Medido na PPP#365 (script `analyses/taskA_ppp365_denominador_teto.sql`, board publicado +
funil inteiro, 04/09): a proporção de linhas em nota 100 cai de 9,2% para 4,1% no board, e a
média de 41,1 para 33,5. Não é surpresa nem regressão — é exatamente o efeito esperado de um
denominador maior (o teto do catálogo é sempre ≥ o p95 observado, por definição de quantil).
Alguns lados nem mudam: onde o p95 já ERA o teto (Azarão do Handicap, "Não" do Ambos
Marcam — os mesmos que a ADR 0005 já registrava como "os que não criam resolução"), a troca
não move nada.

## O que isto NÃO decide

**Não muda os cortes de faixa.** 30/60 seguem os mesmos que a decisão de produto de 01/09
fixou (ver ADR e comentário de `analytics-engineering#109`), por decisão explícita do
Victor em 04/09: "os cortes ficam em 30/60, e o motivo é de significado, não de volume — no
denominador novo os cortes ganham leitura literal (60 é mais da metade da evidência que
aquele mercado pode dar)". A PPP#365 tinha proposto 24/47 como alternativa que preservaria a
MESMA proporção Alta/Média/Baixa de hoje; o Victor preferiu a régua que se explica sozinha à
que reproduz a distribuição de ontem.

**Não reancora em ROI.** A régua 30/60 (como a anterior) não foi calibrada contra retorno —
foi a #107 que mediu que nenhum par da grade discrimina ROI, e a escolha de onde cortar é de
significado. Reancorar em ROI pede o volume que só o funil, sob o gate novo, vai acumular em
semanas (ver o pedido do Victor na própria PPP#365).

**Não traz guarda de deriva estrutural para o teto.** O `futebol_teto_nota_contexto` pode
ficar desalinhado do catálogo real se alguém mudar peso de premissa sem atualizar o seed no
mesmo PR — e nada detecta isso automaticamente hoje. Ficou fora do escopo desta entrega
(que a PPP#365 pediu como "só a troca do denominador"); quem quiser fechar esse buraco
precisa de uma checagem que introspeccione os cinco modelos de premissa, o que é trabalho
à parte.

## O que acontece com o p95

O seed `futebol_p95_nota_contexto` e a guarda `assert_p95_nota_contexto_nao_derivou`
continuam no repositório. Não é dead code por acidente: é registro de como o denominador
era medido antes desta ADR, e duas análises históricas (`taskA_a4_fronteiras.sql`,
`taskA_a4_reconciliacao.sql`) ainda o leem para reproduzir medições passadas. A guarda
perdeu `tag:guarda` e virou `severity='warn'` — não vigia mais nada que decida a nota
publicada, e rodá-la como guarda de produção pagaria custo de BigQuery por um número que
não decide mais nada.

## Consequência sobre o funil

Igual à virada #109/A6: o `fact_value_funnel` é append-only e congelado no apito (ADR
0011). Candidato já escrito antes deste deploy mantém `score_normalizado` calculado sob o
p95 antigo, para sempre — não há reescrita de histórico. Só candidato escrito a partir
deste deploy usa o teto do catálogo. Isso é o mesmo padrão que a A1 (#103) e a A6 (#105) já
estabeleceram para mudança de escala da nota, e é por isso que este PR não precisou de um
`score_versao` novo: o funil já não promete comparabilidade histórica ponto a ponto da
`score_normalizado` — quem precisa dela comparável recompõe pelo código de hoje, como as
próprias análises taskA fazem.
