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

### O piso de amostra não atenua os sinais — ele INVERTE os maiores

O piso entrou como **coluna** do Teste 2, não como varredura posterior, porque o
encolhimento (`k`) e o piso tratam eixos diferentes (ver abaixo). O resultado é o achado
mais forte do ticket.

**Desabam ao exigir 5 jogos disputados nos dois times:**

| Premissa | dif. piso 0 | dif. piso 5 | dif. piso 10 | n: 0 → 5 |
|---|---|---|---|---|
| `clean_sheets_altos` | **+17,1** | **−1,7** | **−10,1** | 105 → 24 |
| `superioridade_xg` | **+5,2** | **−8,9** | **−12,3** | 109 → 31 |
| `tende_golear` | **+3,9** | **−18,5** | **−22,3** | 154 → 18 |
| `superioridade_tabela` | +0,8 | −8,2 | −8,2 | 98 → 35 |
| `mando` | +2,4 | −6,4 | −8,3 | 107 → 48 |
| `defesa_forte` (BTTS) | +2,8 | −3,3 | −6,3 | 70 → 12 |
| `ataques_fracos` | +2,1 | −1,1 | −1,1 | 357 → 178 |

**Sobrevivem — e a maioria fica MAIS forte:**

| Premissa | dif. piso 0 | dif. piso 5 | dif. piso 10 | n: 0 → 5 |
|---|---|---|---|---|
| `raramente_perde_por_2` | +6,3 | **+7,4** | **+7,7** | 445 → 352 |
| `favorito_irregular` | +5,9 | **+7,1** | **+7,9** | 453 → 374 |
| `defesas_vazaveis` (BTTS) | +2,2 | **+8,7** | +8,7 | 58 → 31 |
| `equilibrio_defensivo` | +2,0 | **+6,4** | **+7,7** | 144 → 66 |
| `linha_descendo` | +3,1 | **+5,3** | +5,3 | 405 → 215 |
| `xg_baixo_combinado` | +1,5 | +3,6 | +4,1 | 307 → 133 |
| `defesa_fora_solida` | +3,9 | +2,6 | +2,8 | 322 → 134 |
| `historico_under` | +1,5 | +1,2 | +2,1 | 144 → 139 |

### Leitura

**O ranking sem piso está de cabeça para baixo.** As três maiores diferenças medidas —
`clean_sheets_altos` (+17,1), `superioridade_xg` (+5,2) e `tende_golear` (+3,9) — são as
três que mais dependem de jogo sem histórico (77%, 72% e 88% das linhas), e as três
viram negativo assim que se exige 5 partidas disputadas. É o mesmo padrão dos +9,7% que
morreram na Task [0], agora premissa por premissa em vez de agregado.

Ressalva honesta: com piso 5 essas três ficam com n de 18 a 31, então o valor negativo
também não é bem medido. A afirmação defensável não é "elas são ruins" — é **"não existe
evidência de que funcionem fora de jogo sem passado, e o pouco que dá para medir é
negativo"**.

**Os dois sinais mais robustos do conjunto inteiro são premissas do lado azarão do
Handicap** — `raramente_perde_por_2` e `favorito_irregular` —, que mantêm ~80% da amostra
sob o piso e ficam mais fortes com ele (+7,7 e +7,9 no piso 10). São as únicas com sinal
alto que não dependem de amostra curta.

E `favorito_irregular` é justamente a premissa que os documentos da proposta mandavam
remover por "valer 0 ponto e ser decorativa". A Task [0] mostrou que ela vale +8 pontos;
o Teste 2 mostra que ela é o sinal de valor mais robusto que existe na base.

**Consequência para o plano:** os pesos do ticket #8 têm de sair da medição COM piso. Os
pesos sem piso são dominados por artefato, e usá-los faria a nota ponderada herdar
exatamente o que a Task [0] acabou de remover. O piso deixou de ser calibragem opcional.

### ⚠️ Por que o encolhimento sozinho não bastava

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

## Ticket #6 — Teste 1 completo (fonte do peso de controle)

`analyses/task01_teste1.sql` · **6.042 jogos encerrados**, sem exigir odd

