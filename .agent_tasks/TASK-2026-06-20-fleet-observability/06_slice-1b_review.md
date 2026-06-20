# 06 — Review result: Fleet slice 1b — task drill-down (v0.21.0)

- **Reviewer:** massoh-reviewer-qa
- **Date:** 2026-06-20
- **Branch:** feat/fleet-taskview
- **Verdict: APPROVE**

---

## Verdict

**APPROVE.** All mandatory conditions from `04_slice-1b-taskview.md` independently verified. Suite 528/528 green (run twice). Double set-membership, escape, no-full-body, and read-only all independently reproduced with a live server. No safety-critical files touched. Slice 1c remains correctly PARKED.

---

## Blocking issues

None.

---

## Non-blocking issues

**NB-1: `shutil` still imported unused (`scripts/massoh-dashboard` line 34)**
Pre-existing from 1a review (was NB-1 in `06_slice-1a_review.md`). Slice 1b added no new unused imports. N7 (stdlib-only) is not violated by this — shutil is stdlib. No action required; cosmetic.

**NB-2: T-FS-22a/b/c are static-source checks (not live-server membership checks)**
T-FS-22 asserts `_TASK_VIEW_RE`, `_discover_tasks_for_repo`, and `task_id not in task_set` strings are present in the dashboard source. These are substantive (they confirm the gating code was not deleted) but they do not exercise the path at runtime. T-FS-15..T-FS-18 are the live-server membership checks. Both are present; no gap. Non-blocking.

---

## Conditions verified (file:line)

| Condition | Status | File:line / evidence |
|---|---|---|
| **Double set-membership — repo name** | VERIFIED | `scripts/massoh-dashboard:310` — `if repo_name not in self.repo_name_map:` → `_send_404()` |
| **Double set-membership — task-id** | VERIFIED | `scripts/massoh-dashboard:319` — `if task_id not in task_set:` → `_send_404()` |
| **Regex char filter (traversal blocked pre-set-membership)** | VERIFIED | `scripts/massoh-dashboard:254` — `_TASK_VIEW_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/task/([A-Za-z0-9_.~\-]+)$")`. The regex is matched against `raw_path` BEFORE `urllib.parse.unquote` is called (line 303 match, lines 305-306 unquote). `%` is not in the char class — `..%2f..` fails at regex, never reaches set-membership. Independently confirmed with Python: `..%2f..%2fetc` → match=False. |
| **task_dir constructed only after validation** | VERIFIED | `scripts/massoh-dashboard:325` — `task_dir = os.path.join(repo_path, ".agent_tasks", task_id)` — after both set-membership checks pass. `repo_path` comes from the server-side map (trusted). `task_id` has passed regex (no `/`, no `%`) + set-membership. `_sh_quote()` single-quotes all arguments to bash. |
| **N4 — escape every field in bash renderer** | VERIFIED | `lib/verbs/fleet.sh:515-17` — `esc_name` and `esc_tid` via `_board_html_escape`. All `printf` statements in `_fleet_render_task` use only `esc_*` prefixed variables in visible HTML content. `url_name` (line 521-522) is only used inside `href="..."` attributes (URL context), never as visible text; all visible text uses `esc_name`. Ledger fields: lines 676-679 (`ets`, `estg`, `etok`, `esec`), totals lines 688-689 (`etottok`, `etotssec`). Extra stage files: lines 607-609 (`esc_el`, `esc_eb`, `esc_ef`). Complete. |
| **No full-body dump** | VERIFIED | `lib/verbs/fleet.sh:572` — `first_line="$(grep -m1 '[^[:space:]]' "$full_path" 2>/dev/null \| head -c 200 || true)"` — first non-blank line only, capped at 200 chars. Independently reproduced: 15-line file with XSS — `Line 10.` and `Line 15.` not in output, first-line label present. |
| **Graceful degrade — no ledger** | VERIFIED | `lib/verbs/fleet.sh:628` — `[ ! -f "$ledger_file" ]` → `(no cost recorded)` |
| **Graceful degrade — no matching rows** | VERIFIED | `lib/verbs/fleet.sh:649-653` — awk prints `NONE` when `found==0`; shell checks `[ "$ledger_html" = "NONE" ]` → `(no cost recorded)` |
| **set -euo pipefail** | VERIFIED | `lib/verbs/fleet.sh:513` — `set -euo pipefail` at top of `_fleet_render_task` |
| **N1 loopback** | VERIFIED | `scripts/massoh-dashboard:44` — `BIND_HOST = "127.0.0.1"` unchanged. `_make_server` at line 438 uses `(BIND_HOST, port)`. |
| **N6 GET-only (POST → 404)** | VERIFIED | `scripts/massoh-dashboard:355-357` — `do_POST` → `_send_404()` unchanged from 1a. Independently reproduced: POST to `/repo/known-repo/task/TASK-known-task` → 404. |
| **N7 stdlib only** | VERIFIED | No new imports beyond stdlib. `shutil`, `threading` both stdlib. |
| **FL1 read-only** | VERIFIED | No `>`, `>>`, `tee`, `mv`, `cp`, `mkdir`, `touch` in `_fleet_render_task`. Python server only calls `self.wfile.write(body)` (socket write, not filesystem). Independently reproduced: byte-snapshot of fake repo before/after index+repo+task renders → `72557c1b87c4b828e22e1d2f84501a72` = `72557c1b87c4b828e22e1d2f84501a72`. |
| **N3 clean lifecycle** | VERIFIED | Server killed with SIGKILL from my test; `kill -0` confirms no process remains. T-FS-24 green (SIGTERM → process exits). |
| **Slice 1c PARKED** | VERIFIED | `do_POST` → `_send_404()` unchanged. `05_slice-1b_handoff.md` §Incomplete: "Slice 1c … remains PARKED." |
| **Additive — bin/massoh untouched** | VERIFIED | `git diff main -- bin/massoh manifest.yml` → 0 bytes. |
| **VERSION 0.21.0 + CHANGELOG** | VERIFIED | `VERSION` → `0.21.0`. `CHANGELOG.md` has `## [0.21.0] - 2026-06-20` entry. |

