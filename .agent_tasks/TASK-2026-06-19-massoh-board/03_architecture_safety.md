# 03 — Architecture / Safety Assessment: massoh board --push plane

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date:** 2026-06-19
- **Agent:** massoh-architecture-safety (Massoh role)
- **Verdict:** CONDITIONAL YES — blocked pending recorded owner sign-off on `bin/massoh`
  (no `04_implementation_packet.md` may issue until that sign-off appears in `AGENT_SYNC.md`)

---

## Preamble

This review accepts all product decisions in `01_product_scope.md` (BUILD, push-only,
append-only id-map, jq accepted, config via env + `.env.massoh`, zero LLM, graceful
degrade). Those choices are not re-litigated here. This document focuses exclusively on
technical + safety readiness for implementation.

The feature introduces **three new risk classes** that have never previously existed in
Massoh: secret-handling, outbound network, and a local write surface that includes
`.gitignore` mutation. Each class receives its own condition block. The safety-critical
file constraint (`bin/massoh`) carries the same gate as every prior verb addition.

---

## 1. Backend / service impact

No server-side Massoh component is involved. All execution is local bash in `bin/massoh`.
Impact is confined to:

- `bin/massoh` — one new `cmd_board` function + one new `board)` dispatch arm + two new
  verb registrations (`board` in the error-message verb list at line 1162 and in the
  dispatch `case`).
- `manifest.yml` — must be updated in lockstep if `cmd_board` causes `massoh on` or
  `massoh install` to create new per-repo scaffold files. Specifically:
  - `agent-project/board.conf` (optional, non-secret, committable) — if produced by
    `massoh board --init-config`, it belongs in the `project_scaffold.create_if_missing`
    list.
  - `.env.massoh` and `.agent_tasks/.board-map.tsv` must NOT appear in the manifest as
    install targets; they are runtime artifacts that the verb manages itself.
- `scripts/massoh-gate-check` — exempt-list already covers `.gitignore` (line 30), so the
  `.gitignore` mutation introduced by `cmd_board` is an exempt path. No change to the
  checker needed.
- The `massoh-gate-check` CI workflow's exempt list covers `.agent_tasks/*`, so
  `.board-map.tsv` pushes are also already exempt. Confirm: no change to CI needed.

No database, no migration, no service contract.

---

## 2. Client / app impact

CLI-only. No UI, no UX copy beyond terminal strings. No locale-sensitive surfaces. No
impact on any agent markdown or any installed `~/.claude` file.

---

## 3. API impact

No Massoh API contract is changed. The `manifest.yml` ↔ `bin/massoh` seam (the project's
API contract seam per `CHARTER.md §3`) must be updated **in the same commit** if
`manifest.yml` lists a new scaffold file.

The Plane REST API is a **consumer-only** external dependency. The implementer must fetch
current Plane API docs before coding (see Note for Implementer, §14). The adapter must
not assume specific endpoint paths based on training-data memory.

---

## 4. DB / migration impact

No database. The append-only `.agent_tasks/.board-map.tsv` (tab-separated) is a new
runtime artifact — it is not installed by `massoh on` and must not appear in
`project_scaffold` as a seeded file. It materializes on first `--push plane` run.

Backward compatibility: the file does not exist on existing installs; the verb must
degrade gracefully when it is absent (treat as "no tasks previously pushed").

---

## 5. LLM / prompt impact

Zero LLM. No `claude -p`, no Anthropic API call, no AI-generated content. Data flow is
strictly: local files → bash task model → curl → Plane REST API. This is confirmed and
must be enforced as a mandatory condition.

---

## 6. Safety / guardrail risks

### Risk class A — Secret handling (PLANE_API_TOKEN): HIGHEST RISK

This is Massoh's **first credential surface**. PLANE_API_TOKEN is a bearer token giving
full write access to the owner's Plane workspace. A single accidental `echo`, `set -x`
trace, or `printf '%s'` of the token in an error path would expose it to terminal logs,
shell history, and CI logs.

