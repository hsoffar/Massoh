# 03 — Architecture / Safety Assessment: license-to-code gate enforcement

- **Task ID:** TASK-2026-06-19-license-gate
- **Date:** 2026-06-19
- **Agent:** massoh-architecture-safety (Massoh role)
- **Scope honored:** exactly the MVP from `01_product_scope.md` — no re-litigation of product
  decisions already resolved there.

---

## 1. Impact analysis — every file touched

### New files (additive — do not exist today)

| File | Kind | Notes |
|---|---|---|
| `scripts/massoh-gate-check` | New executable bash script | Shared checker called by both hook and CI. POSIX bash, `set -euo pipefail`. No new deps. |
| `templates/massoh-pre-push` | New template file | Hook wrapper installed into `.git/hooks/pre-push` by `massoh gate on`. |
| `templates/massoh-gate.yml` | New template file | CI workflow template copied to `.github/workflows/massoh-gate.yml` by `massoh gate on`. |

### Modified files (safety-critical)

| File | Kind | Safety-critical? | Change surface |
|---|---|---|---|
| `bin/massoh` | Modified | **YES — NON_NEGOTIABLES designated** | New `cmd_gate()` function + dispatch line in the `case` block (lines 1040–1062). No existing verb behavior altered. |
| `manifest.yml` | Modified | **YES — NON_NEGOTIABLES designated; must move in lockstep with `bin/massoh`** | New entries under `project_scaffold` for the two new templates. |

### Installed artifacts (runtime, not repo-tracked)

| Artifact | Location | Owned by `massoh gate off`? |
|---|---|---|
| `.git/hooks/pre-push` | User repo (not tracked by git) | YES — must remove only the Massoh-namespaced lines; must never remove a pre-existing user hook |
| `.github/workflows/massoh-gate.yml` | User repo (tracked, committed by user) | NO — `massoh gate off` does NOT delete this; per NON_NEGOTIABLES §Prohibited, Massoh never deletes user files it did not create under its own namespace. Owner deletes if desired. |

### Files NOT touched (confirmed)

- `templates/CLAUDE.global-block.md` — unchanged
- `templates/CLAUDE.project.template.md` — unchanged
- `cmd_on` / `cmd_off` / `cmd_install` / `cmd_uninstall` — existing verb behavior unchanged
- `~/.claude/` global footprint — gate is per-repo opt-in only; global install untouched
- All `claude/agents/massoh-*.md` files — unchanged
- All existing `claude/skills/` — unchanged

---

## 2. Risks (enumerated; each maps to a mandatory condition below)

### R1 — CRITICAL: Hook install clobbers a pre-existing user pre-push hook (maps to G3)

