---
status: accepted
---

# Insumos medidos viram tabela achatada, com o grão do mercado já dentro

A ADR 0014 fechou a Entrega 1 (sob qual janela cada premissa foi medida) e deixou a Entrega 2
(o valor em si) "deliberadamente não ticketada, pendente de decisão do Victor sobre custo e
mercado inicial". A Entrega 2 aconteceu (AE#153, PR #154): `int_futebol_premissas_1x2` ganhou
`insumos_medidos`, `ARRAY<STRUCT<premissa, insumo, valor FLOAT64>>`. O valor existe em BigQuery
desde então — e nunca saiu de lá. O sync BQ→Postgres (`src/sync/bq_to_postgres.py`,
data-engineering) pula toda coluna `REPEATED`/`RECORD` por regra, a mesma que já exclui
`dim_leagues.coverage` e `evidencias[]`/`avisos[]`. Sem uma cópia escalar, `insumos_medidos`
fica permanentemente do lado errado do sync, e o front continua sem o número que motivou a
Entrega 2 — o caso Goiás × Fortaleza que ficou 11 dias no ar.

Decisão do Victor no ClickUp (`wdx6zf0fq2`/`wdx6zf0nnv`, 15/09/2026): uma tabela comprida,
colunas todas escalares — `fixture_id`, `outcome`, `premissa`, `insumo`, `valor` — um mart novo,
`fact_insumos_medidos`, em vez de achatar em colunas largas (`insumo_valor_s`/`insumo_valor_o`,
a proposta original da #147) ou reconstruir o valor no RPC a partir de outra coluna já
sincronizável. As duas perguntas que ele fez antes de ticketar — o grão bate com o que
`futebol_insumos_medidos()` já gera? existe insumo não-numérico? — vieram limpas: nenhuma
premissa do catálogo (37 premissas, 5 mercados) repete o mesmo insumo duas vezes na mesma
linha, e todo insumo é numérico (o próprio macro já força `CAST(... AS FLOAT64)`, e isso já
roda em produção sem quebrar).

## Por que `market`/`line_value` entram já, com o escopo ainda travado no 1X2

O ticket cobre só o 1X2 — os outros 4 mercados ficam de fora do modelo de dados por enquanto.
Mas as colunas `market` (constante `'1X2'`, pela mesma `futebol_mercados_pontuados()` que
`fact_value_opportunities` já usa) e `line_value` (`NULL` — o 1X2 não tem linha) entram desde a
primeira versão da tabela, não só quando o próximo mercado chegar.

O motivo é o mesmo que já mordeu este repo quatro vezes (ver o contrato de serving das RPCs):
mudar o grão de uma tabela sincronizada depois que ela já está em produção exige coordenar DDL
no Postgres no mesmo dia da mudança, ou o sync trava em silêncio. Declarar o grão final
(`fixture_id, outcome, market, line_value, premissa, insumo`) agora, com duas colunas
constantes, custa uma migration a mais hoje. Declará-lo depois, quando o segundo mercado
entrar, custa uma migration coordenada numa tabela que já está servindo o app.

## Por que mart, não intermediate

`int_futebol_premissas_1x2` já mostra que este repo materializa como tabela física o que vai
sincronizar, esteja a pasta física em `intermediate/` ou em `marts/` — a "camada de valor" já
mistura as duas por este motivo. Mas `fact_insumos_medidos` não é uma transformação a caminho
de outra coisa: é o produto final que o Postgres e o app consomem, do mesmo jeito que
`fact_value_opportunities` e `fact_odds_snapshot` são. Fica em `marts/`.

## O que esta decisão NÃO faz

**Não entra no allowlist do sync.** `FUTEBOL_SYNC_TABLES_ORDERED` (data-engineering,
`src/config.py`) é uma lista manual — a tabela só começa a sincronizar quando alguém a
adiciona lá, em ordem (depois de `int_futebol_premissas_1x2`, da qual depende). Ticket
separado, repo separado.

**Não cria a tabela de destino no Postgres.** `check_schema_parity` não faz
`CREATE TABLE` — ele compara o schema das duas pontas e falha se a tabela não existir do lado
de cá. A migration em `prop-play-predictor` tem de existir **antes** do allowlist entrar em
produção, não depois, ou a primeira passada do sync já acusa toda coluna como
`missing_in_pg`.

**Não cria a RPC de leitura.** Igual à Entrega 2: o mart publica, o front lê — é o próximo
ticket, na quadra do Victor.

**Não entra no selector sozinha.** `workflow_futebol_odds.yml` (data-engineering) enumera
modelo a modelo, em duas listas (`--select` normal e `--full-refresh`) — a tabela nova precisa
entrar nas duas, ou uma delas fica com o modelo faltando sem nenhum erro na hora do deploy.
