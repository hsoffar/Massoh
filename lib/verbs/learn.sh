#!/usr/bin/env bash
# massoh verb: learn — heuristic read-only miner: review history, decision log, git reverts → lessons report.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# learn — heuristic read-only miner: review history, decision log, git reverts → lessons report.
# NO LLM / NO claude -p / zero spend. Proposals (--write-proposals) go ONLY to LEARNINGS.proposed.md.
cmd_learn() {
  local since=0 write_proposals=0
  while [ $# -gt 0 ]; do case "$1" in
    --since)           shift; since="${1:-0}";;
    --write-proposals) write_proposals=1;;
    --no-write)        write_proposals=0;;
    *) die "unknown learn flag: $1";;
  esac; shift; done

  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"

  # Non-Massoh-project guard (same pattern as cmd_discover)
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } \
    || die "not a Massoh project (run: massoh on)."

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # task-packet-spec: these heading/keyword names match mandatory sections in 11_TASK_PACKET_SPEC.md
  # and the AGENT_SYNC schema. Extracted as named variables for future multi-language projects.
  local _PAT_BLOCKING='## Blocking'
  local _PAT_NONBLOCKING='## Non-blocking'
  local _PAT_REQUEST_CHANGES='REQUEST CHANGES'
  local _PAT_DECISION_LOG='## Decision log'
  local _PAT_ADR_FLAG='irreversible'

  # --- 1. Scan 06_review_result.md + 05_implementation_handoff.md ---
  local blocking_lines="" nonblocking_lines="" risks_lines="" packet_count=0

  if [ -d "$repo/.agent_tasks" ]; then
    local d
    for d in "$repo"/.agent_tasks/TASK-*/; do
      [ -d "$d" ] || continue
      local f06="${d}06_review_result.md"
      local f05="${d}05_implementation_handoff.md"

      # Apply --since filter via mtime (0 means no filter)
      if [ "$since" -gt 0 ]; then
        local recent06=0 recent05=0
        [ -f "$f06" ] && recent06=$(find "$f06" -mtime -"${since}" 2>/dev/null | grep -c . || true)
        [ -f "$f05" ] && recent05=$(find "$f05" -mtime -"${since}" 2>/dev/null | grep -c . || true)
        [ "$recent06" -eq 0 ] && [ "$recent05" -eq 0 ] && continue
      fi

      packet_count=$((packet_count + 1))

      # Mine blocking section from 06
      if [ -f "$f06" ]; then
        local b; b=$(awk -v hdr="$_PAT_BLOCKING" '
          /^## /{if($0~hdr){in_s=1;next}else{in_s=0}}
          in_s && /\S/{print}
        ' "$f06" || true)
        [ -n "$b" ] && blocking_lines="$blocking_lines"$'\n'"$(basename "$d"): $b"

        # Mine non-blocking section from 06
        local nb; nb=$(awk -v hdr="$_PAT_NONBLOCKING" '
          /^## /{if($0~hdr){in_s=1;next}else{in_s=0}}
          in_s && /\S/{print}
        ' "$f06" || true)
        [ -n "$nb" ] && nonblocking_lines="$nonblocking_lines"$'\n'"$(basename "$d"): $nb"

        # Mine the verdict ONLY when REQUEST CHANGES is on a Decision line (v1.1: avoid code
        # citations like `local _PAT_REQUEST_CHANGES='REQUEST CHANGES'` being mistaken for a finding)
        local rc; rc=$(grep -iE "decision.*${_PAT_REQUEST_CHANGES}" "$f06" 2>/dev/null || true)
        [ -n "$rc" ] && blocking_lines="$blocking_lines"$'\n'"$(basename "$d"): $rc"
      fi

      # Mine risks from 05 — v1.1: extract the CONTENT under a "Risk" heading, not the heading itself
      if [ -f "$f05" ]; then
        local rk; rk=$(awk '
          /^#+ /{ if(tolower($0) ~ /risk/){in_s=1; next} else {in_s=0} }
          in_s && /\S/{print}
        ' "$f05" 2>/dev/null || true)
        [ -n "$rk" ] && risks_lines="$risks_lines"$'\n'"$(basename "$d"): $rk"
      fi
    done
  fi

  # --- 2. Count recurring patterns (keyword seen in 2+ review files) ---
  local recurring_summary="    (none)"
  if [ -n "$blocking_lines" ] && [ -d "$repo/.agent_tasks" ]; then
    local kw_counts; kw_counts=""
    local f06
    for f06 in "$repo"/.agent_tasks/TASK-*/06_review_result.md; do
      [ -f "$f06" ] || continue
      if [ "$since" -gt 0 ]; then
        local recent; recent=$(find "$f06" -mtime -"${since}" 2>/dev/null | grep -c . || true)
        [ "$recent" -eq 0 ] && continue
      fi
      # Extract words (5+ chars) from blocking sections + REQUEST CHANGES lines
      local words; words=$(awk -v hdr="$_PAT_BLOCKING" -v rch="$_PAT_REQUEST_CHANGES" '
        /^## /{if($0~hdr){in_s=1;next}else{in_s=0}}
        in_s && /\S/{print}
        index($0,rch){print}
      ' "$f06" | grep -oE '[A-Za-z_|&]{5,}' || true)
      kw_counts="$kw_counts $words"
    done
    # Count each keyword; surface those seen in 2+ reviews
    local recurring; recurring=$(printf '%s\n' $kw_counts | sort | uniq -c | sort -rn | \
      awk '$1>=2{printf "    - (x%d) %s\n",$1,$2}' || true)
    if [ -n "$recurring" ]; then
      recurring_summary="$recurring"
    else
      recurring_summary="    (none — no pattern seen in 2+ reviews)"
    fi
  fi

  [ -z "$blocking_lines" ]    && blocking_lines="    (none)"
  [ -z "$nonblocking_lines" ] && nonblocking_lines="    (none)"
  [ -z "$risks_lines" ]       && risks_lines="    (none)"

  # --- 3. Decision log ADR candidates ---
  local adr_candidates="    (none)"
  local sy="$repo/AGENT_SYNC.md"
  if [ -f "$sy" ]; then
    # Use grep + awk: grep for irreversible lines in the decision log section
    # Pass variable values via awk -v to avoid literal interpolation pitfalls
    local adr; adr=$(awk -v hdr="$_PAT_DECISION_LOG" -v flag="$_PAT_ADR_FLAG" '
      /^## /{if(index($0,hdr)){in_s=1;next}else{in_s=0}}
      in_s && /\|/ && tolower($0)~flag{print "    -"$0}
    ' "$sy" || true)
    [ -n "$adr" ] && adr_candidates="$adr"
  fi

  # --- 4. Git revert + fixup counts ---
  local revert_count=0 fixup_count=0
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    local gitlog_args="--oneline"
    [ "$since" -gt 0 ] && gitlog_args="$gitlog_args --since=${since} days ago"
    # shellcheck disable=SC2086
    revert_count=$(git -C "$repo" log $gitlog_args 2>/dev/null | grep -ci revert || true)
    # shellcheck disable=SC2086
    fixup_count=$(git -C "$repo" log $gitlog_args 2>/dev/null | grep -ci fixup || true)
  fi

  # --- 5. Build and print the lessons report ---
  local ver; ver="$(mver)"
  say "massoh learn — $ts  (v$ver)  [scanned $packet_count packet(s)]"
  say "  Blocking findings (from 06_review_result.md):"
  say "$blocking_lines"
  say "  Non-blocking findings:"
  say "$nonblocking_lines"
  say "  Recurring review findings (seen in 2+ reviews):"
  say "$recurring_summary"
  say "  Risks seen (from 05_implementation_handoff.md):"
  say "$risks_lines"
  say "  ADR candidates (decision log rows flagged '$_PAT_ADR_FLAG'):"
  say "$adr_candidates"
  say "  Repeated-fix indicators (git):"
  say "    - revert commit(s): $revert_count"
  say "    - fixup commit(s):  $fixup_count"

  # --- 6. Optionally append proposals ---
  if [ "$write_proposals" = 1 ]; then
    local proposals="$repo/agent-project/LEARNINGS.proposed.md"
    mkdir -p "$repo/agent-project"
    {
      printf '\n## [learn] %s (v%s)\n' "$ts" "$ver"
      printf '### Proposed STANDARDS.md Do/Don'"'"'t\n'
      if [ "$blocking_lines" != "    (none)" ]; then
        printf '%s\n' "$blocking_lines" | sed 's/^[[:space:]]*/- /'
      else
        printf -- '- (none)\n'
      fi
      printf '### Possible ADR candidates (from decision log)\n'
      if [ "$adr_candidates" != "    (none)" ]; then
        printf '%s\n' "$adr_candidates"
      else
        printf -- '- (none)\n'
      fi
      printf '### Repeated-fix indicators (git)\n'
      printf -- '- %d revert commit(s) found — review for recurring root causes\n' "$revert_count"
      printf -- '- %d fixup commit(s) found\n' "$fixup_count"
    } >> "$proposals" # SAFETY: only permitted write in cmd_learn
    say "  → appended proposals to $proposals"
  fi
}
