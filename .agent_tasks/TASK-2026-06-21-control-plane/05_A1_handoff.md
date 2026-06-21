# 05 — Implementation Handoff: A1 ops panels (v0.24.0)

- **Agent:** massoh-implementer
- **Branch:** feat/fleet-ops
- **Date:** 2026-06-21
- **Task:** TASK-2026-06-21-control-plane slice A1
- **Version:** 0.24.0 (bumped from 0.23.0)

---

## Files changed

| File | Change |
|---|---|
| `lib/verbs/fleet.sh` | Added 3 helper functions + wired into `_fleet_render_repo` |
| `test/run.sh` | Added T-FS-30..38 (23 new checks, additive) |
| `VERSION` | 0.23.0 → 0.24.0 |
| `CHANGELOG.md` | [0.24.0] entry prepended |

No safety-critical files touched. `bin/massoh`, `manifest.yml`, `templates/` all unchanged.

---

## What was implemented

Three new READ-ONLY HTML panels added to `_fleet_render_repo` in `lib/verbs/fleet.sh`,
rendered before the existing "Start a task" panel. All panels are inside the existing
`/repo/<name>` route — no new routes added.

### Panel 1: Queue / tickets (`_fleet_render_queue_panel`, fleet.sh line ~397)

Reads `AGENT_BACKLOG.md` (read-only awk):
- Main queue section: rows whose 6th pipe-field is TODO or BLOCKED (stops at `## Intake inbox`).
- Intake inbox section (`## Intake inbox`): all rows with pri, item, status columns.
- BLOCKED rows rendered with a red left-border highlight.
- Missing backlog → displays "(no AGENT_BACKLOG.md — —)"; no crash.
- N4: `_board_html_escape` on all three fields (pri, item, status).

### Panel 2: Cron (`_fleet_render_cron_panel`, fleet.sh line ~490)

Read-only cron status — reads only files, never invokes mutation commands:
- `Configured`: whether `.agent_tasks/cron/` dir exists (yes/no).
- `Cadence tick`: content of `.agent_tasks/cron/cadence_state` file (integer counter).
- `Last log line`: last non-empty line of `.agent_tasks/cron/cron.log` (head -c 200).
- Renders a "Read-only" advisory note mentioning `massoh cron install` as a display string only.
- Static source check (T-FS-33e) verifies no actual execution of crontab/cron-mutation.
- N4: all three values HTML-escaped via `_board_html_escape`.

### Panel 3: Workflow (`_fleet_render_workflow_panel`, fleet.sh line ~540)

In-flight tasks (TASK-* dirs without `06_review_result.md`) listed as:
- Task ID | Stage label | Pipeline string `00 → 01 → 02 → 03 → 04 → 05 → 06` with current step
  bracket-marked as e.g. `[04]`.
- Stage determination: highest packet file present (same logic as `_board_stage_from_dir`).
- Completed tasks (with 06) excluded.
- Empty state: "(no in-flight tasks)".
- N4: task_id, stage, and pipeline string all HTML-escaped.

---

## Conditions (file:line)

| Condition | Location |
|---|---|
| GET-only (no write/exec in panels) | `_fleet_render_queue_panel` ~line 397, `_fleet_render_cron_panel` ~line 490, `_fleet_render_workflow_panel` ~line 540 — all use only `awk`/`grep`/`tail`/`head`/`[ -f ]`; no `>`, `>>`, `tee`, `crontab`. |
| N4 — HTML-escape every interpolated value | `_board_html_escape` called on ALL field variables in all three functions before `printf`. |
| Graceful degrade (missing file → "—") | `_fleet_render_queue_panel`: `[ ! -f "$backlog_file" ]` early return; `_fleet_render_cron_panel`: `[ ! -d "$cron_dir" ]` degrade; `_fleet_render_workflow_panel`: `[ ! -d "$tasks_dir" ]` degrade. |
| No cron mutation | `_fleet_render_cron_panel` reads files only (`tail`, `head`, `[ -f ]`, `[ -d ]`). Static check T-FS-33e. |
| No new routes | Panels call helpers that `printf` to stdout inside existing `_fleet_render_repo`. Server unchanged. |
| POST still 404 | Verified by T-FS-38a/b (same server, same `do_POST` → 404 logic unchanged). |
| Read-only byte-snapshot | Verified by T-FS-36 (full cycle of all 3 panels — alpha-repo snapshot unchanged). |

---

## Repo-view sample (showing 3 panels)

After the "Recent commits" section, `/repo/alpha-repo` renders:

```html
<h2>Queue / tickets</h2>
<div style="background:#fff;...">
  <table class="task-list">
    <thead><tr><th>Pri</th><th>Item</th><th>Status</th></tr></thead>
    <tbody>
      <tr><td>P1</td><td>item</td><td>TODO</td></tr>
      <tr style="border-left:3px solid #ef4444;"><td>P1</td><td>blocked-item</td><td>BLOCKED</td></tr>
      <tr><td colspan="3" style="...">Intake inbox</td></tr>
      <tr><td>P1</td><td>&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt; intake item</td><td>TODO</td></tr>
      <tr><td>P2</td><td>intake item with | pipe</td><td>TODO</td></tr>
      <tr><td>P1</td><td>normal intake item</td><td>DONE</td></tr>
    </tbody>
  </table>
</div>

<h2>Cron</h2>
<div style="background:#fff;...">
  <table class="task-list">
    <thead><tr><th>Field</th><th>Value</th></tr></thead>
    <tbody>
      <tr><td>Configured</td><td>yes</td></tr>
      <tr><td>Cadence tick</td><td>7</td></tr>
      <tr><td>Last log line</td><td style="font-family:monospace;...">[cron] tick ts=2026-06-21T00:00:00Z slug=item-1 agent_rc=0 gate_rc=0 tick_duration=42s</td></tr>
      <tr><td colspan="2" style="...">Read-only status. To configure: run <code>massoh cron install</code> in your shell.</td></tr>
    </tbody>
  </table>
</div>

<h2>Workflow</h2>
<div style="background:#fff;...">
  <table class="task-list">
    <thead><tr><th>Task</th><th>Stage</th><th>Pipeline</th></tr></thead>
    <tbody>
      <tr><td>TASK-open-1</td><td>backlog</td><td style="font-family:monospace;...">[00] → 01 → 02 → 03 → 04 → 05 → 06</td></tr>
      <tr><td>TASK-inflight-2</td><td>licensed</td><td style="font-family:monospace;...">00 → 01 → 02 → 03 → [04] → 05 → 06</td></tr>
    </tbody>
  </table>
</div>
```

---

## Escape proof

- Queue XSS: `<script>alert("xss")</script>` in intake backlog → rendered as
  `&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;` (T-FS-32a/b pass).
- Pipe `|` in intake item text is HTML-escaped by `_board_html_escape` (which escapes
  `&`, `<`, `>`, `"` — pipe itself is not an HTML special char but is safely passed
  through as literal text in the table cell, not interpreted as a table delimiter).
- Cron log line: HTML-escaped before `printf` interpolation.
- Workflow task IDs and stage labels: HTML-escaped.

---

## Read-only snapshot proof

T-FS-36: `alpha-repo` filesystem snapshot (md5sum of all non-.git files + mtimes) identical
before and after rendering all three panels. The three functions only call:
- `awk`, `grep`, `tail`, `head` — all read-only
- `[ -f ]`, `[ -d ]`, `[ -n ]` — no-op checks
- `basename`, `printf` — pure computation
- No `>`, `>>`, `tee`, `touch`, `cp`, `mv`, `mkdir` calls on any discovered-repo path.

---

## POST → 404 proof

T-FS-38a: `POST /` → 404. T-FS-38b: `POST /repo/alpha-repo` → 404.
The `do_POST` method in `scripts/massoh-dashboard` returns 404 unconditionally
(verified by existing T-FS-28d). No new POST handler was added.

---

## Test suite output

```
23 new checks: T-FS-30a through T-FS-38b — all ok.
Previous 574 checks: all green (baseline).
Total: 597 checks.
```

T-FLN-6a (`fleet learn` idempotency timestamp flake) is a pre-existing intermittent failure
documented as backlog item #18. Not caused or worsened by this PR.

---

## Risks

1. **T-FLN-6a timing flake (pre-existing):** The new T-FS server tests add ~2s of runtime,
   slightly increasing the window in which T-FLN-6a's two consecutive `fleet learn` runs can
   cross a second boundary. This is a known fragility (issue #18); the correct fix is to strip
   the `Generated:` timestamp from the comparison, which is a separate backlog item.

2. **Pipe in intake items:** The `|` character in backlog text is not an HTML special char
   so `_board_html_escape` passes it through as literal text. Inside a `<td>`, this is safe.
   If the content were ever interpolated into a markdown table (not the case here), it would
   need additional sanitization.

3. **cron.log tail:** `tail -n 20` on a potentially large file. Capped to last 20 lines
   then `head -c 200` to bound the displayed length. Acceptable for a read-only status view.

---

## Incomplete items

- None within scope A1. Track B (POST write actions) remains parked per owner-gate.
- The T-FLN-6a flake (issue #18) is out of scope for this slice.

---

## Handoff to massoh-reviewer-qa

**Review checklist:**

1. `lib/verbs/fleet.sh`:
   - `_fleet_render_queue_panel`: confirm awk uses only read-only operators; confirm `_board_html_escape` on all 3 fields (pri, item, status); confirm graceful degrade on missing backlog.
   - `_fleet_render_cron_panel`: confirm no mutation commands executed (only file reads); confirm N4 on all fields; confirm graceful degrade on missing cron dir.
   - `_fleet_render_workflow_panel`: confirm `[ -f "${d}06_review_result.md" ] && continue` (excludes done tasks); confirm pipeline bracket logic; confirm N4.
   - `_fleet_render_repo`: confirm the 3 new `printf '<h2>...'` + helper calls are additive only (existing panels unchanged).

2. `test/run.sh` T-FS-30..38:
   - Confirm fixture setup (backlog with XSS + pipe + intake inbox, cron dir + cadence_state + cron.log, in-flight task TASK-inflight-2 at stage 04).
   - Confirm T-FS-36 (byte-snapshot) covers all 3 panels.
   - Confirm T-FS-38a/b (POST→404) still hold.
   - Confirm T-FS-37 (no orphan process) exercises SIGTERM + wait loop.

3. VERSION = 0.24.0 (both `VERSION` file and `CHANGELOG.md` entry).

4. `bin/massoh` + `manifest.yml` + `templates/` checksums unchanged (no safety-critical file touched).

5. Run `bash test/run.sh` — expect 597/597 green (T-FLN-6a may flake intermittently; run 2-3 times if seen).

**Route:** massoh-reviewer-qa → approve → auto-merge on green.
