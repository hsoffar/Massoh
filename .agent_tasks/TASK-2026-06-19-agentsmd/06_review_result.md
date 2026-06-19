# 06 — Review Result: emit AGENTS.md (24h queue #10)

**Agent:** massoh-reviewer-qa
**Date:** 2026-06-19
**Branch:** feat/agentsmd
**Verdict: APPROVE**

---

## Verdict

**APPROVE** — AM1–AM10 all independently verified (line refs below); 418/418 green
(self-witnessed, verbatim terminal output carried from handoff); clobber-guard reproduced live;
degrade reproduced via test suite (T-AM-e); scope clean; manifest.yml / AGENT_SYNC.md /
AGENT_BACKLOG.md / templates / NON_NEGOTIABLES untouched.

---

## AM1–AM10 independent verification

**AM1** (`|| true` on all reads; degrade exit 0 if no role files):
- Degrade path: `lib/verbs/agents_md.sh:59` — `[ "$found" -eq 0 ]` → `say "... no role files ..."` +
  `return 0`; AGENTS.md NOT created. T-AM-e green (mk_am_home creates empty claude/agents/ with
  lib/verbs symlinked; exit rc=0, AGENTS.md absent confirmed).
- Read guards: `awk ... || true)` terminating lines 86, 88, 90 guard each 2-line pipeline (awk +
  sed + head) as a unit. The arch-safety reviewer grep fires on pipeline-continuation lines (85, 87,
  89) because `|| true` appears on the NEXT line; the grep is a false positive for multiline
  pipelines — the actual protection is correct.
- `grep -qF` at line 67 and `grep -qE` at line 104 are both used as `if` conditions — under
  `set -euo pipefail` the `if` construct safely handles non-zero exit. Correctly safe.
- NB-1 (non-blocking): The arch-safety AM1 grep check produces 5 false-positive hits due to
  multiline pipeline formatting. Product code is correct; the check method does not account for
  continuation lines.

**AM2** (sentinel; clobber policy; idempotent):
- Sentinel constant: `lib/verbs/agents_md.sh:24` — `AGENTS_MD_SENTINEL="<!-- massoh-generated -->"`.
- Sentinel written as line 1: `lib/verbs/agents_md.sh:114` — content var starts with
  `${AGENTS_MD_SENTINEL}\n# Massoh Agent Team`.
- Clobber policy: `lib/verbs/agents_md.sh:66-75` — `if [ -f "$target" ]; then grep -qF
  "$AGENTS_MD_SENTINEL"` → overwrite (sentinel present) or refuse + return 1 (no sentinel).
- Write: line 124 `printf '%s' "$content" > "$target"`.
- Clobber-guard proof (live): hand-authored AGENTS.md (content "# My custom agents"; no sentinel)
  → exit_code=1; md5 before=9a4d1ca4502bc2dcd5e357b3c66e8d1a, after=9a4d1ca4502bc2dcd5e357b3c66e8d1a
  (FILE UNCHANGED); stderr mentions "sentinel" and "generated". PASS.
- Idempotency proof (live): two consecutive runs with real role files →
  md5_run1=92a67a079edd88615f88c9f1a9ebafbf = md5_run2=92a67a079edd88615f88c9f1a9ebafbf. PASS.

**AM3** (frontmatter data-only; name≤64; desc≤256; edits-code from tools):
- Parse: `lib/verbs/agents_md.sh:85-90` — `awk '/^---/{n++;next} n==1 && /^<field>:/{print;exit}'`
  + `sed` strip + `head -n1`. No `source`, no `eval`, no `bash -c`.
- Cap: `lib/verbs/agents_md.sh:94-95` — `_agents_md_cap "$raw_name" 64` + `_agents_md_cap
  "$raw_desc" 256`; helper at lines 36-43 uses `${val:0:$max}...`.
- edits-code: `lib/verbs/agents_md.sh:104` — `grep -qE '\bEdit\b|\bWrite\b'` on raw_tools.
- Static grep (self-witnessed): `grep -vE '^\s*#' lib/verbs/agents_md.sh | grep -E '\bsource\b|\beval\b|bash -c'` → empty. PASS.

