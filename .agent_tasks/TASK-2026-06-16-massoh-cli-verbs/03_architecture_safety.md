# 03 — Architecture / Safety

**Agent:** massoh-architecture-safety · **Date:** 2026-06-16 · UX stage skipped (not user-facing).

## 1. Backend/service impact
None — no service. Pure-bash CLI (`bin/massoh`). All three are local, synchronous, no network except
`update`'s existing `git pull`.

## 2. Client/app impact
`bin/massoh` gains two verbs (`doctor`, `discover`) + hardens one (`update`). New file shipped:
`templates/STANDARDS.template.md`. Two role files gain a one-line read directive.

## 3. API impact (contract change?)
**Yes — adjacent to the contract seam.** `doctor` *reads* `manifest.yml` (the boundary of record).
Risk: `doctor` re-implements the install list and drifts from `cmd_install`. **Mitigation:** `doctor`
must check against the **same** verb set `cmd_install`/`cmd_uninstall` use (block of `massoh-*`
agents, owned skills `start-task/sync/close-task/history-cleanup`, `agent-os/` payload, the
block markers). Do **not** add new manifest keys; `version:` is read-only here. Contract unchanged.

## 4. DB/migration impact
N/A (no DB). Data-equivalent = the user's `~/.claude` + host files. `discover` is **create-if-missing**
(`--force` opt-in) → keep-older-data satisfied. `doctor` is read-only. `update` must **stash→pop**,
never discard: a `stash pop` conflict must abort and leave the clone restored (no data loss).

## 5. LLM/prompt impact
None. `discover` v1 is **heuristic** (file/grep scan), no LLM call, no prompt/safety-rule edits.

## 6. Safety/guardrail risks
- **bin/massoh is designated safety-critical** (`NON_NEGOTIABLES.md`) → **Guardrail B owner-gated.**
  ⇒ **requires explicit owner sign-off before any edit.** This is the hard stop.
- `update` regression could brick a user's installed team. Mitigation: stash logic must be
  fail-safe + covered by a `bats` test; never `reset --hard`, never `git clean`.
- `doctor` must be **read-only** — any write outside stdout is a reject.
- `discover` must never overwrite an existing `STANDARDS.md` without `--force` (create-if-missing,
  mirrors `scaffold()`).
- No change to `manifest.yml`, the block markers, install/uninstall removal set, or backup logic.

## 7. Expansion/localization risks
`discover` must stay language-agnostic — report detected stack, fall back to placeholders; never
hard-code one language/framework into the template.

## 8. Required tests (real, not stubs — Guardrail A5)
First-ever test suite for the CLI (`bats`, or a POSIX `test/run.sh` if bats unavailable):
- `update`: dirty clone → stash→pull→pop, no diff lost; simulated conflict → clean abort + restore.
- `doctor`: matching install → exit 0; remove one `massoh-*` agent → non-zero + names it; assert it
  writes nothing outside stdout.
- `discover`: creates `STANDARDS.md`; re-run without `--force` keeps it; `--force` refreshes.
- regression: `install → status → on → off → uninstall` happy path still green (idempotent).
Run against a **throwaway `CLAUDE_CONFIG_DIR`** temp dir — never the real `~/.claude`.

## 9. Rollback plan
Pure additive. Rollback = revert the branch (no migrations, no state). `update` hardening is the only
behavior change to an existing verb → its `bats` test is the gate; if it can't be made fail-safe,
**ship `doctor`+`discover` only and defer `update`.**

## 10. Approved for implementation? **CONDITIONAL YES**
Approved on design grounds **iff**:
1. **Owner explicitly signs off** on editing `bin/massoh` (Guardrail B — the one blocker). ⛔ until then.
2. Tests run against a temp `CLAUDE_CONFIG_DIR`, never real `~/.claude`.
3. `doctor` stays read-only; `discover` stays create-if-missing; no `manifest.yml`/marker/backup edits.
4. Work on a non-default branch; `update` ships only if its fail-safe test is green (else defer it).

No `04_implementation_packet.md` is written until condition #1 (owner sign-off) is granted.
