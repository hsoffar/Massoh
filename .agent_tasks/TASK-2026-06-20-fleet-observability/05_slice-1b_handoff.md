# 05 — Implementation Handoff: Fleet slice 1b — task drill-down (v0.21.0)

- **Agent:** massoh-implementer
- **Branch:** feat/fleet-taskview
- **Date:** 2026-06-20
- **Handoff to:** massoh-reviewer-qa

---

## Files changed

| File | Change |
|---|---|
| `lib/verbs/fleet.sh` | Added `_fleet_render_task` (bash renderer, Seam A) |
| `scripts/massoh-dashboard` | Extended route allowlist + double set-membership (Seam B) |
| `VERSION` | 0.20.0 → 0.21.0 |
| `CHANGELOG.md` | Added [0.21.0] entry |
| `test/run.sh` | Added T-FS-15..T-FS-24 (additive; 504 → 528 green) |

**Safety-critical files NOT touched:** `bin/massoh`, `manifest.yml`. Verified: `git diff HEAD -- bin/massoh manifest.yml` → 0 bytes.

---

## What was implemented

### 1. `_fleet_render_task` in `lib/verbs/fleet.sh` (Seam A)

Location: `lib/verbs/fleet.sh`, inserted before `_fleet_discover_repos_list`.

- Accepts: `repo`, `repo_name`, `task_id`, `task_dir` (all from server-side trusted sources).
- Emits: HTML breadcrumb (`/` → `/repo/<name>` → task) + link back to board.
- **Stage trail (index only — no full body):** iterates over known stage filenames (00→06) + any extra `??_*.md`/`handoff*.md`/`proposal*.md`. For each present file: reads only the first non-empty line (`grep -m1 '[^[:space:]]' | head -c 200`). Shows: stage label | filename | first line. Full file body is never read beyond the first line (scope + leak guard).
- **Ledger cost:** awk on `ledger.tsv` filtering by `task_id`. Outputs per-row (ROW\t…) and total (TOT\t…) lines, then renders them as a table. Graceful degrade: no file → "(no cost recorded)"; no matching rows → "(no cost recorded)".
- **N4 everywhere:** every interpolated value (repo_name, task_id, stage labels, filenames, first-lines, ledger timestamps/stages/tokens/seconds) passes through `_board_html_escape` before interpolation. Stage first-lines are treated as repo content (data), never as trusted text.
- `set -euo pipefail` at top of function; graceful degrade on all missing files (never crashes).

### 2. `scripts/massoh-dashboard` (Seam B)

- Added `_TASK_VIEW_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/task/([A-Za-z0-9_.~\-]+)$")` — both name and task-id segments are restricted to safe characters; any other byte pattern (including `%2f`, `../..`) returns 404 before set-membership.
- Added `_discover_tasks_for_repo(repo_path)` — discovers `.agent_tasks/TASK-*/` basenames using `os.listdir` on the TRUSTED repo_path. Returns a `set` of strings. Capped at 200 entries. task-id is ONLY used to look up in this set — never passed to `os.path.join` or `os.path.isdir` as an untrusted value.
- Extended `do_GET` with the task route handler — checked BEFORE `/repo/<name>` to avoid partial match. **Double set-membership:**
  1. `repo_name not in self.repo_name_map` → 404 (same as existing 1a)
  2. `task_id not in task_set` → 404 (new; task_set from `_discover_tasks_for_repo(repo_path)`)
- Added `_render_task` method — delegates to bash `_fleet_render_task` via `_run_bash_renderer`. `task_dir` is constructed as `os.path.join(repo_path, ".agent_tasks", task_id)` ONLY after task_id has passed: regex char filter + set-membership + regex match (i.e., task_id is a known, valid basename).
- POST → 404 unchanged (N6, slice 1c parked).

---

## Conditions file:line

| Condition | File | Lines |
|---|---|---|
| Double set-membership — repo name | `scripts/massoh-dashboard` | `_build_repo_name_map`, `do_GET` block: `repo_name not in self.repo_name_map` |
| Double set-membership — task-id | `scripts/massoh-dashboard` | `_discover_tasks_for_repo`, `do_GET` block: `task_id not in task_set` |
| task_dir constructed only after validation | `scripts/massoh-dashboard` | `task_dir = os.path.join(repo_path, ".agent_tasks", task_id)` — after both checks |
| Regex char filter (traversal blocked pre-check) | `scripts/massoh-dashboard` | `_TASK_VIEW_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/task/([A-Za-z0-9_.~\-]+)$")` |
| N4 escape in bash renderer | `lib/verbs/fleet.sh` | `_fleet_render_task`: every `printf` uses `_board_html_escape` on all vars |
| No full-body dump | `lib/verbs/fleet.sh` | `grep -m1 '[^[:space:]]' "$full_path" 2>/dev/null \| head -c 200` — first line only |
| Graceful degrade (no ledger) | `lib/verbs/fleet.sh` | `[ ! -f "$ledger_file" ]` → `(no cost recorded)` |
| Graceful degrade (no rows) | `lib/verbs/fleet.sh` | awk outputs `NONE` when no matching rows; shell checks `[ "$ledger_html" = "NONE" ]` |
| set -euo pipefail | `lib/verbs/fleet.sh` | `_fleet_render_task`: `set -euo pipefail` at top |
| GET-only (no POST) | `scripts/massoh-dashboard` | `do_POST` → `_send_404()` unchanged |
| N1 loopback | `scripts/massoh-dashboard` | `BIND_HOST = "127.0.0.1"` unchanged |
| N7 stdlib only | `scripts/massoh-dashboard` | no new imports beyond stdlib |

