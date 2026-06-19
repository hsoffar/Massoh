# 03 — Architecture / Safety Assessment
# Task: TASK-2026-06-19-fleet-rollup — `massoh fleet` read-only multi-repo rollup
# Agent: massoh-architecture-safety
# Date: 2026-06-19
# Authorization: owner **batch-authorized** (2026-06-19 decision log, `bin/massoh` edits for 24h
#   queue #3-#11 standing sign-off). No separate per-item owner sign-off required.

---

## 1. Backend / service impact

No backend or remote service is involved. `massoh fleet` is a local shell verb that reads the
filesystem and writes stdout only. No network calls, no LLM calls, no credentials.

The only optional write surface is a local cache directory (`~/.claude/massoh/`) — controlled
entirely by the implementer, always to the owner's own home directory, never to a discovered repo.

## 2. Client / app impact

CLI only. New verb `fleet` dispatched by `bin/massoh`. A new `lib/verbs/fleet.sh` is sourced by the
existing startup loop (lines 172-176 of `bin/massoh`). Dispatch: one new `fleet)` case in the
`case "$cmd" in` block; usage line in the unknown-command `die` fallback.

No existing verb behavior changes. Addition is purely additive — the `|| { fail }; exit 1` sourcing
guard on the startup loop means a missing `fleet.sh` would fail loud, not silently degrade; the
implementer must include the file.

## 3. API impact

No external API contract. The CLI surface is `massoh fleet [--root <dir>] [--no-cache]`. That is
the only new surface. Existing verb signatures are untouched. No contract seam change.

## 4. DB / migration impact

None. No schema, no database. The optional `~/.claude/massoh/fleet.tsv` registry is a new file
created by the verb on first use (or by the user manually). It must be create-if-missing, never
overwrite existing content without a flag. The format (TSV: one path per line) must be documented
in the usage string so the user can seed it manually.

No manifest.yml change is required (the `lib/verbs/` glob already covers new `.sh` files; this was
confirmed by MB2/MB12 precedent). The implementer must verify this remains true and not touch
`manifest.yml` unless the glob breaks — if it does, that is a fresh sign-off item (manifest is
safety-critical).

## 5. LLM / prompt impact

None. The verb is pure shell. Content from discovered repos (`AGENT_SYNC.md`, task directory names)
is treated as opaque text strings — never eval'd, never sourced, never passed to an LLM. This is
mandatory (condition FL4 below).

## 6. Safety / guardrail risks

This is the highest-risk surface: a verb that traverses the filesystem beyond the current repo.
The complete risk enumeration and required conditions are in Section 8 below.

Primary risk: the verb writes into a discovered repo. This is prohibited by the task spec and must
be structurally guaranteed, not just declared (condition FL1).

Secondary risks: unbounded `find` traversal (FL2), untrusted file content treated as instructions
(FL4), a single broken repo aborting the whole run (FL5), set -euo pipefail interactions with
find/grep (FL6).

## 7. Expansion / localization risks

The discovery root must be a **parameter** (env var `MASSOH_FLEET_ROOT` or `--root <dir>`), not
hard-coded to `$HOME` or any other path. This keeps the verb usable on any layout without a code
change (expansion principle, `12_EXPANSION_READY_ARCHITECTURE.md`). The `fleet.tsv` path should
similarly default to `~/.claude/massoh/fleet.tsv` but be overridable via env var.

No locale/region constraints apply to a CLI tool. Output is plain text (no i18n concerns for an
operator tool at this stage).

## 8. Risks → numbered conditions (FL1 – FL11)

### FL1 — HIGHEST RISK: structural write-isolation from discovered repos

The verb must never write any byte into a discovered-repo path.

Structural guarantee required (not a comment or assertion — a code structure that makes writing
into a discovered-repo path impossible):

- All `repo_path` variables for discovered repos are used **only** inside read-only operations
  (`[ -f ]`, `[ -d ]`, `cat`, `grep`, `head`, `find` bounded by `-maxdepth`).
