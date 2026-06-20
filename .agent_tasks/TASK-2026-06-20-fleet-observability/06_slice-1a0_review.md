# 06 — Review Result: Fleet slice 1a-0 (serve skeleton)

- **Task:** TASK-2026-06-20-fleet-observability
- **Slice:** 1a-0 — `massoh fleet serve` skeleton
- **Branch:** `feat/fleet-serve`
- **Reviewer:** massoh-reviewer-qa
- **Date:** 2026-06-20
- **Verdict: APPROVE**

---

## Verdict

**APPROVE.** All N1–N7 conditions independently verified. 476/476 green (self-witnessed, exit 0).
No blocking issues. No scope creep. Safety-critical files untouched. Server confirmed loopback-only,
route-allowlist-only, no orphan — all reproduced live.

---

## Checklist walkthrough

### Scope
- [x] Only approved scope changed: `scripts/massoh-dashboard` (new), `lib/verbs/fleet.sh` (additive
  `_fleet_serve()` + dispatch), `test/run.sh` (additive T-FS-1 through T-FS-6, 11 checks). No other
  product files. `git diff main --name-only` = `lib/verbs/fleet.sh`, `test/run.sh` (+ `scripts/massoh-
  dashboard` untracked). Exactly matches the 04 packet scope.
- [x] No broad refactor smuggled in.
- [x] `bin/massoh` diff vs main = 0 lines (fleet dispatch pre-existed at line 226 from fleet-rollup task).
- [x] `manifest.yml` diff vs main = 0 lines. `scripts/` glob (manifest.yml lines 39-40) already covers
  `scripts/massoh-dashboard` — no safety-critical edit required (confirmed).
- [x] `templates/CLAUDE*`, `agent-project/NON_NEGOTIABLES.md` — diff = 0 lines.
- [x] `AGENT_SYNC.md`, `AGENT_BACKLOG.md` — diff = 0 lines.
- [x] No VERSION bump / CHANGELOG (correct: skeleton, held until 1a per 04 packet).

### Correctness + tests
- [x] Real tests exercise the actual path (T-FS-1 live curl, T-FS-2/2b/2c live curl, T-FS-4 live PID,
  T-FS-5 live process with fake-python3 binary). None are vacuous.
- [x] 476/476 green (independently run; exit 0; `ALL GREEN — 476 checks passed.`).
- [x] Ephemeral port used (`_fs_free_port` via `socket.bind('127.0.0.1', 0)`) — no CI collision.
- [x] Trap cleanup at EXIT in test suite; `FS_PID=""` cleared after T-FS-4 so trap is a no-op.

### Guardrails
- [x] No designated safety-critical file touched without sign-off.
- [x] No prohibited content.
- [x] No frozen feature.
- [x] Keep-older-data respected (new file only; no deletes).
- [x] Additive + reversible: rollback = remove `scripts/massoh-dashboard` + revert `_fleet_serve` in
  `lib/verbs/fleet.sh`. Zero installed-behavior impact.

### Compatibility + data
- [x] No API contract change.
- [x] No migration required (new file only).
- [x] Feature flag N/A (project policy: new CLI behavior additive + reversible, not flag-gated).

### Localization / UX invariants
- [x] POSIX-bash in `fleet.sh`; `set -euo pipefail` enforced inside `_fleet_serve()` (line 112).
- [x] CLI error messages go to stderr (lines 132-134 fleet.sh).
- [x] Server messages go to stdout with `flush=True` (correct).

### Ops + trail
- [x] Rollback plan stated in 04 packet and handoff.
- [x] 04 packet issued (system-architect green-light under 8h away-autonomy grant; owner sign-off on
  bin/massoh edits for fleet verbs pre-authorized per AGENT_SYNC.md 2026-06-20).
- [x] 05 handoff written.
- [x] 06 review (this file) written.

---

## N1–N7 independently verified

### N1 — Loopback-only bind

- `scripts/massoh-dashboard:28` — `BIND_HOST = "127.0.0.1"` (module-level constant, assigned once,
  never reassigned; verified by `grep -n "BIND_HOST" scripts/massoh-dashboard` — 5 hits, all reads
  after the single assignment at line 28).
