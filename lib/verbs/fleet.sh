#!/usr/bin/env bash
# massoh verb: fleet — read-only multi-repo rollup.
# Discovers opted-in Massoh repos (.massoh marker) under --root or via a fleet.tsv registry,
# then prints per-repo stage counts, blocked items, and last-handoff info from AGENT_SYNC.md.
#
# PRIVACY: output is LOCAL ONLY. Nothing is uploaded, sent to any network endpoint, or
# written to any discovered repo. This verb writes to no file except an optional cache under
# ~/.claude/massoh/ (off by default; enable with --cache / disable with --no-cache).
#
# WRITE-ISOLATION GUARANTEE (FL1): discovered-repo path variables are used ONLY as arguments
# to read-only builtins and coreutils ([ -d ], [ -f ], find, grep, head, awk). They NEVER
# appear on the right-hand side of >, >>, tee, cp, mv, mkdir, or touch. The only permitted
# filesystem write is the optional cache directory ~/.claude/massoh/ (controlled by the owner).
#
# Sourced by bin/massoh at startup. Requires: say, die (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# --- fleet.tsv default path (overridable via env var; never sourced) ---
_FLEET_TSV_DEFAULT="${HOME}/.claude/massoh/fleet.tsv"

# --- FL2: maxdepth default; overridable via MASSOH_FLEET_MAXDEPTH, capped at 5 ---
_fleet_maxdepth() {
  local d="${MASSOH_FLEET_MAXDEPTH:-3}"
  [ "$d" -gt 5 ] 2>/dev/null && d=5
  [ "$d" -lt 1 ] 2>/dev/null && d=3
  printf '%s' "$d"
}

# --- per-repo rollup (all operations READ-ONLY on $repo) ---
# FL1: $repo is NEVER used as a write target anywhere in this function.
_fleet_report_repo() {
  local repo="$1"

  # FL4/FL5: validate path before any read
  if ! [ -d "$repo" ]; then
    printf '[SKIP] %s: not a directory\n' "$repo"
    return 0
  fi

  # Count task directories (cap 100; FL4)
  local task_count=0 todo_count=0 doing_count=0 blocked_count=0 done_count=0
  local tasks_dir="${repo}/.agent_tasks"

  if [ -d "$tasks_dir" ]; then
    # FL4: cap 100 task dirs; FL6: find guarded with 2>/dev/null || true
    local task_dirs
    task_dirs="$(find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d -name 'TASK-*' 2>/dev/null || true)"
    if [ -n "$task_dirs" ]; then
      # cap at 100 (FL4)
      task_dirs="$(printf '%s\n' "$task_dirs" | head -n 100)"
      task_count="$(printf '%s\n' "$task_dirs" | grep -c . || true)"

      # classify by artifact presence (FL4: no source/eval; only [ -f ] checks)
      local td
      while IFS= read -r td; do
        [ -d "$td" ] || continue
        if [ -f "${td}/06_review_result.md" ]; then
          done_count=$((done_count+1))
        elif [ -f "${td}/04_implementation_packet.md" ]; then
          doing_count=$((doing_count+1))
        else
          todo_count=$((todo_count+1))
        fi
      done <<EOF
$task_dirs
EOF
    fi
  fi

  # blocked: scan AGENT_BACKLOG.md if present (FL4: grep only, data not instructions)
  local backlog_file="${repo}/AGENT_BACKLOG.md"
  if [ -f "$backlog_file" ]; then
    blocked_count="$(grep -c '| BLOCKED |' "$backlog_file" 2>/dev/null || true)"
  fi

  # last-handoff: read first 200 lines of AGENT_SYNC.md (FL4: head -n 200, grep only)
  local sync_file="${repo}/AGENT_SYNC.md"
  local last_agent="(unknown)" last_mode="(unknown)"
  if [ -f "$sync_file" ]; then
    local sync_content
    sync_content="$(head -n 200 "$sync_file" 2>/dev/null || true)"
    # Extract last agent/mode lines if present (data-only; FL4: no eval)
    local agent_line
    agent_line="$(printf '%s\n' "$sync_content" | grep -iE '^(Agent|Current agent):' 2>/dev/null | tail -n1 || true)"
    if [ -n "$agent_line" ]; then
      last_agent="$(printf '%s\n' "$agent_line" | sed 's/^[^:]*: *//' | head -c 80 || true)"
    fi
    local mode_line
    mode_line="$(printf '%s\n' "$sync_content" | grep -iE '^(Mode|Current mode|Strategic mode):' 2>/dev/null | tail -n1 || true)"
    if [ -n "$mode_line" ]; then
      last_mode="$(printf '%s\n' "$mode_line" | sed 's/^[^:]*: *//' | head -c 80 || true)"
    fi
  fi

  # blocked indicator for display
  local blocked_flag=""
  [ "$blocked_count" -gt 0 ] && blocked_flag=" [BLOCKED:${blocked_count}]"

  # FL1: $repo used only in printf (read-only display), never as a write target
  printf 'repo: %s\n' "$repo"
  printf '  tasks: %d total (todo=%d doing=%d done=%d)%s\n' \
    "$task_count" "$todo_count" "$doing_count" "$done_count" "$blocked_flag"
  printf '  last-agent: %s  last-mode: %s\n' "$last_agent" "$last_mode"
}

