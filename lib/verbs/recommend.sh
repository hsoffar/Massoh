#!/usr/bin/env bash
# massoh verb: recommend — forward heuristic suggestions from METRICS.md snapshot trend.
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# recommend — forward heuristic suggestions from METRICS.md snapshot trend. READ-ONLY by default.
# Zero LLM spend. Rules R1-R5 fire on numeric fields from last 2 snapshots. --write appends to
# AGENT_SYNC.md only (Condition C5). awk parse || true (Condition C2). All reads || true (Condition C3).
# Expansion note: rule text is English; numeric extraction is locale-neutral. If METRICS.md snapshot
# format changes, awk parser fails silently to R5 (acceptable failure-mode for MVP).
cmd_recommend() {
  local write_recommend=0  # Condition C1: default OFF; only --write sets to 1
  while [ $# -gt 0 ]; do case "$1" in
    --write)    write_recommend=1;;
    --no-write) write_recommend=0;;
    *) die "unknown recommend flag: $1";;
  esac; shift; done

  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local metrics="$repo/agent-project/METRICS.md"

  # Parse last 2 ## Snapshot blocks from METRICS.md using awk (Condition C2: || true on parse)
  # Extracts named fields: cycle_avg_days, rework_pct, throughput/wk, reverts, backlog_todo
  # If parsing fails silently → snapshot_count=0 → R5 fires. Format change = silent degrade.
  local snap1_cycle=0 snap1_rework=0 snap1_throughput=0 snap1_reverts=0 snap1_todo=0
  local snap2_cycle=0 snap2_rework=0 snap2_throughput=0 snap2_reverts=0 snap2_todo=0
  local snapshot_count=0

  if [ -f "$metrics" ]; then
    # awk: collect last 2 snapshot blocks, extract key=value fields (Condition C3: || true)
    local parsed; parsed=$(awk '
      /^## Snapshot /{
        snap_count++
        # store the previous snapshot data into slots, sliding window
        if (snap_count > 1) {
          s1_cycle=s2_cycle; s1_rework=s2_rework; s1_thru=s2_thru
          s1_reverts=s2_reverts; s1_todo=s2_todo
        }
        s2_cycle=0; s2_rework=0; s2_thru=0; s2_reverts=0; s2_todo=0
        next
      }
      snap_count>0 && /^- cycle_avg_days=/{
        val=substr($0, index($0,"=")+1)
        gsub(/[^0-9]/,"",val); if(val!="") s2_cycle=val+0
      }
      snap_count>0 && /^- rework_pct=/{
        val=substr($0, index($0,"=")+1)
        gsub(/[^0-9]/,"",val); if(val!="") s2_rework=val+0
      }
      snap_count>0 && /^- throughput\/wk=/{
        val=substr($0, index($0,"=")+1)
        gsub(/[^0-9]/,"",val); if(val!="") s2_thru=val+0
      }
      snap_count>0 && /^- reverts=/{
        val=substr($0, index($0,"=")+1)
        gsub(/[^0-9]/,"",val); if(val!="") s2_reverts=val+0
      }
      snap_count>0 && /^- backlog_todo=/{
        val=substr($0, index($0,"=")+1)
        gsub(/[^0-9]/,"",val); if(val!="") s2_todo=val+0
      }
      END {
        print "snap_count=" snap_count
        if (snap_count>=2) {
          print "s1_cycle=" s1_cycle
          print "s1_rework=" s1_rework
          print "s1_thru=" s1_thru
          print "s1_reverts=" s1_reverts
          print "s1_todo=" s1_todo
        }
        print "s2_cycle=" s2_cycle
        print "s2_rework=" s2_rework
        print "s2_thru=" s2_thru
        print "s2_reverts=" s2_reverts
        print "s2_todo=" s2_todo
      }
    ' "$metrics" 2>/dev/null || true)

    # Parse the awk output into local vars (Condition C3: || true on each extraction)
    local _k _v
    while IFS='=' read -r _k _v; do
      case "$_k" in
        snap_count)  snapshot_count="${_v:-0}";;
        s1_cycle)    snap1_cycle="${_v:-0}";;
        s1_rework)   snap1_rework="${_v:-0}";;
        s1_thru)     snap1_throughput="${_v:-0}";;
        s1_reverts)  snap1_reverts="${_v:-0}";;
        s1_todo)     snap1_todo="${_v:-0}";;
        s2_cycle)    snap2_cycle="${_v:-0}";;
        s2_rework)   snap2_rework="${_v:-0}";;
        s2_thru)     snap2_throughput="${_v:-0}";;
        s2_reverts)  snap2_reverts="${_v:-0}";;
        s2_todo)     snap2_todo="${_v:-0}";;
      esac
    done <<< "$parsed" 2>/dev/null || true
  fi

  # Condition C4: count snapshots; suppress R1/R4 if < 2 snapshots
  snapshot_count="${snapshot_count:-0}"

  # Apply rules R1-R5, collect fired suggestions (priority order: R2 > R1 > R4 > R3 > R5)
  local suggestions="" rule_fired=0

  # R2: rework_pct > 25 in latest snapshot (fires on 1 snapshot)
  if [ "${snap2_rework:-0}" -gt 25 ] 2>/dev/null; then
    suggestions="${suggestions}R2: High rework rate (rework_pct=${snap2_rework}%) — arch/safety review may be too shallow; consider deepening 03 conditions."$'\n'
    rule_fired=1
  fi

  # R1: cycle_avg_days rising across last 2 snapshots (requires >= 2 snapshots; Condition C4)
  if [ "$snapshot_count" -ge 2 ] 2>/dev/null; then
    if [ "${snap2_cycle:-0}" -gt "${snap1_cycle:-0}" ] 2>/dev/null; then
      suggestions="${suggestions}R1: Cycle time climbing (${snap1_cycle}→${snap2_cycle} days) — consider tightening product scope (smaller slices) in next planning pass."$'\n'
      rule_fired=1
    fi
  fi

  # R4: backlog grows while throughput/wk flat or falling across 2 snapshots (requires >= 2; Condition C4)
  if [ "$snapshot_count" -ge 2 ] 2>/dev/null; then
    if [ "${snap2_todo:-0}" -gt "${snap1_todo:-0}" ] 2>/dev/null && \
       [ "${snap2_throughput:-0}" -le "${snap1_throughput:-0}" ] 2>/dev/null; then
      suggestions="${suggestions}R4: Throughput bottleneck — backlog growing faster than delivery (TODO: ${snap1_todo}→${snap2_todo}, throughput/wk: ${snap1_throughput}→${snap2_throughput}); re-rank or reduce parallel work."$'\n'
      rule_fired=1
    fi
  fi

  # R3: revert count > 0 in latest snapshot (fires on 1 snapshot)
  if [ "${snap2_reverts:-0}" -gt 0 ] 2>/dev/null; then
    suggestions="${suggestions}R3: Revert spike detected (reverts=${snap2_reverts}) — consider adding regression test coverage before next feature."$'\n'
    rule_fired=1
  fi

  # R5: no METRICS.md or no snapshots (Condition C4: count==0 → only R5)
  if [ "$snapshot_count" -eq 0 ] 2>/dev/null || [ ! -f "$metrics" ]; then
    suggestions="R5: No METRICS.md snapshots yet — run \`massoh review\` to capture a baseline."$'\n'
    rule_fired=1
  fi

  # Print ranked output
  say "massoh recommend — $ts  (v$(mver))"
  if [ "$rule_fired" -eq 1 ]; then
    local n=1
    while IFS= read -r line; do
      [ -n "$line" ] && { say "  $n. $line"; n=$((n+1)); }
    done <<< "$suggestions"
  else
    say "  No issues detected — system metrics look healthy."
  fi

  # --write: append [recommend] block to AGENT_SYNC.md ONLY (Condition C5)
  if [ "$write_recommend" = 1 ]; then
    local sync="$repo/AGENT_SYNC.md"
    if [ -f "$sync" ] || [ -d "$repo" ]; then
      {
        printf '\n## [recommend] %s\n' "$ts"
        if [ "$rule_fired" -eq 1 ]; then
          printf '%s\n' "$suggestions" | sed 's/^/- /'
        else
          printf '- No issues detected.\n'
        fi
      } >> "$sync" # SAFETY: sole permitted write in cmd_recommend (mirrors cmd_learn pattern)
      say "  → appended [recommend] block to AGENT_SYNC.md"
    fi
  fi
}