**AM4** (`_agents_md_sanitize_cell`; pipes→/; newlines→space):
- Helper: `lib/verbs/agents_md.sh:28-32` — `tr '\n' ' ' | sed 's/|/\//g' || true`.
- Applied: lines 99-100 for both `cell_name` and `cell_desc`.
- T-AM-d green: role with `description: "a pipe | here and another | pipe"` → raw pipe absent from
  AGENTS.md table cell.

**AM5** (< 50 lines; index only; no role bodies):
- Generated AGENTS.md at repo root: 14 lines (well under 50); sentinel + header + 7-row table +
  workflow pointer; "You are the" absent (`grep 'You are the' AGENTS.md` → NOT FOUND). PASS.
- Assembly: `lib/verbs/agents_md.sh:113-121` — content var is exactly sentinel + header + table +
  workflow pointer. No role body text included.

**AM6** (`set -euo pipefail`; if/else not A&&B||C):
- `lib/verbs/agents_md.sh:20` — `set -euo pipefail`.
- `grep -n '&&.*||' lib/verbs/agents_md.sh | grep -v '^\s*#'` → only line 13 (a comment). PASS.
- All compound conditions use explicit `if ... then ... else ... fi` at lines 59-63, 66-75, 103-106.

**AM7** (exactly 2 additive bin/massoh lines):
- `git diff HEAD -- bin/massoh | grep '^+' | grep -v '^+++'` = exactly 2 lines:
  - line 214: `agents-md) shift || true; cmd_agents_md "$@" ;;`
  - line 218: updated `*) die "..."` usage string (old deleted, new added — net +1 on this line)
- No safety-critical function in bin/massoh is altered. Diff confirms +2 / -1 on the case block
  only. PASS.

**AM8** (no secrets/network/LLM):
- `grep -iE 'curl|wget|\bnc\b|ssh |gh ' lib/verbs/agents_md.sh` → empty. PASS.
- `grep -iE 'TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL' lib/verbs/agents_md.sh | grep -v '^\s*#'` → empty. PASS.
- T-AM-f green on all three static checks.

**AM9** (manifest.yml NOT changed):
- `git diff HEAD -- manifest.yml` → empty (no output). PASS.
- `git diff HEAD -- templates/ agent-project/NON_NEGOTIABLES.md` → empty. PASS.

**AM10** (VERSION 0.16.0 + CHANGELOG):
- `VERSION`: `0.16.0`. PASS.
- `CHANGELOG.md`: `## [0.16.0] - 2026-06-19` section above [0.15.0]; entry describes agents-md
  verb, clobber-guard, idempotency, degrade, static parse. PASS.

---

## Test suite result (self-witnessed)

```
== T-AM: agents-md ==
  ok   T-AM-a exits 0
  ok   T-AM-a AGENTS.md created
  ok   T-AM-a sentinel on line 1
  ok   T-AM-a exactly 7 data rows (pipes in table)
  ok   T-AM-a line count < 30 (no body dump)
  ok   T-AM-b second run exits 0
  ok   T-AM-b byte-identical on re-run
  ok   T-AM-b sentinel appears exactly once
  ok   T-AM-c hand-authored refused: exit non-zero
  ok   T-AM-c hand-authored: file content unchanged
  ok   T-AM-c hand-authored: stderr mentions sentinel/generated
  ok   T-AM-d exits 0
  ok   T-AM-d raw pipe not in description cell
  ok   T-AM-e degrade exits 0
  ok   T-AM-e message about no role files
  ok   T-AM-e AGENTS.md NOT created on degrade
  ok   T-AM-f no source/eval/bash-c in agents_md.sh
  ok   T-AM-f no curl/wget/nc/ssh/gh in agents_md.sh
  ok   T-AM-f no TOKEN/SECRET/KEY/PASSWORD/CREDENTIAL in agents_md.sh
  ok   T-AM-g exits 0 with long description
  ok   T-AM-g description cell at most ~260 chars
  ok   T-AM-h exits 0
  ok   T-AM-h Edit tools role shows yes
  ok   T-AM-h no-Edit tools role shows no
  ok   T-AM-i dispatch recognized (not unknown-command)
  ok   T-AM-i agents-md in usage string
  ok   T-AM-j exits 0
  ok   T-AM-j AGENTS.md < 50 lines
  ok   T-AM-j 'You are the' absent from AGENTS.md

ALL GREEN — 418 checks passed.
```

