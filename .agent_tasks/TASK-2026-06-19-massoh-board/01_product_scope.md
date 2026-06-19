# 01 — Product Scope: massoh board → Plane push

- **Task ID:** TASK-2026-06-19-massoh-board
- **Date:** 2026-06-19
- **Agent:** massoh-product-scope
- **Decision:** BUILD

---

## 1. Decision: BUILD

The state is already board-shaped (file-existence encodes stage; the hand-kept backlog is provably
drifted today). A `massoh board` verb that generates a canonical task model and pushes it to the
owner's self-hosted Plane instance makes the invisible visible, introduces Massoh's first real-time
project-health surface, and is a direct retention and trust driver. The owner has already chosen the
tool (Plane) and the direction (self-hosted OSS). All preconditions are met to scope and license this.

**Strategic fit:** the north-star calls for "governance + self-measurement + autonomy" coupled. A
live Plane board is the externalized self-measurement layer that makes the system legible to an
operator who is not always reading raw markdown. This is not a vanity feature — it directly reduces
the mental overhead that today makes owners second-guess whether the agent team is on track.

---

## 2. Target segment

Solo owner + Claude Code (the current wedge). "All" because `massoh board` is a dev-tool verb with
no UX copy beyond CLI strings — there is nothing locale-sensitive or user-population-sensitive in
scope here.

---

## 3. Target region / locale

CLI-only, no user-visible text beyond terminal output. Region/locale = not applicable. Plane is
self-hosted by the owner; no geographic constraint.

**Expansion note:** nothing in this design hard-codes Plane as the only target. The internal task
model (see §6 minimal version) is the stable interface; a future `--push github` or `--push linear`
adapter could be added without touching the model layer. Do not couple the model layer to Plane.

---

## 4. Why now / why not

**Why now:**
- The backlog is demonstrably drifted today (00_request.md calls this out explicitly). A generated
  board is self-correcting by construction — it cannot drift because it reads file state, not a
  hand-kept table.
- `massoh ledger` (v0.7) and `massoh meta` (v0.8) already surface per-task cost and efficiency
  data. A Plane board is the natural rendering layer: it converts those signals from grep output to
  a card someone can glance at.
- The license-gate (v0.9, currently in review) is the last "governance core" feature. Once it
  lands, the next growth driver for retention is legibility — can an owner at a glance tell what
  the team is doing and how healthy the queue is?
- Owner has already made the tool decision (Plane). Scope is unusually well-defined coming in.

**Why not delay:**
- A drifted backlog erodes trust in the system. Every day the board doesn't exist, `AGENT_BACKLOG.md`
  diverges further. The pain is active, not hypothetical.

---

## 5. Metric affected

**Primary:** `packet_merged` (activation metric from METRICS.md) — the board makes the path from
idea to merged card visible, reducing the "is anything happening?" drop-off that stalls retention.
A board that shows cards moving from `00 backlog` through to `merged` directly supports the
activation-complete definition.

**Secondary (leading indicator):** owner runs `massoh board --push plane` and can see all current
packets on the board within one command — this is a new observable event we should name for future
instrumentation: `board_pushed`. No telemetry wiring in scope now (local CLI tool; events counted
by hand per METRICS.md policy).

---

## 6. Six scoping questions — resolved

### Q1. MVP cut: model-only first, or model + --push plane together?

**Decision: model + `--push plane` as one slice. Local HTML/Obsidian renderer DEFERRED.**

Rationale: the owner's stated need is a visual kanban ("see what each agent is doing, monitor
backlogs, visually see what really happens"). A JSON dump or text model with no visual surface does
not satisfy that need. The owner has already chosen Plane and presumably has or will stand up a
Plane instance. Shipping the model without the push saves zero user-visible value — the visual
board IS the feature. Internal model code is untestable without the push step exercising it.