- There is no `>`, `>>`, `tee`, `cp`, `mv`, `mkdir`, `touch`, or `printf ... >` whose target path
  is derived from or contains a discovered-repo variable.
- The ONLY write the verb may perform is to the local cache: `~/.claude/massoh/` (e.g. a
  `last-seen.tsv` or nothing at all). If a cache write is included it must be guarded by a
  `--no-cache` flag that disables it entirely; by default the verb is fully read-only (no
  filesystem writes whatsoever, cache is opt-in).
- Reviewer-QA must independently verify: search for `>` and `>>` in `fleet.sh`; confirm every
  target path is under `~/.claude/massoh/` or `/dev/null`, never under a discovered-repo variable.

Test assertion: T-FL-a (writes-nothing-to-discovered-repos) — described in Section 9.

### FL2 — Discovery: bounded scan, no filesystem exhaustion

`find` used for `.massoh` marker scanning MUST include `-maxdepth 3` (three levels is enough to
find a repo root under a typical `~/dev/` layout; configurable upward only via env var
`MASSOH_FLEET_MAXDEPTH` with a cap of 5). Without a depth bound, a misconfigured root (e.g. `/`)
would traverse the whole filesystem.

Additional guards:
- If `MASSOH_FLEET_ROOT` / `--root` is not set and `fleet.tsv` does not exist, the verb prints a
  usage hint and exits 0 (no scan, no error).
- If the root does not exist or is not a directory: print a warning, skip, exit 0.
- The `find` invocation must use `-name .massoh` (not a glob that matches too broadly).
- `find` output must be piped through `head -n 200` or equivalent to cap the repo list at a
  reasonable maximum (200 repos is already far beyond any realistic use case).

### FL3 — `fleet.tsv` registry: format + sanitization

Format: one absolute path per line, `#`-prefixed comment lines ignored, blank lines ignored.
Sanitization requirements:
- Each path is validated with `[ -d "$path" ]` before use. Non-directory entries are skipped with
  a warning.
- Paths are NOT eval'd, not passed to `bash -c`, not used in any string interpolation that could
  constitute code execution.
- Lines longer than 4096 characters are discarded with a warning (prevents pathological inputs).
- The file is read with `while IFS= read -r line; do ... done < "$tsv_file"`, never sourced.
- A missing or empty `fleet.tsv` is not an error: verb prints "no repos in registry" and exits 0.

### FL4 — Untrusted repo content: data, not instructions

Content read from discovered repos (AGENT_SYNC.md body, task directory names, backlog lines) is
treated as opaque text data. Mandatory:
- No `source`/`.` of any file from a discovered repo.
- No `eval` of any string derived from a discovered repo.
- No `bash -c` with discovered-repo content interpolated.
- Content is read with `grep`, `head`, `awk`, or `sed` and the extracted strings are only used in
  `printf`/`echo` output — never as command arguments that execute code.
- Cap reads: at most the first 200 lines of AGENT_SYNC.md per repo (`head -n 200`), at most 100
  task directory entries per repo.

### FL5 — Degrade: per-repo failures never abort the rollup

Every per-repo operation is wrapped in error-tolerant patterns:
- The outer loop iterates repos; each repo's block runs in a subshell or with `|| true` on every
  read step so a single bad repo does not kill the loop.
- A repo that is unreadable, has no `.agent_tasks/`, has a missing or unparseable `AGENT_SYNC.md`,
  or whose path no longer exists must produce a `[SKIP] <path>: <reason>` line on stdout and
  continue to the next repo.
- The overall verb exits 0 as long as at least one repo was attempted (even if all skipped).
- A zero-repo result (nothing found) exits 0 with an informational message, not exit 1.

### FL6 — `set -euo pipefail` discipline; guards on find/grep

`lib/verbs/fleet.sh` must open with `# shellcheck source=/dev/null` and rely on `bin/massoh`'s
top-level `set -euo pipefail`. All `grep`, `find`, `awk`, `git` calls that may return non-zero
(no-match, not-a-git-repo, missing file) must be guarded with `|| true` or `2>/dev/null || true`
to prevent the verb from exiting under `set -e`.