Reconciliação contra os valores publicados no re-run da Task [0]: `tende_golear` +8,1,
`mando` +5,8, `clean_sheets_altos` +5,6 e `forca_mismatch` +11,6 **exatos**;
`superioridade_tabela` +12,0 contra +12,1 e `defesa_forte` +3,4 contra +3,3. A definição
de "média da mesma linha" está certa.

### Os dois testes discordam quase por completo

| Premissa | Teste 1 (prevê a linha) | Teste 2 (bate o preço) |
|---|---|---|
| `superioridade_tabela` | **+12,0** | +0,8 |
| `forca_mismatch` | **+11,6** | −3,1 |
| `supremacia` | **+11,2** | −1,9 |
| `lado_coberto_forte` | **+9,7** | +2,8 |
| `invicto_recente` | **+7,2** | **−10,7** |
| `h2h_favoravel` | **+6,4** | **−10,7** |
| `forma` | **+6,8** | −1,4 |
| `clean_sheets_altos` | +5,6 | **+17,1** |
| `raramente_perde_por_2` | +1,9 | **+6,3** |
| `favorito_irregular` | +1,8 | **+5,9** |

As premissas que melhor **preveem** o resultado da linha — superioridade de tabela,
mismatch de força, supremacia — são as que o mercado já sabe, e valem perto de zero ou
menos contra o preço. As que **geram valor** estão no fundo do Teste 1.

Isso confirma a distinção que sustenta toda a metodologia: prever não é pagar. E confirma
que o Teste 2 tem de ser a fonte de peso.

### ⚠️ Mas isso enfraquece o controle desenhado no ADR 0001

O ADR previa usar pesos do Teste 1 como controle out-of-sample dos pesos do Teste 2. A
premissa era que os dois medissem a mesma coisa em universos diferentes. **Eles não
medem.** São construtos distintos e quase ortogonais.

Consequência: uma curva de ROI plana sob pesos do Teste 1 **não** prova que a curva sob
pesos do Teste 2 é ajuste in-sample — prova apenas que prever a linha não gera valor, o
que a tabela acima já mostrou.

O controle continua valendo a pena (responde "premissa que prevê bem gera valor?" — não),
mas **não substitui** um teste out-of-sample dos pesos do Teste 2. Quem carrega essa
carga passa a ser o teste de permutação, e o ticket #8 precisa ganhar uma **divisão
temporal** — ajustar peso na primeira metade da janela de odds e medir ROI na segunda.
Foi a opção descartada na sessão de grilling por falta de poder; hoje é a única
verdadeiramente out-of-sample sobre a métrica certa.

---

## Ticket #7 — Varredura de edge (Pedido 3)

`analyses/task01_edge.sql`

### ⚠️ Primeiro, um artefato que contamina o universo publicado

O de-vig de **consenso** normaliza a probabilidade sobre o conjunto de saídas da linha.
Quando só **um lado** foi precificado, ele normaliza sobre um único outcome e devolve
`prob_justa = 1,0` — certeza. O edge vira `odd − 1`.

| | |
|---|---|
| Linhas afetadas no universo | **172**, todas consenso, mercados 4 e 5 |
| Edge reportado | de **+820%** a **+14.900%** |
| Odd máxima | 150,0 |
| Vitórias reais | **2 de 172** |
| ROI | **−35,5%** |

O Motor anuncia valor máximo exatamente onde o acerto real é 1,2%.

**Produção NÃO é afetada.** O gate do mart exige ≥ 4 casas e conjunto Pinnacle completo;
o board hoje tem 90 oportunidades, edge máximo 23%, odd máxima 4,5 e mínimo de 4 casas.
Nenhuma dessas linhas chega ao usuário.

Mas elas **estão** no universo de backtest, inclusive no que produziu os números
publicados. O backtest é mais permissivo que o board — mede apostas que o produto nunca
faria. Isso vale para toda a série histórica e precisa entrar no relatório final.

Excluídas dos blocos abaixo, com o descarte auditado no próprio SQL.

### A resposta ao Pedido 3: o filtro é VAZIO, não neutro

| Corte | n | ROI |
|---|---|---|
| sem filtro (referência) | 8.567 | **−9,8%** |
| edge > −30% | 8.567 | −9,8% |
| edge > −20% | 8.567 | −9,8% |
| edge > −10% | 8.564 | −9,8% |
| edge > −5% | 6.759 | −9,2% |
| edge > 0% (regra de hoje) | 1.677 | **−10,4%** |

