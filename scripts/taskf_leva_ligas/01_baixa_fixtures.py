#!/usr/bin/env python3
"""Baixa os /fixtures das 4 ligas da leva (Argentina 128, Colômbia 239, Peru 281, Liga MX 262),
temporadas 2025 e 2026, para o diretório de saída. 8 chamadas à API-Football, com pausa de 0,5 s
(a API derruba rajadas). Reaproveita o que já estiver no diretório.

Por que isto existe: as 4 ligas NÃO estão no landing (o cadastro ainda não foi feito), então o
cenário "depois" da medição do efeito retroativo no PIT não pode ser lido do raw de produção.
NUNCA grave o resultado no bucket do landing: a external table é um wildcard e o próximo diário
publicaria as ligas em produção com competition='unknown'.

Uso:
    API_FOOTBALL_KEY=... python3 scripts/taskf_leva_ligas/01_baixa_fixtures.py [diretorio_saida]

O diretório padrão é $TASKF_LEVA_OUT/cache (padrão /tmp/taskf_leva/cache).
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

LIGAS = (128, 239, 281, 262)
TEMPORADAS = (2025, 2026)
SAIDA = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.environ.get("TASKF_LEVA_OUT", "/tmp/taskf_leva"), "cache"
)


def main() -> int:
    chave = os.environ.get("API_FOOTBALL_KEY")
    if not chave:
        print("defina API_FOOTBALL_KEY no ambiente (a chave fica em data-engineering/.env)", file=sys.stderr)
        return 2
    os.makedirs(SAIDA, exist_ok=True)
    chamadas = 0
    for liga in LIGAS:
        for temporada in TEMPORADAS:
            destino = os.path.join(SAIDA, f"A_fixtures_league{liga}_season{temporada}.json")
            if os.path.exists(destino):
                print(f"já existe: {destino}")
                continue
            url = "https://v3.football.api-sports.io/fixtures?" + urllib.parse.urlencode(
                {"league": liga, "season": temporada}
            )
            req = urllib.request.Request(url, headers={"x-apisports-key": chave})
            with urllib.request.urlopen(req, timeout=60) as resp:
                dados = json.load(resp)
            if dados.get("errors"):
                print(f"erro da API para {liga}/{temporada}: {dados['errors']}", file=sys.stderr)
                return 1
            with open(destino, "w") as f:
                json.dump(dados, f)
            chamadas += 1
            print(f"{liga}/{temporada}: {len(dados.get('response', []))} fixtures")
            time.sleep(0.5)
    print(f"{chamadas} chamadas feitas; arquivos em {SAIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
