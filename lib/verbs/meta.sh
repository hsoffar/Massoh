#!/usr/bin/env bash
# massoh verb: meta — read-only heuristic miner: ledger cost outliers, rework rate, backlog drift.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# meta — read-only heuristic miner: ledger cost outliers, rework rate, backlog drift, repeated
# review findings. NO LLM / NO claude -p / zero spend. Proposals (--write-proposals) go ONLY to
# agent-project/META.proposed.md (append-only >>). NEVER writes ledger, backlog, sync, or safety files.
cmd_meta() {
  local write_meta=0
  local OUTLIER_FACTOR=2    # M7: named constant — multiplier for stage-token outlier detection
  local REPEAT_THRESHOLD=3  # M7: named constant — count at which a finding is flagged as "promote"

  while [ $# -gt 0 ]; do case "$1" in
    --write-proposals) write_meta=1;;
    --no-write)        write_meta=0;;
    *) die "unknown meta flag: $1. usage: massoh meta [--write-proposals|--no-write]";;
  esac; shift; done

  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

  # S4 / Non-Massoh-project guard (same pattern as cmd_learn / cmd_discover)
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } \
    || die "not a Massoh project (run: massoh on)."

  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local ver; ver="$(mver)"

  # M1 / S1: SAFETY — the ONLY permitted write in cmd_meta
  local META_PROPOSALS="$repo/agent-project/META.proposed.md"  # SAFETY: only permitted write in cmd_meta

  say "massoh meta — $ts  (v$ver)"

  # -------------------------------------------------------------------
  # Finding 1: Ledger cost analysis — per-stage token outlier detection
  # -------------------------------------------------------------------
  local LEDGER="$repo/.agent_tasks/ledger.tsv"
  local finding1=""

  if [ ! -f "$LEDGER" ]; then
    finding1="  (no ledger data — run: massoh ledger add ... to populate)"
  else
    # M2: awk || true on every invocation; M3: division-by-zero guard inside awk (mirrors cmd_ledger L5)
    # Outlier logic: compute global mean tokens/row across all valid rows;
    # then flag any row where that row's tokens > OUTLIER_FACTOR × global_mean.
    # Also compute per-stage mean for the comparison label.
    finding1="$(awk -F'\t' -v factor="$OUTLIER_FACTOR" '
      NF < 5 { next }
      $4 !~ /^[0-9]+$/ { next }
      {
        task  = $2; stage = $3; tok = $4 + 0
        total_tok += tok
        total_cnt += 1
        # per-stage accumulators for comparison label
        stg_sum[stage] += tok
        stg_cnt[stage] += 1
        # store rows for second pass
        row_task[NR]  = task
        row_stage[NR] = stage
        row_tok[NR]   = tok
      }
      END {
        # M3: division-by-zero guard on global mean
        if (total_cnt == 0) { print "  (no ledger data)"; exit }
        global_mean = total_tok / total_cnt
        found = 0
        for (i = 1; i <= NR; i++) {
          if (!(i in row_tok)) continue
          tok   = row_tok[i]
          stage = row_stage[i]
          task  = row_task[i]
          cnt   = stg_cnt[stage]
          # M3: per-stage mean for label (guard cnt > 0)
          stg_mean = (cnt > 0) ? stg_sum[stage] / cnt : 0
          # M3: guard global_mean > 0 before division
          if (global_mean > 0 && tok > factor * global_mean) {
            printf "  [outlier] task=%s stage=%s tokens=%d vs global-mean=%d (%.1fx)\n", \
              task, stage, tok, int(global_mean), tok/global_mean
            found = 1
          }
        }
        if (!found) print "  (no outlier stages detected)"
      }
    ' "$LEDGER" 2>/dev/null || true)"
    [ -z "$finding1" ] && finding1="  (no outlier stages detected)"
  fi

  say "Finding 1 — Ledger cost outliers (stage tokens > ${OUTLIER_FACTOR}x mean):"
  say "$finding1"

  # -------------------------------------------------------------------
  # Finding 2: Rework rate — packets with REQUEST CHANGES before APPROVE
  # -------------------------------------------------------------------
  local total_pkts=0 rework_count=0 rework_pct=0
  local finding2=""

  if [ -d "$repo/.agent_tasks" ]; then
    local d
    for d in "$repo"/.agent_tasks/TASK-*/; do
      [ -d "$d" ] || continue
      local f06="${d}06_review_result.md"
      [ -f "$f06" ] || continue
      total_pkts=$((total_pkts + 1))
      # M2: grep || true; M10: reads raw file, not METRICS.md
      local rc_line; rc_line="$(grep -iE 'Decision.*REQUEST CHANGES' "$f06" 2>/dev/null || true)"
      [ -n "$rc_line" ] && rework_count=$((rework_count + 1))
    done
  fi

  if [ "$total_pkts" -eq 0 ]; then
    finding2="  (no packet data — no reviewed packets found)"
  else
    # M3: division-by-zero guard
    [ "$total_pkts" -gt 0 ] && rework_pct=$(( rework_count * 100 / total_pkts ))
    local rework_flag=""
    [ "$rework_pct" -gt 25 ] && rework_flag=" [HIGH — consider deepening arch/safety conditions]"
    finding2="  rework_rate=${rework_pct}% (${rework_count}/${total_pkts} packets had REQUEST CHANGES)${rework_flag}"
  fi

  say "Finding 2 — Rework rate (packets with REQUEST CHANGES before APPROVE):"
  say "$finding2"

  # -------------------------------------------------------------------
  # Finding 3: Backlog drift — TODO items whose keyword appears DONE in AGENT_SYNC.md
  # -------------------------------------------------------------------
  local finding3=""
  local bl="$repo/AGENT_BACKLOG.md"
  local sy="$repo/AGENT_SYNC.md"

  if [ ! -f "$bl" ]; then
    finding3="  (no backlog file — AGENT_BACKLOG.md not found)"
  else
    # M2: awk || true; extract TODO item keywords from AGENT_BACKLOG.md
    local todo_items; todo_items="$(awk -F'|' '
      /^\|/ {
        st = $6; gsub(/^[ \t]+|[ \t]+$/, "", st)
        if (st == "TODO") {
          it = $4; gsub(/^[ \t]+|[ \t]+$/, "", it)
          # extract first hyphen-separated word or first word as keyword
          n = split(it, words, /[-_ ]/)
          for (i = 1; i <= n; i++) {
            w = words[i]; gsub(/[^A-Za-z0-9]/, "", w)
            if (length(w) >= 3) { print w; break }
          }
        }
      }
    ' "$bl" 2>/dev/null || true)"

    local drifted=""
    if [ -n "$todo_items" ] && [ -f "$sy" ]; then
      local kw
      while IFS= read -r kw; do
        [ -n "$kw" ] || continue
        # M2: grep || true; check if keyword appears with DONE in the decision log
        local done_line; done_line="$(grep -i "$kw" "$sy" 2>/dev/null | grep -i 'DONE\|APPROVE\|shipped\|merged' 2>/dev/null || true)"
        if [ -n "$done_line" ]; then
          drifted="${drifted}  [drift] keyword='${kw}' appears TODO in backlog but DONE/APPROVE in sync log"$'\n'
        fi
      done <<< "$todo_items"
    fi

    if [ -z "$drifted" ]; then
      finding3="  (no backlog drift detected)"
    else
      finding3="${drifted%$'\n'}"
    fi
  fi

  say "Finding 3 — Backlog drift (TODO items appearing DONE in decision log):"
  say "$finding3"

  # -------------------------------------------------------------------
  # Finding 4: Repeated review findings — classes seen in >= REPEAT_THRESHOLD blocking sections
  # -------------------------------------------------------------------
  local finding4=""
  local packet_count=0

  if [ ! -d "$repo/.agent_tasks" ]; then
    finding4="  (no packet data — .agent_tasks/ not found)"
  else
    # Collect keywords from blocking sections across all 06 files
    local kw_all=""
    local f06
    for f06 in "$repo"/.agent_tasks/TASK-*/06_review_result.md; do
      [ -f "$f06" ] || continue
      packet_count=$((packet_count + 1))
      # M2: awk || true; extract words from Blocking sections
      local words; words="$(awk '
        /^## /{if($0~/Blocking/){in_s=1;next}else{in_s=0}}
        in_s && /\S/{print}
      ' "$f06" 2>/dev/null | grep -oE '[A-Za-z_]{5,}' 2>/dev/null || true)"
      kw_all="${kw_all} ${words}"
    done

    if [ "$packet_count" -eq 0 ]; then
      finding4="  (no packet data — no 06_review_result.md files found)"
    else
      # M2: sort/uniq || true; count keywords; surface those seen >= REPEAT_THRESHOLD times
      local repeated; repeated="$(printf '%s\n' $kw_all | sort 2>/dev/null | uniq -c 2>/dev/null | sort -rn 2>/dev/null | \
        awk -v thr="$REPEAT_THRESHOLD" '$1>=thr{printf "  [repeat x%d] %s — promote to enforced check candidate\n",$1,$2}' 2>/dev/null || true)"
      if [ -n "$repeated" ]; then
        finding4="$repeated"
      else
        finding4="  (no repeated findings at threshold=${REPEAT_THRESHOLD}+ packets)"
      fi
    fi
  fi

  say "Finding 4 — Repeated review findings (class seen in >=${REPEAT_THRESHOLD} blocking sections):"
  say "$finding4"

  # -------------------------------------------------------------------
  # M1 / S1: --write-proposals: append to META.proposed.md ONLY (>> append, never overwrite)
  # -------------------------------------------------------------------
  if [ "$write_meta" = 1 ]; then
    mkdir -p "$repo/agent-project"
    {
      printf '\n## [meta] %s (v%s)\n' "$ts" "$ver"
      printf '### Finding 1 — Ledger cost outliers (stage tokens > %dx mean)\n' "$OUTLIER_FACTOR"
      printf '%s\n' "$finding1"
      printf '### Finding 2 — Rework rate\n'
      printf '%s\n' "$finding2"
      printf '### Finding 3 — Backlog drift\n'
      printf '%s\n' "$finding3"
      printf '### Finding 4 — Repeated review findings (threshold=%d)\n' "$REPEAT_THRESHOLD"
      printf '%s\n' "$finding4"
      printf '### Suggested next steps\n'
      printf -- '- Review findings above; promote repeated-finding candidates to AGENT_BACKLOG.md or STANDARDS.md via the gate.\n'
      printf -- '- High rework rate → consider deepening 03_architecture_safety conditions.\n'
      printf -- '- Token outliers → consider splitting large stages into smaller packets.\n'
    } >> "$META_PROPOSALS" # SAFETY: only permitted write in cmd_meta
    say "  → appended [meta] block to $META_PROPOSALS"
  fi
}
