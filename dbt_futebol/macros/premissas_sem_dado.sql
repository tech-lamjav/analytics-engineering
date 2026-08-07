{#- Gera a expressão do contador de PREMISSAS SEM DADO de um modelo, derivada do mapa
    futebol_insumos_premissa(). Chamado dentro do modelo, onde as colunas da CTE `metrics`
    ainda existem — no SELECT final elas já viraram booleano e a informação sumiu.

    Por que gerado e não escrito à mão: o contador manual fica correto no dia em que é escrito
    e apodrece na premissa seguinte, e esquecer é silencioso (ADR 0003). Gerando do mapa, uma
    premissa nova só precisa ser declarada — e se não for, a guarda
    assert_premissas_insumo_declarado fica vermelha antes de o contador mentir.

    Conta só `tipo = 'premissa'`. Penalidade não entra: ela não é conhecimento faltando, é
    ponto sendo subtraído, e somá-la ao contador diria ao leitor que sabemos menos do que
    sabemos. Marcador também não — ele nem soma nem subtrai.

    A premissa conta como sem dado quando QUALQUER um dos insumos dela é NULL. É o critério
    certo e não o "todos NULL": `forca_mismatch` compara o ataque de um time com a defesa do
    outro, e faltando um dos dois a comparação não existe — meio insumo não é meia premissa.

    ⚠️ SÓ FUNCIONA ONDE A AUSÊNCIA CHEGA COMO NULL. Insumo COALESCEado antes daqui é
    indistinguível de valor real e o contador o dá por presente. Depois de #41 isso vale para
    UMA premissa: `desfalque_adversario`, cujos s_missing/o_missing seguem COALESCEados para
    zero até a #42 (que espera o vazio registrado de data-engineering#33). As outras 38 têm
    insumo capaz de expressar ausência. -#}
{% macro futebol_premissas_sem_dado(modelo, alias='f') %}
    (
    {%- for p in futebol_insumos_premissa() if p.modelo == modelo and p.tipo == 'premissa' %}
        {{ "  " if loop.first else "+ " }}CAST({% for i in p.insumos %}{{ alias }}.{{ i }} IS NULL{{ " OR " if not loop.last }}{% endfor %} AS INT64)  -- {{ p.nome }}
    {%- endfor %}
    )
{%- endmacro %}
