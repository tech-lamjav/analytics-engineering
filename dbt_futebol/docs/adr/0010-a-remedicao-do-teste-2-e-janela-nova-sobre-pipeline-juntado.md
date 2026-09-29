---
status: accepted
---

# A remedição do Teste 2 é janela nova sobre pipeline juntado, e a decisão de tabela não a bloqueia

A task **[B] Limpeza do catálogo de premissas** (ClickUp `wdx6zev64y`) está bloqueada desde
04/08/2026 por uma condição de três partes: *"a remedição do Teste 2 depois de (a) corrigir o bug
do de-vig de consenso, (b) passar a usar as três janelas de coleta e (c) juntar o histórico do time
entre campeonatos"*. Duas das três envelheceram, a terceira nunca foi implementada, e a ADR 0008
delegou à própria [B] uma decisão que parte de (c) parecia exigir.

Decidimos: **a remedição é uma medição nova, sobre um pipeline que junta escopo e recorte, numa
janela que não contém Copa do Mundo** — e a decisão de tabela adiada pela ADR 0008 **não** é
pré-requisito dela. A condição de destrave é reescrita em termos conferíveis por query, e está no
fim deste documento.

O levantamento que fundamenta tudo abaixo é `docs/PESQUISA_REMEDICAO_TESTE2.md` (19/08/2026), com
fonte em cada afirmação.

---

## Por que a condição de 04/08 não serve mais

**(a) foi feita** — issue #22, commit `398b1d2`, ADR 0002. Sem ressalva.

**(b) foi feita na letra e adjudicada na intenção.** As #37 e #40 puseram a janela na chave do
de-vig, e hoje são **quatro** janelas, não três (`macros/devig_janela.sql:8-11`). Mas se a intenção
de (b) era multiplicar a amostra do Teste 2, ela foi **julgada e rejeitada** pela ADR 0004, não
deixada por fazer: três preços do mesmo palpite liquidados pelo mesmo placar encolhem o intervalo
de confiança por √3 sem que entre informação. *"Os Testes 2, 3 e 4 seguem com uma observação por
linha."* Uma condição de destrave não pode exigir o que uma ADR aceita proíbe.