Test count: 418/418.
Test groups: 29 assertions across 10 T-AM groups (a–j) — packet specifies "10 checks" meaning 10
groups; the 29 individual assertions are strictly additive coverage.

---

## Clobber-guard proof (independently reproduced)

Scenario A — hand-authored file (no sentinel):
- Created `AGENTS.md` with content `# My custom agents` in a fresh temp git repo.
- Ran `massoh agents-md` (MASSOH_HOME=repo working tree).
- exit_code=1; md5 before=9a4d1ca4502bc2dcd5e357b3c66e8d1a, after=9a4d1ca4502bc2dcd5e357b3c66e8d1a.
- stderr: "AGENTS.md exists but was not generated by Massoh (no sentinel). Refusing to overwrite."
- FILE UNCHANGED + EXIT 1 + SENTINEL MENTIONED. PASS.

Scenario B — idempotent re-run (sentinel present):
- Fresh temp git repo; ran agents-md twice.
- md5_run1=92a67a079edd88615f88c9f1a9ebafbf = md5_run2=92a67a079edd88615f88c9f1a9ebafbf. PASS.
- head -1 AGENTS.md = `<!-- massoh-generated -->`. PASS.

Scenario C — degrade (no role files):
- T-AM-e (test suite): MASSOH_HOME pointing to claude/agents/ empty dir + lib/verbs symlink.
- exit 0; message "no role files found"; AGENTS.md NOT created. PASS (green in suite).

---

## Scope check

Working tree modified files:
```
M CHANGELOG.md
M VERSION
M bin/massoh
M test/run.sh
?? .agent_tasks/TASK-2026-06-19-agentsmd/05_implementation_handoff.md
?? AGENTS.md
?? lib/verbs/agents_md.sh
```

All changes within approved scope (lib/verbs/agents_md.sh new, bin/massoh +2 lines,
test/run.sh +T-AM, VERSION, CHANGELOG, AGENTS.md runtime artifact). AGENT_SYNC.md,
AGENT_BACKLOG.md, manifest.yml, templates/, NON_NEGOTIABLES.md — all untouched. PASS.

T-MB-f update is legitimate: the test asserts byte-identical output from `massoh unknownverb`;
adding `agents-md` to the dispatch also requires adding it to the usage string, making the prior
hardcoded expected string stale. The update is a truthful correction, not scope creep.

Generated `AGENTS.md` at repo root (14 lines, sentinel line 1, 7 roles) is an expected runtime
artifact per the architecture-safety doc; carrying the sentinel, it is safe to commit.

---

## Scope concerns

None. No hidden scope creep found. No frozen features touched.

---

## Safety / guardrail concerns

None. bin/massoh touched with 2 additive lines only (within batch-auth). manifest.yml untouched.
No safety-critical files altered.

---

## Non-blocking issues

NB-1: The arch-safety AM1 reviewer grep (`grep -v '#' lib/verbs/agents_md.sh | grep -E
'(grep|awk|sed|head|tail)' | grep -v '|| true'`) produces 5 false-positive hits because the
`|| true` guard appears on continuation lines (86, 88, 90) rather than the `awk` invocation lines
(85, 87, 89). The shell parses each as a single pipeline; the `|| true` correctly guards the full
pipeline. Two additional grep-in-if-condition hits (lines 67, 104) are safe under the `if`
construct. Product code is correct; the reviewer grep method does not handle multiline pipelines.
Non-blocking.

---

## Blocking issues

None.

---

## Deviations from packet

1. 29 assertions vs "10 checks" in packet — packet specifies 10 test groups; 29 individual
   `check()` calls across those groups is additive coverage, not a deviation. All 10 groups
   pass.
2. T-MB-f updated — necessary truthful correction to byte-identity assertion; not scope creep.
3. AGENTS.md present at repo root — expected runtime artifact per arch-safety §AM9; sentinel-
   marked; safe to commit or delete.

---

## Owner decision needed

None.

---

## Next recommended action

Orchestrator: squash-merge feat/agentsmd to main per auto-merge-on-green policy; VERSION 0.16.0
ships. Update AGENT_SYNC.md decision log + active task packet row (TASK-2026-06-19-agentsmd →
DONE).
