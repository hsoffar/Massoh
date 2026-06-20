# 05 — Implementation Handoff: Fleet slice 1a — dashboard content

- **Task:** TASK-2026-06-20-fleet-observability / slice 1a
- **Branch:** `feat/fleet-dashboard`
- **Date:** 2026-06-20
- **Agent:** massoh-implementer
- **VERSION:** 0.20.0

---

## Files changed

| File | Change |
|---|---|
| `lib/verbs/fleet.sh` | Additive: new HTML rendering functions (Seam A) |
| `scripts/massoh-dashboard` | Extended: `/repo/<name>` route + set-membership validation + bash renderer calls (Seam B) |
| `VERSION` | 0.19.0 → 0.20.0 |
| `CHANGELOG.md` | Added [0.20.0] entry |
| `test/run.sh` | Added T-FS-7 through T-FS-14 (28 new checks; 476 → 504 green) |

**Safety-critical files — UNTOUCHED:**
- `bin/massoh` — diff=0 verified via `git diff HEAD -- bin/massoh`
- `manifest.yml` — diff=0 verified
- `agent-project/NON_NEGOTIABLES.md` — untouched
- `AGENT_SYNC.md` / `AGENT_BACKLOG.md` — not edited

---

## What was implemented

### Seam A — bash renders + escapes HTML

New functions in `lib/verbs/fleet.sh`:

| Function | Purpose |
|---|---|
| `_fleet_render_index <root_or_tsv> <tsv_mode>` | Fleet index HTML page → stdout |
| `_fleet_render_repo <repo> <name> <all_repos>` | Per-repo HTML page → stdout |
| `_fleet_repo_kpis <repo>` | Tab-separated KPI line (open/blocked/throughput/rework/cycle/tokens/cost/agent/mode/version) |
| `_fleet_html_header <title>` | Common HTML head (sentinel on line 1, meta-refresh 30s) |
| `_fleet_html_footer` | Closing HTML tags |
| `_fleet_kpi_item <label> <value>` | Single KPI panel item |
| `_fleet_render_board_inline <repo>` | Reuses `_board_build_model` + inline kanban columns → stdout |
| `_fleet_render_task_list <repo>` | Task table (stage · last-handoff) → stdout |
| `_fleet_render_commits <repo>` | Recent commits (`git log -n 10`) → stdout |
| `_fleet_read_version <repo>` | Version file reader |
| `_fleet_discover_repos_list <root> <mode>` | Newline-separated repo path list |

**Every interpolated value passes through `_board_html_escape` (N4 / condition file:line: `lib/verbs/fleet.sh` every `esc_*` variable).**

### Seam B — server routes + streams bash stdout

`scripts/massoh-dashboard` extended:
- Route `/repo/<name>` added to the handler
- `_REPO_NAME_RE` regex gates valid name characters before set-membership check
- `_discover_repos()` discovers repos at server startup (MASSOH_FLEET_ROOT or fleet.tsv)
- `_build_repo_name_map()` builds `{name → abs_path}` dict (N2: name is NEVER joined onto a filesystem path)
- `_FleetHandler.do_GET`: unknown/traversal name → `_send_404()` before any repo access
- `_run_bash_renderer()` shells out to bash (single-quoted paths, no shell injection), captures stdout, streams to client
- GET-only; POST → 404 (N6)
- Python 3 stdlib only (N7): `subprocess`, `urllib.parse`, `re`, `os`, `threading`, `signal`, `socketserver`, `http.server`, `argparse`

### Condition compliance (file:line)

| Condition | File:Line | Evidence |
|---|---|---|
| N1 loopback-only | `scripts/massoh-dashboard:18` | `BIND_HOST = "127.0.0.1"` |
| N2 route allowlist + set-membership | `scripts/massoh-dashboard:163-185` | `_REPO_NAME_RE` + `if repo_name not in self.repo_name_map` → `_send_404()` |
| N2 no path-join from URL | `scripts/massoh-dashboard:178` | `repo_path = self.repo_name_map[repo_name]` (from server-side map only) |
| N3 clean lifecycle | `scripts/massoh-dashboard:246-278` | SIGINT/SIGTERM → `_stop_event.set()` → `server.shutdown()` |
| N4 HTML escaped in bash | `lib/verbs/fleet.sh` every `esc_*=_board_html_escape` | All interpolated values via `_board_html_escape` |
| N5 reuse KPIs | `lib/verbs/fleet.sh:_fleet_repo_kpis` | Reads METRICS.md, ledger.tsv, AGENT_SYNC.md; no recomputation |
| N6 GET-only / zero spend | `scripts/massoh-dashboard:do_POST` → `_send_404()` | No POST handling |
| N7 stdlib-only | `scripts/massoh-dashboard` imports | Only stdlib: subprocess, os, re, urllib, threading, signal, socketserver, http.server, argparse |
| FL1 read-only | `lib/verbs/fleet.sh` header | No `>`, `>>`, write target in fleet.sh |
| set -euo pipefail | `lib/verbs/fleet.sh:_fleet_serve` | Already set; render functions called from bash subshell with `set -euo pipefail` in renderer header |
| Graceful degrade | `lib/verbs/fleet.sh:_fleet_repo_kpis` | Missing METRICS.md / ledger.tsv → "—"; `|| printf '—\t…\n'` on every `_fleet_repo_kpis` call |

