# 05 — Implementation Handoff: A2 File Browser (v0.26.0)

**Branch:** `feat/fleet-filebrowser`
**Commit:** `e38ae21` feat(fleet): A2 read-only file browser on fleet dashboard (v0.26.0)
**Test result:** ALL GREEN — 676 checks passed (`bash test/run.sh`)

---

## B-condition → file:line citations

| Condition | File | Lines |
|-----------|------|-------|
| No path-from-URL — `file_id` used only as dict key, path from server-side map | `scripts/massoh-dashboard` | 699–708 |
| Double set-membership (name ∈ repo_name_map, id ∈ file_map) | `scripts/massoh-dashboard` | 692–702 |
| `_FILES_LIST_RE` / `_FILE_VIEW_RE` regex allow only `[a-f0-9]{16}` | `scripts/massoh-dashboard` | 568–569 |
| `_discover_files_for_repo` builds opaque_id → relpath map from closed taxonomy | `scripts/massoh-dashboard` | 384–470 |
| Symlink exclusion at enumeration (`os.path.islink`) | `scripts/massoh-dashboard` | 438–439 |
| Dotpath exclusion (`_is_dotpath`), `.agent_tasks` root allowed | `scripts/massoh-dashboard` | 340–360 |
| Secret-name denylist (`_is_secret_name`) | `scripts/massoh-dashboard` | 325–338 |
| Binary sniff (`_is_binary_sniff`) via NUL byte check | `scripts/massoh-dashboard` | 362–382 |
| Realpath confinement re-check before read (`_is_confined`) | `scripts/massoh-dashboard` | 711–713 |
| 256 KiB size cap; `truncated` flag passed to bash renderer | `scripts/massoh-dashboard` | 1033–1038 |
| `MAX_VIEW_BYTES = 262144` | `scripts/massoh-dashboard` | 113 |
| Belt-and-suspenders truncation in bash (`wc -c` independent check) | `lib/verbs/fleet.sh` | 1212–1222 |
| All HTML via `_board_html_escape` (listing labels/relpath/category) | `lib/verbs/fleet.sh` | 1100–1137 |
| File content escaped via `head -c | sed` pipeline (not via bash variable) | `lib/verbs/fleet.sh` | 1249–1251 |
| `set -euo pipefail` in bash renderer functions | `lib/verbs/fleet.sh` | 1182, 1093 |
| GET-only — `do_POST` → 404 unless `control_mode` (unchanged) | `scripts/massoh-dashboard` | 758–762 |
| `_FILE_MAP_CAP = 500` (listing cap) | `scripts/massoh-dashboard` | 321 |
| `_ALLOWED_EXTENSIONS` allowlist (`.md .txt .tsv .csv .log .json .yml .yaml`) | `scripts/massoh-dashboard` | 316–318 |
| `BIND_HOST = "127.0.0.1"` loopback unchanged | `scripts/massoh-dashboard` | 110 |
| "Generated files" link in `_fleet_render_repo` (per-repo view) | `lib/verbs/fleet.sh` | 1037–1048 |

---

## T-FB-1..17 — what each asserts

