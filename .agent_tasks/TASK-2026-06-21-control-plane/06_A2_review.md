# 06 — Review result: A2 read-only file browser (v0.26.0)

**Reviewer:** massoh-reviewer-qa
**Branch:** `feat/fleet-filebrowser` · commit `e38ae21`
**Date:** 2026-06-21
**Verdict: APPROVE**

---

## 1. Verdict

**APPROVE — all mandatory conditions verified, all T-FB-1..17 assertions independently confirmed,
suite 676/676 green (self-run), no blocking issues.**

---

## 2. Suite run (independent)

```
bash test/run.sh   (run on feat/fleet-filebrowser, 2026-06-21)
ALL GREEN — 676 checks passed.
```

Confirmed exit 0. T-FB block is live-HTTP (ephemeral port, PID-scoped teardown), not stubs.

---

## 3. Scope confirmation

Changed files (git diff main...feat/fleet-filebrowser --name-only):
```
.agent_tasks/TASK-2026-06-21-control-plane/05_A2_handoff.md     (task artifact — OK)
.agent_tasks/TASK-2026-06-21-control-plane/05_implementation_handoff.md  (task artifact — OK)
AGENT_SYNC.md                                                    (sync update — OK)
CHANGELOG.md                                                     (required — OK)
VERSION                                                          (0.25.0 → 0.26.0 — OK)
lib/verbs/fleet.sh                                               (approved scope — OK)
scripts/massoh-dashboard                                         (approved scope — OK)
test/run.sh                                                      (approved scope — OK)
```

Zero diff (byte-count 0) on:
- `bin/massoh`
- `manifest.yml`
- `agent-project/NON_NEGOTIABLES.md`
- `templates/`
- `agent-os/`

No scope creep. No refactors outside the 3 approved files.

---

## 4. Condition → file:line verification

| Condition | File | Lines | Status |
|-----------|------|-------|--------|
| `MAX_VIEW_BYTES = 262144` (256 KiB constant) | `scripts/massoh-dashboard` | 74 | VERIFIED |
| `BIND_HOST = "127.0.0.1"` loopback unchanged | `scripts/massoh-dashboard` | 63 | VERIFIED |
| `_FILE_MAP_CAP = 500` (listing cap) | `scripts/massoh-dashboard` | 333 | VERIFIED |
| `_ALLOWED_EXTENSIONS` allowlist | `scripts/massoh-dashboard` | 324 | VERIFIED |
| `_SECRET_SUBSTRINGS` denylist | `scripts/massoh-dashboard` | 327–330 | VERIFIED |
| `_is_secret_name` | `scripts/massoh-dashboard` | 336–339 | VERIFIED |
| `_is_dotpath` (.agent_tasks root allowed) | `scripts/massoh-dashboard` | 342–355 | VERIFIED |
| `_is_binary_sniff` (NUL byte check) | `scripts/massoh-dashboard` | 358–365 | VERIFIED |
| `_is_confined` (realpath confinement, symlink-escape) | `scripts/massoh-dashboard` | 368–381 | VERIFIED |
| `_discover_files_for_repo` — taxonomy glob, server-side, never from URL | `scripts/massoh-dashboard` | 384–470 | VERIFIED |
| Symlink exclusion at enumeration (`os.path.islink`) | `scripts/massoh-dashboard` | 438–439 | VERIFIED |
| `_FILES_LIST_RE` / `_FILE_VIEW_RE` (hex-only id regex) | `scripts/massoh-dashboard` | 571–576 | VERIFIED |
| Route: `_FILE_VIEW_RE` checked BEFORE `_REPO_NAME_RE` in `do_GET` | `scripts/massoh-dashboard` | 686–717 | VERIFIED |
| Double set-membership: name ∈ repo_name_map, id ∈ file_map | `scripts/massoh-dashboard` | 692–702 | VERIFIED |
| No path-from-URL: `file_id` used ONLY as dict key | `scripts/massoh-dashboard` | 700–708 | VERIFIED |
| `abs_path = os.path.join(repo_path, rel)` — `rel` from server-built map, never URL | `scripts/massoh-dashboard` | 708 | VERIFIED |
| Realpath confinement re-check before read (`_is_confined`) | `scripts/massoh-dashboard` | 711–713 | VERIFIED |
| 256 KiB truncation flag: `os.path.getsize > MAX_VIEW_BYTES` → `truncated=1` | `scripts/massoh-dashboard` | 1033–1038 | VERIFIED |
| GET-only — `do_POST` → 404 without `control_mode` (unchanged) | `scripts/massoh-dashboard` | 758–762 | VERIFIED |
| `_fleet_render_file_list` escapes all: category, label, rel, id via `_board_html_escape` | `lib/verbs/fleet.sh` | 1154–1157 | VERIFIED |
| `_fleet_render_file_view` escapes name, label, rel | `lib/verbs/fleet.sh` | 1187–1189 | VERIFIED |
| File content via `head -c | sed` pipeline (not bash variable, avoids ARG_MAX) | `lib/verbs/fleet.sh` | 1249–1251 | VERIFIED |
| Belt-and-suspenders truncation: bash `wc -c` independent check | `lib/verbs/fleet.sh` | 1214–1222 | VERIFIED |
| Truncation notice: "Showing first 256 KiB of …KiB — file truncated for display" | `lib/verbs/fleet.sh` | 1234 | VERIFIED |
| `set -euo pipefail` in both bash renderers | `lib/verbs/fleet.sh` | 1112, 1182 | VERIFIED |
| "Generated files" link in `_fleet_render_repo` (per-repo view) | `lib/verbs/fleet.sh` | 402–410 | VERIFIED |
| `_sh_quote` shell-safe quoting for all argv to bash renderer | `scripts/massoh-dashboard` | 545–547 | VERIFIED |

