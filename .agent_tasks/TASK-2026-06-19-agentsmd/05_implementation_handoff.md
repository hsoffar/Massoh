# 05 — Implementation Handoff: emit AGENTS.md (24h queue #10)

**Agent:** massoh-implementer
**Date:** 2026-06-19
**Branch:** feat/agentsmd
**VERSION:** 0.16.0 (bumped from 0.15.0)
**Suite result:** ALL GREEN — 418 checks passed (baseline 389 + 29 new T-AM assertions)

---

## Files changed

| File | Change | Lines |
|---|---|---|
| `lib/verbs/agents_md.sh` | NEW — cmd_agents_md + helpers | ~110 |
| `bin/massoh` | +2 additive lines (dispatch + usage) | +2 |
| `test/run.sh` | +29 T-AM checks (10 test groups a–j) + T-MB-f usage update | +~170 |
| `VERSION` | 0.15.0 → 0.16.0 | 1 |
| `CHANGELOG.md` | [0.16.0] section added | +8 |
| `AGENTS.md` | Generated artifact at repo root (7 roles, 14 lines) | NEW |

---

## AM1–AM10 conditions — file:line evidence

**AM1** (`|| true` on all reads; degrade exit 0 if no role files):
- `lib/verbs/agents_md.sh:56` — `found` counter loop never fails (glob with no matches = zero iterations)
- `lib/verbs/agents_md.sh:59` — `[ "$found" -eq 0 ]` degrade path: `say` + `return 0`; AGENTS.md NOT created
- `lib/verbs/agents_md.sh:81` — `raw_name` parse: `awk ... || true`
- `lib/verbs/agents_md.sh:82` — `sed ... | head -n1 || true`; same for `raw_desc`, `raw_tools`
- Reviewer grep: `grep -v '#' lib/verbs/agents_md.sh | grep -E '(grep|awk|sed|head|tail)' | grep -v '|| true'` → empty

**AM2** (write to repo root; sentinel line 1; overwrite if sentinel; refuse+exit 1 if absent; idempotent):
- `lib/verbs/agents_md.sh:43` — `repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"` and `target="$repo/AGENTS.md"`
- `lib/verbs/agents_md.sh:26` — `AGENTS_MD_SENTINEL="<!-- massoh-generated -->"` (exact string, named var)
- `lib/verbs/agents_md.sh:69–77` — clobber policy: `if [ -f "$target" ]; then grep -qF "$sentinel" ... else refuse+return 1`
- `lib/verbs/agents_md.sh:98` — `${AGENTS_MD_SENTINEL}` is line 1 of `$content` heredoc-style var
- Sentinel on line 1: the `content` variable starts with `${AGENTS_MD_SENTINEL}\n# Massoh Agent Team...`
- Idempotency proof: md5sum run1=92a67a079edd88615f88c9f1a9ebafbf = md5sum run2 (verified live)
- Clobber-guard proof (hand-authored): exit=1, FILE UNCHANGED (md5 identical before/after)

**AM3** (frontmatter as data only; name≤64; desc≤256+`...`; edits-code from tools; no source/eval):
- `lib/verbs/agents_md.sh:80–86` — `awk '/^---/{n++;next} n==1 && /^name:/{print;exit}'` + `sed` + `head -n1`; same for desc and tools. No `source`, no `eval`, no `bash -c`.
- `lib/verbs/agents_md.sh:89–90` — `_agents_md_cap "$raw_name" 64` and `_agents_md_cap "$raw_desc" 256`
- `lib/verbs/agents_md.sh:37–42` — `_agents_md_cap`: `${val:0:$max}...` if len > max
- `lib/verbs/agents_md.sh:95–98` — `grep -qE '\bEdit\b|\bWrite\b'` on tools → `edits_code="yes"/"no"`

**AM4** (`_agents_md_sanitize_cell`; pipes→/; newlines→space; on name+desc):
- `lib/verbs/agents_md.sh:31–35` — `_agents_md_sanitize_cell`: `tr '\n' ' ' | sed 's/|/\//g' || true`
- `lib/verbs/agents_md.sh:93–94` — applied to both `cell_name` and `cell_desc`

**AM5** (< 50 lines; sentinel + header + 7-row table + workflow pointer; no body):
- `lib/verbs/agents_md.sh:101–109` — `content` assembled: sentinel + `# Massoh Agent Team` + table + workflow pointer only
- AGENTS.md generated with real role files: 14 lines (well under 50)
- "You are the" absent from output: confirmed by grep + T-AM-j

**AM6** (`set -euo pipefail`; if/else not A&&B||C):
- `lib/verbs/agents_md.sh:21` — `set -euo pipefail`
- All compound conditions use explicit `if/else` (lines 58–66, 72–78, 95–97)
- Reviewer check: `grep -n '&&.*||' lib/verbs/agents_md.sh | grep -v '^\s*#'` → only line 13 (comment)

