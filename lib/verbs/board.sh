#!/usr/bin/env bash
# massoh verb: board — push Massoh task state to a Plane kanban board (push-only).
# Sourced by bin/massoh at startup. Requires: say, die, mver, MASSOH_HOME (set in bin/massoh bootstrap).
# BG1-BG7: PLANE_API_TOKEN never written/logged/echoed; header-only; gitignore-before-write.
# BG8-BG15: curl timeouts; graceful degrade exit 0; non-2xx = fail; HTTPS enforced; no exfil.
# BG16-BG21: .board-map.tsv append-only; .gitignore add-if-missing idempotent; board.conf create-if-missing.
# BG22: jq guard first in cmd_board. BG25: no internal cmd_* calls. BG26: jq @json encoding.
# NO set -x anywhere in cmd_board (BG3).
# API source: Plane developer-docs feat/add-new-api-docs branch, fetched 2026-06-19.
#   Auth:    X-API-Key: $PLANE_API_TOKEN  (never in URL — BG4)
#   Create:  POST   {base}/api/v1/workspaces/{slug}/projects/{pid}/issues/
#   Update:  PATCH  {base}/api/v1/workspaces/{slug}/projects/{pid}/issues/{issue_id}/
#   States:  GET/POST {base}/api/v1/workspaces/{slug}/projects/{pid}/states/
#   Priority values: none|urgent|high|medium|low
# shellcheck source=/dev/null

cmd_board() {
  # BG22: jq startup guard — FIRST statement, before any read/write/curl.
  command -v jq >/dev/null 2>&1 \
    || die "massoh board: jq is required for --push plane (brew install jq / apt install jq)."

  # --- flag parsing (mirrors cmd_learn / cmd_meta while-loop pattern) ---
  local push_plane=0 dry_run=0 init_config=0 no_push=0
  while [ $# -gt 0 ]; do case "$1" in
    --push)
      shift
      [ "${1:-}" = "plane" ] || die "board: unknown adapter '${1:-}'. usage: massoh board --push plane"
      push_plane=1
      ;;
    --dry-run)   dry_run=1 ;;
    --no-push)   no_push=1 ;;
    --init-config) init_config=1 ;;
    *) die "board: unknown flag '$1'. usage: massoh board [--push plane] [--dry-run] [--no-push] [--init-config]" ;;
  esac; shift; done

  local repo; repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"

  # BG16/BG18: SAFETY — the ONLY permitted write targets in cmd_board.
  # BOARD_MAP is append-only (>>); never truncated, never deleted.
  local BOARD_MAP="$repo/.agent_tasks/.board-map.tsv"  # SAFETY: sole append-only write target in cmd_board

  # --- --init-config: create .env.massoh template (create-if-missing) + gitignore entries ---
  if [ "$init_config" = 1 ]; then
    _board_ensure_gitignore "$repo"
    # BG7: create-if-missing only — never overwrite an existing .env.massoh
    if [ -e "$repo/.env.massoh" ]; then
      say "  keep .env.massoh (exists)"
    else
      cat > "$repo/.env.massoh" <<'ENVTEMPLATE'
# Massoh board config — GITIGNORED (never commit this file)
# Fill in your values and source this file or export as env vars.
PLANE_API_TOKEN=your_api_token_here
PLANE_BASE_URL=https://your-plane-instance.example.com
ENVTEMPLATE
      say "  create .env.massoh (template — fill in real values)"
    fi
    # BG20: board.conf create-if-missing (non-secret config only)
    mkdir -p "$repo/agent-project"
    if [ -e "$repo/agent-project/board.conf" ]; then
      say "  keep agent-project/board.conf (exists)"
    else
      cat > "$repo/agent-project/board.conf" <<'CONFTEMPLATE'
