#!/usr/bin/env python3
"""Transforma os JSONs de /fixtures em NDJSON no formato de linha do raw_futebol_fixtures: um
fixture por linha, o item da API como veio mais os campos que o extractor acrescenta
(mode, total_fixtures, requested_league_id, requested_season, loaded_at). Todos os status entram
(inclusive NS): quem filtra o que conta como histórico é o modelo (futebol_jogo_encerrado).

Uso:
    python3 scripts/taskf_leva_ligas/02_monta_ndjson.py [diretorio_cache] [arquivo_saida]

Padrões: $TASKF_LEVA_OUT/cache e $TASKF_LEVA_OUT/leva8_raw_fixtures.ndjson.
"""
import datetime
import json
import os
import sys

LIGAS = (128, 239, 281, 262)
TEMPORADAS = (2025, 2026)
BASE = os.environ.get("TASKF_LEVA_OUT", "/tmp/taskf_leva")
CACHE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BASE, "cache")
SAIDA = sys.argv[2] if len(sys.argv) > 2 else os.path.join(BASE, "leva8_raw_fixtures.ndjson")


def main() -> int:
    carregado_em = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")
    total = 0
    contagens = {}
    with open(SAIDA, "w") as out:
        for liga in LIGAS:
            for temporada in TEMPORADAS:
                arquivo = os.path.join(CACHE, f"A_fixtures_league{liga}_season{temporada}.json")
                resposta = json.load(open(arquivo))["response"]
                for item in resposta:
                    linha = dict(item)
                    linha["mode"] = "backfill" if temporada == 2025 else "current"
                    linha["total_fixtures"] = len(resposta)
                    linha["requested_league_id"] = liga
                    linha["requested_season"] = temporada
                    linha["loaded_at"] = carregado_em
                    out.write(json.dumps(linha, ensure_ascii=False) + "\n")
                    total += 1
                contagens[(liga, temporada)] = len(resposta)
    for (liga, temporada), n in contagens.items():
        print(f"{liga}/{temporada}: {n}")
    print(f"linhas={total} loaded_at={carregado_em} arquivo={SAIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
