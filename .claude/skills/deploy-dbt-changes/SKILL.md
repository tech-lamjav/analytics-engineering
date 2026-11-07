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
.sql editado ──► build-and-push.sh ──► push git-<sha> + latest ──► jobs update --image @sha256 ──► tag live ──► job roda o código novo
                 (um comando só; tudo isto acontece dentro dele)
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

### 2. Rebuild + deploy da imagem (obrigatório se qualquer arquivo do projeto dbt mudou)

De `analytics-engineering/`:

```bash
./build-and-push.sh dbt_futebol   # ou: ./build-and-push.sh dbt_nba
```

Convenção do script: `dbt_futebol` → `Dockerfile.futebol` → repo `dbt-futebol-repo`,
imagem `dbt-futebol`. `dbt_nba` (default sem argumento) → `Dockerfile`.

O script faz tudo num comando só, nesta ordem:

1. build com `--provenance=false --sbom=false` (uma versão por build no registry);
2. push das tags `git-<sha>` (com `-sujo` se havia alteração não commitada) e `latest`;
3. lê o digest do registry e **aborta** se vier ilegível;
4. `gcloud run jobs update --image <pacote>@sha256:<digest>` + carimbo de procedência;
5. só então move a tag `live` para esse digest.

### 3. NÃO re-aponte o job na mão

> ⚠️ **Não rode `gcloud run jobs update --image ...:latest`.** Antes era o passo mais
> esquecido; agora está dentro do `build-and-push.sh`, e rodá-lo na mão é **prejudicial**:
> o job passa a rodar um digest sem a tag `live`, e a cleanup policy do Artifact Registry
> (repos `dbt-*-repo`: mantém `live`, `latest` e as 9 versões mais novas, apaga o resto com
> mais de 30 dias) pode apagar a imagem que o job roda. Se precisar re-apontar (rollback),
> mova a `live` junto:
>
> ```bash
> PKG=us-east1-docker.pkg.dev/smartbetting-dados/dbt-futebol-repo/dbt-futebol
> gcloud run jobs update dbt-futebol --region us-east1 --image "$PKG@sha256:<digest>"
> gcloud artifacts docker tags add "$PKG@sha256:<digest>" "$PKG:live"
> ```
>
> Detalhes e runbook da policy: `data-engineering/infra/README.md`.

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
- [ ] `build-and-push.sh <projeto>` concluído (já inclui `jobs update` por digest e a tag `live`)
- [ ] **Nenhum** `gcloud run jobs update --image` manual (ver passo 3)
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
