# 06 — Review result: Fleet slice 1c — start-task panel (read-only)

- **Reviewer:** massoh-reviewer-qa
- **Branch:** feat/fleet-starttask
- **Date:** 2026-06-20
- **Verdict:** APPROVE

---

## Summary

All mandatory conditions from `04_slice-1c-starttask.md` independently verified. The POST-park
holds with zero write path in the server. Panel renders correct escaped content. Read-only
byte-snapshot holds. Suite 544/544 green (self-witnessed). Scope clean.

---

## Checklist walkthrough

### Scope
- [x] Only approved scope changed: 4 files only (lib/verbs/fleet.sh +46 lines, test/run.sh +117
  lines, VERSION, CHANGELOG). `scripts/massoh-dashboard` UNTOUCHED. `bin/massoh` UNTOUCHED
  (git diff HEAD -- bin/massoh: empty). `manifest.yml` UNTOUCHED. `AGENT_SYNC.md` has the
  expected additive rolling update (prior 1b APPROVE row added to decision log; last-handoff
  block updated to 1b; no deletions from decision log). `AGENT_BACKLOG.md` not in working tree
  changes.
- [x] No broad refactor smuggled in.

### Correctness + tests
- [x] Suite green: `bash test/run.sh` exits 0 — ALL GREEN — 544 checks passed (self-witnessed,
  run completely).
- [x] T-FS-25 through T-FS-29 are substantive — not stubs. Each exercises a live server with two
  fake repos (reusing FS_FLEET_ROOT/FS_REPO_A from prior fleet tests), real curl requests, and
  real filesystem snapshots. Detail:
    - T-FS-25a/b/c/d/e: curl GET /repo/alpha-repo body; grep for panel heading, commands,
      interactive command, abs-path. Live server. Non-vacuous.
    - T-FS-26a/b: grep for 'owner-gated|parked' and 'sign-off'. Live response. Non-vacuous.
    - T-FS-27a: source grep `_board_html_escape` in fleet.sh. Non-vacuous (confirmed present
      at lines 408-409 of fleet.sh).
    - T-FS-27b: grep -F '<script>alert' absent. Non-vacuous (live response checked).
    - T-FS-27c: grep for `&amp;&amp;` in live response. Non-vacuous.
    - T-FS-28a/b/c: curl -X POST / → HTTP 404; /repo/alpha-repo → 404; /intake → 404.
      Live POST requests, independently reproduced (see live verification below).
    - T-FS-28d: grep do_POST source for _send_404. Source check on actual file.
    - T-FS-29a: md5sum snapshot before/after 3 renders; identical. Real filesystem. Non-vacuous.
    - T-FS-29b: kill server; wait; assert kill -0 fails. Non-vacuous.

### Guardrails
- [x] No safety-critical file touched (bin/massoh, manifest.yml, templates/, NON_NEGOTIABLES.md,
  global-block markers) — git diff HEAD confirms zero changes on all of these.
- [x] No project-prohibited content.
- [x] No frozen feature implemented.
- [x] Data/append-only: no hard-delete; no overwrite; panel is display-only.

### Compatibility + data
- [x] Additive only. `_fleet_render_repo` gains one call at line 392 to the new function.
  Existing render paths unchanged.
- [x] No migration needed. No new file I/O.

### Localization / UX invariants
- [x] POSIX bash `printf` only, no non-portable deps.
- [x] No locale/region hardcoding.

### Ops + trail
- [x] VERSION: 0.22.0. CHANGELOG: `[0.22.0] - 2026-06-20` entry present with accurate description.
- [x] AGENT_SYNC.md: additive update present (1b APPROVE row added, last-handoff updated). No
  rows deleted. Append-only invariant holds.

---

## Critical finding: POST-park holds (highest-priority condition)

Independently reproduced live (free port 54977, 2 fake git repos):

- POST / → HTTP 404 (CONFIRMED)
- POST /repo/alpha-repo → HTTP 404 (CONFIRMED)
- POST /intake → HTTP 404 (CONFIRMED)

Server has exactly 3 HTTP method handlers (`do_GET`, `do_HEAD`, `do_POST`) — all at
`scripts/massoh-dashboard` lines 288, 352, 355. `do_POST` (line 355) is a single-statement
function: `self._send_404()`. No write path, no subprocess call, no intake invocation. The
file was NOT changed in this slice at all (git diff HEAD confirms zero changes to
scripts/massoh-dashboard). This is the strongest possible guarantee: the post park was already
in place and this slice adds nothing to the server.

Source grep confirming no new write/exec/intake in server:
- `grep -n "def do_POST\|def do_PUT\|def do_DELETE\|def do_PATCH\|intake\|write\|open(" scripts/massoh-dashboard`
  → only `open(tsv, "r")` (read-only TSV file open), `wfile.write(body)` (HTTP response stream),
  and `def do_POST` → `_send_404`. No subprocess call from any HTTP handler other than
  `_render_index/_render_repo/_render_task` which shell read-only bash verb functions via
  `["bash", "-c", script]` for GET rendering only.

---

## Panel render verification

Live render of GET /repo/alpha-repo (two fake repos at temporary path):

- "Start a task" heading: PRESENT
- `massoh intake` command: PRESENT
- `massoh work` command: PRESENT
- `/start-task` interactive command: PRESENT
- Abs-path in cd command: PRESENT
- `&amp;&amp;` (HTML-escaped shell `&&`): PRESENT (no raw `&&` in panel)
- No raw `<script>alert`: CONFIRMED ABSENT
- "owner-gated" / "parked" note: PRESENT
- "sign-off" language: PRESENT