Conditions BG1–BG7 (below) address this class exclusively.

### Risk class B — Outbound network (first in Massoh)

All prior verbs are local-only. `cmd_board` is the first to make external HTTP calls.
Risks: curl failure hangs or crashes the verb; non-2xx response misinterpreted as success;
token exposed in verbose curl output; partial push corrupts the id-map; no timeout allows
indefinite hang; URL injection from owner-controlled config is technically possible (SSRF
is not a threat for a local CLI, but the verb should still enforce HTTPS at the config
validation step).

Conditions BG8–BG15 address this class.

### Risk class C — Local write surfaces

Three new write surfaces, each with distinct risks:
- `.agent_tasks/.board-map.tsv`: append-only; if rewritten, loses idempotency and creates
  duplicate Plane issues.
- `.gitignore`: mutation must be add-if-missing + idempotent; must never reorder, truncate,
  or clobber existing entries; a botched write would corrupt the user's ignore rules.
- `agent-project/board.conf`: create-if-missing, committable, never overwrite.
- `.env.massoh` template: create-if-missing (only via `--init-config`), never overwrite;
  must be gitignored before any write.

Conditions BG16–BG21 address this class.

### Risk class D — jq dependency

jq has never been used in any Massoh verb before. Its absence would cause a confusing
failure if not caught early. A startup guard is mandatory.

Condition BG22 addresses this.

### Risk class E — Safety-critical file modification

`bin/massoh` and `manifest.yml` are designated safety-critical per `NON_NEGOTIABLES.md`.
Editing them without owner sign-off is prohibited. The same CONDITIONAL YES gate applied
to G1 in `TASK-2026-06-19-license-gate` applies here without exception.

Condition BG23 addresses the gate; BG24 addresses `manifest.yml` lockstep.

### Risk class F — Read-only against Massoh's own files

`cmd_board` must not write to any packet file, `AGENT_SYNC.md`, `AGENT_BACKLOG.md`,
`METRICS.md`, or `ledger.tsv`. It must not call other cmd_* functions internally
(same isolation requirement as M5 for cmd_meta).

Condition BG25 addresses this.

### Risk class G — Data exfiltration via Plane issue body

The verb sends content from local files (title, description, stage, priority, agent name)
to an external HTTP endpoint. This content must be strictly bounded to the named fields
from `01 §8 step 1`. No raw packet file contents, no directory listings, no environment
variable dumps, no path fragments that could reveal system info beyond the task metadata
must appear in issue bodies or titles.

Condition BG26 addresses this.

---

## 7. Expansion / localization risks

The internal task model (id, title, stage, priority, last_agent, blocked, cost_tokens) is
the stable interface confirmed in `01 §6 Q1` and `01 §12`. The push adapter must be a
named, isolated function within `cmd_board` (e.g. `_board_push_plane`) so that a future
`--push github` or `--push linear` adapter can be added without touching model-building
code.

No locale-sensitive text in this feature. CLI strings are English-only informational output
— acceptable per `01 §2` and `01 §3`.

Nothing in this design hard-codes Plane as the only adapter. The `--push plane` flag is
the selectable wedge per the expansion principle; the internal model must not import
Plane-specific assumptions.

---

## 8. Mandatory conditions (BG1–BG26)

### Secret-handling conditions (Risk class A)

**BG1 — Token never written to any tracked file.**
`PLANE_API_TOKEN` must be read only from the environment (sourced from `.env.massoh` or
set by the caller). It must never be written by the verb to any file. The verb must
validate before sourcing that `.env.massoh` is present in `.gitignore`; if `.gitignore`
does not yet contain `.env.massoh`, the verb must add it before sourcing the file.

