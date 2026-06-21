# 05 — Implementation handoff: test parallel-safety (#17, P0)

**Branch:** `fix/test-parallel-safety`
**VERSION:** 0.27.1 (patch — test-infra only, no behavior change)
**Agent:** massoh-implementer
**Date:** 2026-06-21

---

## What was implemented

Two root causes of concurrent-run collision were fixed in `test/run.sh`:

### 1. Hard-coded ports (the license's stated root cause)

A shared `free_port()` helper was hoisted to the TOP of `test/run.sh`
(after `newcc()` at line ~17) before any test — it binds `:0` and reads
the OS-assigned port, ensuring each invocation returns a distinct port
even under concurrent execution.

`_fs_free_port()` (the existing T-FS helper at line ~3180) now delegates
to `free_port()` — DRY, no duplicate implementation.

All `199xx` hard-coded port assignments were replaced:

| Variable | Was | Now |
|---|---|---|
| `MOCK_PORT_UNREACHABLE_A` | literal `19998` (3 uses: T17b, T17c x2) | `$(free_port)` |
| `MOCK_PORT_UNREACHABLE_B` | literal `19999` (3 uses: T18a, T23a, T23b) | `$(free_port)` |
| `MOCK_PORT_18b` | `=19901` | `$(free_port)` |
| `MOCK_PORT_18c` | `=19902` | `$(free_port)` |
| `MOCK_PORT_18d` | `=19903` | `$(free_port)` |
| `MOCK_PORT_19a` | `=19904` | `$(free_port)` |
| `MOCK_PORT_20e` | `=19905` | `$(free_port)` |

All port variables are allocated in a single block (after the `mktask()`
helper, before T17a) so they are assigned once per run and reused correctly
across the tests that reference them.

### 2. T-FLN shared write target (parallel-collision #2)

`fleet learn --write-proposals` resolves its write path via
`git rev-parse --show-toplevel` of the current working directory. When
called from `$REPO_ROOT` (the previous behaviour), both concurrent runs
write to the SAME `agent-project/FLEET_LEARNINGS.proposed.md` file,
causing race-condition failures on T-FLN-1c/1d/1e/1f/6b/8a/8d (one run's
`rm -f` deleted the file just as the other run was checking it).

Fix: a per-run temp git repo `FLN_HOST_REPO="$TMP/fln_host"` is created
at the top of the T-FLN section. ALL `fleet learn` invocations in T-FLN
now run as `( cd "$FLN_HOST_REPO" && ... )`, so the write target becomes
`$TMP/fln_host/agent-project/FLEET_LEARNINGS.proposed.md` — fully
isolated to each run's `$TMP`. `FLEET_LEARN_FILE` is set once (to the new
path) before T-FLN-1. No product code was changed; only the test's cwd.

---

## Conditions file:line citations

| Condition | File | Lines |
|---|---|---|
| free_port() helper hoisted to top (before any test) | test/run.sh | ~19–32 (after newcc()) |
| `_fs_free_port()` delegates to free_port() (DRY) | test/run.sh | ~3180 (T-FS block) |
| Port block allocated before T17a | test/run.sh | ~1292–1300 (after mktask()) |
| T17b MOCK_PORT_UNREACHABLE_A replaces 19998 | test/run.sh | T17b PLANE_BASE_URL line |
| T17c x2 MOCK_PORT_UNREACHABLE_A replaces 19998 | test/run.sh | T17c 2 occurrences |
| T18a MOCK_PORT_UNREACHABLE_B replaces 19999 | test/run.sh | T18a PLANE_BASE_URL line |
| T18b MOCK_PORT_18b=... removed | test/run.sh | comment replaces assignment |
| T18c MOCK_PORT_18c=... removed | test/run.sh | comment replaces assignment |
| T18d MOCK_PORT_18d=... removed | test/run.sh | comment replaces assignment |
| T19a MOCK_PORT_19a=... removed | test/run.sh | comment replaces assignment |
| T20e MOCK_PORT_20e=... removed | test/run.sh | comment replaces assignment |
| T23a/T23b MOCK_PORT_UNREACHABLE_B replaces 19999 | test/run.sh | 2 occurrences |
| FLN_HOST_REPO created (T-FLN isolation) | test/run.sh | before T-FLN-1 |
| All fleet learn calls use cd "$FLN_HOST_REPO" | test/run.sh | T-FLN-1..8 |
| set -euo pipefail preserved | test/run.sh | line 5 |
| PID-scoped teardown (no broad pkill) | test/run.sh | all mock servers killed by MOCK_PID_* |

---

## Proof 1: Single run — ALL GREEN

```
ALL GREEN — 685 checks passed.
```

## Proof 2: Concurrent run — BOTH ALL GREEN / exit 0

```bash
bash test/run.sh & bash test/run.sh & wait
```

Run 1:
```
ALL GREEN — 685 checks passed.
```

Run 2:
```
ALL GREEN — 685 checks passed.
```

## Proof 3: grep — zero hard-coded 199xx ports

```bash
grep -nE ':199[0-9][0-9]|=199[0-9][0-9]' test/run.sh
# (no output — zero matches)
```

## Proof 4: Product code diff = 0

```bash
git diff main -- bin/massoh manifest.yml lib scripts agent-os policies templates
# (empty — exit 0)
```

## Proof 5: 8787 still 200

```bash
curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8787/
# 200
```

---

## Files changed

| File | Change |
|---|---|
| `test/run.sh` | free_port() helper; _fs_free_port() DRY; 7 port vars dynamic; FLN_HOST_REPO isolation; T-FLN cd wraps |
| `VERSION` | 0.27.0 → 0.27.1 |
| `CHANGELOG.md` | [0.27.1] entry added |
| `AGENT_BACKLOG.md` | inbox #17 Status → DONE (append-only, cell only) |
| `.agent_tasks/TASK-2026-06-21-control-plane/05_A4_handoff.md` | this file |

Product code diff = 0 (bin/massoh, manifest.yml, lib/, scripts/, agent-os/, policies/, templates/ — all unchanged).

---

## Risks

- **None (test-only).** Product behavior is unchanged. The fix cannot break any existing test since single-run is 685/685 green.
- T-FLN tests now write to `$TMP/fln_host/agent-project/` instead of `$REPO_ROOT/agent-project/` — this is strictly more correct (the file was never supposed to survive between test runs; the `rm -f` cleanup was always the intent).

## Incomplete items

None. All acceptance conditions from `04_A4-test-parallel-safety.md` are met.

## Handoff for reviewer

Route to `massoh-reviewer-qa`. The reviewer should independently verify:
1. `grep -nE ':199[0-9][0-9]|=199[0-9][0-9]' test/run.sh` → zero output.
2. `bash test/run.sh` → ALL GREEN 685.
3. `bash test/run.sh & bash test/run.sh & wait` → BOTH ALL GREEN 685.
4. `git diff main -- bin/massoh manifest.yml lib scripts agent-os policies templates` → empty.
5. `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8787/` → 200.
6. `free_port()` defined before any test section (after `newcc()`, line ~19).
7. `_fs_free_port()` delegates to `free_port()` (single-line body).
8. T-FLN fleet learn calls all use `( cd "$FLN_HOST_REPO" && ... )`.
9. AGENT_BACKLOG.md #17 Status cell = DONE (row intact, no deletions elsewhere).
10. VERSION = 0.27.1; CHANGELOG [0.27.1] present.
