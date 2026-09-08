---
status: accepted
---

# O estádio é preenchido point-in-time, e por coluna, não em bloco

A issue #150 media 1 em cada 3 jogos futuros sem estádio (`venue_id` nulo em `fact_fixtures`) —
não falta de dado, é atraso: a API-Football só manda o local perto do apito, mesmo quando o
mandante já jogou em casa antes na nossa base. Decidimos preencher com o último estádio
conhecido desse mandante, sob duas restrições que só ficaram claras medindo, não supondo.

## Por que point-in-time, mesmo o estádio não sendo insumo de premissa nenhuma

Conferido contra `futebol_insumos_premissa()` (issue #148) antes de escrever qualquer SQL: zero
das 37 premissas leem `venue_id`/`venue_name`/`venue_city`. As colunas com "venue" no nome que
as premissas usam (`s_gf_venue` etc.) são o venue-split de gols — mando/visita — sem relação com
o estádio físico. Ou seja, usar um jogo FUTURO pra preencher um estádio passado não teria o
risco clássico de look-ahead que motiva o "Task 0" na maioria dos outros modelos deste projeto:
nada aqui alimenta o Score.

Mesmo assim, o preenchimento é estritamente point-in-time — `LAST_VALUE(venue_id IGNORE NULLS)
OVER (PARTITION BY home_team_id ORDER BY kickoff_utc NULLS LAST, fixture_id ROWS BETWEEN
UNBOUNDED PRECEDING AND CURRENT ROW)`, nunca olhando pra frente. Não por medo de viés de
medição, mas por **consistência de princípio**: é o mesmo PRINCÍPIO que `int_futebol_team_form_pit`
já aplica em outro lugar — só olhar estritamente pra trás no tempo — e abrir uma exceção "aqui
pode olhar pra frente porque não afeta o Score" cria uma segunda regra pra alguém lembrar, sem
comprar nada. **Não é o mesmo mecanismo**: `team_form_pit` é self-join com `l.kickoff_utc <
a.kickoff_utc` e `ORDER BY ... DESC LIMIT`; aqui é `LAST_VALUE` sobre uma janela, mais barato
porque não precisa cruzar a tabela consigo mesma para uma coluna por vez — mecanismo diferente,
mesmo princípio. O backward-fill já cobre 100% do caso que a issue mede (214/214 jogos futuros,
671/671 no passado).

**NULLS LAST e o desempate por `fixture_id` não são decoração.** `kickoff_utc` e `home_team_id`
não têm `not_null` hoje (medido: zero nulos em 08/09/2026), mas nada os garante para sempre. Sem
`NULLS LAST`, uma fixture de kickoff nulo ordenaria PRIMEIRO (default do BigQuery é NULLS
FIRST dentro de uma janela) e uma linha assim, se tivesse `venue_id` preenchido, "vazaria" esse
estádio pra trás — pra fixtures com kickoff real anterior — exatamente o que este ADR promete
nunca acontecer. Achado numa revisão de código, não na medição original.

## `home_team_id` nulo nunca consome o fallback

Mesmo motivo do ponto acima, achado na mesma revisão. `PARTITION BY home_team_id` agrupa toda
fixture de `home_team_id` NULO numa partição só — se duas fixtures de times DIFERENTES caíssem
nela (hoje não acontece, medido: zero fixtures com `home_team_id` nulo em 08/09/2026), uma
poderia herdar o estádio da outra, sem relação nenhuma entre os times. O `COALESCE` final é
condicionado a `home_team_id IS NOT NULL`: a janela continua sendo calculada sobre a partição
nula (não há como evitar isso e também não precisa — calcular um valor que nunca é usado é
barato), mas esse valor nunca é lido para preencher `venue_id`/`venue_name`/`venue_city` nem
para marcar `venue_inferido`. As duas guardas (`assert_fact_fixtures_venue_cobertura`,
`assert_fact_fixtures_venue_inferido_consistente`) já filtram `home_team_id IS NOT NULL` — com
este fix, esse filtro deixa de ser um ponto cego e passa a refletir exatamente o contrato: uma
fixture sem mandante identificado está fora do escopo desta entrega, por desenho, não por
lacuna de teste.

## Por que o fallback é por coluna, não em bloco

A suposição inicial da spec (#150) era que `venue_id`/`venue_name`/`venue_city` sempre chegam
nulos juntos, vindos do mesmo STRUCT da API. **Falsa.** Medido em produção: RB Bragantino
(`home_team_id` 794) tem fixture com `venue_name` preenchido e `venue_id` nulo na mesma linha.
Se o fallback fosse condicionado a "todos os três nulos", essa linha não seria corrigida — e o
inverso também existe (id preenchido, nome nulo). A implementação aplica `LAST_VALUE(...
IGNORE NULLS)` a cada uma das três colunas independentemente, com `COALESCE(original,
último_conhecido)` por coluna. `venue_inferido` é o OR das três comparações de nulidade, não a
nulidade de uma coluna só — do contrário a flag mentiria sobre metade dos casos reais.

## O risco de campo neutro é medido, pequeno e não filtrável — e não bloqueia

A hipótese de risco que a spec original registrava como "não medido" (BigQuery indisponível na
sessão de grelha) foi medida na sessão de implementação, com BigQuery disponível:

- **6.021** pares de fixtures em casa consecutivas com `venue_id` conhecido nos dois lados.
- **192** trocas de estádio entre um par e o seguinte (3,19%).
- Dessas 192, **56** revertem no jogo seguinte — a assinatura de uma anomalia pontual (um jogo
  isolado com estádio diferente, tipo campo neutro, seguido de volta ao normal). As outras 91
  persistem (mudança real — reforma, relocação) e 28 não têm um terceiro jogo pra classificar.
- As 56 anomalias pontuais **não se concentram em nenhuma competição** — Brasileirão lidera com
  17, uma liga sem rodada de campo neutro nenhuma. Ou seja, não é (só) final de copa: é ruído
  geral do campo `venue` da API, sem sinal na fonte (`sources.yml` declara o STRUCT `venue` como
  só `{id, name, city}`, sem flag de neutralidade) que permita filtrar.

**Decisão: shipar sem filtro, com o risco registrado.** 56 em 6.021 pares (0,93%) é o teto do
tamanho do problema — na pior hipótese, um jogo em casa de verdade herda o estádio errado de uma
anomalia anterior por uma linha, até o próximo jogo em casa corrigir a cadeia. Isso é estritamente
melhor que os **900** jogos que hoje ficam sem estádio nenhum (medido na implementação, universo
maior que a amostra da spec original) — e não é irreversível: quando a próxima fixture em casa
tiver `venue_id` real da API, a cadeia se autocorrige, porque o fallback sempre lê o último
CONHECIDO, nunca um valor congelado.

## O que esta decisão NÃO faz

**Não muda o Score.** Confirmado contra o catálogo de insumos antes de escrever o SQL — é mudança
pura de apresentação em `fact_fixtures`.

**Não filtra jogo de campo neutro.** A fonte não tem sinal pra isso; o risco medido (0,93% dos
pares) foi julgado pequeno demais para justificar heurística nova (ex.: excluir jogos de competições
de mata-mata) que a própria medição mostra não discriminar o problema.

**Não resolve para o time que nunca jogou em casa na nossa base.** Sem fixture anterior conhecida,
`venue_id`/`venue_name`/`venue_city` continuam nulos — não há de onde inferir. Medido na
implementação: 900 dos 10.691 fixtures ficam assim.
