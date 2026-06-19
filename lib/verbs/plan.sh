#!/usr/bin/env bash
# massoh verb: plan — the planning "ceremony": prioritized queue + surface owner decisions.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# plan — the planning "ceremony": prioritized queue + surface owner decisions (read-only + optional append).
cmd_plan() {
  local write=1
  while [ $# -gt 0 ]; do case "$1" in --no-write) write=0;; *) die "unknown plan flag: $1";; esac; shift; done
  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local queue="(none)" decisions="(none)" blocked="(none)"
  local bl="$repo/AGENT_BACKLOG.md"
  if [ -f "$bl" ]; then
    queue="$(awk -F'|' '/^\|/{st=$6;gsub(/^[ \t]+|[ \t]+$/,"",st); if(st=="TODO"){pr=$3;it=$4;gsub(/^[ \t]+|[ \t]+$/,"",pr);gsub(/^[ \t]+|[ \t]+$/,"",it);print "    - ["pr"] "it}}' "$bl")"; [ -z "$queue" ] && queue="    (none)"
    blocked="$(grep -E '\| BLOCKED \|' "$bl" | sed -E 's/^/    -/; s/\|/ /g' || true)"; [ -z "$blocked" ] && blocked="    (none)"
  fi
  local sy="$repo/AGENT_SYNC.md"
  if [ -f "$sy" ]; then
    decisions="$(awk '/^## Open questions/{f=1;next} /^## /{f=0} f && /^\| / && $0 !~ /Question|^\|-|---/ {print "    -"$0}' "$sy" | sed 's/|/ /g')"; [ -z "$decisions" ] && decisions="    (none open)"
  fi
  local report="massoh plan — $ts
  queue (top = next):
$queue
  owner decisions needed:
$decisions
  BLOCKED:
$blocked"
  say "$report"
  if [ "$write" = 1 ] && [ -f "$sy" ]; then
    { printf '\n## [plan] %s\n' "$ts"; printf '%s\n' "$report" | sed '1d; s/^  /- /; s/^    /  /'; } >> "$sy"
    say "  → appended to AGENT_SYNC.md"
  fi
}
