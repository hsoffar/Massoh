#!/usr/bin/env bash
# massoh verb: intake — append a ranked idea row to AGENT_BACKLOG.md ## Intake inbox section.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null
#
# PRIORITY HEURISTIC (IK5) — deterministic keyword scan, zero LLM, documented here:
#   P0: idea contains any of: bug, broken, crash, fail, urgent, security, block
#   P1: idea contains any of: add, implement, ship, feature, new verb, enable, integrate
#   P2: idea contains any of: improve, optimize, refactor, update, enhance
#   P3: everything else
# All keyword matches are case-insensitive. No NLP, no subprocess that can fail opaquely.
# Keywords live in named constants below for future localization or replacement.
#
# SAFE-APPEND DESIGN (IK1):
#   The ONLY permitted write to AGENT_BACKLOG.md is a single `printf >> "$BACKLOG"`.
#   No in-place file editor (sed, awk rewrite), no `> file` redirect, no `mv tmp file`.
#   Queue / Done / Frozen sections are NEVER touched.
#   A dedicated `## Intake inbox` section is bootstrapped at end-of-file (after Done/Frozen)
#   via a one-time `printf >>` when the section header is absent. All subsequent appends
#   add one row to that section only.

# Priority heuristic keyword sets (IK5: named constants for auditability)
readonly _IK_P0_KEYWORDS="bug|broken|crash|fail|urgent|security|block"
readonly _IK_P1_KEYWORDS="add|implement|ship|feature|new verb|enable|integrate"
readonly _IK_P2_KEYWORDS="improve|optimize|refactor|update|enhance"

cmd_intake() {
  # IK3: arg guard is the FIRST executable statement — missing idea → die, write nothing.
  [ $# -ge 1 ] || { printf 'massoh intake: usage: massoh intake "<idea>"\n' >&2; exit 1; }

  local idea_raw="$1"

  # IK2: sanitize | \n \r tab; then truncate to 200 chars; then reject empty-after-strip.
  # Zero sed — pure bash parameter expansion only.
  local idea_clean
  idea_clean="${idea_raw//|/ }"              # strip pipe chars (markdown table delimiters)
  idea_clean="${idea_clean//$'\n'/ }"        # strip newlines
  idea_clean="${idea_clean//$'\r'/ }"        # strip carriage returns
  idea_clean="${idea_clean//$'\t'/ }"        # strip tabs
  # Trim leading spaces via bash parameter expansion (no sed, no awk)
  while [[ "${idea_clean:0:1}" == ' ' ]]; do idea_clean="${idea_clean:1}"; done
  # Trim trailing spaces
  while [[ "${idea_clean: -1}" == ' ' ]]; do idea_clean="${idea_clean:0:${#idea_clean}-1}"; done
  idea_clean="${idea_clean:0:200}"           # truncate to 200 chars (after strip, so cell is bounded)
  [ -n "$idea_clean" ] || { printf 'massoh intake: idea is empty after sanitization.\n' >&2; exit 1; }

  # Resolve repo root
  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

  # IK8: Massoh-project guard before any write
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } \
    || { printf 'massoh intake: not a Massoh project (run: massoh on).\n' >&2; exit 1; }

  # IK1: named BACKLOG var + SAFETY comment
  local BACKLOG="$repo/AGENT_BACKLOG.md"  # SAFETY: only permitted write in cmd_intake

  # IK4: idempotency check — if idea already present, skip and exit 0 (|| true: missing file degrades)
  if grep -qF "$idea_clean" "$BACKLOG" 2>/dev/null || true; then
    if grep -qF "$idea_clean" "$BACKLOG" 2>/dev/null; then
      printf 'massoh intake: idea already in %s — skipping (idempotent).\n' "$BACKLOG"
      exit 0
    fi
  fi

  # IK5: deterministic priority heuristic — keyword scan on lowercased idea
  local idea_lower priority
  idea_lower="$(printf '%s' "$idea_clean" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$idea_lower" | grep -qiE "$_IK_P0_KEYWORDS"; then
    priority="P0"
  elif printf '%s' "$idea_lower" | grep -qiE "$_IK_P1_KEYWORDS"; then
    priority="P1"
  elif printf '%s' "$idea_lower" | grep -qiE "$_IK_P2_KEYWORDS"; then
    priority="P2"
  else
    priority="P3"
  fi

  # IK7: if BACKLOG absent, bootstrap it (mkdir -p + section header via >>)
  mkdir -p "$(dirname "$BACKLOG")"
  if [ ! -f "$BACKLOG" ]; then
    printf '# AGENT_BACKLOG\n\n## Intake inbox\n| # | Pri | Item | Status |\n|---|---|---|---|\n' >> "$BACKLOG" # SAFETY: only permitted write in cmd_intake
  fi

  # Bootstrap the ## Intake inbox section header if it is not already present (|| true: absent file already handled above)
  if ! grep -qF '## Intake inbox' "$BACKLOG" 2>/dev/null || true; then
    if ! grep -qF '## Intake inbox' "$BACKLOG" 2>/dev/null; then
      printf '\n## Intake inbox\n| # | Pri | Item | Status |\n|---|---|---|---|\n' >> "$BACKLOG" # SAFETY: only permitted write in cmd_intake
    fi
  fi

  # Compute row number: count existing rows in the Intake inbox section (|| true: degrade to 1)
  local row_num
  row_num="$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$BACKLOG" 2>/dev/null || true)"
  row_num=$(( row_num + 1 ))

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # IK1: single printf >> — the ONLY write to AGENT_BACKLOG.md (Queue/Done/Frozen never touched)
  printf '| %d | %s | %s | TODO |\n' "$row_num" "$priority" "$idea_clean" >> "$BACKLOG" # SAFETY: only permitted write in cmd_intake

  say "massoh intake: queued [$priority] \"$idea_clean\""

  # IK6: memory pointer — append to memory/MEMORY.md (|| true: failure is non-fatal)
  local MEMORY="$repo/memory/MEMORY.md"
  mkdir -p "$repo/memory" 2>/dev/null || true
  local idea_short; idea_short="${idea_clean:0:60}"
  printf -- '- [intake: %s](%s)\n' "$idea_short" "$ts" >> "$MEMORY" 2>/dev/null || true # SAFETY: only permitted write in cmd_intake (secondary)
}