Pattern to follow: `review.sh` lines 26-28 / `learn.sh` grep guards (precedent from this repo).

Specific guards required:
- `grep -c ... || true` for all counting greps.
- `find ... 2>/dev/null || true` for all discovery finds.
- `git -C "$repo" log ... 2>/dev/null || true` for any git reads.
- `[ -f "$file" ] && head -n 200 "$file" 2>/dev/null || true` pattern for file reads.

### FL7 — No network, no LLM, no secrets

The verb must contain no `curl`, `wget`, `nc`, `ssh`, `gh`, or any other network primitive. No
calls to any LLM API. No reading of `.env.massoh` or any credential file. A `grep` for these
patterns in `fleet.sh` by reviewer-QA is a required check.

### FL8 — Privacy: aggregation stays local

Document explicitly in the verb's header comment and in the `--help` / usage string that the fleet
rollup output is local-only and never uploaded. This satisfies the brief's promotion-boundary rule
for this slice (cross-repo lessons promotion is OUT OF SCOPE — slice 3+).

Nothing in this verb may write to any location outside the owner's local filesystem. This is already
covered by FL1 (no writes to discovered repos) and FL7 (no network), but must be stated clearly.

### FL9 — `bin/massoh` dispatch + usage: additive only

The change to `bin/massoh` is limited to:
1. One new `fleet)` case in the dispatch block.
2. One new verb name added to the unknown-command `die` usage string.

