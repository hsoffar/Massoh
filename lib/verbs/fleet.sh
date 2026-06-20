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

# ---------------------------------------------------------------------------
# Fleet HTML rendering (Seam A — bash renders + escapes, server is transport)
# ---------------------------------------------------------------------------
# All functions below are READ-ONLY with respect to every discovered repo.
# They print HTML to stdout; the server captures and forwards that output.
# Every interpolated value is passed through _board_html_escape (from board.sh,
# which must be sourced before these functions are called).
# ---------------------------------------------------------------------------

# _fleet_read_version <repo>
# Print the VERSION file content, or "—" if missing.
_fleet_read_version() {
  local repo="$1"
  local ver_file="${repo}/VERSION"
  if [ -f "$ver_file" ]; then
    head -n1 "$ver_file" 2>/dev/null | tr -d '\n\r' || printf '—'
  else
    printf '—'
  fi
}

# _fleet_repo_kpis <repo>
# Emit a tab-separated line: open_tasks<TAB>blocked<TAB>throughput<TAB>rework<TAB>cycle<TAB>tokens<TAB>cost<TAB>last_agent<TAB>last_mode<TAB>version
# All values are read-only (FL1). Missing files → "—".
_fleet_repo_kpis() {
  local repo="$1"

  # --- task counts (from .agent_tasks/TASK-*/) ---
  local open_tasks=0 blocked=0
  local tasks_dir="${repo}/.agent_tasks"
  local backlog_file="${repo}/AGENT_BACKLOG.md"

  if [ -d "$tasks_dir" ]; then
    local task_dirs
    task_dirs="$(find "$tasks_dir" -mindepth 1 -maxdepth 1 -type d -name 'TASK-*' 2>/dev/null | head -n 100 || true)"
    if [ -n "$task_dirs" ]; then
      local td
      while IFS= read -r td; do
        [ -d "$td" ] || continue
        # not-done = open (no 06_review_result.md)
        if ! [ -f "${td}/06_review_result.md" ]; then
          open_tasks=$((open_tasks+1))
        fi
      done <<EOF
$task_dirs
EOF
    fi
  fi

  if [ -f "$backlog_file" ]; then
    blocked="$(grep -c '| BLOCKED |' "$backlog_file" 2>/dev/null || true)"
    [ -z "$blocked" ] && blocked=0
  fi

  # --- KPIs from METRICS.md (last snapshot; reuse, don't recompute) ---
  local throughput="—" rework="—" cycle="—"
  local metrics_file="${repo}/agent-project/METRICS.md"
  if [ -f "$metrics_file" ]; then
    # Extract the last values from the most recent ## Snapshot block.
    # We search for the last occurrence of each key.
    local m_content
    m_content="$(cat "$metrics_file" 2>/dev/null || true)"
    local t_val r_val c_val
    t_val="$(printf '%s\n' "$m_content" | grep -oE 'throughput/wk=[^ ]+' | tail -n1 | sed 's/throughput\/wk=//' || true)"
    r_val="$(printf '%s\n' "$m_content" | grep -oE 'rework_pct=[^ ]+' | tail -n1 | sed 's/rework_pct=//' || true)"
    c_val="$(printf '%s\n' "$m_content" | grep -oE 'cycle_avg_days=[^ ]+' | tail -n1 | sed 's/cycle_avg_days=//' || true)"
    [ -n "$t_val" ] && throughput="$t_val"
    [ -n "$r_val" ] && rework="${r_val}%"
    [ -n "$c_val" ] && cycle="$c_val"
  fi

  # --- tokens + cost from ledger.tsv (reuse; don't recompute) ---
  local tokens="—" cost="—"
  local ledger_file="${repo}/.agent_tasks/ledger.tsv"
  if [ -f "$ledger_file" ]; then
    local ledger_agg
    ledger_agg="$(awk -F'\t' '
      NF>=5 && $4~/^[0-9]+$/ && $5~/^[0-9]+$/ {
        total_tok += $4
        total_sec += $5
      }
      END { printf "%d\t%d\n", total_tok, total_sec }
    ' "$ledger_file" 2>/dev/null || true)"
    if [ -n "$ledger_agg" ]; then
      tokens="$(printf '%s' "$ledger_agg" | cut -f1)"
      local secs
      secs="$(printf '%s' "$ledger_agg" | cut -f2)"
      # Convert seconds to cost approximation (display minutes of compute time)
      cost="${secs}s"
    fi
  fi

  # --- last-handoff from AGENT_SYNC.md ---
  local last_agent="—" last_mode="—"
  local sync_file="${repo}/AGENT_SYNC.md"
  if [ -f "$sync_file" ]; then
    local sync_content
    sync_content="$(head -n 200 "$sync_file" 2>/dev/null || true)"
    local agent_line mode_line
    agent_line="$(printf '%s\n' "$sync_content" | grep -iE '^(Agent|Current agent):' 2>/dev/null | tail -n1 || true)"
    [ -n "$agent_line" ] && last_agent="$(printf '%s\n' "$agent_line" | sed 's/^[^:]*: *//' | head -c 80 || true)"
    mode_line="$(printf '%s\n' "$sync_content" | grep -iE '^(Mode|Current mode|Strategic mode):' 2>/dev/null | tail -n1 || true)"
    [ -n "$mode_line" ] && last_mode="$(printf '%s\n' "$mode_line" | sed 's/^[^:]*: *//' | head -c 80 || true)"
    [ -z "$last_agent" ] && last_agent="—"
    [ -z "$last_mode" ] && last_mode="—"
  fi

  # --- version ---
  local version
  version="$(_fleet_read_version "$repo")"

  # Output all fields tab-separated (callers parse by position)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$open_tasks" "$blocked" "$throughput" "$rework" "$cycle" \
    "$tokens" "$cost" "$last_agent" "$last_mode" "$version"
}

