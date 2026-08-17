{{ config(tags=['guarda']) }}
-- GUARDA DE REPRODUTIBILIDADE DAS PREMISSAS (#78) — nenhum modelo de premissa pode usar `AVG()`
-- nem `APPROX_QUANTILES()`.
--
-- POR QUE UMA GUARDA DE TEXTO, E NÃO DE DADO. O defeito que ela impede não aparece em UMA
-- execução: `AVG()` no BigQuery não é bit-reproduzível entre execuções, porque a agregação é
-- paralelizada e as médias PARCIAIS de cada shard são fundidas em ponto flutuante. Qualquer
-- guarda que compare números de um build só vê a média certa; o erro só existe ENTRE builds. E
-- uma guarda que comparasse dois builds seria ela própria instável — daria vermelho de vez em
-- quando, que é o pior tipo de guarda. Sobra checar a CONSTRUÇÃO, que é onde o defeito mora e
-- onde ele é determinístico.
--
-- O QUE ELA IMPEDE, MEDIDO. Com o insumo CONGELADO e o MESMO SQL, seis execuções davam
-- `superioridade_xg` em 4019/4020/4021/4022 linhas e `ritmo_alto` em 16684 a 16702 (±15 por
-- build). As linhas que viravam estavam a UM ULP do limiar da premissa. O estrago não é no board
-- (±8 pontos numa soma de ~184 mil): é em MEDIÇÃO — quem comparasse dois builds na [A] ou na [F]
-- veria ±1 linha e não teria como saber, olhando o número, que aquilo é ruído do instrumento e
-- não efeito da mudança sob teste.
--
-- A FORMA CERTA é `SAFE_DIVIDE(SUM(x), COUNT(x))`, com a soma EXATA — inteiro, ou ponto fixo em
-- NUMERIC quando o insumo é fracionário. `SUM` independe da ordem e depois há uma divisão só.
-- Medido sobre 15.556 inteiros: `AVG` deu cinco valores distintos em seis execuções,
-- `SAFE_DIVIDE(SUM, COUNT)` deu um só. Não é privilégio de coluna fracionária — a primeira
-- explicação foi essa e ela é falsa.
--
-- `APPROX_QUANTILES` entra na mesma lista por motivo irmão: é um SKETCH, e o resultado depende de
-- como a execução foi paralelizada. Já estava medido na #57 e já tinha cura escrita
-- (`macros/taskf_mediana.sql`); o que faltava era ela valer na produção, e não só nas análises da
-- task [F]. Foi assim que o `ritmo_alto` passou meses instável sem ninguém reparar.
--
-- ⚠️ A varredura é sobre o código com os comentários REMOVIDOS — os dois tipos. Sem isso esta
-- guarda acusaria a si mesma e aos comentários que explicam a correção, que citam `AVG()` pelo
-- nome dezenas de vezes. `{#- ... -#}` sai primeiro (pode conter `--` dentro), depois `--` até o
-- fim da linha.

{%- set proibidos = ['AVG(', 'APPROX_QUANTILES('] -%}
{%- set achados = [] -%}

{%- if execute -%}
  {%- for node in graph.nodes.values() -%}
    {%- if node.resource_type == 'model' and node.name.startswith('int_futebol_premissas_') -%}
      {%- set sem_jinja = modules.re.sub('(?s)\{#.*?#\}', ' ', node.raw_code) -%}
      {%- set codigo    = modules.re.sub('--[^\n]*', ' ', sem_jinja) -%}
      {%- for termo in proibidos -%}
        {%- if termo in codigo -%}
          {%- do achados.append(node.name ~ ' usa ' ~ termo ~ ')') -%}
        {%- endif -%}
      {%- endfor -%}
    {%- endif -%}
  {%- endfor -%}
{%- endif -%}

-- Uma linha por violação; zero linhas = verde. O array vazio precisa de tipo explícito, senão o
-- BigQuery não sabe montar o UNNEST de um literal `[]`.
SELECT ocorrencia
FROM UNNEST(
{%- if achados %}
    {{ achados | tojson }}
{%- else %}
    CAST([] AS ARRAY<STRING>)
{%- endif %}
) AS ocorrencia
