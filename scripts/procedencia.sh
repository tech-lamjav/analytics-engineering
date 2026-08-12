#!/bin/bash
# Carimbo de procedência de uma imagem dbt.
#
# Imprime um hash único do CONTEÚDO EM DISCO das paths que carregam comportamento de um
# projeto dbt. O `build-and-push.sh` grava esse hash como env var no Cloud Run Job; o
# detector (.github/workflows/deriva-imagem.yml) recalcula a mesma coisa num checkout limpo
# do master e compara. Divergência = deriva: o que roda em produção não é o que está no
# master.
#
# Uso:
#   scripts/procedencia.sh dbt_futebol
#   scripts/procedencia.sh dbt_nba --paths     # lista as paths declaradas e sai
#
# POR QUE CONTEÚDO EM DISCO, e não `git rev-parse HEAD:<path>`:
# o `docker build` copia o disco, não o HEAD. Um build com alteração não commitada — ou
# feito de um `.claude/worktrees/` numa branch, que é como este repo trabalha — carimbaria
# o hash do master enquanto a imagem carrega outra coisa. O carimbo mentiria na direção
# perigosa ("está fresco" quando não está). Hasheando o disco, um build sujo simplesmente
# aparece como deriva até o código ser mergeado, que é a verdade.
#
# POR QUE ESTAS PATHS, e não a pasta inteira do projeto:
# `analyses/`, `docs/` e `CONTEXT.md` vivem dentro do `COPY dbt_futebol/` e portanto mudam
# a imagem sem mudar o comportamento. Nos 30 dias anteriores a 2026-08-07 houve 116 toques
# em `models` mas também 28 nessas três — hashear a pasta inteira produziria ~28 alarmes
# falsos por mês, e um detector que grita por CONTEXT.md é ignorado em duas semanas.
#
# POR QUE O `profiles.yml` ENTRA PELO BLOCO DO PROJETO, e não como arquivo inteiro (issue #65):
# ele é o único path COMPARTILHADO pelos dois alvos. Hasheado inteiro, um target acrescentado
# para um projeto derruba o carimbo do outro — foi o que aconteceu em 12/08, quando o target
# `taskF` (medição do futebol, PR #61) pôs o dbt_nba em deriva sem que uma linha de NBA tivesse
# mudado desde 26/06. É a mesma classe de alarme falso do parágrafo acima, com o agravante de
# que o remédio sugerido seria um deploy num projeto dormente para calar um alarme que não
# descreve risco nenhum. Hasheando só o bloco `dbt_nba:`/`dbt_futebol:`, mudar o `dev`/`prod`
# de um projeto continua sendo deriva DELE — que é a propriedade que a decisão 2 da ADR 0001
# quis garantir — e o target do vizinho deixa de contar.

set -euo pipefail

# Ordenação e hash precisam ser idênticos entre o build (macOS) e o detector
# (ubuntu-latest). Sem LC_ALL=C a collation difere entre os dois, a ordem das linhas muda,
# o hash combinado muda e o detector fica permanentemente vermelho — parecendo bug
# misterioso em vez de diferença de locale.
export LC_ALL=C

PROJECT_NAME="${1:-}"

if [ -z "$PROJECT_NAME" ]; then
    echo "ERROR: uso: $0 <dbt_futebol|dbt_nba> [--paths]" >&2
    exit 2
fi

# Tabela declarativa: projeto -> paths que carregam comportamento.
# Acrescentar um alvo é acrescentar um ramo aqui (ver Q14 do ADR 0001).
# `requirements.txt`, `profiles.yml` e o Dockerfile entram porque também vão para a imagem
# e mudam o que ela faz (versão do dbt, target do BigQuery, etapas do build).
case "$PROJECT_NAME" in
    dbt_futebol)
        PATHS=(
            dbt_futebol/models
            dbt_futebol/macros
            dbt_futebol/tests
            dbt_futebol/snapshots
            dbt_futebol/dbt_project.yml
            dbt_futebol/packages.yml
            dbt_futebol/package-lock.yml
            requirements.txt
            profiles.yml
            Dockerfile.futebol
        )
        ;;
    dbt_nba)
        PATHS=(
            dbt_nba/models
            dbt_nba/macros
            dbt_nba/tests
            dbt_nba/snapshots
            dbt_nba/seeds
            dbt_nba/dbt_project.yml
            dbt_nba/packages.yml
            dbt_nba/package-lock.yml
            requirements.txt
            profiles.yml
            Dockerfile
        )
        ;;
    *)
        echo "ERROR: projeto desconhecido: $PROJECT_NAME (esperado dbt_futebol ou dbt_nba)" >&2
        exit 2
        ;;
