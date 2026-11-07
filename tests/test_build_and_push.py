"""Guarda do `build-and-push.sh` (tags e ordem do deploy da imagem dbt).

Roda o script inteiro numa árvore falsa, com `docker` e `gcloud` de mentira no PATH que só
anotam cada chamada num log em ordem. Nada toca o registry nem o Cloud Run.

O que precisa ficar preso:
- build com `--provenance=false --sbom=false` (sem attestation, uma versão por build);
- tags `git-<sha>` e `latest` no push, e NUNCA `live` no push;
- `jobs update --image <pacote>@sha256:<digest lido do registry>`;
- `live` movida só DEPOIS do `jobs update`;
- digest ilegível aborta ANTES do `jobs update`.

Este repositório não tem CI de pytest: rode à mão com qualquer pytest (ex.: o .venv do
data-engineering): `../data-engineering/.venv/bin/python3 -m pytest tests/test_build_and_push.py`.
"""
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
SCRIPT = REPO_ROOT / "build-and-push.sh"
DIGEST = "sha256:" + "ab" * 32
PACOTE = "us-east1-docker.pkg.dev/smartbetting-dados/dbt-futebol-repo/dbt-futebol"

GCLOUD_STUB = r"""#!/bin/bash
echo "gcloud $*" >> "$SEQ_LOG"
case "$1 $2" in
    "auth print-access-token") echo "token-falso"; exit 0 ;;
esac
if [ "$1 $2 $3 $4" = "artifacts docker images describe" ]; then
    [ -n "${STUB_DIGEST_VAZIO:-}" ] && exit 0
    echo "$STUB_DIGEST"
    exit 0
fi
exit 0
"""

DOCKER_STUB = r"""#!/bin/bash
if [ "$1" = "login" ]; then cat >/dev/null; exit 0; fi
echo "docker $*" >> "$SEQ_LOG"
exit 0
"""

PROCEDENCIA_STUB = r"""#!/bin/bash
if [ "${2:-}" = "--paths" ]; then echo "dbt_futebol"; exit 0; fi
echo "hash-carimbo-falso"
"""


@pytest.fixture
def arvore(tmp_path):
    root = tmp_path / "ae"
    (root / "scripts").mkdir(parents=True)
    (root / "dbt_futebol").mkdir()
    (root / "dbt_futebol" / "modelo.sql").write_text("select 1\n")
    shutil.copy2(SCRIPT, root / "build-and-push.sh")
    (root / "Dockerfile.futebol").write_text("FROM scratch\n")
    (root / "scripts" / "procedencia.sh").write_text(PROCEDENCIA_STUB)
    (root / "scripts" / "procedencia.sh").chmod(0o755)
    git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(git + ["add", "."], cwd=root, check=True)
    subprocess.run(git + ["commit", "-qm", "x"], cwd=root, check=True)
    stubs = tmp_path / "stubs"
    stubs.mkdir()
    for nome, corpo in (("gcloud", GCLOUD_STUB), ("docker", DOCKER_STUB)):
        (stubs / nome).write_text(corpo)
        (stubs / nome).chmod(0o755)
    return root, stubs


def rodar(arvore, **extra):
    root, stubs = arvore
    log = root.parent / "seq.log"
    env = {
        "PATH": f"{stubs}{os.pathsep}{os.environ['PATH']}",
        "HOME": str(root),
        "SEQ_LOG": str(log),
        "STUB_DIGEST": DIGEST,
        **extra,
    }
    r = subprocess.run(["bash", "build-and-push.sh", "dbt_futebol"], cwd=root, env=env,
                       capture_output=True, text=True)
    linhas = log.read_text().splitlines() if log.exists() else []
    sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=root,
                         capture_output=True, text=True).stdout.strip()
    return r, linhas, sha


def _indice(linhas, prefixo):
    achados = [i for i, l in enumerate(linhas) if l.startswith(prefixo)]
    assert len(achados) == 1, (prefixo, linhas)
    return achados[0]


def test_build_sem_attestation_e_com_tags_git_e_latest(arvore):
    r, linhas, sha = rodar(arvore)
    assert r.returncode == 0, r.stdout + r.stderr

    build = linhas[_indice(linhas, "docker build")]
    assert "--provenance=false" in build and "--sbom=false" in build
    assert f"-t {PACOTE}:git-{sha} " in build
    assert f"-t {PACOTE}:latest " in build
    assert ":live" not in build

    pushes = [l for l in linhas if l.startswith("docker push")]
    assert pushes == [f"docker push {PACOTE}:git-{sha}", f"docker push {PACOTE}:latest"]


def test_job_recebe_o_digest_e_live_vem_depois_do_update(arvore):
    r, linhas, sha = rodar(arvore)
    assert r.returncode == 0, r.stdout + r.stderr

    i_describe = _indice(linhas, "gcloud artifacts docker images describe")
    assert f"{PACOTE}:git-{sha}" in linhas[i_describe]
    i_update = _indice(linhas, "gcloud run jobs update")
    assert f"--image={PACOTE}@{DIGEST}" in linhas[i_update]
    assert "PROCEDENCIA_HASH=hash-carimbo-falso" in linhas[i_update]
    i_live = _indice(linhas, "gcloud artifacts docker tags add")
    assert linhas[i_live] == f"gcloud artifacts docker tags add {PACOTE}@{DIGEST} {PACOTE}:live --quiet"
    assert i_describe < i_update < i_live


def test_disco_sujo_marca_a_tag_git(arvore):
    root, _ = arvore
    (root / "dbt_futebol" / "modelo.sql").write_text("select 2\n")
    r, linhas, sha = rodar(arvore)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"-t {PACOTE}:git-{sha}-sujo " in linhas[_indice(linhas, "docker build")]


def test_digest_ilegivel_aborta_antes_do_jobs_update(arvore):
    r, linhas, _ = rodar(arvore, STUB_DIGEST_VAZIO="1")
    assert r.returncode != 0
    assert "NAO foi atualizado" in r.stderr
    assert not any(l.startswith("gcloud run jobs update") for l in linhas)
    assert not any(l.startswith("gcloud artifacts docker tags") for l in linhas)