**BG2 — Token masked in all output paths.**
The token must never appear in any `say`, `printf`, `echo`, or error message. All debug
and verbose output paths must use a masked form (e.g. `"***"`). If the implementer adds
any `-v` / `--verbose` / `--debug` flag, the flag must still mask the token.

**BG3 — Token not passed via curl command-line arguments.**
The token must be passed to curl exclusively via the `-H "X-Api-Key: $PLANE_API_TOKEN"`
header (or the correct header name per Plane docs — implementer must verify) using a
variable, not interpolated into a string that appears in a log. `set -x` must not be used
anywhere in `cmd_board`; if the outer script has tracing enabled, the implementer must
wrap the curl call in `{ set +x; ...; set -x; } 2>/dev/null` or equivalent to suppress
trace output for the token-bearing call.

**BG4 — Token not in URLs or query strings.**
`PLANE_API_TOKEN` must never be appended to `PLANE_BASE_URL` or any endpoint path.
Authentication must use the appropriate request header only.

**BG5 — `.env.massoh` gitignored before any write.**
Before any file write (including writing `.env.massoh` itself), the verb must ensure
`.env.massoh` appears in the repo's `.gitignore`. The gitignore addition is idempotent
(grep-before-append; see BG17). The order of operations: (1) check/add `.env.massoh` to
`.gitignore`, (2) then proceed with any other writes.

**BG6 — Exit 1 on missing required vars; no silent continuation.**
If `PLANE_BASE_URL` or `PLANE_API_TOKEN` are unset after sourcing `.env.massoh`, the verb
must print the names of the missing variables and an actionable setup message, then
`exit 1`. It must never proceed to make any API call or write any file with a missing
credential.

**BG7 — `.env.massoh` template never overwrites an existing file.**
If `--init-config` is used to emit a `.env.massoh` template, it must use create-if-missing
semantics only: `[ -e .env.massoh ] || cat > .env.massoh <<'EOF'`. The template must
contain placeholder values, not real credentials. If `.env.massoh` already exists, print
"keep .env.massoh (exists)" and do nothing.

### Outbound-network conditions (Risk class B)

**BG8 — Connect and read timeouts on every curl call.**
Every `curl` invocation in `cmd_board` must include `--connect-timeout 10 --max-time 30`
(or tighter; implementer may choose stricter values, not looser). No curl call may hang
indefinitely.

**BG9 — Graceful degrade on curl failure (exit 0, no map corruption).**
If any curl call fails (non-zero exit), the verb must: print a warning identifying the
failed task and the HTTP status code or curl error; skip that task; continue to the next
task; never write a map row for the failed task; exit 0 at the end with a summary showing
how many tasks succeeded and how many were skipped. The id-map is never written for a
failed push.

**BG10 — Non-2xx response treated as failure.**
The HTTP response code must be captured and checked. A 4xx or 5xx response is a failure
per BG9 semantics. The pattern must be:
```
http_code=$(curl -s -o "$tmpfile" -w "%{http_code}" ...)
if [ "${http_code:-000}" -ge 200 ] && [ "${http_code:-000}" -lt 300 ]; then
  # success path
else
  # failure path per BG9
fi
```
Never use `curl ... && ...` for success branching — the `if curl ...; then ...; fi`
pattern from existing verbs is mandatory.

**BG11 — HTTPS expectation at config validation.**
The config-validation block (where BG6 fires) must also check that `PLANE_BASE_URL` begins
with `https://`. If it begins with `http://` (plaintext), the verb must print a warning
and exit 1, unless an explicit `PLANE_ALLOW_HTTP=1` env var is set (owner opt-in for
local dev instances). This prevents accidental token transmission over plaintext.

**BG12 — No infinite retry loop.**
If the implementer adds retry logic, it must be bounded to a maximum of 3 attempts with a
fixed backoff, implemented as a counted loop (`for i in 1 2 3; do ...`), never a `while
true`. The more conservative approach — no retry, single attempt, degrade per BG9 — is
also acceptable and preferred for MVP.

