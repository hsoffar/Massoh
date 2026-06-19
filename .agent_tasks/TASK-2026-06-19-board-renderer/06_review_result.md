# 06 — Review Result: `massoh board --local` renderer (v0.15.0)

- **Task ID:** TASK-2026-06-19-board-renderer
- **Agent:** massoh-reviewer-qa
- **Date:** 2026-06-19
- **Branch:** feat/board-renderer (working tree, uncommitted)
- **Verdict:** APPROVE

---

## Verdict

**APPROVE** — BR1–BR8 all independently verified. 389/389 checks green (self-witnessed twice).
XSS escaping proven at runtime and by code inspection. Clobber-guard proven at runtime.
`_board_push_plane` byte-identical. Scope clean (4 files only). T-BR-11 deviation assessed:
non-blocking (see §T-BR-11 assessment below).

---

## Checklist walkthrough

### Scope
- [x] Only approved scope changed. 4 files in working diff: `lib/verbs/board.sh`, `test/run.sh`,
  `VERSION`, `CHANGELOG.md`. `manifest.yml`, `templates/`, `agent-os/policies/`, `bin/massoh`,
  `AGENT_SYNC.md`, `AGENT_BACKLOG.md` — all untouched (confirmed: `git diff HEAD -- manifest.yml
  templates/ AGENT_SYNC.md AGENT_BACKLOG.md bin/massoh` returns empty).
- [x] No broad refactor. Change is additive: new helpers + new flag branch inside existing verb file.
- [x] No frozen feature.
- [x] No safety-critical file touched (manifest install/uninstall/block logic, global-block markers,
  templates, NON_NEGOTIABLES — all clean).

### Correctness + tests
- [x] 389/389 green — independently run twice. Verbatim: `ALL GREEN — 389 checks passed.`
- [x] T-BR-1 through T-BR-12 all green (28 individual sub-checks). T-BR-6 = T17–T23 regression
  suite, which all green. T17–T23 = 28 existing checks all green.
- [x] Tests are substantive (not stubs). T-BR-1 creates a real malicious task and reads actual
  board.html output. T-BR-7 computes md5sum before/after. T-BR-5 strips jq from PATH and runs live.

### BR1 — Reuse `_board_build_model` (no second scanner)

Verified. `grep -n "_board_build_model" lib/verbs/board.sh` returns 4 call sites (lines 74, 92,
101, 146) plus definition (line 194) plus comments. The ONLY `for d in "$repo"/.agent_tasks/TASK-*/`
for-loop is at line 209, inside `_board_build_model`. Lines 281 and 507 containing "TASK-*/" are
string literals in `say`/`printf` messages, not scanners. No second scanner exists. Spirit of BR1
fully met.

**T-BR-11 deviation assessment:** The packet said "exactly 2 call sites." The handoff correctly
identifies that the existing code already had 3 call sites before this feature (no-push, dry-run,
push-plane — confirmed by `git show HEAD:lib/verbs/board.sh | grep -c "_board_build_model"` = 3
real calls on current HEAD). The new `--local` branch adds a 4th call. The packet's "exactly 2"
premise was wrong — it was written before seeing that no-push and dry-run each also call
`_board_build_model`. T-BR-11 correctly pivots to testing the spirit: (a) `_board_build_model`
is called in the `--local` branch, and (b) no second TASK-\*/ scanner exists outside the function.
Both sub-checks are green and substantive. **Non-blocking. No actual duplicate scanner.**

### BR2 — HTML injection escaping (highest risk)

Verified by code inspection and runtime test.

`_board_html_escape` at `lib/verbs/board.sh:293–296`:
- Order: `&`→`&amp;` first (prevents double-escaping), then `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`.
- `|| true` on the sed pipeline (BR8 compatible).
- `${1:-}` default prevents unbound variable failure.

All 7 interpolated fields in `_board_emit_local` pass through `_board_html_escape` before `printf`
into the HTML string:
- `esc_stage` (line 394) — stage name in column header
- `esc_tid` (line 403) — task_id in card meta
- `esc_title` (line 404) — title in card title element
- `esc_desc` (line 405) — description in card meta
- `esc_agent` (line 406) — last_agent in card meta
- `esc_priority` (line 407) — priority in card meta
- `esc_cost` (line 408) — cost_tokens in card meta

No unescaped variable interpolation into HTML markup observed. `$ts` (timestamp) is `date -u`
output — ASCII-safe, no injection risk.

**XSS escape proof (independently reproduced):**
Input title: `<script>alert("xss")</script> & "quoted"`
- `grep -qF '<script>' board.html` → NOT FOUND (PASS)
- `grep -qF '&lt;script&gt;' board.html` → FOUND (PASS)
- `grep -qF '&amp;' board.html` → FOUND (PASS)
- `grep -qF '&quot;' board.html` → FOUND (PASS)

### BR3 — BOARD.md cell sanitization

Verified. `_board_safe_md_cell` at `lib/verbs/board.sh:300–304`:
- `tr '\n' ' '` strips newlines.
- `sed 's/|/\//g'` replaces pipes with `/`.
- `|| true` on each pipe stage.
Applied to `safe_id` (line 471) and `safe_title` (line 472) in `_board_emit_board_md`.
T-BR-4 green: title `foo | bar` → BOARD.md does not contain literal `foo | bar`.

### BR4 — jq isolation

Verified. `grep -n "jq" lib/verbs/board.sh` returns 17 lines; 0 are in `_board_emit_local` or
`_board_emit_board_md` (confirmed: awk-range extraction of both functions finds only a comment
line mentioning "no jq" — no actual `jq` invocation).

