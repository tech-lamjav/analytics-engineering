#!/usr/bin/env python3
"""Confere a transcricao do Teste 2 da Task [0.1] contra o doc que a publicou.

`dbt_futebol/macros/taskf_publicado_01.sql` transcreve para SQL os numeros que
`docs/TASK01_RESULTADOS.md` publicou em prosa. A reconciliacao da celula `base` da task [F]
(issue #51) e a terceira invariante da Costura B (#55) comparam a medicao contra essa
transcricao — entao um digito trocado nela FABRICA uma divergencia que alguem vai investigar
como se fosse achado, e o achado nao existe.

Este script existe para que "a transcricao foi conferida" seja fato reproduzivel em vez de
promessa. Le os dois arquivos, extrai os numeros dos dois lados e compara campo a campo.

Confere os tres recortes que o doc publica, e so eles:

  as 20 de diferenca positiva   linha completa no piso 0 (tabela "Peso medido").
  as 19 de peso zero            so a diferenca no piso 0 (paragrafo corrido).
  as 15 da varredura de piso    diferenca nos pisos 5 e 10 e o n do piso 5 (tabelas
                                "desabam" / "sobrevivem").

Campo que o doc nao publica fica NULL no macro e nao e conferido aqui — e a distincao entre
"bateu" e "nao havia o que comparar" e mantida de proposito.

⚠️ Os nomes dos campos sao LIDOS DO PROPRIO STRUCT<> do macro, nao digitados aqui. Duas razoes:
os nomes das mensagens de divergencia passam a ser os nomes reais das colunas do artefato
conferido, e reordenar os campos dentro do STRUCT deixa de passar despercebido — com uma lista
digitada e ligacao posicional, trocar duas colunas de lugar mantem a contagem e compara os campos
errados, calado, exatamente no script cujo proposito e pegar troca de digito.

Rodar da raiz do repo:

    .venv/bin/python3 scripts/confere_taskf_publicado_01.py

Sai com codigo 1 e lista as divergencias se houver alguma.
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
DOC = RAIZ / "docs" / "TASK01_RESULTADOS.md"
MACRO = RAIZ / "dbt_futebol" / "macros" / "taskf_publicado_01.sql"

# Ordem das colunas da tabela "Peso medido" do doc, DEPOIS de mercado e premissa. Explicita e por
# nome: a ligacao com os valores do macro e feita pelos nomes lidos do STRUCT, nao por posicao.
COLUNAS_TABELA1 = ["n_p0", "a_odd_dava_p0", "aconteceu_p0", "diferenca_p0",
                   "jogos_medios", "pct_amostra_curta", "peso_p0", "peso_p0_k0"]

doc = DOC.read_text(encoding="utf-8")
macro = MACRO.read_text(encoding="utf-8")


def num(s):
    """Numero como o doc escreve: virgula decimal, sinal unicode, negrito."""
    s = s.strip().replace("**", "").replace(",", ".").replace("+", "").replace("−", "-")
    return None if s in ("", "-") else float(s)


# ------------------------------------------------- os nomes dos campos, lidos do STRUCT do macro
struct = re.search(r"STRUCT<(.+?)>\s*$", macro, re.S | re.M)
if not struct:
    sys.exit("nao achei a declaracao STRUCT<> em " + str(MACRO))
campos = [c.strip().split()[0] for c in struct.group(1).split(",")]
if campos[:2] != ["mercado", "premissa"]:
    sys.exit(f"o STRUCT deveria comecar com mercado, premissa — comeca com {campos[:2]}")
campos = campos[2:]

erros = []
faltando = [c for c in COLUNAS_TABELA1 if c not in campos]
if faltando:
    erros.append(f"campos da tabela 1 ausentes do STRUCT do macro: {faltando}")

# ------------------------------------------------------------------- lado do MACRO, por nome
linhas_macro = {}
for m in re.finditer(r"^\s*\('([^']+)',\s*'([^']+)',(.*)\),?\s*$", macro, re.M):
    mercado, premissa, resto = m.group(1), m.group(2), m.group(3)
    vals = [None if v.strip() == "NULL" else float(v) for v in resto.split(",")]
    if len(vals) != len(campos):
        erros.append(f"{mercado}/{premissa}: {len(vals)} valores para {len(campos)} campos")
        continue
    linhas_macro[(mercado, premissa)] = dict(zip(campos, vals))

if len(linhas_macro) != 39:
    erros.append(f"o macro tem {len(linhas_macro)} linhas, e o catalogo tem 39 premissas")

# --------------------------------------------------- doc: as 20 de diferenca positiva
sec = doc.split("### Peso medido")[1].split("As 19 com peso zero")[0]
n_t1 = 0
for mercado, resto in re.findall(
        r"^\|\s*(1X2|Gols|Handicap|BTTS|Dupla Chance)\s*\|(.+)\|\s*$", sec, re.M):
    cels = [c.strip() for c in resto.split("|")]
    premissa = cels[0].replace("`", "")
    n_t1 += 1
    got = linhas_macro.get((mercado, premissa))
    if got is None:
        erros.append(f"FALTA no macro: {mercado}/{premissa}")
        continue
    for campo, cel in zip(COLUNAS_TABELA1, cels[1:1 + len(COLUNAS_TABELA1)]):
        if got.get(campo) != num(cel):
            erros.append(f"{mercado}/{premissa}.{campo}: doc={num(cel)} macro={got.get(campo)}")

# ------------------------------------------------------- doc: as 19 de peso zero
sec19 = doc.split("As 19 com peso zero")[1].split("### O piso de amostra")[0]
pares = re.findall(
    r"`([a-z0-9_]+)`(?:\s*\((Gols|BTTS|1X2|Handicap|Dupla Chance)\))?\s*(−[\d,]+|0,0)", sec19)
for premissa, mercado_doc, dif in pares:
    dif = num(dif)
    achadas = [k for k in linhas_macro
               if k[1] == premissa and linhas_macro[k]["diferenca_p0"] == dif]
    if not achadas:
        erros.append(f"lista-19 {premissa} ({dif}): sem linha no macro com essa diferenca")
    elif mercado_doc and achadas[0][0] != mercado_doc:
        erros.append(f"lista-19 {premissa}: doc diz {mercado_doc}, macro diz {achadas[0][0]}")

# ------------------------------------------------------ doc: a varredura de piso
sec_piso = doc.split("### O piso de amostra")[1].split("### Leitura")[0]
n_piso = 0
for premissa, mercado_doc, resto in re.findall(
        r"^\|\s*`([a-z0-9_]+)`\s*(?:\((Gols|BTTS)\))?\s*\|(.+)\|\s*$", sec_piso, re.M):
    cels = [c.strip() for c in resto.split("|")]
    if len(cels) < 4:
        continue
    n_piso += 1
    d0 = num(cels[0])
    n5 = num(cels[3].split("→")[1]) if "→" in cels[3] else None
    cands = [k for k in linhas_macro
             if k[1] == premissa and (not mercado_doc or k[0] == mercado_doc)
             and linhas_macro[k]["diferenca_p0"] == d0]
    if not cands:
        erros.append(f"piso {premissa}: nenhuma linha do macro com diferenca_p0={d0}")
        continue
    got = linhas_macro[cands[0]]
    for campo, v in (("diferenca_p5", num(cels[1])),
                     ("diferenca_p10", num(cels[2])),
                     ("n_p5", n5)):
        if got.get(campo) != v:
            erros.append(f"{cands[0]}.{campo}: doc={v} macro={got.get(campo)}")

print(f"campos lidos do STRUCT       {len(campos)} ({', '.join(campos)})")
print(f"macro                        {len(linhas_macro)} linhas")
print(f"doc, as 20 positivas         {n_t1} linhas x {len(COLUNAS_TABELA1)} campos")
print(f"doc, as 19 de peso zero      {len(pares)} premissas")
print(f"doc, a varredura de piso     {n_piso} linhas x 3 campos")
print()

if erros:
    print(f"!!! {len(erros)} DIVERGENCIAS")
    for e in erros:
        print("  -", e)
    sys.exit(1)

print("OK — a transcricao bate com o doc em todos os campos publicados")
