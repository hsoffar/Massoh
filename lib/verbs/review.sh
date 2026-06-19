#!/usr/bin/env bash
# massoh verb: review — the KPI "review ceremony": gather metrics (read-only) + append a METRICS snapshot.
# Sourced by bin/massoh at startup. Requires: say, die, mver, msha, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# review — the KPI "review ceremony": gather metrics (read-only) + append a METRICS snapshot.
cmd_review() {
  local since=7 write=1 runtests=0
  while [ $# -gt 0 ]; do case "$1" in
    --since) shift; since="${1:-7}";; --no-write) write=0;; --run-tests) runtests=1;;
    *) die "unknown review flag: $1";; esac; shift; done
  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local pt=0 prev=0 plic=0 d
  # --- v2 KPI accumulators ---
  local cycle_total_days=0 cycle_count=0 rework_count=0 throughput_count=0
  local now_epoch; now_epoch=$(date +%s)
  local since_secs=$(( since * 86400 ))
  if [ -d "$repo/.agent_tasks" ]; then
    for d in "$repo"/.agent_tasks/TASK-*/; do [ -d "$d" ] || continue; pt=$((pt+1))
      local f06="${d}06_review_result.md" f00="${d}00_request.md"
      [ -f "$f06" ] && prev=$((prev+1))
      [ -f "${d}04_implementation_packet.md" ] && plic=$((plic+1))
      # v2: cycle time + rework rate + throughput (only for packets with 06) (Condition B2: || true on all greps)
      if [ -f "$f06" ]; then
        # rework rate: check if 06 contains REQUEST CHANGES on a decision line (mirrors cmd_learn pattern)
        local rc_line; rc_line=$(grep -iE "decision.*REQUEST CHANGES" "$f06" 2>/dev/null || true)
        [ -n "$rc_line" ] && rework_count=$((rework_count+1))
        # throughput: was this packet reviewed within --since window? (git log commit time, Condition B1)
        local f06_ct; f06_ct=$(git -C "$repo" log -1 --format=%ct -- "$f06" 2>/dev/null || true)
        if [ -n "$f06_ct" ] && [ "$f06_ct" -gt 0 ] 2>/dev/null; then
          local age=$(( now_epoch - f06_ct ))
          [ "$age" -le "$since_secs" ] && throughput_count=$((throughput_count+1))
        fi
        # cycle time: 00 → 06 git commit timestamps (Condition B1: git log %ct; stat BANNED)
        if [ -f "$f00" ]; then
          local t00 t06
          t00=$(git -C "$repo" log -1 --format=%ct -- "$f00" 2>/dev/null || true)
          t06=$(git -C "$repo" log -1 --format=%ct -- "$f06" 2>/dev/null || true)
          # If either file is not in git history, cycle time = n/a for this packet (degrade gracefully)
          if [ -n "$t00" ] && [ -n "$t06" ] && [ "$t00" -gt 0 ] 2>/dev/null && [ "$t06" -gt 0 ] 2>/dev/null; then
            local diff_days=$(( (t06 - t00) / 86400 ))
            [ "$diff_days" -lt 0 ] && diff_days=0
            cycle_total_days=$(( cycle_total_days + diff_days ))
            cycle_count=$(( cycle_count + 1 ))
          fi
        fi
      fi
    done
  fi
  local popen=$((pt - prev))
  # v2 KPI computations (Condition B3: division-by-zero guards before all arithmetic)
  local cycle_avg_days="n/a"
  [ "$cycle_count" -gt 0 ] && cycle_avg_days=$(( cycle_total_days / cycle_count ))
  local rework_pct=0
  [ "$prev" -gt 0 ] && rework_pct=$(( rework_count * 100 / prev ))  # Condition B3: guard prev>0
  local throughput_per_week="n/a"
  if [ "$since" -gt 0 ]; then
    throughput_per_week=$(( throughput_count * 7 / since ))  # packets per week
  fi
  local bl="$repo/AGENT_BACKLOG.md" td=0 dg=0 dn=0 bk=0
  if [ -f "$bl" ]; then
    td=$(grep -c '| TODO |' "$bl" || true); dg=$(grep -c '| DOING |' "$bl" || true)
    dn=$(grep -c '| DONE |' "$bl" || true); bk=$(grep -c '| BLOCKED |' "$bl" || true)
  fi
  local prs=0 commits=0 reverts=0 featb=0 cronb=0
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    prs=$(git -C "$repo" log --oneline 2>/dev/null | grep -cE '\(#[0-9]+\)' || true)
    commits=$(git -C "$repo" log --oneline --since="$since days ago" 2>/dev/null | wc -l | tr -d ' ')
    reverts=$(git -C "$repo" log --oneline 2>/dev/null | grep -ci revert || true)
    featb=$(git -C "$repo" branch --list 'feat/*' 2>/dev/null | grep -c . || true)
    cronb=$(git -C "$repo" branch --list 'cron/*' 2>/dev/null | grep -c . || true)
  fi
  local testline="skipped (--run-tests to run)"
  [ "$runtests" = 1 ] && [ -f "$repo/test/run.sh" ] && testline="$(cd "$repo" && bash test/run.sh 2>&1 | tail -1)"
  local report="massoh review — $ts  (v$(mver))
  packets:   $pt total · $prev reviewed · $plic licensed · $popen open
  backlog:   $td TODO · $dg DOING · $dn DONE · $bk BLOCKED
  delivery:  $prs PRs merged · $commits commits/${since}d · $reverts reverts
  branches:  $featb feat/* · $cronb cron/*
  quality:   $testline
  kpi:       cycle_avg_days=$cycle_avg_days · rework_pct=$rework_pct · throughput/wk=$throughput_per_week"
  say "$report"
  if [ "$write" = 1 ]; then
    mkdir -p "$repo/agent-project"
    # Condition B4: new KPI lines appended WITHIN same snapshot block (not a separate block)
    { printf '\n## Snapshot %s (v%s)\n' "$ts" "$(mver)"
      printf '%s\n' "$report" | sed '1d; s/^  /- /'
      printf -- '- cycle_avg_days=%s\n' "$cycle_avg_days"
      printf -- '- rework_pct=%s\n' "$rework_pct"
      printf -- '- throughput/wk=%s\n' "$throughput_per_week"
      printf -- '- reverts=%s\n' "$reverts"
      printf -- '- backlog_todo=%s\n' "$td"
    } >> "$repo/agent-project/METRICS.md"
    say "  → appended snapshot to agent-project/METRICS.md"
  fi
}
