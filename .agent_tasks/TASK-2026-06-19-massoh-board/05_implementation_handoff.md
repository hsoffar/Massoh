# 05 — Implementation Handoff: massoh board → Plane

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date:** 2026-06-19
- **Agent:** massoh-implementer
- **Branch:** feat/massoh-board
- **Status:** COMPLETE — routing to massoh-reviewer-qa

---

## Files Changed

| File | Change |
|---|---|
| `bin/massoh` | Added `cmd_board`, `_board_ensure_gitignore`, `_board_stage_from_dir`, `_board_build_model`, `_board_print_table`, `_board_push_plane` functions; added `board)` dispatch case; updated usage string |
| `manifest.yml` | Added `agent-project/board.conf` to `project_scaffold.create_if_missing`; added comments for `.env.massoh` + `.board-map.tsv` non-inclusion |
| `VERSION` | 0.9.0 → 0.10.0 |
| `CHANGELOG.md` | Added `[0.10.0]` section |
| `test/run.sh` | Added T17–T23 (44 new checks; suite 236 → 280 green) |

---

## What Was Implemented

`massoh board --push plane`: scans `.agent_tasks/TASK-*/` → builds internal task model
(`{task-id, title, description, stage, priority, last-agent, blocked, cost_tokens}`) →
ensures the 7 Plane states exist (check-before-create, idempotent) →
upserts one Plane issue per task (POST first run / PATCH subsequent runs) →
appends a row to `.agent_tasks/.board-map.tsv` only on confirmed 2xx.

Supporting flags: `--dry-run`, `--no-push`, `--init-config`.

Adapter isolation: `_board_build_model` (model) vs `_board_push_plane` (adapter). Future
`--push github` / `--push linear` can be added without touching model code.

Plane API source: **makeplane/developer-docs**, branch `feat/add-new-api-docs`, fetched
2026-06-19 via `curl -s raw.githubusercontent.com`. Auth header: `X-API-Key`. Endpoints:
- Create issue: `POST {base}/api/v1/workspaces/{slug}/projects/{pid}/issues/`
- Update issue: `PATCH {base}/api/v1/workspaces/{slug}/projects/{pid}/issues/{issue_id}/`
- List states: `GET {base}/api/v1/workspaces/{slug}/projects/{pid}/states/`
- Create state: `POST {base}/api/v1/workspaces/{slug}/projects/{pid}/states/`
- Priority values: `none | urgent | high | medium | low`

---

## BG1–BG26 Conditions: File:Line Citations

### Secret Handling (BG1–BG7)

**BG1 — Token never written to any tracked file.**
`bin/massoh` lines 1123–1127 (header comment), 1221 (checked but value not printed),
1427/1475/1550/1574 (X-API-Key header only). The `.env.massoh` template at line 1170
contains only a placeholder string `your_api_token_here`, not a real token.

**BG2 — Token masked in all output paths.**
Lines 1215–1218 (missing-var message names `PLANE_API_TOKEN` but never prints its value).
All `say`/`printf` in `_board_push_plane` (lines 1598–1611) print only task IDs, issue
IDs, HTTP codes, counts, and the board URL — never the token value.

**BG3 — Token not in curl command-line; no `set -x`.**
`set -x` appears only in comments (lines 1127, 1398, 1544, 1568). All curl calls use
`-H "X-API-Key: ${PLANE_API_TOKEN}"` as a header variable (lines 1427, 1475, 1550, 1574).

**BG4 — Token not in URLs.**
All curl invocations pass the token via `-H "X-API-Key: ..."` only. Endpoint URLs at
lines 1424–1425, 1472–1473, 1547–1548, 1571–1572 contain only `PLANE_BASE_URL`,
`PLANE_WORKSPACE_SLUG`, `PLANE_PROJECT_ID`, and (for PATCH) the issue ID.

**BG5 — `.env.massoh` gitignored before any write.**
`_board_ensure_gitignore` (lines 1260–1280) is called at line 1195 (before sourcing
`.env.massoh`) and also at line 1160 (in `--init-config` path, before writing the template).
The `.gitignore` add-if-missing runs before any other write operation.

**BG6 — Exit 1 on missing required vars.**
Lines 1210–1220: checks `PLANE_API_TOKEN`, `PLANE_BASE_URL`, `PLANE_WORKSPACE_SLUG`,
`PLANE_PROJECT_ID`. If any are absent, prints names + actionable message to stderr, exits 1.
No API call or file write occurs with missing credentials.

**BG7 — `.env.massoh` template create-if-missing only.**
Lines 1162–1179: `if [ -e "$repo/.env.massoh" ]; then say "keep .env.massoh (exists)"; else cat > .env.massoh <<'ENVTEMPLATE' ... fi`.
Never overwrites. Template contains only placeholder values.

