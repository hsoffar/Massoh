# 06 — Review Result: license-to-code gate (v0.9.0)

- **Task ID:** TASK-2026-06-19-license-gate
- **Date:** 2026-06-19
- **Reviewer:** massoh-reviewer-qa
- **Verdict:** APPROVE

---

## Verdict summary

All 14 conditions G1–G14 independently verified (line references below). Test suite run
independently: **236/236 green** (was 204 baseline; 32 new assertions across 18 T16 specs).
Zero regressions. Scope is clean. Safety-critical files untouched by any existing verb.

---

## 1. G1–G14 independent verification

All line references verified in the actual source files, not taken from the handoff.

**G1 — `set -euo pipefail` in all new bash files; guarded fallible calls**
- `scripts/massoh-gate-check` line 8: `set -euo pipefail` confirmed.
- `templates/massoh-pre-push` line 8: `set -euo pipefail` confirmed.
- Every `grep`/`find`/`git` call uses `|| true` or `if` guard: lines 43, 75, 92, 124 in
  `massoh-gate-check`; `check_paths()` uses `if ! is_exempt` pattern; `has_packet()` wrapped
  in `if`.
- SATISFIED.

**G2 — Builtins only; no jq/python/node/curl/wget**
- Grep of both new bash files for `jq`, `python`, `node`, `curl`, `wget` returned zero hits.
- `massoh-gate-check`: uses only `bash`, `git`, `find`, `grep`, `printf`, `awk`, `case`.
- `templates/massoh-pre-push`: uses only `bash`, `git`, `printf`.
- `templates/massoh-gate.yml`: CI step is `bash scripts/massoh-gate-check --ci …`; no extra
  tool installation step in the workflow.
- SATISFIED.

**G3 — Hook install create-if-missing; append-safe with namespace markers**
- `bin/massoh` lines 1050–1064: three-branch conditional logic verified:
  - G3a (hook absent, line 1050): `cp … "$hook"` then `chmod +x` — creates from template.
  - G3b (marker present, line 1055): `grep -qF "$GATE_MARKER_START"` guard — prints "already
    installed", no write.
  - G3c (present, no marker, line 1062–1063): `printf '\n' >> "$hook"` then
    `grep -v '^#!/usr/bin/env bash' … >> "$hook"` — append-only, shebang stripped to avoid
    duplication.
- The `>` operator does not appear on the hook variable in any path. CONFIRMED: never truncates.
- SATISFIED.

**G4 — `gate off` strips only Massoh-namespaced block via awk; mirrors `remove_block()`**
- `bin/massoh` lines 1097–1111: awk pattern:
  `awk -v s="$GATE_MARKER_START" -v e="$GATE_MARKER_END" 'index($0,s){skip=1} !skip{print} index($0,e){skip=0}'`
  — identical to `remove_block()` at lines 51–54.
- Writes to `"$hook.massoh-tmp"` then either removes (G3a path: remaining content is only
  shebang or blank) or `mv` back (G3c path: pre-existing content preserved).
- Absent/unmarked hook: no-op exit 0 (lines 1089, 1093).
- SATISFIED.

**G5 — Glob-safe path matching via `case`; `find` guarded with `2>/dev/null`**
- `scripts/massoh-gate-check` lines 22–35: `is_exempt()` uses `case "$path" in … esac` — string
  pattern matching, not filesystem glob expansion.
- `has_packet()` line 43: `find .agent_tasks -name "04_implementation_packet.md" 2>/dev/null |
  grep -q .` wrapped in `if` block.
- `git diff` calls at lines 75, 92, 124 all use `2>/dev/null || true`.
- SATISFIED.