# _fleet_html_header <title>
# Emit the common HTML <head> opening (sentinel on first line, N4: title is already escaped by caller).
_fleet_html_header() {
  local title="$1"
  printf '<!-- massoh-generated -->\n'
  printf '<!DOCTYPE html>\n'
  printf '<html lang="en">\n'
  printf '<head>\n'
  printf '<meta charset="UTF-8">\n'
  printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
  printf '<meta http-equiv="refresh" content="30">\n'
  printf '<title>%s</title>\n' "$title"
  printf '<style>\n'
  printf 'body{font-family:system-ui,sans-serif;margin:0;padding:1rem 1.5rem;background:#f3f4f6;color:#111827;}\n'
  printf 'h1{font-size:1.3rem;margin:0 0 .5rem;}\n'
  printf 'h2{font-size:1.1rem;margin:1rem 0 .5rem;}\n'
  printf 'nav{font-size:.85rem;margin-bottom:1rem;color:#6b7280;}\n'
  printf 'nav a{color:#2563eb;text-decoration:none;}\n'
  printf 'nav a:hover{text-decoration:underline;}\n'
  printf 'table{border-collapse:collapse;width:100%%;background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);font-size:.85rem;}\n'
  printf 'th{background:#e5e7eb;padding:.5rem .75rem;text-align:left;font-weight:600;white-space:nowrap;}\n'
  printf 'td{padding:.45rem .75rem;border-top:1px solid #e5e7eb;vertical-align:top;word-break:break-word;}\n'
  printf 'tr:hover td{background:#f9fafb;}\n'
  printf 'a.repo-link{color:#2563eb;font-weight:600;text-decoration:none;}\n'
  printf 'a.repo-link:hover{text-decoration:underline;}\n'
  printf '.kpi-panel{display:flex;flex-wrap:wrap;gap:.5rem 1.5rem;background:#fff;border-radius:.5rem;padding:.75rem 1rem;box-shadow:0 1px 3px rgba(0,0,0,.1);margin-bottom:1rem;font-size:.85rem;}\n'
  printf '.kpi-item{display:flex;flex-direction:column;}\n'
  printf '.kpi-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;color:#6b7280;}\n'
  printf '.kpi-value{font-weight:600;font-size:1rem;}\n'
  printf '.board{display:flex;gap:.75rem;overflow-x:auto;margin-bottom:1rem;}\n'
  printf '.col{background:#fff;border-radius:.5rem;padding:.75rem;min-width:180px;max-width:230px;flex-shrink:0;box-shadow:0 1px 3px rgba(0,0,0,.1);}\n'
  printf '.col h2{font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;color:#6b7280;margin:0 0 .5rem;}\n'
  printf '.card{background:#f9fafb;border:1px solid #e5e7eb;border-radius:.375rem;padding:.4rem .5rem;margin-bottom:.4rem;font-size:.78rem;}\n'
  printf '.card .title{font-weight:600;word-break:break-word;}\n'
  printf '.card .meta{color:#6b7280;margin-top:.2rem;font-size:.72rem;}\n'
  printf '.card.blocked{border-left:3px solid #ef4444;}\n'
  printf '.empty{color:#9ca3af;font-size:.75rem;font-style:italic;}\n'
  printf '.task-list{width:100%%;border-collapse:collapse;background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);font-size:.83rem;}\n'
  printf '.task-list th{background:#e5e7eb;padding:.4rem .75rem;text-align:left;font-weight:600;}\n'
  printf '.task-list td{padding:.4rem .75rem;border-top:1px solid #e5e7eb;}\n'
  printf '.commit-list{font-size:.8rem;font-family:monospace;background:#fff;border-radius:.5rem;padding:.5rem 1rem;box-shadow:0 1px 3px rgba(0,0,0,.1);margin-bottom:1rem;}\n'
  printf '.commit-list li{margin:.2rem 0;list-style:disc;margin-left:1.2rem;}\n'
  printf '.sibling-nav{font-size:.82rem;margin-bottom:.75rem;}\n'
  printf '.sibling-nav a{color:#2563eb;margin-right:.75rem;text-decoration:none;}\n'
  printf '.sibling-nav a:hover{text-decoration:underline;}\n'
  printf 'footer{margin-top:1.5rem;font-size:.75rem;color:#9ca3af;}\n'
  printf '</style>\n'
  printf '</head>\n'
  printf '<body>\n'
}

# _fleet_html_footer
# Emit closing HTML tags.
_fleet_html_footer() {
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  printf '<footer>massoh-generated &mdash; %s &mdash; meta-refresh 30s (read-only, no agent exec)</footer>\n' \
    "$(_board_html_escape "$ts")"
  printf '</body>\n</html>\n'
}

