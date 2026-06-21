# 05 — Implementation Handoff: A3 Dashboard Hardening (v0.27.0)

**Branch:** `feat/fleet-hardening`
**Commit:** `96c8ff6`
**Suite result:** 685/685 checks passed (ALL GREEN)
**8787 sentinel:** 200 after full test run

---

## Condition → File:Line Citations

### #20 (P1) — Task list clickable hrefs

**Condition:** Each task id in the task list on `/repo/<name>` must be an
`<a href="/repo/<name>/task/<id>">` to the existing drill-down. Id escaped in BOTH
href and text via `_board_html_escape`.

- **`lib/verbs/fleet.sh` — `_fleet_render_task_list` (line ~843)**:
  - Function signature changed from `<repo>` to `<repo> <repo_name>`.
  - `url_tid` computed via `sed` percent-encoding (same pattern as `_fleet_render_index`).
  - When `url_name` is non-empty, emits:
    `<a href="/repo/$url_name/task/$url_tid">$esc_tid</a>` where both `url_tid` and
    `esc_tid` are derived from `_board_html_escape`.
  - Falls back to plain text when `repo_name` is empty (defensive).
- **`lib/verbs/fleet.sh` — `_fleet_render_repo` (line ~386)**:
  - Changed `_fleet_render_task_list "$repo"` → `_fleet_render_task_list "$repo" "$repo_name"`.

### #19 (P3) — Per-request repo map rebuild

**Condition:** The `repo_name_map` must be rebuilt per-request from the same
`_discover_repos()` source as the index, so a repo added to fleet.tsv after launch
resolves without restart.

- **`scripts/massoh-dashboard` — `_FleetHandler` class attributes (line ~579)**:
  - Removed `repo_name_map: dict = {}` class attribute entirely.
- **`scripts/massoh-dashboard` — `_get_repo_name_map()` method (line ~600)**:
  - New instance method; calls `_discover_repos()` + `_build_repo_name_map()` per invocation.
- **`scripts/massoh-dashboard` — `do_GET()` (line ~657)**:
  - Calls `repo_name_map = self._get_repo_name_map()` at the top, before any route check.
  - All five `self.repo_name_map` references replaced with `repo_name_map` (local variable).
- **`scripts/massoh-dashboard` — `do_POST()` (line ~869)**:
  - B4 repo validation now calls `_post_repo_name_map = self._get_repo_name_map()`.
- **`scripts/massoh-dashboard` — `_render_repo()` (line ~969)**:
  - Sibling nav list now built from `self._get_repo_name_map().values()`.
- **`scripts/massoh-dashboard` — `_make_handler_class()` (line ~1084)**:
  - Removed `repo_name_map` parameter and `BoundHandler.repo_name_map` assignment.
- **`scripts/massoh-dashboard` — `main()` (line ~1146)**:
  - Startup discovery kept for informational count message only; map no longer passed to handler.

### #21 (P3) — No broad pkill in test teardown

**Condition:** Zero `pkill`/`killall` broad-match against massoh-dashboard in
`test/run.sh`. All teardowns PID-scoped. Sentinel server survives suite.

- **`test/run.sh` — audit result**: `pkill` appeared only in two comment lines
  (lines 3888, 4615). No executable broad pkill was present. Verified with:
  `grep -nE 'pkill|killall' test/run.sh | grep -v '^[0-9]*:#'`
- All existing teardowns use `kill "$PID"` (PID-scoped).

---

## New Tests Added