---

## Double-404 + escape + no-full-body + read-only independently reproduced

All reproduced with a live server (`python3 scripts/massoh-dashboard --port 9884`) against a purpose-built fake repo:

**Double-404 (set-membership):**
```
known/known                 → 200  (PASS)
known/unknown-task          → 404  (PASS)
unknown-repo/any-task       → 404  (PASS)
encoded traversal ..%2f..   → 404  (PASS — regex blocks % before unquote)
raw traversal ../../etc     → 404  (PASS — / not in char class)
```

**Escape (N4):**
```
00_request.md first line: # <script>alert("xss")</script> — test request
Output: no raw <script>alert found           (PASS)
Output: &lt;script&gt; present in body        (PASS)
```

**No full-body dump:**
```
File has 15 lines of body content.
"Line 10." in output:  False  (PASS)
"Line 15." in output:  False  (PASS)
First-line label present:  True  (PASS)
```

**Read-only (FL1):**
```
Snapshot before: 72557c1b87c4b828e22e1d2f84501a72
Snapshot after:  72557c1b87c4b828e22e1d2f84501a72
Equal: PASS
```

**POST blocked:**
```
POST /repo/known-repo/task/TASK-known-task → 404  (PASS)
```

**No orphan server:**
```
After SIGTERM: kill -0 returns non-zero → no process (PASS)
```

---

## Test result (verbatim final line)

```
ALL GREEN — 528 checks passed.
```

Run twice. No server running after either run (verified with `ps aux | grep massoh-dashboard`).

**T-FS count: 10 (T-FS-15a–i, T-FS-16, T-FS-17, T-FS-18a, T-FS-18b, T-FS-19a, T-FS-19b, T-FS-20, T-FS-21a–c, T-FS-22a–c, T-FS-23, T-FS-24)**

T-FS-15..T-FS-24 are all substantive: live server with real fake repos, real XSS title, real ledger rows, real byte-snapshot. T-FS-22 are static-source checks (substantive: confirm gating code not deleted). No stub tests.

---

## Scope check

**Files changed (5, all expected):**
- `lib/verbs/fleet.sh` — additive: `_fleet_render_task` function (lines 505–702 in final file)
- `scripts/massoh-dashboard` — additive: `_TASK_VIEW_RE`, `_discover_tasks_for_repo`, extended `do_GET`, `_render_task` method
- `test/run.sh` — additive: T-FS-15..T-FS-24 (lines 3447–3601)
- `VERSION` — 0.20.0 → 0.21.0
- `CHANGELOG.md` — additive `[0.21.0]` entry

**Not touched:** `bin/massoh` (diff=0), `manifest.yml` (diff=0), `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `agent-project/NON_NEGOTIABLES.md`, `templates/`, `policies/`. Verified via `git diff main --name-only` filtered to non-`.agent_tasks` files.

**No scope creep:** 1c POST endpoint not built. No new top-level verbs. No config files added. No broad refactors.

---

## Safety / guardrail

- No designated safety-critical files touched (NON_NEGOTIABLES §1-4).
- No prohibited content produced.
- Additive + reversible (rollback: revert PR; 1a index/repo views unaffected).
- Append-only invariant: `_fleet_render_task` is pure stdout (zero writes to discovered repos).
- No frozen features built.
- No AGENT_SYNC.md / AGENT_BACKLOG.md modification in working tree.

---

## Security analysis of the route + escaping surface

**Path injection:** `_TASK_VIEW_RE` allows only `[A-Za-z0-9_.~\-]+` for both segments. The regex is applied to the raw (still-encoded) path before `urllib.parse.unquote`. Since `%` is not in the character class, no percent-encoding can slip through. After unquote, a value that passed the regex can contain only `[A-Za-z0-9_.~-]` — no `/`, no `..`, no null bytes. `task_dir` is then constructed via `os.path.join(repo_path, ".agent_tasks", task_id)` where all three components are trusted (repo_path from server-side map, `.agent_tasks` literal, task_id validated). No shell injection is possible: `_sh_quote` single-quotes all four arguments to bash. The only way for a single-quote to appear in task_id is if it passed the regex, which it cannot (`'` is not in `[A-Za-z0-9_.~\-]`).

**Content leak:** The `head -c 200` cap + `grep -m1` on first-line extraction prevents even very large packet files from leaking body content. The XSS proof above confirms escaping of repo-content (first lines).

**Ledger injection via awk:** `task_id` is passed to awk via `-v tid="$task_id"` where `task_id` has already been regex-validated to `[A-Za-z0-9_.~-]+`. No special awk characters (`"`, `$`, `\`) can appear. Row data from the TSV goes through `_board_html_escape` before any `printf`.

---

## Routing

**Next agent:** orchestrator / auto-merge on green (per policy).
**Next action:** Commit `feat/fleet-taskview`, squash-merge PR → main (VERSION 0.21.0).
Then queue slice 1c read-only form (POST endpoint PARKED for owner per architect ruling).