# _fleet_render_index <repo_root_or_tsv> <tsv_mode:0|1>
# Render the fleet index page as HTML to stdout.
# $1 = fleet_root (--root mode) OR tsv_path (tsv mode)
# $2 = 0 for root-scan mode, 1 for tsv-registry mode
# N4: every interpolated value goes through _board_html_escape.
# FL1: read-only on all repos.
_fleet_render_index() {
  local fleet_root_or_tsv="$1" tsv_mode="${2:-0}"

  # Collect repos into a list (same discovery logic as cmd_fleet, reused)
  local repo_list=""
  if [ "$tsv_mode" = "0" ]; then
    local maxdepth
    maxdepth="$(_fleet_maxdepth)"
    if [ -d "$fleet_root_or_tsv" ]; then
      repo_list="$(find "$fleet_root_or_tsv" -maxdepth "$maxdepth" -name '.massoh' -type f \
        2>/dev/null | head -n 200 | sed 's|/\.massoh$||' || true)"
    fi
  else
    # TSV registry mode: read file, skip blanks/comments, skip non-directories
    if [ -f "$fleet_root_or_tsv" ]; then
      while IFS= read -r line; do
        case "$line" in ''|\#*) continue;; esac
        [ "${#line}" -gt 4096 ] && continue
        [ -d "$line" ] || continue
        repo_list="${repo_list}${line}
"
      done < "$fleet_root_or_tsv"
    fi
  fi

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

  _fleet_html_header "Massoh Fleet"
  printf '<h1>Massoh Fleet</h1>\n'
  printf '<p style="font-size:.82rem;color:#6b7280;">Updated: %s &mdash; auto-refresh 30s</p>\n' \
    "$(_board_html_escape "$ts")"

  if [ -z "$(printf '%s' "$repo_list" | tr -d '[:space:]')" ]; then
    printf '<p>(no opted-in repos found)</p>\n'
    _fleet_html_footer
    return 0
  fi

  # Table header
  printf '<table>\n<thead><tr>\n'
  printf '<th>Repo</th><th>Open</th><th>Blocked</th><th>Throughput/wk</th>'
  printf '<th>Rework%%</th><th>Cycle (days)</th><th>Tokens</th><th>Compute</th>'
  printf '<th>Last Agent</th><th>Mode</th><th>Version</th>\n'
  printf '</tr></thead>\n<tbody>\n'

  while IFS= read -r rp; do
    [ -n "$rp" ] || continue
    [ -d "$rp" ] || continue

    # N4: repo basename is interpolated — must be escaped
    local repo_name
    repo_name="$(basename "$rp")"
    local esc_name
    esc_name="$(_board_html_escape "$repo_name")"

    # Read KPI fields (graceful degrade: on error show all "—")
    local kpi_line
    kpi_line="$(_fleet_repo_kpis "$rp" 2>/dev/null || printf '—\t—\t—\t—\t—\t—\t—\t—\t—\t—\n')"

    # Parse tab-separated KPI fields (N4: all escaped before interpolation)
    local open_tasks blocked throughput rework cycle tokens cost last_agent last_mode version
    open_tasks="$(  printf '%s' "$kpi_line" | cut -f1)"
    blocked="$(     printf '%s' "$kpi_line" | cut -f2)"
    throughput="$(  printf '%s' "$kpi_line" | cut -f3)"
    rework="$(      printf '%s' "$kpi_line" | cut -f4)"
    cycle="$(       printf '%s' "$kpi_line" | cut -f5)"
    tokens="$(      printf '%s' "$kpi_line" | cut -f6)"
    cost="$(        printf '%s' "$kpi_line" | cut -f7)"
    last_agent="$(  printf '%s' "$kpi_line" | cut -f8)"
    last_mode="$(   printf '%s' "$kpi_line" | cut -f9)"
    version="$(     printf '%s' "$kpi_line" | cut -f10)"

    # N4: every field escaped
    local e_open e_blocked e_thru e_rework e_cycle e_tokens e_cost e_agent e_mode e_ver
    e_open="$(    _board_html_escape "$open_tasks")"
    e_blocked="$( _board_html_escape "$blocked")"
    e_thru="$(    _board_html_escape "$throughput")"
    e_rework="$(  _board_html_escape "$rework")"
    e_cycle="$(   _board_html_escape "$cycle")"
    e_tokens="$(  _board_html_escape "$tokens")"
    e_cost="$(    _board_html_escape "$cost")"
    e_agent="$(   _board_html_escape "$last_agent")"
    e_mode="$(    _board_html_escape "$last_mode")"
    e_ver="$(     _board_html_escape "$version")"

    # N2/N4: repo name used only as an HTML text + URL value, escaped both ways;
    # the actual filesystem lookup on /repo/<name> is done by the server via set-membership.
    local url_name
    url_name="$(printf '%s' "$repo_name" | sed 's|%|%25|g; s| |%20|g; s|"|%22|g; s|<|%3C|g; s|>|%3E|g')"

    printf '<tr><td><a class="repo-link" href="/repo/%s">%s</a></td>' \
      "$url_name" "$esc_name"
    printf '<td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>' \
      "$e_open" "$e_blocked" "$e_thru" "$e_rework" "$e_cycle"
    printf '<td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td>' \
      "$e_tokens" "$e_cost" "$e_agent" "$e_mode" "$e_ver"
    printf '</tr>\n'
  done <<EOF
$repo_list
EOF

  printf '</tbody>\n</table>\n'
  _fleet_html_footer
}

# _fleet_render_repo <repo> <repo_name> <all_repos_newline_separated>
# Render a single-repo view page as HTML to stdout.
# N4: every interpolated value is HTML-escaped.
# FL1: read-only on $repo.
_fleet_render_repo() {
  local repo="$1" repo_name="$2" all_repos="$3"

  local esc_name
  esc_name="$(_board_html_escape "$repo_name")"

  _fleet_html_header "Massoh Fleet — $esc_name"

  # Breadcrumb
  printf '<nav><a href="/">&larr; Fleet index</a></nav>\n'

  # Sibling nav (A↔B links)
  if [ -n "$all_repos" ]; then
    printf '<div class="sibling-nav">Repos: '
    while IFS= read -r sibling_path; do
      [ -n "$sibling_path" ] || continue
      [ -d "$sibling_path" ] || continue
      local sib_name
      sib_name="$(basename "$sibling_path")"
      local esc_sib
      esc_sib="$(_board_html_escape "$sib_name")"
      local url_sib
      url_sib="$(printf '%s' "$sib_name" | sed 's|%|%25|g; s| |%20|g; s|"|%22|g; s|<|%3C|g; s|>|%3E|g')"
      if [ "$sib_name" = "$repo_name" ]; then
        printf '<strong>%s</strong> ' "$esc_sib"
      else
        printf '<a href="/repo/%s">%s</a> ' "$url_sib" "$esc_sib"
      fi
    done <<EOF2
$all_repos
EOF2
    printf '</div>\n'
  fi

  printf '<h1>%s</h1>\n' "$esc_name"

  # KPI panel
  local kpi_line
  kpi_line="$(_fleet_repo_kpis "$repo" 2>/dev/null || printf '—\t—\t—\t—\t—\t—\t—\t—\t—\t—\n')"
  local open_tasks blocked throughput rework cycle tokens cost last_agent last_mode version
  open_tasks="$(  printf '%s' "$kpi_line" | cut -f1)"
  blocked="$(     printf '%s' "$kpi_line" | cut -f2)"
  throughput="$(  printf '%s' "$kpi_line" | cut -f3)"
  rework="$(      printf '%s' "$kpi_line" | cut -f4)"
  cycle="$(       printf '%s' "$kpi_line" | cut -f5)"
  tokens="$(      printf '%s' "$kpi_line" | cut -f6)"
  cost="$(        printf '%s' "$kpi_line" | cut -f7)"
  last_agent="$(  printf '%s' "$kpi_line" | cut -f8)"
  last_mode="$(   printf '%s' "$kpi_line" | cut -f9)"
  version="$(     printf '%s' "$kpi_line" | cut -f10)"

  printf '<div class="kpi-panel">\n'
  _fleet_kpi_item "Open tasks"   "$open_tasks"
  _fleet_kpi_item "Blocked"      "$blocked"
  _fleet_kpi_item "Throughput/wk" "$throughput"
  _fleet_kpi_item "Rework"       "$rework"
  _fleet_kpi_item "Cycle (days)" "$cycle"
  _fleet_kpi_item "Tokens"       "$tokens"
  _fleet_kpi_item "Compute"      "$cost"
  _fleet_kpi_item "Last agent"   "$last_agent"
  _fleet_kpi_item "Mode"         "$last_mode"
  _fleet_kpi_item "Version"      "$version"
  printf '</div>\n'

  # Kanban board (reuse _board_build_model + _board_emit_local rendering, adapted for stdout)
  printf '<h2>Kanban</h2>\n'
  _fleet_render_board_inline "$repo"

  # Task list
  printf '<h2>Tasks</h2>\n'
  _fleet_render_task_list "$repo"

  # Recent commits
  printf '<h2>Recent commits</h2>\n'
  _fleet_render_commits "$repo"

  # Start a task (read-only panel — POST is PARKED, owner-gated)
  _fleet_render_start_task_panel "$repo" "$repo_name"

  _fleet_html_footer
}

