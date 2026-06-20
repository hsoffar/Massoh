# 06 — Review result: Fleet slice 1a — dashboard content

- **Task:** TASK-2026-06-20-fleet-observability / slice 1a (content)
- **Reviewer:** massoh-reviewer-qa
- **Date:** 2026-06-20
- **Branch:** `feat/fleet-dashboard`
- **Verdict: APPROVE**

---

## Verdict summary

All conditions from `04_slice-1a-content.md` and `00_architecture_review.md` (N1–N7, FL1, Seam A/B)
are independently verified. Tests: **504/504 green** (self-witnessed, exit 0). Traversal → 404,
XSS escape, and read-only invariant independently reproduced live. Scope is clean. No safety-critical
file touched.

---

## Condition verification (file:line)

### N1 — Loopback-only
- `scripts/massoh-dashboard:40` — `BIND_HOST = "127.0.0.1"` (module-level constant, hard-coded)
- `scripts/massoh-dashboard:344` — `socketserver.TCPServer((BIND_HOST, port), handler_class)` — only argument is the constant
- `scripts/massoh-dashboard:353-359` — `argparse` accepts `--port` only; no `--host` argument exists
- `lib/verbs/fleet.sh:654-657` — belt-and-suspenders comment; `exec python3 "$dashboard" --port "$port"` passes only `--port`
- Reproduced live: `GET / → 200`, `/repo/alpha-repo → 200` on 127.0.0.1; no --host switch exists in code

### N2 — Route allowlist + set-membership (highest-priority security condition)
- `scripts/massoh-dashboard:214` — `_FleetHandler` extends `http.server.BaseHTTPRequestHandler` (NOT `SimpleHTTPRequestHandler`); `translate_path()` is never called
- `scripts/massoh-dashboard:211` — `_REPO_NAME_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)$")` — regex gates before any set-membership check; `%` is NOT in the allowed character class
- `scripts/massoh-dashboard:247` — `raw_path = self.path.split("?", 1)[0].split("#", 1)[0]` — query/fragment stripped
- `scripts/massoh-dashboard:250-252` — GET `/` matched first (literal string equality)
- `scripts/massoh-dashboard:256-267` — `/repo/<name>`: regex match → `urllib.parse.unquote` → set-membership check (`if repo_name not in self.repo_name_map → _send_404()`)
- `scripts/massoh-dashboard:269` — `repo_path = self.repo_name_map[repo_name]` — filesystem path comes from the SERVER-SIDE MAP ONLY, never from the URL
- `scripts/massoh-dashboard:274-275` — catch-all: any unmatched path → `_send_404()`
- `scripts/massoh-dashboard:112-124` — `_build_repo_name_map` built from `_discover_repos()` at startup; no HTTP input touches the map
- **Traversal independently reproduced:**
  - `GET /repo/..%2f..%2fetc/passwd → 404` (regex rejects `%` character)
  - `GET /repo/../../../etc/passwd → 404` (regex rejects `.` sequences with `/`)
  - `GET /repo/nonexistent → 404` (set-membership check fails)
  - `GET /repo/alpha-repo → 200` (known repo in map)
- **Defense order confirmed by code inspection:** the regex (`%` not in `[A-Za-z0-9_.~\-]+`) rejects `%2f`-encoded traversals **before** `urllib.parse.unquote` is called. Even if unquoting ran, the set-membership check would still block unknown names.

### N3 — Clean lifecycle
- `scripts/massoh-dashboard:381-387` — `threading.Event` + `signal.signal(SIGINT/SIGTERM, _shutdown)` → `_stop_event.set()`
- `scripts/massoh-dashboard:389-390` — server runs on daemon thread; main thread blocks on `_stop_event.wait()`
- `scripts/massoh-dashboard:401-403` — `server.shutdown()` then `server.server_close()` on signal
- `lib/verbs/fleet.sh:657` — `exec python3 "$dashboard" --port "$port"` (no parent shell orphan)
- T-FS-14 confirmed: process gone after SIGTERM (504 suite confirms); post-suite pgrep clean (independently checked: `pgrep -f "massoh-dashboard"` exits 1)

### N4 — HTML escape in bash (Seam A) — every interpolated field
All interpolations via `_board_html_escape`. Enumeration across every render function:

**`_fleet_render_index` (fleet.sh:205–309):**
- `esc_name` (repo basename): line 259 `_board_html_escape "$repo_name"`
- `_board_html_escape "$ts"` (timestamp): line 236
- `e_open`, `e_blocked`, `e_thru`, `e_rework`, `e_cycle`, `e_tokens`, `e_cost`, `e_agent`, `e_mode`, `e_ver` (all 10 KPI fields): lines 280–289
- `url_name` (href attribute): line 294 sed-encoded for URL safety (not HTML but URL context; `esc_name` is used for HTML text)

**`_fleet_render_repo` (fleet.sh:315–392):**
- `esc_name` (repo name): line 319 `_board_html_escape "$repo_name"` — used in `<title>` (line 321) and `<h1>` (line 349)
- `esc_sib` (sibling nav names): line 335 `_board_html_escape "$sib_name"` — used in nav links and strong
- All 10 KPI fields passed to `_fleet_kpi_item` (lines 367–376) which escapes label+value internally (lines 399–400)

**`_fleet_kpi_item` (fleet.sh:394–403):**
- `esc_label`, `esc_value`: lines 399–400 `_board_html_escape` for both arguments

**`_fleet_render_board_inline` (fleet.sh:408–442):**
- `esc_stage` (column heading): line 421 `_board_html_escape "$stage"`
- `esc_tid`, `esc_title`, `esc_agent` (card fields): lines 428–430 `_board_html_escape` on each

**`_fleet_render_task_list` (fleet.sh:444–484):**
- `esc_tid`, `esc_stage`, `esc_agent`: lines 474–476 `_board_html_escape` on each

**`_fleet_render_commits` (fleet.sh:486–503):**
- `esc_commit` (git log line): line 496 `_board_html_escape "$commit_line"`

**`_fleet_html_footer` (fleet.sh:191–197):**
- `_board_html_escape "$ts"` (timestamp): line 195

**`_fleet_html_header` (fleet.sh:140–187):**
- `$title` parameter: documented "N4: title is already escaped by caller" (line 139)
- Callers: line 233 uses literal `"Massoh Fleet"` (safe); line 321 uses `"Massoh Fleet — $esc_name"` where `$esc_name` is pre-escaped (line 319)

**XSS escape independently reproduced:**
- Seeded `# <script>alert(1)</script> & "xss-task"` as task title in fake repo
- `GET /repo/alpha-repo`: no raw `<script>alert` in output; `&lt;script&gt;` confirmed present
- T-FS-11a/b/c pass (504 suite)

### N5 — Reuse, don't recompute
- `fleet.sh:_fleet_repo_kpis` reads from:
  - `.agent_tasks/TASK-*/` (task stage counting via `-f` checks, no metric recomputation)
  - `AGENT_BACKLOG.md` (grep for `| BLOCKED |`)
  - `agent-project/METRICS.md` (grep-extract last `throughput/wk=`, `rework_pct=`, `cycle_avg_days=` values)
  - `.agent_tasks/ledger.tsv` (awk sum; reuse, not recompute)
  - `AGENT_SYNC.md` (head -n 200 + grep for agent/mode)
  - `VERSION` file via `_fleet_read_version`
- No Python business logic; no new metric computation in `scripts/massoh-dashboard`

### N6 — GET-only / zero browser spend
- `scripts/massoh-dashboard:280-283` — `do_POST()` → `_send_404()` (independently reproduced: `POST / → 404`, `POST /repo/alpha-repo → 404`)
- `scripts/massoh-dashboard:277-278` — `do_HEAD()` → `_send_404()`
- No subprocess exec of any agent; `_run_bash_renderer` exec's `bash -c` with rendering-only functions

### N7 — Stdlib only
- Imports at lines 26–35: `argparse`, `http.server`, `os`, `re`, `shutil`, `signal`, `socketserver`, `subprocess`, `sys`, `threading` — all Python 3 stdlib
- `urllib.parse` imported inline at line 259 (also stdlib)
- No PyYAML, no pip dep
- `lib/verbs/fleet.sh:638-642` — python3 guard: `if ! command -v python3` → prints message + `return 1`

### FL1 — Read-only on discovered repos
- `fleet.sh` header (lines 12–13): explicit write-isolation guarantee documented
- All render functions use only: `find`, `grep`, `head`, `awk`, `cat`, `git log`, `git rev-parse`
- No `>`, `>>`, `tee`, `cp`, `mv`, `mkdir`, or `touch` in any `_fleet_render_*` or `_fleet_repo_kpis` function (grep confirmed: zero matches)
- **Read-only independently reproduced:** byte-snapshot of 2 fake repos before/after 3 curl requests (GET /, GET /repo/alpha-repo, GET /repo/beta-repo) → checksums identical for both repos
- T-FS-12a/b pass (504 suite)

