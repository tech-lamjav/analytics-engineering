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
>
> ⚠️ **RECONGELAR NÃO BASTOU, e esta emenda estava incompleta** — ver a emenda de 2026-08-26 no
> fim deste arquivo. Virar o default para `todas` mudou o FECHO da conta do PIT, e a partição da
> impressão digital da Costura A continuou sendo `(competition_id, season)`. O recongelamento de
> 25/08 deixou a guarda verde por algumas horas; em 26/08 ela estava vermelha de novo, sobre
> movimento legítimo.

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

---

## Emenda de 2026-08-26 — a partição da impressão digital é o FECHO da computação, e a #91 mudou o fecho

A Costura A (`tests/assert_taskf_pit_default_igual_baseline`) compara só as partições cujo
**insumo** está idêntico ao do congelamento, e particiona esse insumo por `(competition_id,
season)`. O `taskf_fingerprint_insumo_pit` declara a premissa que sustenta esse recorte:

> O recorte por (competition_id, season) é sólido porque **no caminho DEFAULT** a linha de uma
> âncora em (C,S) é função só dos fixtures de (C,S) e das standings de (C,S) […] **Sob
> `pit_escopo=todas` isso deixa de valer** — e é aí que a guarda deve mesmo falhar, porque a var
> saiu do default.

**A #91 tornou `todas` o default.** A premissa foi falsificada pela própria mudança que a emenda
de 19/08 acima anuncia, e nem aquela emenda nem o recongelamento de 25/08 recalcularam o recorte.
O resultado é uma guarda que acende sobre movimento legítimo e ficaria vermelha para sempre — o
destino que este repositório documenta em todo lugar como "guarda permanentemente vermelha morre
ignorada", só que na versão lenta.

**Medido em 26/08:** o Brasileirão 2026 **casou** na digital (380 fixtures, `fp_fixtures` byte a
byte igual ao baseline) e ainda assim divergiu em **60 linhas**. Os **20** times dele também jogam
em Libertadores (13/2026) e Copa do Brasil (73/2026), duas das seis partições que se moveram. Sob
`todas`, a linha de um jogo do Brasileirão lê o histórico do time em **toda** competição — então
ela se move com a digital da própria competição intacta.

### A regra que fica

**A partição de uma impressão digital de insumo tem de ser o FECHO da computação que ela protege.**
Partição mais grossa que o fecho não fica frouxa — fica **mentirosa**: ela declara comparáveis
linhas cujo insumo mudou fora do recorte, e a guarda passa a acusar defeito onde há
comportamento. E o inverso também vale: mudar o fecho sem recalcular a partição é uma quebra
**muda**, porque o sintoma aparece dias depois e se parece com deriva de dados.

Toda mudança de eixo — de escopo, de recorte, de fonte — é candidata a mudar o fecho, e a
pergunta *"isto muda de que a linha depende?"* passa a ser parte do checklist de quem a faz.

### O recorte novo: por LINHA

Sob `todas`, a linha em (fixture F de C/S, time T) é função de **(a)** os fixtures de T com
`kickoff < kickoff(F)`, em toda competição, e **(b)** as standings correntes de (C,S). O fecho é,
portanto, **a própria linha** — e o baseline ganha uma coluna `fp_insumo_linha` gravada no
congelamento, que a guarda recomputa e compara.

As três alternativas foram medidas sobre o baseline de 21.078 linhas, e não estimadas:

| recorte | cobertura em 26/08 | trajetória |
|---|---|---|
| por `(competition_id, season)` — o de hoje | 88,1% | **mentirosa**: inclui as linhas que não deveriam ser comparáveis |
| por **time** (digital do histórico global de T) | 57,1% | **erode até zero** |
| por **linha** (o fecho exato) | **68,2%** — 14.366 linhas, 25 de 37 partições | **não erode; cresce** |

⚠️ **Por que "por time" é a armadilha, e não a resposta óbvia.** Ela *parece* o fecho, mas
digitaliza o histórico inteiro do time — **incluindo jogos posteriores à linha**, que a linha não
lê. O Palmeiras jogar amanhã invalidaria a linha dele de 2024. O fecho exato é per-linha porque a
conta é per-linha, e é exatamente isso que o torna estável: o passado de uma linha de 2024 não se
move quando um jogo de 2026 acontece. A cobertura por linha **sobe** com o tempo, porque temporada
encerrada fica encerrada.

### O que a emenda NÃO muda

**O piso de cobertura fica em 0,5** (`taskf_cobertura_minima`) e ganha sentido novo. Ele existia
para pegar a erosão estrutural de um recorte que encolhia sozinho; sob o recorte por linha a
cobertura não encolhe por conta própria, então ele passa a ser guarda de **vacuidade**: se cair, é
porque o passado está sendo reescrito em massa — achado, não desgaste. Recalibrá-lo agora seria
calibrar contra uma trajetória que ninguém mediu.

**A guarda continua em `tag:taskf`, fora do agendado.** Ela cobre o caminho que produção serve,
o que é argumento para promovê-la — mas o precedente da **#33** manda o contrário: guarda com
baseline permanente não entra na tag. Baseline permanente precisa de curadoria humana, e guarda
que precisa de curadoria dentro do agendado vira ruído no resumo diário. O que ela ganha em troca
é voltar a ficar **verde**, que é a condição para alguém olhar para ela de novo.

**A guarda não se aposenta.** Desde a #91 o default É o caminho de produção, então a pergunta
"a saída do default mudou sozinha?" vale mais agora do que quando a guarda foi escrita.

### O recongelamento é obrigatório, e no mesmo commit

`fp_insumo_linha` não existe no baseline de hoje. Mudar o que entra no `FARM_FINGERPRINT` sem
recongelar faz **nenhuma** partição casar — e aí a guarda não fica vermelha, fica **VAZIA**, que
é pior. O `taskf_fingerprint_insumo_pit` já escreve essa regra; a #91 já pagou o preço de não a
seguir. O recongelamento sai de **produção** (`--target prod`), nunca do `futebol_taskF`: congelar
do dataset de medição carimbaria o baseline com fatos parados — a lição da seção #82 do
`docs/TASKF_RESULTADOS.md`.

E o reparo **não invalida a âncora da remedição (#82)**: o `fp_insumo_pit` não é lido por nenhum
modelo de premissa, nem pelo `task01_base`, nem pelo de-vig. Ele não está na lista de "o que
invalida esta âncora", e por isso este trabalho entra **antes** da remedição sem forçar
re-medição.

### As duas falsificações

1. **a de sempre** — célula fora do default deixa a guarda vermelha por desenho
   (`--vars '{pit_escopo: da_competicao, pit_recorte: temporada}'`);
2. **a nova, e é ela que prova o reparo** — rodar a guarda com o recorte novo **sem** recongelar
   o baseline tem de dar **vazia**, nenhuma linha casando. Ver a falha acontecer de propósito é o
   que impede alguém de produzi-la por acidente depois.