# _fleet_render_start_task_panel <repo_abs_path> <repo_name>
# Render a read-only "Start a task" copy-paste panel.
# Shows the two shell commands an owner can run from their own terminal.
# NO POST handler — the submit path is PARKED pending owner sign-off (slice 1c §4 R3).
# N4: repo_abs_path and repo_name are escaped via _board_html_escape before interpolation.
# N6: no server-side exec, no agent call, no write, no network.
_fleet_render_start_task_panel() {
  local repo="$1" repo_name="$2"

  # N4: escape both the abs-path and the name before any HTML interpolation.
  local esc_path esc_name
  esc_path="$(_board_html_escape "$repo")"
  esc_name="$(_board_html_escape "$repo_name")"

  printf '<section style="margin-top:1.5rem;">\n'
  printf '<h2>Start a task</h2>\n'
  printf '<p style="font-size:.84rem;color:#374151;margin-bottom:.75rem;">'
  printf 'Run one of these commands in your own shell to queue or start a task in '
  printf '<strong>%s</strong>:</p>\n' "$esc_name"

  printf '<div style="background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);padding:.85rem 1rem;font-size:.84rem;">\n'

  # Option 1: queue via intake
  printf '<p style="margin:.3rem 0 .2rem;font-weight:600;color:#374151;">Queue it (append-only inbox):</p>\n'
  printf '<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0 .75rem;">'
  printf '<code>cd %s &amp;&amp; massoh intake &quot;&lt;your idea&gt;&quot;</code>' "$esc_path"
  printf '</pre>\n'

  # Option 2: build interactively
  printf '<p style="margin:.3rem 0 .2rem;font-weight:600;color:#374151;">Build it interactively:</p>\n'
  printf '<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0 .75rem;">'
  printf '<code>massoh work %s</code>' "$esc_name"
  printf '</pre>\n'
  printf '<p style="margin:.1rem 0 .2rem;font-size:.8rem;color:#6b7280;">then, inside the agent session:</p>\n'
  printf '<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0;">'
  printf '<code>/start-task &quot;&lt;your idea&gt;&quot;</code>'
  printf '</pre>\n'

  # Parked note (N6 / §4 R3 — POST is owner-gated)
  printf '<p style="margin-top:.85rem;font-size:.78rem;color:#9ca3af;font-style:italic;">'
  printf 'Live one-click submit from the dashboard is owner-gated &mdash; parked pending sign-off.'
  printf '</p>\n'

  printf '</div>\n'
  printf '</section>\n'
}

# _fleet_kpi_item <label> <value>
# Emit a single KPI panel item. N4: both label and value are escaped.
_fleet_kpi_item() {
  local label="$1" value="$2"
  local esc_label esc_value
  esc_label="$(_board_html_escape "$label")"
  esc_value="$(_board_html_escape "$value")"
  printf '<div class="kpi-item"><span class="kpi-label">%s</span><span class="kpi-value">%s</span></div>\n' \
    "$esc_label" "$esc_value"
}

# _fleet_render_board_inline <repo>
# Render an inline kanban board (same data as _board_emit_local but to stdout, not a file).
# N4: all fields escaped. FL1: read-only.
_fleet_render_board_inline() {
  local repo="$1"

  # Reuse _board_build_model (from board.sh, which must be sourced)
  _board_build_model "$repo"

  local n="${#_BOARD_IDS[@]}"
  local stages="backlog scoping arch-safety licensed implementing review merged"

  printf '<div class="board">\n'
  local stage
  for stage in $stages; do
    local esc_stage
    esc_stage="$(_board_html_escape "$stage")"
    printf '<div class="col"><h2>%s</h2>\n' "$esc_stage"
    local found_any=0 i
    for (( i=0; i<n; i++ )); do
      if [ "${_BOARD_STAGES[$i]}" = "$stage" ]; then
        found_any=1
        local esc_tid esc_title esc_agent
        esc_tid="$(   _board_html_escape "${_BOARD_IDS[$i]}")"
        esc_title="$( _board_html_escape "${_BOARD_TITLES[$i]}")"
        esc_agent="$( _board_html_escape "${_BOARD_LAST_AGENTS[$i]}")"
        local blocked_cls=""
        [ "${_BOARD_BLOCKED[$i]}" = "true" ] && blocked_cls=" blocked"
        printf '<div class="card%s"><div class="title">%s</div>' "$blocked_cls" "$esc_title"
        printf '<div class="meta">%s</div>' "$esc_tid"
        printf '<div class="meta">agent: %s</div></div>\n' "$esc_agent"
      fi
    done
    [ "$found_any" = "0" ] && printf '<div class="empty">(empty)</div>\n'
    printf '</div>\n'
  done
  printf '</div>\n'
}

# _fleet_render_task_list <repo>
# Render a table of tasks with stage and last-handoff. N4: all escaped.
_fleet_render_task_list() {
  local repo="$1"
  local tasks_dir="${repo}/.agent_tasks"
  local sync_file="${repo}/AGENT_SYNC.md"

  # Read last-handoff agent once
  local last_agent="—"
  if [ -f "$sync_file" ]; then
    local agent_line
    agent_line="$(head -n 200 "$sync_file" 2>/dev/null | grep -iE '^(Agent|Current agent):' 2>/dev/null | tail -n1 || true)"
    [ -n "$agent_line" ] && last_agent="$(printf '%s\n' "$agent_line" | sed 's/^[^:]*: *//' | head -c 80 || true)"
    [ -z "$last_agent" ] && last_agent="—"
  fi

  printf '<table class="task-list">\n'
  printf '<thead><tr><th>Task ID</th><th>Stage</th><th>Last Agent</th></tr></thead>\n'
  printf '<tbody>\n'

  local found_any=0
  if [ -d "$tasks_dir" ]; then
    local d
    for d in "$tasks_dir"/TASK-*/; do
      [ -d "$d" ] || continue
      found_any=1
      local task_id stage
      task_id="$(basename "$d")"
      stage="$(_board_stage_from_dir "$d")"
      local esc_tid esc_stage esc_agent
      esc_tid="$(   _board_html_escape "$task_id")"
      esc_stage="$( _board_html_escape "$stage")"
      esc_agent="$( _board_html_escape "$last_agent")"
      printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
        "$esc_tid" "$esc_stage" "$esc_agent"
    done
  fi

  [ "$found_any" = "0" ] && printf '<tr><td colspan="3">(no tasks)</td></tr>\n'
  printf '</tbody>\n</table>\n'
}