`bin/massoh`'s `cmd_on` scaffold function uses `scaffold()`, which is create-if-missing and never
overwrites. The gate's `cmd_gate on` must follow the same invariant for the hook file. If the user
already has a `.git/hooks/pre-push`, silently overwriting it destroys their tooling. This is
explicitly prohibited by NON_NEGOTIABLES §Prohibited ("a scaffold that overwrites an existing
project file — create-if-missing only") and §Data+migration ("never hard-delete a user's files").

Mitigation: `cmd_gate on` must check for an existing `.git/hooks/pre-push`. If absent, write
the Massoh hook. If present AND not already containing the Massoh hook marker, append a call
to `scripts/massoh-gate-check` to the existing file (append-safe). If already present, skip
(idempotent). Never use `>` (overwrite) — only `>>` append or skip.

### R2 — Exempt-list glob correctness under `set -euo pipefail` (maps to G5, G6)

The checker reads paths from stdin (pre-push) or from `git diff --name-only` (CI mode). In
`set -euo pipefail`, an unquoted glob that matches nothing expands to the literal pattern string,
and `for f in $unmatched_glob` iterates over the literal string instead of zero items. The checker
must use `case`/`grep -E` pattern matching on string values, not shell glob expansion over
path lists. Every `grep` call must be guarded with `|| true`.

### R3 — First-push / empty-diff / detached-HEAD edge cases (maps to G7)

Pre-push hook receives push info on stdin in the format `<local-ref> <local-sha1> <remote-ref>
<remote-sha1>`. On a first push (no remote counterpart yet), the remote SHA is the all-zeros
null SHA (`0000000000000000000000000000000000000000`). `git diff --name-only <null-sha> <local-sha>`
is not a valid invocation and will fail. The checker must detect the null SHA and use
`git diff-tree --no-commit-id -r --name-only <local-sha>` as the fallback, or degrade to
exit 0 (no diff available — permit the push). A detached HEAD has no branch ref; the checker
must not fail on that either.

### R4 — Override always works; gate must never trap the owner (maps to G8)

`MASSOH_GATE_OVERRIDE=1` must be checked before any diff computation. If it is set, the checker
must print the warning and `exit 0` immediately — no path classification, no `find` call. This
prevents the override from being defeated by a script error in the classification logic.

### R5 — CI template references wrong checker path (maps to G9)

The CI workflow template (`templates/massoh-gate.yml`) will reference the checker as
`scripts/massoh-gate-check`. If the implementer gets the relative path wrong (e.g., uses
`./massoh-gate-check` without the `scripts/` prefix, or an absolute path), the CI step will
fail with "command not found" rather than a gate failure, silently degrading enforcement to
always-pass. The template must use a path relative to the repo root, consistent with
`git diff` usage in CI mode.

### R6 — manifest.yml drift from what is actually installed (maps to G10)

`manifest.yml` is the boundary of record (NON_NEGOTIABLES). If the implementer adds a new
template file but does not update `manifest.yml`, `massoh doctor` will not flag the drift and
`massoh uninstall` will miss it. The two new template entries (`massoh-pre-push`,
`massoh-gate.yml`) must be added to `manifest.yml` under `project_scaffold.create_if_missing`
in the same commit that adds the templates. The hook installed into `.git/hooks/` is NOT listed
in manifest (it is per-repo ephemeral, not a global install artifact) — this is correct and must
be documented in a comment.

### R7 — Self-bootstrap paradox: gate blocks its own installation commit (maps to G11)

The implementation commit for this task will touch `bin/massoh`, `manifest.yml`, `scripts/`,
and `templates/`. These are non-exempt paths. If the gate is already installed in the Massoh
repo before the implementation PR is merged, the pre-push hook will fire and block the push
because the task's `04_implementation_packet.md` exists but `bin/massoh` is in the diff.
Actually, that is the INTENDED behavior — the gate should pass because a `04_implementation_packet.md`
exists. The implementer must confirm the packet file is present before pushing.
Risk: if the implementer forgets to stage `.agent_tasks/TASK-2026-06-19-license-gate/04_implementation_packet.md`,
the hook will block the push. Resolution: ensure the packet file is in the working tree before
pushing. Note that `.agent_tasks/` paths are exempt, so the packet file's own push is always
safe — only non-exempt paths require the packet to exist.

### R8 — Uninstall backward-compat for one release (maps to G12)

NON_NEGOTIABLES §Data+migration: "changes to the install/uninstall contract must be backward-compatible
for one release (old layout still uninstalls cleanly)." The gate adds new behavior but does NOT
change any existing install/uninstall path. `massoh uninstall` removes global footprint only;
per-repo artifacts (the hook, the CI workflow) are managed by `massoh gate off`. This is a new
surface and requires no migrate/contract phase — but `massoh gate off` must be safe to run on a
repo where the gate was never installed (no-op, exit 0) and on a repo where only one of the two
artifacts exists (partial state after a failed gate-on or manual edit).

### R9 — `set -euo pipefail` interaction with `find` returning zero results (maps to G5)

`find .agent_tasks -name "04_implementation_packet.md" | grep -q .` — if `.agent_tasks/` does
not exist, `find` exits non-zero (POSIX: `find` on a non-existent path returns exit 1), which
under `set -euo pipefail` would abort the checker script before reaching `grep`. Must use
`find .agent_tasks -name "04_implementation_packet.md" 2>/dev/null | grep -q .` with the
`2>/dev/null` to suppress the error, and the entire pipeline must be guarded with `|| true`
or wrapped in an `if` block.

### R10 — Hook append-safety must preserve existing hook's shebang and logic (maps to G3, G4)

When appending to an existing hook, the Massoh-added lines must be bounded by namespace markers
(e.g., `# massoh-gate:start` / `# massoh-gate:end`) so that `massoh gate off` can remove
exactly those lines and nothing more. This is the same pattern as the global CLAUDE.md block
markers (`BLOCK_START`/`BLOCK_END` in `bin/massoh`). Without markers, `massoh gate off`
cannot remove the Massoh lines without potentially corrupting the pre-existing hook content.

---

## 3. Mandatory conditions (implementer MUST satisfy all)

**G1 — `set -euo pipefail` in all new bash files**
`scripts/massoh-gate-check` and `templates/massoh-pre-push` must both open with
`#!/usr/bin/env bash` and `set -euo pipefail`. Every `grep`, `find`, and `git` call that can
legitimately return non-zero must be guarded with `|| true` or wrapped in an `if` block.
Rationale: matches the existing `bin/massoh` pattern (line 5); POSIX+pipefail invariant in
NON_NEGOTIABLES.

**G2 — No non-portable deps; allowed builtins only**
The checker and hook wrapper may use only: `bash`, `git`, `find`, `grep`, `printf`, `awk`,
`sed`, `case`. Specifically forbidden: `jq`, `python`, `python3`, `node`, `curl`, `wget`,
any package manager. The CI template may reference `actions/checkout` but the checker step
must run the bash script with no additional tool installation.
Rationale: NON_NEGOTIABLES POSIX-bash invariant; AC10 from `01_product_scope.md`.

**G3 — Create-if-missing for hook install; append-safe with namespace markers if hook exists**
`massoh gate on` logic for the hook:
(a) If `.git/hooks/pre-push` is absent: create it with the Massoh hook content (shebang +
namespace markers + call to checker).
(b) If `.git/hooks/pre-push` is present and already contains the Massoh marker: skip (idempotent,
print "already installed").
(c) If `.git/hooks/pre-push` is present and does NOT contain the Massoh marker: append the
Massoh block (framed by `# massoh-gate:start` / `# massoh-gate:end`) to the existing file.
Never use `>` (truncate) on an existing hook file.
Rationale: NON_NEGOTIABLES §Prohibited "create-if-missing only"; R1/R10 above.

**G4 — `massoh gate off` removes only Massoh-namespaced hook lines**
`massoh gate off` must use `awk` (same pattern as `remove_block` in `bin/massoh` lines 50–56)
to strip the `# massoh-gate:start … # massoh-gate:end` block from `.git/hooks/pre-push` if
present, leaving all other content intact. If `.git/hooks/pre-push` no longer contains any
non-Massoh content after removal (i.e., Massoh created the file from scratch in case G3a),
then the file may be removed entirely. If the hook was not installed (file absent or marker
absent), `gate off` exits 0 silently (no-op).
Rationale: NON_NEGOTIABLES §Prohibited "uninstall removes nothing not massoh-namespaced"; R8.

**G5 — Glob-safe path matching in checker: use `case`/`grep -E`, not shell glob expansion**
The checker must classify each path as exempt or non-exempt by matching the path string against
patterns using `case "$path" in *.md) … ;; .agent_tasks/*) … ;;` or equivalent `grep -E`
matching — NOT by shell glob expansion over the filesystem. Every `grep` and `find` invocation
must be guarded with `|| true`. The `find .agent_tasks -name "04_implementation_packet.md"`
invocation must include `2>/dev/null` before the pipe.
Rationale: R2 and R9; `set -euo pipefail` + empty-glob hazard.

**G6 — Exempt list must exactly match `01_product_scope.md` §3**
The checker's exempt list must cover all of: `*.md`, `.agent_tasks/*`, `agent-project/*`,
`AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `memory/*`, `.massoh`, `LICENSE`, `.gitignore`,
`.gitattributes`, `.github/*`. No paths may be added to or removed from this list without
a new product-scope decision. The implementer must not silently expand or contract the
exempt list during implementation.
Rationale: scope discipline (Guardrail A9); the exempt list is a product decision already
resolved in `01_product_scope.md`.

**G7 — Null-SHA / first-push / empty-diff degrade safely**
The checker must detect the null SHA (`0000000000000000000000000000000000000000`) as the
remote ref in the pre-push stdin payload and degrade to exit 0 (permit the push, no block).
When run in CI mode (`--ci <base-ref>`), if `git diff --name-only <base-ref>...HEAD` returns
zero lines (empty diff), the checker must exit 0. A detached HEAD must not cause a crash.
Rationale: R3; hook must be non-trapping.

**G8 — Override is the first check; exits 0 unconditionally when set**
The very first executable statement in the checker body (after `set -euo pipefail`) must be:
```
[ "${MASSOH_GATE_OVERRIDE:-}" = "1" ] && { printf '[massoh-gate] OVERRIDE active — gate bypassed. Record justification in commit message.\n'; exit 0; }
```
(or equivalent). No diff computation, no `find`, no `git` call may precede this check.
Rationale: R4; the gate must never trap the owner.

**G9 — CI template checker path must be repo-root-relative and consistent**
The CI workflow template step that runs the checker must invoke it as
`bash scripts/massoh-gate-check --ci "${{ github.event.pull_request.base.sha }}"` (or
equivalent with the base ref). The path `scripts/massoh-gate-check` must be relative to
the repo root (the working directory in a GitHub Actions `run` step after `actions/checkout`).
The implementer must not use an absolute path or a path that only resolves in the Massoh
source repo.
Rationale: R5; CI enforcement is the server-side trust anchor for the entire gate feature.

**G10 — manifest.yml updated in the same commit as the new templates; hook location commented**
Both `templates/massoh-pre-push` and `templates/massoh-gate.yml` must be added to
`manifest.yml` under `project_scaffold.create_if_missing` in the same commit that introduces
those files. A comment must be added near the `project_scaffold` section clarifying that
`.git/hooks/pre-push` is NOT listed in manifest because it is a per-repo ephemeral artifact
managed exclusively by `massoh gate on/off`, not by `massoh on/install/uninstall`.
Rationale: R6; manifest ↔ bin/massoh lockstep is the API contract seam (CHARTER.md §3).

**G11 — `massoh gate on/off` are idempotent**
Running `massoh gate on` twice: same hook content, no error, exit 0 (prints "already installed"
for the hook). Running `massoh gate off` twice: no error, exit 0 (prints "not installed" or
"nothing to remove" on second run). Running `massoh gate off` in a repo where `gate on` was
never run: no error, exit 0.
Rationale: matches `scaffold()` pattern and all prior Massoh verbs; `01_product_scope.md` §AC7/AC8.

**G12 — `massoh gate on` must require the current directory to be a git repo and a Massoh project**
Before any hook-write, `cmd_gate` must verify (a) `git -C "$PWD" rev-parse --git-dir >/dev/null 2>&1`
and (b) `[ -e "$PWD/.massoh" ] || [ -d "$PWD/agent-project" ]`. If either check fails, `die`
with a clear message and exit 1. This prevents accidental hook installation in non-repo
directories or non-Massoh repos.
Rationale: consistent with `cmd_discover`/`cmd_learn` project guard pattern
(bin/massoh lines 167–169, 370–372).

**G13 — New `gate` verb registered in the dispatch `case` block and in the usage `die` message**
The dispatch table at the bottom of `bin/massoh` (lines 1040–1062) must gain a `gate)` case.
The `die` usage message (line 1062) must list `gate` among the verbs. The `cmd_gate` function
must accept `on` and `off` as sub-commands and `die` with usage on any other argument.
Rationale: consistency with all prior verb additions; `massoh gate` must be discoverable.

**G14 — VERSION bumped to 0.9.0 and `massoh install` re-run propagates the new templates**
`VERSION` must be updated to `0.9.0` in the same PR. Because `cmd_install` wires
`agent-os/templates/` into `~/.claude/agent-os/templates/`, the new `massoh-pre-push` and
`massoh-gate.yml` templates will be available to any user who runs `massoh update` /
`massoh install` after the release. No separate install step is needed.
Rationale: CHARTER.md §5 versioning policy ("bump on any change to the install/uninstall
contract"); `01_product_scope.md` §Version note.

---

## 4. Required tests

All tests use the existing harness (`test/run.sh`) with temp repos (`TMP`), consistent with
the T1–T-meta patterns. No bats required. New tests are T16a–T16r (18 checks). Current
suite: 204. Target after this feature: **204 + 18 = 222** (exceeds the ≥213 floor from
`01_product_scope.md` AC11, giving margin for sub-tests added at implementation time).

### T16 setup helper (to be defined by implementer)
```
mkgaterepo()  — creates a temp git repo with .massoh marker; optionally calls massoh gate on
mkgatepacket() — creates .agent_tasks/<name>/04_implementation_packet.md in a repo
```

### T16a — `massoh gate on` creates hook and CI template in a Massoh git repo
Assert: `.git/hooks/pre-push` exists and is executable; `.github/workflows/massoh-gate.yml` exists.

### T16b — `massoh gate on` is idempotent (run twice, same result, exit 0)
Assert: second run exits 0; hook file content unchanged (md5sum before == md5sum after); no
duplicate Massoh marker blocks in the hook file.

### T16c — `massoh gate on` does not overwrite a pre-existing user hook
Setup: write a pre-existing `.git/hooks/pre-push` with unique sentinel content before running
`massoh gate on`. Assert: original sentinel content still present in the file after `gate on`
(not clobbered); Massoh marker block also present.

### T16d — `massoh gate off` removes the hook block and preserves pre-existing user content
Setup: pre-existing hook content + `massoh gate on` → then `massoh gate off`. Assert: Massoh
marker lines absent; pre-existing sentinel content still present (NOT deleted).

### T16e — `massoh gate off` is a no-op when gate was never installed
Assert: exit 0; no error on stderr; hook file unchanged (or still absent).

### T16f — checker blocks push on non-exempt path with no packet
Setup: invoke `scripts/massoh-gate-check` directly with a non-exempt path on stdin and no
`.agent_tasks/*/04_implementation_packet.md` present. Assert: exit 1; stderr or stdout
contains "no approved 04_implementation_packet.md".

### T16g — checker passes push when packet exists
Setup: same as T16f but with `.agent_tasks/TASK-test/04_implementation_packet.md` present.
Assert: exit 0.

### T16h — checker passes push when all paths are exempt (markdown + .agent_tasks only)
Setup: invoke checker with only `.md`-matching paths and `.agent_tasks/` paths; no packet.
Assert: exit 0.

### T16i — checker passes on AGENT_SYNC.md, memory/ paths, .github/ paths (all exempt)
Setup: provide `AGENT_SYNC.md`, `memory/MEMORY.md`, `.github/workflows/some.yml` as changed
paths; no packet. Assert: exit 0.

### T16j — `MASSOH_GATE_OVERRIDE=1` causes exit 0 with warning
Setup: non-exempt path, no packet, `MASSOH_GATE_OVERRIDE=1` set in environment. Assert: exit 0;
output contains "OVERRIDE active".

### T16k — `--no-verify` bypass is unblocked (hook not invoked by git)
Setup: install gate in a temp repo; commit a non-exempt file without a packet; run
`git push --no-verify` to a bare remote. Assert: push exits 0 (git did not invoke the hook).
This is standard git behavior; the test confirms the hook file does not interfere with
`--no-verify`.

### T16l — first-push null-SHA degrades to exit 0
Setup: invoke checker with null SHA (`0000000000000000000000000000000000000000`) as the
remote ref in the pre-push stdin payload. Assert: exit 0 (degrade, not crash).

### T16m — empty diff (CI mode, no changed files) exits 0
Setup: invoke `scripts/massoh-gate-check --ci <base-ref>` in a temp repo where
`git diff --name-only <base-ref>...HEAD` returns zero lines. Assert: exit 0.

### T16n — `massoh gate on` fails outside a git repo or non-Massoh project
Setup: run `massoh gate on` in a plain temp directory (no `.git`, no `.massoh`). Assert:
exit 1 with a message; no hook file created.

### T16o — checker rejects mix of exempt + non-exempt paths when no packet
Setup: invoke checker with both `.md` paths and a `bin/massoh`-like path; no packet.
Assert: exit 1 (non-exempt path overrides the exempt ones).

### T16p — CI mode checker blocks on non-exempt path without packet; passes with packet
Setup: temp git repo with a commit adding `bin/something`; invoke checker with `--ci <base>`.
(a) No packet: assert exit 1. (b) Packet present: assert exit 0. Two sub-checks.

### T16q — `massoh gate off` in repo where only the hook exists (no CI file): exits 0 cleanly
Assert: exit 0; no crash on partial state.

### T16r — safety-critical files unchanged by all T16 checks
Mirror the T11i / T15l pattern: capture `md5sum` of `bin/massoh` and `manifest.yml` before
T16 suite; assert checksums unchanged after all T16 checks complete.

---

## 5. Rollback plan

1. **Per-repo rollback:** `massoh gate off` in any repo where the gate was installed. This
   removes the hook block and exits 0. The CI workflow file remains on disk; owner deletes
   `.github/workflows/massoh-gate.yml` if desired (Massoh never deletes user-tracked files).
2. **Code rollback:** revert the PR that ships v0.9.0. Users on the old version (v0.8.0) are
   unaffected — `massoh gate` does not exist in v0.8.0, so old installs have no gate verb and
   no hooks. The new templates copied into `~/.claude/agent-os/templates/` by `massoh install`
   are inert (templates only; they do not auto-run). No migration step needed.
3. **Backward-compat guarantee:** a user who ran `massoh gate on` with v0.9.0 and then reverts
   to v0.8.0 via `massoh update` will find that `massoh gate off` no longer exists. They can
   manually remove the Massoh block from `.git/hooks/pre-push` by deleting lines between
   `# massoh-gate:start` and `# massoh-gate:end`. This must be documented in the `gate --help`
   output or in a comment in the hook file itself.

---

## 6. Approval decision

### Backend/service impact
No server component. The gate is pure bash + git hooks + CI YAML. No network calls, no LLM
invocations, no external services.

### Client/app impact
No client. The `massoh gate` verb is a new per-repo CLI command. Existing `massoh` verbs are
unaffected. Existing repos are unaffected until `massoh gate on` is run.

### API impact
The `manifest.yml` ↔ `bin/massoh` contract seam (CHARTER.md §3) is extended — new templates
added to `project_scaffold`. Both sides must ship together in one PR (G10). No existing
contract entry is modified.

### DB/migration impact
No database. No migration. New templates are additive. The hook is a per-repo ephemeral artifact
with no global footprint. Backward-compatible: v0.8.0 installs are unaffected.

### LLM/prompt impact
Zero. The checker is a deterministic bash script. No LLM call, no `claude -p`, no model spend.
Safety rules fully intact.

### Safety/guardrail risks
The two safety-critical files (`bin/massoh`, `manifest.yml`) are touched. Owner sign-off is
required and is the gate on issuing `04_implementation_packet.md`. All 14 conditions (G1–G14)
address the specific risks enumerated above.

### Expansion/localization risks
None. The checker output is English CLI strings for a developer tool (no locale dimension,
confirmed in `01_product_scope.md` §Target segment). The checker script carries no harness
assumption; when multi-harness lands, it is portable as-is (no `.claude/` reference in the
checker).

### Required tests
T16a–T16r (18 checks). Total target: 222.

### Rollback plan
Stated in §5 above.

---

## APPROVED: CONDITIONAL YES

**This task is CONDITIONALLY APPROVED for implementation — blocked pending owner sign-off on
editing `bin/massoh`.**

This mirrors the exact precedent in the decision log for every prior `bin/massoh` change:

> "CONDITIONAL YES — blocked pending owner sign-off on `bin/massoh`"
> (Decision log rows: 2026-06-16, 2026-06-17 massoh-learn, 2026-06-17 efficiency-v2,
> 2026-06-17 massoh-ledger, 2026-06-17 massoh-meta)

**No `04_implementation_packet.md` may be issued until the owner's sign-off is on record in
`AGENT_SYNC.md`.**

When the owner signs off, the implementer must:
1. Satisfy all 14 mandatory conditions (G1–G14) — each is independently checkable.
2. Deliver 18 new bats-style tests (T16a–T16r) bringing the suite total to ≥222.
3. Ship `bin/massoh` + `manifest.yml` + new scripts/templates in one PR.
4. Bump `VERSION` to `0.9.0`.
5. Confirm that all 204 existing tests remain green before opening the PR.