**Deferred (local renderer):** a `massoh board --local` that outputs an HTML or Obsidian-flavored
Kanban to stdout or a temp file.
- Re-entry condition: owner reports that Plane is unavailable or too heavy to self-host, OR requests
  an offline-first mode, OR a second adopter requests a non-Plane renderer.

### Q2. Sync direction: push-only for MVP?

**Decision: push-only (Massoh → Plane). Two-way sync DEFERRED.**

Massoh's source of truth is the file system + git. Plane is a read-only mirror. An owner dragging a
card in Plane MUST NOT affect Massoh's packet state — that would create a split-brain where two
systems each think they own the canonical stage.

Two-way sync is deferred indefinitely because:
- It requires Massoh to read back from Plane and write to packet files — a destructive local write
  that cannot be trivially reversed.
- Ephemeral subagents have no daemon to poll. A Plane webhook has nowhere to call back into.
- The safety and conflict-resolution complexity is disproportionate to an MVP.

**Re-entry condition for two-way sync:** owner requests it explicitly after MVP is live AND
architecture-safety approves a conflict-resolution protocol AND a daemon/webhook surface exists.

### Q3. Identity / idempotency: how are packets matched to Plane issues across runs?

**Decision: append-only local id-map at `.agent_tasks/.board-map.tsv`.**

Format (tab-separated, one row per task):
```
TASK-2026-06-19-massoh-board	<plane-issue-id>	<plane-project-id>	<pushed-at-epoch>
```

Rules:
- On first `--push plane` for a task: create the Plane issue, append the mapping row.
- On subsequent runs: look up the task-id in `.board-map.tsv` to get the Plane issue id; call the
  UPDATE endpoint instead of CREATE.
- The map is append-only: never delete or rewrite rows. If a task appears twice (e.g. a botched run
  created a duplicate), the implementer documents this is resolved by the owner manually removing
  the duplicate Plane issue and the stale row; `board` does not auto-delete.
