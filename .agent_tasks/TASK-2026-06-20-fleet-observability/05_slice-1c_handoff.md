# 05 — Implementation Handoff: Fleet slice 1c — start-task panel (read-only)

- **Implementer:** massoh-implementer
- **Branch:** feat/fleet-starttask
- **Date:** 2026-06-20
- **VERSION:** 0.22.0
- **Status:** Implementation complete — ready for reviewer-qa

---

## Files changed

| File | Change |
|---|---|
| `lib/verbs/fleet.sh` | Added `_fleet_render_start_task_panel` function (lines 396–449) and wired it into `_fleet_render_repo` (line 392) |
| `VERSION` | 0.21.0 → 0.22.0 |
| `CHANGELOG.md` | Added [0.22.0] entry |
| `test/run.sh` | Added T-FS-25 through T-FS-29 (10 new additive checks) |

Files NOT touched (confirmed unchanged):
- `bin/massoh` — untouched (no install/uninstall/block logic change)
- `manifest.yml` — untouched
- `scripts/massoh-dashboard` — untouched (POST→404 already in do_POST; no route added)
- `agent-project/NON_NEGOTIABLES.md` — untouched
- `AGENT_SYNC.md` / `AGENT_BACKLOG.md` — untouched

---

## What was implemented

### Panel: `_fleet_render_start_task_panel` in `lib/verbs/fleet.sh`

Added a new bash function `_fleet_render_start_task_panel <repo_abs_path> <repo_name>` that renders a read-only "Start a task" HTML panel. Called at the bottom of `_fleet_render_repo`, just before `_fleet_html_footer`.

Panel content (rendered, escaped):
1. `cd <repo-abs-path> && massoh intake "<your idea>"` — queue it (the `&&` is rendered as `&amp;&amp;` in HTML)
2. `massoh work <repo>` then `/start-task "<your idea>"` — build interactively
3. A muted italic note: "Live one-click submit from the dashboard is owner-gated — parked pending sign-off."

### Conditions satisfied

| Condition | File:line |
|---|---|
| N4: `_board_html_escape` applied to `$repo` (abs-path) | `lib/verbs/fleet.sh:411-412` |
| N4: `_board_html_escape` applied to `$repo_name` | `lib/verbs/fleet.sh:411-412` |
| N6: no server-side exec / no agent call / no network / no write | `_fleet_render_start_task_panel` — printf-only |
| POST→404: `do_POST` calls `_send_404` | `scripts/massoh-dashboard:355-357` |
| Read-only FL1: panel is display-only; commands run in the user's own shell | entire function |
| No innerHTML / no eval / no fetch (JS not used) | static panel only — no JS added |
| set -euo pipefail in sourced file | `lib/verbs/fleet.sh:1` (file header) |

### Panel HTML sample (representative, from a live render of alpha-repo)

```html
<section style="margin-top:1.5rem;">
<h2>Start a task</h2>
<p style="font-size:.84rem;color:#374151;margin-bottom:.75rem;">Run one of these commands in your own shell to queue or start a task in <strong>alpha-repo</strong>:</p>
<div style="background:#fff;border-radius:.5rem;box-shadow:0 1px 3px rgba(0,0,0,.1);padding:.85rem 1rem;font-size:.84rem;">
<p style="margin:.3rem 0 .2rem;font-weight:600;color:#374151;">Queue it (append-only inbox):</p>
<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0 .75rem;"><code>cd /tmp/.../alpha-repo &amp;&amp; massoh intake &quot;&lt;your idea&gt;&quot;</code></pre>
<p style="margin:.3rem 0 .2rem;font-weight:600;color:#374151;">Build it interactively:</p>
<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0 .75rem;"><code>massoh work alpha-repo</code></pre>
<p style="margin:.1rem 0 .2rem;font-size:.8rem;color:#6b7280;">then, inside the agent session:</p>
<pre style="background:#f3f4f6;border-radius:.375rem;padding:.5rem .75rem;font-size:.82rem;overflow-x:auto;margin:.2rem 0;"><code>/start-task &quot;&lt;your idea&gt;&quot;</code></pre>
<p style="margin-top:.85rem;font-size:.78rem;color:#9ca3af;font-style:italic;">Live one-click submit from the dashboard is owner-gated &mdash; parked pending sign-off.</p>
</div>
</section>
```

### POST → 404 proof

`scripts/massoh-dashboard` lines 355–357 (unchanged):
```python
def do_POST(self):  # noqa: N802
    # N6: GET-only; no POST handling in this slice (slice 1c is owner-gated)
    self._send_404()
```

T-FS-28 confirms this at runtime:
- POST / → 404 (T-FS-28a green)
- POST /repo/alpha-repo → 404 (T-FS-28b green)
- POST /intake → 404 (T-FS-28c green)
- Source grep confirms do_POST → _send_404 (T-FS-28d green)

### Read-only byte-snapshot proof

T-FS-29a: alpha-repo md5sum snapshot before and after three curl requests (index + two repo views) — identical. Green.

---

## Tests run

```
bash test/run.sh
ALL GREEN — 544 checks passed.
```

Previous count (end of slice 1b): ~514 checks
New checks added: 10 (T-FS-25a/b/c/d/e, T-FS-26a/b, T-FS-27a/b/c, T-FS-28a/b/c/d, T-FS-29a/b — 14 assertions across 5 test IDs, all green)
Final count: 544

---

## Risks

- None identified. The change is purely additive bash `printf` statements inside an existing function. No new route, no new Python code, no new file I/O.
- The panel uses `&amp;&amp;` (HTML-encoded `&&`) and `&quot;` / `&lt;` / `&gt;` for shell metacharacters — all correct for display-only.

---

## Incomplete items

None. The POST/write path (live one-click submit) remains PARKED as per the architecture review §4 R3. This is intentional and documented in the panel's muted note. Owner sign-off required before that slice proceeds.

---

## Handoff to reviewer-qa

Reviewer: please verify:
1. `lib/verbs/fleet.sh`: `_fleet_render_start_task_panel` at lines 397–449; call at line 392 inside `_fleet_render_repo`.
2. `scripts/massoh-dashboard`: `do_POST` at lines 355–357 — still returns 404 (no edit).
3. `test/run.sh`: T-FS-25 through T-FS-29 additive — suite still exits 0 (`ALL GREEN — 544`).
4. `VERSION`: 0.22.0. `CHANGELOG.md`: [0.22.0] entry present.
5. Safety-critical files: `bin/massoh` and `manifest.yml` checksums unchanged (T11i/T15l/T16r/T22b in the suite cover these; or verify manually).
6. POST park intact: `grep -A3 'def do_POST' scripts/massoh-dashboard` → `_send_404`.
7. No innerHTML / no eval / no fetch: no JS was added; the panel is 100% static HTML from bash.

Auto-merge on green is pre-authorized per the packet (slice 1c routing).