| Test | Assertion |
|------|-----------|
| T-FB-1a | `GET /repo/alpha-repo/files` → HTTP 200 |
| T-FB-1b | Listing body contains `task-list` (table class) |
| T-FB-1c | Listing body contains `Brief` label |
| T-FB-1d | Listing body contains `/file/` link |
| T-FB-2a | Listing contains `Packet` label (task packet category) |
| T-FB-2b | Listing contains a stage label (`request`, `impl-packet`, etc.) |
| T-FB-3a | `GET /repo/alpha-repo/file/<real-id>` → HTTP 200 |
| T-FB-3b | File view contains `<pre>` element |
| T-FB-3c | File view has `massoh-generated` sentinel |
| T-FB-4 | Valid hex shape but unknown id → 404 (set-membership rejects) |
| T-FB-5 | Non-hex id (e.g. `NOTAHEXID1234`) → 404 (regex rejects) |
| T-FB-6 | URL traversal `/../` → 404 (regex never matches; path not joined) |
| T-FB-7 | Symlink-escaped file (→ `/etc/hostname`) has no id; its computed hash → 404 |
| T-FB-8 | Secret-named file (`secret-token.md`) excluded from map; its id → 404 |
| T-FB-9 | Unknown repo name in files route → 404 (set-membership) |
| T-FB-10a | `large-file.md` (312 KiB) id → HTTP 200 |
| T-FB-10b | View of large file contains truncation notice (`Showing first 256 KiB`) |
| T-FB-10c | `TAIL_MARKER_LINE` absent from truncated view (tail bytes not served) |
| T-FB-10d | Truncated view body length bounded (< 512 000 bytes) |
| T-FB-11a | `xss-content.md` → HTTP 200 |
| T-FB-11b | Raw `<script>alert(` NOT in view body (escaped) |
| T-FB-11c | Escaped form `&lt;script&gt;` IS in `<pre>` |
| T-FB-12a | No raw `<script>` in listing body |
| T-FB-12b | `_fleet_render_file_list` calls `_board_html_escape` (source check) |
| T-FB-13a | `POST /repo/alpha-repo/files` → 404 (GET-only) |
| T-FB-13b | `POST /repo/alpha-repo/file/<id>` → 404 (no write surface) |
| T-FB-14 | `FS_REPO_A` byte-snapshot unchanged after file browser requests (read-only) |
| T-FB-15 | Server PID gone after SIGTERM (PID-scoped teardown, no orphan) |
| T-FB-16a | `_is_confined` present in dashboard source (realpath confinement) |
| T-FB-16b | `_discover_files_for_repo` present in dashboard source (map-lookup) |
| T-FB-16c | `_FILE_VIEW_RE` regex present in dashboard source |
| T-FB-16d | No `translate_path()` call in handler methods (not a file server) |
| T-FB-16e | Does not extend `SimpleHTTPRequestHandler` |
| T-FB-16f | `file_id not in file_map` check present (double set-membership) |
| T-FB-17 | `BIND_HOST = '127.0.0.1'` in dashboard source (loopback unchanged) |

---

## Pasted proofs

### Files-panel listing sample (`GET /repo/alpha-repo/files`)
```
HTTP 200

<h1>alpha-repo — Generated files</h1>
<table class="task-list">
<tr><td>Brief · large-file.md</td><td>brief</td>
    <td style="font-family:monospace;">agent-project/briefs/large-file.md</td>
    <td><a href="/repo/alpha-repo/file/6c5d2d358acdf8d9">view</a></td></tr>
<tr><td>Brief · sample-brief.md</td><td>brief</td>
    <td style="font-family:monospace;">agent-project/briefs/sample-brief.md</td>
    <td><a href="/repo/alpha-repo/file/da8b5c55e38d9c5b">view</a></td></tr>
<tr><td>Brief · xss.md</td><td>brief</td>
    <td style="font-family:monospace;">agent-project/briefs/xss.md</td>
    <td><a href="/repo/alpha-repo/file/5b07a5ab1d331c5a">view</a></td></tr>
```

### Known-id 200 with escaped content (`GET /repo/alpha-repo/file/da8b5c55e38d9c5b`)
```
HTTP 200

<title>Massoh Fleet — alpha-repo — Brief · sample-brief.md</title>
<h1>Brief · sample-brief.md</h1>
<pre ...># Sample brief
This is a brief.
</pre>
```

### Traversal / unknown-id / non-hex → 404
```
GET /repo/alpha-repo/file/../../etc/passwd  → 404 (regex rejects — not [a-f0-9]{16})
GET /repo/alpha-repo/file/deadbeefdeadbeef  → 404 (not in file_map)
GET /repo/alpha-repo/file/NOTAHEXID1234567  → 404 (regex rejects)
```

### Secret-unreachable (`secret-token.md` excluded at enumeration)
```
sha256("agent-project/secret-token.md")[:16] = 18552e5915343dc6
GET /repo/alpha-repo/file/18552e5915343dc6  → 404
(secret-token.md matches _SECRET_SUBSTRINGS {"secret","token"} — excluded at enumeration)
```

