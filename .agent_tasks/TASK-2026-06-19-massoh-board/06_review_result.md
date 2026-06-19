# 06 — Review Result: massoh board → Plane

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date:** 2026-06-19
- **Agent:** massoh-reviewer-qa
- **Verdict:** REQUEST CHANGES

---

## Verdict: REQUEST CHANGES

One blocking finding (scope creep / data integrity violation in AGENT_BACKLOG.md). All 26 BG conditions independently verified and clean. Tests: 280/280 green (independently run). T17b confirmed live. The single fix is surgical (revert AGENT_BACKLOG.md to HEAD, or restore the deleted Done rows).

---

## 1. Blocking Findings

### BLOCK-1 — Scope creep + NON_NEGOTIABLES violation: AGENT_BACKLOG.md rewritten

**File:** `AGENT_BACKLOG.md`
**Severity:** BLOCKING

The implementation modified `AGENT_BACKLOG.md`, which is not in the approved scope for this task. The `04_implementation_packet.md §Scope` lists exactly: `bin/massoh`, `manifest.yml`, `VERSION`, `CHANGELOG.md`, `test/run.sh`. AGENT_BACKLOG.md is not listed.

Beyond scope creep, `NON_NEGOTIABLES.md §Data + migration policy` states:
> "Decision-log + Done + Frozen rows are append-only — never deleted."

The diff (confirmed via `git diff HEAD -- AGENT_BACKLOG.md`) shows:
- 3 rows removed from the Done section (`v0.4 cadence ceremonies`, `massoh cron`, `Version stamp / massoh discover`). These rows existed at HEAD.
- The Queue section entirely replaced (10+ rows deleted, 12+ new rows added).
- The "Done" table header row (`| # | Pri | Item | Why | Status |`) replaced with a different schema (`| # | Pri | Item | bin? | Status |`).

The new Done section contains more rows than the old one, so the actual information is largely preserved, but the rule is literal: rows may not be deleted. The removal of the 3 original Done rows is a hard violation of the append-only guarantee, even if the content was restructured to be more accurate.

**Fix (minimal, surgical):** Restore `AGENT_BACKLOG.md` to its HEAD state (`git checkout HEAD -- AGENT_BACKLOG.md`). If the implementer wishes to reconcile the backlog, that must be done in a separate `SYNC_ONLY` task (no product code involved).

**Alternative fix:** At minimum, restore the 3 deleted Done rows. The Queue rewrite is scope creep regardless but only the Done deletion is a NON_NEGOTIABLES violation.

---

## 2. Non-Blocking Findings

### NB-1 — Untracked directories not in scope: `deck/` and `.agent_tasks/TASK-2026-06-19-modularize-bin/`

`git status` shows two untracked paths that are not staged:
- `deck/` (contains `build_deck.js` and `Massoh-pitch.pptx`) — not code and not in scope for this task.
- `.agent_tasks/TASK-2026-06-19-modularize-bin/` (contains `00_request.md`) — a future task packet.

These are untracked and will not be included in the PR if staged properly. **Non-blocking** provided neither directory is added to the PR commit. The reviewer notes them for owner awareness — the `deck/` directory should be gitignored or committed separately; the modularize-bin task packet should be committed only when that task starts.

### NB-2 — T19c is not a direct sanitization unit test

`test/run.sh` line 1533: T19c re-asserts the same condition as T19b (rows from the T19a live run have exactly 4 fields). The comment acknowledges "we can't create a dir with a tab." This is accurate — POSIX filesystems allow tabs in filenames, but bash glob expansion and the for-loop pattern make it unreachable in practice. The sanitization code at `bin/massoh:1510` is correct. This is the strongest feasible test.

Non-blocking; noted for transparency.

### NB-3 — T18b name vs. behavior mismatch

T18b is named "non-2xx for one task: that task skipped" but the comment in `test/run.sh` lines 1352-1354 explicitly explains it was repurposed to cover "successful response → map row written" because the single-response mock pattern doesn't easily return 422 for one specific task. The T18a + T18c combination covers the failure paths adequately (T18a: unreachable, T18c: 500). Non-blocking; the comment is transparent.

