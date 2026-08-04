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

## Ressalvas que valem para tudo neste documento

- **A amostra é o gargalo, não a análise.** 168 jogos, cerca de um mês e meio, com
  apostas correlacionadas dentro do mesmo jogo. Nenhum número aqui é definitivo.
- Os valores `esperado` das reconciliações são os **publicados**, e a procedência de cada
  bloco está comentada no SQL. Reproduzir não valida a metodologia original — valida que
  esta implementação é a mesma.