**G6 — Exempt list exactly matches `01_product_scope.md` §3**
- `scripts/massoh-gate-check` lines 24–34: 11 entries verified:
  `*.md`, `.agent_tasks/*`, `agent-project/*`, `memory/*`, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`,
  `.massoh`, `LICENSE`, `.gitignore`, `.gitattributes`, `.github/*`.
- Cross-checked against `04_implementation_packet.md` §Scope "Exempt paths": exact match.
  No additions, no omissions.
- SATISFIED.

**G7 — Null-SHA / first-push / empty-diff degrade to exit 0**
- `scripts/massoh-gate-check` line 67: `NULL_SHA="0000000000000000000000000000000000000000"`.
- Line 72: remote_sha null check → uses `git diff-tree --no-commit-id -r --name-only` fallback
  or `continue` (exit 0) if empty.
- Line 86: local_sha null check (deleted ref) → `continue`.
- Lines 93–94: empty `paths` → `continue`.
- `run_ci()` lines 124–127: `|| true` + empty-string guard → `exit 0`.
- SATISFIED.

**G8 — Override is the FIRST statement; exits 0 unconditionally when set**
- `scripts/massoh-gate-check` lines 10–14: immediately after `set -euo pipefail` (line 8) and
  before any function definitions or other executable statements:
  ```
  [ "${MASSOH_GATE_OVERRIDE:-}" = "1" ] && {
    printf '[massoh-gate] OVERRIDE active …'
    exit 0
  }
  ```
- No `git`, `find`, or `diff` call precedes this. CONFIRMED first statement.
- SATISFIED.

**G9 — CI template path is repo-root-relative and consistent**
- `templates/massoh-gate.yml` line 25: `bash scripts/massoh-gate-check --ci
  "${{ github.event.pull_request.base.sha }}"`.
- Path `scripts/massoh-gate-check` is relative to the repo root (the CWD after
  `actions/checkout` in GitHub Actions). No absolute path or Massoh-repo-specific path.
- SATISFIED.

**G10 — manifest.yml updated in same commit as templates; hook location commented**
- `manifest.yml` lines 36–38: comment clarifying `.git/hooks/pre-push` is NOT listed in manifest
  (per-repo ephemeral artifact). CONFIRMED.
- `manifest.yml` lines 51–54: `massoh-gate.yml` listed under `create_if_missing` with inline
  comment "installed by `massoh gate on` (not by `massoh on`)"; `massoh-pre-push` similarly
  commented. CONFIRMED in same working-tree commit.
- Both new template files and manifest.yml changed together in the same working tree. CONFIRMED.
- Note (non-blocking): the `massoh-gate.yml` entry appears under `create_if_missing` in the YAML
  schema while its inline comment explicitly states it is NOT installed by `massoh on`. This is
  potentially confusing documentation, but `cmd_on` does NOT parse the YAML at runtime (it has
  hard-coded `scaffold()` calls at lines 102–112 that do not include `massoh-gate.yml`). There is
  zero runtime impact. See non-blocking finding NB-1 below.
- SATISFIED (condition met; documentation note is non-blocking).

**G11 — `gate on` / `gate off` idempotent**
- `_gate_on` G3b path (line 1055): second `gate on` skips write, prints "already installed",
  exits 0. T16b confirms md5sum of hook unchanged on second run.
- `_gate_off` lines 1089–1094: absent hook or no marker → prints "nothing to remove", exits 0.
  T16e confirms no-op when never installed.
- SATISFIED.

**G12 — `gate on` requires git repo AND Massoh project**
- `bin/massoh` lines 1040–1043:
  ```
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || die "gate on: not inside a git repository."
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } || die "gate on: not a Massoh project (run: massoh on)."
  ```
- Both guards fire before any hook-write. T16n verifies both failure paths.
- SATISFIED.

**G13 — `gate` in dispatch case + usage message; `cmd_gate` dies on unknown args**
- `bin/massoh` line 1158: `gate)      shift || true; cmd_gate "$@" ;;` — confirmed in dispatch.
- `bin/massoh` line 1162: usage string includes `gate` among verbs.
- `cmd_gate()` lines 1029–1035: `on`/`off` cases; `*) die "gate: usage: massoh gate on|off" ;;`
- SATISFIED.

**G14 — VERSION 0.9.0**
- `VERSION`: contains `0.9.0` (confirmed by independent read).
- `CHANGELOG.md`: `## [0.9.0] - 2026-06-19` entry at top, before `[0.8.0]`.
- SATISFIED.

---

## 2. Test results (independently run)

Command: `bash test/run.sh 2>&1`

Result (verbatim final line): `ALL GREEN — 236 checks passed.`

- Baseline (pre-feature): 204 checks.
- New assertions: 32 (T16a–T16r, 18 test specs as required, some with multiple assertions).
- Target from `04_implementation_packet.md`: ≥222. Actual: 236. EXCEEDS TARGET.
- Zero FAIL lines in output.

### T16c substantive assertion verified

T16c (`test/run.sh` lines 1073–1080): writes sentinel content `# SENTINEL-UNIQUE-CONTENT-T16c`
to `.git/hooks/pre-push` BEFORE calling `massoh gate on`, then asserts:
1. `grep -q 'SENTINEL-UNIQUE-CONTENT-T16c'` — sentinel still present.
2. `grep -q 'massoh-gate:start'` — Massoh block also appended.

This exercises the real G3c code path (append). NOT a stub.

### T16d substantive assertion verified

T16d (`test/run.sh` lines 1082–1090): pre-existing hook + `gate on` + `gate off`, then asserts:
1. `! grep -q 'massoh-gate:start'` — Massoh block removed.
2. `grep -q 'SENTINEL-UNIQUE-CONTENT-T16d'` — user sentinel still present.

This exercises the real G4 awk strip path. NOT a stub.

### T16r substantive assertion verified

T16r (`test/run.sh` lines 1035–1037, 1229–1233): captures `md5sum` of `bin/massoh` and
`manifest.yml` BEFORE the T16 suite begins; re-captures AFTER the final T16 check; asserts
checksums unchanged. Uses real `md5sum` invocations. NOT a stub.

---

## 3. Scope discipline

- `git diff HEAD --name-only` (changed tracked files): `AGENT_BACKLOG.md`, `AGENT_SYNC.md`,
  `CHANGELOG.md`, `VERSION`, `agent-project/NOW_NEXT_LATER.md`, `bin/massoh`, `manifest.yml`,
  `test/run.sh`.
- New untracked files in scope: `scripts/massoh-gate-check`, `templates/massoh-gate.yml`,
  `templates/massoh-pre-push`, `.agent_tasks/TASK-2026-06-19-license-gate/05_implementation_handoff.md`.
- Untracked files out of scope (not part of this PR — owner files predating this task):
  `.agent_tasks/TASK-2026-06-19-massoh-board/`, `agent-project/briefs/`, `deck/`. These have
  zero git history and are clearly owner-side materials not created by the implementer; they will
  not be staged in this PR.
- `bin/massoh` diff: only deletion is the old usage string (no `gate` verb); additions are
  `GATE_MARKER_START`/`GATE_MARKER_END` constants, `cmd_gate()`, `_gate_on()`, `_gate_off()`,
  dispatch `gate)` case, updated usage string. No existing verb (`cmd_on`, `cmd_off`,
  `cmd_install`, `cmd_uninstall`, `remove_block`, etc.) was altered.
- Deferred items (pre-commit hook, packet-path matching, issue-link parsing, auto-wire gate on
  into cmd_on, auto-logging overrides): NONE of these appear in the implementation. CLEAN.

---

## 4. Safety-critical invariants

- `BLOCK_START`/`BLOCK_END` and `templates/CLAUDE.global-block.md`: untouched.
- `templates/CLAUDE.project.template.md`: untouched.
- Global `cmd_install`/`cmd_uninstall`/`add_block`/`remove_block`/`backup_claude`: zero changes
  confirmed by `git diff HEAD -- bin/massoh` showing only additions + one usage-string deletion.
- `~/.claude/` global footprint: not touched by any new code path (`_gate_on`/`_gate_off` operate
  on the local repo's `.git/hooks/` and `.github/workflows/`, never on `~/.claude/`).
- No secrets, no network calls, no LLM invocations in new code.
- T16r confirms `bin/massoh` and `manifest.yml` md5sums unchanged across the T16 test suite
  (tests do not self-modify safety-critical files).

---

## 5. Blocking findings

None.

---

## 6. Non-blocking findings

**NB-1 — `manifest.yml` documentation ambiguity: `massoh-gate.yml` under `create_if_missing`**

`manifest.yml` line 52 lists `{ dest: .github/workflows/massoh-gate.yml, source: templates/massoh-gate.yml }` under `project_scaffold.create_if_missing`. The inline comment (line 51) says "installed by `massoh gate on` (not by `massoh on`)". This is correct at the code level — `cmd_on` does NOT parse the YAML, so it will not scaffold `massoh-gate.yml`. However, a future implementer reading only the manifest YAML (without the comment) could infer that `massoh on` will install the CI file, which is incorrect. The 04 packet required this placement; the comment mitigates the confusion. Owner may wish to move this entry to a separate `gate_templates:` section in a future cleanup task to make the intent unambiguous.

No code change needed; no runtime impact; documentation note only.

**NB-2 — T16n variable naming: `G16n_nogit` is actually a git repo**

`test/run.sh` line 1186: `G16n_nogit="$TMP/g16n_nomassoh"` — the variable name says "nogit" but the directory IS initialized as a git repo (no `.massoh` / `agent-project/`). The assertions use `G16n_nogit` consistently, so there is no test bug. The variable name is misleading. No fix required.

---

## 7. Hidden scope concerns

None. The five explicitly deferred items (pre-commit, packet-path matching, issue parsing, auto-wire, override logging) are absent from the implementation. No unrequested features were added.

---

## 8. Guardrails / POSIX invariants

- POSIX bash + `set -euo pipefail` in all new bash files: CONFIRMED.
- No non-portable deps: CONFIRMED (G2).
- Idempotent: CONFIRMED (G11).
- Additive + reversible: gate on/off are per-repo opt-in; existing repos unaffected until
  `gate on` is called; `gate off` fully reverses `gate on` (hook stripped or removed; CI file
  left for owner per NON_NEGOTIABLES §Prohibited).
- Zero LLM spend: CONFIRMED (checker is deterministic bash).
- No hard-delete of user files: `gate off` strips the Massoh marker block and, only when the hook
  was created from scratch by Massoh, removes the entire file. Pre-existing user hooks are never
  deleted (only the Massoh block is stripped). CI file is never deleted. CONFIRMED.

---

## 9. Owner decision needed

None.

---

## Decision

**APPROVE.** All 14 conditions G1–G14 independently verified with specific file:line evidence.
Test suite independently run: 236/236 green. Scope is clean. Safety-critical files untouched by
any existing verb logic. Two non-blocking documentation notes (NB-1, NB-2) require no code change.
Ready for owner PR merge.