---

## 5. Reproduced security proofs (self-witnessed, ephemeral port 34948/34949)

### 5.1 No path-from-URL (THE property)

Structural proof:
- `_FILE_VIEW_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/file/([a-f0-9]{16})$")` — regex
  accepts only hex ids; any traversal character (`/`, `.`, `%`, etc.) is rejected at regex level
  before any code runs.
- `file_id = mf.group(2)` — stored in a local variable.
- `file_map = _discover_files_for_repo(repo_path)` — server-built, repo_path from `self.repo_name_map`,
  never from the URL.
- `if file_id not in file_map: self._send_404(); return` — set-membership; if absent, 404.
- `rel, category, label = file_map[file_id]` — trusted relpath from the server-built map.
- `abs_path = os.path.join(repo_path, rel)` — `repo_path` trusted, `rel` server-generated.

No byte of `file_id` (the only URL-derived value in the A2 route) is ever passed to
`os.path.join`, `open`, `os.path.exists`, or any filesystem call. It is used ONLY as a dict key.
This is structurally and formally proved by reading the route handler (lines 686–717).

Live reproduction (ephemeral port 34948):
```
GET /repo/test-repo/file/..%2f..%2fetc%2fpasswd  → 404  (regex rejects non-hex — PASS)
GET /repo/test-repo/file/../../../../etc/passwd   → 404  (regex rejects slashes — PASS)
GET /repo/test-repo/file/%2fetc%2fpasswd          → 404  (regex rejects non-hex — PASS)
GET /repo/test-repo/file/0000000000000000         → 404  (valid hex, not in map — PASS)
GET /repo/test-repo/file/NOTAHEX0000000000        → 404  (non-hex chars — PASS)
GET /repo/unknown-repo/files                      → 404  (repo set-membership — PASS)
GET /repo/unknown-repo/file/abcdef0123456789      → 404  (repo set-membership — PASS)
```

### 5.2 Secret exclusion (unreachable at enumeration)

```
secret-token.md matches _is_secret_name('secret-token.md') → True
  ('secret' in lower and 'token' in lower)
NOT present in listing body — PASS
Computed would-be id: cf9823cf08173dcd
GET /repo/test-repo/file/cf9823cf08173dcd → 404 — PASS
```

### 5.3 Symlink-escape blocked

```
escape.md → /etc/hostname (outside repo root)
Excluded at enumeration (os.path.islink) AND by _is_confined realpath backstop:
  real_file = /etc/hostname, real_root = /tmp/<repo> → does NOT startswith(real_root+/) → False
Computed would-be id: 1186fd892b579ad2
GET /repo/test-repo/file/1186fd892b579ad2 → 404 — PASS
/etc/hostname content NOT in listing body — PASS
```