- `.board-map.tsv` MUST be gitignored (it contains a workspace/project-scoped Plane id that is
  instance-specific and has no meaning outside the owner's install). Add to `.gitignore` if missing
  (`create-if-missing` rule).

**Why not Plane's external_id / custom field?**
Storing the map in Plane (e.g. a custom "massoh-task-id" field) would make it retrievable without
a local file, but adds a required Plane API round-trip (fetch all issues, match by field) on every
run. The local TSV is O(1) lookup and works offline for the lookup step. It is also simpler to
implement in POSIX bash. The TSV is the right call for MVP.

### Q4. Live "what's each agent doing now"?

**Decision: MVP = task-level state only. Real-time per-agent event feed DEFERRED.**

MVP shows, per Plane card:
- Stage (derived from highest packet file number present).
- Last-handoff agent and mode (parsed from `AGENT_SYNC.md` §Last handoff or the most recent
  `05_implementation_handoff.md`).
- `git worktree list` output summarized as a label (e.g. "worktree: feat/license-gate") when a
  worktree is active for this task's branch.
- Blocked flag (if `BLOCKED` in AGENT_BACKLOG.md for this task).

**Why not per-agent telemetry:**
Massoh agents are ephemeral subagents spawned by Claude Code's orchestrator. There is no running
process to poll. A "SubagentStop" hook could emit structured events, but that requires the harness
to call back into Massoh (a `massoh ledger add` call already demonstrates this pattern). Real-time
per-agent live status (e.g. "massoh-implementer is currently in the middle of T16g") is not
derivable without a hook that fires mid-run, and mid-run state is not persisted to files.

**Re-entry condition for real-time feed:** harness adds SubagentStop hooks that can call
`massoh board --emit-event`; owner requests live-feed view in Plane. This is a distinct feature
requiring its own task packet. Flag it in NOW_NEXT_LATER as a LATER item.

### Q5. Config surface for PLANE_BASE_URL / PLANE_API_TOKEN / workspace + project slug?

**Decision: environment variables + an optional `.env.massoh` file (gitignored), falling back to
an `agent-project/board.conf` for non-secret config.**

Specifics:
- `PLANE_BASE_URL` — env var (e.g. `https://plane.example.com`). No default. Required.
- `PLANE_API_TOKEN` — env var. No default. Required. MUST NOT be read from any tracked file.
- `PLANE_WORKSPACE_SLUG` — env var OR stored in `agent-project/board.conf` (not a secret; it is
  the URL slug visible in the browser, not a credential).
- `PLANE_PROJECT_ID` — env var OR stored in `agent-project/board.conf`.

**Loading order:**
1. Source `.env.massoh` if present in repo root (gitignored; create-if-missing template printed on
   first run when vars are absent).
2. Env vars override anything from file.
3. If any required var is still unset after loading, `massoh board --push plane` prints a clear
   error message (listing the missing vars and the `.env.massoh` template) and exits 1. It does NOT
   silently continue or attempt the push.

**Secret safety:**
- `.env.massoh` MUST be in `.gitignore`. The verb adds it to `.gitignore` if it is absent (same
  `create-if-missing` pattern as other file writes).
- `agent-project/board.conf` contains ONLY non-secret values (slugs, IDs). It MAY be committed.
- The verb never reads `PLANE_API_TOKEN` from any file that is tracked in git.
- The verb never prints `PLANE_API_TOKEN` to stdout (mask it in any debug/verbose output).

**Why not `~/.claude/massoh-board.conf` (global)?**
The Plane instance is per-project (different repos point to different Plane projects). Project-level
config belongs in the repo's `agent-project/`. Global config would couple repos, which violates
the isolation model.

### Q6. Safety posture: read-only, zero LLM, graceful degrade?

**Decision: confirmed as specified. Explicit rules:**

- **Read-only against Massoh's own files:** `massoh board` reads `.agent_tasks/TASK-*/`, `AGENT_SYNC.md`,
  `AGENT_BACKLOG.md`, `.agent_tasks/ledger.tsv`, `git log`, `git worktree list`. It writes ONLY:
  - `.agent_tasks/.board-map.tsv` (append-only)
  - `.gitignore` (add-if-missing: one line for `.env.massoh`)
  - `.env.massoh` template (create-if-missing, if owner runs `massoh board --init-config`)
  No other local file is written. No packet files are modified.
- **Outbound:** Plane REST API calls only (create/update issues; create/set state names on first
  push). No other outbound network call.
- **Zero LLM:** no `claude -p`, no API call to Anthropic. Data flows: local files → task model
  → Plane REST API. All logic is bash + awk + grep + curl.
- **Graceful degrade:**
  - If Plane is unreachable (curl fails), print a warning and exit 0. Do NOT crash. Do NOT corrupt
    the local id-map.
  - If a partial push fails mid-run (some issues updated, some not), the id-map is only written for
    successfully pushed issues. The next run will retry the skipped ones.
  - If `.agent_tasks/` is empty, print "no tasks found" and exit 0.
  - If `PLANE_BASE_URL` / `PLANE_API_TOKEN` are unset, print the setup instructions and exit 1.
    (Exit 1 here is correct — this is a misconfiguration, not a runtime degrade.)
- **Matches the existing verb pattern:** use `|| true` on all grep/awk calls that may return
  no matches; use `if curl ...; then ...; else ...; fi` (never `curl ... && ...|| die ...`).

---

## 7. Dependency decision: jq

**jq is REQUIRED. Flag this explicitly.**

Plane's REST API speaks JSON. Both the request body (create/update issue) and the response body
(extract issue id from create response) are JSON. The existing verbs avoid jq by operating on
plaintext files (markdown, TSV, git log `--pretty` with custom formats). That is not possible with
a JSON API.

Options considered:
1. **Use jq** — available on most modern Linux/macOS; clean, correct JSON handling; well-known.
2. **Python -c "import json, sys; ..."** — POSIX-ish but `python3` is not guaranteed on all
   systems and is heavier.
3. **Regex/awk to extract JSON fields** — fragile, fails on nested objects, not maintainable,
   wrong approach for an API response with variable whitespace.

**Decision: use jq, with a startup guard.** The verb checks `command -v jq >/dev/null 2>&1` at
startup. If jq is absent, it prints:

```
massoh board: jq is required for --push plane (brew install jq / apt install jq).
```

...and exits 1 (a clear, actionable error, not a crash).

This is a **scoping decision** that must be explicitly communicated to architecture-safety and
the implementer: jq joins curl as the only non-POSIX-bash dependency for this verb. The verb
MUST NOT use jq for any operation that does not require JSON parsing (all existing non-board
verbs remain jq-free).

The architecture-safety agent must review the jq guard as a mandatory condition.

---

## 8. Minimal version (smallest slice that tests the hypothesis)

**"I can see my tasks move across a Plane board."**

The MVP is a single `massoh board --push plane` command that:

1. Scans `.agent_tasks/TASK-*/` and derives the internal task model (one record per task):
   - `task_id` — folder name
   - `title` — first non-empty heading from `00_request.md` (fallback: folder name)
   - `description` — first paragraph of `00_request.md` (truncated to 500 chars)
   - `stage` — highest-numbered packet file present: 00 backlog, 01 scoping, 03 arch-safety,
     04 licensed, 05 implementing, 06 review, merged (git: `00_request.md` in main but no open
     packet folder, OR presence of a `## merged` tag in AGENT_SYNC.md for this task)
   - `priority` — parsed from AGENT_BACKLOG.md (P0/P1/P2/P3; default P2 if absent)
   - `last_agent` — parsed from most recent `05_implementation_handoff.md` or AGENT_SYNC.md
     §Last handoff
   - `blocked` — true if task appears in AGENT_BACKLOG.md with status BLOCKED
   - `cost_tokens` — sum from ledger.tsv for this task-id (0 if absent)

2. Ensures the Plane project has the 7 required states (named exactly):
   `backlog`, `scoping`, `arch-safety`, `licensed`, `implementing`, `review`, `merged`
   On first push: creates any missing states. On subsequent pushes: reads existing states (no
   duplicates). State creation is idempotent (check before create).

3. For each task, looks up `.board-map.tsv`:
   - Not found → POST to Plane create-issue endpoint; append row to `.board-map.tsv`.
   - Found → PATCH to Plane update-issue endpoint (title, description, state, priority).
   No issue is ever deleted from Plane by `massoh board`.

4. Prints a summary:
   ```
   massoh board — 2026-06-19T14:22:01Z
     tasks scanned: 9
     pushed (new): 2
     pushed (updated): 7
     skipped (error): 0
     board: https://plane.example.com/massoh-workspace/projects/abc123/issues/
   ```
   and exits 0.

**Out of scope for MVP (non-goals — see §9).**

---

## 9. Non-goals (explicit)

- Two-way sync (Plane → Massoh).
- Local HTML renderer or Obsidian Kanban output.
- Real-time per-agent telemetry / SubagentStop hook integration.
- Plane attachment uploads (cost breakdown chart, packet file attachments).
- Plane labels beyond the stage-derived state.
- Plane cycle/module/module assignment.
- GitHub Projects, Linear, Jira, or any other board tool.
- `massoh board --watch` (continuous push loop / daemon).
- Auto-create the Plane workspace or project (assumes owner has created the project; the verb only
  manages issues and states within it).
- Deleting or archiving Plane issues when a task folder is deleted.
- Any form of LLM-generated description or summarization.

---

## 10. Required events (named, instrumentation deferred)

Per METRICS.md policy (no telemetry wiring; counted by hand):

| Event name | Meaning |
|---|---|
| `board_pushed` | `massoh board --push plane` completes with ≥1 issue upserted, exit 0 |
| `board_config_missing` | exits 1 because PLANE_BASE_URL or PLANE_API_TOKEN absent |
| `board_plane_unreachable` | curl to Plane fails; degrades gracefully, exits 0 |

---

## 11. Safety / guardrail impact

- **bin/massoh is safety-critical** (NON_NEGOTIABLES.md). Adding `cmd_board` modifies it. Owner
  sign-off is required before implementation. Architecture-safety must issue a CONDITIONAL YES
  referencing the sign-off requirement explicitly — same pattern as license-gate (G1–G14).
- **manifest.yml** must be updated in lockstep if the verb registration or any new scaffold file
  (`.board-map.tsv`, `board.conf`, `.env.massoh` template) changes the install/uninstall contract.
- **First outbound-network surface in Massoh.** All previous verbs are local-only. This verb makes
  outbound HTTP calls to a user-configured URL. Architecture-safety must treat this as a new risk
  class: the token must never be logged, the URL is owner-supplied (no SSRF mitigation needed for
  a local CLI tool, but the risk must be named), and the graceful-degrade pattern must be mandatory.
- **First secret-handling surface in Massoh.** `PLANE_API_TOKEN` is the first credential the CLI
  reads. Architecture-safety must mandate: no token logging, no token in error messages (mask to
  `***`), no token in any file written by the verb except the sourced `.env.massoh` (gitignored).
- **Additive + reversible:** the verb adds `.board-map.tsv`, `.env.massoh`, and (optionally)
  `agent-project/board.conf`. None of these are written by any other verb. Removing them leaves the
  repo in exactly the same state as before `massoh board` was first run. The verb is fully
  reversible by removing those three files.
- **No LLM spend.** Zero Anthropic API calls. Safe for autonomous cron (but cron should not run
  `massoh board` on an unattended tick unless the owner has explicitly set `--push plane` in a cron
  config — outbound network calls during unattended ticks require opt-in, same discipline as
  `--yes-spend`).

---

## 12. Expansion / localization impact

- The internal task model (§8 step 1) is the stable interface. Plane is the first adapter. A second
  adapter (GitHub Projects, Linear) would implement the same push interface against a different API.
  Architecture-safety should ensure the push logic is not interleaved with the model-building logic
  in `cmd_board` — a clear separation makes future adapters safe to add without touching the model
  code.
- Nothing in this design couples to the Claude Code harness specifically. The verb reads files and
  calls a REST API; it would work identically in a future multi-harness Massoh.

---

## 13. Acceptance criteria (testable by reviewer-qa)

All criteria must be independently verified by the reviewer without running against a live Plane
instance (use a mock or stub server for API calls).

| ID | Criterion | How to verify |
|---|---|---|
| B1 | `massoh board --push plane` with no Plane vars set: exits 1, prints which vars are missing, writes nothing | `env -i HOME=$HOME PATH=$PATH bash -c 'massoh board --push plane'; echo $?` → exit 1, stderr/stdout lists missing vars |
| B2 | `massoh board --push plane` with Plane unreachable (bad URL): exits 0, prints warning, .board-map.tsv not created | Set `PLANE_BASE_URL=http://127.0.0.1:19999` (nothing listening), run, verify exit 0 + no `.board-map.tsv` written |
| B3 | jq absent: exits 1, prints install instructions | `PATH=$(echo $PATH \| tr ':' '\n' \| grep -v jq \| tr '\n' ':')` (remove jq from path); run; verify exit 1 + message mentions jq |
| B4 | `.env.massoh` is added to `.gitignore` if missing | fresh repo; run; verify `.gitignore` contains `.env.massoh` |
| B5 | `.board-map.tsv` is append-only: re-running with same tasks does not duplicate rows | mock Plane; run twice with same tasks; count rows = number of tasks (not 2x) |
| B6 | Stage derivation correct: task with only `00_request.md` → stage `backlog`; with `04_implementation_packet.md` and no `06` → stage `licensed` | create synthetic `.agent_tasks/` folders; run `massoh board` (with `--dry-run` or in a test harness that stubs curl); inspect internal model output |
| B7 | Priority parsed from AGENT_BACKLOG.md: P0 task maps to Plane's highest priority | verify via mock Plane API request body |
| B8 | `PLANE_API_TOKEN` never appears in stdout/stderr | run with a known token; pipe stdout+stderr to grep for the token value → no match |
| B9 | `massoh board` with `--no-push` (or no flags) prints the task model as a human-readable table and exits 0 without making any API calls | run without `--push plane`; verify no curl invocations (stubbing or checking curl count) |
| B10 | All grep/awk calls in `cmd_board` use `|| true` (no set -e exit on empty match) | code review of `cmd_board` implementation |
| B11 | Partial push failure: if Plane returns 4xx for one issue, the verb continues to next task, skips the failed one, exits 0, and does NOT write the failed task to `.board-map.tsv` | mock server returns 422 for one task id; verify other tasks succeed and map only contains successful ones |
| B12 | `--dry-run` flag: prints what would be pushed, makes zero API calls, writes nothing | run with `--dry-run`; verify no `.board-map.tsv` mutations, no curl calls |

---

## 14. Kill / defer criteria

**Kill this task if:**
- Owner decides not to stand up or maintain a self-hosted Plane instance (the feature has no
  target surface).
- Plane's API changes in a way that requires non-curl dependencies heavier than jq (e.g. OAuth
  flows requiring a browser) and there is no workaround.

