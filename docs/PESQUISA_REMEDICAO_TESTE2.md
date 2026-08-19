# Pesquisa — a remedição do Teste 2 está destravada?

> **A decisão que este levantamento pedia foi tomada em 2026-08-19:**
> `dbt_futebol/docs/adr/0010-a-remedicao-do-teste-2-e-janela-nova-sobre-pipeline-juntado.md`.
> Ela responde a bifurcação da seção 3 (leitura estrita, e não a pragmática), corta a circularidade
> da ADR 0008 descrita na seção 2c, e substitui a condição de destrave de 04/08 por cinco termos
> conferíveis. Duas incertezas da seção 4 foram fechadas com dado vivo — o universo do Teste 2 não
> passa pelo gate, e o eixo que resgata a Europa na janela nova é o **recorte**, não o escopo.
> Este documento fica como está: é o levantamento que a ADR cita, não um documento vivo.

Levantamento, não decisão. Escrito em 2026-08-19 contra o código do worktree
`impl-87-flags-penalidade` (`master` em `2a4ac2a`), o corpo das issues do GitHub, as ADRs do
`dbt_futebol/docs/adr/` e os dois docs de resultado (`docs/TASK01_RESULTADOS.md`,
`docs/TASKF_RESULTADOS.md`). Nenhum modelo, macro, teste ou config foi tocado; nenhum `dbt run`
foi executado.

---

## 1. A pergunta e a resposta curta

> **A pergunta:** a [B] está destravada — (a) o bug do de-vig de consenso foi corrigido, (b) as
> três janelas de coleta estão em uso e (c) o histórico do time foi juntado entre campeonatos?
> **A resposta: NÃO.** (a) FEITA e (b) FEITA (com ressalva de domínio), mas (c) foi **medida pela
> [F] e recomendada — nunca implementada em produção**, e é ela que segura a remedição do Teste 2.