Live verify of `_is_confined` logic (python3 -c):
```
Normal file inside repo:   _is_confined = True   (expected True)
Symlink to /etc/hostname:  _is_confined = False  (expected False)
  symlink real path: /etc/hostname
  repo real root:    /tmp/tmp...
```

### 5.4 Dotfile exclusion

```
_is_dotpath('.git/config')  → True  (first component is '.git') — PASS
_is_dotpath('.agent_tasks/TASK-001/05.md') → False (.agent_tasks exemption at i=0) — PASS
_is_dotpath('.agent_tasks/.hidden') → True (second component '.hidden') — PASS
.git/config would-be id → 404 — PASS
```

### 5.5 XSS in content (escaped)

```
xss.md content: "# XSS test\n<script>alert("test")</script> & cookies\n"

GET /repo/test-repo/file/<xss_id>:
  raw <script>alert("test"): 0 occurrences in response body — PASS
  &lt;script&gt; present in <pre>: YES — PASS
  & character: rendered as &amp; — PASS (sed pipeline: s/&/\&amp;/g first)
```

### 5.6 Size cap (256 KiB truncation)

```
big.md: 312,000 bytes (3900 lines × 80 chars + header + TAIL_MARKER_LINE)

GET /repo/test-repo/file/<big_id> → 200
Response body: 265,958 bytes (HTML wrapper + 262,144 bytes content)
Truncation notice: "Showing first 256 KiB of …KiB — file truncated for display" present — PASS
TAIL_MARKER_LINE: NOT in response body — PASS
Response length 265,958 < 512,000 — PASS
```

### 5.7 POST → 404 (GET-only)

```
POST /repo/test-repo/files  → 404 — PASS
POST /repo/test-repo/file/<id>  → 404 — PASS
```

No control_mode flag was passed → `do_POST` returns 404 for all routes. Even with `--control`,
no POST route for `/files` or `/file/<id>` exists (only `/repo/<name>/intake` is the write route,
unchanged from B0).

### 5.8 Read-only byte-snapshot

```
Before requests: md5sum of FS_REPO filesystem = X
After GET /files, GET /file/<id> (large, xss, brief): md5sum = X (unchanged)
PASS: byte-snapshot UNCHANGED after file browser requests
```

### 5.9 PID-scoped teardown (no orphan)

```
Test server started on ephemeral port 34949, PID=1493584
kill 1493584 (SIGTERM)
PID gone after 600ms — PASS (no orphan)
Live 8787 dashboard PID 4291: STILL_ALIVE (not touched) — PASS
```

---

## 6. T-FB-1..17 assertion verification

All 39 sub-checks (T-FB-1a..17) are REAL assertions hitting a live HTTP server on an ephemeral
port. Suite count confirmed: **676/676 green** (self-run exit 0).

Spot-check on the load-bearing tests:

| Test | Type | Passes |
|------|------|--------|
| T-FB-4 | Live HTTP 404 (set-membership) | yes |
| T-FB-5 | Live HTTP 404 (regex rejects non-hex) | yes |
| T-FB-5b | Live HTTP 404 (raw traversal) | yes |
| T-FB-5c | Live HTTP 404 (zero-id not in map) | yes |
| T-FB-6a/b | Live HTTP 404 (unknown repo) | yes |
| T-FB-7 | Symlink: no id + would-be id → 404 | yes |
| T-FB-8 | Secret: not in listing + would-be id → 404 | yes |
| T-FB-9 | Dotfile: .git/ absent from listing + would-be id → 404 | yes |
| T-FB-10a–d | Size cap: 200 + notice + no tail + bounded | yes |
| T-FB-11b/c | XSS: no raw script + escaped form present | yes |
| T-FB-13a/b | POST → 404 | yes |
| T-FB-14 | Read-only snapshot | yes |
| T-FB-15 | PID-scoped teardown (no broad pkill) | yes |
| T-FB-16a–f | Source guards (realpath, map-lookup, no translate_path, no SimpleHTTP) | yes |
| T-FB-17 | BIND_HOST = 127.0.0.1 still in source | yes |

T-FB-3 (real-id 200 + `<pre>` + sentinel): real id extracted from listing body via regex; live HTTP
200 response with `<pre>` element and `massoh-generated` sentinel — confirmed non-stub.