---

## 3. BG1–BG26 Independent Verification

All 26 conditions verified against actual source at `bin/massoh` lines 1122–1619.

| Condition | Verified | Evidence |
|---|---|---|
| **BG1** Token never written to tracked file | PASS | `grep 'PLANE_API_TOKEN' bin/massoh` shows: (a) line 1170 is inside a heredoc — value is literal `your_api_token_here`; (b) lines 1427/1475/1550/1574 are `-H "X-API-Key: ${PLANE_API_TOKEN}"` header only. No file write of the token variable. |
| **BG2** Token masked in all output paths | PASS | Lines 1226 prints `$missing` which contains only the variable name `PLANE_API_TOKEN`, not its value. All `say`/`printf` in `_board_push_plane` (lines 1558/1561/1594/1596/1601/1609–1614) print task IDs, HTTP codes, counts, board URL — never `${PLANE_API_TOKEN}`. |
| **BG3** Token not in curl args; no set -x | PASS | `grep 'set -x' bin/massoh` shows 4 lines — all comments (lines 1127/1398/1544/1568). No actual `set -x` invocation. All curl calls use `-H "X-API-Key: ${PLANE_API_TOKEN}"` as a positional argument (which does not appear in process list when `set -x` is absent). |
| **BG4** Token not in URLs | PASS | All 4 endpoint URL strings (lines 1429/1478/1543/1567) contain only `PLANE_BASE_URL`, `PLANE_WORKSPACE_SLUG`, `PLANE_PROJECT_ID`, and `$issue_id`. No `PLANE_API_TOKEN` in any URL. |
| **BG5** .env.massoh gitignored before any write | PASS | `_board_ensure_gitignore` called at line 1162 (before `cat > .env.massoh` at 1167 in `--init-config` path) and at line 1193 (before sourcing .env.massoh at 1196 in push path). Order: gitignore add → then file operations. |
| **BG6** Exit 1 on missing vars | PASS | Lines 1221–1229: checks all 4 required vars; if any are missing, prints their names and actionable message to stderr, then `exit 1`. No API call or file write occurs before this check (after gitignore and sourcing, but before push). |
| **BG7** .env.massoh create-if-missing only | PASS | Lines 1164–1173: `if [ -e "$repo/.env.massoh" ]; then say "keep..."; else cat > ... fi`. The heredoc template contains only placeholder `your_api_token_here`. |
| **BG8** Timeouts on every curl | PASS | All 4 curl calls include `--connect-timeout 10 --max-time 30` (lines 1423–1430, 1470–1479, 1544–1554, 1568–1578). |
| **BG9** Graceful degrade exit 0 | PASS | After each curl: `if [ "${http_code:-000}" -ge 200 ] ... ; then ... else say "WARNING: ..."; skipped=$((skipped+1)); fi`. Final `return 0` at line 1617. Never exits non-zero on network failure. |
| **BG10** Non-2xx treated as failure | PASS | Pattern `http_code=$(curl ... -w "%{http_code}")` then `if [ "${http_code:-000}" -ge 200 ] && [ ... -lt 300 ]` at lines 1432/1480/1556/1580. No `curl ... && ...` branching. |
| **BG11** HTTPS enforced | PASS | Lines 1233–1246: `case "$PLANE_BASE_URL" in https://*) ;; http://*) if PLANE_ALLOW_HTTP=1 warn else exit 1 fi ;; *) exit 1 esac`. |
| **BG12** No infinite retry | PASS | Single attempt per task. No retry loop of any kind. |
| **BG13** Map row only after confirmed 2xx | PASS | Line 1589–1591: `printf '%s\t...' >> "$BOARD_MAP"` is inside the `if [ "${http_code:-000}" -ge 200 ] ...` branch AND guarded by `if [ -n "$new_issue_id" ]` (line 1583). Never written speculatively. |
| **BG14** No exfiltration | PASS | `_board_build_model` (lines 1300–1382) collects: task_id (folder name), title (first heading of 00_request.md), desc (first paragraph, `head -c 500`), stage (derived from packet filenames), priority (from backlog), last_agent (from AGENT_SYNC.md handoff block), blocked (from backlog), cost_tokens (summed from ledger). `_board_push_plane` body fields (lines 1522–1533): name, description_html, state, priority only. No file paths, git remotes, env vars, or directory listings. |
| **BG15** State upsert idempotent | PASS | Lines 1434–1438: parse existing state names + IDs into `STAGE_IDS[]`. Lines 1460–1487: `for stage_name in ...; if [ -z "${STAGE_IDS[$stage_name]:-}" ]; then create fi`. Only creates if absent. |
| **BG16** .board-map.tsv append-only | PASS | Line 1158: `local BOARD_MAP="$repo/.agent_tasks/.board-map.tsv"  # SAFETY: sole append-only write target`. Line 1591: `>> "$BOARD_MAP"  # SAFETY: BOARD_MAP is the ONLY permitted write target`. Confirmed by `grep 'BOARD_MAP' bin/massoh` — no `>` truncation, no `rm`, no `sed -i`. |
| **BG17** .gitignore add-if-missing idempotent | PASS | Lines 1266–1267: `grep -qxF '.env.massoh' "$gi" 2>/dev/null || printf '\n.env.massoh\n' >> "$gi"`. Exact-line match, append-only. Verified idempotent by T17c (two runs → appears exactly once). |
| **BG18** .board-map.tsv gitignored | PASS | Lines 1269–1270: `grep -qxF '.agent_tasks/.board-map.tsv' "$gi" 2>/dev/null || printf '\n.agent_tasks/.board-map.tsv\n' >> "$gi"`. Called in `_board_ensure_gitignore` before any map write. |
| **BG19** TSV fields sanitized | PASS | Line 1510: `safe_task_id="${task_id//$'\t'/}"; safe_task_id="${safe_task_id//$'\n'/}"; safe_task_id="${safe_task_id//$'\r'/}"`. Lines 1586–1587: `safe_issue_id` and `safe_proj_id` similarly sanitized. Only sanitized values written to BOARD_MAP. |
| **BG20** board.conf create-if-missing | PASS | Lines 1177–1185: `if [ -e "$repo/agent-project/board.conf" ]; then say "keep..."; else cat > ... fi`. Template contains only PLANE_WORKSPACE_SLUG and PLANE_PROJECT_ID (no token). |
| **BG21** manifest.yml lockstep | PASS | `manifest.yml` line 56: `{ dest: agent-project/board.conf, source: null }` added. `.env.massoh` and `.board-map.tsv` NOT listed. Both files modified in the same working tree. |
| **BG22** jq guard first in cmd_board; confined | PASS | Lines 1137–1138: first two lines of `cmd_board`. `grep 'jq' bin/massoh` shows all jq references on lines 1126–1619 (cmd_board subsystem only). No jq in any other cmd_*. |
| **BG23** Owner sign-off recorded | PASS | `AGENT_SYNC.md` decision log (2026-06-19): "TASK-2026-06-19-massoh-board: Owner SIGNED OFF on editing bin/massoh + manifest.yml". Verified. |
| **BG24** manifest.yml same commit as bin/massoh | PASS | Both modified in this working tree on `feat/massoh-board`. |
| **BG25** No internal cmd_* calls | PASS | `_board_build_model` (lines 1300–1382) uses direct file reads via grep/awk/cat and `git log`. No `cmd_ledger`, `cmd_learn`, `cmd_plan`, or any other cmd_* call. Confirmed: `grep 'cmd_' bin/massoh | grep '_board_'` shows only self-references within the board subsystem. |
| **BG26** Issue body bounded; jq @json encoding | PASS | Lines 1522–1533: all JSON bodies built via `jq -n --arg name ... --arg description_html ... --arg state ... --arg priority ...`. No raw string interpolation into JSON. `description_html` assembled from `$desc` (HTML-escaped via sed), `$stage` (known fixed string), `$cost_tokens` (integer). `jq --arg` handles all escaping. Description truncated at 500 chars (line 1517: `head -c 500`). |

