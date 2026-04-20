# Análise de Player Props — SmartBetting Data

**Data:** 15/04/2026

---

## Contexto

Análise exploratória dos dados de player props coletados de 8 casas de apostas via balldontlie.io. Três perguntas foram levantadas sobre os dados e capacidades atuais do pipeline.

---

## Pergunta 1 — Qual vendor possui mais dados?

**Métrica:** total de registros por vendor (soma do campo de contagem).

| Rank | Vendor | Total de Registros |
|------|--------|-------------------|
| 1 | **DraftKings** | **234.101** |
| 2 | Rebet | 23.897 |
| 3 | Caesars | 5.831 |
| 4 | Betway | 5.684 |
| 5 | FanDuel | 5.192 |
| 6 | BetRivers | 2.471 |
| 7 | BetParx | 2.096 |
| 8 | BallyBet | 1.338 |

**DraftKings representa ~87% de todo o volume de dados.**

Observações relevantes:
- Rebet tem volume elevado concentrado em `steals milestone` (17.460 registros), o que parece desproporcional — possível anomalia de dados
- BallyBet só possui props do tipo `milestone`, sem nenhum `over/under`
- DraftKings é o único vendor com props de primeiros 3 minutos de jogo (`first3min`)

---

## Pergunta 2 — Qual vendor possui mais stats combinadas (PRA, P+A, P+R, R+A)?

Stats combinadas = `points_rebounds_assists`, `points_assists`, `points_rebounds`, `rebounds_assists`.

### 2a. Todos os tipos de mercado

| Rank | Vendor | P+R+A | P+A | P+R | R+A | Total |
|------|--------|-------|-----|-----|-----|-------|
| 1 | **BetParx** | 327 | 82 | 129 | 13 | **551** |
| 2 | Caesars | 147 | 117 | 154 | 111 | **529** |
| 3 | FanDuel | 117 | 108 | 148 | 102 | **475** |
| 4 | BetRivers | 446 | — | — | — | **446** |
| 5 | DraftKings | 67 | 67 | 81 | 63 | **278** |
| — | BallyBet, Betway, Rebet | — | — | — | — | **0** |

### 2b. Apenas `over_under`

| Rank | Vendor | P+R+A | P+A | P+R | R+A | Total |
|------|--------|-------|-----|-----|-----|-------|
| 1 | **Caesars** | 147 | 117 | 154 | 111 | **529** |
| 2 | FanDuel | 117 | 108 | 148 | 102 | **475** |
| 3 | BetRivers | 446 | — | — | — | **446** |
| 4 | DraftKings | 67 | 67 | 81 | 63 | **278** |
| 5 | BetParx | 146 | — | — | — | **146** |
| — | BallyBet, Betway, Rebet | — | — | — | — | **0** |

### Impacto do filtro over_under

| Vendor | Total geral | Total over_under | Registros que eram só milestone |
|--------|-------------|-----------------|--------------------------------|
| BetParx | 551 | 146 | **405** |
| Caesars | 529 | 529 | 0 |
| FanDuel | 475 | 475 | 0 |
| BetRivers | 446 | 446 | 0 |
| DraftKings | 278 | 278 | 0 |

Observações:
- **BetParx cai do 1º para o último** ao filtrar por over_under — os 405 registros que o colocavam na liderança eram todos `milestone`
- **Caesars sobe para o 1º lugar** e é o único com cobertura completa dos 4 combos exclusivamente em over_under
- **Caesars e FanDuel** são os únicos vendors com os 4 combos disponíveis em over_under
- **BetRivers** tem bom volume em PRA, mas sem P+A, P+R e R+A
- **DraftKings**, apesar de liderar no volume geral, ocupa o 4º lugar em stats combinadas
- **BallyBet, Betway e Rebet** não oferecem nenhuma stat combinada em nenhum tipo de mercado

---

## Pergunta 2c — Vendor mais volumoso por stat individual (somente `over_under`)

Qual vendor possui mais registros para cada tipo de prop, considerando apenas mercados `over_under`?