**BG13 — Partial-push semantics: only successful tasks enter the map.**
The id-map row append (`printf '...' >> .board-map.tsv`) must occur only after the HTTP
response has been validated as 2xx. It must never be written speculatively before the
call, or after a failed call.

**BG14 — No exfiltration of repo internals.**
The Plane issue body must contain only the named model fields (`title`, truncated
`description` from `00_request.md`, `stage`, `priority`, `last_agent`, `blocked`,
`cost_tokens`). The description must be truncated at 500 characters (per `01 §8`). No raw
file paths, no git remote URLs, no environment variable values, no directory tree output,
no ledger.tsv raw content may appear in any field sent to Plane.

**BG15 — State upsert is idempotent.**
When creating Plane project states (the 7 named stages), the verb must check for existing
states before attempting to create them. A state with the matching name already existing
on Plane is not an error; the verb must retrieve the existing state ID and use it. No
state creation attempt must fire without a prior check.

### Local write surface conditions (Risk class C)

**BG16 — `.board-map.tsv` is append-only; never rewrite or delete rows.**
The id-map must use `printf '...\t...\t...\t...\n' >> "$BOARD_MAP"` exclusively. The verb
must never `>` (truncate), `rm`, or `sed -i` the map file. A named variable
`BOARD_MAP="$repo/.agent_tasks/.board-map.tsv"` with a SAFETY comment (same pattern as
`LEDGER` in cmd_ledger and `META_PROPOSALS` in cmd_meta) must mark the only permitted
write target. No other file in `.agent_tasks/` may be written.

**BG17 — `.gitignore` mutation: add-if-missing + idempotent + non-destructive.**
The verb must use `grep -qxF '.env.massoh' "$repo/.gitignore" 2>/dev/null || printf '\n.env.massoh\n' >> "$repo/.gitignore"` (exact-line match, no regex).
The append is never a `>` (truncate). If `.gitignore` does not exist, create it with
`touch` or create it and append. The add-if-missing logic must be idempotent: running
`massoh board` twice must not duplicate the `.env.massoh` line.

**BG18 — `.board-map.tsv` must be gitignored.**
The `.board-map.tsv` file contains Plane-instance-specific IDs that have no meaning
outside the owner's install. It must be added to `.gitignore` alongside `.env.massoh`
(same add-if-missing + idempotent pattern as BG17). The verb must add
`.agent_tasks/.board-map.tsv` to `.gitignore` before the first write to the map.

**BG19 — TSV fields sanitized before append.**
All four fields written to `.board-map.tsv` (task_id, plane_issue_id, plane_project_id,
pushed_at_epoch) must have tab and newline characters stripped before the `printf` write
(same L1 precedent from cmd_ledger). A botched task-id containing a tab would corrupt the
TSV structure.

**BG20 — `agent-project/board.conf` is create-if-missing only.**
If the verb writes `agent-project/board.conf` (for non-secret slug/ID config), it must
use `[ -e "$repo/agent-project/board.conf" ] || ...` semantics. Never overwrite. The file
must contain only `PLANE_WORKSPACE_SLUG` and `PLANE_PROJECT_ID` — never `PLANE_API_TOKEN`.

**BG21 — `manifest.yml` updated in lockstep.**
If `agent-project/board.conf` is added as a per-repo scaffold file (created by
`--init-config` or by `massoh board` on first run), it must be listed in
`manifest.yml` `project_scaffold.create_if_missing`. The `manifest.yml` change and the
`bin/massoh` change must ship in the same commit. `.env.massoh` and `.board-map.tsv` must
NOT appear in the manifest (they are runtime artifacts, not scaffolded files).

### jq dependency condition (Risk class D)

**BG22 — jq startup guard at the top of `cmd_board`.**
The first statement in `cmd_board` (before any file read, any curl call, any write) must
be:
```bash
command -v jq >/dev/null 2>&1 \
  || die "massoh board: jq is required for --push plane (brew install jq / apt install jq)."
```
jq must not be called, referenced, or imported in any other cmd_* function. All existing
verbs remain jq-free.

