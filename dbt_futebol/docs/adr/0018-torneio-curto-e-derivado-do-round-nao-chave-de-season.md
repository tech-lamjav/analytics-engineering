---
status: proposed
---

# Torneio curto (Apertura/Clausura) é derivado do round, não chave de `season`

Argentina, Colômbia, Peru e México rodam dois torneios curtos por ano dentro da mesma `season` da API (a da Liga MX é split-year, e as outras três são ano-calendário). Decidimos **manter `competition` e `season` como estão e derivar o torneio corrente do `round`/`group_name`**, com um mapeamento por liga e não uma regex, porque os rótulos mudam entre temporadas (Argentina "1st Phase"/"2nd Phase" em 2025 e "Apertura"/"Clausura" em 2026; México "Reclasificación" com e sem acento).

O que quebra hoje com dois torneios por `season` é enumerável: o CTE `tabela` acumula rank e ppg dos dois torneios, o `team_group` escolhe um grupo de forma arbitrária em empate de `snapshot_date`, o `n_teams` da Argentina dá 30 contra zonas de 15 (e `s_rank >= n_teams - 3` nunca dispara), e as quatro premissas de tabela leem esses campos. O last-10 do PIT não quebra: cruza competições por desenho desde a #91, e o piso 5 não morde na virada porque `played_total_disponivel` conta todo jogo anterior.

No dia 0 as quatro ligas ficam **fora** de `futebol_ligas_pontos_corridos()`, como UCL e Libertadores, para as premissas de tabela silenciarem em vez de disparar sobre uma tabela sem sentido, até a derivação existir. Falta confirmar no PR que essa via cobre as quatro premissas.

## Considered options

**Competição = liga + torneio (slug distinto).** Rejeitada: os 6 `CASE` de slug deixam de ser função só de `league_id`, e `fact_team_season_stats`, odds, injuries e predictions não têm chave de torneio (a API serve as estatísticas acumuladas nos dois).

**`season` sintética (f(ano, torneio)).** Rejeitada: todo join por `(competition_id, season)` passaria a separar a tabela sozinho, mas mexe em 23 tabelas sincronizadas, e a retenção do DEV, que compara `season` com um inteiro (2026), falharia.

## Consequences

O torneio derivado depende de rótulos que a API muda sem aviso, então o mapeamento por liga é dívida de manutenção. O app hoje trata `Apertura - N` como mata-mata (o classificador só reconhece `Regular Season - N`), e a `get_futebol_standings_official` devolve 2 a 3 linhas por time, o que é do lado do Victor. Vale para o Peru também, que a task de origem não cita.