**O edge mínimo de todo o universo é −10,6%.** Não existe cauda de "preço muito pior que
o justo" para barrar: cortar em −30% ou −20% remove **zero** linhas, e −10% remove três.

A razão é estrutural: `edge = melhor odd × prob justa − 1`, e a melhor odd é tomada entre
**todas** as casas. Pegar o melhor preço entre ~14 casas impede, por construção, que o
preço fique muito abaixo do justo.

Então a resposta não é "o filtro é neutro, fica como proteção de reputação". É **"não há o
que filtrar"** — a regra proposta na A3 não teria agido sobre nenhuma aposta.

### O preço não ordena, em nenhuma direção

| Decil de edge | Faixa | n | ROI |
|---|---|---|---|
| 1 (pior preço) | −10,6 a −7,4 | 857 | −15,7 |
| 5 | −3,6 a −3,0 | 857 | −11,0 |
| 8 | −1,7 a −0,1 | 856 | **−5,7** |
| 9 | −0,1 a +4,2 | 856 | −9,1 |
| 10 (melhor preço) | +4,2 a +173 | 856 | −11,3 |

Sem ordenação. O melhor decil é o oitavo. **A A1 (tirar o preço da nota) está
confirmada**, e a regra de hoje (`edge > 0`) piora o resultado: −10,4% contra −9,8% de
apostar tudo.

### O maior discriminador de ROI da base não é o preço — é o benchmark

| Recorte | n | ROI |
|---|---|---|
| sharp (Pinnacle precifica) | 3.329 | **−5,0%** |
| derivada (Dupla Chance) | 299 | −3,9% |
| consenso (Pinnacle não precifica) | 3.262 | **−14,9%** |

Quase **10 pontos** de diferença, contra ~0 de qualquer filtro de preço. Restringir o
board às linhas com preço sharp vale mais do que toda a família de regras de edge junta.
Não estava no escopo desta task e não foi investigado — mas é a maior alavanca que
apareceu.

---

## Ticket #8 — Teste 4: o ROI sobe com a nota?

`analyses/task01_teste4.sql` e `task01_teste4_permutacao.sql`

Pesos do Teste 2 **com piso de 5 jogos** (sem o piso a nota herdaria
`clean_sheets_altos`, +17,1 sem piso e −1,7 com). Artefato de conjunto incompleto
excluído. Normalização 0–100 por mercado, faixas agrupadas depois.

### A inclinação sobrevive out-of-sample praticamente intacta

O controle real é o par B/C: **mesmos pesos**, universos de avaliação diferentes.

| Avaliação | Pesos ajustados em | ROI medido em | Inclinação (pp por ponto de nota) |
|---|---|---|---|
| A. `t2_full` | toda a janela | toda a janela | **+0,238** |
| B. `t2_h1` | 1ª metade | **1ª metade** (in-sample) | **+0,228** |
| C. `t2_h1` | 1ª metade | **2ª metade** (out-of-sample) | **+0,223** |
| D. `t1_controle` | Teste 1, 6.042 jogos | toda a janela | +0,149 |

**B → C perde 0,005.** A inflação in-sample, que o ADR 0001 existia para vigiar, é
desprezível para a inclinação. O sinal não é ajuste.

E o controle do ADR (D) fica claramente atrás, confirmando de novo que peso tem de sair
do Teste 2 e não do Teste 1.

### Mas a ordenação não é monótona — o topo não é o melhor

Faixas de C (out-of-sample, nota de premissas), com erro-padrão agrupado por fixture:

| Faixa | n apostas | n jogos | ROI | ± EP |
|---|---|---|---|---|
| 00–20 | 2.419 | 84 | **−16,7** | 6,5 |
| 20–40 | 436 | 81 | −3,6 | 4,6 |
| 40–60 | 279 | 57 | **+10,3** | 16,4 |
| 60–80 | 506 | 73 | **+8,1** | 6,2 |
| 80–100 | 512 | 66 | −3,9 | 4,1 |