### Safety-critical file gate (Risk class E)

**BG23 — CONDITIONAL block: owner sign-off on `bin/massoh`.**
This assessment is CONDITIONAL YES. Implementation of `cmd_board` in `bin/massoh` is
blocked until the owner records explicit sign-off in `AGENT_SYNC.md §Decision log`, using
the exact pattern established for prior verbs:
`"Owner SIGNED OFF on editing bin/massoh — massoh board → 04 issued"`.
No `04_implementation_packet.md` may be written until that row exists. The issuing agent
(architecture-safety or system-architect) must verify the row before issuing the packet.

**BG24 — `manifest.yml` updated in the same commit as `bin/massoh` (per BG21).**
This repeats the lockstep requirement: no PR may touch `bin/massoh` without the
corresponding `manifest.yml` update (or a documented explicit no-change finding with
justification) in the same commit.

### Read-only isolation (Risk class F)

**BG25 — `cmd_board` must not call other cmd_* functions internally.**
`cmd_board` must read its own files directly (same isolation as cmd_meta condition M5).
It must not call `cmd_ledger`, `cmd_learn`, `cmd_plan`, or any other cmd_* function.
Permitted read operations: direct file reads of `.agent_tasks/ledger.tsv`,
`AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `.agent_tasks/TASK-*/` packet files, and
`git log / git worktree list` calls with `|| true`.

### Data exfiltration guard (Risk class G)

**BG26 — Issue body content bounded to named model fields.**
Code review by reviewer-qa must verify that no curl request body assembled by `cmd_board`
contains file paths, repo root, git remote URL, any `$HOME` reference, environment
variable values, full file contents, or any field not named in `01 §8 step 1`. The
description field must be truncated at 500 characters before JSON encoding. jq's
`@json` or `@sh` must be used for JSON encoding — never raw string interpolation into
JSON bodies (which would allow injection if title/description contains `"` or `\n`).

---

## 9. Required tests

Current suite baseline: **236 checks** (236/236 green, `TASK-2026-06-19-license-gate`).

The implementer must add the following checks. Each check must exercise the real code path
(not a stub). Plane API calls must use a mock HTTP server (e.g. `nc -l` or a minimal
`python3 -m http.server` fixture) — no live Plane instance required.

### T17 — cmd_board: secret handling

**T17a — Token absent: exit 1, prints missing var names, writes nothing.**
Set `PLANE_BASE_URL=https://example.com` but unset `PLANE_API_TOKEN`. Verify exit code 1.
Verify stdout/stderr names `PLANE_API_TOKEN`. Verify no `.board-map.tsv` created. Verify
no `.gitignore` mutation (or only the expected gitignore add was performed with no map
write).

**T17b — Token never appears in stdout or stderr.**
Run `cmd_board --push plane` with a known token value (`TEST_TOKEN_SENTINEL`). Capture
combined stdout+stderr. Assert the sentinel string does not appear anywhere in the
combined output.

**T17c — `.env.massoh` is added to `.gitignore` before any write, idempotent.**
In a fresh Massoh repo with no `.gitignore` entry for `.env.massoh`: run `massoh board
--push plane` (with mocked Plane). Assert `.gitignore` contains `.env.massoh`. Run again.
Assert `.env.massoh` appears exactly once in `.gitignore`.

**T17d — `.env.massoh` create-if-missing with `--init-config`: never overwrites existing file.**
Create a `.env.massoh` with sentinel content. Run `massoh board --init-config`. Assert
the file content is unchanged.

**T17e — Plaintext URL rejected (HTTPS guard).**
Set `PLANE_BASE_URL=http://10.0.0.1`. Assert exit 1 with a message referencing HTTPS.

### T18 — cmd_board: outbound network degrade