# Massoh board non-secret config — committable (no credentials here)
PLANE_WORKSPACE_SLUG=your-workspace-slug
PLANE_PROJECT_ID=your-project-uuid
CONFTEMPLATE
      say "  create agent-project/board.conf (fill in workspace slug + project ID)"
    fi
    say "done. edit .env.massoh (secret) + agent-project/board.conf (non-secret), then: massoh board --push plane"
    return 0
  fi

  # --- config loading ---
  # BG5: ensure .env.massoh is gitignored BEFORE sourcing it (order: gitignore first, then source)
  _board_ensure_gitignore "$repo"

  # Source .env.massoh if present (gitignored; never tracked)
  [ -f "$repo/.env.massoh" ] && . "$repo/.env.massoh" || true
  # Source board.conf if present (non-secret; committable)
  [ -f "$repo/agent-project/board.conf" ] && . "$repo/agent-project/board.conf" || true

  # --no-push / bare massoh board: print task table only, zero API calls, zero writes
  if [ "$no_push" = 1 ] || [ "$push_plane" = 0 ]; then
    _board_build_model "$repo"
    say "massoh board — task model ($(date -u +%Y-%m-%dT%H:%M:%SZ))"
    _board_print_table
    say "(no push — run: massoh board --push plane  to send to Plane)"
    return 0
  fi

  # --dry-run: print what would be pushed, zero API calls, zero writes
  if [ "$dry_run" = 1 ]; then
    _board_build_model "$repo"
    say "massoh board --dry-run — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    _board_print_table
    say "(dry-run: no API calls, no writes)"
    return 0
  fi

  # --- push plane: validate config first (BG6 + BG11) ---
  # BG6: exit 1 on missing required vars (never proceed with missing creds)
  local missing=""
  [ -z "${PLANE_API_TOKEN:-}" ]    && missing="$missing PLANE_API_TOKEN"
  [ -z "${PLANE_BASE_URL:-}" ]     && missing="$missing PLANE_BASE_URL"
  [ -z "${PLANE_WORKSPACE_SLUG:-}" ] && missing="$missing PLANE_WORKSPACE_SLUG"
  [ -z "${PLANE_PROJECT_ID:-}" ]   && missing="$missing PLANE_PROJECT_ID"
  if [ -n "$missing" ]; then
    printf 'massoh board: missing required variables:%s\n' "$missing" >&2
    printf 'Set them in .env.massoh (gitignored) or export as environment variables.\n' >&2
    printf 'Run: massoh board --init-config   to create a .env.massoh template.\n' >&2
    exit 1
  fi

  # BG11: HTTPS requirement — reject plaintext URLs unless PLANE_ALLOW_HTTP=1
  case "$PLANE_BASE_URL" in
    https://*) ;;
    http://*)
      if [ "${PLANE_ALLOW_HTTP:-0}" = "1" ]; then
        say "  WARNING: PLANE_BASE_URL uses http:// (plaintext). PLANE_ALLOW_HTTP=1 override active."
      else
        printf 'massoh board: PLANE_BASE_URL must use https:// (got: %s)\n' \
          "$(printf '%s' "$PLANE_BASE_URL" | sed 's|://.*|://...|')" >&2
        printf 'Set PLANE_ALLOW_HTTP=1 to allow plaintext (local dev only).\n' >&2
        exit 1
      fi
      ;;
    *) printf 'massoh board: PLANE_BASE_URL must begin with https:// (got invalid URL)\n' >&2; exit 1 ;;
  esac

  # BG18: ensure .board-map.tsv is gitignored BEFORE any write to the map
  # (already called _board_ensure_gitignore above, which covers both entries)

  # --- build internal task model ---
  _board_build_model "$repo"

  # --- push to Plane ---
  _board_push_plane "$repo"
}

# _board_ensure_gitignore: add-if-missing, idempotent, non-destructive (BG5/BG17/BG18).
# Adds .env.massoh and .agent_tasks/.board-map.tsv to .gitignore if not already present.
_board_ensure_gitignore() {
  local repo="$1"
  local gi="$repo/.gitignore"
  # Create .gitignore if missing (touch pattern — never truncate existing)
  [ -f "$gi" ] || touch "$gi"
  # BG5/BG17: .env.massoh — grep exact-line match, append only if absent
  grep -qxF '.env.massoh' "$gi" 2>/dev/null \
    || printf '\n.env.massoh\n' >> "$gi"
  # BG18: .agent_tasks/.board-map.tsv — same idempotent pattern
  grep -qxF '.agent_tasks/.board-map.tsv' "$gi" 2>/dev/null \
    || printf '\n.agent_tasks/.board-map.tsv\n' >> "$gi"
}