**Defer to later if:**
- `massoh gate` (license-gate, currently in review) is not yet merged — prefer not to open a second
  implementation branch while a safety-critical change to `bin/massoh` is in review. Wait for
  license-gate to land and be reviewed before issuing `04_implementation_packet.md` for `board`.
- Owner's Plane instance is not yet standing when implementation is ready — implementation can
  begin (using a mock), but the B1–B12 acceptance tests cannot be run end-to-end.

---

## 15. Route

**UX pass: NOT required.** No user-facing copy beyond CLI terminal strings. All strings are
informational (counts, URLs, error messages). No design decisions required.

**Architecture-safety: REQUIRED (next agent).** Reasons:
1. `bin/massoh` and `manifest.yml` are safety-critical — owner sign-off required before
   implementation.
2. This is Massoh's **first outbound-network surface** — new risk class requiring explicit
   treatment.
3. This is Massoh's **first secret-handling surface** — `PLANE_API_TOKEN` discipline must be
   mandated as conditions.
4. jq as a new dependency must be reviewed and accepted.
5. The `.board-map.tsv` id-map write and the `.gitignore` write are new local write surfaces that
   must be scoped and constrained.

Route to: `massoh-architecture-safety` with a BLOCK on implementation until:
(a) `TASK-2026-06-19-license-gate` is merged (avoid parallel safety-critical `bin/massoh` edits),
(b) owner sign-off on `bin/massoh` + `manifest.yml` changes for this task.

---

## 16. NOW_NEXT_LATER update note

The following addition should be made to `NOW_NEXT_LATER.md` under LATER:

- Live per-agent event feed via SubagentStop hooks → real-time Plane card activity log.
  Re-entry: harness adds SubagentStop hook support AND owner requests live feed view.

The following should be noted under DEFERRED:

| Item | Decision | Reason | Re-entry condition | Date |
|---|---|---|---|---|
| `massoh board --local` (HTML/Obsidian renderer) | Defer | No visual surface without push; Plane satisfies MVP need | Owner reports Plane unavailable or requests offline renderer | 2026-06-19 |
| Two-way Plane sync | Defer | Split-brain risk; no daemon to poll; destructive local writes | Explicit owner request + arch-safety-approved conflict protocol + daemon/webhook surface | 2026-06-19 |
