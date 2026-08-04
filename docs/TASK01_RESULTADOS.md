# Task [0.1] — Resultados

Documento vivo. Cada ticket da [issue #3](https://github.com/tech-lamjav/analytics-engineering/issues/3)
acrescenta a sua seção aqui. O SQL que produz cada número está em `dbt_futebol/analyses/`.

Os resultados moram neste arquivo, e não no cabeçalho das análises, para que o SQL mude
quando a lógica muda e não quando os números mudam.

---

## Carimbo de execução

**Toda tabela desta seção precisa de carimbo.** O mercado de Gols não é reproduzível
entre builds (ver §Estabilidade), então número de Gols sem data de build não é
verificável.

| Execução | Corte do universo | `dbt_loaded_at` das origens |
|---|---|---|
| 2026-08-04 | jogos com kickoff ≤ 2026-08-02 | `odds_devig` 12:09:33 · `team_form_pit` 12:09:56 · `premissas_ah` 12:10:00 · `premissas_1x2` e `premissas_ou` 12:10:11 |

---

## Ticket #4 — Reconciliação por resposta conhecida (Seam 1)

`analyses/task01_reconciliacao.sql`

### Veredito

**A máquina generalizada está certa. A base não é estável.**

22 das 25 linhas de comparação com delta **exatamente 0,0** — incluindo as seis do
Teste 2 e quatro dos cinco mercados. A Dupla Chance bate inclusive o `n = 154` publicado.

As três que divergem são todas do mercado de Gols, direta ou indiretamente:

| Bloco | Métrica | n | Esperado | Obtido | Delta |
|---|---|---|---|---|---|
| Teste 3 | 2+ premissas | 4.066 | −7,6 | −7,4 | **+0,2** |
| Teste 3 | 3+ premissas | 1.892 | −6,0 | −6,1 | **−0,1** |
| Teste 3 por mercado | Gols | 2.182 | −7,3 | −6,9 | **+0,4** |

Gols é 2.182 das 4.066 apostas do corte "2+", então a deriva agregada vem inteiramente
dele. 1X2 (−2,5), Handicap (−9,9), BTTS (−1,1) e Dupla Chance (+1,4) reproduzem exato.

**Não é regressão da generalização:** a query ad-hoc original da Task [0], rodada hoje
sem alterar um byte, também devolve −7,4 onde ontem devolveu −7,6.

### Descartes

A guarda de descarte silencioso lê as odds **antes** de qualquer recorte e classifica
tudo que não vira aposta. Nenhum descarte inesperado:

| Motivo | Linhas |
|---|---|
| Fora do escopo do Motor (market 6, Goals O/U First Half) | 3.642 |
| Linha inteira, push possível (AH e O/U) | 5.903 |
| Gap conhecido: Dupla Chance não emite premissa para a saída `12` | 168 |
| **INESPERADOS** | **0** |

Dois destes eram invisíveis antes. O market 6 só ficava de fora por acidente do INNER
JOIN com as premissas — hoje o escopo `market_id IN (1,4,5,8,12)` é declarado e derivado
do catálogo de premissas. As 5.903 linhas inteiras são exclusão de desenho (push não tem
liquidação binária) e batem com a metodologia publicada, mas nunca tinham sido contadas.

O gap da saída `12` da Dupla Chance segue **reportado e não corrigido**: uma saída
inteira de um mercado está fora de toda a medição, na rodada anterior e nesta.

### Cobertura por benchmark

Os mercados 4 e 5 são **mistos** — a Pinnacle cobre a maior parte, não todos os jogos:

| Mercado | Benchmark | Linhas | ROI sem porta |
|---|---|---|---|
| 1X2 | sharp | 504 | −11,8 |
| Handicap | sharp | 1.848 | −6,5 |
| Handicap | consenso | 1.837 | −26,7 |
| Gols | sharp | 1.722 | −1,8 |
| Gols | consenso | 2.105 | −7,1 |
| BTTS | consenso | 336 | −4,3 |
| Dupla Chance | derivada | 336 | −5,7 |

⚠️ A diferença entre sharp e consenso no Handicap (−6,5 contra −26,7) é grande demais
para ser ignorada na leitura do Teste 2. Não investigada neste ticket.

---

## Estabilidade das tabelas entre rebuilds

`analyses/task01_estabilidade.sql`

Compara o estado congelado em `futebol_task0` (2026-08-03) contra o atual, sobre as
premissas do mercado de Gols. Só as quatro que a Task [0] **não** alterou são
comparáveis; as outras nove aparecem para dar escala à correção.

| Classe | Premissa | Flips / 50.608 | % |
|---|---|---|---|
| **Lê odds** | `linha_descendo` | **20** | 0,040 |
| **Lê odds** | `linha_subindo` | **16** | 0,032 |
| **Controle** (lê histórico) | `historico_over` | **0** | 0,000 |
| **Controle** (lê histórico) | `historico_under` | **0** | 0,000 |
| Corrigida na Task 0 | `defesas_firmes` | 7.124 | 14,08 |
| Corrigida na Task 0 | `ataques_fracos` | 6.735 | 13,31 |
| Corrigida na Task 0 | `ambos_vazam` | 5.745 | 11,35 |
| Corrigida na Task 0 | `defesas_vazaveis` | 5.716 | 11,30 |
| Corrigida na Task 0 | `ataque_combinado` | 4.403 | 8,70 |
| Corrigida na Task 0 | `ritmo_alto` | 4.212 | 8,32 |
| Corrigida na Task 0 | `xg_baixo_combinado` | 1.950 | 3,85 |
| Corrigida na Task 0 | `xg_combinado_alto` | 1.807 | 3,57 |
| Corrigida na Task 0 | `clean_sheets_altos` | 1.766 | 3,49 |

### Leitura

**O controle em zero fecha o argumento.** `historico_over` e `historico_under` estão na
mesma classe de premissa não afetada pela Task [0], mas leem histórico de jogos em vez
de odd — e não mexeram uma linha. As duas que leem `fact_odds_snapshot` mexeram.

Gols é o **único** dos cinco mercados do Motor com premissa derivada de odd
(`linha_subindo`/`linha_descendo` usam a média das probabilidades implícitas de todas as
casas, t24h → t15m, e o modelo ainda monta o universo de linhas a partir das odds
presentes). Os outros quatro não leem odd em premissa nenhuma — e são exatamente os
quatro que reproduziram byte a byte.

**A escala importa:** a correção da Task [0] moveu de 3,5% a 14,1% das linhas. A
instabilidade move 0,03–0,04%. São fenômenos de ordens de grandeza diferentes, e só o
segundo é ruído.

### Consequências

1. **Número de Gols exige carimbo de build.** Sem ele, uma diferença de 0,2–0,4pp entre
   execuções vira caça a bug inexistente — ou pior, vira "achado".
2. **0,07% das linhas viraram e o ROI do mercado andou 0,4pp**, porque a porta "N+
   premissas" é um **limiar**: uma linha que sai de `n_prem=1` para `2` entra inteira no
   universo. Vale checar no ticket #8 se a nota ponderada, sendo contínua, é menos
   sensível a esse ruído. Se for, é um argumento a favor dela que ninguém levantou — e
   que **não depende do resultado de ROI**.

---

## Ticket #5 — Teste 2 completo nos 5 mercados e peso medido

`analyses/task01_teste2.sql` · execução 2026-08-04 · janela **16/06 a 04/08/2026**, 169 jogos

As 39 premissas medidas. `diferença = acerto − prob justa`, em pp, só nas linhas em que
a premissa acendeu.

### Peso medido (melhor benchmark de cada mercado)

**20 das 39 têm diferença positiva; 19 vão a zero.** Com peso ≥ 1,0 sobram **17**.

| Mercado | Premissa | n | A odd dava | Aconteceu | Dif. | Jogos méd. | % amostra curta | peso k50 | peso k0 |
|---|---|---|---|---|---|---|---|---|---|
| Gols | `clean_sheets_altos` | 105 | 51,5 | 68,6 | **+17,1** | 5,3 | **77,1** | 11,58 | 17,10 |
| Handicap | `raramente_perde_por_2` | 445 | 63,1 | 69,4 | **+6,3** | 14,1 | 20,9 | 5,67 | 6,31 |
| Handicap | `favorito_irregular` | 453 | 62,3 | 68,2 | **+5,9** | 14,8 | 17,4 | 5,29 | 5,88 |
| BTTS | `ataque_dos_dois` | 32 | 50,6 | 62,5 | +11,9 | 12,1 | 37,5 | 4,65 | 11,91 |
| 1X2 | `superioridade_xg` | 109 | 38,0 | 43,1 | +5,2 | 6,3 | **71,6** | 3,54 | 5,17 |
| Handicap | `defesa_fora_solida` | 322 | 62,5 | 66,5 | +3,9 | 8,4 | 58,4 | 3,39 | 3,92 |
| Gols | `defesas_firmes` | 246 | 64,6 | 68,3 | +3,7 | 11,4 | 40,7 | 3,05 | 3,67 |
| Handicap | `tende_golear` | 154 | 44,2 | 48,1 | +3,9 | 3,5 | **88,3** | 2,91 | 3,86 |
| Gols | `linha_descendo` | 405 | 53,0 | 56,0 | +3,1 | 10,3 | 46,9 | 2,74 | 3,08 |
| Dupla Chance | `lado_coberto_forte` | 112 | 74,0 | 76,8 | +2,8 | 8,6 | 58,0 | 1,92 | 2,78 |
| Gols | `ataques_fracos` | 357 | 51,7 | 53,8 | +2,1 | 9,6 | 50,1 | 1,81 | 2,07 |
| BTTS | `defesa_forte` | 70 | 52,9 | 55,7 | +2,8 | 4,4 | **82,9** | 1,65 | 2,82 |
| 1X2 | `mando` | 107 | 43,4 | 45,8 | +2,4 | 9,0 | 55,1 | 1,63 | 2,39 |
| Dupla Chance | `equilibrio_defensivo` | 144 | 63,3 | 65,3 | +2,0 | 9,0 | 54,2 | 1,49 | 2,01 |
| Gols | `xg_baixo_combinado` | 307 | 64,9 | 66,4 | +1,5 | 8,7 | 56,7 | 1,31 | 1,52 |
| BTTS | `defesas_vazaveis` | 58 | 47,8 | 50,0 | +2,2 | 10,3 | 46,6 | 1,20 | 2,24 |
| Gols | `historico_under` | 144 | 70,0 | 71,5 | +1,5 | 17,0 | 3,5 | 1,11 | 1,50 |
| 1X2 | `superioridade_tabela` | 98 | 50,2 | 51,0 | +0,8 | 7,6 | 64,3 | 0,55 | 0,82 |
| Dupla Chance | `adversario_limitado` | 160 | 68,7 | 69,4 | +0,7 | 9,7 | 50,0 | 0,51 | 0,66 |
| BTTS | `historico_btts` | 16 | 50,0 | 50,0 | 0,0 | 18,4 | 0,0 | 0,01 | 0,03 |

As 19 com peso zero, da menos ruim para a pior: `historico_over` −0,5 · `forma` −1,4 ·
`linha_subindo` −1,5 · `supremacia` −1,9 · `ataque_trava` −2,2 · `ambos_marcam` −2,5 ·
`xg_combinado_alto` −2,6 · `sem_rodizio` −2,7 · `adversario_fragil_fora` −2,8 ·
`historico_seco` −0,9 · `mando_forte` −3,1 · `forca_mismatch` −3,1 ·
`ataque_combinado` −3,6 · `ambos_vazam` −3,7 · `defesas_vazaveis` (Gols) −5,0 ·
`ritmo_alto` −5,3 · `h2h_favoravel` −10,7 · `invicto_recente` −10,7 ·
`desfalque_adversario` −24,9 (n=7).

### ⚠️ O encolhimento não protege contra o artefato que matou a medição anterior

São **dois eixos diferentes**, e o `k=50` só cobre um deles:

- **n pequeno** — a premissa acendeu poucas vezes. É o que o encolhimento trata.
  `ataque_dos_dois` (n=32) cai de 11,9 para 4,65: funcionou.
- **amostra curta** — os jogos em que ela acendeu tinham pouco histórico. O
  encolhimento **não vê isso**.

E os três maiores sinais estão contaminados pelo segundo eixo:

| Premissa | Dif. | n | % das linhas com < 5 jogos |
|---|---|---|---|
| `clean_sheets_altos` | +17,1 | 105 (grande) | **77,1** |
| `superioridade_xg` | +5,2 | 109 (grande) | **71,6** |
| `tende_golear` | +3,9 | 154 (grande) | **88,3** |
| `defesa_forte` (BTTS) | +2,8 | 70 | **82,9** |

`clean_sheets_altos` tem o maior peso da tabela e acende quase só em jogo sem histórico
— a assinatura exata dos +9,7% que morreram. **Isso torna o ticket #9 (piso de amostra)
não-opcional**: sem ele, a nota do #8 é dominada por uma premissa cujo sinal pode ser o
mesmo artefato de novo.

O contraste: `raramente_perde_por_2` (+6,3, n=445, só 20,9% de amostra curta) e
`favorito_irregular` (+5,9, n=453, 17,4%) são os únicos sinais fortes que **não**
dependem de jogo sem passado.

### `favorito_irregular` é o 3º maior sinal de valor da tabela

A premissa que os documentos da proposta mandavam remover — "vale 0 ponto, é
decorativa" — mede **+5,9 pp contra o preço**, com n=453 e a segunda menor exposição a
amostra curta. A Task [0] já tinha mostrado que ela vale +8 pontos e é premissa do
azarão; o Teste 2 agora mostra que ela também é uma das poucas que batem o mercado.

### Por que as linhas de consenso não foram pooled

O consenso não é "o mesmo jogo com benchmark pior" — é **outro conjunto de linhas**. A
prob justa média da mesma premissa muda de forma estrutural:

| Mercado | Premissa | `a_odd_dava` sharp | `a_odd_dava` consenso |
|---|---|---|---|
| Handicap | `raramente_perde_por_2` | 63,1 | **87,7** |
| Handicap | `mando_forte` | 43,9 | **17,1** |
| Gols | `xg_baixo_combinado` | 64,9 | **88,1** |
| Gols | `ritmo_alto` | 49,4 | **42,7** |

A Pinnacle precifica as linhas principais; as extremas caem no consenso. Uma linha com
17% ou 88% de probabilidade implícita é handicap grande ou total distante — população
diferente, não amostra a mais. Juntar as duas metades teria produzido uma média sem
referente.

---

## Ressalvas que valem para tudo neste documento

- **A amostra é o gargalo, não a análise.** 168 jogos, cerca de um mês e meio, com
  apostas correlacionadas dentro do mesmo jogo. Nenhum número aqui é definitivo.
- Os valores `esperado` das reconciliações são os **publicados**, e a procedência de cada
  bloco está comentada no SQL. Reproduzir não valida a metodologia original — valida que
  esta implementação é a mesma.
