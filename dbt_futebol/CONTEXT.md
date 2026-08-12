# Futebol Value Betting

Pre-match value betting for football (Brasileirão-first, plus cups and European
leagues): a deterministic rules engine rates every fixture x market x outcome with a
reliability score and explains why.

## Language

### The score engine

**Motor de Score**:
The deterministic rules engine ("Pilar A") that computes a Score de Confiabilidade for
each fixture x market x outcome. Rules and arithmetic, not statistics.
_Avoid_: model (reserved for statistical models)

**Score de Confiabilidade**:
The 0–100 rating of how trustworthy a value opportunity is: value points + premissa
points + corroboration points, minus penalties, clamped. It is an **absolute** measure —
how much evidence fired — and never a rank within its peer group. So a régua on it means
"this much evidence", not "the best of this mercado"; markets legitimately publish at
different rates, and that is a consequence, not a defect.
_Avoid_: reading a score as a percentile or a quota

**Teto alcançável**:
The denominator the pontos de premissa are normalised against, per (mercado, lado): the
observed p95, measured once over a **declared window** and **frozen**. Its job is to make
100 mean the same thing on every lado — the top of the scale anchored at a common
quantile. It is deliberately not the sum of the weights, which never occurs, and not
recomputed at runtime: a denominator that moves makes the régua mean a different thing
each day and kills every historical comparison.
_Avoid_: teto (bare — ambiguous with the sum of the pesos)

**Premissa**:
A boolean context signal computed from the data, carrying a point weight. Fired
premissas add to the score and become evidence bullets.
_Avoid_: feature, predictor

**Gate**:
The eliminatory precondition (positive edge and enough bookmakers). Failing the gate
means the bet is not an opportunity at all. Dupla Chance has its own gate.

**Faixa**:
The confidence band over the score: Alta (>= 60), Média (40–59), Baixa (< 40).
Thresholds differ from the NBA context. The band cuts and the **régua** are the same
numbers wearing two hats — set the régua at a band floor and the band below it stops
existing, leaving a column that is constant and therefore lying. So the cuts are never
chosen apart from the régua, and never on a scale that is about to change: they come out
of one measurement, on the scale that will actually ship.
_Avoid_: treating the régua as independent of the bands

**Value opportunity**:
A fixture x market x outcome that passed the gate with positive edge — the product's
unit of output.
_Avoid_: pick, tip

**Candidato**:
A (fixture, mercado, saída, linha, janela) that **had a price in that janela** — the
universe the gates act on, and the denominator of every funnel reading. A line nobody
priced is not a rejected candidato, it is absence of market: that belongs to coleta, not
to the funil. A candidato whose conjunto de saídas came in incomplete still counts —
it exists, it just lost its fair probability.
_Avoid_: counting every premissa row (they are generated for canonical lines with no
market at all, and are unbounded)

**Evidência**:
A fired premissa surfaced to the user as a "why" bullet, ordered by weight.

**Aviso**:
An applied penalty surfaced to the user as a warning.

**Penalidade**:
A point deduction for a red flag: outlier odd, few bookmakers, longshot, juice, plus
market-specific ones (e.g. picking the draw).

**Corroboração**:
External confirmation points: the API's prediction model agrees, or the sharp line
moved toward our side.