cmd_fleet() {
  # FL8: local-only, no upload
  local fleet_root="" use_cache=0 tsv_file=""
  local maxdepth

  while [ $# -gt 0 ]; do case "$1" in
    --root)      shift; fleet_root="${1:-}";;
    --no-cache)  use_cache=0;;
    --cache)     use_cache=1;;
    --help|-h)
      printf 'massoh fleet [--root <dir>] [--no-cache]\n'
      printf '\n'
      printf 'Discover opted-in Massoh repos and print a per-repo rollup.\n'
      printf '\n'
      printf 'Discovery modes (tried in order):\n'
      printf '  1. --root <dir>   scan <dir> (find -maxdepth 3) for .massoh markers\n'
      printf '  2. $MASSOH_FLEET_ROOT env var  same as --root\n'
      printf '  3. $MASSOH_FLEET_TSV env var   OR ~/.claude/massoh/fleet.tsv registry\n'
      printf '     Format: one absolute path per line; # comments + blank lines ignored.\n'
      printf '\n'
      printf 'PRIVACY: output is LOCAL ONLY — nothing is uploaded or sent anywhere.\n'
      printf 'WRITE-ISOLATION: this verb writes NOTHING to any discovered repo.\n'
      printf 'Optional cache (--cache): ~/.claude/massoh/ only.\n'
      return 0
      ;;
    *)  die "unknown fleet flag: $1";;
  esac; shift; done

  # env var fallback (FL2 / expansion principle: never hard-code a root)
  [ -z "$fleet_root" ] && fleet_root="${MASSOH_FLEET_ROOT:-}"

  # FL3: fleet.tsv path from env or default
  tsv_file="${MASSOH_FLEET_TSV:-$_FLEET_TSV_DEFAULT}"

  maxdepth="$(_fleet_maxdepth)"

  # FL8 header: local-only, no upload
  printf 'massoh fleet — local-only rollup (nothing uploaded)\n'

  local repo_list="" found_any=0

  # --- Mode 1: --root scan ---
  if [ -n "$fleet_root" ]; then
    # FL2: missing or non-directory root → warn + exit 0
    if ! [ -d "$fleet_root" ]; then
      printf '[WARN] fleet root not found or not a directory: %s\n' "$fleet_root"
      return 0
    fi

    # FL2: bounded find (-maxdepth 3, cap 200), guarded with 2>/dev/null || true
    # FL7: no network; FL1: $fleet_root is the SCAN root, not a write target
    repo_list="$(find "$fleet_root" -maxdepth "$maxdepth" -name '.massoh' -type f \
      2>/dev/null | head -n 200 | sed 's|/\.massoh$||' || true)"

    if [ -z "$repo_list" ]; then
      printf '(no opted-in repos found under %s at maxdepth=%s)\n' "$fleet_root" "$maxdepth"
      return 0
    fi

    found_any=1
    # FL5: per-repo degrade; FL1: _fleet_report_repo only reads $repo
    while IFS= read -r rp; do
      [ -n "$rp" ] || continue
      _fleet_report_repo "$rp" || printf '[SKIP] %s: error reading repo\n' "$rp"
      printf '\n'
    done <<EOF
$repo_list
EOF
    return 0
  fi

  # --- Mode 2: fleet.tsv registry ---
  if [ -f "$tsv_file" ]; then
    local line_num=0 repo_count=0
    # FL3: while IFS= read -r (never source); FL4: no eval
    while IFS= read -r line; do
      line_num=$((line_num+1))
      # FL3: skip blank lines and comments
      case "$line" in
        ''|\#*) continue;;
      esac
      # FL3: discard lines longer than 4096 chars
      if [ "${#line}" -gt 4096 ]; then
        printf '[SKIP] fleet.tsv line %d: exceeds 4096 chars, skipped\n' "$line_num"
        continue
      fi
      # FL3: validate as directory
      if ! [ -d "$line" ]; then
        printf '[SKIP] fleet.tsv line %d: not a directory: %s\n' "$line_num" "$line"
        continue
      fi
      # FL4: $line is data only — used as path arg to read-only _fleet_report_repo
      repo_count=$((repo_count+1))
      found_any=1
      _fleet_report_repo "$line" || printf '[SKIP] %s: error reading repo\n' "$line"
      printf '\n'
    done < "$tsv_file"

    if [ "$repo_count" -eq 0 ]; then
      printf '(no valid repos in registry: %s)\n' "$tsv_file"
    fi
    return 0
  fi

  # --- Mode 3: no config ---
  printf '(no fleet root or registry configured)\n'
  printf 'Usage: massoh fleet --root <dir>\n'
  printf '       or set MASSOH_FLEET_ROOT=<dir>\n'
  printf '       or populate %s (one path per line)\n' "$tsv_file"
  return 0
}