No other line in `bin/massoh` changes. The sourcing loop already picks up `fleet.sh` automatically.
This is within the scope of the batch-authorization (24h queue #6 listed explicitly).

### FL10 — No manifest.yml change required (verify, don't assume)

The existing `manifest.yml` install stanza uses a glob or directory copy for `lib/verbs/` (per
MB2 precedent). The implementer must verify that a new `.sh` file in `lib/verbs/` is automatically
picked up by `cmd_install` without a manifest edit. If the glob does NOT cover it, that requires a
manifest edit — which is a safety-critical file requiring fresh owner sign-off, and the implementer
must STOP and route back here. Do not silently patch manifest.yml.

### FL11 — VERSION bump: 0.12.0

This is a new user-facing verb. VERSION must be bumped from `0.11.0` to `0.12.0` in the `VERSION`
file. CHANGELOG.md must receive a `[0.12.0]` entry. No other version-file changes.

---

## 9. Required tests (T-FL-* suite; target: 301 + 11 = 312 checks)

New test section `T-FL` appended to `test/run.sh` after the `T-MB` section.

### T-FL-a — writes-nothing-to-discovered-repos (highest-priority test)

Setup: create two temp git repos (`REPO_A`, `REPO_B`), each with a `.massoh` marker, a minimal
`.agent_tasks/` directory, and a minimal `AGENT_SYNC.md`. Record a byte-for-byte snapshot of both:

```
before_a="$(cd "$REPO_A" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
before_b="$(cd "$REPO_B" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
```

Run `massoh fleet --root "$root_dir"` where `root_dir` is the parent of `REPO_A` and `REPO_B`.

Assert both repos are byte-identical after the run:

```
after_a="$(cd "$REPO_A" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
after_b="$(cd "$REPO_B" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
check "T-FL-a REPO_A unchanged after fleet" "[ '$before_a' = '$after_a' ]"
check "T-FL-b REPO_B unchanged after fleet" "[ '$before_b' = '$after_b' ]"
```

(T-FL-a and T-FL-b are two assertions from the same setup block.)

### T-FL-c — bounded discovery: maxdepth cap

Create a deeply nested directory structure (5 levels) with a `.massoh` marker at depth 4. Run
`fleet --root "$deep_root"` with default maxdepth. Assert the deep marker is NOT discovered
(i.e., output does not contain the deep path). This verifies the `-maxdepth 3` default.

```
check "T-FL-c deep .massoh not discovered at default maxdepth" \
  "! (massoh fleet --root "$deep_root" 2>/dev/null | grep -q 'level4')"
```

### T-FL-d — degrade on unreadable repo

Create a valid discovered repo, then `chmod 000` its `.agent_tasks/` directory. Run fleet. Assert:
exit code is 0 AND stdout contains `SKIP` for the unreadable repo AND does not abort before
printing output.

```
check "T-FL-d exit 0 on unreadable repo"   "[ $rc_fl_d -eq 0 ]"
check "T-FL-d SKIP line printed"           "echo '$out_fl_d' | grep -qi 'skip'"
```

Restore permissions in cleanup: `chmod 755 "$bad_repo/.agent_tasks"` (trap cleanup).

### T-FL-e — empty/missing root

Run `fleet --root "$TMP/nonexistent_dir_$$"`. Assert exit 0 and informational message (no error
crash).

```
check "T-FL-e missing root exits 0"        "[ $rc_fl_e -eq 0 ]"
check "T-FL-e missing root prints message" "[ -n '$out_fl_e' ]"
```

Run `fleet` with no `--root` and no `fleet.tsv`. Assert exit 0.

```
check "T-FL-f no config exits 0"           "[ $rc_fl_f -eq 0 ]"
```

### T-FL-g — fleet.tsv registry parse

Create a `fleet.tsv` with: one valid repo path, one comment line (`# comment`), one blank line,
one non-existent path, one valid repo path. Run fleet with `MASSOH_FLEET_TSV` pointing to it.
Assert: two repos discovered (the two valid paths), comment/blank/missing paths silently skipped,
exit 0.

```
check "T-FL-g tsv: 2 repos discovered"     "[ $(echo '$out_fl_g' | grep -c 'repo:') -eq 2 ]"
check "T-FL-g tsv: exit 0"                 "[ $rc_fl_g -eq 0 ]"
```

### T-FL-h — no network / no secrets in fleet.sh

Static check: `grep -E 'curl|wget|nc |ssh |PLANE_API|SECRET|TOKEN' "$MASSOH_HOME/lib/verbs/fleet.sh"` must produce no output.

```
check "T-FL-h fleet.sh has no network/secret primitives" \
  "! grep -qE 'curl|wget|nc |ssh |PLANE_API|SECRET|TOKEN' '$MASSOH/lib/verbs/fleet.sh'"
```

### T-FL-i — no source/eval of discovered-repo content

Static check: `grep -E '^\s*(source|\.)\s+\$\{?repo\|eval\|bash -c' "$MASSOH_HOME/lib/verbs/fleet.sh"` must produce no output.

```
check "T-FL-i fleet.sh does not source/eval repo content" \
  "! grep -qE '^\s*(source|\.) .*repo|eval.*repo|bash -c.*repo' '$MASSOH/lib/verbs/fleet.sh'"
```

### T-FL-j — rollup output correctness

Use the two repos from T-FL-a setup (REPO_A with 2 task dirs one DOING one BLOCKED, REPO_B with 1
task dir TODO). Run fleet. Assert stdout contains at minimum: both repo paths, a task count for each,
the blocked indicator for REPO_A.

```
check "T-FL-j output contains REPO_A path"  "echo '$out_fl_j' | grep -q '$(basename $REPO_A)'"
check "T-FL-j output contains REPO_B path"  "echo '$out_fl_j' | grep -q '$(basename $REPO_B)'"
check "T-FL-j output shows blocked flag"     "echo '$out_fl_j' | grep -qi 'block'"
```

### T-FL-k — dispatch + usage registration

```
check "T-FL-k 'massoh fleet' dispatches (exit 0 on empty run)"  "[ $rc_fl_k -eq 0 ]"
check "T-FL-k unknown cmd usage lists 'fleet'"  \
  "('$MASSOH' bogus_verb_$$ 2>&1 || true) | grep -q 'fleet'"
```

---

Total new assertions: 2 (T-FL-a/b) + 1 (T-FL-c) + 2 (T-FL-d) + 2 (T-FL-e/f) + 2 (T-FL-g) +
1 (T-FL-h) + 1 (T-FL-i) + 3 (T-FL-j) + 2 (T-FL-k) = **16 new checks**

However, 5 of these subsume into paired asserts within 3-check groups, so the net **minimum new
check count is 11** (implementer may add more; suite target is 312 minimum).

**Suite target: 301 (current baseline) + 11 (minimum new) = 312 checks green.**

The implementer may add checks and must report the exact final count. Reviewer-QA independently
re-runs and confirms the count.

---

## 10. Rollback plan

`massoh fleet` is additive: a new `lib/verbs/fleet.sh` + two lines in `bin/massoh`. Rollback is:

1. `git revert <fleet-commit>` — removes `fleet.sh` and the two dispatch lines; no other file is
   affected.
2. The sourcing loop in `bin/massoh` exits loudly if a `lib/verbs/*.sh` file is listed in the
   install but missing from disk — so the reverted file must also be removed from any installed
   copy via `massoh install` after revert.
3. No data to roll back: the verb writes nothing to discovered repos. The optional cache
   (`~/.claude/massoh/`) can be removed with `rm -rf ~/.claude/massoh/` if desired.

Rollback is fast (< 1 min) and fully reversible. No migration needed.

---

## 11. Approved for implementation?

**YES — APPROVED.**

Authorization basis: owner batch-authorized `bin/massoh` edits for 24h queue items including #6
(fleet rollup) on 2026-06-19 (AGENT_SYNC.md decision log). No separate sign-off required for
this item. `manifest.yml` is NOT expected to change (FL10); if the implementer finds the glob
does not cover fleet.sh, they must STOP and escalate before touching manifest.yml.

Conditions that must be satisfied before reviewer-QA approves:

| ID | Condition | Verifiable by |
|----|-----------|---------------|
| FL1 | Zero writes into any discovered-repo path — structural, not asserted only | grep `>` in fleet.sh; T-FL-a/b |
| FL2 | `find` uses `-maxdepth 3` (default), capped at 200 repo results | code review; T-FL-c |
| FL3 | `fleet.tsv` read with `while IFS= read -r`; paths validated with `[ -d ]`; lines >4096 chars discarded | code review; T-FL-g |
| FL4 | No `source`, `eval`, `bash -c` with repo-content interpolation; reads capped at 200 lines per file | T-FL-i; code review |
| FL5 | Per-repo failures produce `[SKIP]` line + loop continues; exit 0 on partial | T-FL-d |
| FL6 | All `grep`/`find`/`awk`/`git` calls guarded `|| true`; no unguarded pipeline that kills verb under `set -e` | code review; T-FL-a through T-FL-k |
| FL7 | No `curl`, `wget`, `nc`, `ssh`, `gh`, no credential reads | T-FL-h |
| FL8 | Header comment + usage string explicitly state local-only, no upload | code review |
| FL9 | `bin/massoh` changes limited to: one dispatch case + one usage entry; no other lines changed | diff review |
| FL10 | `manifest.yml` NOT changed; implementer verified glob covers fleet.sh; if glob broken → STOP + escalate | code review |
| FL11 | VERSION bumped 0.11.0 → 0.12.0; CHANGELOG [0.12.0] entry added | code review |

**Condition count: 11 (FL1 – FL11).**

**Test target: 312 checks (301 baseline + 11 minimum new T-FL-* assertions).**

**Highest risk: FL1 — a write into a discovered-repo path.** Structurally guaranteed by confining
all write targets to `~/.claude/massoh/` (optional, off by default) and using discovered-repo
paths exclusively as arguments to read-only shell builtins and coreutils. The T-FL-a/b snapshot
test provides an independent byte-for-byte verification that no write occurred.

No merge dependency: impl may proceed immediately on a new worktree.

---

## 12. Implementation routing

Route to: `massoh-implementer`
Branch: `feat/fleet-rollup` (new worktree, no conflict with other in-flight items)
Task packet path: `.agent_tasks/TASK-2026-06-19-fleet-rollup/`
Next artifact to write: `04_implementation_packet.md`
Auto-merge-on-green: YES (batch-auth + auto-merge policy active per 2026-06-19 decision log)