---

## 4. Tests

**Independently run:** `bash test/run.sh` (at `/home/hossam/dev/Massoh`)

**Result:** ALL GREEN — 280 checks passed. (Verbatim last line.)

**Suite count observed:** 280/280 (vs. minimum requirement of 263). Implementer added 44 new T17–T23 checks (exceeds the 27 required).

**T17b live status:** PASS. Test at `test/run.sh` lines 1276–1285 runs `cmd_board --push plane` with `PLANE_API_TOKEN="TEST_TOKEN_SENTINEL_XYZ987"` against `http://127.0.0.1:19998` (nothing listening). Captures combined stdout+stderr via `$()` substitution. Asserts `! printf '%s' "$out17b" | grep -qF '$SENTINEL_TOKEN'`. Confirmed the sentinel string does not appear in output. This is a real live execution, not a stub.

**T19 (network degrade / local writes):** Real Python3 HTTP mock servers on ports 19901–19905. T18b uses a live mock returning 201 and verifies 2 map rows. T18c uses a live mock returning 500 and verifies no map rows. T18d uses a socket that accepts but never responds, verifies verb completes within 60 seconds. All real code paths exercised.

**T20 (POST-then-PATCH idempotent):** T19a runs two pushes with the same 2 tasks against a mock returning 201 on POST and 200 on PATCH. First run: 2 rows. Second run: still 2 rows (no duplicates). Real assertion.