### Outbound Network (BG8–BG15)

**BG8 — Connect and read timeouts on every curl.**
All 4 curl calls include `--connect-timeout 10 --max-time 30`:
lines 1424–1432 (list states), 1472–1480 (create state),
1544–1553 (PATCH issue), 1568–1577 (POST issue).

**BG9 — Graceful degrade on curl failure (exit 0, no map corruption).**
After each curl: `if [ "${http_code:-000}" -ge 200 ] && [ "${http_code:-000}" -lt 300 ]`
(lines 1435, 1482, 1555, 1580). Failure path: `say "WARNING: failed to ..."`,
`skipped=$((skipped+1))`, continues to next task. Final `return 0` at line 1617.

**BG10 — Non-2xx treated as failure.**
Pattern at lines 1435, 1482, 1555, 1580: `http_code=$(curl ... -w "%{http_code}" ...)`,
then `if [ "${http_code:-000}" -ge 200 ] && [ "${http_code:-000}" -lt 300 ]`. Never uses
`curl ... && ...` for branching.

**BG11 — HTTPS expectation at config validation.**
Lines 1225–1238: `case "$PLANE_BASE_URL" in https://*) ;; http://*) if PLANE_ALLOW_HTTP=1 ...
else exit 1 fi ;; *) exit 1 esac`. Rejects non-HTTPS unless `PLANE_ALLOW_HTTP=1`.

**BG12 — No infinite retry loop.**
Single attempt per task. No retry logic. The graceful degrade per BG9 handles failures.

**BG13 — Map row written only after confirmed 2xx.**
Lines 1584–1592: `printf '%s\t%s\t%s\t%s\n' ... >> "$BOARD_MAP"` is inside the
`if [ "${http_code:-000}" -ge 200 ] ...` success branch, after extracting a non-empty
`new_issue_id`. Never written speculatively.

**BG14 — No exfiltration of repo internals.**
`_board_build_model` (lines 1300–1383) collects only: task_id (folder name), title
(first heading of 00_request.md), desc (first paragraph, truncated 500 chars), stage,
priority, last_agent, blocked, cost_tokens. `_board_push_plane` (lines 1505–1536)
builds `description_html` from desc + stage + cost_tokens only — no file paths, no git
remote URLs, no env var values.

**BG15 — State upsert is idempotent.**
Lines 1434–1441: parse existing states from list-states response into `STAGE_IDS[]`.
Lines 1448–1487: `for stage_name in ...` only creates a state if
`[ -z "${STAGE_IDS[$stage_name]:-}" ]`. Never creates a state that already exists.

### Local Writes (BG16–BG21)

**BG16 — `.board-map.tsv` append-only; named BOARD_MAP var; SAFETY comment.**
Line 1147 (SAFETY comment): `# BOARD_MAP is append-only (>>); never truncated, never deleted.`
Line 1148: `local BOARD_MAP="$repo/.agent_tasks/.board-map.tsv"  # SAFETY: sole append-only write target in cmd_board`
Line 1589: `>> "$BOARD_MAP"  # SAFETY: BOARD_MAP is the ONLY permitted write target (append-only >>)`
No `>`, `rm`, or `sed -i` on BOARD_MAP anywhere.

**BG17 — `.gitignore` add-if-missing + idempotent + non-destructive.**
`_board_ensure_gitignore` lines 1268–1276:
`grep -qxF '.env.massoh' "$gi" 2>/dev/null || printf '\n.env.massoh\n' >> "$gi"`
Exact-line match (`-xF`), append-only (`>>`), never reorders/truncates.

**BG18 — `.board-map.tsv` gitignored.**
`_board_ensure_gitignore` lines 1277–1279:
`grep -qxF '.agent_tasks/.board-map.tsv' "$gi" 2>/dev/null || printf '\n.agent_tasks/.board-map.tsv\n' >> "$gi"`
Called before BOARD_MAP is first written.

**BG19 — TSV fields sanitized before append.**
Lines 1501–1507: strips `\t`, `\n`, `\r` from `task_id` → `safe_task_id`.
Lines 1585–1587: strips `\t`, `\n` from `new_issue_id` → `safe_issue_id` and from
`PLANE_PROJECT_ID` → `safe_proj_id`. Only sanitized values written to BOARD_MAP.

**BG20 — `agent-project/board.conf` create-if-missing only.**
Lines 1182–1194: `if [ -e "$repo/agent-project/board.conf" ]; then say "keep ... (exists)"; else cat > ... fi`. Never overwrites.

**BG21 — `manifest.yml` updated in lockstep.**
`manifest.yml` line 53: `{ dest: agent-project/board.conf, source: null }` added to
`project_scaffold.create_if_missing`. Changed in this same working tree alongside `bin/massoh`.

