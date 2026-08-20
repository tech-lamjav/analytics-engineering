---
status: accepted
---

# A medição de escopo roda em dataset próprio, atrás de uma var com default de produção

> ⚠️ **Emenda de 2026-08-19 — a exigência de dataset próprio expira quando (c) entra em produção.**
> A **ADR 0010** decidiu que o pipeline passa a computar a célula `ambos` (`pit_escopo: todas`,
> `pit_recorte: ultimos_10`) por default. A premissa desta ADR — *"medir histórico juntado
> significaria publicar histórico juntado"* — deixa de valer no instante em que publicar histórico
> juntado é a decisão. A partir daí a remedição roda contra `futebol`, sem var, e `futebol_taskF`
> fica como registro congelado do 2×2 da [F].
>
> Nada disto vale **antes** daquele commit: enquanto o default for `da_competicao`/`temporada`,
> tudo abaixo continua em vigor, inclusive a Costura A. No commit que vira o default, a Costura A
> (`tests/assert_taskf_pit_default_igual_baseline`) é **recongelada** — a saída que o cabeçalho
> dela já nomeia.

A task [F] precisa saber o que cada premissa vira quando o PIT do time deixa de ser
contado dentro da competição. Trocar só o `min_jogos` não responde isso: as flags das premissas
saem dos 5 modelos de `intermediate/`, que fazem `ref('int_futebol_team_form_pit')` — e são elas
que decidem em quais jogos a premissa acende. A medição exige, portanto, **re-materializar a
camada de premissas inteira** sob outro escopo de PIT.

Decidimos fazer isso com uma **var** em **todas** as fontes de histórico competição-scoped, cujo
**default reproduz exatamente o comportamento de hoje**, mais um **target `taskF` novo apontando
para o dataset `futebol_taskF`**. É o mesmo padrão que a Task 0 usou para guardar o estado
contaminado em `futebol_task0`.

São seis modelos e nove predicados de join — e desde a #54 os **dois** eixos passam por todos
eles, não só o de escopo:

| modelo | mecanismo | premissas alcançadas |
|---|---|---|
| `int_futebol_team_form_pit` | o join do agregado PIT | as que leem médias/forma dele |
| `int_futebol_premissas_1x2` | spine de xG | `superioridade_xg` |
| `int_futebol_premissas_ou` | spine de xG, `pace_team`, `league_pace_median`, `last5` | `xg_combinado_alto`, `xg_baixo_combinado`, `ritmo_alto`, `historico_over`, `historico_under` |
| `int_futebol_premissas_btts` | `last5` | `historico_btts`, `historico_seco` |
| `int_futebol_premissas_ah` | `margin_stats` | `raramente_perde_por_2`, `favorito_irregular` |
| `int_futebol_premissas_dc` | `team_hist` | `equilibrio_defensivo`, `invicto_recente` |

⚠️ A redação anterior desta ADR enumerava só três mecanismos locais (os `last5` de Gols e de BTTS
e o spine de xG). Era enumeração incompleta, não regra: o Handicap e a Dupla Chance têm histórico
competição-scoped próprio pelos mesmos motivos, e deixá-los de fora produziria célula misturada
dentro do MESMO modelo — `tende_golear` juntado ao lado de `raramente_perde_por_2` não juntado. O
critério de saída é o da ADR 0008: ficam de fora **quatro** premissas, as de tabela. Com a
enumeração antiga ficariam oito.

⚠️ No `league_pace_median`, o eixo alcança o **histórico** de cada time do pool, não o **pool**.
A mediana é o benchmark "a liga em que estou jogando": juntar campeonatos no pool compararia o
ritmo do time contra uma liga que não existe. Os dois lados da comparação — o ritmo do time
avaliado e o de cada time do pool — são medidos sob o mesmo escopo, que é o que a comparação
exige. Isto **não** é a exceção da ADR 0008: `ritmo_alto` não está na lista fechada de quatro
premissas de tabela, e é o histórico dele que muda entre células.

⚠️ O `margin_stats` do Handicap não tem filtro de temporada nem no default: ele já atravessa
season hoje. O eixo de escopo mexe só na dimensão competição, então sob `todas` ele passa a contar
todas as competições e todo o tempo coletado. É achado para a tabela de 39 linhas — estas duas
premissas nunca sofreram o zeramento de virada de temporada que as outras sofrem. E é também o
único site em que o eixo de RECORTE **encolhe** o histórico em vez de alargá-lo: sem filtro de
season para remover, sob `ultimos_10` sobra só o teto de contagem.

## Como o eixo de recorte entra em cada site (#54)

O eixo de recorte é `temporada` (default) ou `ultimos_10`, e ele **não** tem uma forma só:

| forma | sites | o que muda |
|---|---|---|
| filtro de season sai, e só | os dois `last5` (Gols, BTTS) | `last5` já é janela de contagem de 5, e 5 é subconjunto de 10 — o teto não alcança |
| filtro de season sai **e** entra teto de contagem | spine de xG (1X2 e Gols), `pace_team`, `league_pace_median`, `team_hist` (DC), o próprio PIT | são médias sobre tudo o que está no recorte, então o teto muda o denominador |
| só entra o teto | `margin_stats` (Handicap) | não havia filtro de season para remover |

O teto exige um nível a mais de agregação: `QUALIFY` na mesma `SELECT` de um `GROUP BY` filtra
**depois** da agregação, com a média já feita. Por isso cada site com teto tem um CTE de pares
ranqueados, e o FROM/JOIN — que é onde os dois eixos moram — é escrito **uma vez** por site e
renderizado nas duas formas, pela mesma razão que a lista de valores aceitos vive numa macro só.

O **tamanho** do recorte (10) também existe uma vez, em `taskf_eixos()`. Ele **não** é var: um
botão livre de tamanho multiplicaria as células do 2x2 sem que a spec tenha pedido.

⚠️ **Sob recorte de contagem, `min_jogos` vira dois números.** O **usado** (o que alimentou as
médias) satura no tamanho do recorte; o **disponível** (o que existe no escopo) não. O piso de
amostra corta o **disponível**, para significar a mesma coisa nas quatro células — nos pisos
varridos hoje os dois cortam o mesmo conjunto, e isso é medido em
`analyses/taskf_saturacao_recorte.sql`, não assumido. O modelo emite `played_total_disponivel`
**apenas** fora do default, porque sem teto ela seria o próprio `played_total` e emiti-la mudaria
o SQL compilado do caminho que produção usa.

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

A lista de valores aceitos existe **uma vez**, em `macros/taskf_eixos.sql`. Sete cópias dela —
seis modelos mais a `taskf_celula()` — não ficam iguais para sempre, e a divergência seria muda:
um modelo aceitando um valor que outro rejeita mede célula misturada sem levantar nada.

"O primeiro jogo de um time" também passa a ser **relativo à célula**. O guard de look-ahead da
Task 0 (`assert_pit_first_game_has_no_history`) particiona pelo escopo e pelo recorte da célula,
em vez de sempre por (time, competição, temporada). Sem isso ele ficaria vermelho por desenho
fora do default — sob `todas` ele acusa 224 linhas, que **são o mecanismo funcionando**: o
primeiro jogo de Copa do Brasil de um time passa a carregar até 17 partidas de Brasileirão, o de
Sudamericana até 25. Guard vermelho por desenho é guard que se exclui da linha de comando, e aí a
célula roda sem guarda de look-ahead — o defeito que contaminou a medição que a [F] existe para
refazer. A única exclusão que a medição precisa é a Costura A, que é default-only por definição.