**T18a — Plane unreachable: exit 0, prints warning, no `.board-map.tsv` created.**
Set `PLANE_BASE_URL=http://127.0.0.1:19999` (nothing listening). Verify exit 0. Verify
warning printed. Verify `.board-map.tsv` does not exist.

**T18b — Plane returns 422 for one task: that task skipped; others succeed; exit 0.**
Mock server returns 422 for one task-id and 201 for others. Verify `.board-map.tsv`
contains rows only for successful tasks. Verify exit 0.

**T18c — Non-2xx does not write a map row for the failed task.**
Single-task scenario; mock returns 500. Verify `.board-map.tsv` is empty or absent after
the run.

**T18d — curl timeout does not hang indefinitely.**
Run against a server that accepts the connection but never responds. Verify the verb
completes within 60 seconds (use `timeout 60` wrapper). Verify exit 0 (graceful degrade).

### T19 — cmd_board: local write surfaces

**T19a — `.board-map.tsv` is append-only: two runs produce exactly N rows (no duplicates).**
Mock Plane returning 201 on create and 200 on update. Task folder has 3 TASK-* dirs. Run
once: assert 3 rows in map. Run again: assert still 3 rows (idempotent upsert, no new
rows). Row count must equal task count, not double.

**T19b — `.board-map.tsv` TSV structure: each row has exactly 4 tab-separated fields.**
After a successful push, assert every row in `.board-map.tsv` has exactly 4 fields when
split on `\t`.

**T19c — TSV field sanitization: task-id with embedded tab produces clean row.**
Create a TASK dir whose name would produce a tab in the field (simulate by injecting a
tab into the task_id variable in a unit test). Assert the resulting `.board-map.tsv` row
still has exactly 4 fields.

**T19d — `.board-map.tsv` gitignored: appears in `.gitignore` before first write.**
In a repo with no prior board run, verify that after running `massoh board --push plane`
(mocked), `.agent_tasks/.board-map.tsv` appears in `.gitignore`.

**T19e — `agent-project/board.conf` create-if-missing: existing file not overwritten.**
Create `board.conf` with sentinel content. Run `massoh board --init-config` or first
run. Assert file content is unchanged.

### T20 — cmd_board: task model correctness

**T20a — Stage derivation: task with only `00_request.md` → stage `backlog`.**
Synthetic folder with only `00_request.md`. Assert internal model reports stage=backlog.

**T20b — Stage derivation: task with `04_implementation_packet.md` and no `06` → stage `licensed`.**
Assert stage=licensed for this combination.

**T20c — Stage derivation: task with `06_review_result.md` present → stage `review`.**
Assert stage=review.

**T20d — Empty `.agent_tasks/` directory: exit 0, prints "no tasks found", no API calls.**
Remove all TASK-* dirs; run with mocked Plane (verify zero curl calls via a count or
file-based stub). Assert exit 0.

**T20e — Priority parsed: P0 task in AGENT_BACKLOG.md produces Plane request with highest priority value.**
Verify via mock server request body inspection.

**T20f — `--no-push` (or bare `massoh board`): prints task table, zero API calls, zero writes.**
Assert no `.board-map.tsv` write, no curl invocations.

**T20g — `--dry-run`: prints what would be pushed, zero API calls, zero writes.**
Assert `.board-map.tsv` unchanged after run.

### T21 — cmd_board: jq guard

**T21a — jq absent: exit 1, message mentions jq, mentions install instruction.**
Shadow jq with a function that returns 127. Assert exit 1 and message contains "jq".

**T21b — All other verbs (review, plan, standup, learn, recommend, ledger, meta, gate) remain
jq-free: none calls jq.**
Code review check: `grep -n 'jq' bin/massoh` output must contain only lines inside the
`cmd_board` function boundaries. This is a reviewer-qa code review assertion, not a
runtime test. However, the test suite must include a check that `cmd_review` (for
example) succeeds in a `PATH` that excludes jq.

