{#
    O QUE CONTA COMO JOGO ENCERRADO NO HISTÓRICO DE UM TIME (issue #71), escrito num lugar só.

    Devolve o predicado, e o predicado é a decisão inteira:

        status_short IN ('FT','AET','PEN')  -- o jogo aconteceu e acabou
        AND score_fulltime_* IS NOT NULL    -- e o placar do TEMPO NORMAL existe

    POR QUE AET E PEN ENTRAM. Até a #71 o histórico filtrava `status_short = 'FT'`, e jogo
    decidido na prorrogação (`AET`) ou nos pênaltis (`PEN`) não é `FT` — então ele não entrava no
    histórico de time nenhum: nem nos gols, nem nos clean sheets, nem na forma, nem na contagem
    que decide a amostra curta. O efeito é inteiramente de mata-mata, medido em 24/08/2026 sobre
    a `fact_fixtures` inteira:

        copa_do_brasil    331 FT + 55 (14,2% do histórico da competição)
        copa_mundo         95 FT +  9 ( 8,7%)
        sudamericana      427 FT + 30 ( 6,6%)
        libertadores      427 FT + 22 ( 4,9%)
        champions_league  617 FT + 26 ( 4,0%)
        ligue_1 / bundesliga        +  3 (jogo de acesso/rebaixamento — 0,2-0,3%)

    ⚠️ POR QUE `score_fulltime_*` E NÃO `goals_*` — é a metade não óbvia da decisão, e ela não é
    neutra. `goals_*` INCLUI gol de prorrogação: nos 21 jogos `AET` da base, `goals_*` difere de
    `score_fulltime_*` em **21 de 21**. Contar por `goals_*` colocaria gol de 120 minutos dentro
    de médias que alimentam mercado precificado em **90** (1X2, Over/Under, BTTS, Handicap) —
    trocaria um erro (o jogo não existir) por outro (o jogo existir com o placar errado).

    A troca é segura fora das copas, e isso foi MEDIDO, não presumido: nos **8.076** jogos `FT`
    da base, `goals_*` = `score_fulltime_*` em **8.076** (100%), e nenhuma das quatro colunas tem
    NULL em jogo encerrado. Ou seja, para o caminho que já existia, o predicado novo compila para
    o mesmo conjunto de linhas com os mesmos números.

    Nos `PEN` as duas colunas coincidem em 123 de 124. A exceção é o fixture **1208413**
    (Ballkani × UE Santa Coloma, Champions 1st Qualifying Round, 16/07/2024): `score_fulltime_*`
    0-1, `score_extratime_*` 1-1, pênaltis 5-6, e `goals_*` = 1-2. É um jogo que teve
    prorrogação E pênaltis, e a API o carimba `PEN`. É exatamente o caso que `score_fulltime_*`
    resolve certo: o resultado de 90 minutos foi 0-1.

    ⚠️ `PEN` NÃO É SINÔNIMO DE EMPATE, e o modelo não deve tratá-lo como tal. Só 83 dos 121
    medidos na #71 terminaram empatados no tempo normal: em confronto de ida e volta o time vence
    o jogo da noite e cai nos pênaltis no agregado. O W/D/L derivado de `score_fulltime_*` já
    descreve isso certo, sem caso especial.

    PRECEDENTE NO REPO: `fact_h2h` já filtra `status_short IN ('FT','AET','PEN')` desde que
    nasceu, com a justificativa escrita na própria `description` ("inclui mata-mata da Copa por
    prorrogação/pênaltis"). O histórico de time estava sozinho do outro lado.

    Uso — o alias é o da tabela no site que chama, ou vazio quando não há alias:

        WHERE {{ futebol_jogo_encerrado() }}
        WHERE {{ futebol_jogo_encerrado('l.') }}

    ⚠️ Quem chama esta macro tem de ler `score_fulltime_home`/`score_fulltime_away` no SELECT
    também. A macro não consegue centralizar isso: cada site inverte casa/fora à sua maneira
    (`goals_home AS gf` no PIT, `goals_away AS conceded` na DC, `goals_home - goals_away AS
    margin` no Handicap), e uma macro de colunas custaria mais indireção do que as seis edições
    mecânicas que ela pouparia. O predicado é que precisava existir uma vez.
#}

{% macro futebol_jogo_encerrado(alias='') %}
    {{ alias }}status_short IN ('FT', 'AET', 'PEN')
      AND {{ alias }}score_fulltime_home IS NOT NULL
      AND {{ alias }}score_fulltime_away IS NOT NULL
{%- endmacro %}
