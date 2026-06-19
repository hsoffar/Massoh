# 04 — Implementation Packet (LICENSE TO CODE): massoh board → Plane

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date issued:** 2026-06-19
- **Issued after:** product-scope BUILD (`01_product_scope.md`) + architecture-safety CONDITIONAL YES
  (`03_architecture_safety.md`, 26 conditions BG1–BG26) + **owner sign-off on `bin/massoh` +
  `manifest.yml`** (recorded in `AGENT_SYNC.md` decision log, 2026-06-19). Massoh's first credential
  + outbound-network surface — sign-off explicitly covers that risk class.
- **Target VERSION:** 0.10.0
- **Branch:** `feat/massoh-board`

This file is the license. Without it no product code may be written for this task.

## Scope (build exactly this — no more)
A new opt-in verb **`massoh board --push plane`** that turns Massoh's file-based task state into a
Plane kanban (push-only; Plane = read-only mirror).
- **Read** `.agent_tasks/TASK-*/` (stage = highest `0N_` file present) + git + `AGENT_SYNC.md`
  (last-handoff agent/mode) + `AGENT_BACKLOG.md` (pri/blocked) + `ledger.tsv` → an **internal task
  model**: `{task-id, title, stage, priority, last-agent, blocked}`.
- **Upsert** one Plane issue per task-id via Plane's REST API; column/state = the stage. Idempotent
  via an **append-only** local id-map `.agent_tasks/.board-map.tsv`
  (`task-id \t plane-issue-id \t plane-project-id \t pushed-at-epoch`): first run POSTs + appends a
  row; later runs look up the row and PATCH.
- **Config:** `PLANE_BASE_URL` + `PLANE_API_TOKEN` from env or a gitignored `.env.massoh`
  (sourced at startup); non-secret `PLANE_WORKSPACE_SLUG` + `PLANE_PROJECT_ID` may live in a
  committable `agent-project/board.conf`. `massoh board --init-config` writes a `.env.massoh` template
  (create-if-missing) and ensures `.gitignore` entries.
- `bin/massoh`: add `cmd_board` + dispatch `board)` case + usage line (mirror `cmd_gate` structure,
  lines ~1022–1120). No existing verb altered.
- `manifest.yml` lockstep; `VERSION` → 0.10.0; `CHANGELOG.md` `[0.10.0]`.

## Out of scope (deferred — do NOT build)
Two-way sync (Plane → Massoh); local HTML/Obsidian renderer; real-time per-agent telemetry
(SubagentStop); any non-Plane adapter; the fleet/multi-repo rollup. (Re-entry conditions in
`NOW_NEXT_LATER.md`.)

## Mandatory conditions — BG1–BG26 (from `03_architecture_safety.md`; all required)
Implement every one; cite file:line for each in `05_implementation_handoff.md`. The load-bearing set:

**Secret handling — `PLANE_API_TOKEN` (BG1–BG7, the critical block):**
- Token NEVER written to any git-tracked file; NEVER printed/echoed/logged — masked in every output,
  verbose, and error path. No `set -x` anywhere in `cmd_board`.
- Token passed to Plane via the API-key/Authorization **header only** — never in a URL/query string.
- `.gitignore` must contain `.env.massoh` and `.board-map.tsv` **before** either is written
  (enforce add-if-missing at the very top of any write path).
- Missing required vars → `exit 1` with an actionable setup message (no token value printed).
- `--init-config` is create-if-missing only (never overwrite an existing `.env.massoh`).

**Outbound network (BG8–BG15):**
- Connect + read **timeouts on every `curl`**; bounded retries (no infinite loop).
- **Graceful degrade:** Plane unreachable / non-2xx → print a warning, `exit 0`, and **never corrupt
  the id-map** (only a confirmed-success POST appends a row). Use `if curl ...; then ...; fi` — never
  trust exit status implicitly under `set -euo pipefail`.
- **HTTPS** expected; reject/refuse a non-https base URL.
- **Partial-push:** only successfully-pushed tasks get a map row; the next run retries the rest.
- **No exfiltration:** issue payload limited to the named model fields (BG26); never send repo file
  contents, secrets, or `.env*`.

**Local writes (BG16–BG21):** `.board-map.tsv` append-only (single `>>`, named var + SAFETY comment,
fields sanitized of tab/newline like the ledger L1/L6 precedent); `.gitignore` add-if-missing,
idempotent, non-destructive (never reorder/dedupe-rewrite existing lines); `.board-map.tsv` itself
gitignored; `board.conf` create-if-missing; `manifest.yml` updated in the same commit.

**Plumbing (BG22–BG26):** jq startup guard (`command -v jq` at the top of `cmd_board`, actionable
install msg; jq confined to `cmd_board` only — no other verb gains a jq dependency); owner sign-off
on record + manifest lockstep (done); read-only isolation (no internal `cmd_*` calls); issue body
bounded to the model fields with **`jq @json` encoding mandatory** (no string interpolation into JSON).

## Required tests — T17–T23 (27 checks; suite 236 → ≥263)
Use `test/run.sh` + temp repos; a **fake Plane endpoint** (a local stub / function, like the
autonomous-fleet `MASSOH_AGENT_CMD` injectable pattern) so tests need no real network or token.
At minimum:
- **T17 secret:** token never appears in stdout/stderr — **T17b is a LIVE assertion** (run cmd_board
  with a sentinel token, grep all output, assert absent); token never in any tracked file; missing-var → exit 1.
- **T18 gitignore:** `.env.massoh` + `.board-map.tsv` added if missing; idempotent (run twice, no dupes); existing entries preserved.
- **T19 network degrade:** Plane unreachable / non-2xx → exit 0, warning printed, id-map unchanged.
- **T20 id-map:** first push appends a row + POST; second push PATCHes (no duplicate row, no duplicate issue); append-only (no row removed).
- **T21 task model:** stage derived from highest packet file; pri/blocked parsed; empty/mixed model handled.
- **T22 jq guard:** jq-absent → exit 1 with install message; jq not referenced by any other verb.
- **T23 safety-critical:** `md5sum bin/massoh` (existing verbs region) + `manifest.yml` invariants; install/uninstall/block logic untouched; `|| true` / degrade discipline present.

## Acceptance criteria (implementer self-checks before handoff)
1. All 26 conditions BG1–BG26 satisfied — file:line for each in `05_implementation_handoff.md`.
2. T17–T23 present + green; full suite ≥263 green; paste verbatim output. T17b proven live.
3. Manual smoke against the fake endpoint: first push (POST + map row) → second push (PATCH, no dup)
   → unreachable (exit 0, map intact) → token never surfaced. Transcript in handoff.
4. Existing 236 tests still green (zero regressions).
5. `bin/massoh` diff adds only `cmd_board` + dispatch/usage; no other verb altered.
6. `manifest.yml` lockstep; VERSION 0.10.0; CHANGELOG `[0.10.0]`.
7. Plane REST API used per **current docs fetched via context7** (API-key header, workspace/project/
   issue + state endpoints) — NOT coded from memory.

## Rollback
Per-repo: delete `.env.massoh` + `.board-map.tsv`; remove the gitignore lines. Code-level: revert the
v0.10.0 PR — repos without the verb are unaffected (no token, no network, no hooks). Full plan in
`03_architecture_safety.md`.

## Routing
`massoh-implementer` → `05_implementation_handoff.md` → `massoh-reviewer-qa` (06) → owner merge.
Branch `feat/massoh-board`, one PR.
