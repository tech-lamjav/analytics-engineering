---
status: accepted
---

# A nota é absoluta, e o denominador é medido e congelado

Quando o preço sai da nota, o Score passa a ser só pontos de premissa — e esses pontos vivem
em escalas diferentes em cada `(mercado, lado)`. Hoje o `pts_valor` (0 a 30, idêntico em todos
os mercados) é o que disfarça isso; ele some junto com o edge.

Medido nos onze pares de mercado e lado, com os tetos lidos do código, a nota média vai de
**16** no Resultado fora a **59** no azarão do Handicap — **3,8 vezes**. E a causa não são os
pesos, é a interação: somar cresce reto conforme se adiciona premissa, acender junto cresce
muito mais devagar. O Resultado tem 7 premissas e enche 21% do próprio teto; o azarão do
Handicap tem 3 e enche 59%. **Quanto mais premissa um mercado tem, mais baixa é a nota dele** —
o mercado onde se investiu mais modelagem é o mais punido.

Isso também responde, sem nenhuma teoria sobre qualidade de aposta, a reclamação que originou a
investigação inteira: o Score "nunca passa de 40 ou 50" porque estava sendo dividido por uma
soma que nunca ocorre.

Decidimos duas coisas. A nota é uma medida **absoluta** — quanta evidência acendeu — e nunca
uma posição relativa dentro do lado. E o denominador é o **p95 observado** por `(mercado, lado)`,
medido uma vez sobre uma **janela declarada** e **congelado** em seed versionado. O serviço dele
é fazer o 100 significar a mesma coisa em todos os lados: o topo da escala ancorado no mesmo
quantil.

## Por que absoluta, e não relativa

A alternativa era a nota ser o percentil dentro do lado. Ela entrega o objetivo declarado com
exatidão — uma régua única passaria a significar literalmente "os melhores X% daquele lado",
igual nos cinco mercados. Foi rejeitada por três motivos.

Ela garante volume de publicação independente de qualidade: um lado sem nenhuma linha boa
publica os X% melhores do lixo, e o produto não tem como dizer isso. Ela contradiz a degradação
graciosa, que é a regra que sustenta a honestidade do motor — "a nota fica honestamente mais
baixa" não quer dizer nada quando a nota só fala do grupo de comparação. E ela envenena o funil
da ADR 0006: a rejeição passaria a ser exatamente X% por construção, e a pergunta que o funil
existe para responder — quanto rendeu a faixa que a gente descartou — fica sem sentido.

O preço de escolher absoluta é ter que dizer em voz alta que **os mercados publicam em taxas
diferentes, e isso é consequência, não defeito**.

## Por que medido, e não declarado

A alternativa barata era um teto **estrutural**, função dos pesos — por exemplo a soma dos três
maiores. Sai do código, não precisa de janela, não envelhece, é auditável sem query. Ela erra
nos dois sentidos ao mesmo tempo:

| lado | p95 observado | soma dos 3 maiores pesos | |
| --- | --- | --- | --- |
| Gols Over | 44 | 30 | linhas reais passariam de 100 |
| Handicap favorito | 26 | 30 | teto nunca alcançado |

Para funcionar, o teto declarado teria que ser calibrado lado a lado — que é medir com outro
nome, e sem a janela escrita em lugar nenhum. Perde-se a única vantagem que ele tinha.

## O que esta decisão NÃO compra

**Não iguala a média.** O rescale leva a amplitude de 3,8× para 2,1×, mas o topo não se move: o
azarão do Handicap fica cravado em 59, vinte pontos acima do segundo colocado. Uma régua única
continua sendo réguas diferentes — só que menos diferentes. Quem quiser igualdade de taxa de
publicação está pedindo a alternativa relativa, que foi rejeitada acima.

**Não cria resolução.** O azarão do Handicap e o "Não" do Ambos Marcam têm 3 premissas cada, o
que dá **8 notas possíveis no total**, e uma delas é o próprio teto. Rescalar não separa quem já
está empatado. Isso é granularidade de catálogo e pertence à Limpeza do catálogo, não ao
denominador.

**Não cria sinal.** Nenhuma aposta fica melhor. O ganho é de coerência da régua e de parar de
punir o mercado que tem mais premissa.

## O empate

O empate do 1X2 não tem lado apostado, então nenhuma premissa dispara: teto de premissa zero,
p95 zero, denominador zero. O zero é **explícito antes da divisão**, e não um `SAFE_DIVIDE` — o
`SAFE_DIVIDE` devolveria `NULL`, a comparação com a régua também seria `NULL`, e a linha sairia
sem passar e sem ser marcada. Descarte silencioso é exatamente o que a ADR 0006 proíbe.

## O custo, e a guarda

Número congelado envelhece em silêncio. Toda mexida no catálogo, toda liga nova e toda remoção
como a das premissas de movimento de linha desloca a distribuição, e o denominador continua lá,
certo no dia em que foi medido e cada vez menos certo depois. Por isso a decisão vem com uma
guarda que recalcula o p95 vivo e fica vermelha quando ele se afasta do congelado além de uma
distância declarada.

⚠️ O ponto cego dessa guarda é conhecido e não é nosso: **teste em dbt hoje não alarma**. O job
devolve sucesso com teste vermelho, e o resumo diário não lê o status das guardas. Até a
subtask C4 fechar, esta guarda é uma linha de log num job que retorna sucesso — o que faz desta
decisão uma dependência da [A] na [C] que não estava registrada em lugar nenhum.

E o denominador é medido **depois** da A1, não antes. A A1 tira as premissas de movimento de
linha do Gols: o teto vai de 56/52 para 50/46 e o p95 anda junto. Qualquer p95 medido antes
disso descreve uma escala que não vai existir.