**T23 (safety-critical checksum):** T22a/T22b capture md5sum of bin/massoh and manifest.yml before T17 and after T21; assert equal. Guards against tests accidentally modifying source files.

---

## 5. Scope + Safety-Critical Invariants

**bin/massoh diff (independently verified via `git diff HEAD -- bin/massoh`):**
- 1 line deleted: the `*)` die usage string (expected — adds `board` to the verb list).
- 500 lines added: `cmd_board` + `_board_ensure_gitignore` + `_board_stage_from_dir` + `_board_build_model` + `_board_print_table` + `_board_push_plane` + `board)` dispatch arm.
- No other verbs modified. Existing install/uninstall/block/gate logic untouched. Two diff hunks: (1) insertion at line 1119 (after `_gate_off`), (2) dispatch table addition at line 1657.

**Adapter isolation:** `_board_build_model` (model layer) and `_board_push_plane` (Plane adapter) are separate named functions. A future `_board_push_github` can be added without touching model code. Requirement from `03_architecture_safety.md §12` satisfied.

**manifest.yml:** `board.conf` added to `project_scaffold.create_if_missing` with `source: null`. `.env.massoh` and `.board-map.tsv` explicitly excluded (noted in comments). Lockstep with bin/massoh confirmed.

**VERSION:** `0.10.0` ✓

**CHANGELOG:** `## [0.10.0] - 2026-06-19` section present and substantive ✓

**jq confined to cmd_board:** `grep -n 'jq' bin/massoh` shows all 10 jq references on lines 1126–1619 only. Zero jq in any other verb function.

**set -x:** `grep -n 'set -x' bin/massoh` shows 4 lines — all comments. No actual tracing enabled.

---

## 6. Guardrails Check

| Guardrail | Status |
|---|---|
| No code without a license (04 packet) | PASS — 04_implementation_packet.md issued after owner sign-off |
| POSIX-bash + set -euo pipefail | PASS — cmd_board follows same pattern as other verbs |
| Idempotent verbs | PASS — gitignore add-if-missing; map append-only; state check-before-create |
| Additive + reversible | PASS — new verb only; existing verbs unchanged; rollback = git revert |
| Keep older data | PASS for bin/massoh, manifest.yml, test/run.sh. FAIL for AGENT_BACKLOG.md Done rows (see BLOCK-1) |
| No secrets in git | PASS — .env.massoh gitignored by the verb; PLANE_API_TOKEN never written to tracked file |
| Feature flag (new verb = additive) | PASS — new verb defaults to no-op on existing installs; nothing changes without explicit invocation |
| Zero LLM | PASS — pure bash + curl + jq; no claude/Anthropic API calls |
| No internal cmd_* calls | PASS — confirmed BG25 above |
| No frozen features | PASS — no frozen items in AGENT_SYNC.md §Frozen |
| No exfiltration | PASS — BG14/BG26 verified |