**AM7** (exactly 2 additive lines in bin/massoh):
- `bin/massoh:213` — `agents-md) shift || true; cmd_agents_md "$@" ;;`
- `bin/massoh:217` — usage string updated to include `agents-md`
- Verified: `git diff HEAD -- bin/massoh | grep '^+' | grep -v '^+++'` = exactly 2 lines

**AM8** (no secrets/network/LLM):
- Static checks all pass (verified live and in T-AM-f):
  - `grep -vE '^\s*#' lib/verbs/agents_md.sh | grep -E 'curl|wget|\bnc\b|ssh |gh '` → empty
  - `grep -vE '^\s*#' lib/verbs/agents_md.sh | grep -E '\bsource\b|\beval\b|bash -c'` → empty
  - `grep -iE 'TOKEN|SECRET|KEY|PASSWORD|CREDENTIAL'` (non-comment) → empty

**AM9** (manifest.yml NOT changed):
- `git diff HEAD -- manifest.yml` → empty (no diff). AGENTS.md classified as runtime artifact.

**AM10** (VERSION 0.16.0 + CHANGELOG):
- `VERSION`: `0.16.0`
- `CHANGELOG.md`: `## [0.16.0] - 2026-06-19` section added above [0.15.0]

---

## Clobber-guard + sentinel proof

Scenario 1 — Fresh repo, no AGENTS.md:
- Run `massoh agents-md` → exits 0, AGENTS.md created, line 1 = `<!-- massoh-generated -->`

Scenario 2 — Idempotent overwrite (sentinel present):
- Second run → exits 0, md5sum identical (92a67a079edd88615f88c9f1a9ebafbf both runs)
- Sentinel appears exactly once (T-AM-b confirmed)

Scenario 3 — Hand-authored AGENTS.md (no sentinel):
- Run → exit 1; stderr contains "sentinel" / "generated"; file md5 identical before/after
- T-AM-c green; T-BR-5 pattern mirrored

Scenario 4 — Degrade (no role files):
- Run → exits 0; message "no role files found"; AGENTS.md NOT created (T-AM-e)

---

## Test suite output (verbatim last section)

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

---

## Deviations from packet

1. **29 assertions vs "10 checks"** — the packet specifies 10 test *groups* (T-AM-a through T-AM-j), each containing multiple assertions. Total 29 check() calls across the 10 groups. All 10 groups pass. This is strictly additive (more coverage, not less).
2. **T-MB-f updated** — that test had a hardcoded usage string; adding `agents-md` to the usage correctly required updating it. This is an additive/truthful fix, not scope creep.
3. **AGENTS.md generated at repo root** — the verb was run manually during verification, generating the real AGENTS.md for the Massoh repo (14 lines, 7 roles, sentinel line 1). This is a valid runtime artifact; it carries the sentinel and is safe to commit or delete.

---

## Risks

- None critical. The sentinel clobber-guard (AM2, the highest risk per arch-safety) is verified correct.
- The T-AM test helper uses `ln -s $REPO_ROOT/lib/verbs $mock/lib/verbs` — symlink to real lib. This is the standard pattern (mirrors T3/T4 clone approach) and is safe in throwaway temp dirs.

---

## Incomplete items

None. All AM1–AM10 satisfied. All T-AM-a through T-AM-j green. VERSION 0.16.0. Manifest untouched.

---

## Handoff to reviewer-qa

**Routing:** massoh-reviewer-qa

**What to verify:**
1. AM1: `grep -v '#' lib/verbs/agents_md.sh | grep -E '(grep|awk|sed|head|tail)' | grep -v '|| true'` → empty
2. AM2: clobber-guard — run T-AM-b and T-AM-c manually; assert byte-identical + exit 1 on hand-authored
3. AM3: `grep -E '\bsource\b|\beval\b|bash -c' lib/verbs/agents_md.sh` (non-comment) → empty
4. AM6: `grep -n '&&.*||' lib/verbs/agents_md.sh | grep -v '^\s*#'` → only comment line
5. AM7: `git diff HEAD -- bin/massoh | grep '^+' | grep -v '^+++' | wc -l` → 2
6. AM9: `git diff HEAD -- manifest.yml` → empty
7. AM10: VERSION=0.16.0; CHANGELOG has [0.16.0] section
8. AGENTS.md: line 1 = `<!-- massoh-generated -->`; `wc -l AGENTS.md` < 50; `grep 'You are the' AGENTS.md` → empty
9. `bash test/run.sh` → ALL GREEN — 418 checks passed
10. Scope: 5 new files/changes only; AGENT_SYNC.md / AGENT_BACKLOG.md / manifest.yml / templates/ untouched