# _fleet_render_commits <repo>
# Render a list of recent git commits. N4: all output escaped. FL1: git log is read-only.
_fleet_render_commits() {
  local repo="$1"
  printf '<div class="commit-list"><ul>\n'
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    local commit_line
    while IFS= read -r commit_line; do
      [ -n "$commit_line" ] || continue
      local esc_commit
      esc_commit="$(_board_html_escape "$commit_line")"
      printf '<li>%s</li>\n' "$esc_commit"
    done < <(git -C "$repo" log -n 10 --oneline 2>/dev/null || true)
  else
    printf '<li>(not a git repo)</li>\n'
  fi
  printf '</ul></div>\n'
}

# _fleet_render_task <repo> <repo_name> <task_id> <task_dir>
# Render the task drill-down page as HTML to stdout.
# Shows: breadcrumb, stage-trail index (label + first-line who/what), ledger cost.
# N4: every interpolated value is HTML-escaped via _board_html_escape.
# FL1: read-only — no writes to $repo.
# No full-body dump: shows only stage presence + one-line label/title (scope guard).
_fleet_render_task() {
  local repo="$1" repo_name="$2" task_id="$3" task_dir="$4"
  set -euo pipefail

  local esc_name esc_tid
  esc_name="$(_board_html_escape "$repo_name")"
  esc_tid="$(_board_html_escape "$task_id")"

  # URL-safe name for breadcrumb links (minimal percent-encoding matching _fleet_render_index)
  local url_name
  url_name="$(printf '%s' "$repo_name" | sed 's|%|%25|g; s| |%20|g; s|"|%22|g; s|<|%3C|g; s|>|%3E|g')"

  _fleet_html_header "Massoh Fleet — ${esc_name} — ${esc_tid}"

  # Breadcrumb: / → /repo/<name> → task
  printf '<nav>'
  printf '<a href="/">&larr; Fleet index</a>'
  printf ' &rsaquo; <a href="/repo/%s">%s</a>' "$url_name" "$esc_name"
  printf ' &rsaquo; %s' "$esc_tid"
  printf '</nav>\n'

  printf '<h1>%s</h1>\n' "$esc_tid"
  printf '<p style="font-size:.82rem;color:#6b7280;"><a href="/repo/%s">&larr; Back to %s board</a></p>\n' \
    "$url_name" "$esc_name"

  # -----------------------------------------------------------------------
  # Stage trail — index only (no full body dump; scope + leak guard N4+no-full-body)
  # For each known stage file present, show: stage label + who/what (file's first line)
  # "who/what" = the first heading/non-blank line of the file → repo content → treated as
  # data and HTML-escaped (N4).
  # -----------------------------------------------------------------------
  printf '<h2>Packet trail</h2>\n'
  printf '<table class="task-list">\n'
  printf '<thead><tr><th>Stage</th><th>File</th><th>First line (title / who)</th></tr></thead>\n'
  printf '<tbody>\n'

  local found_any_stage=0

  # Known stage files in order (00→06 + common extras)
  # Format: "stage_label|filename_glob_suffix"
  local _stage_files
  _stage_files="
00_request|00_request.md
01_product_scope|01_product_scope.md
02_product_scope|02_product_scope.md
03_architecture_safety|03_architecture_safety.md
04_implementation_packet|04_implementation_packet.md
05_implementation_handoff|05_implementation_handoff.md
06_review_result|06_review_result.md
"

  local sf
  while IFS='|' read -r sf_label sf_file; do
    [ -n "$sf_label" ] || continue
    local full_path="${task_dir}/${sf_file}"
    [ -f "$full_path" ] || continue
    found_any_stage=1

    # First line: read only the first non-empty, non-whitespace-only line (N4 + no-full-body).
    # This gives the title/heading — we never read the rest of the file.
    local first_line=""
    first_line="$(grep -m1 '[^[:space:]]' "$full_path" 2>/dev/null | head -c 200 || true)"
    [ -z "$first_line" ] && first_line="(empty)"

    local esc_label esc_sfname esc_first
    esc_label="$(  _board_html_escape "$sf_label")"
    esc_sfname="$( _board_html_escape "$sf_file")"
    esc_first="$(  _board_html_escape "$first_line")"

    printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
      "$esc_label" "$esc_sfname" "$esc_first"
  done <<EOF
$_stage_files
EOF

  # Also scan for any other files present in the task dir (e.g. 0N_*, handoff, proposal)
  # that are NOT in the known list above — show them too but only their first line.
  if [ -d "$task_dir" ]; then
    local extra_f
    for extra_f in "$task_dir"/??_*.md "$task_dir"/handoff*.md "$task_dir"/proposal*.md; do
      [ -f "$extra_f" ] || continue
      local extra_base
      extra_base="$(basename "$extra_f")"
      # Skip files already in the known list above
      case "$extra_base" in
        00_request.md|01_product_scope.md|02_product_scope.md| \
        03_architecture_safety.md|04_implementation_packet.md| \
        05_implementation_handoff.md|06_review_result.md) continue;;
      esac
      found_any_stage=1
      local extra_label
      extra_label="$(printf '%s' "$extra_base" | sed 's/\.md$//')"
      local extra_first=""
      extra_first="$(grep -m1 '[^[:space:]]' "$extra_f" 2>/dev/null | head -c 200 || true)"
      [ -z "$extra_first" ] && extra_first="(empty)"
      local esc_el esc_eb esc_ef
      esc_el="$(_board_html_escape "$extra_label")"
      esc_eb="$(_board_html_escape "$extra_base")"
      esc_ef="$(_board_html_escape "$extra_first")"
      printf '<tr><td>%s</td><td>%s</td><td>%s</td></tr>\n' "$esc_el" "$esc_eb" "$esc_ef"
    done
  fi

  if [ "$found_any_stage" = "0" ]; then
    printf '<tr><td colspan="3">(no packet files found)</td></tr>\n'
  fi

  printf '</tbody>\n</table>\n'

  # -----------------------------------------------------------------------
  # Ledger cost — rows in .agent_tasks/ledger.tsv for this task_id only.
  # Per-stage tokens/seconds + totals. Graceful degrade: no rows → message.
  # FL1: read-only (awk on ledger.tsv).
  # -----------------------------------------------------------------------
  printf '<h2>Cost (ledger)</h2>\n'
  local ledger_file="${repo}/.agent_tasks/ledger.tsv"

  if [ ! -f "$ledger_file" ]; then
    printf '<p style="color:#6b7280;font-size:.85rem;">(no cost recorded)</p>\n'
  else
    # Extract rows for this task_id only, compute per-stage + totals.
    # N4: all values from the ledger are repo data → HTML-escape before interpolation.
    local ledger_html
    ledger_html="$(awk -F'\t' -v tid="$task_id" '
      # Skip malformed rows (< 5 fields) and non-matching task-ids
      NF < 5 { next }
      $2 != tid { next }
      $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ { next }
      {
        rows[NR]["ts"]    = $1
        rows[NR]["stage"] = $3
        rows[NR]["tok"]   = $4 + 0
        rows[NR]["sec"]   = $5 + 0
        total_tok += $4 + 0
        total_sec += $5 + 0
        found++
      }
      END {
        if (!found) {
          print "NONE"
          exit
        }
        for (r in rows) {
          printf "ROW\t%s\t%s\t%d\t%d\n", rows[r]["ts"], rows[r]["stage"], rows[r]["tok"], rows[r]["sec"]
        }
        printf "TOT\t%d\t%d\n", total_tok, total_sec
      }
    ' "$ledger_file" 2>/dev/null || printf 'NONE\n')"

    if [ "$ledger_html" = "NONE" ] || [ -z "$ledger_html" ]; then
      printf '<p style="color:#6b7280;font-size:.85rem;">(no cost recorded)</p>\n'
    else
      printf '<table class="task-list">\n'
      printf '<thead><tr><th>Timestamp</th><th>Stage</th><th>Tokens</th><th>Seconds</th></tr></thead>\n'
      printf '<tbody>\n'
      local line
      while IFS= read -r line; do
        case "$line" in
          ROW*)
            local ts_val stg_val tok_val sec_val
            ts_val="$( printf '%s' "$line" | cut -f2)"
            stg_val="$(printf '%s' "$line" | cut -f3)"
            tok_val="$(printf '%s' "$line" | cut -f4)"
            sec_val="$(printf '%s' "$line" | cut -f5)"
            local ets estg etok esec
            ets="$( _board_html_escape "$ts_val")"
            estg="$(_board_html_escape "$stg_val")"
            etok="$(_board_html_escape "$tok_val")"
            esec="$(_board_html_escape "$sec_val")"
            printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
              "$ets" "$estg" "$etok" "$esec"
            ;;
          TOT*)
            local tot_tok tot_sec
            tot_tok="$(printf '%s' "$line" | cut -f2)"
            tot_sec="$(printf '%s' "$line" | cut -f3)"
            local etottok etotssec
            etottok="$(_board_html_escape "$tot_tok")"
            etotssec="$(_board_html_escape "$tot_sec")"
            printf '<tr style="font-weight:600;background:#e5e7eb;"><td colspan="2">TOTAL</td><td>%s</td><td>%s</td></tr>\n' \
              "$etottok" "$etotssec"
            ;;
        esac
      done <<EOF2