| Stat | Vendor líder | Total |
|------|-------------|-------|
| `points` | **DraftKings** | 6.176 |
| `rebounds` | **DraftKings** | 5.558 |
| `threes` | **DraftKings** | 4.559 |
| `assists` | **DraftKings** | 3.860 |
| `steals` | **DraftKings** | 642 |
| `blocks` | **DraftKings** | 182 |
| `points_rebounds_assists` | **BetRivers** | 446 |
| `points_rebounds` | **Caesars** | 154 |
| `points_assists` | **Caesars** | 117 |
| `rebounds_assists` | **Caesars** | 111 |

### Stats sem dados em over_under

Os seguintes tipos existem **apenas como milestone** — nenhum vendor os oferece em over_under:

`points_1q`, `rebounds_1q`, `assists_1q`, `points_first3min`, `rebounds_first3min`, `assists_first3min`, `double_double`, `triple_double`

### Resumo por vendor líder

| Vendor | Stats em que lidera |
|--------|---------------------|
| **DraftKings** | points, rebounds, threes, assists, steals, blocks |
| **Caesars** | points_rebounds, points_assists, rebounds_assists |
| **BetRivers** | points_rebounds_assists |

**DraftKings lidera todas as stats individuais em over_under.** Caesars domina as stats combinadas de 2 elementos (P+R, P+A, R+A). BetRivers lidera o PRA.

---

## Pergunta 3 — Temos dados de spread/handicap?

**Não.**

Os únicos tipos de mercado (`market.type`) presentes nos dados são:

| Tipo | Descrição |
|------|-----------|
| `milestone` | Apostas em marcos — ex: "jogador vai fazer 30+ pontos" |
| `over_under` | Linha tradicional de over/under com valor de linha decimal |

Nenhum registro contém `spread`, `handicap` ou equivalente. Caso esse tipo de mercado exista na API, seria necessário investigar e capturar separadamente.

---

## Pergunta 4 — Conseguimos replicar as features do concorrente DMP?

### O que o DMP oferece
Para cada pick, o DMP exibe:
- Odds no formato americano (ex: `+252`, `+114`)
- Nome da casa de apostas (ex: Kalshi, bet365)
- **EV%** — Expected Value percentual

### Nossa situação

**O que já temos hoje:**

| Feature | Status | Detalhe |
|---------|--------|---------|
| Odds por casa | ✅ Disponível | Campo `market.odds` em formato americano |
| Nome da casa | ✅ Disponível | Campo `vendor` com 8 casas |
| Comparação entre múltiplos books | ✅ Disponível | Base para calcular linha justa |
| **EV%** | ⚠️ Falta implementar | Requer algoritmo de devig + cálculo de EV |
| Odds em mercados `over_under` | ⚠️ Gap | Muitos registros chegam com `odds: null` |
| Kalshi | ❌ Não disponível | Mercado de predição, API separada |
| bet365 | ❌ Não disponível | Não coberto pela balldontlie |

### Como o EV% seria calculado

1. Coletar as odds de múltiplas casas para o mesmo mercado (já temos)
2. Remover a vig de cada casa (métodos: Pinnacle, Power, etc.)
3. Calcular a probabilidade implícita consenso
4. Comparar com a odd de uma casa específica → se ela paga mais do que a probabilidade justa, existe EV+

### Conclusão

Um **MVP de EV+** usando as casas que já temos (DraftKings, FanDuel, Caesars, BetRivers) é **totalmente viável sem nenhuma fonte nova**. O trabalho principal é implementar o algoritmo de devig e EV%.

Integração com **bet365 e Kalshi** seria uma segunda fase, com esforço dedicado de engenharia.

---

## Referência — Estrutura dos dados

```json
{
  "vendor": "draftkings",
  "prop_type": "rebounds",
  "line_value": "12.0",
  "market": {
    "type": "milestone",
    "odds": "700"
  },
  "player_id": "4",
  "game_id": "18447084",
  "season": "2025"
}
```
