# 03 — Architecture & Safety Assessment
# TASK-2026-06-19-modularize-bin: Modularize bin/massoh → sourced verb files

**Assessor:** massoh-architecture-safety
**Date:** 2026-06-19
**Verdict:** APPROVED (batch-authorized; see condition §Authorization below)
**Implementation start:** BLOCKED until feat/massoh-board (board #1) merges to main

---

## 0. Authorization on record

Owner **batch-authorized** `bin/massoh` edits for 24h queue items #3–#11 on 2026-06-19
(AGENT_SYNC.md decision log, last row). This assessment is the required arch/safety gate;
no fresh per-item sign-off is needed. Implementation proceeds to `04_implementation_packet.md`
immediately after this file is written and after board #1 merges.

---

## 1. Backend / service impact

Pure-bash CLI tool; no server or daemon. The only "backend" is the installed copy of Massoh
in `~/.claude` (or `$CLAUDE_CONFIG_DIR`). The blast radius of a wrong path resolution in the
sourced verb files is that **an installed user gets a broken CLI** — every `massoh <verb>` call
silently no-ops or hard-errors because the sourced file is not found.

The refactor adds a new directory `lib/verbs/` to the Massoh source tree. The implementer must
ensure the install path for `lib/verbs/` is wired so that the post-install `bin/massoh` (the
copy that lives in `$PATH` or as a symlink) can locate its verbs under `~/.claude/agent-os/lib/verbs/`
or equivalent. This is the highest-risk surface — see MB1 and MB2.

---

## 2. Client / app impact

Users invoke `massoh <verb>` directly. They must see no behavioral difference: same stdout,
same stderr, same exit codes on all verbs. The refactor is invisible to them if done correctly.
If done incorrectly (wrong path, missing source) the CLI breaks for every verb that was
extracted — a catastrophic regression.

---

## 3. API impact

No external API. The internal API contract seam is `manifest.yml` ↔ `bin/massoh`
(CHARTER.md §3). The refactor adds `lib/verbs/` files that must be listed in `manifest.yml`
so `massoh install` copies them and `massoh uninstall` removes exactly what was installed.
This is a contract change: **both sides must ship together in the same PR** (manifest.yml
updated to list the new dir, cmd_install updated to wire it, cmd_uninstall / cmd_doctor updated
to verify it). See MB2 and MB4.

---

## 4. DB / migration impact

No database. The only persisted data is the installed layout in `~/.claude`. Migration
implications:

- A user who installed Massoh before this PR will not have `~/.claude/agent-os/lib/verbs/`.
  After `massoh update && massoh install` they will have the new layout.
- For the one-release backward-compatibility window required by NON_NEGOTIABLES §Data + migration
  policy: the uninstall path must continue to clean up the old layout (no stale `lib/verbs/`
  left behind if the user uninstalls after upgrading). This is automatically satisfied if
  `cmd_uninstall` removes `~/.claude/agent-os/` wholesale (which it currently does via
  `rm -rf "$CLAUDE_DIR/agent-os"`), since `lib/verbs/` lives inside `agent-os/`. Confirm
  at implementation time that no separate removal step is needed (condition MB4).

---

## 5. LLM / prompt impact

None. No prompts, no LLM calls, no advisory output. Not applicable.

---

## 6. Safety / guardrail risks

### Risk 1 (HIGHEST): Installed-layout sourcing path
`bin/massoh` when installed is invoked as `~/.local/bin/massoh` or a symlink somewhere on
`$PATH`. It is NOT invoked from the Massoh source repo. The current bootstrap line:

    SELF="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

follows `readlink -f` to resolve symlinks before computing `SELF`. This correctly handles the
symlinked-invocation case for the current monolithic file. The new sourcing of
`lib/verbs/<verb>.sh` must use the SAME `$MASSOH_HOME` variable (which resolves to the
install root, not the clone root when invoked after install). Getting this wrong means the
installed CLI breaks entirely.

### Risk 2: Missing lib file fails silently instead of loudly
Under `set -euo pipefail`, a `source` that finds its target will succeed; a sourced file
that is absent with `source path/to/missing.sh` will fail with "No such file or directory"
and exit 1 — which is LOUD and correct. However, if the implementer uses a conditional
`[ -f ... ] && source ...` pattern, a missing verb file silently skips the verb, causing a
confusing "unknown command" error rather than a clear "lib file missing" error. The pattern
must be unconditional `source` (or `. `) so that set -e catches a missing file loudly.

### Risk 3: Helper definition order under sourcing
The bootstrap section of `bin/massoh` (lines 1–56) defines `say`, `die`, `mver`, `msha`,
`backup_claude`, `wire`, `block_present`, `add_block`, `remove_block` before any `cmd_*`.
If verb files are sourced before these helpers are defined, any verb that calls `say()` or
`die()` at source-time (not just at call-time) will fail. The sourcing loop must come AFTER
the bootstrap section and BEFORE the dispatch `case`.

### Risk 4: set -euo pipefail propagation into sourced files
Sourced files inherit `set -euo pipefail` from the parent shell. This is correct behavior
and must be preserved. The verb files must not contain bare-error-exit patterns that rely on
a permissive shell. No `set +e` in sourced files.

### Risk 5: install/uninstall/block helpers extracted — scope creep risk
If the implementer decides to move `backup_claude`, `wire`, `add_block`, `remove_block`,
`block_present`, `scaffold`, and the associated `cmd_install` / `cmd_uninstall` / `cmd_on`
/ `cmd_off` / `cmd_enable` / `cmd_disable` into `lib/verbs/`, those files become
safety-critical themselves. Moving them increases the blast radius of a sourcing failure
from "one feature verb broken" to "install/uninstall broken" — the most dangerous outcome.

### Risk 6: GATE_MARKER_START / GATE_MARKER_END globals
`cmd_gate` depends on the global variables `GATE_MARKER_START` and `GATE_MARKER_END` defined
at lines 1027–1028. If `gate.sh` is sourced before those globals are set, the functions will
use empty strings. These globals must remain in `bin/massoh` or be defined before the source
of `gate.sh`.

### Risk 7: Parallel arrays in cmd_board
`_BOARD_IDS`, `_BOARD_TITLES`, etc. are script-level globals initialized by `_board_build_model`
and consumed by `_board_push_plane` and `_board_print_table`. If `board.sh` is sourced and
these declarations are inside the sourced file, they must be visible to all three functions.
Since bash sources files into the current scope, this is safe as long as all three functions
and the global arrays live in the same sourced file (or in bin/massoh). Splitting
`_board_build_model` into one file and `_board_push_plane` into another would break the globals
unless explicitly managed.

---

## 7. Expansion / localization risks

CHARTER.md §2 expansion principle: no hardcoding of today's single-valued assumptions.
This refactor is purely structural and introduces no new locale, region, or segment assumptions.
No expansion risk from this change itself. However, the `lib/verbs/` path structure must not
hard-code any OS-specific path separator or assume a specific install prefix — `$MASSOH_HOME`
must remain the sole indirection.

---

## 8. Recommended split: what moves vs what stays in bin/massoh

**Stays in bin/massoh (bootstrap + safety-critical core):**

- Lines 1–8: shebang, `set -euo pipefail`, `SELF` / `MASSOH_HOME` / `CLAUDE_DIR` / globals
  (`BLOCK_START`, `BLOCK_END`, `LINK`)
- Lines 15–18: `say`, `die`, `mver`, `msha` (tiny helpers used by every verb)
- Lines 20–56: `backup_claude`, `wire`, `block_present`, `add_block`, `remove_block`
  (NON_NEGOTIABLES §safety-critical; install/uninstall/block logic stays in bin/massoh)
- Lines 58–95: `cmd_install`, `cmd_update`, `cmd_enable`, `cmd_disable`
  (directly call the safety-critical helpers above; keep co-located)
- Lines 98–120: `cmd_on`, `scaffold`
  (touches user repos; create-if-missing logic; safety-critical by policy)
- Line 120: `cmd_off`
- Line 122: `cmd_version`
- Lines 124–163: `cmd_status`, `cmd_doctor`
  (verify the install; closely coupled to the manifest contract — stay)
- Lines 1625–1633: `cmd_uninstall` (safety-critical; stays)
- Lines 1027–1028: `GATE_MARKER_START` / `GATE_MARKER_END` globals (stay in bin/massoh)
- Lines 1636–1662: `for a` arg parse + `case` dispatch block (stays — it is the entry point)
- Sourcing loop for `lib/verbs/` (new, added in bin/massoh after bootstrap, before dispatch)

**Moves to lib/verbs/<verb>.sh (additive feature verbs — safe to extract):**

| File | Functions | Current line range |
|---|---|---|
| `lib/verbs/discover.sh` | `cmd_discover` | 166–196 |
| `lib/verbs/review.sh` | `cmd_review` | 199–289 |
| `lib/verbs/standup.sh` | `cmd_standup` | 292–325 |
| `lib/verbs/plan.sh` | `cmd_plan` | 328–355 |
| `lib/verbs/learn.sh` | `cmd_learn` | 359–533 |
| `lib/verbs/recommend.sh` | `cmd_recommend` | 541–696 |
| `lib/verbs/ledger.sh` | `cmd_ledger` | 700–790 |
| `lib/verbs/meta.sh` | `cmd_meta` | 795–1020 |
| `lib/verbs/gate.sh` | `cmd_gate`, `_gate_on`, `_gate_off` | 1022–1120 |
| `lib/verbs/board.sh` | `cmd_board`, `_board_*` helpers + globals | 1122–1618 |
| `lib/verbs/cron.sh` | `cmd_cron` (one line) | 1621 |
| `lib/verbs/work.sh` | `cmd_work` (one line) | 1623 |

Note: `gate.sh` depends on `GATE_MARKER_START` and `GATE_MARKER_END`. Those two lines (1027–1028)
must either stay in `bin/massoh` (defined before the sourcing loop) or be defined at the top of
`gate.sh`. Either placement is acceptable as long as the globals are set before `_gate_on` and
`_gate_off` execute. Recommendation: keep them in `bin/massoh` alongside the other globals.

**Rationale for this split:**
The install/uninstall/block/backup surface is what NON_NEGOTIABLES explicitly designates as
safety-critical. Moving it introduces no parallelism benefit (it is already low-churn) and
maximizes blast radius if the sourcing fails. The additive feature verbs (review, learn, meta,
board, etc.) are the high-churn surface that the 24h queue touches — extracting only these
achieves the parallelization goal at minimum risk.

---

## 9. Mandatory conditions (MB1–MB8)

### MB1 — Symlink-safe self-location (SOURCING ROBUSTNESS)
`bin/massoh` already resolves its own location via `readlink -f "${BASH_SOURCE[0]}"` at
line 8. The sourcing loop for `lib/verbs/` MUST derive the verb directory from `$MASSOH_HOME`
(which is already correctly set by line 9) — never from `$PWD`, never from a relative path,
never from `dirname "$0"` alone. The pattern must be:

    for _verb_file in "$MASSOH_HOME/lib/verbs/"*.sh; do
      [ -f "$_verb_file" ] || { printf 'massoh: missing lib file: %s\n' "$_verb_file" >&2; exit 1; }
      # shellcheck source=/dev/null
      . "$_verb_file"
    done

The `[ -f ... ] || exit 1` check before sourcing satisfies MB3 (loud failure on missing file).
This exact pattern is the condition — no variant is acceptable.

**Verification:** after install, run `massoh status` from a directory unrelated to the clone.
The verb must resolve correctly. Run via a symlink too (see T-MB-symlink).

### MB2 — Install wires lib/verbs/ and manifest.yml lists it (INSTALL-PATH BLAST RADIUS)
`cmd_install` (bin/massoh lines 58–71) copies engine artifacts via the `for p in ...` loop.
The implementer MUST add `lib/verbs` to that loop:

    for p in OPERATING_SYSTEM.md policies templates docs manifest.yml VERSION lib/verbs; do

`manifest.yml`'s `global_install` section already has a comment:
"NOTE: the exact payload is the `for p in …` list in bin/massoh:cmd_install — keep the two in sync."
The manifest must gain an entry documenting `lib/verbs/` in `global_install` (kind: dir, source: lib/verbs,
dest: ~/.claude/agent-os/lib/verbs/). Both changes ship in the same commit.

**Backward-compat:** `cmd_uninstall` currently runs `rm -rf "$CLAUDE_DIR/agent-os"` which
removes the entire `agent-os/` tree including `agent-os/lib/verbs/`. This is already sufficient
for one-release backward compatibility — no separate removal step needed. Confirm in PR.

**Verification:** after install, `ls ~/.claude/agent-os/lib/verbs/` must show all verb files.
After uninstall, `ls ~/.claude/agent-os/` must fail (directory gone). Test IDs: T-MB-install-layout,
T-MB-uninstall-clean.

### MB3 — Loud failure if a lib file is missing (SOURCING ROBUSTNESS)
The sourcing loop must NOT use a conditional `&&` or `|| true` pattern that silently skips
a missing file. If `$MASSOH_HOME/lib/verbs/board.sh` does not exist, `bin/massoh` must
exit non-zero with a diagnostic message. The `[ -f ... ] || exit 1` guard in the MB1 pattern
satisfies this. Do not use `source "$f" 2>/dev/null || true`.

**Verification:** T-MB-missing-lib: remove one lib file after extraction; invoke `massoh status`;
assert exit non-zero and stderr contains "missing lib file".

### MB4 — cmd_doctor verifies lib/verbs/ presence (INSTALL CONTRACT LOCKSTEP)
`cmd_doctor` (lines 136–163) checks every artifact that `cmd_install` writes. After this
refactor, it must also check for `$CLAUDE_DIR/agent-os/lib/verbs/` (or individual verb files).
If `doctor` does not verify the new artifacts, drift will go undetected. Minimal check:

    if [ -d "$CLAUDE_DIR/agent-os/lib/verbs" ]; then say "  ok   agent-os/lib/verbs/"; else say "  MISS agent-os/lib/verbs/"; problems=$((problems+1)); fi

**Verification:** T-MB-doctor-detects-drift: install, then `rm -rf ~/.claude/agent-os/lib/verbs`
(simulated), run `doctor`; assert non-zero exit and "MISS" line.

### MB5 — Behavior invariance: byte-identical CLI output (REGRESSION BAR)
Before extraction: capture output of a fixed set of verbs:

    massoh help 2>&1       # the usage/error line from unknown-command dispatch
    massoh status 2>&1     # dynamic fields (version, sha) — capture format only
    massoh version 2>&1

After extraction: same commands must produce identical output (excluding dynamic timestamps,
commit SHAs, and version numbers which may differ only by VERSION bump). For non-dynamic verbs
(the "unknown command" usage line, the help text embedded in die()), output must be byte-identical.

**Verification:** T-MB-output-identical: capture before (on current branch HEAD) and after; diff;
assert empty diff for the usage/die string, assert format-identical for dynamic verbs.

### MB6 — No logic change: pure extraction only
The implementer is forbidden from making any edit beyond moving function bodies verbatim. This
includes:
- No renaming of variables, flags, or output strings
- No opportunistic cleanup of code style
- No adding or removing `|| true` guards
- No reordering of statements within a function
- No changes to the dispatch `case` block beyond adding the `source` loop

The reviewer must diff each `lib/verbs/<verb>.sh` against the corresponding lines in the
pre-refactor `bin/massoh` and confirm byte-for-byte equality of function bodies.

**Verification:** T-MB-no-logic-change: `git diff HEAD~1 -- bin/massoh lib/verbs/` in the
implementation PR; the reviewer confirms that every function body that moved is identical to
what was in bin/massoh on the base commit (feat/massoh-board HEAD).

### MB7 — Helpers defined before verbs at source time
The sourcing loop runs after the bootstrap section (helpers `say`, `die`, `mver`, `msha`,
`backup_claude`, `wire`, `block_present`, `add_block`, `remove_block`, `scaffold` defined in
bin/massoh). The sourcing loop must be placed AFTER line ~120 (after `cmd_off` and `scaffold`)
and BEFORE the `for a in "$@"` dispatch block at line ~1636. This preserves the current
execution order: helpers → verbs → dispatch.

**Verification:** syntax check all extracted files with `bash -n lib/verbs/<verb>.sh` (must
pass) AND source them in a subshell where the helpers are defined (must produce no errors).
Test ID: T-MB-source-order.

### MB8 — Full test suite green at current target (280 after board merges)
The implementation PR must include a run of `bash test/run.sh` showing **280/280** green (the
post-board count from the board task). This refactor adds no new features, so the test target
does not increase. The 280 tests exercise the full verb set; if any verb breaks due to the
extraction, the existing tests will catch it.

**Verification:** T-MB-suite: `bash test/run.sh` in CI; assert `0 failures` and `280 tests`
in final summary line.

---

## 10. Required tests (IDs + assertions)

All new tests are additions to `test/run.sh`. They do not replace any existing test. Target
after this task: **280 + 7 new = 287 tests** (7 new modularization-specific checks).

| ID | What it asserts |
|---|---|
| T-MB-symlink | Invoke `bin/massoh` via a symlink in `$TMP`; assert `massoh status` exits 0 and prints the version line. Confirms MB1 symlink-robustness. |
| T-MB-install-layout | Run `massoh install`; assert `$CC/agent-os/lib/verbs/` directory exists and contains at least one `.sh` file. Confirms MB2. |
| T-MB-uninstall-clean | Run `massoh install` then `massoh uninstall`; assert `$CC/agent-os` directory is gone (entire tree removed). Confirms MB2 backward-compat. |
| T-MB-doctor-detects-drift | Run `massoh install`; remove `$CC/agent-os/lib/verbs/`; run `massoh doctor`; assert non-zero exit and output contains "MISS". Confirms MB4. |
| T-MB-missing-lib | Remove one verb file from `lib/verbs/` in a scratch copy of the repo; invoke `bin/massoh status`; assert exit non-zero and stderr contains "missing lib file". Confirms MB3. |
| T-MB-output-identical | Invoke `massoh <unknown-verb>` before and after; diff the `die()` usage line; assert empty diff. Confirms MB5 for the non-dynamic output path. |
| T-MB-suite | `bash test/run.sh` exits 0 with `280 tests` and `0 failures` in the summary. Confirms MB8 (this is the existing suite run, already present; listed here as a named requirement). |

---

## 11. Rollback plan

1. The refactor lives on a dedicated branch (`feat/modularize-bin` or similar).
2. The PR is never auto-merged (owner merge only, per batch-authorization terms).
3. If the PR is merged and the install breaks:
   - `git revert <merge-commit>` on main restores `bin/massoh` to the monolithic form.
   - Users run `massoh update && massoh install` to re-install the reverted version.
   - The `rm -rf "$CLAUDE_DIR/agent-os"` in `cmd_install` (which runs before re-populating)
     ensures no stale `lib/verbs/` files remain from the failed version.
4. The one-release backward-compat window (NON_NEGOTIABLES §Data + migration) is automatically
   satisfied because `cmd_uninstall` removes `agent-os/` wholesale — no per-file cleanup needed.

---

## 12. Impact analysis — every file touched

| File | Change | Risk |
|---|---|---|
| `bin/massoh` | Remove 12 `cmd_*` / `_board_*` / `_gate_*` function bodies; add sourcing loop; keep bootstrap + safety-critical core | HIGH — safety-critical file; batch-authorized |
| `lib/verbs/discover.sh` | New file; contains `cmd_discover` verbatim | LOW |
| `lib/verbs/review.sh` | New file; contains `cmd_review` verbatim | LOW |
| `lib/verbs/standup.sh` | New file; contains `cmd_standup` verbatim | LOW |
| `lib/verbs/plan.sh` | New file; contains `cmd_plan` verbatim | LOW |
| `lib/verbs/learn.sh` | New file; contains `cmd_learn` verbatim | LOW |
| `lib/verbs/recommend.sh` | New file; contains `cmd_recommend` verbatim | LOW |
| `lib/verbs/ledger.sh` | New file; contains `cmd_ledger` verbatim | LOW |
| `lib/verbs/meta.sh` | New file; contains `cmd_meta` verbatim | LOW |
| `lib/verbs/gate.sh` | New file; contains `cmd_gate`, `_gate_on`, `_gate_off` verbatim | LOW-MEDIUM (gate logic touches git hooks) |
| `lib/verbs/board.sh` | New file; contains `cmd_board`, all `_board_*` helpers, parallel array globals verbatim | MEDIUM (network + secret handling; no behavior change) |
| `lib/verbs/cron.sh` | New file; contains `cmd_cron` (single line exec) | LOW |
| `lib/verbs/work.sh` | New file; contains `cmd_work` (single line exec) | LOW |
| `manifest.yml` | Add `lib/verbs/` entry to `global_install` section; add comment cross-reference | LOW-MEDIUM — safety-critical file (manifest ↔ bin/massoh lockstep) |
| `test/run.sh` | Add 7 new T-MB-* checks | LOW |
| `VERSION` | Bump (infrastructure change) | LOW |
| `CHANGELOG.md` | Append [new version] entry | LOW |

**Files that MUST NOT change:**
- `templates/CLAUDE.global-block.md`
- `templates/CLAUDE.project.template.md`
- `agent-project/NON_NEGOTIABLES.md`
- `agent-os/policies/*`
- Any existing test assertion in `test/run.sh` (no edits to existing tests, only additions)

---

## 13. Verdict

**APPROVED for implementation.**

Authorization: owner batch-authorized on 2026-06-19 (AGENT_SYNC.md decision log). No separate
per-item sign-off required. This assessment + reviewer-qa + green tests are the remaining gates.

**Implementation must NOT begin until feat/massoh-board merges to main** (the post-board
`bin/massoh` at lines 1–1662, including `cmd_board` at lines 1122–1619, is the source the
implementer must operate on). Arch-safety is read-only and proceeds now.

**Single highest risk:** MB2 — installed-layout sourcing path. When `bin/massoh` is invoked
after `massoh install`, it runs from a copy or symlink far from the source tree. The sourcing
loop must use `$MASSOH_HOME` (not a relative path) and `$MASSOH_HOME` must point to the
`agent-os/` directory as installed (i.e., `~/.claude/agent-os` after install). Confirm that
the `SELF` / `MASSOH_HOME` bootstrap logic (line 8–9) correctly resolves to the install
root when invoked via the installed PATH entry, not just when run from the clone.

**Conditions count:** 8 (MB1–MB8)
**Test target:** 287 (280 existing + 7 new T-MB-* checks)
**Recommended split:** keep safety-critical bootstrap + install/uninstall/block/on/off/status/doctor
in `bin/massoh` (~340 lines retained); extract 12 verb units to `lib/verbs/` (~1320 lines moved).