$ledger_html
EOF2
      printf '</tbody>\n</table>\n'
    fi
  fi

  _fleet_html_footer
}

# _fleet_discover_repos_list <fleet_root_or_tsv> <tsv_mode:0|1>
# Print a newline-separated list of repo absolute paths.
_fleet_discover_repos_list() {
  local fleet_root_or_tsv="$1" tsv_mode="${2:-0}"
  if [ "$tsv_mode" = "0" ]; then
    local maxdepth
    maxdepth="$(_fleet_maxdepth)"
    if [ -d "$fleet_root_or_tsv" ]; then
      find "$fleet_root_or_tsv" -maxdepth "$maxdepth" -name '.massoh' -type f \
        2>/dev/null | head -n 200 | sed 's|/\.massoh$||' || true
    fi
  else
    if [ -f "$fleet_root_or_tsv" ]; then
      while IFS= read -r line; do
        case "$line" in ''|\#*) continue;; esac
        [ "${#line}" -gt 4096 ] && continue
        [ -d "$line" ] || continue
        printf '%s\n' "$line"
      done < "$fleet_root_or_tsv"
    fi
  fi
}

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

# --- fleet serve subcommand (N1/N2/N3/N7 from 00_architecture_review.md) ---
# massoh fleet serve [--port N]
# Starts scripts/massoh-dashboard (Python stdlib only) bound to 127.0.0.1 (hard-coded, N1).
# --port is the only knob (default 8787). If python3 is absent: clear message + exit non-zero (N7).
# set -euo pipefail safe: all fallible commands guarded.
_fleet_serve() {
  set -euo pipefail
  local port=8787

  while [ $# -gt 0 ]; do case "$1" in
    --port) shift; port="${1:-8787}";;
    --help|-h)
      printf 'massoh fleet serve [--port N]\n'
      printf '\n'
      printf 'Start the Massoh Fleet dashboard server.\n'
      printf '  Binds to 127.0.0.1 ONLY (not configurable).\n'
      printf '  Default port: 8787. Override with --port N.\n'
      printf '  Requires: python3 (stdlib; no pip deps).\n'
      printf '  Stop with Ctrl-C or SIGTERM.\n'
      return 0
      ;;
    *) die "unknown fleet serve flag: $1";;
  esac; shift; done

  # N7: guard — python3 must be present; if absent, clear message + non-zero exit.
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'massoh fleet serve: python3 is required but not found.\n' >&2
    printf '  Install python3 to use the fleet dashboard.\n' >&2
    return 1
  fi

  # Locate scripts/massoh-dashboard relative to the Massoh home (same pattern as bin/massoh).
  local dashboard
  dashboard="${MASSOH_HOME:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)}/scripts/massoh-dashboard"

  if ! [ -f "$dashboard" ]; then
    printf 'massoh fleet serve: dashboard script not found: %s\n' "$dashboard" >&2
    printf '  Re-run "massoh install" to restore it.\n' >&2
    return 1
  fi

  # N1: host is hard-coded 127.0.0.1 here in the caller too (belt-and-suspenders).
  # The dashboard script also enforces this independently.
  # exec replaces the shell process so no orphan parent lingers (N3).
  exec python3 "$dashboard" --port "$port"
}

