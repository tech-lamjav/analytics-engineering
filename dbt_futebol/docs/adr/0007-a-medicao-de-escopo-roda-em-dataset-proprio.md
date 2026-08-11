---
status: accepted
---

# A medição de escopo roda em dataset próprio, atrás de uma var com default de produção

A task [F] precisa saber o que cada premissa vira quando o PIT do time deixa de ser
contado dentro da competição. Trocar só o `min_jogos` não responde isso: as flags das premissas
saem dos 5 modelos de `intermediate/`, que fazem `ref('int_futebol_team_form_pit')` — e são elas
que decidem em quais jogos a premissa acende. A medição exige, portanto, **re-materializar a
camada de premissas inteira** sob outro escopo de PIT.

Decidimos fazer isso com uma **var** nas fontes do PIT que são competição-scoped
(`int_futebol_team_form_pit`, os `last5` locais de Gols e BTTS, o spine de xG), cujo **default
reproduz exatamente o comportamento de hoje**, mais um **target `taskF` novo apontando para o
dataset `futebol_taskF`**. É o mesmo padrão que a Task 0 usou para guardar o estado contaminado
em `futebol_task0`.

## Por que isto não é opcional

No `profiles.yml`, `dev` **e** `prod` apontam para o mesmo dataset `futebol`, e `target: dev` é
o default. Um `dbt run` sem `--target` escreve em produção. Sem um destino próprio, medir
histórico juntado significa publicar histórico juntado no board — e o próximo run agendado
reverteria por cima, deixando um intervalo em que o app serviu número de outra definição.

Isto é um **dataset de medição**, análogo ao `futebol_task0`, e não um dataset por pessoa —
proposta diferente, e recusada.

## Considered options

**Copiar os 5 modelos para versões de medição.** Rejeitada: são ~1000 linhas de premissa que
passam a existir em duas cópias, e a cópia deriva da produção no primeiro commit seguinte. O
modo de falha é silencioso — a medição continua rodando, medindo um catálogo que já não é o de
produção.

**Editar os modelos, medir e reverter.** Rejeitada: não deixa rastro reproduzível. Quem
quiser refazer a medição daqui a três meses não tem como saber o que exatamente foi editado.

## Consequences

Fica uma var no código de produção que **produção nunca usa**. Um leitor futuro vai encontrá-la
e não vai saber se pode remover. Por isso a var vem acompanhada de um teste que compara a saída
com default contra a tabela publicada: enquanto ele passar, "o default preserva o comportamento"
é fato verificado, e não promessa no comentário.