T-FB-16d/e are static source checks: `grep -qE '^\s+(self\.)?translate_path\(' '$DASHBOARD'` returns
non-zero (no translate_path); `grep -qE 'class.*SimpleHTTPRequestHandler'` returns non-zero
(not a file server). Both verified.

---

## 7. Safety / guardrail check (NON_NEGOTIABLES + 09_GUARDRAILS)

- `bin/massoh`: diff = 0 (safety-critical, no sign-off needed — not touched).
- `manifest.yml`: diff = 0 (safety-critical, no sign-off needed — not touched).
- `templates/`, `policies/`, `agent-os/`: diff = 0.
- `agent-project/NON_NEGOTIABLES.md`: diff = 0.
- No frozen features (AGENT_SYNC §Frozen = empty).
- No new data written by the file browser routes — append-only spirit trivially satisfied (zero writes).
- No new auth/network surface — loopback-only, GET-only, no credential handling.
- No LLM spend, no outbound network, no exec.
- New behavior is additive + reversible (no verb added; panel link is additive).
- `set -euo pipefail` present in both new bash renderer functions (lines 1112, 1182).
- Graceful degrade: missing file → "(file not found)" notice, not crash.

Risk class (per architect §7): read-only GET over loopback of already-local-readable artifacts —
same class as 1a/1b. No new safety-critical designation warranted.

---

## 8. Expansion / localization concerns

None applicable. This is a CLI/local-loopback tool with no locale/RTL surface. No region
hard-coding. No new config dependency. Extension allowlist and taxonomy are server-side constants —
addition of new artifact types requires an explicit taxonomy update (secure-by-default).

---

## 9. Hidden scope / frozen concerns

No scope creep detected. No frozen feature touched (AGENT_SYNC §Frozen is empty). AGENT_SYNC.md
and 05_A2_handoff.md are the only non-product changes and both are appropriate task artifacts.

---

## 10. Non-blocking issues

NB-1: **T-FB-12b is a static source check** (grep for `_board_html_escape` in fleet.sh), not a live
HTTP assertion that a specific label was escaped. This is acceptable: T-FB-11/12a provide live XSS
proof for content and listing respectively; the static check is belt-and-suspenders. No action needed.

NB-2: **`_is_confined` at enumeration** checks `os.path.islink` first (line 438) to skip symlinks
before the realpath check (line 454). The re-check at view time (line 711) also calls `_is_confined`
which covers the symlink case via `realpath`. Both layers are redundant by design (defense-in-depth).
No action needed.

NB-3: **Python < 3.10 fallback** (lines 413–423): the `root_dir` kwarg is not supported in Python
< 3.10; the fallback uses `os.path.join(repo_path, glob_pattern)` + `os.path.relpath`. This is
correct and the relpath conversion preserves the no-path-from-URL invariant (glob patterns are server
constants, not URL-derived). No action needed.

---

## 11. Blocking issues

None.

---

## 12. Recommended next action

Squash-merge `feat/fleet-filebrowser` → main (VERSION 0.26.0). Auto-merge-on-green applies per
owner's policy (2026-06-19 decision log).

---

## Condition summary

| Condition | Verified |
|-----------|---------|
| No path-from-URL (structural + live) | YES |
| Double set-membership | YES |
| `[a-f0-9]{16}` regex gate | YES |
| Taxonomy glob closed (server-side constants) | YES |
| Symlink excluded at enumeration + realpath backstop | YES |
| Dotfile excluded (`.agent_tasks` exemption correct) | YES |
| Secret-name excluded | YES |
| Binary-sniff exclusion | YES |
| `_is_confined` at both enumeration and view | YES |
| `MAX_VIEW_BYTES = 262144` + truncation notice | YES |
| XSS escape via `_board_html_escape` + sed pipeline | YES |
| GET-only (POST → 404) | YES |
| BIND_HOST = 127.0.0.1 unchanged | YES |
| `set -euo pipefail` | YES |
| Read-only (zero writes) | YES |
| bin/massoh + manifest.yml + safety-critical files diff=0 | YES |
| VERSION 0.26.0 + CHANGELOG [0.26.0] | YES |
| T-FB-1..17 all real (live-HTTP, non-stub) | YES |
| Suite 676/676 green (self-run) | YES |
| PID-scoped teardown (live 8787 dashboard untouched) | YES |
