# O contrato de serving: quem lê as tabelas sincronizadas, e com que suposição de grão

**Levantado em 2026-08-10, lendo as funções do Postgres PRD vivo** (`pg_get_functiondef`), não o
`prop-play-predictor/docs/futebol-prod-deploy.sql` — aquele arquivo não é migration, é registro, e
já ficou obsoleto antes.

## Por que este documento existe

O sync BQ→Postgres tem uma verificação de esquema (`check_schema_parity`) que responde uma
pergunta só: **o sync sobrevive?** Ele compara coluna a coluna e aborta as 21 tabelas se qualquer
uma divergir.

Ele não responde a pergunta que quebra o produto: **os leitores sobrevivem?** As RPCs
`public.get_futebol_*` leem essas tabelas e várias assumem o GRÃO delas. Mudar o grão de uma
tabela sincronizada **passa o parity inteiro e ainda entrega dado errado ao app.**

Isso já custou duas vezes:

| Quando | O quê |
|---|---|
| 2026-08-07 | A janela `daily` entra na coleta. O desempate de janela das duas RPCs de odds não a conhece, e `daily` empata com `t24h`. Ninguém notou por 3 dias |
| 2026-08-10 | A #37 põe a janela no grão do de-vig. `get_futebol_fixture_value` não tem desempate de janela e passa a escolher arbitrariamente os avisos de penalidade. Chegou a produção e foi revertido no mesmo dia |

Duas specs desta fila declararam esta camada verificada quando não estava: a **C1** afirma "a
aplicação não os consulta" (falso, ver abaixo) e a **C5** não a mencionou.

## A matriz

21 das 22 tabelas da allowlist são lidas por alguma RPC. **Só `dim_leagues` não é lida por
nenhuma** — mudança de grão nela não alcança o app.

✅ **A frase que estava aqui morreu, como previsto** (ADR 0009). Até 19/08/2026 este parágrafo
dizia que o `fact_value_opportunities_hist` também não era lido por RPC nenhuma e era "consumido
só por análise", com um aviso de que a segunda metade da frase morreria com o expurgo. Morreu: o
release #271 pôs no PRD as migrations 092–105, e **o `hist` virou fonte de duas telas** —
`get_futebol_value_history` (aba Histórico) e `get_futebol_fixture_value` (que cai no snapshot
quando o kickoff já passou). O passado do app é servido em leitura point-in-time no apito.

**O grão do `hist` é contrato de serving a partir daqui.** Ele deixou de ser tabela de análise, e
a consequência é a regra desta página inteira: mudar o grão dele — ou o `check_cols` do snapshot,
que é o que decide quando nasce versão nova — muda o que duas telas mostram. Não é mais mudança
interna.

