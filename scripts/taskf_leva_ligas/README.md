# Medição do efeito retroativo das ligas AR/CO/PE/MX no PIT

Reproduz a medição registrada em `docs/TASKF_RESULTADOS.md`, seção "Leva AR/CO/PE/MX — efeito retroativo no PIT".
É o portão antes do primeiro backfill das ligas Argentina (128), Colômbia (239), Peru (281) e Liga MX (262).

## Por que isto não é só ligar uma var

Na DE#95 (amistosos) o raw já tinha os jogos e a var `taskf_incluir_amistosos` bastava. Aqui os fixtures das 4 ligas
**não estão no landing** (o cadastro ainda não foi feito). A fonte do cenário "depois" é uma tabela nativa
`futebol_taskF.leva8_raw_fixtures`, montada a partir da API. **Nunca grave esses arquivos no bucket do landing:** a
external table é um wildcard e o próximo diário publicaria as ligas em produção com `competition = 'unknown'`.

## Ordem

| Passo | Script | Escreve? |
|---|---|---|
| 1 | `01_baixa_fixtures.py` (8 chamadas à API-Football) | só arquivos locais |
| 2 | `02_monta_ndjson.py` | só arquivos locais |
| 3 | `03_carrega_raw_fixtures.sh` | `futebol_taskF.leva8_raw_fixtures` |
| 4 | `04_roda_builds.sh checagens` e depois `completo` | `futebol_taskF` (ver abaixo) |
| 5 | `05_compara.sh` | só leitura |

Pré-requisitos: `gcloud auth login` **e** `gcloud auth application-default login` (o `bq` e o dbt travam em silêncio
com a autenticação vencida), `bq` e `dbt` no PATH (ou `DBT_BIN`), `API_FOOTBALL_KEY` para o passo 1.
Saídas e logs em `$TASKF_LEVA_OUT` (padrão `/tmp/taskf_leva`).

## O que o passo 4 escreve, e como volta

- Saídas dos modelos `stg_futebol_fixtures` (view), `fact_fixtures` e `int_futebol_team_form_pit` no `futebol_taskF`,
  durante os 3 builds (`2025_2026`, `2026` e o baseline `antes`), sempre `--full-refresh` e sem testes.
- Tabelas `leva8_bak_*` (backup), `leva8_pit_*` e `leva8_fixtures_*` (snapshots).
- Nunca escreve no dataset `futebol`, no GCS, nem em `taskf_teste2*`, `taskf_pit_por_celula*` e `*_ancora`.
- **Restauração exata:** um `trap` devolve `fact_fixtures` e `int_futebol_team_form_pit` por `bq cp` a partir dos
  backups (preserva partição e cluster) e recria a view com a definição original, mesmo se um build falhar. Um rebuild
  default **não** restaura: ele refrescaria o `taskF` para hoje.
- **Guarda de concorrência:** o `taskF` é compartilhado com quem mede âncora e Teste 2. O script recusa rodar se
  houve escrita alheia na última hora. A guarda não distingue operadores: uma execução sua deste mesmo script bloqueia
  a seguinte por uma hora. Se acabou de rodar, espere ou confira com `INFORMATION_SCHEMA.JOBS_BY_PROJECT` o que ela viu.
- Recusa também se o `taskF` já tiver linhas das 4 ligas (execução anterior interrompida): restaure antes.

## Como ler o resultado

- A proxy é a taxa de vitória PIT (`wins_total / played_total`) em pp. **Não é a unidade da régua de 0,25 pp**
  (`aconteceu_p*` das premissas); as razões são ordem de grandeza.
- O grupo de controle (`controle_lib_sud`, `controle_outras`) tem de dar delta **exato 0**. Qualquer outro valor é drift
  de raw entre os builds (o `fixtures-live` roda a cada 15 min), não efeito.
- Todo delta é "cenário contra baseline `antes`", porque o rebuild default não é igual ao backup (o raw avançou).
- A Liga MX dá n = 0 por construção: nenhum clube mexicano joga Libertadores ou Sudamericana.

## Limitações conhecidas

- O unit test `stg_fixtures_insumo_so_entra_a_partir_do_corte` falha com a var **ligada** (o mock não tem
  `total_fixtures` e `mode`); com a var em default ele não muda. Por isso os builds usam
  `--exclude-resource-type test unit_test`.
- A medição cobre só `int_futebol_team_form_pit`. As fontes de histórico próprias dos mercados e os cinco modelos de
  premissa não foram rodados nos cenários.
- Os scripts 01 e 03 não foram executados de ponta a ponta na sessão que os versionou. O 02 foi (reproduz byte a byte o
  NDJSON carregado na medição original), assim como o `checagens` do 04 e o 05 (reproduz a matriz de 84 linhas).
- O modo `completo` do 04 **não foi executado nesta versão**. A lógica é a do script que rodou a medição em 01/10 (3
  builds, snapshots e restauração por `trap`, que funcionou), mas esta versão é autocontida: ela própria faz o backup
  (`leva8_bak_*`) e salva a definição da view, que antes eram passos manuais. Essas duas partes são novas. Rode primeiro
  o `checagens` e acompanhe a primeira execução.
