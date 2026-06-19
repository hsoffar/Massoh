# 04 — Implementation Packet (LICENSE TO CODE): license-to-code gate

- **Task ID:** TASK-2026-06-19-license-gate
- **Date issued:** 2026-06-19
- **Issued after:** product-scope BUILD (`01_product_scope.md`) + architecture-safety CONDITIONAL YES
  (`03_architecture_safety.md`) + **owner sign-off on `bin/massoh` + `manifest.yml`** (recorded in
  `AGENT_SYNC.md` decision log, 2026-06-19).
- **Target VERSION:** 0.9.0
- **Branch:** `feat/license-gate`

This file is the license. Without it (or an approved issue), no code may be written for this task.

## Scope (build exactly this — no more)
A new per-repo, opt-in **license-to-code gate** that mechanically enforces Massoh's "no code without
an approved `04_implementation_packet.md`" guardrail.

**New files (additive):**
- `scripts/massoh-gate-check` — shared POSIX-bash checker. Exit 1 (block) when a diff touches a
  non-exempt path and no `.agent_tasks/*/04_implementation_packet.md` exists; exit 0 otherwise.
  Runs in two modes: pre-push (reads `<local-ref> <local-sha> <remote-ref> <remote-sha>` lines on
  stdin) and CI (`--ci <base-ref>`).
- `templates/massoh-pre-push` — hook wrapper installed into `.git/hooks/pre-push`; calls the checker.
- `templates/massoh-gate.yml` — CI workflow template copied to `.github/workflows/massoh-gate.yml`.

**Modified files (safety-critical — owner-approved):**
- `bin/massoh` — add `cmd_gate()` (sub-commands `on` / `off`) + a `gate)` case in the dispatch block
  and `gate` in the usage `die` message. **No existing verb behavior may change.**
- `manifest.yml` — add the two new templates under `project_scaffold.create_if_missing` (lockstep
  with `bin/massoh`).
- `VERSION` → `0.9.0`. `CHANGELOG.md` → `[0.9.0]` entry.

**Exempt paths (exact, from `01_product_scope.md` §3 — do not drift):** every `*.md`; and
`.agent_tasks/*`, `agent-project/*`, `memory/*`, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `.massoh`,
`LICENSE`, `.gitignore`, `.gitattributes`, `.github/*`. Everything else (`bin/`, `claude/`,
`templates/`, `test/`, `manifest.yml`, `VERSION`, …) is non-exempt.

**Escape hatches:** `git push --no-verify` (standard git) and `MASSOH_GATE_OVERRIDE=1` (checker
exits 0 with a printed warning).

## Out of scope (deferred — do NOT build)
Pre-commit hook; path-to-packet scope matching (which packet covers which path); issue-link parsing;
auto-wiring `gate on` into `cmd_on`; auto-logging of overrides. Re-entry conditions per
`01_product_scope.md`.

## Mandatory conditions — G1–G14 (from `03_architecture_safety.md` §3; all required)
- **G1** `#!/usr/bin/env bash` + `set -euo pipefail` in both new bash files; guard every fallible
  `grep`/`find`/`git` with `|| true` or an `if`.
- **G2** Builtins only: bash, git, find, grep, printf, awk, sed, case. No jq/python/node/curl/wget.
- **G3** Hook install create-if-missing; if `.git/hooks/pre-push` exists without the marker, **append**
  a block framed by `# massoh-gate:start` / `# massoh-gate:end`; if marker present, skip. **Never `>`
  truncate an existing hook.**
- **G4** `gate off` strips only the `# massoh-gate:start…end` block via `awk` (same pattern as
  `remove_block()` in `bin/massoh`); if Massoh created the file standalone, it may remove the file;
  otherwise preserve all non-Massoh content. Absent/un-marked → no-op exit 0.
- **G5** Classify paths via `case`/`grep -E` on the path **string**, not shell glob expansion;
  `find .agent_tasks -name 04_implementation_packet.md 2>/dev/null | grep -q .` (guarded).
- **G6** Exempt list = exactly the list above. No silent add/remove.
- **G7** Null-SHA (`0000…0000`), first-push, empty-diff, detached-HEAD all degrade to exit 0.
- **G8** Override check is the **first** statement in the checker body — exits 0 before any diff/find.
- **G9** CI template invokes `bash scripts/massoh-gate-check --ci <base-sha>` (repo-root-relative path).
- **G10** `manifest.yml` updated in the **same commit** as the new templates; add a comment that
  `.git/hooks/pre-push` is intentionally not manifest-tracked (per-repo ephemeral).
- **G11** `gate on` / `gate off` idempotent; `gate off` on an ungated repo exits 0 silently.
- **G12** `gate on` requires `git rev-parse --git-dir` to succeed AND (`.massoh` exists OR
  `agent-project/` exists); else `die` exit 1, write nothing.
- **G13** `gate` registered in the dispatch `case` block + usage message; `cmd_gate` `die`s with
  usage on any arg other than `on`/`off`.
- **G14** `VERSION` → `0.9.0` in the same PR.

## Required tests — T16a–T16r (18; suite 204 → ≥222)
Use the existing `test/run.sh` harness + temp repos (no bats). Build the spec exactly as listed in
`03_architecture_safety.md` §4: T16a install creates hook+CI; T16b idempotent (md5 unchanged, no
duplicate marker blocks); **T16c no-clobber of pre-existing hook**; **T16d `gate off` preserves
pre-existing content, removes marker block**; T16e `gate off` no-op when never installed; T16f block
on non-exempt w/o packet; T16g pass with packet; T16h pass on exempt-only diff; T16i AGENT_SYNC.md /
memory/ / .github/ exempt; T16j `MASSOH_GATE_OVERRIDE=1` exit 0 + warning; T16k `--no-verify` bypass;
T16l null-SHA degrade exit 0; T16m empty-diff CI exit 0; T16n `gate on` fails outside git/non-Massoh;
T16o mixed exempt+non-exempt blocks w/o packet; T16p CI mode block-then-pass (2 sub-checks); T16q
`gate off` partial-state exit 0; **T16r `md5sum bin/massoh` + `manifest.yml` unchanged across the
suite**.

## Acceptance criteria (implementer self-checks before handoff)
1. All 14 conditions G1–G14 satisfied — cite file:line for each in `05_implementation_handoff.md`.
2. All 18 tests T16a–T16r present and green; full suite ≥222 green; paste verbatim test output.
3. `massoh gate on` then `gate off` round-trips cleanly in a scratch repo (manual smoke, transcript
   in handoff) — including the "pre-existing user hook preserved" case.
4. Existing 204 tests still green (zero regressions).
5. `bin/massoh` diff adds only `cmd_gate` + dispatch/usage lines; no other verb altered (G13).
6. `manifest.yml` ↔ templates lockstep in one commit (G10); VERSION 0.9.0; CHANGELOG `[0.9.0]`.

## Rollback
`massoh gate off` per repo (removes hook block; leaves user-tracked CI file for owner to delete).
Code-level: revert the v0.9.0 PR — v0.8.0 installs have no `gate` verb and no hooks, so they are
unaffected. Full plan in `03_architecture_safety.md` §5.

## Routing
`massoh-implementer` → `05_implementation_handoff.md` → `massoh-reviewer-qa` (`06_review_result.md`)
→ owner merge. Branch `feat/license-gate`, one PR.
