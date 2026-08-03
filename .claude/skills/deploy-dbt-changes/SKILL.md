---
name: deploy-dbt-changes
description: Colocar em produção uma mudança em modelo dbt do dbt_futebol ou dbt_nba. Use SEMPRE que editar/criar/renomear um .sql ou .yml em analytics-engineering/dbt_futebol/models ou dbt_nba/models e a mudança precisar valer em produção (GCP Cloud Run Job + Workflows). Também use ao investigar "rodei o dbt mas o BigQuery não mudou", "o workflow deu SUCCEEDED mas a tabela está velha", PARTIAL_FAILURE em workflow-futebol-*, ou antes de dizer que um deploy está concluído. Editar o modelo NÃO é deployar — a imagem Docker é o artefato.
---

# Deploy de mudanças no dbt (futebol / NBA)

## O modelo mental

Produção **não lê seus arquivos**. O que roda no GCP é uma **imagem Docker** com o
projeto dbt copiado pra dentro (`/app/dbt_futebol`). Editar o `.sql` e rodar `dbt run`
local muda o BigQuery *naquele momento*, mas o job agendado continua rodando o código
**antigo** até a imagem ser reconstruída e o job re-apontado.

```
.sql editado ──► build-and-push.sh ──► imagem :latest ──► gcloud run jobs update ──► job roda o código novo
                                                              ▲
                            (sem este passo, o job fica preso no digest antigo)
```

E, em paralelo, **qual** modelo roda é decidido pelo `--select` hardcoded no YAML do
workflow, que vive em **outro repo** (`data-engineering`) e precisa de deploy próprio.

## Layout (três repos git independentes)

A raiz `smartbetting/` **não é um repo**. São três:

| Caminho | Repo | Contém |
|---|---|---|
| `analytics-engineering/` | sim | projetos dbt, `build-and-push.sh`, Dockerfiles |
| `data-engineering/` | sim | `workflow_*.yml`, `scripts/deploy_workflows.sh`, extractors |
| `prop-play-predictor/` | sim | app |

Commits e PRs são por repo — uma mudança de modelo + workflow são **dois** commits.

## Procedimento

### 1. Validar local antes de qualquer coisa

De dentro de `analytics-engineering/dbt_futebol/` (o `dbt` não está no PATH):

```bash
DBT_PROFILES_DIR=.. ../.venv/bin/dbt build --select +nome_do_modelo
```

> ⚠️ **`dev` e `prod` apontam pro MESMO dataset** (`futebol` / `nba`) no
> `profiles.yml`. Não existe sandbox: rodar local **escreve em produção**. Trate
> qualquer `dbt run` como uma ação em prod.

### 2. Rebuild da imagem (obrigatório se qualquer arquivo do projeto dbt mudou)

De `analytics-engineering/`:

```bash
./build-and-push.sh dbt_futebol   # ou: ./build-and-push.sh dbt_nba
```

Convenção do script: `dbt_futebol` → `Dockerfile.futebol` → repo `dbt-futebol-repo`,
imagem `dbt-futebol:latest`. `dbt_nba` (default sem argumento) → `Dockerfile`.

### 3. Re-apontar o Cloud Run Job — **o passo mais esquecido**

```bash
gcloud run jobs update dbt-futebol \
  --image us-east1-docker.pkg.dev/smartbetting-dados/dbt-futebol-repo/dbt-futebol:latest \
  --region us-east1
```

**Por que é necessário mesmo com a tag `:latest`:** o Cloud Run resolve a tag para um
**digest** no momento do deploy e fica preso nele. Push de um novo `:latest` não muda
nada sozinho. Sem este passo o job roda o código antigo **sem erro nenhum** — é a
falha silenciosa mais comum aqui.

### 4. Modelo NOVO? Adicione ao `--select` do workflow

O `--select` é hardcoded em `containerOverrides.args` no YAML. Ache qual workflow
precisa mudar (não decore — verifique):

```bash
cd ../data-engineering
grep -ln "modelo_vizinho_ja_existente" workflow_*.yml
```

Adicione o modelo novo ao array de `args` no lugar certo da ordem (o `--select` do
`workflow_futebol_odds.yml` é **sem `+`**, enxuto e ordenado por dependência), e então:

```bash
./scripts/deploy_workflows.sh workflow-futebol-odds
```

> ⚠️ **Editar o YAML local não muda o workflow live.** Sem `deploy_workflows.sh`, o
> Scheduler continua disparando a versão antiga. Segunda falha silenciosa mais comum.

Workflows existentes: `workflow-data-engineering`, `workflow-injury-report`,
`workflow-bets`, `workflow-futebol`, `workflow-futebol-lineups`,
`workflow-futebol-team-stats`, `workflow-futebol-odds`,
`workflow-futebol-predictions`, `workflow-futebol-injuries`,
`workflow-futebol-sync`, `workflow-daily-summary`.

### 5. Verificar — e desconfiar do exit code

```bash
gcloud run jobs execute dbt-futebol --region us-east1 \
  --args="dbt,run,--select,+nome_do_modelo,--project-dir,/app/dbt_futebol,--profiles-dir,/app/.dbt,--target,prod" \
  --wait
```

> ⚠️ `gcloud run jobs execute` **retorna exit 0 mesmo com `ERROR >= 1` no dbt**. O
> exit code não prova nada. Abra o log e procure a linha `Done. PASS=... ERROR=0`.
> Idem para o Workflow: ele **engole erros de fase e retorna `SUCCEEDED`** mesmo com
> `PARTIAL_FAILURE` dentro.

> ⚠️ `--args` do `gcloud` **rejeita token duplicado**: não dá pra passar `--select`
> duas vezes numa execução manual (o Workflow via API aceita, o gcloud não). Valide
> com **um único** `--select`.

## Checklist de "deployado de verdade"

- [ ] `dbt build` local verde (`ERROR=0`), ciente de que já escreveu em prod
- [ ] `build-and-push.sh <projeto>` concluído
- [ ] `gcloud run jobs update` executado (**não pule por causa do `:latest`**)
- [ ] Modelo novo adicionado ao `--select` do workflow certo **e** `deploy_workflows.sh` rodado
- [ ] Execução verificada **no log** (`Done. PASS=`), não pelo exit code
- [ ] Commit nos **dois** repos, se ambos mudaram

## Armadilhas conhecidas

**`materialized` divergente entre código e BigQuery.** Se o modelo está como `view` no
código mas existe como `table` no BQ (ou vice-versa), o dbt falha — e o workflow
devolve `SUCCEEDED` mascarando isso. Aconteceu com `int_futebol_odds_devig` e
`int_futebol_premissas_1x2`. Ao criar/alterar modelo, confirme que o
`materialized` bate com o que já existe no dataset. Alguns modelos **precisam** ser
`table`: o sync BQ→Supabase usa `list_rows()`, que não lê view.

**Conta gcloud errada.** Confirme com `gcloud config get-value account` antes de
deployar — há mais de uma conta configurada nesta máquina e a errada dá 403 ou, pior,
silêncio.

**Coleta de odds é forward-only.** Não dá pra reconstruir janelas de jogos passados. Um
deploy atrasado de modelo de odds significa dados perdidos, não adiáveis.

## O que este fluxo NÃO é

A skill `dbt:troubleshooting-dbt-job-errors` é para **jobs do dbt Cloud/platform**
(Admin API, run logs da plataforma). Este projeto é **dbt Core** rodando em Cloud Run
Job — aquela skill não se aplica aqui.