---

## Rendered-index HTML sample (first 20 table lines)

```html
<!-- massoh-generated -->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="30">
<title>Massoh Fleet</title>
<!-- ... CSS omitted ... -->
</head>
<body>
<h1>Massoh Fleet</h1>
<table>
<thead><tr>
<th>Repo</th><th>Open</th><th>Blocked</th><th>Throughput/wk</th>
<th>Rework%</th><th>Cycle (days)</th><th>Tokens</th><th>Compute</th>
<th>Last Agent</th><th>Mode</th><th>Version</th>
</tr></thead>
<tbody>
<tr>
  <td><a class="repo-link" href="/repo/alpha-repo">alpha-repo</a></td>
  <td>1</td><td>0</td><td>2</td><td>10%</td><td>4</td>
  <td>1500</td><td>120s</td><td>test-agent</td><td>IMPLEMENTATION</td><td>0.20.0</td>
</tr>
```

---

## Escape proof (N4 — XSS title → escaped in bash)

Task title in `00_request.md`:
```
# <script>alert(1)</script> & "xss-task"
```

Output from `_fleet_render_repo` (bash renderer):
```html
<div class="card"><div class="title">&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;xss-task&quot;</div>
```

Raw `<script>alert` does NOT appear in any HTTP response (verified by T-FS-11a/b checks).

---

## Read-only byte-snapshot (FL1)

Test T-FS-12 captures `find . -type f | sort | xargs ls -la | md5sum` BEFORE and AFTER a full index + two repo-view renders. Both alpha-repo and beta-repo checksums are identical (`ok T-FS-12a` and `ok T-FS-12b`).

The bash rendering functions only READ from discovered repos (grep/find/awk/git log). No `>`, `>>`, `tee`, `cp`, `mv`, `mkdir`, or `touch` in `_fleet_render_*` or `_fleet_repo_kpis`.

---

## Route-validation proof (N2)

| Request | Expected | Result |
|---|---|---|
| `GET /repo/nonexistent-repo` | 404 | ok T-FS-9 |
| `GET /repo/..%2f..%2fetc` | 404 (encoded traversal) | ok T-FS-10a |
| `GET /repo/../../../etc` | 404 (raw traversal) | ok T-FS-10b |
| `GET /repo/alpha-repo/../../etc` | 404 (sub-path) | ok T-FS-10c |
| `GET /repo/alpha-repo` | 200 (known repo) | ok T-FS-8a |

The guard is pure set-membership: `if repo_name not in self.repo_name_map: self._send_404(); return`. The string `repo_name` is never passed to `os.path.join()` or any filesystem call.

---

## Suite output

```
ALL GREEN — 504 checks passed.
```

(476 before slice 1a; 28 new T-FS-7..T-FS-14 checks added)

---

## Risks

1. **Discovery at startup only** — repos discovered when server starts; new repos added while the server is running require a restart to appear. This is the same model as `board --local`. Low risk; documented in the `--help` output.
2. **Per-request bash subprocess** — each GET request shells bash (source board.sh + fleet.sh + run render). On a machine with many repos or large `.agent_tasks/`, a render could take several seconds. The 30s meta-refresh is the mitigation; no streaming is implemented yet.
3. **`_board_build_model` populates shared global bash arrays** — `_BOARD_IDS`, `_BOARD_TITLES`, etc. are global. In the current design each render is a fresh bash subprocess so there is no cross-request contamination, but this must remain true if the architecture changes.

---

## Incomplete items

- **Slice 1b (task drill-down):** not in this scope; parked.
- **Slice 1c (POST → intake):** PARKED for owner per architecture review (new safety-critical risk class).
- **Slice 3 (fleet learn + browser button):** PARKED for owner.
- **Streaming/SSE render:** not in scope; meta-refresh 30s is the current UX.

---

## Handoff to reviewer-qa

Route to `massoh-reviewer-qa` for:

1. Verify N1–N7 conditions at the file:line references above.
2. Reproduce: run `bash test/run.sh` → confirm 504/504 green.
3. Verify route validation: `/repo/unknown` → 404, `/repo/..%2f..%2fetc` → 404.
4. Verify escape: grep for `<script>alert` in T-FS-11 output → absent; `&lt;script&gt;` → present.
5. Verify read-only: T-FS-12 before/after checksums identical.
6. Verify safety-critical files untouched: `git diff HEAD -- bin/massoh manifest.yml` → empty.
7. Verify VERSION = 0.20.0, CHANGELOG [0.20.0] present.
8. Confirm `massoh doctor --offline` exits 0 on a clean install.

Auto-merge on green per the 8h autonomy grant.