The jq guard moved to `lib/verbs/board.sh:109` — inside the `push_plane=1` path, AFTER the
`--local` early-return at line 78. The `--local` branch returns at line 78 before reaching line
109. T-BR-5 independently confirms: `PATH` with no `jq` → `--local` exits 0 and creates both
files. T21a regression (jq absent → `--push plane` exits 1) still green.

### BR5 — Clobber-guard / sentinel

Verified. `_board_write_safe` at `lib/verbs/board.sh:310–345`:
- HTML sentinel: `<!-- massoh-generated -->` (line 1 of board.html output).
- BOARD.md sentinel: `<!-- massoh:board-generated -->` (line 1 of BOARD.md output).
- File does not exist → create (line 343).
- File exists WITH sentinel → overwrite (line 332–333).
- File exists WITHOUT sentinel → refuse, `return 1`, stderr message (lines 336–340). Exit 1
  propagates under `set -euo pipefail` via the `_board_emit_local` call chain.
- `--out` path: `force=1`, always overwrites (line 323–327).

**Clobber-guard proof (independently reproduced):**
- Created `agent-project/board.html` with content `hand-authored content — no sentinel here`
- md5sum before: `12fac13a3d856d96f0fb6db67ff187b3`
- `massoh board --local` exit code: 1 (non-zero — PASS)
- md5sum after: `12fac13a3d856d96f0fb6db67ff187b3` (identical — PASS, file unchanged)

T-BR-10 confirms sentinel does not double on second run: `grep -c '<!-- massoh:board-generated -->'`
returns 1 after two sequential runs. Green.

### BR6 — `_board_push_plane` byte-identical

Verified. `awk '/^_board_push_plane\(\)/,0'` extraction from working tree vs `git show HEAD:...`
— diff returns clean: `BYTE-IDENTICAL: _board_push_plane unchanged`. T17–T23 all 28 checks green.

### BR7 — No network / no secret reads on `--local`

Verified. The `--local` branch at lines 73–79 calls `_board_build_model` + two emitters + `return 0`.
It returns before:
- `_board_ensure_gitignore` (line 83)
- `. "$repo/.env.massoh"` (line 86)
- `PLANE_API_TOKEN` read (lines 115–118)
- Any `curl` invocation (all in `_board_push_plane`)

T-BR-9 static grep confirms: `_board_emit_local` and `_board_emit_board_md` contain no `curl`
(awk range-check, not just grep — checks entire function bodies). Green.

### BR8 — `set -euo pipefail` + `|| true` discipline

Verified. No `set +e` / `set +u` in new code; inherits from `bin/massoh` sourcer.
- `_board_html_escape`: `|| true` on the sed pipeline (line 295).
- `_board_safe_md_cell`: `|| true` on the final sed (line 303).
- `_board_write_safe`: `grep -qF "$sentinel" "$target" 2>/dev/null` suppresses missing-file error
  (line 331); `mkdir -p` before every write (line 321).
- `_board_emit_local`: `mkdir -p` via `_board_write_safe`; no new grep/awk not already guarded.

---

## Blocking issues

None.

---

## Non-blocking issues

**NB-1 — T-BR-11 deviation (already assessed above — non-blocking).** The packet's "exactly 2 call
sites" premise was incorrect; pre-existing code had 3. The implementer's pivot to testing "no second
scanner" is the correct and sufficient verification of BR1's spirit. No action required.

**NB-2 — `$ts` in HTML body is unescaped (non-issue).** `date -u +%Y-%m-%dT%H:%M:%SZ` produces
ISO-8601 UTC output containing only `[0-9T:Z-]` — none of which require HTML escaping. Not a risk.

---

## Missing tests

None. All 12 T-BR-* checks are substantive. T-BR-6 = implicit (T17–T23 run as part of suite; arch-
safety doc states "no new check needed" for T-BR-6, which is correct). Count: 28 new sub-checks
across T-BR-1 through T-BR-12 (excluding T-BR-6 which is the existing regression suite).

---

## Safety / guardrail concerns

None. XSS escaping applied to every interpolated field. No outbound network on `--local` path.
No secret reads on `--local` path. Clobber-guard protects hand-authored files.

---

## Hidden scope concerns

None. `manifest.yml`, `templates/`, `bin/massoh`, `agent-os/policies/`, `NON_NEGOTIABLES.md`,
`AGENT_SYNC.md`, `AGENT_BACKLOG.md` — all untouched.

---

## Expansion / localization concerns

None. HTML escaping is locale-neutral (only `&<>"` transformed). UTF-8 titles/descriptions pass
through unchanged. `--out <dir>` makes output path configurable. No hard-coded locale or region.

---

## Checks run (self-witnessed)

```
bash test/run.sh (x2) -> ALL GREEN — 389 checks passed. PASS.
git diff HEAD -- manifest.yml templates/ AGENT_SYNC.md AGENT_BACKLOG.md bin/massoh -> empty. PASS.
grep -n "for d in.*TASK-\*/" lib/verbs/board.sh -> line 209 only (inside _board_build_model). PASS.
awk-range _board_emit_local | grep "jq" (non-comment) -> empty. PASS.
awk-range _board_emit_board_md | grep "jq" (non-comment) -> empty. PASS.
diff _board_push_plane (wt vs HEAD) -> BYTE-IDENTICAL. PASS.
XSS reproduction (manual T-BR-1): no raw <script>; &lt;script&gt;/&amp;/&quot; present. PASS.
Clobber reproduction (manual T-BR-7): exit 1, md5sum unchanged. PASS.
VERSION = 0.15.0. PASS.
CHANGELOG.md has [0.15.0] entry. PASS.
```

---

## Owner decision needed

None.

---

## Next recommended agent

Orchestrator: squash-merge `feat/board-renderer` to `main` per auto-merge-on-green policy
(batch-authorized, reviewer-qa APPROVED, 389/389 green). Update `AGENT_SYNC.md` on merge.