# ---------------------------------------------------------------------------
# cmd_fleet_learn — aggregate cross-repo lesson candidates (FLN1–FLN8)
#
# Reads LEARNINGS.proposed.md + META.proposed.md from each discovered repo
# (read-only; || true on every read — FLN6).  Clusters lessons by recurrence
# and writes a consolidated candidates doc to THIS repo only (FLN3/FLN4).
# ZERO LLM / ZERO network / ZERO spend (FLN1).
# ---------------------------------------------------------------------------
cmd_fleet_learn() {
  set -euo pipefail

  # FLN3 / FLN8: single named write target + SAFETY comment; Pattern A (sentinel-regenerate)
  local repo
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  local FLEET_LEARNINGS="$repo/agent-project/FLEET_LEARNINGS.proposed.md"  # SAFETY: only permitted write in cmd_fleet_learn

  # FLN8: recurrence threshold — NAMED CONSTANT (never a magic number)
  local FLEET_REPEAT_THRESHOLD=2

  local write_proposals=0 fleet_root="" tsv_file=""

  while [ $# -gt 0 ]; do case "$1" in
    --write-proposals) write_proposals=1;;
    --no-write)        write_proposals=0;;
    --root)            shift; fleet_root="${1:-}";;
    --help|-h)
      printf 'massoh fleet learn [--write-proposals|--no-write] [--root <dir>]\n'
      printf '\n'
      printf 'Aggregate cross-repo lesson candidates (ZERO LLM, read-only on discovered repos).\n'
      printf 'With --write-proposals: write consolidated candidates to agent-project/FLEET_LEARNINGS.proposed.md\n'
      printf 'Without --write-proposals (default): print candidate summary to stdout only.\n'
      return 0
      ;;
    *) die "unknown fleet learn flag: $1";;
  esac; shift; done

  # env var fallback for fleet root
  [ -z "$fleet_root" ] && fleet_root="${MASSOH_FLEET_ROOT:-}"
  tsv_file="${MASSOH_FLEET_TSV:-$_FLEET_TSV_DEFAULT}"

  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  local ver
  ver="$(mver 2>/dev/null || cat "$repo/VERSION" 2>/dev/null || printf 'unknown')"

  # -------------------------------------------------------------------------
  # Discover repos (same logic as cmd_fleet)
  # -------------------------------------------------------------------------
  local repo_list=""
  if [ -n "$fleet_root" ]; then
    if [ -d "$fleet_root" ]; then
      local maxdepth
      maxdepth="$(_fleet_maxdepth)"
      repo_list="$(find "$fleet_root" -maxdepth "$maxdepth" -name '.massoh' -type f \
        2>/dev/null | head -n 200 | sed 's|/\.massoh$||' || true)"
    fi
  elif [ -f "$tsv_file" ]; then
    while IFS= read -r _fl_line; do
      case "$_fl_line" in ''|\#*) continue;; esac
      [ "${#_fl_line}" -gt 4096 ] && continue
      [ -d "$_fl_line" ] || continue
      repo_list="${repo_list}${_fl_line}
"
    done < "$tsv_file"
  fi

  # -------------------------------------------------------------------------
  # Per-repo lesson extraction (FLN2: read-only; FLN6: || true + [ -f ] guard)
  # Lesson format collected: "<lesson_text>\t<repo_basename>"
  # -------------------------------------------------------------------------
  # all_lessons: newline-sep "<sanitized_lesson_text>\t<repo_basename>"
  local all_lessons="" skip_report=""

  local rp
  while IFS= read -r rp; do
    [ -n "$rp" ] || continue
    [ -d "$rp" ] || continue

    # FLN5: use basename only (never abs-path in output) — leak guard
    local rp_name
    rp_name="$(basename "$rp" 2>/dev/null || printf '%s' "$rp")"

    local learnings_file="${rp}/agent-project/LEARNINGS.proposed.md"
    local meta_file="${rp}/agent-project/META.proposed.md"

    local found_any_file=0

    # Read LEARNINGS.proposed.md — FLN2: only used as arg to read commands
    if [ -f "$learnings_file" ]; then
      found_any_file=1
      # Extract lesson lines (lines starting with "- "), strip leading "- " prefix,
      # cap at 100 lines (FLN5).
      local llines
      llines="$(grep -E '^\- ' "$learnings_file" 2>/dev/null | sed 's/^- //' | head -n 100 || true)"
      if [ -n "$llines" ]; then
        local ll
        while IFS= read -r ll; do
          [ -n "$ll" ] || continue
          # FLN5: cap at 500 chars; FLN8: sanitize | and backticks
          local sanitized
          sanitized="$(printf '%s' "$ll" | head -c 500 | sed 's/|/ /g; s/`/'"'"'/g' || true)"
          [ -n "$sanitized" ] || continue
          all_lessons="${all_lessons}${sanitized}	${rp_name}
"
        done <<EOF_LL
$llines
EOF_LL
      fi
    fi

    # Read META.proposed.md — FLN2: only used as arg to read commands
    if [ -f "$meta_file" ]; then
      found_any_file=1
      # Extract proposal bullet lines (lines starting with "- "), strip leading "- " prefix.
      local mlines
      mlines="$(grep -E '^\- ' "$meta_file" 2>/dev/null | sed 's/^- //' | head -n 100 || true)"
      if [ -n "$mlines" ]; then
        local ml
        while IFS= read -r ml; do
          [ -n "$ml" ] || continue
          # FLN5: cap at 500 chars; FLN8: sanitize
          local m_sanitized
          m_sanitized="$(printf '%s' "$ml" | head -c 500 | sed 's/|/ /g; s/`/'"'"'/g' || true)"
          [ -n "$m_sanitized" ] || continue
          all_lessons="${all_lessons}${m_sanitized}	${rp_name}
"
        done <<EOF_ML
$mlines
EOF_ML
      fi
    fi

    if [ "$found_any_file" = "0" ]; then
      # FLN6: no proposals → [skip] line; continue (per-repo degrade, exit 0 overall)
      skip_report="${skip_report}  [skip] ${rp_name}: no LEARNINGS.proposed.md or META.proposed.md found
