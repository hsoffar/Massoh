#!/usr/bin/env bash
# massoh verb: ledger — append a cost row (add) or print an aggregated report (no args).
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# ledger — append a cost row (add) or print an aggregated report (no args). POSIX bash,
# set -euo pipefail compatible. Sole write target: $repo/.agent_tasks/ledger.tsv.
cmd_ledger() {
  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  # SAFETY: only permitted write in cmd_ledger
  local LEDGER="$repo/.agent_tasks/ledger.tsv"

  local subcmd="${1:-}"; shift || true

  case "$subcmd" in
    add)
      # L3: arg-count guard is the first statement in the add branch
      [ $# -eq 4 ] || { printf 'massoh ledger add: expected 4 args (task-id stage tokens seconds), got %d\n' "$#" >&2; exit 1; }

      local task_id="$1" stage="$2" tokens="$3" seconds="$4"

      # L1: strip \t \n \r from task-id and stage; die if empty after stripping
      task_id="${task_id//$'\t'/}"; task_id="${task_id//$'\n'/}"; task_id="${task_id//$'\r'/}"
      # L9: stage: free-form in v1; future versions may add enum validation
      stage="${stage//$'\t'/}";   stage="${stage//$'\n'/}";   stage="${stage//$'\r'/}"
      [ -n "$task_id" ] || { printf 'massoh ledger add: task-id is empty after stripping whitespace\n' >&2; exit 1; }
      [ -n "$stage"   ] || { printf 'massoh ledger add: stage is empty after stripping whitespace\n' >&2; exit 1; }

      # L2: validate tokens and seconds as non-negative integers BEFORE any file touch
      [[ "$tokens"  =~ ^[0-9]+$ ]] || { printf 'massoh ledger: tokens must be a non-negative integer, got: %s\n' "$tokens" >&2; exit 1; }
      [[ "$seconds" =~ ^[0-9]+$ ]] || { printf 'massoh ledger: seconds must be a non-negative integer, got: %s\n' "$seconds" >&2; exit 1; }

      # L4: mkdir-p then single atomic printf->> append (the ONLY write in cmd_ledger)
      mkdir -p "$repo/.agent_tasks"
      local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$task_id" "$stage" "$tokens" "$seconds" >> "$LEDGER"
      ;;

    "")
      # Report verb — read-only; no >> path.
      # L7: if ledger absent → human-readable message, exit 0, no file created
      [ -f "$LEDGER" ] || { printf '  (no ledger data — run: massoh ledger add <task-id> <stage> <tokens> <seconds>)\n'; exit 0; }

      local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'massoh ledger — %s  (v%s)\n' "$ts" "$(mver)"
      local nrows; nrows="$(wc -l < "$LEDGER" 2>/dev/null || echo 0)"
      printf '  ledger: %s rows  (%s)\n\n' "$nrows" ".agent_tasks/ledger.tsv"

      # L6 + L5: awk aggregation with malformed-row guard and division-by-zero guard
      # L7: awk invocation terminated with || true
      awk -F'\t' '
        # L6: skip rows with fewer than 5 fields
        NF < 5 { next }
        # L6: skip rows where tokens or seconds is non-numeric
        $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
        {
          task = $2; stage = $3; tok = $4 + 0; sec = $5 + 0
          # per-task accumulators
          task_tok[task]   += tok
          task_sec[task]   += sec
          task_count[task] += 1
          # per-stage accumulators
          stg_tok[stage]   += tok
          stg_sec[stage]   += sec
          stg_count[stage] += 1
          # totals
          total_tok  += tok
          total_sec  += sec
        }
        END {
          print "  Per-task summary:"
          for (t in task_tok) {
            cnt = task_count[t]
            # L5: division-by-zero guard on every average
            avg = (cnt > 0) ? int(task_tok[t] / cnt) : "n/a"
            printf "    %-40s tokens=%-8d seconds=%-8d avg_tokens/stage=%-8s stages=%d\n", \
              t, task_tok[t], task_sec[t], avg, cnt
          }
          printf "    %-40s tokens=%-8d seconds=%d\n", "TOTAL", total_tok, total_sec
          print ""
          print "  Per-stage summary:"
          for (s in stg_tok) {
            cnt = stg_count[s]
            # L5: division-by-zero guard on every average
            avg = (cnt > 0) ? int(stg_tok[s] / cnt) : "n/a"
            printf "    %-20s tokens=%-8d seconds=%-8d count=%-4d avg_tokens=%s\n", \
              s, stg_tok[s], stg_sec[s], cnt, avg
          }
        }
      ' "$LEDGER" || true
      ;;

    *)
      printf 'massoh ledger: unknown sub-command %q. usage: massoh ledger [add <task-id> <stage> <tokens> <seconds>]\n' "$subcmd" >&2
      exit 1
      ;;
  esac
}