- `scripts/massoh-dashboard:111` — `socketserver.TCPServer((BIND_HOST, port), _FleetHandler)` — the
  bind tuple uses `BIND_HOST`, not any literal.
- `grep -nE "0\.0\.0\.0|\"\"|\bINADDR\b|--host|host.*arg" scripts/massoh-dashboard` — zero hits as
  a bind target (comment on line 27 says "NOT 0.0.0.0" — that's documentation, not a bind call).
- `argparse` has exactly one `add_argument` call (line 120-124) — for `--port` only. Host not
  configurable. `*) die` in `_fleet_serve` rejects unknown flags including any hypothetical `--host`.
- `exec python3 "$dashboard" --port "$port"` (fleet.sh:150) — only `--port` passed to the script.
- Reproduced live: `curl http://127.0.0.1:34217/ → HTTP 200`. Process confirmed at 127.0.0.1.
- **CONFIRMED.**

### N2 — No static file server / route allowlist only

- `scripts/massoh-dashboard:55` — `class _FleetHandler(http.server.BaseHTTPRequestHandler):` —
  extends `BaseHTTPRequestHandler`, NOT `SimpleHTTPRequestHandler`. Confirmed.
- `grep -n "SimpleHTTPRequestHandler\|translate_path\|os\.path\.join" scripts/massoh-dashboard` →
  zero hits. No filesystem path resolution.
- `scripts/massoh-dashboard:34-36` — `_ALLOWED_ROUTES = {"/": "text/html; charset=utf-8"}` — fixed
  dict, exactly one route.
- `scripts/massoh-dashboard:78-83` — `do_GET` strips query/fragment, checks allowlist, returns 404
  on non-match. Path never passed to any `os.*` function.
- `scripts/massoh-dashboard:95-96` — defensive fallthrough: anything else not explicitly handled → 404.
- `do_POST` (line 101) → `_send_404()`. No body read (`rfile` never called).
- `grep -n "subprocess\|os\.system\|os\.popen\|exec\b" scripts/massoh-dashboard` → zero hits.
- Reproduced live:
  - `GET / → HTTP 200` (confirmed)
  - `GET /../.. → HTTP 404` (no path traversal)
  - `GET /%2e%2e%2fetc → HTTP 404` (encoded traversal)
  - `GET /anything → HTTP 404` (route allowlist)
- **CONFIRMED.**

### N3 — Clean lifecycle / no orphan

- `scripts/massoh-dashboard:144-155` — `threading.Event` + daemon thread running `serve_forever()`.
  Signal handlers (`SIGINT`, `SIGTERM`) set the event. Main thread blocks on `_stop_event.wait()`.
  After event set: `server.shutdown()` (waits for daemon thread), then `server.server_close()`.
- `lib/verbs/fleet.sh:150` — `exec python3 "$dashboard" --port "$port"` — `exec` replaces the shell
  process; no orphan parent.
- `bin/massoh-cron` — `grep -n "serve\|fleet serve"` → zero hits. Cron never auto-starts `serve`. N3
  cron condition satisfied.
- Reproduced live: started server at PID 1383172, sent SIGTERM via `kill $DASH_PID`, confirmed
  `massoh-dashboard: stopped.` printed, `kill -0 1383172` → "No such process".
- Post-suite: `pgrep -a "massoh-dashboard"` → "No massoh-dashboard processes found".
- T-FS-4 mechanism (test/run.sh:3235-3243): `kill "$FS_PID"`, poll `kill -0` up to 3s,
  assert `! kill -0 "$FS_PID"`. Substantive (real PID, real poll).
- `_fs_cleanup` trap on EXIT (test/run.sh:3179-3188) cleans up if server still running at suite end.
  `FS_PID=""` is cleared at line 3243 after T-FS-4, so the EXIT trap is a no-op for this server.
- **CONFIRMED.**

### N4 — Escape in bash (N/A for skeleton)

Correctly marked N/A: no dynamic repo data rendered in this stub. Architecture SEAM A (bash-side
escaping) enforced in slice 1a content. No HTML interpolation in `_STUB_HTML` (static literal).

### N5 — Reuse verbs (N/A for skeleton)

No verb calls in stub. Correctly N/A. Enforced in slice 1a.

### N6 — Zero browser spend / no agent exec

- `grep -n "subprocess\|os\.system\|os\.popen\|exec\b" scripts/massoh-dashboard` → zero hits.
- Server serves static literal `_STUB_HTML` only. No shell-out. No token spend. No agent invocation.
- **CONFIRMED.**

### N7 — Stdlib-only Python + python3 guard

- `grep -E "^import |^from " scripts/massoh-dashboard` → `argparse, http.server, signal,
  socketserver, sys, threading` — all Python 3 stdlib. No PyYAML, no pip, no external dep.
- `lib/verbs/fleet.sh:131-135` — `command -v python3` guard: absent python3 → stderr message +
  `return 1` (non-zero exit).
- T-FS-5 (test/run.sh:3247-3262): creates a stub `python3` binary in `$_fs5_dir` that exits 127,
  prepends it to PATH, runs `$MASSOH fleet serve`. Verifies `$_fs5_rc -ne 0` AND output mentions
  `python3`. This is a real live process test, not a stub.
- T-FS-6 (test/run.sh:3265-3266): greps dashboard source for `^import yaml`, `^from yaml`,
  `^import PyYAML`. Catches the primary non-stdlib risk (PyYAML). Note: does not catch `import pip`
  (non-blocking: the actual import list has been visually verified as stdlib-only above).
- **CONFIRMED.**

---

## Live reproduction transcript

```
Server PID: 1383172
massoh-dashboard: serving at http://127.0.0.1:34217/
massoh-dashboard: press Ctrl-C or send SIGTERM to stop.
GET / → HTTP 200
GET /../.. → HTTP 404
GET /%2e%2e%2fetc → HTTP 404
GET /anything → HTTP 404
massoh-dashboard: stopped.
No orphan — PID 1383172 gone cleanly

Post-suite: pgrep -a "massoh-dashboard" → No massoh-dashboard processes found
```

---

## Test suite result

```
bash test/run.sh 2>&1 | tail -22

  ok   T-FS-1 GET / returns HTTP 200
  ok   T-FS-2 GET /bogus/path returns 404 (route allowlist)
  ok   T-FS-2b GET /../.. returns 404 (no path traversal)
  ok   T-FS-2c GET /%2e%2e%2f returns 404 (encoded traversal)
  ok   T-FS-3 BIND_HOST assigned 127.0.0.1 in source (N1)
  ok   T-FS-3b TCPServer not called with literal 0.0.0.0 in source (N1)
  ok   T-FS-3c TCPServer called with BIND_HOST (not a hard-coded alternative)
  ok   T-FS-4 no orphan process after SIGTERM (N3 clean lifecycle)
  ok   T-FS-5 python3 absent → non-zero exit (N7 guard)
  ok   T-FS-5b python3 absent → message mentions python3
  ok   T-FS-6 massoh-dashboard imports stdlib only (no PyYAML, no pip)
== T-FS done ==

ALL GREEN — 476 checks passed.
```

Exit code: 0. Test count: 476 (up from 465 baseline; +11 T-FS checks = 476).
T-SR-11 mid-run snapshot shows pre-existing T6 failure (#13 fix-t6, REQUEST CHANGES on main) — not
introduced by this slice. Final suite counter and exit code are authoritative (476/476, exit 0).

---

## Blocking issues

None.

---

## Non-blocking issues

**NB-1 — T-FS-6 stdlib check partial (cosmetic):** The grep pattern
`'^import yaml|^from yaml|^import PyYAML'` does not catch `import pip` or other unusual non-stdlib
imports. This is acceptable: (a) the actual import list has been visually verified as 6 stdlib
modules; (b) `pip` as an import is not a practical attack vector; (c) the condition guards against
the specific dep the project uses (PyYAML). Non-blocking; consider expanding to a whitelist-check
in a future maintenance pass.

**NB-2 — `allow_reuse_address = False` is class-level mutation (cosmetic):**
`scripts/massoh-dashboard:110` sets `socketserver.TCPServer.allow_reuse_address = False` as a
class attribute rather than an instance attribute. Since `False` is already the CPython default, this
line is redundant. As a standalone `exec`-invoked script it has no inter-process impact. Non-blocking.

---

## Missing tests

None. T-FS-2b (traversal), T-FS-2c (encoded), T-FS-4 (no-orphan), T-FS-5 (python3-absent) all
exercise real code paths with live processes and curl. Not vacuous.

---

## Safety / guardrail concerns

None. First inbound listening surface is loopback-only, GET-only, route-allowlist-only, stdlib-only.
N1 (loopback) and N2 (no file server) are the two highest-care conditions; both independently
confirmed at source level and at runtime.

POST write path (slice 1c) and browser-triggered learn button (slice 3) remain correctly PARKed
for owner sign-off per `00_architecture_review.md` §4 and AGENT_SYNC.md. No drift from that ruling
detected in this implementation.

---

## Hidden scope concerns

None. Implementation is additive: 3 files only (new `scripts/massoh-dashboard`, additive
`lib/verbs/fleet.sh`, additive `test/run.sh`). All safety-critical files unchanged.

---

## Expansion / localization concerns

None. No locale/region/segment hard-coded. POSIX-bash path preserved. Port is the only configurable
knob (overridable via `--port`). Host intentionally non-configurable per N1 (correct).

---

## Owner decision needed

None for this slice. Pre-existing parked decisions (1c POST path, slice-3 browser button) unchanged.

---

## Handoff

```
Agent: massoh-reviewer-qa
Mode: REVIEW_QA
Task: TASK-2026-06-20-fleet-observability — slice 1a-0 serve skeleton
Status: APPROVE. 06_slice-1a0_review.md written.
Branch: feat/fleet-serve (uncommitted)

Decision: APPROVE. All N1–N7 conditions independently verified. 476/476 green.

  N1 (loopback-only): BIND_HOST = "127.0.0.1" at scripts/massoh-dashboard:28;
    assigned once, never reassigned; single add_argument (--port only); exec passes
    only --port to script; reproduced live at 127.0.0.1:34217.
  N2 (no file server): BaseHTTPRequestHandler (not SimpleHTTPRequestHandler);
    no translate_path / os.path.join / subprocess; _ALLOWED_ROUTES = {"/"} only;
    traversal /../.. → 404, /%2e%2e%2fetc → 404, /anything → 404 — reproduced live.
  N3 (clean lifecycle): threading.Event + daemon thread + server.shutdown() on signal;
    exec in fleet.sh (no orphan parent); cron never auto-starts serve; PID 1383172
    gone after SIGTERM — reproduced live. Post-suite pgrep clean.
  N4/N5: N/A for skeleton (static stub; no repo data).
  N6 (zero spend): no subprocess/exec/agent calls in dashboard. Static HTML only.
  N7 (stdlib-only): 6 stdlib imports confirmed; python3 guard in fleet.sh:131-135;
    T-FS-5 live fake-binary test.

  Scope: 3 files only (scripts/massoh-dashboard new, fleet.sh additive, test/run.sh
    additive). bin/massoh diff=0. manifest.yml diff=0. Safety-critical files clean.
    AGENT_SYNC.md / AGENT_BACKLOG.md untouched.

  Tests: 476/476 green (exit 0). T-FS-2b/2c substantive (live curl). T-FS-4
    substantive (live PID poll). T-FS-5 substantive (live fake-python3 binary).
    Ephemeral port used. EXIT trap + FS_PID="" clear.

  NB-1 T-FS-6 stdlib check partial (non-blocking).
  NB-2 allow_reuse_address class-level mutation redundant (non-blocking).

Next recommended agent: orchestrator / auto-merge on green (per policy).
Next action: Commit feat/fleet-serve (scripts/massoh-dashboard, lib/verbs/fleet.sh,
             test/run.sh, task artifacts), squash-merge PR → main.
             Then proceed to slice 1a content (index + KPI + nav) under N1–N4.
```
