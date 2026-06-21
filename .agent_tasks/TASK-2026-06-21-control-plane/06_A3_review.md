# 06 — Review Result: A3 Dashboard Hardening (v0.27.0)

**Verdict: APPROVE**
**Suite: 685/685 green (independently run)**
**Branch:** `feat/fleet-hardening` commit `96c8ff6`
**Reviewer:** massoh-reviewer-qa
**Date:** 2026-06-21

---

## Verdict Summary

All three bugs (#20/#19/#21) fixed correctly. No scope creep. No safety-critical file
touched. No-path-from-URL invariant structurally confirmed and live-reproduced after the
per-request refactor. 8787 live server survived the full suite. Suite 685/685 green
(self-run). APPROVE.

---

## Reproduced Proofs

### #20 (P1) — Clickable task links

Live reproduction on ephemeral port 37517 against the Massoh repo:

```
href pattern present:
href="/repo/Massoh/task/TASK-2026-06-16-massoh-autonomous-fleet"
href="/repo/Massoh/task/TASK-2026-06-16-massoh-cadence-verbs"
href="/repo/Massoh/task/TASK-2026-06-16-massoh-cli-verbs"

GET on one href:
HTTP 200 (/repo/Massoh/task/TASK-2026-06-16-massoh-autonomous-fleet)
```

ID escaped in BOTH href and anchor text (sample):
```
<a href="/repo/Massoh/task/TASK-2026-06-16-massoh-autonomous-fleet">TASK-2026-06-16-massoh-autonomous-fleet</a>
<a href="/repo/Massoh/task/TASK-2026-06-16-massoh-cadence-verbs">TASK-2026-06-16-massoh-cadence-verbs</a>
```

Condition met: `lib/verbs/fleet.sh` `_fleet_render_task_list` (line ~876) emits
`<a href="/repo/$url_name/task/$url_tid">$esc_tid</a>` where `url_tid` and `esc_tid`
are both derived from `_board_html_escape` / percent-encoding. Caller at `_fleet_render_repo`
(line ~383) passes `"$repo_name"`. No new route introduced.

T-FS-A3-1a, T-FS-A3-1b, T-FS-A3-1c, T-FS-A3-2: all green.

### #19 (P3) — Per-request rediscovery (AND security invariant)

Live reproduction on ephemeral port (fresh temp TSV, temp repo):

```
Before adding to TSV → 404   (pre-condition confirmed)
After adding to TSV (no restart) → 200  (#19 fix confirmed)
```

Implementation: `_get_repo_name_map()` (scripts/massoh-dashboard line 603) is an
instance method calling `_discover_repos()` + `_build_repo_name_map(repos)` on every
invocation. Called at the top of `do_GET()` (line 665) before any route check, and
independently in `do_POST()` (line 871) for B4 repo validation. The startup
`repo_name_map` class attribute was removed entirely from `_FleetHandler` and from
`_make_handler_class()`. All five former `self.repo_name_map` references replaced with
the per-request local variable.

**Critical: no-path-from-URL invariant STILL HOLDS after the refactor.**

Structural proof:
- `repo_name_map` is ALWAYS built server-side from `_discover_repos()` (trusted TSV/root).
- `repo_name` from URL (via `urllib.parse.unquote(m.group(1))`) is used ONLY for
  set-membership lookup: `if repo_name not in repo_name_map → _send_404()`.
- `repo_path = repo_name_map[repo_name]` — path comes from the server-side map, never
  from any URL byte.
- For task route (line 699): `task_id` passes BOTH regex `[A-Za-z0-9_.~\-]+` (no `/`)
  AND `_discover_tasks_for_repo` set-membership before `os.path.join(repo_path,
  ".agent_tasks", task_id)`.
- For file route (line 731): `file_id` is `[a-f0-9]{16}` by regex; `abs_path` is
  constructed from server-built `file_map[file_id]` rel-path; `_is_confined()` backstop
  applied before any read.

Live traversal proof on ephemeral port 50303:
```
..%2f..%2fetc%2fpasswd → 404  (regex rejects %)
../../etc/passwd → 404          (regex rejects /)
unknown-repo → 404
unknown-repo/task/TASK-foo → 404
known-repo/unknown-task → 404   (task not in _discover_tasks_for_repo set)
non-hex file id (NOTAHEX) → 404 (regex rejects)
POST /repo/Massoh → 404         (read-only preserved)
```

T-FS-A3-3a, T-FS-A3-3b: both green (independently run in suite).

### #21 (P3) — No broad pkill in teardown

Static grep — all pkill/killall occurrences in test/run.sh:

```
3888:  # a broad pkill. All ports are ephemeral ...          ← comment line, filtered
4615:  # Teardown: ONLY kill FB_PID (never a broad pkill...) ← comment line, filtered
4925:  # #21 (P3): ZERO broad pkill/killall ...               ← comment line, filtered
5054:  # This test statically asserts ...                      ← comment line, filtered
5062:  check "T-FS-A3-4 no broad pkill/killall ..."           ← check() string, filtered
5063:  "! grep -nE 'pkill...' ...                             ← contains 'grep', filtered
5090:  # Verify the sentinel is still up (nothing ... pkill)  ← comment, filtered
5092:  check "T-FS-A3-5b sentinel server ... broad pkill)"    ← check() string, filtered
```

Zero executable broad pkill/killall after filtering. All teardowns in test/run.sh
use `kill "$PID"` (PID-scoped). Confirmed independently:

```
grep -nE 'pkill.*massoh-dashboard|killall.*massoh-dashboard' test/run.sh \
  | grep -vE '^\s*[0-9]+:\s*#|grep|check\s+"'
→ (empty — zero matches)
```

Guard analysis: the T-FS-A3-4 filter `grep -vE '^\s*[0-9]+:\s*#|grep|check\s+"'` is
self-consistent. Line 5054 is a comment (filtered by `#`). Line 5062 begins with
`check` (filtered by `check\s+"`). Line 5063 is a continuation containing `grep`
(filtered by `grep`). No live pkill slips through.

Sentinel survived: started an ephemeral sentinel server, verified it was alive at
T-FS-A3-5a and still alive at T-FS-A3-5b. Plus the live 8787 server:

```
8787 before suite → 200
[bash test/run.sh → 685/685 green]
8787 after suite  → 200
8787 after reviewer's own ephemeral-port tests → 200
```

T-FS-A3-4, T-FS-A3-5a, T-FS-A3-5b: all green.

---

## Condition → File:Line Verification

| Condition | File:Line | Verified |
|---|---|---|
| #20 href links to existing route only | lib/verbs/fleet.sh ~876 | YES — `href="/repo/$url_name/task/$url_tid"`, existing `_TASK_VIEW_RE` route |
| #20 id escaped in href | lib/verbs/fleet.sh ~873 | YES — `url_tid=$(... sed ...)` same percent-encoding as index |
| #20 id escaped in text | lib/verbs/fleet.sh ~876 | YES — `$esc_tid` from `_board_html_escape` |
| #20 no new route | scripts/massoh-dashboard | YES — T-FS-A3-2 GETs pre-existing `_TASK_VIEW_RE` route |
| #19 per-request rebuild same source as index | scripts/massoh-dashboard line 603 | YES — `_discover_repos()` + `_build_repo_name_map()`, same functions as `_render_index()` |
| #19 no drift (index shows ↔ route resolves) | scripts/massoh-dashboard line 665 | YES — rebuilt at top of `do_GET()` before any route check |
| #19 no path-from-URL introduced | scripts/massoh-dashboard line 684, 715, 748, 766 | YES — set-membership only; repo_path from map |
| #21 zero pkill/killall broad-match executable | test/run.sh (all lines) | YES — grep confirms zero after filter |
| Read-only / GET-only preserved | scripts/massoh-dashboard lines 774+ | YES — `do_POST()` still 404 without --control; live reproduced |
| Loopback-only unchanged | scripts/massoh-dashboard BIND_HOST | YES — pre-existing, no change in diff |
| set -euo pipefail | lib/verbs/fleet.sh header | YES — pre-existing, fleet.sh inherits from sourcing bin/massoh |
| bin/massoh diff = 0 | git diff main...feat/fleet-hardening -- bin/massoh | YES — empty |
| manifest.yml diff = 0 | git diff main...feat/fleet-hardening -- manifest.yml | YES — empty |
| NON_NEGOTIABLES / templates / policies / agent-os diff = 0 | git diff | YES — empty |
| VERSION 0.27.0 | VERSION | YES — confirmed |
| CHANGELOG [0.27.0] | CHANGELOG.md | YES — present |
| AGENT_BACKLOG #19/#20/#21 DONE (Status cell only, rows not deleted) | AGENT_BACKLOG.md lines 100-102 | YES — rows present, Status cells edited, content unchanged |

---

## Scope Confirmation

Files changed vs. main:
```
.agent_tasks/TASK-2026-06-21-control-plane/05_A3_handoff.md  (task artifact)
AGENT_BACKLOG.md     (Status cells #19/#20/#21 → DONE; append-only, no rows deleted)
AGENT_SYNC.md        (task artifact update)
CHANGELOG.md         ([0.27.0] section added)
VERSION              (0.26.0 → 0.27.0)
lib/verbs/fleet.sh   (+27 lines: _fleet_render_task_list href fix + caller update)
scripts/massoh-dashboard  (+78/-38 lines: per-request map refactor only)
test/run.sh          (+190 lines: T-FS-A3-1..5 tests)
```

diff = 0 confirmed on: `bin/massoh`, `manifest.yml`, `agent-project/NON_NEGOTIABLES.md`,
`templates/`, `agent-os/`, `policies/`. No scope creep detected.

---

## Suite Count

685/685 checks passed — self-run (`bash test/run.sh` in repo root on branch
`feat/fleet-hardening`). Exit code 0. T-FS-A3-1a/1b/1c/2/3a/3b/4/5a/5b all green
(9 new checks; 685 − 676 = 9 net new).

---

## Checklist (05_REVIEW_CHECKLIST.md)

- [x] Only approved scope changed — 8 files, all within A3 bounds
- [x] No broad refactor smuggled
- [x] Real tests exercise actual HTTP paths (live-HTTP style, ephemeral ports)
- [x] Suite green — 685/685 independently run, exit 0
- [x] No designated safety-critical file touched without sign-off
- [x] No prohibited content
- [x] No frozen feature implemented
- [x] Keep-older-data respected (AGENT_BACKLOG rows intact, Status cell only)
- [x] API contract unchanged (all existing routes preserved; no new route)
- [x] Backward-compatible (per-request map is strictly additive fix)
- [x] No feature flag needed (bug fix, not new behavior)
- [x] POSIX-bash, set -euo pipefail in fleet.sh
- [x] VERSION bumped (0.26.0 → 0.27.0)
- [x] AGENT_SYNC.md updated
- [x] Task packet 05_A3_handoff.md present

---

## Blocking Issues

None.

---

## Non-Blocking Issues

NB-1: `_render_repo()` (scripts/massoh-dashboard line ~966) calls
`self._get_repo_name_map()` a third time (for the sibling nav list), independently of
the `repo_name_map` local variable already built in `do_GET()`. This is correct (same
source, same result) but performs 3 calls per `/repo/<name>` GET instead of 1. At
typical fleet sizes (1-200 repos) this is negligible as noted in the handoff. Non-blocking.

NB-2: T-FS-A3-4 static guard uses `check\s+"` to filter check() string arguments, but
relies on `grep` keyword to filter the continuation of the multi-line check string (line
5063). If a future executor `pkill massoh-dashboard` were wrapped in something other than
`check "...` or a grep/comment context, the guard might miss it. The guard is correct
for the current file state and is the same pattern used elsewhere. Non-blocking for this
review.

---

## Safety / Guardrail Concerns

None — the per-request `_get_repo_name_map()` refactor does NOT weaken the no-path-from-URL
invariant. All five former `self.repo_name_map` lookups are now `repo_name_map` local-variable
lookups; the semantics are identical (server-side set-membership, path from the map, never
from the URL). Traversal attacks structurally blocked at two layers: regex (`[A-Za-z0-9_.~\-]+`
rejects `/`, `%`, `..`) and set-membership (name/id must be in server-discovered sets).

---

## Hidden Scope Concerns

None. Diff is clean. Only `lib/verbs/fleet.sh`, `scripts/massoh-dashboard`, `test/run.sh`,
plus version/changelog/backlog/sync artifacts. No "while I'm here" changes observed.

---

## Expansion / Localization Concerns

None. Fixes are route-logic and test changes only. No locale/region hard-coding.

---

## Owner Decision Needed

None.

---

## Next Action

Auto-merge-on-green applies (owner 2026-06-19 policy). Ready to squash-merge
`feat/fleet-hardening` → main, VERSION 0.27.0.
