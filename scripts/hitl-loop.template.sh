#!/usr/bin/env bash
# Human-in-the-loop reproduction loop.
# Copy this file, edit the steps below, and run it.
# The agent runs the script; the user follows prompts in their terminal.
# (Referenced by the mattpocock-skills /diagnosing-bugs skill as scripts/hitl-loop.template.sh.)
#
# Usage:
#   bash scripts/hitl-loop.template.sh
#
# Two helpers:
#   step "<instruction>"          → show instruction, wait for Enter
#   capture VAR "<question>"      → show question, read response into VAR
#
# At the end, captured values are printed as KEY=VALUE for the agent to parse.

set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Enter when done] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

# --- edit below ---------------------------------------------------------

step "Abra o painel/BI e localize a linha suspeita (ex.: a oportunidade do jogador X em dim_daily_opportunities)."

capture DIVERGIU "O valor exibido diverge do que a query no BigQuery retorna? (y/n)"

capture VALOR_EXIBIDO "Cole o valor exibido no painel (ou 'none'):"

# --- edit above ---------------------------------------------------------

printf '\n--- Captured ---\n'
printf 'DIVERGIU=%s\n' "$DIVERGIU"
printf 'VALOR_EXIBIDO=%s\n' "$VALOR_EXIBIDO"