| Test ID | Condition | What it proves |
|---------|-----------|----------------|
| T-FS-A3-1a | #20 | `/repo/alpha-repo` response body contains `href="/repo/alpha-repo/task/TASK-...` pattern |
| T-FS-A3-1b | #20 | Known task `TASK-open-1` id appears in the page |
| T-FS-A3-1c | #20 | Exact href `href="/repo/alpha-repo/task/TASK-open-1"` present |
| T-FS-A3-2  | #20 | GET on that href returns HTTP 200 (existing drill-down route reachable) |
| T-FS-A3-3a | #19 | Repo NOT reachable before being added to TSV (pre-condition) |
| T-FS-A3-3b | #19 | Repo added to TSV post-launch resolves 200 WITHOUT server restart |
| T-FS-A3-4  | #21 | Static grep: zero broad `pkill/killall massoh-dashboard` commands in test/run.sh |
| T-FS-A3-5a | #21 | Sentinel server on ephemeral port is up at start of A3 block |
| T-FS-A3-5b | #21 | Sentinel server still alive after full A3 block (no side-effect kill) |

---

## Proofs

### Href sample (T-FS-A3-1c + T-FS-A3-2 proof)

```
T-FS-A3-1c check: href="/repo/alpha-repo/task/TASK-open-1" present in /repo/alpha-repo
T-FS-A3-2 check: GET /repo/alpha-repo/task/TASK-open-1 → HTTP 200
```

Both passed. The task id appears in the response body as:
`<a href="/repo/alpha-repo/task/TASK-open-1">TASK-open-1</a>`

### Post-launch repo resolves (T-FS-A3-3 proof)

```
T-FS-A3-3a: /repo/a3_late_repo → 404 (server started with empty TSV)
T-FS-A3-3b: same URL → 200 after appending path to TSV, no restart
```

Both passed. Demonstrates per-request `_get_repo_name_map()` rebuild.

### No-broad-pkill guard (T-FS-A3-4 proof)

```
T-FS-A3-4: ! grep -nE 'pkill.*massoh-dashboard|killall.*massoh-dashboard' test/run.sh \
             | grep -vE '^\s*[0-9]+:\s*#|grep|check\s+"' | grep -q .
→ ok (zero matches after excluding comments and grep/check lines)
```

### 8787 sentinel survived

```
$ curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/
200
```

Confirmed before and after `bash test/run.sh`.

---

## Files Changed

| File | Change summary |
|------|----------------|
| `lib/verbs/fleet.sh` | `_fleet_render_task_list`: new `repo_name` param, href links; caller updated |
| `scripts/massoh-dashboard` | Per-request map via `_get_repo_name_map()`; removed startup map from class |
| `test/run.sh` | T-FS-A3-1..5 (9 checks) added at end of file |
| `AGENT_BACKLOG.md` | Intake inbox #19/#20/#21 Status → DONE (append-only edit) |
| `VERSION` | 0.26.0 → 0.27.0 |
| `CHANGELOG.md` | [0.27.0] section added |

**diff = 0 on:** `bin/massoh`, `manifest.yml`, `agent-project/NON_NEGOTIABLES.md`,
`templates/`, `policies/`, `agent-os/`

---

## Risks

- The per-request `_discover_repos()` call adds a small O(repos) cost on every
  request (TSV read or `find` scan). For typical fleet sizes (1–200 repos) this is
  negligible. If the fleet is very large, the existing startup-count message still
  provides a baseline; the per-request rebuild is the correct correctness trade-off
  per the license (#19 preferred approach).
- `_fleet_render_task_list` now requires `repo_name` to emit hrefs. If called without
  `repo_name` (e.g. from a future caller), it falls back to plain-text ids (defensive
  guard in place).

## Incomplete Items

None. All three bugs fixed per exact scope; no "while-I'm-here" changes made.

## Handoff for Reviewer

Assign `massoh-reviewer-qa`. Verify:

1. `git checkout feat/fleet-hardening && bash test/run.sh` → 685/685 green.
2. `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/` → 200 after run.
3. `/repo/<name>` page source: grep for `href="/repo/.*/task/TASK-` — at least one match per repo with tasks.
4. POST to any route still → 404 (GET-only preserved).
5. `git diff main -- bin/massoh manifest.yml` → empty.
6. AGENT_BACKLOG.md rows 19/20/21: Status cells show DONE.
7. VERSION = 0.27.0, CHANGELOG [0.27.0] present.