---

## Escape verification (N4)

`_fleet_render_start_task_panel` (lib/verbs/fleet.sh lines 403-442):
- Line 408: `esc_path="$(_board_html_escape "$repo")"` — abs path escaped
- Line 409: `esc_name="$(_board_html_escape "$repo_name")"` — repo name escaped
- Both `$esc_path` and `$esc_name` used exclusively in all printf interpolations within the function
- `&&` rendered as literal `&amp;&amp;` (static string, not from user input)
- `"` rendered as `&quot;`, `<` as `&lt;`, `>` as `&gt;` (static strings in the template)
- No JS added: static HTML only; no innerHTML, no eval, no fetch anywhere in the function or
  in the massoh-dashboard server (confirmed by grep).

---

## Read-only verification (FL1 / byte-snapshot)

Live: REPO_A md5sum identical before/after 3 renders (GET /repo/alpha-repo, /repo/beta-repo, /).
Live: REPO_B md5sum identical before/after same renders.
T-FS-29a confirms same in the automated suite.

---

## Loopback + lifecycle (N1, N3)

- BIND_HOST = "127.0.0.1" at scripts/massoh-dashboard line 44 (unchanged; not configurable).
- Server stopped cleanly on SIGTERM (live verification: "massoh-dashboard: stopped." printed;
  PID no longer responsive to kill -0). T-FS-29b passes.
- No orphan process after live verification or after full test suite.

---

## Blocking issues

None.

---

## Non-blocking issues

NB-1: Handoff claims "AGENT_SYNC.md — untouched" but it is in the working-tree diff. The change
is the expected additive rolling update (1b APPROVE row added to decision log, last-handoff block
updated to 1b). Decision-log rows are append-only (no deletions). This is correct behavior;
the claim in the handoff is inaccurate but the code is correct. Non-blocking.

NB-2: T-FS-27a is a source-grep test (`grep -q '_board_html_escape' fleet.sh`) rather than a
live escape test with a name containing `<script>`. The live XSS test (T-FS-27b) covers the
absence of raw `<script>` in the response but the fixture (alpha-repo) has no special chars in
its name. For future hardening: add a repo with `<script>` in the name and assert it renders
as `&lt;script&gt;` in the panel specifically. Non-blocking for this slice since the static
`esc_name` variable is used throughout and the function is simple enough for code-inspection
confidence.

NB-3: `shutil` unused import in scripts/massoh-dashboard (pre-existing from slice 1a, noted in
prior review NB-1). Non-blocking.

---

## Missing tests

None blocking. See NB-2 for a future hardening suggestion.

---

## Safety/guardrail concerns

None. POST park is the primary safety invariant and is rock-solid (server file not modified;
do_POST → _send_404 is the only handler for POST).

---

## Hidden scope concerns

None. The diff is exactly the 4 files declared in the handoff. scripts/massoh-dashboard is
genuinely untouched (the pre-existing do_POST → _send_404 already covers the park). The
handoff's claim "no new route, no new Python code, no new file I/O" is verified.

---

## Expansion/localization concerns

None applicable. Panel content is static CLI command strings; no locale/region hardcoding.

---

## Owner decision needed

None for this slice. The POST/write path (live one-click submit) remains correctly PARKED per
architecture review §4 R3. That PARK is visible in the panel's muted note and in the do_POST
source. Owner sign-off remains required before that path is built.

---

## Conditions verified (from 04_slice-1c-starttask.md)

| Condition | Verified | Evidence |
|---|---|---|
| NO POST handler / no server-side write / no exec | YES | scripts/massoh-dashboard line 355-357: do_POST → _send_404; file unmodified; live POST → 404 x3 |
| HTML-escape repo name + abs path via _board_html_escape | YES | fleet.sh lines 408-409; live &amp;&amp; present; no raw <script>alert |
| No innerHTML / no eval / no fetch / no JS | YES | No JS added; static HTML only; grep clean |
| Loopback-only; GET-only; read-only | YES | BIND_HOST=127.0.0.1 (line 44); do_POST→404; byte-snapshot identical |
| set -euo pipefail | YES | _run_bash_renderer sets it as first line of inline bash script (massoh-dashboard line 195) before sourcing fleet.sh |
| Panel contains massoh intake / massoh work / parked note | YES | T-FS-25a/b/c/d/e, T-FS-26a/b all green; live confirmed |
| POST to any route → 404 | YES | T-FS-28a/b/c/d all green; live independently reproduced |
| Byte-snapshot unchanged | YES | T-FS-29a green; live REPO_A + REPO_B identical |
| No orphan server | YES | T-FS-29b green; live clean stop confirmed |
| VERSION 0.22.0 + CHANGELOG | YES | VERSION file = "0.22.0"; CHANGELOG line 14 [0.22.0] |
| bin/massoh + manifest untouched | YES | git diff HEAD -- bin/massoh: empty; git diff HEAD -- manifest.yml: empty |

---

## Test result

```
bash test/run.sh
ALL GREEN — 544 checks passed.
```

Self-witnessed, exit 0. Count matches handoff claim (544). Previous count after slice 1b was
528; 16 new assertions added across T-FS-25..29 (5 test groups, 16 check() calls).

---

## Verdict: APPROVE

All mandatory conditions verified. POST-park holds with zero write path (strongest possible
guarantee: server file unmodified). Panel renders and is correctly escaped. Read-only invariant
holds. Suite 544/544 green. Scope clean. Safety-critical files untouched. 1c POST/write path
correctly PARKED for owner.

Ready to merge feat/fleet-starttask → main, VERSION 0.22.0.