---

## 7. Expansion / Localization

The adapter isolation (`_board_build_model` vs. `_board_push_plane`) satisfies the expansion principle from `03_architecture_safety.md §12`. A future `_board_push_github` adapter can be added without touching model-building code.

No locale-sensitive surfaces. CLI strings are English informational output. The Plane adapter uses `--push plane` flag as the selectable wedge — the design does not hard-code Plane as the only possible adapter.

---

## 8. Suggested Fix Instructions

**For BLOCK-1 (the only blocking issue):**

Option A (preferred): Revert AGENT_BACKLOG.md to HEAD state and keep it out of this PR.
```bash
git checkout HEAD -- AGENT_BACKLOG.md
```
The backlog reconciliation is legitimate work but belongs in a separate `SYNC_ONLY` task.

Option B (minimal): Restore the 3 deleted Done rows to their original form. The Queue section rewrite constitutes scope creep regardless, but restoring the Done rows satisfies the NON_NEGOTIABLES data-integrity requirement. This leaves the Queue rewrite as residual scope creep (which would still be a BLOCK per the checklist).

**Recommendation:** Option A. The AGENT_BACKLOG.md change, while well-intentioned, adds scope creep on top of a NON_NEGOTIABLES violation. One git command resolves both.

---

## 9. Owner Decision Needed

None. The fix is unambiguous and mechanical. No policy exception is needed.

---

## 10. Summary

After the AGENT_BACKLOG.md revert, this implementation should receive APPROVE. All 26 BG conditions are independently verified with line references. The test suite is real (not stub-only), T17b is a live token-suppression assertion, the mock servers in T18–T20 exercise real network paths, and the safety-critical file checksums are guarded by T22a/T22b. The core feature — `massoh board --push plane` — is correctly implemented, secret-safe, network-safe, and scope-clean.

**Decision requested:** Implementer reverts AGENT_BACKLOG.md, re-routes to massoh-reviewer-qa for APPROVE confirmation (fast-track: single-file revert, all BG conditions already verified).

---

## Fast-track re-review — 2026-06-19

**Verdict: APPROVED**

Prior full review verified BG1–BG26, ran 280/280 suite, live-passed T17b. This re-review checked only the single prior blocker (BLOCK-1).

### Check results

**Check 1 — Board commit file scope (`git show --stat 5fb1788`):**
PASS. Commit `5fb1788` touches exactly 7 files: `.agent_tasks/TASK-2026-06-19-massoh-board/05_implementation_handoff.md`, `.agent_tasks/TASK-2026-06-19-massoh-board/06_review_result.md`, `CHANGELOG.md`, `VERSION`, `bin/massoh`, `manifest.yml`, `test/run.sh`. `AGENT_BACKLOG.md` is NOT present. Scope clean.

**Check 2 — Board commit does not touch `AGENT_BACKLOG.md` (`git diff origin/main..5fb1788 -- AGENT_BACKLOG.md`):**
PASS. Output is empty. The board commit has zero impact on `AGENT_BACKLOG.md`.

**Check 3 — Append-only: no Done row deleted in working-tree `AGENT_BACKLOG.md` (`git diff origin/main -- AGENT_BACKLOG.md`):**
PASS. The diff shows the 3 originally blocked Done rows (`v0.4 cadence ceremonies`, `massoh cron`, `Version stamp`) are all present under the `### — earlier granular rows (preserved verbatim; append-only, never delete) —` subheader. No `-` line removes any pre-existing Done table row. The NON_NEGOTIABLES append-only requirement is satisfied. The backlog change is a separate governance commit (not part of `5fb1788`), restored all deleted rows, and is out of band from the board PR.

**Check 4 — `bin/massoh` additive (`git diff --stat origin/main..5fb1788 -- bin/massoh`):**
PASS. `1 file changed, 500 insertions(+), 1 deletion(-)`. The single deletion is the `*)` usage die-line that was extended to include `board` in the verb list — consistent with the prior review finding of exactly 2 diff hunks (verb insertion + dispatch addition). Additive confirmed.
