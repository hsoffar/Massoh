# 05 — Implementation Handoff: Fleet slice 1a-0 (serve skeleton)

- **Task:** TASK-2026-06-20-fleet-observability
- **Slice:** 1a-0 — `massoh fleet serve` skeleton
- **Branch:** `feat/fleet-serve`
- **Agent:** massoh-implementer
- **Date:** 2026-06-20
- **Status:** COMPLETE — 476/476 suite green; ready for massoh-reviewer-qa.

---

## Files changed

| File | Change |
|---|---|
| `scripts/massoh-dashboard` | NEW — Python stdlib-only dashboard server (N1/N2/N3/N7) |
| `lib/verbs/fleet.sh` | ADDITIVE — `_fleet_serve()` + `serve` dispatch in `cmd_fleet()` |
| `test/run.sh` | ADDITIVE — T-FS-1 through T-FS-6 (11 checks) |

Safety-critical files (`bin/massoh`, `manifest.yml`, `templates/CLAUDE.*`, `NON_NEGOTIABLES.md`) are **unchanged**. The `fleet serve` dispatch rides the existing `fleet)` case at `bin/massoh:226` — no new line added.

---

## N1–N7 compliance (file:line)

| Condition | Status | Evidence |
|---|---|---|
| **N1** loopback-only bind | PASS | `scripts/massoh-dashboard:26` — `BIND_HOST = "127.0.0.1"` (literal); `scripts/massoh-dashboard:110` — `socketserver.TCPServer((BIND_HOST, port), ...)`. Host is NOT configurable. |
| **N2** route allowlist / no file server | PASS | `scripts/massoh-dashboard:34-36` — `_ALLOWED_ROUTES = {"/": ...}` (fixed allowlist); `_FleetHandler.do_GET` strips query/fragment then checks allowlist only; path never passed to `os.path.join()` or filesystem. |
| **N3** clean lifecycle | PASS | `scripts/massoh-dashboard:118-145` — daemon thread runs `serve_forever()`; main thread blocks on `threading.Event`; `SIGTERM/SIGINT` sets event; main thread calls `server.shutdown()` then `server.server_close()`. No lingering process (T-FS-4). |
| **N4** escape in bash (future slices) | N/A (skeleton) | No dynamic repo data rendered yet. Architecture SEAM A applies to slice 1a content. |
| **N5** reuse verbs (future slices) | N/A (skeleton) | No verb calls in this stub. |
| **N6** zero browser spend / no agent exec | PASS | Server serves static HTML only; no subprocess; no token spend; no agent exec. |
| **N7** stdlib-only Python | PASS | `scripts/massoh-dashboard` imports: `argparse, http.server, signal, socketserver, sys, threading` — all stdlib. No PyYAML, no pip. Guarded in `lib/verbs/fleet.sh:_fleet_serve()` (`command -v python3` check). |

---

## Start → curl → 404 → stop transcript

```
=== START ===
massoh-dashboard: serving at http://127.0.0.1:38585/
massoh-dashboard: press Ctrl-C or send SIGTERM to stop.

=== GET / (expect 200) ===
HTTP 200

=== GET /bogus (expect 404) ===
HTTP 404

=== GET /../.. (expect 404, no traversal) ===
HTTP 404

=== STOP ===
massoh-dashboard: stopped.
Process exited cleanly at iteration 6
No orphan - clean lifecycle (N3 confirmed)
```

---

## No-orphan proof

T-FS-4 in the test suite:
1. Server started as background process, PID captured.
2. `kill $PID` (SIGTERM) sent.
3. Loop: `kill -0 $PID` every 0.1s for up to 3s — exited at iteration 6 (~0.5s).
4. Final assert: `! kill -0 $PID` → PASS.

Post-suite: `ps aux | grep "massoh-dashboard"` → clean (no processes).

---

## Test suite output

```
bash test/run.sh 2>&1 | tail -14

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

---

## Risks

- None new for this skeleton. The listening socket is loopback-only, GET-only, static stub. N1+N3 proven by test.
- Future slices (1a content, 1b) must continue the N2 index-not-path discipline and N4 escape-in-bash discipline before adding any repo data.

---

## Incomplete items (by design — scope of this slice)

- No repo content / KPIs / board rendered (slice 1a content).
- No VERSION bump (skeleton; will bump to 0.20.0 when 1a is user-useful per packet).
- No CHANGELOG entry (held until 1a per packet).
- N4 (HTML escape in bash) and N5 (reuse verbs) are N/A for this stub; enforced in slice 1a.

---

## Handoff to massoh-reviewer-qa

**Review focus:**
1. Confirm `scripts/massoh-dashboard` uses `BIND_HOST = "127.0.0.1"` (literal, hard-coded) at line 26 and never 0.0.0.0 as a bind target (N1).
2. Confirm `_FleetHandler` has no `SimpleHTTPRequestHandler` inheritance and no `translate_path()` call (N2).
3. Confirm threading lifecycle: `serve_forever()` on daemon thread + `threading.Event` wake-up + `server.shutdown()` on signal (N3).
4. Confirm `fleet.sh` `_fleet_serve()` has `command -v python3` guard before exec (N7).
5. Run `bash test/run.sh` → expect `ALL GREEN — 476 checks passed`.
6. Confirm `bin/massoh`, `manifest.yml`, safety-critical files unchanged (git diff main shows only: `scripts/massoh-dashboard` new, `lib/verbs/fleet.sh` additive, `test/run.sh` additive + handoff file).
7. Confirm no server process running after test suite.

**Auto-merge condition:** all T-FS-* green, suite green, no orphan, no safety-critical file changed.