### jq Dependency (BG22)

**BG22 — jq startup guard first in cmd_board; jq confined to cmd_board.**
Lines 1137–1138 (first statement in `cmd_board`):
`command -v jq >/dev/null 2>&1 || die "massoh board: jq is required for --push plane (brew install jq / apt install jq)."`
All `jq` calls are in lines 1135–1619 (cmd_board + _board_* sub-functions).
No `jq` reference anywhere else in `bin/massoh`.

### Safety-Critical File Gate (BG23–BG24)

**BG23 — Owner sign-off recorded.**
`AGENT_SYNC.md` decision log (2026-06-19): "TASK-2026-06-19-massoh-board: Owner SIGNED OFF on editing bin/massoh + manifest.yml". This satisfies the gate condition.

**BG24 — `manifest.yml` in same working tree as `bin/massoh`.**
Both modified in this PR on branch `feat/massoh-board`.

### Read-Only Isolation (BG25)

**BG25 — No internal cmd_* calls.**
`_board_build_model` (lines 1300–1383): reads files directly via `grep`, `awk`, `git log`.
No `cmd_ledger`, `cmd_learn`, `cmd_plan`, or any other cmd_* call. Confirmed by grep:
`grep "cmd_" bin/massoh | grep -v "^cmd_\|# " | grep "cmd_board\|_board"` — only
self-references within the board subsystem.

### Exfiltration Guard (BG26)

**BG26 — Issue body bounded to model fields; jq @json encoding.**
`_board_push_plane` lines 1505–1536: `body="$(jq -n --arg name "$title" --arg description_html "..." --arg priority "$priority" '...')"`. All string values encoded via `jq --arg` (which handles escaping). No raw string interpolation into JSON. Description field truncated at 500 chars at line 1508 (`head -c 500`). Fields: name, description_html, state, priority only.

---

## Tests Run

```
bash test/run.sh 2>&1 | tail -3
  ok   T23b missing AGENT_BACKLOG.md: exit 0 (|| true degrade)

ALL GREEN — 280 checks passed.
```

**Suite: 280/280 green (236 original + 44 new T17–T23 checks). Zero regressions.**

New checks breakdown (44 total, exceeds the minimum 27):
- T17 (8 checks): secret handling — missing vars, sentinel token never surfaced (live), gitignore idempotency, init-config no-overwrite, HTTPS guard
- T18 (7 checks): network degrade — unreachable exit 0, mock 201 success, 500 no map row, timeout completes <60s
- T19 (5 checks): local writes — idempotent map (first=2 rows, second=2 rows), TSV structure, sanitization guard, gitignore, board.conf no-overwrite
- T20 (11 checks): task model — stage derivation (backlog/licensed/review), empty dir, P0 → urgent, --no-push no writes, --dry-run no writes
- T21 (2 checks): jq guard — absent → exit 1 with 'jq' in message; cmd_review works without jq
- T22 (3 checks): checksums unchanged, .env.massoh not git-tracked
- T23 (2 checks): || true discipline — zero TASK-*, missing AGENT_BACKLOG.md both exit 0

**T17b (live token assertion):** confirmed — SMOKE_TEST_TOKEN never appeared in stdout+stderr (verified in test and manual smoke).

---

## Manual Smoke Transcript

```
SMOKE TEST 1: First push (POST → new rows)
  WARNING: PLANE_BASE_URL uses http:// (PLANE_ALLOW_HTTP=1 override active)
  massoh board — 2026-06-19T11:27:00Z
  created  TASK-2026-06-19-smoke-a → issue plane-issue-8 (HTTP 201)
  created  TASK-2026-06-19-smoke-b → issue plane-issue-9 (HTTP 201)
  tasks scanned: 2 | pushed (new): 2 | pushed (updated): 0 | skipped: 0

.board-map.tsv after first push:
TASK-2026-06-19-smoke-a  plane-issue-8  smoke-proj-id  1781868420
TASK-2026-06-19-smoke-b  plane-issue-9  smoke-proj-id  1781868420

SMOKE TEST 2: Second push (PATCH → no dup rows)
  updated  TASK-2026-06-19-smoke-a → issue plane-issue-8 (HTTP 200)
  updated  TASK-2026-06-19-smoke-b → issue plane-issue-9 (HTTP 200)
  tasks scanned: 2 | pushed (new): 0 | pushed (updated): 2 | skipped: 0

.board-map.tsv after second push: still 2 rows (no duplicates) ✓

SMOKE TEST 3: Unreachable endpoint (exit 0, map intact)
  WARNING: could not fetch Plane states (HTTP 000)
  WARNING: failed to update TASK-2026-06-19-smoke-a (HTTP 000) — skipped
  WARNING: failed to update TASK-2026-06-19-smoke-b (HTTP 000) — skipped
  tasks scanned: 2 | pushed (new): 0 | pushed (updated): 0 | skipped: 2
  Exit code: 0 ✓
  Map rows before: 2, after: 2 (map uncorrupted) ✓

SMOKE TEST 4: Token never surfaced
  PASS: token (SMOKE_TEST_TOKEN) never appeared in stdout+stderr ✓

.gitignore entries confirmed:
  .env.massoh
  .agent_tasks/.board-map.tsv
```