---

## Drill-down sample (alpha-repo / TASK-drill-1)

Rendered page sections (from T-FS-15 test run):
- Breadcrumb: `← Fleet index › alpha-repo › TASK-drill-1`
- Link: `← Back to alpha-repo board`
- **Packet trail table:**
  - `00_request_md | 00_request.md | # &lt;script&gt;alert(&quot;drill&quot;)&lt;/script&gt; — drill-down test request`
  - `04_implementation_packet | 04_implementation_packet.md | # 04 — Implementation packet for drill-down task`
- **Cost table:**
  - `2026-06-20T01:00:00Z | scope | 1234 | 90`
  - `2026-06-20T02:00:00Z | implement | 5678 | 300`
  - `TOTAL | 6912 | 390`
- Footer: massoh-generated sentinel + timestamp

---

## Escape proof

T-FS-19a: `! printf '%s' "$_fs15_body" | grep -F '<script>alert'` → PASS (no raw `<script>alert` in output)
T-FS-19b: `printf '%s' "$_fs15_body" | grep -qF '&lt;script&gt;'` → PASS (`<script>` appears escaped)

The 00_request.md first line `# <script>alert("drill")</script> — drill-down test request` is rendered as:
`# &lt;script&gt;alert(&quot;drill&quot;)&lt;/script&gt; — drill-down test request`

---

## Double-404 proof

- T-FS-16: `/repo/alpha-repo/task/TASK-nonexistent-xyz` → 404 ✓ (unknown task-id, known repo)
- T-FS-17: `/repo/no-such-repo/task/TASK-drill-1` → 404 ✓ (unknown repo)
- T-FS-18a: `/repo/alpha-repo/task/..%2f..` → 404 ✓ (encoded traversal — fails regex before set-membership)
- T-FS-18b: `/repo/alpha-repo/task/../..` → 404 ✓ (raw traversal — fails regex)

---

## Read-only snapshot proof

T-FS-20: alpha-repo byte-snapshot taken before + after `/`, `/repo/alpha-repo`, and `/repo/alpha-repo/task/TASK-drill-1` renders → `before == after` (md5sum) ✓

---

## No-full-body proof

T-FS-21a: `! grep -qF 'Line 10.'` in drill-down body → PASS (body not dumped)
T-FS-21b: `! grep -qF 'Line 15.'` in drill-down body → PASS
T-FS-21c: `grep -qi 'drill-down test request'` → PASS (first-line label present)

The 00_request.md has 15+ lines of body content; only the first line appears in the rendered output.

---

## Test count

Suite run: **528/528 green** (`bash test/run.sh` → `ALL GREEN — 528 checks passed.`)
T-FS-15..T-FS-24: 24 new checks (10 subtests under T-FS-15 + 1+1+2+2+1+3+1+1 = all named above).

---

## Risks

1. The `_fleet_render_task` awk block uses a `rows[]` array keyed by NR. On awk versions where the hash ordering is non-deterministic, row order in the ledger table may differ from TSV order. This is cosmetic only (totals are correct; ordering is not contractual).
2. The regex `[A-Za-z0-9_.~\-]+` excludes parentheses and spaces from task-id segments. If a repo has a task directory with such characters in its name, it would return 404 on the drill-down. The existing T-FS-15..T-FS-24 fixture uses standard `TASK-` naming which complies. Existing naming conventions in the test suite confirm this is the expected pattern.
3. `_fleet_render_task` calls `set -euo pipefail` which is already set in fleet.sh's sourcing context — this is belt-and-suspenders and matches the existing pattern in `_fleet_serve`.

---

## Incomplete items

- None within slice 1b scope.
- Slice 1c (POST → intake) remains PARKED for owner sign-off (architect ruling, 00_architecture_review.md §4 R3).

---

## Handoff to reviewer-qa

- Branch: `feat/fleet-taskview`
- Run: `bash test/run.sh` → expect 528 green
- Spot-check: start `MASSOH_FLEET_ROOT=<a massoh repo parent> massoh fleet serve --port 9876`, navigate to `/repo/<name>/task/<task-id>` in browser
- Verify: breadcrumb, stage trail (index only), ledger table, no raw `<script>` in output
- Verify: `/repo/<name>/task/unknown-task` → 404; `/repo/unknown/task/x` → 404; `/repo/x/task/..%2f` → 404
- Check: `bin/massoh` and `manifest.yml` checksums unchanged from main
- Check: VERSION = 0.21.0 in `VERSION` file and CHANGELOG entry present