# Internal task model — populated by _board_build_model, consumed by _board_push_plane + _board_print_table.
# Stored as parallel arrays (POSIX bash compatible).
_BOARD_IDS=()
_BOARD_TITLES=()
_BOARD_DESCS=()
_BOARD_STAGES=()
_BOARD_PRIORITIES=()
_BOARD_LAST_AGENTS=()
_BOARD_BLOCKED=()
_BOARD_COST_TOKENS=()

# Stage name → file number map (highest packet file present determines stage).
# 00=backlog 01=scoping 03=arch-safety 04=licensed 05=implementing 06=review merged=merged
_board_stage_from_dir() {
  local d="$1"
  # Check from highest to lowest; return first match
  [ -f "${d}06_review_result.md" ]         && printf 'review'        && return
  [ -f "${d}05_implementation_handoff.md" ] && printf 'implementing'  && return
  [ -f "${d}04_implementation_packet.md" ]  && printf 'licensed'      && return
  [ -f "${d}03_architecture_safety.md" ]    && printf 'arch-safety'   && return
  [ -f "${d}01_product_scope.md" ]          && printf 'scoping'       && return
  [ -f "${d}00_request.md" ]                && printf 'backlog'       && return
  printf 'backlog'
}

# _board_build_model: scan .agent_tasks/TASK-*/, AGENT_BACKLOG.md, AGENT_SYNC.md, ledger.tsv.
# BG25: direct file reads only — no cmd_* calls.
_board_build_model() {
  local repo="$1"
  _BOARD_IDS=(); _BOARD_TITLES=(); _BOARD_DESCS=(); _BOARD_STAGES=()
  _BOARD_PRIORITIES=(); _BOARD_LAST_AGENTS=(); _BOARD_BLOCKED=(); _BOARD_COST_TOKENS=()

  local backlog="$repo/AGENT_BACKLOG.md"
  local sync="$repo/AGENT_SYNC.md"
  local ledger="$repo/.agent_tasks/ledger.tsv"

  # Parse last-handoff agent from AGENT_SYNC.md §Last handoff block (|| true: BG25/T23)
  local last_agent=""
  last_agent="$(grep -oE '^Agent: [^$]+' "$sync" 2>/dev/null | head -1 | sed 's/^Agent: //' || true)"
  [ -z "$last_agent" ] && last_agent="unknown"

  local idx=0
  for d in "$repo"/.agent_tasks/TASK-*/; do
    [ -d "$d" ] || continue
    local task_id; task_id="$(basename "$d")"

    # Stage: highest packet file present (BG25: direct read)
    local stage; stage="$(_board_stage_from_dir "$d")"

    # Title: first non-empty heading from 00_request.md, fallback to task_id
    local title="$task_id"
    if [ -f "${d}00_request.md" ]; then
      local h; h="$(grep -m1 '^#' "${d}00_request.md" 2>/dev/null | sed 's/^#* *//' || true)"
      [ -n "$h" ] && title="$h"
    fi

    # Description: first paragraph of 00_request.md, truncated at 500 chars (BG14/BG26)
    local desc=""
    if [ -f "${d}00_request.md" ]; then
      desc="$(awk '
        /^#/{next}
        /^[[:space:]]*$/{if(found) exit; next}
        {found=1; lines=lines $0 "\n"}
        END{printf "%s", lines}
      ' "${d}00_request.md" 2>/dev/null | head -c 500 || true)"
    fi
    [ -z "$desc" ] && desc="$task_id"

    # Priority: parse from AGENT_BACKLOG.md (|| true — BG25/T23)
    local priority="medium"
    if [ -f "$backlog" ]; then
      local pri_raw; pri_raw="$(grep -F "$task_id" "$backlog" 2>/dev/null | grep -oE '\| P[0-9] \|' | head -1 | tr -d '| ' || true)"
      case "$pri_raw" in
        P0) priority="urgent" ;;
        P1) priority="high" ;;
        P2) priority="medium" ;;
        P3) priority="low" ;;
        *)  priority="medium" ;;
      esac
    fi

    # Blocked: task appears in AGENT_BACKLOG.md with BLOCKED status (|| true — BG25/T23)
    local blocked="false"
    if [ -f "$backlog" ]; then
      grep -qF "$task_id" "$backlog" 2>/dev/null \
        && grep -F "$task_id" "$backlog" 2>/dev/null | grep -qF '| BLOCKED |' \
        && blocked="true" || true
    fi

    # Cost tokens: sum from ledger.tsv for this task-id (|| true — BG25/T23)
    local cost_tokens=0
    if [ -f "$ledger" ]; then
      cost_tokens="$(awk -F'\t' -v tid="$task_id" '
        NF>=4 && $2==tid && $4~/^[0-9]+$/ { sum += $4 }
        END { print (sum+0) }
      ' "$ledger" 2>/dev/null || true)"
      [[ "$cost_tokens" =~ ^[0-9]+$ ]] || cost_tokens=0
    fi

    _BOARD_IDS+=("$task_id")
    _BOARD_TITLES+=("$title")
    _BOARD_DESCS+=("$desc")
    _BOARD_STAGES+=("$stage")
    _BOARD_PRIORITIES+=("$priority")
    _BOARD_LAST_AGENTS+=("$last_agent")
    _BOARD_BLOCKED+=("$blocked")
    _BOARD_COST_TOKENS+=("$cost_tokens")
    idx=$((idx+1))
  done
}

