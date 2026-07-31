# NBA Player Props

Analytics for NBA player-prop betting: measure how an injured player's absence lifts
teammates' stats, and score daily betting opportunities against bookmaker lines.

## Language

### Core analysis

**COM**:
The subset of a teammate's games in which the trigger player played.
_Avoid_: with-games, together games

**SEM**:
The subset of a teammate's games in which the trigger player did not play. The side of
the split where betting value appears.
_Avoid_: without-games

**360 analysis**:
The full COM-vs-SEM comparison for every trigger/teammate pair, with no score gate
applied. Feeds both the daily opportunities and the Analise 360 UI.

**Gap**:
How much a backup's SEM average exceeds the betting line (absolute or %). The core
value signal.
_Avoid_: edge, delta

**Pilling**:
This codebase's word for unpivoting wide stat columns into long format — one row per
player/game/stat type.
_Avoid_: unpivoting, melting

### Players and roles

**Trigger player**:
An injured/doubtful/questionable player whose absence may boost teammates' stats and
create betting value.
_Avoid_: injured leader, absent star

**Backup player**:
A teammate with positive SEM lift — better stats when the trigger is out.
_Avoid_: substitute, replacement

**Trigger freshness**:
How recent the trigger's injury information is. Stale triggers are filtered out or
scored down.

### Daily pipeline and scoring

**Daily pipeline**:
The current-date run that refreshes today's triggers, COM/SEM aggregates and scored
opportunities. Must complete before games start.

**Slate**:
The set of NBA games on a given day.

**Opportunity**:
A trigger/backup/stat/line combination scored for today's slate. Score below 40 means
it is not an opportunity at all.

**Score**:
The 0–100 confidence rating of an opportunity — a weighted blend of gap vs line,
sample size, trigger freshness, opponent matchup, ambient factors and variation.

**Confidence label**:
The score band shown to users: ALTA CONFIANCA (>= 80), MEDIA CONFIANCA (>= 60),
BAIXA CONFIANCA (>= 40). Bands differ from the futebol context.

**B2B (back-to-back)**:
A game played on the day after the team's previous game. A fatigue signal.

### Stats and lines

**Stat type**:
One of the long-format `player_<stat>` measures (points, rebounds, assists, threes,
minutes, ...), including combo stats such as points+rebounds+assists.

**Line**:
The bookmaker's over/under threshold for a player stat in a game (DraftKings is the
source).
_Avoid_: prop threshold, spread
