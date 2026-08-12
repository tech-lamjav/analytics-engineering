# Task [F] — Resultados

Documento vivo. Cada ticket da [issue #49](https://github.com/tech-lamjav/analytics-engineering/issues/49)
acrescenta a sua seção aqui. O SQL que produz cada número está em `dbt_futebol/analyses/`.

Os resultados moram neste arquivo, e não no cabeçalho das análises, para que o SQL mude quando a
lógica muda e não quando os números mudam. Mesmo padrão do `TASK01_RESULTADOS.md`.

---

## Ticket #51 — Célula `base` ponta a ponta

`analyses/taskf_teste2.sql` + `analyses/taskf_reconciliacao_01.sql` · execução 2026-08-12 13:34
UTC · commit `fa98ceb` · dataset `futebol_taskF`

A célula que não muda nada — escopo na competição do jogo, recorte na temporada corrente — vai
ponta a ponta: camada de premissas materializada no dataset de medição, Teste 2 rodando por cima,
saída com coluna de célula, e comparação contra o Teste 2 publicado da [0.1]. É o tracer bullet: o
caso em que a resposta já é conhecida, para o caminho inteiro ser exercitado antes de as células
que mudam alguma coisa terem o direito de significar algo.

### Veredito

**38 das 39 premissas reproduzem o publicado EXATAMENTE**, em todos os campos comparáveis — até
11 campos por premissa nas 15 de varredura completa. A única divergência é `linha_descendo`, com
2 linhas de 405 e ≤ 0,2 pp.

O caminho está certo. As células `escopo`, `recorte` e `ambos` podem ser medidas.

### O universo congelado não é um corte por dia

`analyses/taskf_universo_congelado.sql`

| variante | período | jogos | vs publicado |
|---|---|---|---|
| `A_sem_corte` — o que a [0.1] rodou | 16/06 → 12/08 | 228 | +59 |
| `B_ate_0408_por_dia` — `DATE(kickoff) <= '2026-08-04'` | 16/06 → 04/08 | **178** | **+9** |
| `C_universo_congelado` — `kickoff < 04/08 12:00 UTC` | 16/06 → 04/08 | **169** | **0** |
| `D_teto_alternativo` — o mesmo com teto às 06:00 UTC | 16/06 → 04/08 | 169 | 0 |

O corte ingênuo por dia devolve 178, não 169. Os 9 excedentes são exatamente os jogos de 04/08
com kickoff a partir das 16:00 UTC — 8 da Champions e o da Copa do Brasil das 22:30. No dia
inteiro **um único** jogo começou antes disso, o das 00:00 UTC, e ele está nos 169.

A explicação é que a [0.1] **rodou sem corte congelado**: o teto dela é o instante em que a query
executou, e o `janela_fim = 04/08` publicado é só o `MAX(DATE(kickoff))` que saiu daquilo. Os
nove jogos da noite ainda não tinham sido disputados. Reproduzir a janela publicada exige,
portanto, um **instante**, e não uma data.

O teto ficou às 12:00 UTC, no meio do vão vazio: entre o fim do jogo das 00:00 (~02:00) e o
kickoff das 16:00 não existe jogo nenhum na base. A variante D mede a outra ponta da faixa e dá o
mesmo resultado — o corte é **robusto a catorze horas de incerteza**, e não um valor calibrado até
o número bater. As duas datas publicadas continuam verdadeiras: o último jogo incluído é mesmo de
04/08.

O piso de 16/06 é no-op — a coleta de odds é forward-only e começou nesse dia, então A e B já
devolvem `janela_ini = 16/06` sozinhos. Fica declarado assim mesmo, para a janela não depender de
um efeito colateral da coleta.

**Composição dos 169:** copa_mundo 79 (46,7%), serie_b 39 (23,1%), brasileirao 28 (16,6%),
sudamericana 15 (8,9%), copa_do_brasil 8 (4,7%). Os 46,7% da Copa do Mundo batem com os "47% da
amostra" que a spec #49 atribui a ela, e Copa do Brasil + Sudamericana somam 23, contra os "cerca
de 24 jogos" que a spec estima que o merge recupera.

⚠️ **A Champions não tem UM jogo no universo primário.** Os únicos jogos dela na janela são os 8
de 04/08 à noite, e o corte os remove. A pergunta da spec sobre a fase classificatória da
Champions (user story 24) não tem amostra nenhuma no universo congelado — quem for executar a
#58 precisa saber disso antes de desenhar a resposta, porque ela terá de sair do universo
estendido ou de lugar nenhum.

### A tolerância, declarada

> **Tolerância: 0,5 pp de diferença absoluta, em qualquer piso, e SÓ para `linha_subindo` e
> `linha_descendo`.**

Ela vale para essas duas e para mais nenhuma. As outras 37 premissas leem fixture, estatística ou
tabela — insumos determinísticos sobre um universo congelado — e para elas a régua é **igualdade
exata**. `linha_subindo` e `linha_descendo` são as únicas que comparam preço com preço: acendem
quando a média das probabilidades implícitas de todas as casas sobe de t24h para t15m.

O valor 0,5 pp foi declarado **antes** de medir, calibrado pelo que o repositório já sabia:
`docs/TASK01_RESULTADOS.md` registra que o mercado de Gols anda 0,2–0,4 pp entre execuções sem
que nada mude, e que isso já produziu caça a bug inexistente.

### ⚠️ A justificativa da tolerância não se aplica a uma janela congelada

Este é o achado do ticket que ninguém tinha escrito.

A tolerância existe porque "`linha_subindo`/`linha_descendo` leem odds ao vivo e viram sozinhas
entre builds". Isso é **verdade no board vivo e falso num universo congelado do passado**: a
coleta de odds é forward-only e para no apito. Medido — para os 169 jogos congelados há **zero
capturas com data posterior a 04/08** em qualquer das três janelas de fechamento:

| janela de coleta | linhas | jogos | última coleta | coletadas após 04/08 |
|---|---|---|---|---|
| t15m | 34.691 | 157 | 02/08 | **0** |
| t1h | 37.135 | 168 | 02/08 | **0** |
| t24h | 34.854 | 162 | 03/08 | **0** |

O insumo de `linha_caiu` é imóvel. Logo a tolerância continua valendo como **régua declarada** —
foi anunciada antes da medição e a única linha que a usou passou nela —, mas ela **não explica**
a divergência que encontrou. Passar na régua e ter causa conhecida são coisas diferentes, e a
diferença está registrada aqui em vez de fechada por conveniência.

### A correção da spec #22 tem footprint ZERO — medido, não suposto

A spec #22 corrigiu o de-vig em **05/08**, um dia *depois* de a [0.1] publicar. Os números
publicados ainda continham as linhas de conjunto de saídas incompleto; os medidos já não contêm.
Era a divergência de outra origem mais provável do ticket, e a hipótese de partida era que ela
atingiria o BTTS, cujo benchmark preferido é justamente o consenso.

**Ela não atinge nada.** Duas medições:

| mercado | linhas na janela | conjunto incompleto | destas, com preço Pinnacle |
|---|---|---|---|
| 1X2 (1) | 507 | **0** | — |
| Handicap (4) | 6.624 | 58 | **0** |
| Gols (5) | 6.871 | 179 | **0** |
| BTTS (8) | 338 | **0** | — |
| Dupla Chance (12) | 507 | **0** | — |

1X2, BTTS e Dupla Chance não têm nenhuma linha degenerada na janela. As 237 que existem estão em
Handicap e Gols, e **nenhuma delas tem preço da Pinnacle em janela nenhuma** — são consenso puro.
Como o benchmark preferido desses dois mercados é o sharp, a correção não alcança nenhuma das 39
linhas comparadas.

O teste do "nenhuma tem Pinnacle" foi **falsificado contra um controle**, porque um join quebrado
daria zero do mesmo jeito: nas linhas *não* degeneradas o mesmo join casa 3.370 de 6.566 no
Handicap e 3.054 de 6.692 no Gols. O zero é real.

Isto confirma empiricamente a afirmação "TODAS consenso" que o cabeçalho do `task01_base()` faz
sobre as 172 linhas, e a estende: a correção é **invisível ao benchmark preferido**, em todos os
cinco mercados.

### A única divergência: `linha_descendo`

| campo | publicado | medido | delta |
|---|---|---|---|
| n (piso 0) | 405 | 403 | **−2** |
| n (piso 5) | 215 | 213 | **−2** |
| diferença piso 0 | +3,1 | +3,2 | +0,1 |
| diferença piso 5 | +5,3 | +5,5 | +0,2 |
| diferença piso 10 | +5,3 | +5,5 | +0,2 |
| a odd dava (piso 0) | 53,0 | 52,9 | −0,1 |
| aconteceu (piso 0) | 56,0 | 56,1 | +0,1 |
| jogos médios | 10,3 | 10,3 | **0** |
| % amostra curta | 46,9 | 47,1 | +0,2 |
| peso k50 / k0 | 2,74 / 3,08 | 2,85 / 3,21 | +0,11 / +0,13 |

São **duas linhas de aposta**, e não uma mudança de comportamento: 0,5% da amostra da premissa.
As duas tinham `min_jogos >= 5` (saíram também do piso 5) e não eram de amostra curta — é por isso
que `% amostra curta` **sobe** ao removê-las e `jogos médios` não se move.

`linha_subindo`, que é o mesmo sinal do lado Over, reproduz a diferença publicada **exatamente**
(−1,5). O doc não publica o `n` dela, então a superfície de comparação é menor.

**O que foi descartado, com medição:**

1. **Correção #22** — descartada. As linhas removidas por ela são consenso puro; `linha_descendo`
   publicado é sharp. Nenhuma linha com Pinnacle foi removida em mercado nenhum.
2. **Deriva de odds** — descartada. Zero capturas posteriores a 04/08 para os 169 jogos.
3. **Mudança de código nos modelos do caminho** — descartada. Entre o commit que publicou a [0.1]
   (`e6bc54e`) e este, os únicos modelos alterados no caminho de Gols são o `int_futebol_odds_devig`
   (só a regra de emissão da #22) e dois `CASE` de slug em `fact_fixtures`/`fact_odds_snapshot`
   que acrescentam Bundesliga, Ligue 1 e Primeira Liga — nenhuma das três está na janela.
   `int_futebol_premissas_ou` não foi tocado.
4. **`int_futebol_team_form_pit`** — descartada. A Costura A passou nesta execução: a saída no
   default é igual, linha a linha, ao baseline congelado antes das vars.

**O que sobra**, e fica registrado como resíduo aberto: o `fact_odds_snapshot` é reconstruído do
NDJSON do GCS a cada build, e o `collection_date` vem do dado, não do instante da ingestão. Um
arquivo que tenha chegado ao bucket depois de 04/08 carimbado com data anterior entraria na tabela
sem aparecer no teste 2 acima — e uma casa a mais na média de t15m basta para virar uma linha
marginal. É a única hipótese que sobrevive a tudo que foi medido, e ela é **candidata, não causa
provada**.

**Por que isso não invalida a medição:** o resíduo é 2 linhas em 1 premissa de 39, ele move a
diferença em 0,2 pp, e ele afeta as quatro células **da mesma forma** — as quatro leem o mesmo
`fact_odds_snapshot` na mesma execução. A [F] compara células entre si; um viés comum às quatro
cancela na comparação. Ele importaria se alguém reaproveitasse o baseline publicado da [0.1] como
célula `base`, que é exatamente o que a spec proíbe.

### O que a medição produziu além da reconciliação

A tabela `futebol_taskF.taskf_teste2` tem 60 linhas na célula `base`: as **39** do benchmark
preferido (`usado_para_peso = true`) mais 21 de consenso do Handicap e do Gols, que não pesam mas
ficam visíveis. Duas coisas nela não existiam antes:

- **O piso 3**, que a spec #49 pede e a [0.1] não tinha, nas 39 linhas.
- **Os pisos 5 e 10 das 19 premissas de peso zero.** A [0.1] publicou só a diferença no piso 0
  delas, em parágrafo corrido. Agora há varredura completa — e ela mostra coisas que valem para a
  [B], como `sem_rodizio` medindo −2,7 **idêntico nos quatro pisos** (n=188 em todos), o que é a
  assinatura de uma premissa que só acende em jogo com histórico longo.

### Reprodução

```bash
cd dbt_futebol

# 1. a camada de premissas na célula base (vars no default), no dataset de medição
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --target taskF \
  --select +int_futebol_premissas_1x2 +int_futebol_premissas_ou +int_futebol_premissas_ah \
           +int_futebol_premissas_btts +int_futebol_premissas_dc +int_futebol_corroboracao

# 2. o Teste 2 com coluna de célula
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_teste2 \
  --vars '{taskf_git_sha: fa98ceb}'
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_teste2.sql

# 3. a reconciliação contra o publicado
DBT_PROFILES_DIR=.. ../.venv/bin/dbt compile --target taskF --select taskf_reconciliacao_01
bq query --use_legacy_sql=false --project_id=smartbetting-dados \
  < target/compiled/dbt_futebol/analyses/taskf_reconciliacao_01.sql

# 4. a transcrição dos números publicados confere com o doc que os publicou
.venv/bin/python3 scripts/confere_taskf_publicado_01.py
```

O `dbt build` do passo 1 fecha com **10 ERROR e 3 SKIP**, todos em testes de `relationships` cuja
contraparte (`dim_teams`, `dim_players`, `fact_fixture_lineups`, `fact_fixture_events`) está fora
da ancestria da medição e por isso não existe no dataset. Nenhum modelo falha; os 25 saem
`success`, e passam a Costura A, as guardas de grão dos cinco modelos de premissas — soltar
`competition_id` de um join é o caminho natural para fan-out, e é isso que elas pegam — e as duas
guardas do conjunto de saídas do de-vig.