O que a nota faz bem é **separar o fundo**: −16,7% na faixa baixa, a 2,6 erros-padrão de
zero. O que ela não faz é ordenar o topo — a faixa 80–100 é pior que a 60–80, e nenhuma
faixa positiva cruza dois erros-padrão.

### A nota de premissas ordena MELHOR que o Score pós-A1

| Composição | Inclinação (A) | Inclinação (C, out-of-sample) |
|---|---|---|
| nota de premissas | +0,238 | **+0,223** |
| Score pós-A1 (+ corroboração − penalidades) | +0,158 | **+0,114** |

Somar corroboração e penalidades **piora** a ordenação, e piora mais fora da amostra. Na
faixa 80–100 do Score pós-A1 o ROI out-of-sample é −17,0.

A corroboração é praticamente inerte (só implementada p/ 1X2, e o `/predictions` era
~vazio no histórico), então quem degrada são as **penalidades** — que são calculadas
sobre características da odd (outlier, poucas casas, longshot, juice) e empurram para
baixo linhas por razões descorrelacionadas do resultado. É um achado acionável e não
estava em nenhuma frente aberta.

### A régua: qual inclinação o acaso produz?

200 réplicas embaralhando os pesos **entre premissas do mesmo mercado** — a distribuição
de pesos fica idêntica, muda só quem recebe qual.

| Métrica | Observado | Nulo mediana | Nulo p05 | Nulo p95 | Nulo máx | p |
|---|---|---|---|---|---|---|
| Inclinação | **+0,238** | +0,078 | −0,178 | +0,276 | +0,335 | **0,070** |
| Gap alta(≥60) − baixa(<20) | **+17,3 pp** | +5,6 | −8,7 | +16,4 | +29,1 | **0,035** |

**O nulo NÃO está centrado em zero, e isso não é defeito.** Embaralhar pesos dentro do
mercado preserva quantas premissas acenderam — e o Teste 3 já mostrou que contagem tem
sinal fraco. Então a mediana nula de +0,078 é o que **a contagem sozinha** compra; o
excedente até +0,238 é o que a **ponderação correta** acrescenta.

O critério de aceite do ticket dizia "se a curva embaralhada subir, o defeito é nosso".
Ele foi escrito antes de eu entender que a permutação preserva a contagem por
construção. O critério certo é se o observado excede o nulo — e excede, mas por pouco:
**p = 0,035 no gap e 0,070 na inclinação.**

### Veredito de produto

**Existe sinal de ordenação, e ele é real — mas fraco, e não chega a rentabilidade.**

1. Sobrevive out-of-sample quase intacto (+0,228 → +0,223). Não é ajuste in-sample.
2. Excede a curva nula, mas com folga pequena (p = 0,035 no gap).
3. Ordena o **fundo**, não o topo: −16,7% na faixa baixa é o achado sólido; nenhuma
   faixa positiva se distingue de zero com confiança.
4. O objeto que iria pro ar (Score pós-A1) ordena **pior** que a nota de premissas pura.

A leitura honesta não é "temos produto" nem "não sobrou nada". É: **a nota serve hoje
para excluir, não para escolher.** Um corte que descarte a faixa baixa é defensável pelo
dado; um corte que selecione a faixa alta não é.

⚠️ A permutação foi rodada contra os pesos in-sample (+0,238). Como a inclinação
out-of-sample é quase idêntica, a conclusão carrega — mas o p-valor não foi recalculado
para o corte temporal.

---

## Ticket #9 — Piso coerente e a variante de premissa forte

`analyses/task01_teste4_piso.sql` e `task01_premissa_forte.sql`

Corrige uma incoerência do #8: lá o piso de 5 foi aplicado aos **pesos** mas o ROI foi
medido no universo inteiro. Aqui cada corte é coerente — piso P gera os pesos com P e
mede o ROI com P.

### O piso é um filtro de competição, e o dado agora mostra o tamanho disso

| Piso | Jogos | Competições que sobram |
|---|---|---|
| 0 | **169** | Copa do Mundo (79), Série B (39), Brasileirão (28), Sudamericana (15), Copa do Brasil (8) |
| 5 | **69** | Brasileirão (28), Série B (39), Copa do Mundo (2) |
| 10 | **67** | Brasileirão (28), Série B (39) |