### Size-cap truncation (`large-file.md` = 312 030 bytes)
```
GET /repo/alpha-repo/file/6c5d2d358acdf8d9  → 200
body_len: 265 991 bytes (includes HTML wrapper + 262 144 bytes of content)
Truncation notice: "Showing first 256 KiB of 305KiB — file truncated for display (read-only view)."
TAIL_MARKER_LINE: absent (confirmed — tail bytes not served)
```

### XSS in content → escaped
```
GET /repo/alpha-repo/file/5b07a5ab1d331c5a  → 200
raw <script>: 0 occurrences
escaped: &lt;script&gt; present in <pre>
```

### Read-only byte-snapshot
```
before: 25b62beb40e72cafd4eead5c2c5dc9fc
after:  25b62beb40e72cafd4eead5c2c5dc9fc
SNAPSHOT UNCHANGED — no writes to the repo during file browser requests
```

### POST → 404
```
POST /repo/alpha-repo/files  → 404
POST /repo/alpha-repo/file/<id>  → 404
```

---

## Files changed

| File | Change |
|------|--------|
| `scripts/massoh-dashboard` | Added `_is_secret_name`, `_is_dotpath`, `_is_binary_sniff`, `_is_confined`, `_discover_files_for_repo`, `_render_file_list`, `_render_file_view`; added `_FILES_LIST_RE`, `_FILE_VIEW_RE`; two new route branches in `do_GET`; `MAX_VIEW_BYTES`, `_TAXONOMY`, constants |
| `lib/verbs/fleet.sh` | Added `_fleet_render_file_list`, `_fleet_render_file_view`; added "Generated files" link in `_fleet_render_repo` |
| `test/run.sh` | Added T-FB-1..17 live-HTTP tests (file-based body capture to avoid shell-variable pipe issues with large bodies) |
| `VERSION` | `0.25.0` → `0.26.0` |
| `CHANGELOG.md` | Added `## [0.26.0] - 2026-06-21` |

---

## Hard constraints verified

- `bin/massoh`, `manifest.yml`, `NON_NEGOTIABLES.md`, `templates/`, `policies/`, `agent-os/` → **diff = 0** (confirmed via `git diff --name-only HEAD -- bin/massoh manifest.yml ...` → empty output)
- GET-only — POST routes return 404 (control_mode unchanged)
- No secrets, `.env*`, build outputs committed
- Branch: `feat/fleet-filebrowser` (non-default)
- PID-scoped teardown: `kill "$FB_PID"` only — no broad `pkill`

---

## Risks

1. **T-FB-10b root cause (grep + large variable in eval):** The truncation notice grep failed when `$FB10_BODY` (265 990 bytes) was passed through `printf '%s' | grep` inside `eval`. Fixed by writing the body to a temp file and grepping the file. The bash renderer and server-side truncation logic are correct — confirmed by manual testing and the 674/676 → 676/676 fix.
2. **`_TAXONOMY` pattern breadth:** The 12-category taxonomy globs cover designed artifact paths. If new artifact directories appear outside the taxonomy, they won't appear in the file browser (secure by design — new categories need explicit addition).
3. **File-map cap (500):** Repos with > 500 artifacts will silently cap. First-glob-wins is deterministic.

---

## Incomplete items

None. All T-FB-1..17 pass. Suite is 676/676 green.

---

## Handoff for reviewer (`massoh-reviewer-qa`)

Verify:
1. No path-from-URL: `file_id` in `do_GET` is ONLY used as `file_map[file_id]` (dict key). `abs_path` is `os.path.join(repo_path, rel)` where `rel` comes from the server-built map (never the URL).
2. Confinement: `_is_confined` called at enumeration (line ~454) AND again before read (line ~711).
3. Escaping: `_fleet_render_file_list` uses `_board_html_escape` for all label/relpath cells; file content goes through `head -c MAX_BYTES | sed 's/&/\&amp;/g; ...'` pipeline.
4. Size cap: Python sets `truncated=1` when `os.path.getsize > 262144`; bash has belt-and-suspenders `wc -c` check; `head -c 262144` limits the byte read.
5. Read-only: no write target anywhere in the new routes; T-FB-14 snapshot test confirms.
6. POST → 404: `do_POST` returns 404 for all routes unless `control_mode` (unchanged by this slice).
7. Run `bash test/run.sh` → `ALL GREEN — 676 checks passed.`