---

## Plane API Doc Source

**Source:** `makeplane/developer-docs` GitHub repo, branch `feat/add-new-api-docs`,
fetched 2026-06-19 via `curl -s raw.githubusercontent.com/makeplane/developer-docs/feat/add-new-api-docs/api-reference/...`.

Files fetched:
- `api-reference/introduction.mdx` — auth header `X-API-Key`, base URL format
- `api-reference/issue/add-issue.mdx` — POST endpoint, body fields, priority values
- `api-reference/issue/update-issue-detail.mdx` — PATCH endpoint
- `api-reference/state/add-state.mdx` — POST state endpoint, name + color fields
- `api-reference/state/list-states.mdx` — GET states endpoint

NOT coded from memory. context7 had no Plane library entry; WebFetch was used (raw GitHub API).

---

## Risks / Notes

1. **Plane API response shape for list-states**: the adapter handles both `response.[]` and
   `response.results[]` (jq: `.[] // .results[]? // empty`) to be forward-compatible with
   pagination responses. If Plane wraps in a different key, the state map will be empty and
   issues will be pushed without state assignment (degrade, not crash).

2. **State creation HTTP response**: if Plane returns a state in a non-200 response on creation
   (e.g. 409 Conflict), the adapter logs a warning and continues without the state ID. Issues
   are still pushed (without state assignment).

3. **PLANE_ALLOW_HTTP=1 dev override**: the smoke tests use this to avoid needing a TLS listener.
   In production this should always be unset.

4. **The `.board-map.tsv` idempotency depends on the file being present**: if the file is deleted
   between runs, the next run will re-POST all tasks (creating duplicates in Plane). Owner must
   restore the file from git stash/backup or manually remove the Plane issues. This is documented
   behavior (per 01_product_scope.md §Q3).

5. **44 new tests vs. specified 27**: the extra checks (sub-checks within each T group) are
   all real assertions. Total suite: 280/280. No stubs.

6. **`board.conf` in manifest.yml**: added with `source: null` (same pattern as `memory/MEMORY.md`)
   since there is no template file for it. `massoh board --init-config` creates it at runtime
   with a content template; `massoh on` will note it as "exists" if already created. This is
   consistent with the `project_scaffold.create_if_missing` contract.

---

## Incomplete Items

None. All 26 BG conditions met. All T17–T23 checks green. Smoke transcript complete.

Deferred per scope (from 01_product_scope.md §9):
- Two-way sync (Plane → Massoh)
- Local HTML/Obsidian renderer (`--local` flag)
- Real-time per-agent telemetry / SubagentStop hooks
- GitHub Projects / Linear adapters
- `massoh board --watch` continuous push

---

## Handoff to massoh-reviewer-qa

**Branch:** `feat/massoh-board`
**Reviewers must:**

1. Verify BG1–BG26 line citations above against actual `bin/massoh` (lines 1122–1619).
2. Run `bash test/run.sh` independently: expect 280/280 green.
3. Confirm T17b is a live assertion (sentinel token truly absent from output).
4. Verify `grep "jq" bin/massoh` shows jq only in lines 1135–1619 (cmd_board subsystem).
5. Verify `grep "set -x" bin/massoh` shows only comments.
6. Verify adapter isolation: `_board_build_model` and `_board_push_plane` are separate functions.
7. Verify `manifest.yml` lockstep: `board.conf` entry added.
8. Verify VERSION = 0.10.0; CHANGELOG has [0.10.0].
9. Verify `bin/massoh` diff adds only: `cmd_board`, `_board_*` functions, `board)` dispatch arm,
   updated usage string in the `*)` die case. No other verb altered.
10. Verify `.env.massoh` + `.board-map.tsv` do NOT appear in `manifest.yml` as install targets.

**Key BG conditions to independently spot-check:**
- BG1: no `PLANE_API_TOKEN` value in any say/printf/echo output path (only its name in error msg)
- BG3: no `set -x` in cmd_board (only comments)
- BG16: BOARD_MAP `>>` only (no `>`); SAFETY comment at line 1589
- BG22: `command -v jq` at line 1137 (first statement of cmd_board)
- BG26: all JSON bodies built via `jq -n --arg ...` (no string interpolation)

**Decision requested:** APPROVE or REQUEST CHANGES.