---

## Test run (independently witnessed)

```
bash test/run.sh
...
  ok   T-FS-7a index HTTP 200
  ok   T-FS-7b index contains alpha-repo
  ok   T-FS-7c index contains beta-repo
  ok   T-FS-7d index has link to /repo/alpha-repo
  ok   T-FS-7e index has link to /repo/beta-repo
  ok   T-FS-7f index contains KPI table headers (Tokens)
  ok   T-FS-7g index contains Open tasks column
  ok   T-FS-7h index has massoh-generated sentinel
  ok   T-FS-8a /repo/alpha-repo returns HTTP 200
  ok   T-FS-8b /repo/alpha-repo contains repo name in title
  ok   T-FS-8c /repo/alpha-repo contains breadcrumb link to /
  ok   T-FS-8d /repo/alpha-repo contains KPI panel (kpi-panel class)
  ok   T-FS-8e /repo/alpha-repo contains board (board class)
  ok   T-FS-8f /repo/alpha-repo contains task-list table
  ok   T-FS-8g /repo/alpha-repo task list shows TASK-open-1
  ok   T-FS-8h /repo/alpha-repo sibling nav links to beta-repo
  ok   T-FS-8i /repo/alpha-repo has massoh-generated sentinel
  ok   T-FS-9 /repo/<unknown> → 404
  ok   T-FS-10a /repo/..%2f..%2fetc → 404 (encoded traversal)
  ok   T-FS-10b /repo/../../../etc → 404 (raw traversal)
  ok   T-FS-10c /repo/alpha-repo/../../etc → 404 (sub-path traversal)
  ok   T-FS-11a no raw <script> in fleet index (N4 escape)
  ok   T-FS-11b no raw <script> in repo view (N4 escape)
  ok   T-FS-11c &lt;script&gt; appears escaped in repo view
  ok   T-FS-12a alpha-repo byte-snapshot unchanged after render (read-only)
  ok   T-FS-12b beta-repo byte-snapshot unchanged after render (read-only)
  ok   T-FS-13 BIND_HOST = 127.0.0.1 still in updated dashboard source (N1)
  ok   T-FS-14 no orphan content-server process after SIGTERM (N3)
== T-FS done ==

ALL GREEN — 504 checks passed.
```

Test count: **504** (476 baseline + 28 new T-FS-7..T-FS-14; meets target ≥488).

Post-suite orphan check: `pgrep -f "massoh-dashboard"` → exit 1 (clean; no server running).

---

## Security reproduced independently

| Check | Result |
|---|---|
| `GET / → 200` | PASS |
| `GET /repo/alpha-repo → 200` | PASS |
| `GET /repo/nonexistent → 404` | PASS |
| `GET /repo/..%2f..%2fetc/passwd → 404` | PASS |
| `GET /repo/../../../etc/passwd → 404` | PASS |
| `POST / → 404` | PASS |
| `POST /repo/alpha-repo → 404` | PASS |
| No raw `<script>alert` in index or repo view | PASS |
| `&lt;script&gt;` escaped form present in repo view | PASS |
| alpha-repo byte-snapshot identical before/after render | PASS |
| beta-repo byte-snapshot identical before/after render | PASS |
| No orphan server process after SIGTERM | PASS |

Defense-order note (traversal): `_REPO_NAME_RE` regex (`[A-Za-z0-9_.~\-]+`) rejects `%` at the character class level, so `..%2f..%2fetc` is rejected **before** `urllib.parse.unquote` runs. Even if unquoting ran, the set-membership check would block unknown names. The layered design is correct.

---

## Scope

**Files changed (6 total):**
| File | Change | Verdict |
|---|---|---|
| `lib/verbs/fleet.sh` | Additive: new `_fleet_render_*` + `_fleet_repo_kpis` + `_fleet_discover_repos_list` functions; `cmd_fleet` and `_fleet_serve` are pre-existing from slice 1a-0 | CLEAN |
| `scripts/massoh-dashboard` | Extended: `/repo/<name>` route + set-membership + bash renderer invocation | CLEAN |
| `VERSION` | 0.19.0 → 0.20.0 | CORRECT |
| `CHANGELOG.md` | Added [0.20.0] entry | CORRECT |
| `test/run.sh` | Added T-FS-7..T-FS-14 (28 new checks) | CLEAN |
| `AGENT_SYNC.md` | Prior reviewer's slice 1a-0 APPROVE entry + handoff (expected review artifact) | EXPECTED |

