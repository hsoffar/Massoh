# 03 — Architecture / Safety: `massoh board --local` renderer

**Task ID:** TASK-2026-06-19-board-renderer (24h queue #8)
**Agent:** massoh-architecture-safety
**Date:** 2026-06-19
**Mode:** ARCHITECTURE_SAFETY
**Sign-off basis:** Owner batch-authorization 2026-06-19 covers `bin/massoh`; `manifest.yml`
changes (if any) require lockstep and are covered by the same batch-auth scope (per precedent
from BG21/BG24 in TASK-2026-06-19-massoh-board). No new safety-critical file designation
introduced. No fresh per-change sign-off required.

---

## 1. Backend / service impact

The entire feature lives in `lib/verbs/board.sh` (a new `_board_emit_local` helper + a
`_board_emit_board_md` helper, both called from `cmd_board` when `--local` is parsed). No
backend, no service, no daemon.

`bin/massoh` dispatch: `board` already routes to `cmd_board "$@"`. The `--local` flag is parsed
inside `cmd_board` by the existing while-loop, exactly as `--dry-run` and `--no-push` are. No
change to `bin/massoh` dispatch is required unless `--out` is also parsed there — it is not; the
`--out` argument is consumed by the while-loop in `cmd_board` with a `shift` for the value. So
`bin/massoh` is likely unchanged.

## 2. Client / app impact

CLI only. The new flag `--local [--out <dir>]` adds output behavior; no existing invocation is
affected. `--push plane` is byte-identical (condition BR6). The usage/help string in `cmd_board`
must be updated to mention `--local` and `--out <dir>`.

## 3. API impact

No external API surface change. The Plane REST adapter (`_board_push_plane`) is not touched. No
contract change.

## 4. DB / migration impact

Two new output files: `agent-project/board.html` and `agent-project/BOARD.md`. They are
**generated artifacts** — overwriting them on re-run is correct behavior (same semantics as a
`massoh review --write` snapshot). No TSV/ledger touched. No migration needed. No backward-
compatibility concern; existing installs that never run `--local` see no file change.

`manifest.yml`: `board.html` and `BOARD.md` are runtime output artifacts, not scaffold files.
Precedent is `.env.massoh` and `.board-map.tsv` — both intentionally NOT in `manifest.yml`
(runtime artifacts). The same classification applies here. No `manifest.yml` change is needed
unless the owner decides these should be scaffold-listed; they should not be (they are generated
on demand, not created by `massoh on`).

## 5. LLM / prompt impact

None. No LLM call, no prompt, no agent file touched.

## 6. Safety / guardrail risks and conditions

### BR1 — Reuse `_board_build_model`; no second model builder
The `--local` path MUST call `_board_build_model "$repo"` to populate the eight `_BOARD_*`
arrays before emitting HTML or BOARD.md. A second, independent parser is prohibited. The
reviewer must grep for `_board_build_model` in `--local` call path and confirm no parallel data
gathering exists.

### BR2 — HTML injection escaping (highest risk)
Task titles (`_BOARD_TITLES[@]`), descriptions (`_BOARD_DESCS[@]`), task IDs, stage names, and
any other interpolated string MUST be HTML-escaped before insertion into the HTML template.
Required replacements (in order): `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`, `"` → `&quot;`.
Implementation: a pure-bash helper using `sed` (no jq, no external tools beyond standard POSIX
utils):

```
_board_html_escape() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}
```

This helper must be called for every field written into HTML markup. The reviewer must assert
that at least title, desc, task_id, stage, and last_agent pass through this helper before any
`printf` into the HTML buffer.

### BR3 — BOARD.md cell sanitization (pipe and newline injection)
Obsidian-Kanban markdown uses `|`-delimited table syntax and is newline-sensitive. Each cell
value written into BOARD.md must have `|` replaced with a safe substitute (e.g. `/`) and
embedded newlines stripped (replace `\n` with ` `). This mirrors the sanitization already
present in the Plane path for TSV fields (see `safe_task_id` in `_board_push_plane`). A
pure-bash helper or inline `sed`/`tr` is acceptable; no jq.

### BR4 — No jq on the `--local` path
The `--local` path must contain zero `jq` invocations. The existing `jq` guard at the top of
`cmd_board` must be relocated or made conditional: the guard must fire ONLY when `--push plane`
is active. Keeping the guard at the top of `cmd_board` unconditionally would force `jq`
installation even for `--local`, which violates the feature requirement.

Correct structure:

```
cmd_board() {
  # parse all flags first ...
  local push_plane=0 local_mode=0 out_dir="" ...
  while ...; do case "$1" in
    --push)   ...; push_plane=1 ;;
    --local)  local_mode=1 ;;
    --out)    shift; out_dir="${1:-}" ;;
    ...
  esac; shift; done

  # jq guard ONLY on the Plane path
  if [ "$push_plane" = 1 ]; then
    command -v jq >/dev/null 2>&1 \
      || die "massoh board: jq is required for --push plane ..."
  fi
  ...
}
```

The reviewer must `grep -n 'jq' lib/verbs/board.sh` and verify all `jq` references are inside
`_board_push_plane` or inside the `if [ "$push_plane" = 1 ]` block. Zero `jq` references
permitted in `_board_emit_local` or `_board_emit_board_md`.

### BR5 — Write location: default path and clobber policy
Default write targets: `agent-project/board.html` and `agent-project/BOARD.md`.

Policy:
- If the target file does not exist, create it (standard).
- If the target file exists AND contains the generator sentinel comment
  `<!-- massoh-generated -->` (for HTML) or `<!-- massoh:board-generated -->` (for BOARD.md,
  as a YAML front-matter comment `massoh_generated: true` or a first-line comment), overwrite
  it. The sentinel is written by the emitter on first creation; subsequent runs detect it and
  overwrite.
- If the target file exists AND does NOT contain the sentinel (i.e. it was hand-authored), the
  command MUST refuse to overwrite and print a clear error directing the user to `--out <dir>`
  to redirect output.
- `--out <dir>` overrides the default path; always writes/overwrites within the specified
  directory without the sentinel check (the user is explicitly redirecting).
- `mkdir -p` the target directory if it does not exist.

This policy prevents clobbering an `agent-project/BOARD.md` or `board.html` that a user may
have authored by hand.

### BR6 — `--push plane` byte-identical; no regression
The `_board_push_plane` function must not be modified. The existing `--no-push`, `--dry-run`,
and `--init-config` flows must be unchanged. The `--local` path is additive: it inserts a new
branch in `cmd_board` that returns early after emitting the two files. The set -euo pipefail
discipline in `lib/verbs/board.sh` (inherited from `bin/massoh`) must remain intact throughout
the new code.

### BR7 — No network, no secret reads on `--local`
The `--local` path must not invoke `curl`, must not source `.env.massoh` (which is only needed
for credentials), and must not read `PLANE_API_TOKEN` in any form. The config-loading block
(`. "$repo/.env.massoh"`) must remain conditional on the `push_plane` path or be guarded so it
is only executed when `push_plane=1`.

Note: `_board_build_model` reads `.agent_tasks/`, `AGENT_BACKLOG.md`, `AGENT_SYNC.md`, and
`ledger.tsv` — all local files, no secrets. This is safe and correct.

### BR8 — `set -euo pipefail` + `|| true` discipline
Every `grep`, `awk`, `sed`, `git`, and `find` call in the new helpers that may legitimately
produce no output must be guarded with `|| true`. In particular: the HTML-escape helper using
`sed` should degrade to empty string rather than hard-fail if the field is empty. All writes
(`>` and `>>`) to the output files must be under `set -euo pipefail` — a failed write aborts
cleanly.

---

## 7. Expansion / localization risks

No locale, region, or segment hard-coding. HTML is ASCII-safe markup; UTF-8 content from task
titles/descriptions passes through without transformation (only `&<>"` are escaped, which is
locale-neutral). BOARD.md is plain UTF-8 markdown. No risk to expansion principles. The
`--out <dir>` parameter makes the output location configurable; no path is hard-coded beyond the
default `agent-project/` prefix (which is a project structural constant, not a locale wedge).

---

## 8. Required tests

All tests are additions to `test/run.sh`. Target baseline: 327 checks (current post-fleet
baseline may be higher if #6 lands first — take the then-current baseline as `N`; target is
`N + 12` minimum).

**T-BR-1 — HTML escape: malicious title injection**
Create a task whose `00_request.md` heading is `# <script>alert("xss")</script> & "quoted"`.
Run `massoh board --local`. Assert `board.html` does NOT contain `<script>` literally and DOES
contain `&lt;script&gt;` and `&amp;` and `&quot;`. (Confirms BR2.)

**T-BR-2 — HTML emit: both files created**
Run `massoh board --local` in a repo with at least one TASK-* dir. Assert both
`agent-project/board.html` and `agent-project/BOARD.md` exist after the run. (Confirms BR5
create path.)

**T-BR-3 — HTML emit: HTML sentinel present**
After T-BR-2, assert `agent-project/board.html` contains `<!-- massoh-generated -->`.
(Confirms the sentinel is written, enabling safe overwrite on re-run.)

**T-BR-4 — BOARD.md cell sanitization**
Create a task whose title contains a `|` character and an embedded newline (simulate via a
title like `foo | bar`). Run `--local`. Assert `agent-project/BOARD.md` does NOT contain a raw
`|` inside a card cell (the pipe is replaced). (Confirms BR3.)

**T-BR-5 — No jq on `--local` path**
Build a `NO_JQ_PATH` (as in T21a, removing jq from PATH). Run
`PATH="$NOJQ_PATH" massoh board --local` in a valid repo with one TASK-*. Assert exit code 0
and both output files are created. (Confirms BR4 — jq guard only on Plane path.)

**T-BR-6 — `--push plane` output unchanged (regression)**
Run the full existing T17/T18/T19/T20/T21/T22/T23 suite. All must remain green. (Confirms BR6.)
This is covered by the existing suite; no new check needed, but the runner must confirm 0
regressions.

**T-BR-7 — No-clobber: hand-authored file**
Create `agent-project/board.html` WITHOUT the `<!-- massoh-generated -->` sentinel. Run
`massoh board --local`. Assert the command exits non-zero (or prints an error and does NOT
overwrite the file), and the file content is unchanged after the run. (Confirms BR5 clobber
protection.)

**T-BR-8 — `--out <dir>` redirect**
Run `massoh board --local --out /tmp/testout-$$`. Assert `/tmp/testout-$$/board.html` and
`/tmp/testout-$$/BOARD.md` are created. Assert `agent-project/board.html` does NOT exist (no
default-path side effect). (Confirms BR5 `--out` redirect.)

**T-BR-9 — No network on `--local`**
Using `unshare -n` (if available on the test runner) or by installing a `curl` stub that
`exit 1`, assert `massoh board --local` exits 0 and emits files without invoking `curl`.
Alternative: `grep -n 'curl' lib/verbs/board.sh` and assert all `curl` references are inside
`_board_push_plane` only. (Confirms BR7. Static grep is acceptable when dynamic network
isolation is unavailable in CI.)

**T-BR-10 — Sentinel overwrite: generated file is safely overwritten**
Run `--local` twice. Assert the second run exits 0 and updates the output files without error.
Assert `BOARD.md` contains only one `massoh_generated` sentinel (no doubling). (Confirms BR5
overwrite policy for generated files.)

**T-BR-11 — `_board_build_model` reuse: no second scanner**
Static check: `grep -c '_board_build_model' lib/verbs/board.sh` must return exactly 1 call
site per execution path (the existing Plane-path call plus 1 new `--local` call = 2 call
sites total, definition excluded). Assert no second `for d in "$repo"/.agent_tasks/TASK-*/`
loop exists outside `_board_build_model`. (Confirms BR1.)

**T-BR-12 — Degrade: zero TASK-* dirs on `--local`**
Run `massoh board --local` in a repo with no TASK-* directories. Assert exit 0 and that
`board.html` and `BOARD.md` are created (possibly empty kanban columns). No crash. (Confirms
BR8 degrade discipline.)

**Test target:** current baseline (N checks, where N >= 327) + 12 new T-BR-* checks = N + 12.
Minimum acceptable: all existing checks green, all 12 new checks pass.

---

## 9. Rollback plan

The change is confined to `lib/verbs/board.sh` (additive: new helpers + new flag parsing
branch). No schema change, no data mutation, no manifest change.

Rollback: `git revert <commit>` or `git checkout HEAD~1 -- lib/verbs/board.sh`. The Plane
adapter and all other verbs are unaffected. Any `agent-project/board.html` or
`agent-project/BOARD.md` files that were generated can be deleted (`rm`) without consequence —
they are re-generated on the next run. No irreversible state.

---

## 10. Approved for implementation?

**YES — APPROVED (batch-authorized; no additional sign-off required).**

Owner batch-authorization 2026-06-19 covers `bin/massoh` for queue item #8.
`bin/massoh` is likely unchanged (dispatch already routes to `cmd_board`; `--local` is parsed
inside that function). If the implementer determines a single-line dispatch or usage-string
change is needed in `bin/massoh`, it is covered by the standing batch-auth.
`manifest.yml` is unchanged (generated artifacts follow the `.env.massoh` / `.board-map.tsv`
precedent: runtime artifacts not listed in manifest).

**Condition count: 8 (BR1 – BR8).**

All 8 conditions are mandatory. Reviewer-QA must verify each before APPROVE.

---

## 11. Summary for implementer

**Files to change:**
- `lib/verbs/board.sh` — primary target. Add: `_board_html_escape` helper; `_board_emit_local`
  (HTML emitter); `_board_emit_board_md` (Obsidian-Kanban emitter); flag parsing for `--local`
  and `--out <dir>` in the `cmd_board` while-loop; jq guard moved into the `push_plane=1`
  branch; new `--local` execution branch before the existing `--push plane` block.
- `test/run.sh` — add T-BR-1 through T-BR-12.
- `VERSION` — bump to 0.14.0 (fleet #6 is licensed at 0.13.0; board-renderer follows).
- `CHANGELOG.md` — additive entry for `[0.14.0]`.
- `bin/massoh` — usage string update only, if needed (single line). No logic change.
- `manifest.yml` — NO change required.

**Generated file locations:**
- Default: `agent-project/board.html` and `agent-project/BOARD.md`.
- Override: `--out <dir>` writes to `<dir>/board.html` and `<dir>/BOARD.md`.

**Clobber policy:**
- Overwrite if sentinel present (generated file); refuse + error if sentinel absent (hand-authored).
- `--out <dir>` always overwrites.

**HTML escaping mechanism:**
Pure bash + sed helper `_board_html_escape()`: replaces `&`, `<`, `>`, `"` in order. Called on
every interpolated value before `printf` into HTML. No jq anywhere on the `--local` path.

**BOARD.md cell sanitization:**
Strip/replace `|` → `/` and `\n` → ` ` in all cell values via `tr` or inline `sed`.

**Highest risk:** HTML injection (BR2). The escaping helper must be applied to every
interpolated field without exception; missing one field (e.g. `last_agent`) is a silent bug
that will not show in normal tests unless the adversarial title test (T-BR-1) covers that
field. Implementer must enumerate every interpolated field and confirm each passes through
`_board_html_escape`.

**Serialization note:** 00_request.md states implement after #6 (fleet rollup) and #9 (profiles)
land, as all touch `lib/verbs/board.sh` or the bin tree. Rebase onto the then-current main to
get the correct VERSION base before bumping.