**(c) foi medida e recomendada, nunca implementada.** A [F] (#49–#59) montou o 2×2 de eixos como
vars com default de produção (`macros/taskf_eixos.sql:43-44`), mediu as quatro células em
`futebol_taskF` e recomendou juntar — *"é uma mudança de pipeline, não de peso"*
(`docs/TASKF_RESULTADOS.md:58`). Produção segue em `da_competicao`: os modelos dizem por escrito
*"Produção nunca as passa"*, nenhum workflow passa `--vars`, e nenhuma issue aberta implementa.

---

## A decisão, em cinco partes

### 1. A medição da [F] é evidência, não é a remedição

A [B] parou por um motivo escrito no corpo dela: *"36 das 39 premissas foram medidas com 40% a 88%
das linhas vindo de jogo sem histórico"*. A [F] atacou isso e o número melhorou — amostra curta
média de 45,5% para 34,5%, piso 5 de 69 para 92 jogos — mas **34,5% continua sendo amostra curta**,
e **46,7% da janela congelada é Copa do Mundo** (79 de 169 jogos encerrados e precificados), o
pedaço que juntar não conserta: 0% dos pares (jogo, time) ganham uma partida ao soltar a
competição, porque seleção não joga mais nada na nossa base.

Aceitar as células da [F] como a remedição seria destravar a [B] sobre o mesmo defeito que a fez
parar, com o número menor.

Há um segundo motivo, de coerência: se a [B] remover premissa com base em evidência sob
`escopo=todas` enquanto produção computa `da_competicao`, **o catálogo deployado terá sido validado
sobre um histórico que produção nunca calcula**. O pipeline muda primeiro; a evidência que decide o
catálogo tem de vir do pipeline que serve o catálogo.

### 2. (c) implementa escopo **e** recorte — a célula `ambos`, não a `escopo`

A Recomendação 1 da [F] fala em soltar `competition_id`. Na janela em que a remedição vai rodar,
isso não basta, e o motivo é calendário.

O ramo default do PIT mantém `AND l.season = a.season`
(`models/intermediate/int_futebol_team_form_pit.sql:238`). Todas as competições carregam
`season = 2026`, então o rótulo não bloqueia o merge — mas a temporada 2026 das europeias **começou
agora** (Primeira Liga 07/08, La Liga 15/08). Um clube português tem 0,5 partida de histórico na
season 2026 por mais competições que se juntem.

Piso 5, contado com a mesma aritmética do PIT (a contagem reproduz `base = 57` contra a leitura
direta de `int_futebol_team_form_pit`, que é a célula onde produção existe):

| piso 5 | `base` | `escopo` | `recorte` | `ambos` |
|---|---|---|---|---|
| janela congelada — 169 jogos ([F], #54) | 69 | **92** | 81 | 92 |
| janela nova — 112 jogos (04/08 12:00 → 19/08) | 57 | 69 | **88** | **94** |

| janela nova, por competição | jogos | `base` | `escopo` | `recorte` | `ambos` |
|---|---|---|---|---|---|
| champions_league | 21 | 0 | **0** | 6 | 9 |
| primeira_liga | 17 | 0 | **0** | 13 | 13 |
| la_liga | 5 | 0 | **0** | 3 | 3 |
| copa_do_brasil | 8 | 0 | 8 | 5 | 8 |
| sudamericana | 9 | 5 | 9 | 9 | 9 |

Na janela congelada o escopo fazia todo o trabalho e o recorte não acrescentava um jogo acima do
piso 5. Na janela nova é o inverso: **soltar a competição não resgata um único jogo europeu** —
0 de 43. É exatamente o que a Recomendação 5 da [F] avisou: *"'Escopo sozinho não ajuda a Europa'
NÃO é regra geral. Vale para esta janela, que cai inteira na virada de temporada… Quem implementar
precisa decidir o eixo de recorte com o calendário na mão, e não a partir deste número."*

Há um argumento de definição junto do de cobertura: **`temporada` é o recorte que fabrica a escassez
que a [B] parou para não usar.** Ele significa 30 jogos em novembro e 2 em agosto; um teto fixo de
10 é mais comparável entre competições e entre meses, não menos.

**O custo está medido e é do lado que dói.** O `margin_stats` do Handicap não tem filtro de season
nem hoje (ADR 0007), então para ele o recorte é só o teto — e as duas premissas mais fortes da base
inteira encolhem: `raramente_perde_por_2` `n_p0` 445 → 388 e `favorito_irregular` 453 → 427
(`docs/TASKF_RESULTADOS.md:898-905`). Do outro lado, `ambos` é a única célula em que `tende_golear`
e `clean_sheets_altos` saem do vermelho no piso 5 ao mesmo tempo — duas das quatro que a spec da [B]
apontou como "muito sinal, pouca amostra". A perda do Handicap entra como ressalva com número, ao
lado das duas da Recomendação 4 da [F].

### 3. A circularidade da ADR 0008 é aparente, e corta-se assim

A ADR 0008 adia para a [B] a alternativa da "competição principal" para `superioridade_tabela`,
`supremacia` e `sem_rodizio` (+ a coluna interna `x_superioridade_tabela`). Isso parece exigir que a
[B] decida antes de (c) — a task que (c) bloqueia.

Não exige, e a própria ADR 0008 já diz por quê: as quatro **permanecem competição-scoped**, e
*"essa imobilidade é o resultado reportado, não uma lacuna a preencher"*. Então:

1. **(c) sobe a produção sem tocar nas quatro.** `rank`, `ppg` e `n_teams` não existem num histórico
   juntado; o agregado `tabela` do PIT continua competição + temporada em qualquer célula.
2. **A remedição entrega, para as três premissas de tabela medidas, evidência sob `da_competicao`** —
   por construção, e a ADR 0008 explica a construção. A [B] as julga nessa evidência, como julga as
   outras 36. ⚠️ A igualdade entre células é no **piso 0**; nos pisos maiores elas mudam de número
   porque o `min_jogos` segue a célula, e isso é o mecanismo, não falha.
3. **"Competição principal" é um resultado candidato da [B], não um insumo dela** — muda a definição
   da premissa e exige medição própria depois. O `sem_rodizio` é o caso a vigiar: é do Handicap, o
   mercado com ROI positivo, e mediu −2,7.

Nada em (c) fica esperando a [B], e nada na [B] fica esperando uma decisão que (c) precisasse tomar.

### 4. A remedição roda em produção, ancorada na célula `ambos`

A ADR 0007 mandou medir em `futebol_taskF` porque `dev` e `prod` apontam para o mesmo dataset
`futebol`, e medir histórico juntado significaria publicar histórico juntado. **Com (c) em
produção essa premissa expira**: produção passa a *ser* a célula juntada, e a remedição vira um
`dbt run` normal mais o Teste 2 do `task01_base` contra `futebol`, sem var nenhuma. A ADR 0007 fica
`superseded` no que toca a exigência de dataset próprio; `futebol_taskF` permanece como registro
congelado do 2×2.

A reconciliação contra a [0.1] (`macros/taskf_publicado_01.sql`) morre por construção — janela
diferente e pipeline diferente. **O que a substitui:** rodar o Teste 2 do pipeline novo sobre a
**janela congelada** e cobrar que ele reproduza a célula `ambos` da [F]. Se reproduzir, a máquina
está certa e o que mudou é o mundo; se não reproduzir, a implementação de (c) divergiu da medição
que a autorizou. É a única conferência que sobrevive à troca de janela.

⚠️ **A janela congelada é um INSTANTE, e o `cutoff` do macro é um DIA.** O universo da [F] é
`kickoff_utc ∈ [2026-06-16, 2026-08-04 12:00 UTC)` (carimbo de execução do `TASKF_RESULTADOS.md`),
enquanto `macros/task01_base.sql:178` filtra `DATE(kickoff_utc) <= DATE(cutoff)` — fim do dia. Rodar
a âncora com `cutoff='2026-08-04'` puxaria para dentro os jogos da tarde e da noite de 04/08, que
pertencem à **janela nova**, e a comparação divergiria da célula `ambos` por um motivo chato que
alguém investigaria como achado. Quem implementar precisa de granularidade de timestamp na âncora —
seja estendendo o `cutoff` do macro, seja lendo a definição de universo da própria [F]. As duas
janelas ladrilham exatamente nesse instante, e é por isso que ele precisa ser o mesmo dos dois lados.

⚠️ **EMENDA DE 25/08 (#82, executada): a âncora NÃO cabe dentro da acumulativa.** Este documento
diz "reconstruir a célula `ambos`", e a leitura literal disso é sobrescrevê-la em
`futebol_taskF.taskf_teste2`. Não dá: a primeira invariante da Costura B
(`assert_taskf_celulas_mesmo_universo`, CTE `execucao`) cobra `git_sha` **idêntico nas quatro
células**, e uma célula medida noutro commit deixaria a guarda vermelha com razão — o 2×2 deixaria
de ser uma comparação, e este mesmo documento promete que `futebol_taskF` permanece o registro
congelado dele. A âncora nasce em `taskf_teste2_ancora`, por uma var fail-closed (`taskf_destino`,
macros/taskf_destino.sql) na MESMA análise, e as acumulativas ficam intocadas.

E ela saiu em **duas passadas**, não uma: entre a medição da [F] e hoje entrou também a **#113** —
a quarta cópia do predicado de meia-linha, que deixava a linha de QUARTO entrar no universo de
medição como se fosse meia (3.140 de 9.252 linhas na janela congelada). Uma correção nesse caminho
depois da âncora a mataria pelo mesmo argumento de identidade de código que o parágrafo abaixo faz
sobre a #71. P1 mede sem a #113 e isola #78+#71+#91; P2 mede com ela e é a âncora. Resultados e
carimbos em `docs/TASKF_RESULTADOS.md`, seção "#82 — A âncora da remedição, em duas passadas".

Isso torna a **#82 pré-requisito**, e a reescopa: de *"rebaselinar os 4 números da [F]"* para
**"reconstruir a célula `ambos` sob o código pós-#78, como âncora da remedição"**. Sem isso a
comparação falharia justamente em `superioridade_xg`, `xg_combinado_alto`, `xg_baixo_combinado` e
`ritmo_alto` — que é o que a #82 previu. A metade dela sobre a calibragem de `taskf_tolerancia_pp`
não depende disto e virou a **#92**.

**Quem executa esta ADR, e em que ordem:** expurgo do board (#80, #85, #86) → **#91**, que implementa
(c) — os dois eixos, a Costura A recongelada, a #71 no mesmo commit e o piso cortando o disponível →
**#82** reescopada, que reconstrói a célula `ambos` **sob o código da #91** e entrega a âncora → a
remedição em si (termos 3 a 5 abaixo). A **#92** é independente de toda essa cadeia.

### 5. Ordem de entrada em produção

(c) move o `min_jogos` de todo jogo → move quais premissas acendem → move a nota → move o board, o
snapshot `fact_value_opportunities_hist` e o sync. Há três issues abertas do [A] mexendo no mesmo
board (#80, #85, #86), e a #86 é uma medição de churn D+7 — ela leria o churn de (c) como se fosse
do expurgo.

**(c) entra depois do expurgo e depois de a #86 fechar.** O expurgo conserta defeito conhecido e a
#86 o valida; (c) é mudança de definição e pode esperar. Nenhum `ALTER` é preciso — (c) muda valores,
não colunas do mart —, então a ordem que a #40 estabeleceu (imagem antes do `ALTER`) não se aplica:
é `./build-and-push.sh dbt_futebol` e `./scripts/checa_deriva.sh` verde, rodado **de fora do
worktree**.

⚠️ **Sob `ultimos_10`, o piso de amostra passa a cortar a contagem errada se ninguém mexer.** O
`played_total` satura no teto do recorte, e a regra da [F] é que o piso corte o **disponível** (ADR
0007). O `pit` do `macros/task01_base.sql` lê `played_total`; com o default virado, ele precisa
ler `played_total_disponivel` — que o modelo passa a emitir, porque hoje ele só é emitido fora do
default. O raio disso é a medição e só ela: nenhum modelo de `marts/` lê `min_jogos` nem
`int_futebol_team_form_pit`.

⚠️ **CORREÇÃO DA ARITMÉTICA (review do PR #111, implementada em `bd10cd5`).** A versão original do
parágrafo acima afirmava que a troca é inócua no piso 5 mas deixa de ser no **piso 10**, onde "piso
10" passaria a querer dizer "exatamente 10" em vez de "pelo menos 10". **Isso é falso.** A
identidade `LEAST(d, 10) >= p ⟺ d >= p` vale para **todo** `p <= 10`, o piso 10 inclusive: com
`d = 15`, `LEAST` dá 10 e `10 >= 10` passa. Como `taskf_pisos()` é `[0, 3, 5, 10]`, a troca é
**no-op de filtragem nos quatro pisos**. A decisão não muda — o piso passa a **significar** o que a
[F] diz que ele significa, e o defeito deixa de estar armado para o dia em que alguém puser um piso
acima de 10, onde o `played_total` saturado empataria todo mundo e o piso pararia de filtrar. O que
cai é a urgência, não o mérito.

⚠️ **E O RAIO NÃO É SÓ FILTRO: TRÊS ANÁLISES REPORTAM `min_jogos` COMO VALOR.** O parágrafo do raio
acima está certo sobre `marts/`, mas não distingue quem usa `min_jogos` como **corte** de quem o usa
como **número publicado**. A esmagadora maioria dos consumidores filtra (`>= piso`), e para esses a
identidade acima garante que nada muda. Estes três **reportam**:

| onde | o quê |
|---|---|
| `analyses/task01_teste1.sql` | `AVG(min_jogos) AS jogos_medios` |
| `analyses/task01_teste2.sql` | `AVG(min_jogos) AS jogos_medios` |
| `analyses/task01_teste4_piso.sql` | `ROUND(AVG(min_jogos), 1) AS jogos_medios` |

Nas células de recorte `ultimos_10` — o default desde a #91 — esse `jogos_medios` passa a ser a
média **sem teto** em vez da saturada em 10, e portanto **sobe**. Nas células `temporada` nada muda,
porque ali as duas contagens são a mesma coluna.

**Decidido: registrar e seguir, não preservar.** O `jogos_medios` é diagnóstico de amostra, não
resultado — nenhuma conclusão da [0.1] se apoia nele, e as três análises já mudam de valor sob o
novo default por causa do escopo e do recorte, que é uma mudança muito maior que esta. Preservá-lo
como média da usada custaria um CTE `pit_usado` em cada uma das três só para manter comparável um
número que já não é comparável. Quem for reler os `jogos_medios` da [0.1] tem de reler sob a célula
em que foram medidos, e é isso que este parágrafo existe para dizer.

⚠️ Virar o default mata a premissa da Costura A (`tests/assert_taskf_pit_default_igual_baseline`),
que existe para provar que produção nunca usa a var. O cabeçalho dela já nomeia a saída honesta —
*"recongelar o baseline de propósito, no mesmo commit da mudança que o justifica"*. É isso, e no
mesmo commit. As outras três guardas da [F] têm tag `taskf`/`costura_b`, não `guarda`: não rodam no
agendado e se aposentam junto com o dataset, o que é limpeza da [B].

---

## A condição de destrave reescrita

A [B] destrava quando as cinco forem verdade. Cada uma é conferível por query ou por link — nenhuma
depende de leitura de intenção.

1. **O pipeline junta.** `pit_escopo` e `pit_recorte` têm default `todas` e `ultimos_10` em
   `macros/taskf_eixos.sql`; os nove predicados de `macros/taskf_fontes_de_historico.sql` compilam
   sem filtro de competição no default; as quatro premissas de tabela seguem competição-scoped
   (ADR 0008); o piso de amostra do `task01_base` passou a cortar `played_total_disponivel`; a
   imagem foi reconstruída e `./scripts/checa_deriva.sh` está verde.
2. **A #71 entrou no mesmo commit.** `AET` e `PEN` contam no `team_log` — é o mesmo diff, mexe em
   quais partidas entram no histórico, e medir uma sem a outra obriga a remedir de novo.
3. **A âncora reproduz.** Com a célula `ambos` reconstruída **sob o mesmo código que virou o
   default** (#82 reescopada, rodando **depois** da #91), o Teste 2 do pipeline novo rodado sobre a
   janela congelada — `kickoff_utc ∈ [2026-06-16, 2026-08-04 12:00 UTC)`, o **instante** do carimbo
   da [F], não o fim do dia 04/08 — reproduz essa célula dentro da tolerância declarada.

   ⚠️ **"Pós-#78" não basta, e a ordem importa.** O pipeline novo carrega também a **#71**
   (`AET`/`PEN` no `team_log`), que muda quais partidas entram no histórico. A janela congelada tem
   8 jogos de Copa do Brasil, e sob `ambos` o efeito vaza para o histórico de qualquer clube
   brasileiro que os tenha jogado. Uma célula `ambos` reconstruída **antes** da #91 não seria
   reproduzível pelo pipeline que a inclui, e a âncora ficaria vermelha por um motivo já conhecido —
   que é exatamente o modo de falha que ela existe para não ter.
4. **A janela nova existe e tem forma.** `kickoff_utc ∈ [2026-08-04 12:00, 2026-10-01 00:00) UTC`,
   com **≥ 400** jogos encerrados e precificados, **≥ 300** acima do piso 5, **≥ 100** desses vindos
   de competição split-year, e **zero** de Copa do Mundo. Projeção em 19/08: 568 agendados, taxa
   observada de encerrado-e-precificado de 96,6% (112/116).
5. **O Teste 2 rodou nessa janela** e as linhas estão publicadas em `docs/` com carimbo de execução
   (data, commit, dataset, universo), no padrão de `TASK01_RESULTADOS.md` e `TASKF_RESULTADOS.md`.

### O que NÃO é condição — declarado para não voltar

- **Não** é condição a amostra do Teste 2 crescer pelas janelas de coleta. São quatro janelas hoje,
  e a ADR 0004 decidiu que elas não multiplicam a amostra: uma observação por linha, janela fixada
  antes de olhar resultado.
- **Não** é condição a [A] (#15) ter aterrissado. O universo do Teste 2 **não passa pelo gate** —
  `macros/task01_base.sql:381-384` filtra `best_odd IS NOT NULL AND edge IS NOT NULL`, escopo de
  mercado e meia-linha, sem corte por nota nem por edge positivo. A A2 não o toca; a A1 só remove do
  catálogo `linha_subindo` e `linha_descendo`, que a [B] julgaria de qualquer forma. A emenda de
  06/08 da ADR 0004 ("remedir, não reaproveitar") fala dos três números de CLV, que saem de um
  recompute do gate — não do Teste 2.
- **Não** é condição a "competição principal" da ADR 0008 estar decidida. É resultado candidato da
  [B].
- **Não** é condição a Europa estar coberta. Sob `ambos` o que sobra não é eixo, é **fronteira de
  coleta**: UCL 9/21, Primeira Liga 13/17, La Liga 3/5, com o backfill de 2024 e 2025 completo nas
  sete europeias. Quem falta são qualificatórias da UCL e clubes recém-promovidos, cuja liga de
  origem não coletamos. Entra como ressalva com número, ao lado dos 40,7% de partidas emprestadas
  contra adversário que a coleta não alcança (#57).

---

## Alternativas consideradas

**Aceitar as células da [F] como a remedição, com três ressalvas.** Rejeitada pela parte 1: a
janela congelada é 46,7% Copa do Mundo, 100% ano-calendário e ainda 34,5% de amostra curta — é o
defeito que parou a [B], atenuado, não removido. E destravaria a [B] para editar um catálogo
validado sobre um histórico que produção não calcula.

**Implementar só o escopo (Recomendação 1 da [F], ao pé da letra).** Rejeitada pela parte 2: entrega
0 de 43 jogos europeus acima do piso 5 na janela em que a remedição vai rodar. A própria [F]
antecipou isso na Recomendação 5.

**Desacoplar o teto de contagem por site** — aplicar `ultimos_10` só onde havia filtro de season, e
poupar o `margin_stats` do Handicap. Rejeitada: compra ~400 linhas de Handicap ao preço de a célula
de produção deixar de ser uma das quatro que a [F] mediu, e portanto ao preço da âncora da parte 4.

**Deixar produção em `da_competicao` e remedir em `futebol_taskF`.** É a alternativa da parte 1 com
outro nome, e cai pelo mesmo argumento de coerência.

**Esperar a [A] (#15).** Rejeitada: custa semanas e não compra precisão nenhuma no Teste 2, cujo
universo não é gated.

**Manter a condição antiga e só marcar (c) como pendente.** Rejeitada: a condição exige, em (b),
algo que a ADR 0004 proíbe, e delega, via ADR 0008, uma decisão à task que ela bloqueia. Uma
condição que não pode ser satisfeita não é bloqueio, é esquecimento com data.

---

## Emenda de 2026-09-29 — o Teste 2 não passa pelo gate de preço, e a janela nova é declarada

Escrita **antes** de olhar qualquer resultado do Teste 2 na janela nova (regra 3 da ADR 0004).

### 1. O universo do Teste 2 continua sem gate — e agora isso está no código, não na intenção

A parte "O que NÃO é condição" afirma que o universo do Teste 2 **não passa pelo gate**. Em
2026-09-10 o `b4aad43` pôs as três portas de preço do board (`n_casas >= 4`, `NOT pen_odd_outlier`,
faixa de odd 1,50–4,00; Dupla Chance 1,25–2,00) como `WHERE` incondicional em `apostas` do
`task01_base`. A intenção do commit era o backtest ("o backtest media aposta que o board recusa"),
mas o macro é compartilhado e o Teste 2 herdou — sem que ninguém registrasse. Efeito medido em
2026-09-29 sobre a janela congelada (`completo`): **5.605 → 1.802 linhas**, mesmos 169 jogos (`sharp`
2.481 → 1.311; `consenso` 2.786 → 341; `derivada` 338 → 150). É "mudar quais linhas entram", que
invalida a âncora pela lista da #82.

**Decisão:** `task01_base` ganha `gates_board` (default `true`; produção e backtests inalterados) e
só `analyses/taskf_teste2.sql` passa `false`. O Teste 2 mede o universo que a ADR sempre disse que
media, e a âncora continua comparável. A leitura **com** gate é reportada ao lado como leitura
secundária — não como o Teste 2.

Por que não re-ancorar sobre o universo com gate: seria trocar o desenho do Teste 2 por tabela, num
commit que não o tinha como alvo. O gate filtra a faixa de odd (1,50–4,00), que enviesa o que
`a_odd_dava` enxerga; se o Teste 2 deve passar a medir o universo do board, isso é decisão da [B], com
ADR própria, e não efeito colateral.

O argumento de amostra curta **não** discrimina as duas leituras: acima do piso 5 ficam 514 de 632
jogos sem gate e 512 de 630 com gate (81,3% nos dois casos). O gate corta linhas (21,2 mil → 7,0 mil),
não jogos.

### 2. A janela e a composição do universo primário

- **Janela:** `kickoff_utc ∈ [2026-08-04 12:00:00, 2026-10-01 00:00:00) UTC`, como declarada em 25/08.
- **Seleções ficam fora do universo primário:** `copa_mundo` (1), `nations_league` (5) e `amistosos`
  (10). A Nations League entrou no mart depois da janela ser declarada (AE#193, 22/09) e está dentro do
  que o `task01_base` enxerga hoje (42 jogos encerrados e precificados; na leitura com gate, 478 linhas, 92% delas
  abaixo do piso 5, e nenhum jogo no piso 10). O ADR §1 recusou a Copa do Mundo pelo mecanismo — histórico de
  seleção não é medido pela nossa coleta —, e a Nations League repete esse defeito. Ela é medida **à
  parte**, como universo secundário.
- **Por que a redação é "seleções" e não "Copa do Mundo":** a macro `taskf_familia_competicao` rotula a
  Nations League `ano_calendario` só porque a base tem a temporada 2026 (24/09–17/11). Se o mata-mata de
  2027 entrar sob `season=2026`, ela passa a `split_year` e o piso de 100 split-year subiria por
  reclassificação, não por jogo. A família de cada competição na janela fica **fixada** como a lista
  abaixo, e uma re-execução posterior não a redecide.
- **Famílias fixadas (29/09):** `split_year` = `la_liga`, `primeira_liga`, `premier_league`,
  `serie_a_ita`, `champions_league`, `ligue_1`, `bundesliga`. `ano_calendario` = `serie_b`,
  `brasileirao`, `sudamericana`, `libertadores`, `copa_do_brasil`. Fora: `copa_mundo`,
  `nations_league`, `amistosos`.
- O predicado do universo da janela nova em `macros/taskf_universos.sql` ainda **não existe**; entra no
  PR que roda o Teste 2, depois de 01/10, com esta lista como especificação.

### 3. Os quatro pisos do termo 4 — contagem provisória de 29/09 (a final é a de 01/10)

`analyses/ae117_termo4_pisos.sql` (uma consulta, ambas as leituras). Universo primário = sem seleções
(a linha "Nations League fora" não desconta `copa_mundo` nem `amistosos`, que já são 0):

| piso | alvo | sem gate, NL dentro | sem gate, NL fora (primário) |
|---|---|---|---|
| encerrados e precificados | ≥ 400 | 632 | 588 |
| acima do piso 5 | ≥ 300 | 514 | 511 |
| de competição split-year | ≥ 100 | 359 | 359 |
| de Copa do Mundo | 0 | 0 | 0 |

Com gate (leitura secundária) os números são 630 / 512 / 359 / 0 com a Nations League dentro e
586 / 509 / 359 / 0 fora. Os quatro passam em todas as leituras, com folga; o veredito de
passa/falha não depende da decisão sobre a Nations League nem do gate. Restam ~11 jogos com odds abertas (Nações + uma Série B); nenhum é
split-year. A contagem que vale é a de 01/10, depois do rebuild dos fatos.

### 4. Ressalva nova, que a lista de invalidação da #82 não nomeia

`team_group` em `int_futebol_team_form_pit.sql` lê o `snapshot_date` **mais recente** de standings —
não é point-in-time. Na janela congelada, 43 das 542 linhas de PIT têm `rank` diferente entre o
`futebol_taskF` (build de 24/09) e produção (29/09), todas de Copa do Mundo e Champions, e isso move
duas células no `taskF` (`superioridade_tabela` sharp 98→99; `lado_coberto_forte` 119→120). Um snapshot
futuro pode mover o valor de um booleano da janela por **dado**, sem commit. Não é corrigido aqui;
fica registrado para que qualquer delta da remedição seja lido com isto em mente.

### 5. A âncora re-medida (nota de 2026-09-29, depois do re-run)

Com `gates_board=false`, a âncora foi re-medida no `aa9f44a`: mesmo universo (169 jogos / 5.605 linhas), 0
linhas sem contraparte, e **uma** linha divergente — `Gols · xg_combinado_alto` (sharp), por dado (fixture
1492290), não por código. Carimbo, delta e a descoberta do `team_group` não-PIT em
`docs/TASKF_RESULTADOS.md`, seção "AE#117". O termo 3 volta a ✅ com essa ressalva.