esac

if [ "${2:-}" = "--paths" ]; then
    printf '%s\n' "${PATHS[@]}"
    exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Fail-closed no inventário: como cada projeto declara a própria lista (futebol não tem
# `seeds/`, nba tem), não sobrou caso legítimo de path ausente. Pular em silêncio deixaria
# um erro de digitação na tabela enfraquecer o detector sem avisar — a mesma lógica do
# fail-closed do carimbo ausente.
for p in "${PATHS[@]}"; do
    if [ ! -e "$p" ]; then
        echo "ERROR: path declarada para $PROJECT_NAME nao existe: $p" >&2
        exit 1
    fi
done

# O `profiles.yml` sai da varredura por arquivo e entra pelo bloco do projeto (ver cabeçalho).
# Ele continua declarado em PATHS para que `--paths` o liste e a checagem de existência acima
# o cubra — o que muda é só COMO ele contribui para o hash.
PATHS_VARRIDAS=()
for p in "${PATHS[@]}"; do
    [ "$p" = "profiles.yml" ] || PATHS_VARRIDAS+=("$p")
done

# Extração puramente textual: do `<projeto>:` na coluna 0 até a próxima chave (ou comentário) na
# coluna 0. Sem PyYAML de propósito — o detector roda num ubuntu-latest pelado, e uma dependência
# a mais é uma forma nova de o detector morrer sem falar do que devia falar.
# Fail-closed: bloco ausente (chave renomeada) aborta. Hash de bloco vazio seria um detector
# calado, que é o defeito que a ADR 0001 existe para corrigir.
BLOCO_HASH=$(python3 -c '
import sys

projeto = sys.argv[1]
dentro, bloco = False, []
with open("profiles.yml", encoding="utf-8") as fh:
    for linha in fh:
        if linha.startswith(projeto + ":"):
            dentro = True
        elif dentro and linha[:1] not in (" ", "\t", "\n", "\r"):
            break
        if dentro:
            bloco.append(linha)

if not bloco:
    sys.exit("ERROR: bloco `%s:` nao encontrado em profiles.yml" % projeto)

sys.stdout.write("".join(bloco))
' "$PROJECT_NAME" | git hash-object --stdin)

# `-c` (rastreados) + `-o --exclude-standard` (não rastreados que o .gitignore não cobre):
# juntos, é exatamente o conjunto que o `docker build` copiaria. Um arquivo de modelo novo
# ainda não adicionado ao git entra na imagem e precisa entrar no hash.
#
# O par `<path> <blob>` — e não só o blob — porque nome de arquivo É comportamento no dbt:
# o nome do modelo vem do nome do arquivo. Renomear `int_x.sql` para `int_y.sql` sem mudar
# uma linha muda a tabela materializada, e uma lista de hashes soltos não veria isso.
{
    git ls-files -co --exclude-standard -- "${PATHS_VARRIDAS[@]}" | while IFS= read -r f; do
        # Arquivo rastreado mas apagado do disco: o `docker build` também não o copiaria.
        # Omiti-lo faz o hash refletir o disco, que é o invariante deste script.
        [ -f "$f" ] || continue
        printf '%s %s\n' "$f" "$(git hash-object "$f")"
    done
    # O sufixo `:<projeto>` deixa explícito, para quem depurar o hash, que a entrada é o BLOCO
    # e não o arquivo — os dois nunca dariam o mesmo valor, e a confusão custaria uma hora.
    printf '%s %s\n' "profiles.yml:${PROJECT_NAME}" "$BLOCO_HASH"
} | sort | git hash-object --stdin
