"""Diz quais modelos alterados num PR alimentam tabelas sincronizadas para o Postgres.

POR QUE ISTO EXISTE:
mudar coluna de um modelo que o sync copia exige o DDL correspondente no Postgres no MESMO
deploy. Sem isso o parity check pré-flight aborta o sync inteiro — as 22 tabelas, nos dois
ambientes — até alguém aplicar o DDL à mão. Aconteceu 4 vezes; na última (PR #122, colunas
`linha_subindo`/`linha_descendo`) o serving ficou 3 dias congelado. Nas quatro o gatilho foi
o mesmo: mudou o mart, ninguém olhou o Postgres.

Isto NÃO valida nada, e não dá para validar aqui: no momento do PR o modelo ainda não rodou,
então o BigQuery ainda tem as colunas velhas e um parity check daria verde. Isto marca — põe
o aviso na frente de quem revisa, no momento em que a mudança ainda é barata.

POR QUE A LISTA VEM DO data-engineering EM TEMPO DE EXECUÇÃO:
a allowlist canônica é `FUTEBOL_SYNC_TABLES_ORDERED` em `src/config.py` do
`data-engineering`. Uma cópia aqui derivaria — que é exatamente a doença que este aviso
existe para tratar. Os dois repos são públicos, então basta ler o raw. Falha de rede derruba
o job de propósito: marcar a menos seria pior que não marcar.
"""
import os
import re
import sys
import urllib.request

CONFIG_URL = (
    "https://raw.githubusercontent.com/tech-lamjav/data-engineering/master/src/config.py"
)
LISTA = "FUTEBOL_SYNC_TABLES_ORDERED"


def allowlist(url: str = CONFIG_URL) -> set[str]:
    with urllib.request.urlopen(url, timeout=30) as r:
        fonte = r.read().decode("utf-8")

    bloco = re.search(rf"^{LISTA}\s*=\s*\[(.*?)^\]", fonte, re.S | re.M)
    if not bloco:
        raise RuntimeError(f"{LISTA} não encontrada em {url} — o config mudou de forma?")

    tabelas = set(re.findall(r'"([^"]+)"', bloco.group(1)))
    if not tabelas:
        raise RuntimeError(f"{LISTA} veio vazia — parsing quebrado, não allowlist vazia.")
    return tabelas


def afetadas(arquivos, tabelas: set[str]) -> list[str]:
    """Modelo alterado cujo nome está na allowlist. O nome do arquivo é o nome da tabela."""
    achadas = set()
    for caminho in arquivos:
        caminho = caminho.strip()
        if not caminho.endswith(".sql"):
            continue
        nome = os.path.basename(caminho)[: -len(".sql")]
        if nome in tabelas:
            achadas.add(nome)
    return sorted(achadas)


def main():
    arquivos = sys.stdin.read().splitlines()
    try:
        tabelas = allowlist()
    except Exception as e:
        print(f"ERRO ao ler a allowlist: {e}", file=sys.stderr)
        return 2

    encontradas = afetadas(arquivos, tabelas)
    for t in encontradas:
        print(t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