# _board_print_table: print a human-readable task table (--no-push / --dry-run mode).
_board_print_table() {
  local n="${#_BOARD_IDS[@]}"
  if [ "$n" -eq 0 ]; then say "  (no tasks found in .agent_tasks/TASK-*/)"; return 0; fi
  printf '  %-40s %-14s %-10s %-8s %s\n' "TASK ID" "STAGE" "PRIORITY" "BLOCKED" "COST_TOKENS"
  local i
  for (( i=0; i<n; i++ )); do
    printf '  %-40s %-14s %-10s %-8s %s\n' \
      "${_BOARD_IDS[$i]}" "${_BOARD_STAGES[$i]}" "${_BOARD_PRIORITIES[$i]}" \
      "${_BOARD_BLOCKED[$i]}" "${_BOARD_COST_TOKENS[$i]}"
  done
}

# _board_push_plane: push the internal model to Plane via REST API.
# BG3: NO set -x; BG4: token ONLY in header; BG8: timeouts; BG9: degrade exit 0; BG10: http_code check.
# BG13: map row written ONLY on confirmed 2xx. BG14: payload bounded to model fields. BG26: jq @json.
_board_push_plane() {
  local repo="$1"
  local n="${#_BOARD_IDS[@]}"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  say "massoh board — $ts"

  if [ "$n" -eq 0 ]; then
    say "  no tasks found in .agent_tasks/TASK-*/ — nothing to push."
    return 0
  fi

  # Ensure mkdir -p for .agent_tasks (BOARD_MAP location)
  mkdir -p "$repo/.agent_tasks"

  # Step 1: ensure Plane project has the 7 required states; retrieve/create state IDs.
  # BG15: check before create (idempotent).
  local -A STAGE_IDS=()
  local states_ok=1

  local states_json tmpstates; tmpstates="$(mktemp)"
  local http_code_states
  # BG3: token in header only; BG8: timeouts; BG10: capture http_code
  http_code_states="$(curl -s \
    --connect-timeout 10 --max-time 30 \
    -o "$tmpstates" \
    -w "%{http_code}" \
    -H "X-API-Key: ${PLANE_API_TOKEN}" \
    -H "Content-Type: application/json" \
    "${PLANE_BASE_URL}/api/v1/workspaces/${PLANE_WORKSPACE_SLUG}/projects/${PLANE_PROJECT_ID}/states/" \
    2>/dev/null)" || true

  if [ "${http_code_states:-000}" -ge 200 ] && [ "${http_code_states:-000}" -lt 300 ] 2>/dev/null; then
    # Parse existing states from response
    while IFS= read -r line; do
      local sname sid
      sname="$(printf '%s' "$line" | jq -r '.name // empty' 2>/dev/null || true)"
      sid="$(printf '%s' "$line" | jq -r '.id // empty' 2>/dev/null || true)"
      [ -n "$sname" ] && [ -n "$sid" ] && STAGE_IDS["$sname"]="$sid"
    done < <(jq -c '.[] // .results[]? // empty' "$tmpstates" 2>/dev/null || true)
  else
    say "  WARNING: could not fetch Plane states (HTTP ${http_code_states:-000}). Will attempt without state mapping."
    states_ok=0
  fi
  rm -f "$tmpstates"

  # State color map (for creation)
  declare -A STATE_COLORS=(
    [backlog]="#6b7280"
    [scoping]="#3b82f6"
    [arch-safety]="#f59e0b"
    [licensed]="#8b5cf6"
    [implementing]="#f97316"
    [review]="#06b6d4"
    [merged]="#22c55e"
  )

  # BG15: create missing states only (check before create)
  if [ "$states_ok" = 1 ]; then
    local required_stages=(backlog scoping arch-safety licensed implementing review merged)
    for stage_name in "${required_stages[@]}"; do
      if [ -z "${STAGE_IDS[$stage_name]:-}" ]; then
        local color="${STATE_COLORS[$stage_name]:-#6b7280}"
        local create_body; create_body="$(jq -n \
          --arg name "$stage_name" \
          --arg color "$color" \
          '{"name":$name,"color":$color}')"
        local tmpstate; tmpstate="$(mktemp)"
        local http_code_st
        # BG3: header only; BG8: timeouts
        http_code_st="$(curl -s \
          --connect-timeout 10 --max-time 30 \
          -o "$tmpstate" \
          -w "%{http_code}" \
          -X POST \
          -H "X-API-Key: ${PLANE_API_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "$create_body" \
          "${PLANE_BASE_URL}/api/v1/workspaces/${PLANE_WORKSPACE_SLUG}/projects/${PLANE_PROJECT_ID}/states/" \
          2>/dev/null)" || true
        if [ "${http_code_st:-000}" -ge 200 ] && [ "${http_code_st:-000}" -lt 300 ] 2>/dev/null; then
          local new_id; new_id="$(jq -r '.id // empty' "$tmpstate" 2>/dev/null || true)"
          [ -n "$new_id" ] && STAGE_IDS["$stage_name"]="$new_id"
        else
          say "  WARNING: could not create state '$stage_name' (HTTP ${http_code_st:-000})"
        fi
        rm -f "$tmpstate"
      fi
    done
  fi

  # Step 2: load existing id-map (append-only; never rewrite)
  declare -A MAP_ISSUE_IDS=()
  if [ -f "$BOARD_MAP" ]; then
    while IFS=$'\t' read -r tid iid _pid _epoch || [ -n "$tid" ]; do
      [ -n "$tid" ] && [ -n "$iid" ] && MAP_ISSUE_IDS["$tid"]="$iid"
    done < "$BOARD_MAP"
  fi

  # Step 3: push each task
  local pushed_new=0 pushed_update=0 skipped=0 i
  for (( i=0; i<n; i++ )); do
    local task_id="${_BOARD_IDS[$i]}"
    local title="${_BOARD_TITLES[$i]}"
    local desc="${_BOARD_DESCS[$i]}"
    local stage="${_BOARD_STAGES[$i]}"
    local priority="${_BOARD_PRIORITIES[$i]}"
    local cost_tokens="${_BOARD_COST_TOKENS[$i]}"

    # Sanitize fields for TSV (BG19): strip tab + newline from task_id (others are not written to map)
    local safe_task_id="${task_id//$'\t'/}"; safe_task_id="${safe_task_id//$'\n'/}"; safe_task_id="${safe_task_id//$'\r'/}"

    # Get state ID for this stage
    local state_id="${STAGE_IDS[$stage]:-}"

    # Build issue body: bounded to model fields only (BG14/BG26).
    # Use jq @json encoding — NO string interpolation into JSON (BG26).
    local description_html; description_html="<p>$(printf '%s' "$desc" | head -c 500 | \
      sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')</p><p>stage: $stage | cost_tokens: $cost_tokens</p>"

    local body
    if [ -n "$state_id" ]; then
      body="$(jq -n \
        --arg name "$title" \
        --arg description_html "$description_html" \
        --arg state "$state_id" \
        --arg priority "$priority" \
        '{"name":$name,"description_html":$description_html,"state":$state,"priority":$priority}')"
    else
      body="$(jq -n \
        --arg name "$title" \
        --arg description_html "$description_html" \
        --arg priority "$priority" \
        '{"name":$name,"description_html":$description_html,"priority":$priority}')"
    fi

    local tmp_resp; tmp_resp="$(mktemp)"
    local http_code method endpoint

    if [ -n "${MAP_ISSUE_IDS[$task_id]:-}" ]; then
      # PATCH — update existing issue (BG15: idempotent upsert)
      local issue_id="${MAP_ISSUE_IDS[$task_id]}"
      method="PATCH"
      endpoint="${PLANE_BASE_URL}/api/v1/workspaces/${PLANE_WORKSPACE_SLUG}/projects/${PLANE_PROJECT_ID}/issues/${issue_id}/"
      # BG3: NO set -x; BG4: token in header only; BG8: timeouts; BG10: http_code
      http_code="$(curl -s \
        --connect-timeout 10 --max-time 30 \
        -o "$tmp_resp" \
        -w "%{http_code}" \
        -X PATCH \
        -H "X-API-Key: ${PLANE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$endpoint" \
        2>/dev/null)" || true

      if [ "${http_code:-000}" -ge 200 ] && [ "${http_code:-000}" -lt 300 ] 2>/dev/null; then
        pushed_update=$((pushed_update+1))
        say "  updated  $task_id → issue $issue_id (HTTP $http_code)"
      else
        # BG9: non-2xx → warn, skip, continue; map NOT written (BG13)
        say "  WARNING: failed to update $task_id (HTTP ${http_code:-000}) — skipped"
        skipped=$((skipped+1))
      fi
    else
      # POST — create new issue
      method="POST"
      endpoint="${PLANE_BASE_URL}/api/v1/workspaces/${PLANE_WORKSPACE_SLUG}/projects/${PLANE_PROJECT_ID}/issues/"
      # BG3: NO set -x; BG4: token in header only; BG8: timeouts; BG10: http_code
      http_code="$(curl -s \
        --connect-timeout 10 --max-time 30 \
        -o "$tmp_resp" \
        -w "%{http_code}" \
        -X POST \
        -H "X-API-Key: ${PLANE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$body" \
        "$endpoint" \
        2>/dev/null)" || true

      if [ "${http_code:-000}" -ge 200 ] && [ "${http_code:-000}" -lt 300 ] 2>/dev/null; then
        # Extract the new issue ID from the response
        local new_issue_id; new_issue_id="$(jq -r '.id // empty' "$tmp_resp" 2>/dev/null || true)"
        if [ -n "$new_issue_id" ]; then
          # BG13: map row written ONLY after confirmed 2xx + valid ID
          # BG16/BG19: append-only >>; fields sanitized of tab/newline
          local safe_issue_id="${new_issue_id//$'\t'/}"; safe_issue_id="${safe_issue_id//$'\n'/}"
          local safe_proj_id="${PLANE_PROJECT_ID//$'\t'/}"; safe_proj_id="${safe_proj_id//$'\n'/}"
          local epoch; epoch="$(date +%s)"
          printf '%s\t%s\t%s\t%s\n' \
            "$safe_task_id" "$safe_issue_id" "$safe_proj_id" "$epoch" \
            >> "$BOARD_MAP"  # SAFETY: BOARD_MAP is the ONLY permitted write target (append-only >>)
          MAP_ISSUE_IDS["$task_id"]="$new_issue_id"
          pushed_new=$((pushed_new+1))
          say "  created  $task_id → issue $new_issue_id (HTTP $http_code)"
        else
          say "  WARNING: POST succeeded (HTTP $http_code) but no issue ID in response for $task_id — skipped"
          skipped=$((skipped+1))
        fi
      else
        # BG9: non-2xx → warn, skip, continue; map NOT written (BG13)
        say "  WARNING: failed to create $task_id (HTTP ${http_code:-000}) — skipped"
        skipped=$((skipped+1))
      fi
    fi
    rm -f "$tmp_resp"
  done

  # Summary (BG2: no token value in any output path)
  say "  tasks scanned: $n"
  say "  pushed (new):     $pushed_new"
  say "  pushed (updated): $pushed_update"
  say "  skipped (error):  $skipped"
  if [ -n "${PLANE_BASE_URL:-}" ] && [ -n "${PLANE_WORKSPACE_SLUG:-}" ] && [ -n "${PLANE_PROJECT_ID:-}" ]; then
    say "  board: ${PLANE_BASE_URL}/${PLANE_WORKSPACE_SLUG}/projects/${PLANE_PROJECT_ID}/issues/"
  fi
  # BG9: always exit 0 (graceful degrade — partial failures already reported per-task)
  return 0
}