**Degradação graciosa**:
Missing data means the premissa simply does not fire — never an error or NULL. The rule
holds when the absence is **in the world** ("there is no desfalque"): the score gets
honestly lower. It does not hold when the absence is **in the collection** ("we never
asked", or "we asked and kept no record") — reading that as a negative is a fabricated
claim, not a degraded one. See ADR 0003.

**Premissas sem dado**:
The count, per rated line, of premissas whose declared input was unavailable. It is
diagnosis, never penalty: it does not move the score. It is what makes a low score
readable as *little evidence* instead of *evidence against*.

**Insumo declarado**:
The inputs a premissa depends on, declared per premissa in one place — the same idiom as
the conjunto de saídas. A premissa whose input is undeclared cannot be counted as missing,
so the declaration is what makes **premissas sem dado** honest rather than optimistic.

**Dado não perguntado**:
An input absent because the source was never consulted — as opposed to consulted and
answered "nothing". The two are indistinguishable downstream unless the asking itself is
recorded, and the Motor then reports the second while in fact holding the first.
_Avoid_: dado faltante (silent about which of the two it is)

### Odds and value

**Edge**:
The margin by which the best available odd beats the fair closing probability
(best odd x fair probability − 1).

**De-vig**:
Removing the bookmaker margin (overround) from a market's full set of odds to obtain
fair probabilities. Operates on a **conjunto de saídas**, never on a single price.

**Conjunto de saídas**:
The set of mutually exclusive and exhaustive outcomes a de-vig normalises over, for one
(fixture, market, line) — Home/Draw/Away for 1X2, Over/Under for a goals line, the
complementary pair for an asian handicap. Its expected size is **declared per market**,
in one place, and the declaration is what makes a set *complete*.
_Avoid_: "as odds do mercado" (a market has many prices across bookmakers; the set is the
outcome axis, not the bookmaker axis)

**Conjunto incompleto**:
A set missing at least one outcome. It does **not** yield a worse fair probability — it
yields **no** fair probability. Normalising over a partial set inflates every probability
in it (one outcome alone yields certainty), so a partial set is not a weak estimate but an
invalid one. A line built on an incomplete set keeps its real outcome count as diagnosis
and loses fair probability, edge and value points.
_Avoid_: treating a partial set as a degraded estimate

**Double Chance (conjunto)**:
Its three outcomes (1X/12/X2) are *not* exhaustive — they sum to ~2 — so Double Chance is
never de-vigged on its own set. Its fair probability is **derived** from the 1X2 set, and
that is the set its declaration refers to.

**Prob justa de fechamento**:
The fair probability a value claim must beat. It has three possible benchmarks, in
descending order of trust: **sharp** (de-vigged Pinnacle, for 1X2/OU/AH), **derivada**
(computed from Pinnacle's 1X2 de-vig, the only source for Dupla Chance) and
**consenso**. Only the first two are anchored on a sharp price; note the data stamps
derivada as `pinnacle` too, so the three-way split exists only where analysis makes it.

**Sharp**:
Pinnacle, the reference bookmaker. "Linha sharp" is its price; its movement toward our
side is corroboration.
_Avoid_: soft book (that is the opposite concept)

**Janela**:
The odds collection window relative to kickoff: daily (anything beyond 24h, one capture
per day), t24h, t1h, t15m. t15m is the fechamento (closing).

**Janela de avaliação**:
The janela whose prices a given rating was computed from. It is part of the identity of a
rating, not a property resolved away: the same line is rated once per janela it has, and
no janela is discarded in favour of a fresher one. See ADR 0004.

**Janela de detecção**:
The earliest janela in which a line passed the gate. Stamped on the board so an
opportunity is published once and followed from there, instead of re-announced whenever a
fresher price arrives.
_Avoid_: janela usada (ambiguous between the two above)

**Consenso**:
Fallback fair probability from the median of all bookmakers, used when Pinnacle does
not price a market (e.g. BTTS). Consensus-derived value is an estimativa, not
calibrated value.

**CLV (Closing Line Value)**:
Getting a better price than the closing line — the king KPI of real edge. Accumulates
forward only.

**Line**:
The market line (goals total for Over/Under, handicap for Asian Handicap — always
stated from the home side).

### Markets

**Mercado**:
A bet type priced for a fixture. Covered: 1X2 (match winner), Over/Under (gols),
Handicap Asiático, BTTS (Ambos Marcam), Dupla Chance.

**S / O**:
Playbook convention: S is the side being bet, O is the opponent.

**Mando**:
Home advantage — playing at home with a strong home record. A declining, per-league
signal.

### Match context

**Desfalque**:
A player missing a fixture. Only a desfalque of a titular importante fires premissas;
"Questionable" (dúvida) is displayed but never fires. The source publishes the list
roughly two to three days out and not before — so on the earlier part of the board the
premissa has **no input**, which is not the same as a negative one.
_Avoid_: injury (a desfalque may be suspension or other absence)

**Escalação confirmada**:
The starting eleven as announced before kickoff, roughly forty minutes out — distinct
from the escalação real recorded after the match. It is the only pre-kickoff evidence of
who actually plays, and it arrives too late to inform any janela but t15m. Its value is
therefore corroboration and measurement, not the desfalque premissa itself.
_Avoid_: escalação provável (the source does not publish one)

**Titular importante**:
A regular starter by minutes played and start share — the importance proxy that makes
a desfalque matter.

**Rodízio**:
Squad rotation — resting starters when a bigger match looms. "Sem rodízio" means the
game matters and no midweek decision competes.

**xG (expected goals)**:
Shot-quality-based goal expectation; the strongest form signal. Rich in the Brasileirão
**and in the top-5 European leagues** (~100% of finished fixtures); thin in the cups and
in Série B, with Copa do Brasil the extreme at ~10%. Where it is thin the xG premissas
have no input at all — that is **premissas sem dado**, not a weak reading.

**Forma**:
Recent results run (wins in last 5). Deliberately low-weight: it mostly duplicates
underlying strength.

**H2H**:
Head-to-head history between the two teams.

**Pilar A / Pilar B**:
Pilar A is this rules engine. Pilar B is the future proper statistical model
(Dixon-Coles + xG) — out of scope today; when it exists it becomes corroboration.

### Measurement and calibration

Each Teste answers a different question, and only one of them can justify a weight.

**Point-in-time (PIT)**:
An aggregate over a team's fixtures rebuilt from only the matches that kicked off
before the fixture being rated. The default for anything the Score reads.
_Avoid_: histórico, média da temporada (both are silent about where the cut is)

**Base limpa / base contaminada**:
The premissa data as recomputed point-in-time, versus the same data before that
correction. The contaminated state is kept only to audit the difference — no
conclusion may rest on it.

**Teste 1**:
A premissa's hit rate where it fired, minus the average hit rate of comparable lines.
Answers "does it predict the line?". Needs no odds, so it runs on the full history.

**Teste 2**:
A premissa's hit rate where it fired, minus the fair probability the price implied on
those same lines. Answers "does it beat the price?" — the only Teste that may justify a
weight, and it runs only on the odds era.

**Teste 3**:
The ROI of a gate (e.g. "2+ premissas acesas") at flat stakes on the best odd.
Answers "does a counting rule select bets?".

**Teste 4**:
The ROI by band of nota ponderada. Answers "does the score *order* bets?" — the
product question, which counting never asked.

**Nota ponderada**:
A 0–100 rating built from premissas weighted by their measured Teste 2 gain and
normalised per mercado. It exists only in analysis, and is not the Score de
Confiabilidade — whose weights are hand-set.
_Avoid_: score (reserved for the Score de Confiabilidade)

**Peso de catálogo / peso medido**:
A peso de catálogo is the point weight a premissa carries in production, chosen by hand
and never derived; a peso medido comes from that premissa's Teste 2 gain. Rewriting the
first from the second requires an out-of-sample control (ADR 0001).

**Amostra curta**:
A fixture whose teams have played too few matches for a season aggregate to mean
anything — structural in knockout competitions, and an established cause of fabricated
signal.

**Escopo do PIT**:
Which competitions a PIT aggregate counts. Today it is *da competição*: only fixtures of the
same competition as the one being rated. It is **not one join** — `int_futebol_team_form_pit`
holds one, and each of the five premissa models holds its own local history besides (the `last5`
of Gols, BTTS and Dupla Chance, the Handicap's `margin_stats`, the xG/ritmo spine). Nine
predicates over six models; the axis reaches all of them or the cell comes out mixed. Table sheet
in ADR 0007.
_Avoid_: "juntar os campeonatos" (silent about whether escopo, recorte, or both is changing)

**Recorte do PIT**:
Which stretch of past fixtures a PIT aggregate counts. Today it is season-to-date. A counting
recorte ("the last N") crosses the season boundary by construction; a season recorte does not.
_Avoid_: janela — that word is taken by the odds collection window, and the two are unrelated

**Célula de medição**:
One combination of escopo and recorte under which the whole premissa layer is rematerialised
and remeasured. Two cells are comparable only if computed in the same run over the same frozen
universe. The four are `base`, `escopo`, `recorte` and `ambos`, named for the axis each releases.
_Avoid_: C1–C4 (C1, C2 and C3 already name subtasks of the [C] Coleta task)

**Universo congelado**:
The fixed set of fixtures every célula is measured over — the [0.1]'s published window, 169
fixtures. Its ceiling is an **instant**, not a date: the [0.1] ran mid-day with no frozen cutoff,
so `DATE(kickoff) <= '2026-08-04'` returns 178 and only `kickoff < 04/08 12:00 UTC` returns the
published 169. Written once in `taskf_universo()`; see `docs/TASKF_RESULTADOS.md`.
_Avoid_: janela in prose — that word already names the odds collection window and its two
derivatives, and this is a third unrelated thing. Say "universo congelado" or "o corte".
The `janela_ini` / `janela_fim` **columns** are the one exception, and deliberate: they are the
[0.1]'s own column names, carried over so the measured output lines up with the published table
field for field. Renaming them would buy vocabulary hygiene at the cost of the reconciliation
being eyeball-checkable against the doc.

**min_jogos**:
The smaller of the two teams' prior-fixture counts for a rated fixture, under the escopo and
recorte in force. It is the number the piso de amostra cuts on, and what makes a fixture an
amostra curta.
_Avoid_: jogos disputados (ambiguous between the two teams)

**min_jogos disponível / usado**:
*Disponível* is how many prior fixtures exist in the escopo; *usado* is how many fed the average.
They diverge only under a counting recorte, which saturates. The piso always cuts on disponível,
so that it means the same thing in every célula.

**Piso de amostra**:
The minimum min_jogos for a line to enter a measurement. A parameter of the measurement, never
of the Motor in production.

**Premissa de tabela**:
A premissa whose input is the team's standing — rank, ppg, or the size of the league. There are
four. A league table exists inside one competition, so these have no juntado escopo and their
numbers are identical across células by construction. See ADR 0008.

**Família de competição**:
How a competition labels its seasons: *ano-calendário* (Brasileirão, Série B, the cups, Copa do
Mundo) or *split-year* (the European leagues and the Champions, where season N means N/N+1). A
team belongs to one family, and the family decides whether releasing escopo without releasing
recorte does anything for it.
