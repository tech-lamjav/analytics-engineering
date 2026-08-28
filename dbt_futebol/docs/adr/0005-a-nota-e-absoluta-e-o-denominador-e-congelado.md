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

## Emenda (2026-08-26, #105): o denominador medido

A decisão acima foi tomada com números de ILUSTRAÇÃO, medidos antes da A1 e sobre a soma de
pesos. A medição que congelou o seed rodou depois — `analyses/taskA_a6_p95.sql`, sobre os
candidatos do funil (uma janela por candidato), com as premissas **recomputadas** nos cinco
mercados e a nota de contexto pós-A1 como quantidade medida. Janela de kickoff 16/06 a 31/08
de 2026, medida em 26/08.

| mercado | lado | p95 | teto do catálogo | candidatos |
| --- | --- | ---: | ---: | ---: |
| Resultado | Home | 33 | 51 | 476 |
| Resultado | Away | 22 | 47 | 476 |
| Resultado | Draw | **0** | 0 | 476 |
| Gols | Over | 44 | 50 | 9.854 |
| Gols | Under | 36 | 46 | 9.405 |
| Handicap | Favorito | 24 | 40 | 8.744 |
| Handicap | Azarão | **30** | 30 | 8.608 |
| Handicap | Pick | **0** | 0 | 952 |
| Ambos Marcam | Sim | 28 | 34 | 476 |
| Ambos Marcam | Não | **28** | 28 | 476 |
| Dupla Chance | único | 28 | 34 | 952 |

O que a medição confirmou e o que ela corrigiu:

**Os dois lados que saturam são os previstos.** O azarão do Handicap e o "Não" do Ambos
Marcam têm p95 igual ao próprio teto — os dois com três premissas cada. É o mesmo fato que
a decisão nomeia como "não cria resolução", agora medido.

**O `Pick` do Handicap entrou junto com o empate.** A decisão só nomeia o empate do 1X2
porque foi o caso que apareceu na medição de origem. O handicap de linha zero tem a mesma
estrutura — nenhuma premissa se aplica, porque todas são `is_favorito AND ...` ou
`is_azarao AND ...` — e são 952 candidatos reais, não um caso de canto. Entra no seed com o
mesmo zero explícito, e o `CASE` do modelo não distingue os dois.

**A amplitude cai mais do que a decisão previa, e o topo se move.** Sobre os nove lados com
lado apostado, a média em fração do próprio teto ia de 16,5% (Resultado fora) a 49,7%
(azarão do Handicap) — **3,0×**. Depois da normalização pelo p95, de 33,2 a 49,7 — **1,5×**,
e não os 2,1× projetados. O azarão do Handicap continua em primeiro, mas cravado em 49,7 e
quatro pontos acima do segundo (a Dupla Chance, 45,6), não vinte. A conclusão qualitativa da
decisão não muda — uma régua única continua sendo réguas diferentes —, mas o número dela sim,
e o certo é o medido.

**A recomputação é fiel ao registro.** Sobre exatamente as mesmas linhas do funil escritas
depois da A1, a nota recomputada e a nota registrada divergem em **zero** de 6.713 linhas de
Handicap e Gols. É o que autoriza a rota da recomputação sem que ela vire uma escala
paralela — e não elimina o limite conhecido da #78, que é sobre builds diferentes.

**A tolerância de 20% da guarda não é frouxa.** Recalculando o p95 sobre uma janela rolante
de 30 dias de verdade, os onze lados batem com o congelado; o maior desvio é o "Sim" do
Ambos Marcam, com 26 contra 28 — 7%.

⚠️ E uma cegueira nova, que a medição descobriu e a guarda declara: no dia do deploy as
únicas linhas com nota de contexto preenchida são as de jogo ainda por vir, porque o
append-only não reescreve o passado. A amostra viva nasce com seis dias de rodada, não com
trinta, e nela o favorito do Handicap dava p95 30 contra os 24 da janela inteira — 25% de
distância, guarda vermelha, e nada de errado com o denominador. Por isso a metade da DERIVA
só passa a cobrar quando a janela está cheia até o fundo: **ela fica dormente por ~30 dias
depois do deploy**. A metade da COBERTURA — o lado que existe e não tem denominador — morde
desde o primeiro build.