### T22 — cmd_board: safety-critical files unchanged

**T22a — `bin/massoh` checksum unchanged across T17–T21 suite.**
Capture md5sum of `bin/massoh` before T17 group; re-capture after T21; assert equal.
(The test suite itself does not call `massoh install` or modify `bin/massoh`; this guards
against any test fixture that accidentally writes to the source file.)

**T22b — `manifest.yml` checksum unchanged across T17–T21 suite.**
Same pattern as T22a for `manifest.yml`.

**T22c — `.env.massoh` not tracked in git after a board run.**
After a board run that creates `.env.massoh` (via `--init-config`), assert
`git status --short | grep '.env.massoh'` returns empty (i.e. the file is gitignored and
does not appear as untracked).

### T23 — `|| true` discipline (code-review assertions)

**T23a — All grep/awk/git reads in `cmd_board` use `|| true`.**
Reviewer-qa code review: enumerate every grep, awk, and git call in cmd_board and verify
each is either inside an `if` statement or terminated with `|| true`. This is a code
review finding (B10 from 01 §13), confirmed in the test suite by:
- running `cmd_board` against a project with zero TASK-* folders (empty model);
- running it against a project with a missing `AGENT_BACKLOG.md`;
- both must exit 0 without error.

### Suite target

Current: 236 checks.
T17 (5) + T18 (4) + T19 (5) + T20 (7) + T21 (2) + T22 (3) + T23 (1) = **27 new checks**.
Target total: **263 checks**.

The implementer must reach 263/263 green before routing to reviewer-qa. If the implementer
adds sub-checks beyond these (e.g. for B4, B7, B9, B11, B12 from `01 §13` not directly
named above), the target total rises accordingly; the minimum is 263.

---

## 10. Rollback plan

`cmd_board` is fully additive. Rollback is:

1. `git revert <sha>` on the `bin/massoh` commit — removes `cmd_board` and the `board)`
   dispatch arm. All existing verbs continue to function without any code change.
2. Manually remove (or git-ignore) any `.agent_tasks/.board-map.tsv` and
   `agent-project/board.conf` files created during operation. `.env.massoh` was already
   gitignored by the verb — no git cleanup needed for it.
3. The `.gitignore` additions (`.env.massoh`, `.agent_tasks/.board-map.tsv`) are harmless
   even if left in place after rollback. Removing them is optional.
4. Plane issues created before rollback remain on Plane; the verb never deletes them, and
   rollback of the local verb does not affect Plane state. Owner must archive/delete
   them in Plane manually if desired.

There is no database migration to reverse. There is no installed file in `~/.claude` that
must be removed (the verb is entirely in the repo's `bin/massoh`, not in the installed
copy until `massoh install` is run again post-merge).

---

## 11. Impact table (every file and surface)

| File / surface | Type of change | Blast radius | Reversible? |
|---|---|---|---|
| `bin/massoh` | New `cmd_board` fn + dispatch arm | Safety-critical; owner sign-off required | Yes (git revert) |
| `manifest.yml` | Add `board.conf` to scaffold list if applicable | Safety-critical; in lockstep with bin/massoh | Yes (git revert) |
| `.agent_tasks/.board-map.tsv` | New runtime artifact (append-only) | Repo-local; gitignored | Yes (delete file) |
| `.gitignore` | Add 2 lines (`.env.massoh`, `.board-map.tsv`) | Add-if-missing; idempotent; non-destructive | Yes (remove lines) |
| `agent-project/board.conf` | New optional config (create-if-missing) | Non-secret; committable | Yes (delete file) |
| `.env.massoh` | New optional secret template (create-if-missing) | Gitignored; never tracked | Yes (delete file) |
| Plane REST API | Outbound HTTP (create/update issues + states) | Owner's Plane workspace only; push-only | Plane issues deletable by owner |
| `scripts/massoh-gate-check` | No change | Existing exempt list already covers all new paths | N/A |
| `test/run.sh` | 27+ new checks (T17–T23) | Test suite only | N/A |

