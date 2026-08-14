{#- Gera a lista de PREMISSAS CEGAS de um modelo — as que se aplicavam à linha, não acenderam,
    e não acenderam porque faltou insumo. Derivada do mapa futebol_insumos_premissa(), e
    chamada de dentro do modelo, onde as colunas da CTE `metrics` ainda existem: no SELECT
    final elas já viraram booleano e a informação sumiu.

    O contador do board é o tamanho desta lista (premissas_sem_dado = ARRAY_LENGTH). A lista em
    si fica exposta porque é o que torna o número auditável — e porque a Dupla Chance a lê do
    1X2 para herdar a cegueira das premissas que reusa, em vez de herdar só o FALSE delas.

    Por que gerado e não escrito à mão: o contador manual fica correto no dia em que é escrito
    e apodrece na premissa seguinte, e esquecer é silencioso (ADR 0003). Gerando do mapa, uma
    premissa nova só precisa ser declarada — e se não for, a guarda
    assert_premissas_insumo_declarado fica vermelha antes de o contador mentir.

    TRÊS CONDIÇÕES por premissa, e nenhuma das três é decorativa:

      aplicável        — premissa do outro lado da linha (favorito/azarão, Over/Under, Yes/No)
                         não está cega, está fora de jogo. Sem esta condição toda linha de
                         Handicap contaria 3 ou 4, sempre, e o contador viraria ruído.
      não acesa        — premissa que ACENDEU não pode ser contada como sem dado, e sem esta
                         condição ela seria: `lado_coberto_forte` é um OR de dois insumos, e
                         acende com um só. Também é a rede de segurança do resto — enquanto
                         ela estiver aqui, o contador não consegue contradizer o score.
      insumo NULL      — qualquer um dos insumos declarados. É o critério certo, e não "todos
                         NULL": forca_mismatch compara o ataque de um time com a defesa do
                         outro, e faltando um dos dois a comparação não existe. Meio insumo não
                         é meia premissa. Insumo condicional ({'col', 'quando'}) só é cobrado
                         quando a condição dele vale — é o `mando`, que lê uma coluna mandando
                         e outra jogando fora.

    Conta só `tipo = 'premissa'`. Penalidade não entra: ela não é conhecimento faltando, é
    ponto sendo subtraído, e somá-la ao contador diria ao leitor que sabemos menos do que
    sabemos. Marcador também não — ele nem soma nem subtrai.

    ⚠️ SÓ ENXERGA A AUSÊNCIA QUE CHEGA COMO NULL. Insumo COALESCEado antes daqui é
    indistinguível de valor real e o contador o dá por presente. Depois da #42 as 39 premissas
    têm insumo capaz de expressar ausência — `desfalque_adversario` era a última, e o NULL dela
    só existe porque a coleta passou a registrar o vazio (data-engineering#33). As três classes
    de disfarce estão no cabeçalho do macros/premissas_insumos.sql, e nenhuma delas fica
    vermelha sozinha: quem repuser um COALESCE cala o contador em silêncio. -#}
{% macro futebol_premissas_cegas(modelo) %}
    {%- set premissas = [] -%}
    {%- for p in futebol_insumos_premissa() if p.modelo == modelo and p.tipo == 'premissa' -%}
        {%- do premissas.append(p) -%}
    {%- endfor -%}

    {#- Fail-closed em toda direção: chave faltando no mapa vira string vazia em Jinja, não
        erro, e o contador nasceria com um pedaço mudo. Erro de compilação é barulhento. -#}
    {%- if premissas | length == 0 -%}
        {{ exceptions.raise_compiler_error(
            "futebol_premissas_cegas: nenhuma premissa declarada para o modelo '" ~ modelo ~
            "' em futebol_insumos_premissa(). Nome do modelo errado ou mapa incompleto.") }}
    {%- endif -%}
    {%- for p in premissas -%}
        {%- if not p.get('aplicavel') -%}
            {{ exceptions.raise_compiler_error(
                "futebol_premissas_cegas: a premissa '" ~ p.nome ~ "' (" ~ modelo ~
                ") não declara 'aplicavel'. Sem a condição de aplicabilidade o contador soma "
                "'sem dado' com 'não se aplica'.") }}
        {%- endif -%}
        {%- if p.get('insumos') | length == 0 -%}
            {{ exceptions.raise_compiler_error(
                "futebol_premissas_cegas: a premissa '" ~ p.nome ~ "' (" ~ modelo ~
                ") não declara insumo nenhum. Ela nunca incrementaria o contador — é a "
                "podridão por dentro do mapa, que a guarda de nome não pega.") }}
        {%- endif -%}
    {%- endfor -%}

    ARRAY(SELECT premissa FROM UNNEST([
    {%- for p in premissas %}
        IF(COALESCE(({{ p.aplicavel }})
           AND NOT COALESCE({{ p.nome }}, FALSE)
           AND ({% for i in p.insumos -%}
                    {%- if i is mapping -%}
                        (({{ i.quando }}) AND {{ i.col }} IS NULL)
                    {%- else -%}
                        {{ i }} IS NULL
                    {%- endif -%}
                    {{ " OR " if not loop.last }}
                {%- endfor %}), FALSE), '{{ p.nome }}', NULL){{ "," if not loop.last }}
    {%- endfor %}
    ]) AS premissa WHERE premissa IS NOT NULL)
{%- endmacro %}

{#- Testa se uma premissa de OUTRO modelo ficou cega, contra a lista premissas_cegas dele.

    Existe para que o nome da premissa não seja um literal solto dentro do modelo que a
    reusa. A Dupla Chance lê três premissas do 1X2 pelo nome; escritos à mão, um `rename` no
    1X2 deixaria a guarda do mapa VERDE (lá o nome novo casa com a coluna nova) e mataria a
    herança de cegueira da DC em silêncio — o modo de falha exato que esta entrega existe
    para fechar, reaparecendo uma camada acima. Aqui o par (modelo, nome) é conferido contra
    o mapa em tempo de COMPILAÇÃO. -#}
{% macro futebol_premissa_esta_cega(alias, modelo, nome) -%}
    {%- set nomes = [] -%}
    {%- for p in futebol_insumos_premissa() if p.modelo == modelo and p.tipo == 'premissa' -%}
        {%- do nomes.append(p.nome) -%}
    {%- endfor -%}
    {%- if nome not in nomes -%}
        {{ exceptions.raise_compiler_error(
            "futebol_premissa_esta_cega: '" ~ nome ~ "' não é premissa declarada de '" ~ modelo ~
            "' em futebol_insumos_premissa(). Renomeada ou removida lá? Quem a reusa herdaria "
            "cegueira de uma premissa que não existe mais — em silêncio, porque a guarda do mapa "
            "fica verde com o nome novo.") }}
    {%- endif -%}
    '{{ nome }}' IN UNNEST({{ alias }}.premissas_cegas)
{%- endmacro %}