| Tabela sincronizada | RPCs que leem | Suposição de grão | Estado |
|---|---|---|---|
| `fact_fixtures` | 9 (incl. `_futebol_team_form`) | 1 linha por `fixture_id` | ✅ |
| `dim_teams` | 4 | `get_futebol_teams` faz `distinct on (team_id)` **sem desempate** | ✅ inofensivo — a tabela é única por `team_id` (591/591 medido) |
| `fact_odds_snapshot` | 2 | `distinct on (…, bookmaker_name)` com desempate por janela | ⛔ **DEFEITO VIVO** — ver abaixo |
| `fact_value_opportunities` | 2 | 1 linha por (fixture, market, outcome, line) | ✅ hoje; ⚠️ #40/#41/A1 mexem nas COLUNAS |
| `int_futebol_odds_devig` | **nenhuma** (era 1, `get_futebol_fixture_value`) | — | ✅ **RESOLVIDO** pela migration 105 (release #271, 19/08). Era DEFEITO VIVO: a chave do `distinct on (fixture_id, outcome_side, line_value)` não tinha `market_id` nem `janela_usada`, então as 4 flags de penalidade que a RPC remontava saíam de uma linha sorteada — 74 das 126 linhas do board com janela diferente da publicada em 18/08, 76 em 19/08, e 34 com as flags contradizendo o `penalidades_globais_pts` da própria linha. A #87 publicou as flags no mart e o CTE morreu. Conferido em 20/08 no PRD: **nenhuma função de `public` referencia a tabela** |
| `fact_fixture_lineups` + `_players` | 1 (`get_futebol_fixture_extras`) | **uma fase só**, decidida por tempo e em separado para cada uma das duas tabelas | ✅ **RESOLVIDO** pela migration 103 (release #271, 19/08). O `jsonb_agg` filtrava nada e pegava TODAS as linhas do fixture: com as duas fases no ar, a tela mostraria formação sorteada entre a anunciada e a que entrou em campo, e desenharia cada jogador duas vezes. Agora `where lineup_phase = v_fase_*`, com a regra por TEMPO (`kickoff_utc <= now()` → `real`, senão `confirmed`) — a regra por EXISTÊNCIA que a 098 tinha estava errada: nos 154 jogos com as duas fases, a `confirmed` tinha 2,0 jogadores por jogo contra 46,5 da `real`. Conferido em 20/08 no PRD com `pg_get_functiondef` |
| `fact_injuries_snapshot` | 1 | `distinct on (player_id)` + `order by snapshot_date desc` | ✅ desempate correto e semântico |
| 5 × `int_futebol_premissas_*` | 2 cada | join por (fixture, outcome[, line]) | ✅ hoje; ⚠️ #41 pode adicionar coluna |
| `fact_h2h`, `fact_predictions_api`, `fact_standings_snapshot`, `fact_team_season_stats`, `fact_fixture_stats`, `fact_fixture_events`, `fact_fixture_player_stats` | 1–2 cada | leitura direta, sem suposição de unicidade além da chave natural | ✅ |
| `fact_value_opportunities_hist` | **2** (`get_futebol_value_history`, `get_futebol_fixture_value`) | leitura **point-in-time no apito**: 1 linha por `opportunity_key`, a versão viva quando o jogo começou | ⚠️ **tabela de serving** desde o release #271 (ADR 0009). O grão É contrato: mexer nele, ou no `check_cols` do snapshot, muda o que a aba Histórico e o bloco pós-jogo da tela do jogo mostram |
| `dim_leagues` | **nenhuma** | — | ✅ fora do alcance do app |

## ⛔ Defeito vivo: o desempate de janela das RPCs de odds não conhece a `daily`

`get_futebol_fixture_odds` e `get_futebol_odds_board` escolhem a janela corrente assim:

```sql
case when collection_window = 't15m' then 3
     when collection_window = 't1h'  then 2
     else 1 end
```

**`t24h` e `daily` caem os dois no `else 1` e empatam.** Com empate, o `DISTINCT ON` do Postgres
resolve arbitrariamente — e pode virar entre chamadas, sem nenhuma mudança de dado.

Medido em 2026-08-10 no PRD: **27.066 chaves (fixture, casa, mercado, saída) empatadas, em 25
fixtures** — as que já têm `daily` e `t24h` e ainda não têm `t1h`/`t15m`. Para elas, a tela de odds
e o board de odds podem exibir uma odd de até 7 dias atrás em vez da de 24h.

**Não foi causado pela #37.** Nasceu em 07/08 com `tech-lamjav/data-engineering#34`, quando a
`daily` entrou na coleta e este `CASE` não acompanhou. É o mesmo formato do defeito da #37, três
dias mais velho.

Conserto: acrescentar `when collection_window = 't24h' then 2` deslocando os demais, ou melhor,
derivar a prioridade de um lugar só. No dbt esse lugar já existe — o macro
`futebol_janela_prioridade` — mas ele não atravessa para o Postgres, então aqui é duplicação
inevitável e o que resta é **manter as duas listas juntas na mesma mudança**.

## ✅ Gate FECHADO em 20/08: a RPC de escalação filtra fase, e a #38 pode subir

**O gate abaixo está resolvido.** Ele dizia *"não rodar `./build-and-push.sh dbt_futebol` até a
RPC ser corrigida"*, e a correção chegou na **migration 103** (release #271, 19/08). Conferido em
20/08 no PRD com `pg_get_functiondef` — no banco vivo, não no `deploy.sql`, que é a disciplina
que este próprio gate exigia:

```sql
-- Uma fase so, nunca as duas. Prefere a confirmada; cai para a real quando
-- nao houver confirmada. As duas tabelas sao decididas em separado porque
-- discordam entre si.
when v_fix.kickoff_utc <= (now() at time zone 'UTC')
     and count(*) filter (where lineup_phase = 'real') > 0 then 'real'
when count(*) filter (where lineup_phase = 'confirmed') > 0 then 'confirmed'
```

...e os dois sub-selects filtram `where lineup_phase = v_fase_*`.

Duas coisas que valem guardar do conserto:

1. **A regra é por TEMPO, não por existência.** A migration 098 tinha decidido a fase pela
   existência de linhas, e estava errada: nos 154 jogos com as duas fases, a `confirmed` tem
   **2,0 jogadores por jogo** contra **46,5** da `real`. Sob a regra por existência, o campinho
   de jogo encerrado apareceria com dois jogadores.
2. **As duas tabelas decidem em separado**, de propósito, porque discordam entre si — o fato de
   times e o de jogadores não têm garantia de cobrir a mesma fase no mesmo fixture.

O que segue abaixo é o registro do que o gate impedia, mantido porque é o caso de teste de
qualquer mudança futura nessa RPC. **No dia em que a imagem subisse sem a RPC corrigida:**

- `lineups` passa de 2 para **4** elementos nos jogos com as duas fases (279 hoje). O front faz
  `extras.lineups.find(l => l.team_side === 'home')?.formation` sobre array sem ordem — a
  formação exibida vira sorteio entre a anunciada e a que entrou em campo, e pode virar entre
  dois carregamentos da mesma página.
- `lineup_players` **dobra** (275 fixtures hoje): cada jogador desenhado duas vezes no campinho,
  com `is_starter`/`grid` contraditórios entre as duas cópias.

O conserto pedido era, do lado do app (`prop-play-predictor`, escopo do Victor): filtrar
`lineup_phase = 'real'` nos dois sub-selects quando o jogo já terminou e `'confirmed'` antes do
apito, expondo `lineup_phase` na projeção junto — sem ela o front não tem como dizer ao usuário
que está vendo a escalação anunciada e não a que jogou, que é o produto que a #38 destrava.
**Foi exatamente isso que a 103 fez**, incluindo o `lineup_phase` na projeção dos dois blocos.

⚠️ **A spec da #38 afirmava "a aplicação não os consulta".** É falso, e este documento já
registrava isso desde 10/08 — a spec é de 06/08 e não foi revisada depois. A verificação de
grão da spec não substituiu a consulta ao banco vivo do passo 1 abaixo.

## A regra que vale daqui pra frente

Antes de mudar **grão** ou **colunas** de qualquer tabela da allowlist:

1. `SELECT p.proname, pg_get_functiondef(p.oid) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname LIKE '%futebol%'` — no banco vivo.
2. Procure `distinct on`, `jsonb_agg`/`array_agg`, `limit 1` e joins por subconjunto da chave. São as quatro impressões digitais de "assumo uma linha por chave".
3. **Coluna nova ou removida** → migration no Postgres ANTES do deploy da imagem, senão o parity aborta as 21 tabelas. Coluna que a RPC declara no `RETURNS TABLE` exige `DROP FUNCTION` e recriar (Postgres não faz `CREATE OR REPLACE` mudando assinatura).
4. **Tabela nova** → ignorada pelo sync (a allowlist é explícita), então é livre.

## O que isto diz sobre o trabalho na fila

| Ticket | O que faz | Consequência nesta camada |
|---|---|---|
| **#37** (C5) | Janela no grão do de-vig | Precisa de desempate por `janela_usada` em `get_futebol_fixture_value` |
| **#38** (C1) | Duas fases da escalação coexistem | `get_futebol_fixture_extras` duplicaria cada time e cada jogador; a projeção nem expõe `lineup_phase`. `lineup_phase` **já é coluna** nos dois fatos, então não há drift de esquema — só de grão |
| **#40** (C5b) | Coluna `janela_deteccao` no mart | Coluna nova → migration antes do deploy, em **DUAS** tabelas: `futebol.fact_value_opportunities` e `futebol.fact_value_opportunities_hist` (o snapshot copia a linha inteira, então a coluna chega lá no primeiro `dbt snapshot` e o parity acusa as duas). `ALTER TABLE ... ADD COLUMN janela_deteccao text;` nos dois bancos (dev e prd). Nenhuma RPC muda: `get_futebol_value_board` declara o `RETURNS TABLE` coluna a coluna e não lista a nova — o board só passa a exibi-la quando o front pedir |
| **#41** (C3b) | Contador de premissas sem dado | Coluna nova → migration antes do deploy |
| **#87** | Quatro flags de penalidade (`pen_odd_outlier`, `pen_poucas_casas`, `pen_odd_longshot`, `pen_odd_juice`) como `BOOLEAN` no mart | Colunas novas → mesmo caminho da #40: `ALTER TABLE ... ADD COLUMN <flag> boolean;` nas **duas** tabelas (`fact_value_opportunities` e `_hist`) × **dois** bancos, antes do deploy da imagem. **Nenhuma RPC quebra** — verificado no prd em 19/08: as duas que leem o mart o aliasam como `v` e enumeram coluna a coluna, sem `v.*`. E a #87 é o pré-requisito do conserto do lado do app: só com estas colunas no prd o CTE `d` de `get_futebol_fixture_value` (linha ⛔ da tabela acima) vira leitura direta e morre |
| **A1** | Remove `pts_valor`/`pts_corroboracao`/`penalidades` do mart | Colunas removidas **e** declaradas no `RETURNS TABLE` das duas RPCs → `DROP FUNCTION` + recriar |
| **A7** | Tabela nova de funil | Livre — fora da allowlist |
| **Expurgo do board** (ADR 0009, #85) | Mart para de emitir linha de jogo encerrado; passado vem do `hist` | ✅ **ENTREGUE.** **Nenhuma coluna muda** — o filtro é por join com `fact_fixtures`, de propósito, e por isso este passo não precisou de migration nenhuma. O risco aqui era o outro: o parity passa, as RPCs devolvem 200 e o Histórico esvazia em silêncio. Foi por isso que a RPC nova (`get_futebol_value_history`) e o front foram **antes** — os dois no PRD pelo release #271, em 19/08 — e `get_futebol_value_board` **não foi alterada**. `get_futebol_fixture_value` mudou só o corpo (assinatura idêntica → `CREATE OR REPLACE`) |
