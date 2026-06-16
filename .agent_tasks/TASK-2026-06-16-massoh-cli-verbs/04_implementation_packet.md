# 04 — Implementation Packet (THE LICENSE TO CODE)

**Task:** TASK-2026-06-16-massoh-cli-verbs · **Date:** 2026-06-16
**Authorized by:** owner sign-off (Guardrail B, `bin/massoh`) + product-scope BUILD(01) + arch/safety
CONDITIONAL YES(03, all conditions accepted). **Branch:** `feat/massoh-cli-verbs` (off `main`).

## Scope (exactly this — Guardrail A9, no "while I'm here")
1. **Harden `cmd_update`** in `bin/massoh`: before `git pull --ff-only`, if the clone is dirty,
   `git stash push -u`; pull; `git stash pop`. On pull/pop failure → abort cleanly, restore, message.
   No new flags. No `reset --hard`, no `git clean`.
2. **Add `cmd_doctor`** to `bin/massoh` (verb `doctor`): read-only. Check the live `~/.claude` against
   what `cmd_install` writes — the global block, `massoh-*` agents present, owned skills
   (`start-task sync close-task history-cleanup`), `agent-os/` payload. Print version + repo short
   SHA. Exit `0` if all present, non-zero + a list if drift. **Writes only to stdout/stderr.**
3. **Add `cmd_discover`** to `bin/massoh` (verb `discover`): writes `agent-project/STANDARDS.md` from
   `templates/STANDARDS.template.md`, with a heuristic scan pre-fill (detected language/build files,
   test command guess, commit convention from `git log`, top-level dir layout). Create-if-missing;
   `--force` refreshes. Requires being in a Massoh project (`.massoh` or `agent-project/`).
4. **Ship `templates/STANDARDS.template.md`** — language-agnostic standards doc.
5. **Wire**: add one line to `claude/agents/massoh-implementer.md` + `claude/agents/massoh-reviewer-qa.md`:
   read `agent-project/STANDARDS.md` if present.
6. **Tests** `test/massoh.bats` (+ `test/run.sh` fallback): exercise the real paths against a
   throwaway `CLAUDE_CONFIG_DIR`/temp repo — never the real `~/.claude`.

## Out of scope (do NOT touch)
`manifest.yml` contract/keys, block markers, `backup_claude`, the install/uninstall removal set, any
other policy/template. No LLM in discover. No `doctor --repair` (later). No `AGENTS.md`.

## Flag / behavior
Additive verbs = dark by default (absent = no change). Only behavior-change = `update` internals,
gated by its fail-safe test. If that test can't be made green → ship doctor+discover, defer update.

## Required tests (real — Guardrail A5) — acceptance
- `update`: dirty clone → no diff lost (stash→pop); simulated conflict → clean abort + restore.
- `doctor`: full install → exit 0; remove one `massoh-*` agent → non-zero + names it; asserts no
  writes outside stdout.
- `discover`: creates non-empty `STANDARDS.md`; re-run w/o `--force` keeps it; `--force` refreshes;
  refuses outside a Massoh project.
- regression: `install→status→on→off→uninstall` happy path green, idempotent.
- All tests use `CLAUDE_CONFIG_DIR=$(mktemp -d)` + a temp git repo.

## Rollback
Pure additive → `git revert` the branch. No state/migration.

## Handoff target
`massoh-implementer` → produce `05_implementation_handoff.md` (files, verbatim test output, risks) →
`massoh-reviewer-qa` → `06_review_result.md`. PR left open for owner merge.
