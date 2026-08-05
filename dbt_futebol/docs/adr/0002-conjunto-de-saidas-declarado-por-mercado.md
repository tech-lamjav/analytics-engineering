---
status: accepted
---

# O conjunto de saídas é declarado por mercado, e a comparação é exata

O de-vig normaliza probabilidades sobre o conjunto de saídas de um (fixture, mercado,
linha). Quando esse conjunto está incompleto, a normalização **infla** as probabilidades —
e no limite de uma única saída devolve `prob = 1,0`, certeza absoluta, com `edge = odd − 1`.
Em produção isso significou **403 linhas anunciando valor máximo** com 1,2% de acerto real:
uma odd de 150 aparecia como edge de +14.900%, e no recorte liquidado da Task [0.1] essas
linhas deram **2 vitórias em 172**, ROI de −35,5%.

Decidimos que o tamanho esperado do conjunto passa a ser **declarado por mercado**, num
macro que é a fonte única, e que a comparação com o conjunto observado é **exata**.
Conjunto que não bate não produz uma estimativa pior — produz **nenhuma**: prob justa,
booksum, edge, pontos de valor e fonte de valor viram nulos, e a linha sai da base de valor
preservando a contagem real de saídas como diagnóstico. Mercado não declarado não emite
(fail-closed).

## Por que exata, e não "pelo menos duas saídas"

É o que o ticket de origem pedia, e hoje resolveria exatamente as mesmas 403 linhas. Foi
rejeitada porque deixa aberto o caso mais perigoso: **um 1X2 com duas das três saídas**.
Ali o booksum fica em ~0,66, as probabilidades saem infladas em ~1,5×, o edge é falso — e
**não há prob de 1,0 para denunciar**. É o mesmo bug, um mercado ao lado, e mais difícil de
enxergar justamente porque o sintoma gritante desaparece. Não ocorre hoje; o código não
impede que ocorra. Só a comparação exata cobre a família inteira em vez do caso extremo.

O custo dessa escolha é um ponto cego próprio: se um rótulo novo fizer o conjunto real de
um mercado declarado crescer, a comparação exata faz o mercado **parar de emitir em
silêncio**. Por isso a decisão vem acompanhada de uma guarda que compara o declarado com o
**máximo observado** por mercado, e não apenas com a presença do mercado no mapa.

## Por que na projeção final, e não dentro de cada fonte

A regra é escrita **uma única vez**, sobre a coluna que já consolida as três fontes de
valor (Pinnacle, Dupla Chance derivada e consenso). Assim as três são cobertas pela mesma
linha de código, e — o que mais importa — **a Pinnacle ganha uma guarda que nunca teve**.
Hoje ela não produz nenhuma linha degenerada, mas isso é o estado da coleta, não uma
propriedade do código: o mesmo bug reaparecendo pela Pinnacle viria carimbado como
benchmark `sharp`, o mais confiável de todos.

## Por que o booksum é teste e não filtro

O booksum abaixo de 1 é a invariante estrutural do problema — conjunto incompleto derruba a
soma por construção — e sozinho pegaria os dois casos sem mapa nenhum para manter. Mas tem
falso positivo possível: **arbitragem real de mediana entre casas** produz booksum abaixo
de 1 com conjunto completo, e como filtro isso descartaria uma linha boa em silêncio. Como
teste, o mesmo evento vira pergunta em vez de descarte. Zero ocorrências na base atual.

O teste existia desde o primeiro dia, como aviso, e estava vermelho o tempo todo — com
correspondência perfeita: `booksum < 1` ⟺ conjunto de 1 saída ⟺ `prob = 1,0`, em 403 de 403
linhas, zero falso positivo. **O bug era detectável desde sempre.** O que faltava era o
aviso significar alguma coisa: guarda permanentemente vermelha morre ignorada. Por isso o
booksum das linhas rejeitadas vira nulo junto com o resto — sem isso, promovê-lo a erro o
manteria vermelho para sempre e reproduziria o mesmo destino.

## Alternativas consideradas

- **Filtrar as linhas fora da tabela.** Rejeitada: mudaria o grão e apagaria o diagnóstico.
  A contagem real de saídas na linha rejeitada é o que permite auditar rejeições sem
  re-derivar tudo das odds cruas — e é o que torna a guarda principal **falsificável**, em
  vez de verde por não haver o que testar.
- **Corrigir só o consenso, que é onde o bug aparece.** Rejeitada: trata o sintoma no lugar
  onde ele calhou de surgir, e deixa a Pinnacle e a DC derivada sem guarda nenhuma.
- **Uma tabela de constantes por liga/mercado fora do código.** Rejeitada por ora: o mapa
  tem seis entradas e muda quando a API muda, não quando a operação muda.

## Consequência conhecida e aceita

A entrada da **Dupla Chance** declara 3, e isso é uma coincidência numérica perigosa: a DC
tem 3 saídas, mas o número declarado se refere ao **conjunto 1X2 de origem**, do qual a
probabilidade é derivada. São coisas diferentes que calham de ser iguais, e o macro carrega
comentário explícito para que ninguém "conserte" a coincidência.