A task `[B] Limpeza do catálogo de premissas` ([ClickUp `wdx6zev64y`](https://app.clickup.com/t/wdx6zev64y),
status `backlog`) tem, desde 04/08/2026, esta condição de destrave: *"a remedição do Teste 2 depois
de (a) corrigir o bug do devig de consenso, (b) passar a usar as três janelas de coleta e (c)
juntar o histórico do time entre campeonatos."*

| Condição | Veredito |
|---|---|
| (a) bug do de-vig de consenso | **FEITA** — corrigida na origem em 05/08 (issue #22, commit `398b1d2`) |
| (b) usar as três janelas de coleta | **FEITA na letra, com ressalva de domínio** — #37 e #40 mergeadas, são QUATRO janelas hoje; mas a ADR 0004 decidiu explicitamente que isso **não** multiplica a amostra do Teste 2 |
| (c) juntar o histórico entre campeonatos | **NÃO FEITA em produção; MEDIDA na [F]** — o eixo existe como var de medição, o default de produção continua `da_competicao`, e nenhuma issue aberta implementa a mudança |

**Resposta: NÃO destravada.** A [F] respondeu a pergunta de (c) — e recomendou juntar — mas o
código de produção não mudou: as nove fontes de histórico seguem filtrando por competição. O que
existe hoje é a *medição* de como o Teste 2 fica com o histórico junto (células `escopo` e `ambos`
em `futebol_taskF.taskf_teste2`, lote de 13/08), não um pipeline que junta. Se a [B] aceitar ler a
medição da [F] como "a remedição", ela está **parcialmente** destravada — com três ressalvas
abertas (#82, #71 e a janela 100% ano-calendário) descritas na seção 3.

---

## 2. Condição por condição

### (a) "corrigir o bug do devig de consenso" — **FEITA**

**A que o bug se refere.** É o achado colateral da [0.1] registrado em
`docs/TASK01_RESULTADOS.md:79`: *"De-vig de consenso com uma só saída precificada dá
`prob_justa = 1,0` e edge de até 14.900% (172 linhas, 2 vitórias em 172)"*, com a coluna "Produção
afetada?" respondida **Não** — *"o gate barra. Mas contamina todo backtest, inclusive o
publicado"*.

Ele virou a issue **#22** (`Futebol · [D] Conjunto de saídas declarado por mercado: o de-vig para
de anunciar certeza`, **CLOSED**), cuja origem no ClickUp é `wdx6zevnhx` — *"Corrigir o de-vig de
consenso que anuncia valor máximo em linha de 1% de acerto"*. O corpo da #22 dimensiona: **404
linhas** em produção com `prob_justa = 1,0`, **todas de benchmark consenso**, edge de +820% a
+14.900%, odd até 150,0 — 62 no Handicap(4), 206 no Gols(5) e 136 no Gols 1ºT(6). Mecanismo: o
de-vig normaliza `prob = (1/odd) / Σ(1/odd)` sobre o conjunto de saídas; conjunto de um elemento
faz a soma valer o próprio termo e a prob virar 1,0.

**A correção está no código.** Commit `398b1d2` (2026-08-05, *"fix(devig): conjunto de saidas
declarado por mercado — o de-vig para de anunciar certeza"*):

- `dbt_futebol/macros/devig_conjunto_saidas.sql:24` — macro `futebol_conjunto_saidas()`, fonte
  única do tamanho esperado do conjunto por mercado (`1:3, 4:2, 5:2, 6:2, 8:2, 12:3`).
  Comparação **exata**, não `>=`, com o argumento escrito no cabeçalho: *"pelo menos duas"
  deixaria passar o 1X2 com duas das três saídas (booksum ~0,66, probs infladas ~1,5×) — mesmo
  bug, sem a prob 1,0 que denuncia*.
- `dbt_futebol/models/intermediate/int_futebol_odds_devig.sql:227-234` — CTE `emissao`:
  `(c.conjunto_esperado IS NOT NULL AND c.n_outcomes_valor = c.conjunto_esperado) AS emite_valor`.
  Mercado não declarado → `NULL` → não emite (fail-closed).
- `int_futebol_odds_devig.sql:251-265` — `prob_justa_fechamento`, `booksum_fechamento`,
  `valor_fonte`, `edge` e `pts_valor` viram `NULL` quando `emite_valor` é falso;
  `n_outcomes_valor` permanece real como diagnóstico (linha 258).
- A regra é escrita **uma vez só**, sobre a coluna já consolidada — cobre Pinnacle, Dupla Chance
  derivada e consenso de uma vez (CTE `consolidado`, `int_futebol_odds_devig.sql:161-166`), o que
  fecha o risco latente que a #22 nomeia: *"o de-vig da Pinnacle usa a mesma normalização, sem
  nenhuma guarda"*.
- Decisão registrada em `dbt_futebol/docs/adr/0002-conjunto-de-saidas-declarado-por-mercado.md`.

**E a base de medição já foi reapontada para o universo corrigido.**
`dbt_futebol/macros/task01_base.sql:40-46` (cabeçalho, ⚠️ REAPONTADA em 2026-08-05): *"o universo
de referência passa a ser o CORRIGIDO — sem as linhas de conjunto de saídas incompleto... O
headline de consenso se move de −14,9% para −14,5%: ~0,4 ponto, e NENHUMA conclusão da [0.1]
vira."* O flag `conjunto_incompleto` (`task01_base.sql:231`) não foi removido: **trocou de papel
para testemunha** — se voltar a ser verdadeiro, a correção regrediu (`task01_base.sql:224-230`).

**O que sobra.** Nada bloqueante. Duas notas de contorno, nenhuma reabre (a):

1. A #22 registrava que *"nenhum `dbt test` roda em lugar nenhum... Todo teste deste projeto é
   decorativo hoje"*. Isso foi endereçado: `dbt_futebol/macros/devig_janela.sql:20-22` descreve o
   agendado já com fase própria de teste — *"No `workflow_futebol.yml` a fase de `dbt run` é a 2 e
   a de `dbt test --select tag:guarda` é a 4, sem gate (de propósito, para teste vermelho não
   derrubar o board nem o sync)"*. Consequência a ter em conta: guarda vermelha **reporta**, não
   impede a linha ruim de chegar ao board.
2. A issue **#87** (`O mart descarta as 4 flags de penalidade e o serving as readivinha errado`,
   CLOSED em 19/08) mede que **7.710 chaves `(fixture, outcome_side, line_value)` colidem entre os
   mercados 5 e 6** em `int_futebol_odds_devig` — mas o defeito é do consumidor (o `distinct on`
   da RPC `get_futebol_fixture_value`, sem `market_id` nem `janela_usada`), não do de-vig. O
   mercado 6 está declarado no `futebol_conjunto_saidas()` justamente porque carregava **136 das
   404 linhas podres** da #22 (`devig_conjunto_saidas.sql`, bloco de documentação).

---

### (b) "passar a usar as três janelas de coleta" — **FEITA na letra, com ressalva de domínio**

**O que existia em 04/08 (data da condição).** O `int_futebol_odds_devig` resolvia cada linha para
**uma** janela — a mais recente disponível, via `QUALIFY window_priority = MAX(...)` — e descartava
as outras duas. Está escrito na ADR 0004, primeiro parágrafo
(`dbt_futebol/docs/adr/0004-o-grao-do-devig-e-a-janela.md`), e no comentário histórico que
sobreviveu no modelo (`int_futebol_odds_devig.sql:25-30`).

**O que foi feito.**

- **Issue #37** (`Motor: o de-vig passa a emitir por janela, com o board inalterado`, **CLOSED**),
  commit `b684a9a` (2026-08-10). A janela entrou na chave: o grão do de-vig é hoje
  `(fixture_id, market_id, outcome_side, line_value, janela)` —
  `int_futebol_odds_devig.sql:3` (description) e a CTE `per_outcome`
  (`int_futebol_odds_devig.sql:31-56`), com `collection_window` no `GROUP BY`. Todas as três
  fontes de valor normalizam **dentro da janela**: `pinnacle_devig` (`:75`), `consensus_devig`
  (`:108`) e `dc_devig` (`:144`, que casa com `x2_pinnacle` em `:132` pela janela). Os joins da
  consolidação também casam pela janela (`:186-232`), com uma exceção declarada: `pinnacle_move`
  (`:89`) **não** entra pela janela, porque o sinal de movimento sharp é propriedade da linha
  (comentário em `:213-217`).
- **Issue #40** (`Motor: janela de detecção no board`, **CLOSED**), commit `988d0ac`
  (2026-08-18). O board ganhou `janela_deteccao` — a janela mais cedo em que a linha passou no
  gate — sem mudar o grão do mart.
- A redução para a janela corrente virou macro única:
  `dbt_futebol/macros/devig_janela.sql:94` (`futebol_devig_janela_corrente()`), que desde a #40 é
  um filtro sobre `futebol_devig_todas_janelas()` (`devig_janela.sql:58`) — as duas leituras não
  têm como divergir na definição de "janela corrente".

**⚠️ São QUATRO janelas, não três.** `devig_janela.sql:8-11`: *"A `daily` entrou em produção em
07/08/2026 (`tech-lamjav/data-engineering#34`, horizonte de 7 dias) e o board já publica nela.
Qualquer coisa que assuma três janelas está desatualizada."* A ordem declarada é
`daily(1) < t24h(2) < t1h(3) < t15m(4)` (`devig_janela.sql:28-36`). Ou seja: a condição (b) foi
escrita com o mapa de 04/08 e o mapa mudou a favor dela.

**A medição consome isso — reduzindo a uma janela, de propósito.**
`dbt_futebol/macros/task01_base.sql:248` lê `FROM ({{ futebol_devig_janela_corrente() }})`, e o
comentário imediatamente acima (`task01_base.sql:237-247`) explica: *"⚠️ REDUZIDO À JANELA
CORRENTE (#37). O de-vig passou a emitir uma avaliação por janela coletada; ler sem reduzir faria
cada aposta entrar no backtest até 4 vezes, uma por preço, todas liquidadas pelo mesmo placar. É
EXATAMENTE o erro que a ADR 0001 e a ADR 0004 existem para impedir... A redução reproduz
byte-a-byte a base de antes da #37."*

**A ressalva de domínio, e ela é o ponto.** Se a intenção por trás de (b) era *aumentar a amostra
do Teste 2*, essa intenção foi **julgada e rejeitada**, não deixada por fazer. ADR 0004, seção *"O
que esta decisão NÃO compra"*: o multiplicador de 2,84× (21.407 linhas contra 60.818 pares
linha×janela; no recorte liquidado 19.649 → 56.440 sobre **179 jogos, antes e depois**) é real e a
conclusão é falsa — *"As três janelas de uma linha são três preços do mesmo palpite, liquidados
pelo mesmo placar... o ROI esperado não se move e o intervalo de confiança encolhe por √3 sem que
tenha entrado informação nenhuma."* E a sentença operativa: **"os Testes 2, 3 e 4 seguem com uma
observação por linha, com a janela fixada antes de olhar resultado."**

**O que (b) então compra para a remedição:** (i) a janela é agora uma escolha declarada e fixável
antes de olhar resultado, em vez de um `QUALIFY` implícito; (ii) a pergunta de CLV — *o edge de
t24h prevê melhor ou pior que o de t15m?* — passa a ser formulável (6.885 linhas com as duas
janelas, ADR 0004); (iii) o board ganhou `janela_deteccao`. Nenhum desses três é pré-requisito da
limpeza de catálogo, mas nenhum está pendente.

**O que sobra.** Nada de infraestrutura. Sobra uma **decisão de leitura**: quem escrever a
remedição precisa dizer se aceita a adjudicação da ADR 0004 (uma observação por linha) ou se
considera (b) não cumprida por a amostra não ter triplicado. Sob a ADR, (b) está cumprida.
⚠️ A ADR 0004 tem ainda uma *emenda de 2026-08-06* avisando que os três números de CLV dela
(931 / 1.350 / 368 linhas) **têm prazo de validade**: depois das subtasks A1+A2 da task [A] a nota
deixa de se mover entre janelas e as 368 passam a ser outro conjunto — *"remedir, não reaproveitar"*.

---

### (c) "juntar o histórico do time entre campeonatos" — **NÃO FEITA em produção; MEDIDA na [F]**

Esta é a condição que decide a resposta, e é onde "a [F] respondeu" e "o código mudou" se separam.

#### O que a [F] fez: mediu

A task [F] são as issues **#49 a #59** (todas **CLOSED**; #59 fecha também a #49). Ela montou um
2×2 de eixos de medição:

- `dbt_futebol/macros/taskf_eixos.sql:43-44` — os dois eixos são **vars de dbt**:
  `pit_escopo` (`da_competicao` | `todas`) e `pit_recorte` (`temporada` | `ultimos_10`), com
  validação fail-closed (`:47-54`).
- `dbt_futebol/macros/taskf_celula.sql` — o nome da célula é **derivado** dos eixos:
  `da_competicao|temporada → base`, `todas|temporada → escopo`,
  `da_competicao|ultimos_10 → recorte`, `todas|ultimos_10 → ambos`
  (`taskf_celula.sql`, macro `taskf_nomes_de_celula()`).
- O eixo de escopo alcança **nove predicados em seis modelos** —
  `dbt_futebol/macros/taskf_fontes_de_historico.sql` (bloco "OS NOVE PREDICADOS DE ESCOPO (#52)"):
  `team_form_pit` (dois ramos), `premissas_1x2.spine`, `premissas_ah.margin`,
  `premissas_btts.last5`, `premissas_dc.hist`, `premissas_ou.spine`, `premissas_ou.pool`,
  `premissas_ou.last5`.
- A medição roda em **dataset próprio** (`futebol_taskF`), por decisão registrada na
  `dbt_futebol/docs/adr/0007-a-medicao-de-escopo-roda-em-dataset-proprio.md`, e a saída é
  `futebol_taskF.taskf_teste2` (`dbt_futebol/analyses/taskf_teste2.sql`, cabeçalho: *"POR QUE ESTA
  ANÁLISE É UM SCRIPT DDL, E NÃO UM MODELO dbt"*).

**Resultado medido** (`docs/TASKF_RESULTADOS.md`, seção Veredito, linhas 20-56):
32 das 39 premissas mudam de número quando o escopo é solto; o universo com `min_jogos >= 5` sobe
de **69 para 92 jogos** (`TASKF_RESULTADOS.md:30-31, 367-368, 1979, 2421`); a amostra curta média
cai de **45,5% para 34,5%**; premissas com peso positivo no piso 5 **caem de 15 para 11**
(`:604`) — o merge não infla o catálogo.

#### O que a [F] NÃO fez: mudar o pipeline

Este é o cerne, e a evidência é direta:

1. **O default é competição-scoped.** `dbt_futebol/macros/taskf_eixos.sql:43-44` —
   `var('pit_escopo', 'da_competicao')` e `var('pit_recorte', 'temporada')`. Sem `--vars`, o SQL
   compilado é o antigo.
2. **Produção nunca passa as vars, e isso está escrito no próprio modelo.**
   `dbt_futebol/models/intermediate/int_futebol_team_form_pit.sql:4` (description): *"aceita as
   vars pit_escopo (da_competicao|todas) e pit_recorte (temporada|ultimos_10), cujos DEFAULTS
   reproduzem exatamente o descrito acima — no default o SQL compilado é idêntico ao de antes das
   vars existirem. **Produção nunca as passa**; elas servem às células de medição, materializadas
   no dataset futebol_taskF."* A mesma frase está nos cinco modelos de premissas
   (`int_futebol_premissas_1x2.sql:3`, `_ah.sql:4`, `_ou.sql:3`, `_btts.sql:3`, `_dc.sql:3`).
3. **O predicado de competição continua lá no caminho default.**
   `int_futebol_team_form_pit.sql:186-187`:
   `{%- if pit_escopo == 'da_competicao' %} AND l.competition_id = a.competition_id`.
4. **Nada no agendado passa `--vars`.** As únicas ocorrências de `pit_escopo`/`pit_recorte` neste
   repo, fora dos modelos/macros, são em `docs/TASKF_RESULTADOS.md` (linhas de comando de medição,
   ex. `:633, 965-967, 1223-1225, 2345-2347`) e em testes da própria [F]
   (`dbt_futebol/tests/assert_taskf_*.sql`). Nenhum script de `scripts/` passa vars, e um `grep -r`
   por `pit_escopo|pit_recorte` em `data-engineering/` — onde moram os workflows que disparam o
   job dbt — devolve **zero ocorrências**.
5. **A própria [F] declara que juntar é trabalho futuro.** `docs/TASKF_RESULTADOS.md:58`,
   Recomendação 1: *"**Juntar o escopo — sim, e é uma mudança de pipeline, não de peso.** A
   medição sustenta soltar `competition_id` nas nove fontes de histórico."* Uma recomendação, não
   uma execução.
6. **Nenhuma issue aberta implementa isso.** As 8 issues abertas hoje são #86, #85, #82, #80, #71,
   #38, #26 e #15 (`gh issue list --state open`); nenhuma delas é "soltar `competition_id` nas nove
   fontes".

#### O impedimento que sobra, e a circularidade

`dbt_futebol/docs/adr/0008-premissa-de-tabela-nao-tem-escopo-juntado.md` decide que **quatro
premissas de tabela** — `superioridade_tabela` (1X2), `supremacia` e `sem_rodizio` (Handicap) e a
coluna interna `x_superioridade_tabela` (reusada pela Dupla Chance) — **permanecem
competição-scoped em todas as células**, porque `rank`, `ppg` e `n_teams` não existem num histórico
juntado. A ADR nomeia a alternativa séria (eleger uma "competição principal" por time) e a **adia
explicitamente para a [B]**: *"Fica registrada como candidata para a [B], onde o `sem_rodizio`
merece atenção por ser do Handicap, o mercado com ROI positivo."*

⚠️ **Isso é uma circularidade real:** parte de (c) está delegada à própria task que (c) bloqueia.
Ela não pode ser resolvida por evidência — é chamada de escopo de quem despacha a [B].

#### O que falta em (c)

Soltar `competition_id` nos nove predicados em produção (as sete premissas cobertas pela ADR 0008 e
pelas fontes imunes ficam de fora por construção), com as duas ressalvas que a [F] já mediu e
precificou (`TASKF_RESULTADOS.md:66-68`, Recomendação 4): **1,46 titular a mais de rodízio** entre
liga e copa, e **40,7% das partidas emprestadas contra adversário que a coleta não alcança**.
Nenhuma das duas inverte a recomendação — as duas entram na [B] como ressalva com número.

---

## 3. O que ainda falta para a remedição rodar

Ordenado do que bloqueia para o que qualifica.

1. **Decidir o que "remedição" significa** — é a bifurcação, e é humana:
   - **Leitura estrita** ("o pipeline junta e aí se remede"): falta implementar a Recomendação 1
     da [F] (soltar `competition_id` nas nove fontes em produção). Não existe issue; precisa ser
     escrita.
   - **Leitura pragmática** ("a [F] já mediu o Teste 2 com o histórico junto"): a medição existe —
     `futebol_taskF.taskf_teste2`, células `base`/`escopo`/`recorte`/`ambos`, lote único de
     13/08/2026 17:49–17:56 UTC, commit `7fdd1a3`, universo congelado `kickoff ∈ [16/06, 04/08
     12:00 UTC)` = **169 jogos** (`TASKF_RESULTADOS.md`, seção "Carimbo de execução"). Ela roda
     sobre a base já corrigida por (a) e já reduzida por (b). Nesse caminho, o que falta são os
     itens 2 a 5 abaixo.
2. **Fechar a #82 antes de reconstruir qualquer célula.** `Rebaselinar os 4 números da [F] medidos
   sob a regra antiga de média` (**OPEN**, follow-up da #78, que trocou `AVG`/`APPROX_QUANTILES`
   por `SAFE_DIVIDE(SUM, COUNT)` + `NUMERIC`). O corpo é explícito: as células hoje em
   `futebol_taskF` são as da **regra antiga**; a guarda
   `tests/assert_taskf_base_reproduz_01.sql` *"fica verde enquanto ninguém reconstruir as células
   da [F]"* e **fica vermelha de propósito na próxima remedição**, em `superioridade_xg`,
   `xg_combinado_alto`, `xg_baixo_combinado` e `ritmo_alto`. Qualquer remedição real reconstrói as
   células, logo cai nisto.
3. **Resolver, ou aceitar como ressalva, a decisão adiada pela ADR 0008** (competição principal
   para `superioridade_tabela`, `supremacia`, `sem_rodizio`). É a circularidade da seção 2c.
4. **Decidir o que fazer com a #71** (`Jogo decidido nos pênaltis ou na prorrogação não entra no
   histórico de time nenhum`, **OPEN**). Ela bate exatamente no histórico de copa que (c) resgata:
   `status_short = 'FT'` exclui `AET`/`PEN` do `team_log` e dos `last5` — **14,2% dos jogos
   encerrados da Copa do Brasil**. O próprio ticket mede que, nas contagens que o PIT usa, o efeito
   é pequeno (Copa do Brasil 409 → 412 partidas, **+0,7%**), mas ele existe e é do mesmo lado do
   dado que (c) mexe.
5. **Aceitar que a janela congelada não responde pela Europa nem pelas seleções.**
   `TASKF_RESULTADOS.md:44-56`: **Copa do Mundo e Champions somam 53,7% das partidas encerradas da
   janela (145 de 270)** e seguem sem conserto — na Copa do Mundo o deserto é real (0% dos pares
   (jogo, time) ganham uma partida ao soltar a competição); a Champions **não tem um jogo** no
   universo congelado. E ⚠️ *"o universo congelado é 100% ano-calendário: as ligas split-year não
   tinham começado em 16/06–04/08. Célula vazia é sem amostra, nunca efeito nulo."* Uma limpeza de
   catálogo feita sobre essa janela herda esse limite.
6. **Reler a instrução da [0.1] antes de usar o resultado.** A conclusão que sobreviveu a tudo é
   que **peso individual não se replica fora da amostra** (+8,3% in-sample virando −6,2%
   out-of-sample; 14,5 pontos de viés de seleção) — repetida na Recomendação 1 da [F]
   (`TASKF_RESULTADOS.md:58-61`). A [B] é **remover premissa sem evidência**, não reescrever peso;
   a remedição serve à primeira coisa.

---

## 4. Incertezas e o que eu não consegui determinar

- **A intenção exata de (b) não está escrita em lugar nenhum.** A condição diz "passar a usar as
  três janelas de coleta" e não diz para quê. Duas leituras são compatíveis com o texto: "o de-vig
  para de jogar duas janelas fora" (cumprida, #37/#40) ou "o Teste 2 passa a medir sobre as três
  janelas" (rejeitada pela ADR 0004, que a chama de amostra falsa). Reportei as duas em vez de
  escolher. **Não sei** qual o Victor tinha em mente quando escreveu em 04/08.
- **Não confirmei em BigQuery** que a tabela `futebol.int_futebol_odds_devig` de hoje tem zero
  linhas com `prob_justa_fechamento = 1,0` nem que `futebol_taskF.taskf_teste2` está com o lote de
  13/08 intacto. A instrução era não materializar; consultas de leitura seriam seguras, mas optei
  por não gastar quota já que o código e os docs decidem os três vereditos. Se alguém quiser
  fechar por dado vivo, são duas queries de leitura.
- **A task `wdx6zev64y` não tem nenhum comentário** (`clickup_get_task_comments`, `count: 0`) — a
  condição de destrave de 04/08 é o texto mais recente sobre o assunto no ClickUp, e nada a
  reinterpretou por lá. A task foi atualizada pela última vez em 04/08/2026
  (`date_updated: 1785883853106`).
- **Não li as tasks-irmãs do ClickUp** (`wdx6zevnhy`, origem da [F], e `wdx6zevnhx`, origem da
  #22) — só as conheço pelas citações dentro das issues do GitHub e dos macros. Se alguma delas
  tiver contexto que muda a leitura de (b) ou (c), ele não está neste levantamento.
- **Nomenclatura que engana:** `dbt_futebol/analyses/taskf_remedicao.sql` **não** é a "remedição do
  Teste 2" desta pergunta. É a análise de **estabilidade** da [F] (#56): compara duas execuções das
  quatro células campo a campo para provar que reconstruir devolve o mesmo número. O próprio
  cabeçalho avisa: *"Ela não confere que a medição está certa... Duas execuções idênticas e ambas
  erradas passariam aqui."*
- **Não sei quanto custa** implementar a Recomendação 1 em produção. Os nove predicados estão
  enumerados (`taskf_fontes_de_historico.sql`) e a var já existe em todos os seis modelos, então o
  diff mecânico é pequeno — mas a mudança move o `min_jogos` de todo jogo, logo move o board, o
  snapshot histórico e o sync. Nada nas fontes lidas dimensiona esse impacto a jusante.
- **Não avaliei** se a [A] (issue #15, redesenho do Score — tira o preço da nota) deveria vir antes
  da remedição. A emenda de 2026-08-06 da ADR 0004 diz que A1+A2 mudam a população das linhas que
  passam no gate, e a [B] herda essa população. Isso é uma pergunta de sequenciamento de tasks que
  está fora do que esta pesquisa foi pedida para responder.
