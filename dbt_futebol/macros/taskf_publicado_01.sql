{#
    OS NÚMEROS PUBLICADOS DO TESTE 2 DA TASK [0.1], transcritos para SQL.

    A terceira invariante da Costura B pede que a célula `base` reproduza o Teste 2 publicado da
    [0.1]. Esses números não existem em tabela nenhuma: a [0.1] rodou em 04/08/2026 e publicou o
    resultado em prosa, em `docs/TASK01_RESULTADOS.md` (ticket #5). Reconciliar contra markdown
    exige que alguém leia duas tabelas lado a lado e confie na própria vista. Aqui eles viram
    dado, uma vez, e a comparação vira query.

    ⚠️ ISTO É UMA TRANSCRIÇÃO, E TRANSCRIÇÃO ERRA. Um dígito trocado aqui FABRICA uma divergência
    que alguém vai investigar como se fosse achado. A conferência é contra
    `docs/TASK01_RESULTADOS.md`, seção "Ticket #5 — Teste 2 completo nos 5 mercados e peso
    medido", e mais nada — não contra outra análise, não de memória.

    ⚠️ E ELA É CONTRATO CONGELADO, pelo mesmo motivo da taskf_fingerprint_insumo_pit: as duas
    pontas (a reconciliação da #51 e a guarda da #55) leem daqui. Mudar um valor move as duas de
    uma vez, o que é o comportamento certo — mas mudar um valor só faz sentido se o doc publicado
    mudar junto, e o doc é registro histórico. Na prática: não se mexe.

    ────────────────────────────────────────────────────────────────────────────────
    O QUE ESTÁ PUBLICADO, E O QUE NÃO ESTÁ

    O doc não publica as 39 linhas inteiras. Publica três recortes, e a transcrição preserva a
    diferença entre eles em vez de preencher buraco com zero:

      as 20 de diferença positiva   linha completa no piso 0 (n, prob justa, acerto, diferença,
                                    jogos médios, % amostra curta, os dois pesos).
      as 19 de peso zero            SÓ a diferença no piso 0, que é como o doc as lista, em
                                    parágrafo corrido. As demais colunas ficam NULL.
      as 15 da varredura de piso    diferença nos pisos 5 e 10, e o n do piso 5. Vêm das duas
                                    tabelas "desabam" / "sobrevivem". Para as outras 24, o doc
                                    não publica piso 5 nem 10 e aqui elas ficam NULL.

    NULL aqui significa NÃO PUBLICADO, nunca zero. A reconciliação tem de dizer, por linha, quais
    campos eram comparáveis — senão "bateu" fica indistinguível de "não havia o que comparar".

    ────────────────────────────────────────────────────────────────────────────────
    BENCHMARK. Todas estas linhas são o benchmark PREFERIDO de cada mercado (sharp para 1X2,
    Handicap e Gols; derivada para Dupla Chance; consenso para BTTS) — é o recorte que o doc
    publica. As linhas de consenso do Handicap e do Gols existem na medição com
    `usado_para_peso = false` e NÃO têm contraparte publicada.

    `defesas_vazaveis` existe em DOIS mercados (Gols e BTTS) com números diferentes. A chave é
    (mercado, premissa), nunca a premissa sozinha.

    Emite UMA CTE no escopo do chamador, `publicado_01`. Uma CTE do chamador com esse nome a
    sombreia em silêncio.

    Uso:

        WITH {{ taskf_publicado_01() }},
        comparado AS (SELECT ... FROM medido JOIN publicado_01 USING (mercado, premissa))
#}

{% macro taskf_publicado_01() %}

publicado_01 AS (
    SELECT * FROM UNNEST([
        STRUCT<mercado STRING, premissa STRING,
               n_p0 INT64, a_odd_dava_p0 FLOAT64, aconteceu_p0 FLOAT64, diferenca_p0 FLOAT64,
               jogos_medios FLOAT64, pct_amostra_curta FLOAT64,
               peso_p0 FLOAT64, peso_p0_k0 FLOAT64,
               n_p5 INT64, diferenca_p5 FLOAT64, diferenca_p10 FLOAT64>

        {#- ── As 20 de diferença positiva. Tabela "Peso medido (melhor benchmark de cada
            mercado)". Ordem preservada do doc, que é por peso k50 decrescente. ── #}
        ('Gols',         'clean_sheets_altos',     105, 51.5, 68.6,  17.1,  5.3, 77.1, 11.58, 17.10,   24,  -1.7, -10.1),
        ('Handicap',     'raramente_perde_por_2',  445, 63.1, 69.4,   6.3, 14.1, 20.9,  5.67,  6.31,  352,   7.4,   7.7),
        ('Handicap',     'favorito_irregular',     453, 62.3, 68.2,   5.9, 14.8, 17.4,  5.29,  5.88,  374,   7.1,   7.9),
        ('BTTS',         'ataque_dos_dois',         32, 50.6, 62.5,  11.9, 12.1, 37.5,  4.65, 11.91, NULL,  NULL,  NULL),
        ('1X2',          'superioridade_xg',       109, 38.0, 43.1,   5.2,  6.3, 71.6,  3.54,  5.17,   31,  -8.9, -12.3),
        ('Handicap',     'defesa_fora_solida',     322, 62.5, 66.5,   3.9,  8.4, 58.4,  3.39,  3.92,  134,   2.6,   2.8),
        ('Gols',         'defesas_firmes',         246, 64.6, 68.3,   3.7, 11.4, 40.7,  3.05,  3.67, NULL,  NULL,  NULL),
        ('Handicap',     'tende_golear',           154, 44.2, 48.1,   3.9,  3.5, 88.3,  2.91,  3.86,   18, -18.5, -22.3),
        ('Gols',         'linha_descendo',         405, 53.0, 56.0,   3.1, 10.3, 46.9,  2.74,  3.08,  215,   5.3,   5.3),
        ('Dupla Chance', 'lado_coberto_forte',     112, 74.0, 76.8,   2.8,  8.6, 58.0,  1.92,  2.78, NULL,  NULL,  NULL),
        ('Gols',         'ataques_fracos',         357, 51.7, 53.8,   2.1,  9.6, 50.1,  1.81,  2.07,  178,  -1.1,  -1.1),
        ('BTTS',         'defesa_forte',            70, 52.9, 55.7,   2.8,  4.4, 82.9,  1.65,  2.82,   12,  -3.3,  -6.3),
        ('1X2',          'mando',                  107, 43.4, 45.8,   2.4,  9.0, 55.1,  1.63,  2.39,   48,  -6.4,  -8.3),
        ('Dupla Chance', 'equilibrio_defensivo',   144, 63.3, 65.3,   2.0,  9.0, 54.2,  1.49,  2.01,   66,   6.4,   7.7),
        ('Gols',         'xg_baixo_combinado',     307, 64.9, 66.4,   1.5,  8.7, 56.7,  1.31,  1.52,  133,   3.6,   4.1),
        ('BTTS',         'defesas_vazaveis',        58, 47.8, 50.0,   2.2, 10.3, 46.6,  1.20,  2.24,   31,   8.7,   8.7),
        ('Gols',         'historico_under',        144, 70.0, 71.5,   1.5, 17.0,  3.5,  1.11,  1.50,  139,   1.2,   2.1),
        ('1X2',          'superioridade_tabela',    98, 50.2, 51.0,   0.8,  7.6, 64.3,  0.55,  0.82,   35,  -8.2,  -8.2),
        ('Dupla Chance', 'adversario_limitado',    160, 68.7, 69.4,   0.7,  9.7, 50.0,  0.51,  0.66, NULL,  NULL,  NULL),
        ('BTTS',         'historico_btts',          16, 50.0, 50.0,   0.0, 18.4,  0.0,  0.01,  0.03, NULL,  NULL,  NULL),

        {#- ── As 19 de peso zero. O doc as lista em parágrafo corrido, "da menos ruim para a
            pior", e publica SÓ a diferença no piso 0 — daí todo o resto NULL. O mercado de cada
            uma sai do catálogo task01_markets(); `defesas_vazaveis` aqui é a do GOLS, e o doc
            marca isso explicitamente porque a de BTTS está na tabela de cima. ── #}
        ('Gols',         'historico_over',        NULL, NULL, NULL,  -0.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'historico_seco',        NULL, NULL, NULL,  -0.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forma',                 NULL, NULL, NULL,  -1.4, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'linha_subindo',         NULL, NULL, NULL,  -1.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'supremacia',            NULL, NULL, NULL,  -1.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ataque_trava',          NULL, NULL, NULL,  -2.2, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('BTTS',         'ambos_marcam',          NULL, NULL, NULL,  -2.5, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'xg_combinado_alto',     NULL, NULL, NULL,  -2.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'sem_rodizio',           NULL, NULL, NULL,  -2.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'adversario_fragil_fora',NULL, NULL, NULL,  -2.8, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Handicap',     'mando_forte',           NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'forca_mismatch',        NULL, NULL, NULL,  -3.1, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ataque_combinado',      NULL, NULL, NULL,  -3.6, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ambos_vazam',           NULL, NULL, NULL,  -3.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'defesas_vazaveis',      NULL, NULL, NULL,  -5.0, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Gols',         'ritmo_alto',            NULL, NULL, NULL,  -5.3, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'h2h_favoravel',         NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('Dupla Chance', 'invicto_recente',       NULL, NULL, NULL, -10.7, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL),
        ('1X2',          'desfalque_adversario',     7, NULL, NULL, -24.9, NULL, NULL,  NULL,  NULL, NULL,  NULL,  NULL)
    ])
)

{% endmacro %}
