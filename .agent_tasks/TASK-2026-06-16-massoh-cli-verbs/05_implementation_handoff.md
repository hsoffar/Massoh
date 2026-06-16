# 05 — Implementation Handoff

**Agent:** massoh-implementer · **Date:** 2026-06-16 · **Branch:** `feat/massoh-cli-verbs`
**License:** `04_implementation_packet.md` (owner-signed). Scope implemented exactly; no extras.

## 1. Files changed
| File | Change |
|---|---|
| `bin/massoh` | hardened `cmd_update` (stash→pull→pop, fail-safe); +`cmd_doctor` (read-only); +`cmd_discover`; dispatch + usage string updated |
| `templates/STANDARDS.template.md` | **new** — language-agnostic standards doc (shipped by install via `templates/`) |
| `claude/agents/massoh-implementer.md` | +1 line: read `agent-project/STANDARDS.md` if present |
| `claude/agents/massoh-reviewer-qa.md` | +1 line: check change conforms to `STANDARDS.md` |
| `test/run.sh` | **new** — first CLI test suite (POSIX, throwaway `CLAUDE_CONFIG_DIR`) |
| `agent-project/STANDARDS.md` | **generated artifact** by running `massoh discover` here (project file, not engine) |

## 2. What was implemented
All three `04` items + the STANDARDS template + role wiring + tests. `manifest.yml`, block markers,
`backup_claude`, install/uninstall removal set — **untouched** (per arch/safety conditions).

## 3. Tests run (verbatim)
```
$ bash test/run.sh
== T1: install / status / doctor ==      6 ok (incl. doctor read-only + non-zero-on-drift)
== T2: discover ==                       6 ok (create-if-missing, --force, refuses outside project)
== T3: update preserves dirty edits ==   1 ok (stash→pull→pop, no data loss)
== T4: update aborts non-ff cleanly ==   2 ok (non-zero + local commit preserved)
== T5: regression on/off/uninstall ==    6 ok
ALL GREEN — 21 checks passed.   (exit 0)
```
Every test ran against `mktemp -d` CLAUDE_CONFIG_DIR + temp git repos. **Real `~/.claude` not touched.**

## 4. Risks
- `cmd_update` is the only behavior change to an existing verb. Mitigated: fail-safe (never
  `reset --hard`/`clean`; conflict → abort + edits kept in `git stash list`), covered by T3+T4.
- `discover` heuristic is conservative: commit-convention needs ≥5 conventional commits in last 50
  (a 2-commit repo reads "no clear convention"). By design (avoid false positives); user confirms.

## 5. Incomplete items
None in scope. Out-of-scope (deferred, recorded): `doctor --repair`, LLM-deep discover, `AGENTS.md`,
`massoh report`. Title `{{PROJECT}}` in generated `STANDARDS.md` left for owner to fill (template norm).

## 6. Handoff for reviewer
Review against `04` acceptance criteria. Verify: (a) no edit to `manifest.yml`/markers/backup/removal
set; (b) `doctor` writes nothing outside stdout (T1 asserts via md5 snapshot); (c) `discover`
create-if-missing; (d) `update` cannot lose data. Independence caveat: implemented + tested in one
session — owner is the final independent reviewer/merger.

## 7. Not committed yet
Changes staged on branch `feat/massoh-cli-verbs`, not yet committed (awaiting `06` + owner).