**Safety-critical files untouched:**
- `bin/massoh` — `git diff HEAD -- bin/massoh` = empty
- `manifest.yml` — `git diff HEAD -- manifest.yml` = empty
- `agent-project/NON_NEGOTIABLES.md` — untouched
- `templates/` — untouched
- `AGENT_BACKLOG.md` — untouched

**Parked items correctly excluded:** slice 1c (POST), slice 3 browser button — both absent from the implementation. No scope creep.

---

## Blocking issues

None.

---

## Non-blocking issues

**NB-1: `shutil` imported but unused** (`scripts/massoh-dashboard:30`)
- `import shutil` appears at line 30 but `shutil` is never called anywhere in the file.
- No security risk (stdlib module). Dead code only.
- Fix: remove the import. Does not require re-review.

**NB-2: `urllib.parse` imported inline inside `do_GET`** (`scripts/massoh-dashboard:259`)
- `import urllib.parse` is inside the method body rather than at the module top. Python caches module imports so this is not a performance issue, but it's non-idiomatic.
- No security risk.
- Fix: move to top-level imports alongside the other stdlib imports. Does not require re-review.

**NB-3: `_fleet_html_header` title parameter not self-escaping**
- The function takes `$title` and prints it raw (`printf '<title>%s</title>\n' "$title"`). This is sound because callers always pre-escape: line 233 uses a literal, line 321 uses `$esc_name`. The contract is documented in the comment. However, if a future caller passes an unescaped value the function will not catch it.
- Not a current vulnerability. Suggest adding `esc_title="$(_board_html_escape "$title")"` inside the function as a defensive measure. Does not require re-review.

---

## Missing tests

None. T-FS-7 through T-FS-14 (28 checks) are substantive:
- T-FS-7a–h: live HTTP requests against a real running server; verify real rendered output
- T-FS-8a–i: live per-repo view with real fake-task data
- T-FS-9: set-membership 404 against real server
- T-FS-10a–c: traversal 404s against real server (independently reproduced)
- T-FS-11a–c: XSS escape with a real seeded `<script>` task title
- T-FS-12a–b: byte-snapshot read-only proof with real repos before/after requests
- T-FS-13: source-level BIND_HOST constant check
- T-FS-14: process lifecycle / no orphan

---

## Safety / guardrail concerns

None. All guardrails (09_GUARDRAILS.md):
- A1 (license): `04_slice-1a-content.md` exists and is licensed — SATISFIED
- A2 (branch+PR): on `feat/fleet-dashboard` — SATISFIED
- A3 (keep older data): no deletes; additive only — SATISFIED
- A5 (real tests): T-FS-7..T-FS-14 exercise real paths — SATISFIED
- A9 (scope discipline): exactly approved scope — SATISFIED
- B (owner-gated): slice 1c/3 correctly parked — SATISFIED

---

## Hidden scope / expansion concerns

None. Slice 1c (POST→intake) and slice 3 (browser button) are correctly absent. No new safety-critical file changes. No hardcoded locale/region. MASSOH_FLEET_ROOT/MASSOH_FLEET_TSV env vars allow expansion; host is correctly not configurable (N1).

---

## Verdict

**APPROVE.**

- N1 (loopback): `BIND_HOST = "127.0.0.1"` at line 40; single `--port` knob; independently verified.
- N2 (route allowlist + set-membership): regex rejects `%`, `.`, `/` at char-class level; `repo_name` never `os.path.join`'d; traversal → 404 independently reproduced.
- N3 (lifecycle): SIGTERM → clean shutdown; no orphan; independently confirmed post-suite.
- N4 (escape every field): all 10 KPI fields + task titles + commit messages + sibling nav + stage labels + timestamps escapes enumerated and verified; XSS independently reproduced and blocked.
- N5 (reuse): KPIs read from METRICS.md / ledger.tsv / AGENT_SYNC.md / AGENT_BACKLOG.md; no recomputation in Python.
- N6 (GET-only / zero spend): POST → 404 independently reproduced; no agent exec.
- N7 (stdlib-only): all imports are stdlib; python3 guard in fleet.sh.
- FL1 (read-only): byte-snapshot independently reproduced; no write ops in render functions.
- VERSION 0.20.0 + CHANGELOG [0.20.0] present.
- Suite: **504/504 green** (self-witnessed).
- Scope: **6 files only**; safety-critical files diff=0.
- NB-1 (unused shutil import) and NB-2 (inline urllib.parse import) are non-blocking style issues; NB-3 (header title not self-escaping) is a future defensive hardening suggestion.