"
    fi
  done <<EOF_RP
$repo_list
EOF_RP

  # -------------------------------------------------------------------------
  # Cluster by recurrence: count how many distinct repos each lesson appears in
  # (FLN8: threshold is FLEET_REPEAT_THRESHOLD named constant)
  # -------------------------------------------------------------------------
  # Build a deduplicated list of unique (lesson_text, repo) pairs first,
  # then count repos-per-lesson-text.
  # All processing via awk || true (FLN6).

  # lesson_summary: "<tag>\t<count>\t<sources>\t<text>"
  local lesson_summary
  lesson_summary="$(printf '%s\n' "$all_lessons" | awk -F'\t' -v thr="$FLEET_REPEAT_THRESHOLD" '
    NF < 2 { next }
    {
      txt = $1; src = $2
      # deduplicate (txt, src) pairs
      key = txt SUBSEP src
      if (seen[key]++) next
      # count repos per lesson text
      repo_count[txt]++
      # accumulate sources (comma-sep, deduplication handled via seen above)
      if (sources[txt] == "") { sources[txt] = src }
      else { sources[txt] = sources[txt] ", " src }
    }
    END {
      for (txt in repo_count) {
        cnt = repo_count[txt]
        tag = (cnt >= thr) ? "[generalizable-candidate]" : "[project: " sources[txt] "]"
        printf "%s\t%d\t%s\t%s\n", tag, cnt, sources[txt], txt
      }
    }
  ' 2>/dev/null | sort -t$'\t' -k2 -rn 2>/dev/null || true)"

  # -------------------------------------------------------------------------
  # Print candidate summary to stdout (always, regardless of --write-proposals)
  # -------------------------------------------------------------------------
  say "massoh fleet learn — $ts  (v$ver)"
  say "  Cross-repo lesson candidates (threshold=${FLEET_REPEAT_THRESHOLD} repos for [generalizable-candidate]):"
  if [ -z "$(printf '%s' "$lesson_summary" | tr -d '[:space:]')" ]; then
    say "  (no lessons found across fleet)"
  else
    local ls_line
    while IFS= read -r ls_line; do
      [ -n "$ls_line" ] || continue
      local ls_tag ls_cnt ls_src ls_txt
      ls_tag="$(printf '%s' "$ls_line" | cut -f1)"
      ls_cnt="$(printf '%s' "$ls_line" | cut -f2)"
      ls_src="$(printf '%s' "$ls_line" | cut -f3)"
      ls_txt="$(printf '%s' "$ls_line" | cut -f4)"
      say "  ${ls_tag} (repos=${ls_cnt}, sources=${ls_src}): ${ls_txt}"
    done <<EOF_SUM
$lesson_summary
EOF_SUM
  fi
  if [ -n "$skip_report" ]; then
    say "$skip_report"
  fi

  # -------------------------------------------------------------------------
  # FLN7: --write-proposals → Pattern A (sentinel-regenerate, idempotent)
  # The file is always regenerated fresh; two runs produce identical content.
  # -------------------------------------------------------------------------
  if [ "$write_proposals" = "1" ]; then
    mkdir -p "$repo/agent-project"
    {
      printf '<!-- massoh-fleet-generated -->\n'
      printf '# FLEET_LEARNINGS — Candidate Pool\n'
      printf '\n'
      printf '> CANDIDATES ONLY — engine adoption is a separate owner/gated step.\n'
      printf '> Generated: %s (v%s)\n' "$ts" "$ver"
      printf '> Recurrence threshold: %d repos for [generalizable-candidate].\n' "$FLEET_REPEAT_THRESHOLD"
      printf '> Source attribution uses repo basename only (not absolute path).\n'
      printf '\n'
      printf '## Lessons\n'
      printf '\n'
      if [ -z "$(printf '%s' "$lesson_summary" | tr -d '[:space:]')" ]; then
        printf '(no lessons found across discovered repos)\n'
      else
        local ls2_line
        while IFS= read -r ls2_line; do
          [ -n "$ls2_line" ] || continue
          local ls2_tag ls2_cnt ls2_src ls2_txt
          ls2_tag="$(printf '%s' "$ls2_line" | cut -f1)"
          ls2_cnt="$(printf '%s' "$ls2_line" | cut -f2)"
          ls2_src="$(printf '%s' "$ls2_line" | cut -f3)"
          ls2_txt="$(printf '%s' "$ls2_line" | cut -f4)"
          # FLN8: printf '%s' with named vars — never eval; fields already sanitized
          # Use printf -- to prevent format string starting with '-' being parsed as option
          printf -- '- %s (repos=%s, sources=%s): %s\n' \
            "$ls2_tag" "$ls2_cnt" "$ls2_src" "$ls2_txt"
        done <<EOF_W
$lesson_summary
EOF_W
      fi
      printf '\n'
      printf '## Skipped repos (no proposals)\n'
      printf '\n'
      if [ -z "$(printf '%s' "$skip_report" | tr -d '[:space:]')" ]; then
        printf '(none)\n'
      else
        printf '%s\n' "$skip_report"
      fi
    } > "$FLEET_LEARNINGS"  # SAFETY: only permitted write in cmd_fleet_learn (FLN3)
    say "  -> wrote $FLEET_LEARNINGS"
  fi
}

cmd_fleet() {
  # FL8: local-only, no upload
  local fleet_root="" use_cache=0 tsv_file=""
  local maxdepth

  # Dispatch subcommands first (before option parsing).
  case "${1:-}" in
    serve) shift; _fleet_serve "$@"; return $?;;
    learn) shift; cmd_fleet_learn "$@"; return $?;;
  esac

  while [ $# -gt 0 ]; do case "$1" in
    --root)      shift; fleet_root="${1:-}";;
    --no-cache)  use_cache=0;;
    --cache)     use_cache=1;;
    --help|-h)
      printf 'massoh fleet [--root <dir>] [--no-cache]\n'
      printf 'massoh fleet serve [--port N]\n'
      printf 'massoh fleet learn [--write-proposals] [--root <dir>]\n'
      printf '\n'
      printf 'Discover opted-in Massoh repos and print a per-repo rollup.\n'
      printf 'Use "massoh fleet serve" to start the observability dashboard.\n'
      printf 'Use "massoh fleet learn" to aggregate cross-repo lesson candidates.\n'
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