**Copa do Mundo é 47% da amostra e desaparece inteira.** O piso não corta jogos ruins,
corta competições — e as que ele remove não são as piores: Sudamericana rende −1,6% e
Copa do Mundo −9,7%, contra −13,4% do Brasileirão e −10,0% da Série B, que ficam.

Exigir piso 10 reduz o universo a **67 jogos**. Qualquer calibragem fina em cima disso é
ilusão, e é o argumento mais concreto que apareceu para a prioridade da task C2.

### ⚠️ A variante de premissa forte: +10,0% que não sobrevive

O corte "ao menos uma premissa com ganho ≥ 5 pp" produziu o **primeiro ROI positivo de
toda a investigação**. Mas "forte" é definido pelo Teste 2 medido nos mesmos dados em que
o ROI é medido — selecionar por critério ajustado à amostra e avaliar na mesma amostra é
o procedimento que produziu os +9,7% que a Task [0] matou, trocando vazamento temporal
por vazamento de seleção.

O teste que decide, com "forte" definido **só na 1ª metade** e ROI medido **na 2ª**:

| Piso | Cenário | n | ROI | ± EP |
|---|---|---|---|---|
| 5 | 1. todas as apostas, 2ª metade | 2.962 | −10,0 | 3,9 |
| 5 | 2. forte de TODA a janela, ROI em toda (**in-sample**) | 1.235 | **+7,5** | 5,1 |
| 5 | 3. forte de TODA a janela, ROI na 2ª metade | 1.065 | +8,3 | 5,7 |
| 5 | 4. **forte só da 1ª metade, ROI na 2ª (OUT-OF-SAMPLE)** | 1.438 | **−6,2** | 3,4 |

E o mesmo padrão nos outros pisos: **+10,0 → −3,5** (piso 0) e **+8,3 → −5,1** (piso 10).

**A distância entre o cenário 3 e o 4 — 14,5 pontos percentuais — é viés de seleção
puro.** Os dois medem o mesmo conjunto de jogos; a única diferença é se a definição de
"forte" pôde ou não enxergar os resultados que ela seleciona.

### O contraste que dá coerência a tudo

| Objeto | In-sample | Out-of-sample | Sobrevive? |
|---|---|---|---|
| Nota ponderada (inclinação) | +0,228 | **+0,223** | **sim** |
| Filtro "tem premissa forte" (ROI) | +7,5% | **−6,2%** | **não** |

Não é contradição — é o mecanismo. A nota usa **todas** as premissas com peso contínuo,
e erro de peso individual se cancela na soma. O filtro de premissa forte é um **limiar
duro sobre o ganho individual**, e por construção seleciona exatamente as premissas que
tiveram sorte na amostra. Um agrega ruído, o outro o concentra.

É a mesma lição da Task [0] numa forma nova: o problema nunca foi a premissa, foi o
procedimento de seleção.

---

## Instabilidade: terceira medição, dentro da mesma sessão

O `dbt_loaded_at` das origens era 12:09 na primeira execução do dia e **15:01** três horas
depois. A mesma reconciliação, mesmo código, devolveu:

| Métrica | Publicado | Build 12:09 | Build 15:01 |
|---|---|---|---|
| Teste 3, 2+ premissas | −7,6 | −7,4 | **−7,6** |
| Teste 3, 3+ premissas | −6,0 | −6,1 | **−6,0** |
| Teste 3 por mercado, Gols | −7,3 | −6,9 | −7,2 |

Não é uma deriva que aconteceu uma vez: é **oscilação contínua**, e desta vez ela voltou a
cair sobre os valores publicados. Reforça a exigência de carimbar o build em qualquer
número de Gols — e mostra que "reproduziu" e "não reproduziu" podem ser a mesma medição
tirada em horas diferentes.

---

## Ressalvas que valem para tudo neste documento

- **A amostra é o gargalo, não a análise.** 168 jogos, cerca de um mês e meio, com
  apostas correlacionadas dentro do mesmo jogo. Nenhum número aqui é definitivo.
- Os valores `esperado` das reconciliações são os **publicados**, e a procedência de cada
  bloco está comentada no SQL. Reproduzir não valida a metodologia original — valida que
  esta implementação é a mesma.
