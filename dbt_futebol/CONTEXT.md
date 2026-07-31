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
points + corroboration points, minus penalties, clamped.

**Premissa**:
A boolean context signal computed from the data, carrying a point weight. Fired
premissas add to the score and become evidence bullets.
_Avoid_: feature, predictor

**Gate**:
The eliminatory precondition (positive edge and enough bookmakers). Failing the gate
means the bet is not an opportunity at all. Dupla Chance has its own gate.

**Faixa**:
The confidence band over the score: Alta (>= 60), Média (40–59), Baixa (< 40).
Thresholds differ from the NBA context.

**Value opportunity**:
A fixture x market x outcome that passed the gate with positive edge — the product's
unit of output.
_Avoid_: pick, tip

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
Missing data means the premissa simply does not fire — never an error or NULL. The
score gets honestly lower.

### Odds and value

**Edge**:
The margin by which the best available odd beats the fair closing probability
(best odd x fair probability − 1).

**De-vig**:
Removing the bookmaker margin (overround) from a market's full set of odds to obtain
fair probabilities.

**Prob justa de fechamento**:
The fair probability obtained by de-vigging Pinnacle's closing odds — the benchmark
any value claim must beat.

**Sharp**:
Pinnacle, the reference bookmaker. "Linha sharp" is its price; its movement toward our
side is corroboration.
_Avoid_: soft book (that is the opposite concept)

**Janela**:
The odds collection window relative to kickoff: t24h, t1h, t15m. The latest available
acts as the fechamento (closing).

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
"Questionable" (dúvida) is displayed but never fires.
_Avoid_: injury (a desfalque may be suspension or other absence)

**Titular importante**:
A regular starter by minutes played and start share — the importance proxy that makes
a desfalque matter.

**Rodízio**:
Squad rotation — resting starters when a bigger match looms. "Sem rodízio" means the
game matters and no midweek decision competes.

**xG (expected goals)**:
Shot-quality-based goal expectation; the strongest form signal. Only rich for the
Brasileirão — elsewhere xG premissas degrade gracefully.

**Forma**:
Recent results run (wins in last 5). Deliberately low-weight: it mostly duplicates
underlying strength.

**H2H**:
Head-to-head history between the two teams.

**Pilar A / Pilar B**:
Pilar A is this rules engine. Pilar B is the future proper statistical model
(Dixon-Coles + xG) — out of scope today; when it exists it becomes corroboration.