---

## 12. Structural requirement: adapter isolation

`cmd_board` must be structured with a clear internal separation:

- **Model-building section** — reads `.agent_tasks/TASK-*/`, `AGENT_SYNC.md`,
  `AGENT_BACKLOG.md`, `ledger.tsv`, `git log`, `git worktree list` → populates an
  internal task array (or series of variables per task).
- **Push adapter section** — a named sub-function `_board_push_plane` that takes the
  task model as input and performs all Plane API interaction.

This separation is enforced because `01 §12` explicitly requires the model layer to be
decoupled from the Plane adapter for future expansion. A second adapter (e.g.
`_board_push_github`) must be addable without touching any model-building code.
Reviewer-qa must verify this structural boundary as a condition of APPROVE.

---

## 13. Verdict

**CONDITIONAL YES — implementation is approved subject to:**

1. Owner sign-off on `bin/massoh` recorded in `AGENT_SYNC.md §Decision log` (BG23).
   Pattern: `"Owner SIGNED OFF on editing bin/massoh — massoh board (TASK-2026-06-19-massoh-board) → 04 issued"`.
   No `04_implementation_packet.md` may be written before this row exists.

2. All 26 mandatory conditions BG1–BG26 must be satisfied in the implementation and
   verified by reviewer-qa with line-number references, matching the G1–G14 precedent
   from `TASK-2026-06-19-license-gate`.

3. Suite must reach at minimum **263/263 green** before routing to reviewer-qa.

4. `manifest.yml` must be updated in the same commit as `bin/massoh` (BG21/BG24), or the
   implementer must document with justification that no manifest change is required (e.g.
   if `board.conf` is not added to scaffold). This finding must appear explicitly in
   `05_implementation_handoff.md`.

5. The implementer must fetch current Plane REST API docs before coding (see §14).

---

## 14. Note for implementer (do not act on this — read only)

Before writing any Plane API interaction code:

- Fetch the **current** Plane REST API documentation via context7 or the official Plane
  docs. Do not code the adapter from training-data memory. Plane's API evolves; the
  correct header name for the API key, the workspace/project/issue endpoint paths, the
  state management endpoints, and the request/response schema must be confirmed against
  current docs before a single line of curl code is written.

- Verify: the correct authentication header (likely `X-Api-Key` but must be confirmed);
  the endpoint structure for create-issue, update-issue, list-states, create-state within
  a project; the response field that contains the issue ID on creation; the priority
  field name and accepted values; and the rate-limit behavior.

- The `--push plane` flag and the `--no-push` / `--dry-run` flags must be implemented
  as a flag-parse block at the top of `cmd_board`, following the same `while [ $# -gt 0 ]`
  pattern used in cmd_review, cmd_learn, cmd_meta, cmd_recommend.

---

## 15. `AGENT_SYNC.md` update note (for the issuing agent after sign-off)

When owner sign-off is recorded, add to `AGENT_SYNC.md §Decision log`:

```
| 2026-06-19 | TASK-2026-06-19-massoh-board: arch/safety CONDITIONAL YES — blocked pending owner sign-off on bin/massoh; 26 conditions BG1–BG26 (secret handling, network degrade, write surface isolation, jq guard, manifest lockstep, adapter isolation); 27 required tests T17–T23; target total 263; highest risk = PLANE_API_TOKEN exposure (BG1–BG7) | architecture-safety |
```

And when sign-off arrives:

```
| 2026-06-19 | TASK-2026-06-19-massoh-board: Owner SIGNED OFF on editing bin/massoh — massoh board → 04 issued | owner |
```

Update `§Active task packets` row for TASK-2026-06-19-massoh-board to: `03_arch_safety | CONDITIONAL YES — awaiting owner sign-off`.
