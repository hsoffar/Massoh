#!/usr/bin/env bash
# massoh verb: standup — the progress-delta "ceremony": what moved since last tick.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# standup — the progress-delta "ceremony": what moved since last tick (read-only + optional sync append).
cmd_standup() {
  local since=1 write=1
  while [ $# -gt 0 ]; do case "$1" in --since) shift; since="${1:-1}";; --no-write) write=0;; *) die "unknown standup flag: $1";; esac; shift; done
  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local commits="(none)" doing="(none)" blocked="(none)" inflight="(none)" d
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    commits="$(git -C "$repo" log --since="$since days ago" --pretty='%h %s' 2>/dev/null | sed 's/^/    - /')"; [ -z "$commits" ] && commits="    (none)"
  fi
  local bl="$repo/AGENT_BACKLOG.md"
  if [ -f "$bl" ]; then
    doing="$(grep -E '\| DOING \|' "$bl" | sed -E 's/^/    -/; s/\|/ /g' || true)"; [ -z "$doing" ] && doing="    (none)"
    blocked="$(grep -E '\| BLOCKED \|' "$bl" | sed -E 's/^/    -/; s/\|/ /g' || true)"; [ -z "$blocked" ] && blocked="    (none)"
  fi
  if [ -d "$repo/.agent_tasks" ]; then
    inflight=""; for d in "$repo"/.agent_tasks/TASK-*/; do [ -d "$d" ] || continue
      [ -f "${d}04_implementation_packet.md" ] && [ ! -f "${d}06_review_result.md" ] && inflight="$inflight    - $(basename "$d")"$'\n'; done
    [ -z "$inflight" ] && inflight="    (none)" || inflight="${inflight%$'\n'}"
  fi
  local report="massoh standup — $ts  (since ${since}d)
  commits:
$commits
  DOING:
$doing
  BLOCKED:
$blocked
  in-flight packets (licensed, unreviewed):
$inflight"
  say "$report"
  if [ "$write" = 1 ] && [ -f "$repo/AGENT_SYNC.md" ]; then
    { printf '\n## [standup] %s\n' "$ts"; printf '%s\n' "$report" | sed '1d; s/^  /- /; s/^    /  /'; } >> "$repo/AGENT_SYNC.md"
    say "  → appended to AGENT_SYNC.md"
  fi
}
