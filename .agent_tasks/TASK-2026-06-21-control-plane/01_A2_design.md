# 01 — A2 design: read-only file browser (allowlist + opaque-id, NO path-from-URL)

- **Task:** TASK-2026-06-21-control-plane · **Slice:** A2 (read-only file browser on the fleet dashboard)
- **Author:** massoh-system-architect · **Date:** 2026-06-21 · **Mode:** ARCHITECTURE_SAFETY (design-only)
- **Request:** `00_A2_design_request.md` — *"access each file generated, understand what it is."*
- **Prior review (THE constraint):** `.agent_tasks/TASK-2026-06-20-fleet-observability/00_architecture_review.md`
  §4 R2 / N2 — *"server = route-allowlist transport, NOT a file server."*
- **Verdict in one line:** **SHIPS under the existing read-only model + the 8h away-grant.** A view that
  strictly cannot read an attacker-supplied path is the same risk class as the already-shipped read-only
  GET views (1a/1b), not a new one. **Recommend: proceed to a `04_A2-file-browser.md` license now.**

---

## 0. The single load-bearing invariant (everything else serves this)

> **No byte of any HTTP request is ever joined onto a filesystem path.**

The server already proves this twice (`scripts/massoh-dashboard`):
- **repos:** `/repo/<name>` → `<name>` is looked up in `self.repo_name_map` (set-membership);
  `repo_path` comes from the map value, never from the URL (lines 161-173, 414-421).
- **tasks:** `/repo/<name>/task/<id>` → `<id>` is checked for membership in
  `_discover_tasks_for_repo(repo_path)` (a set built server-side), then the dir is built from the
  **trusted** `repo_path` + the **validated** `id` (lines 176-206, 382-406).

A2 is the **third instance of the exact same pattern**, one level deeper: a per-repo **file map**
(`opaque-id → relative-path`) built server-side by globbing an allowlist, where the view route accepts
**only a known id** and 404s everything else. The id is opaque; it is never decomposed into a path. This
is the file-level analogue of `repo_name_map` and the task set — mirror them precisely.

---

## 1. Safe enumeration model — opaque-id map (mirror `repo_name_map`)

### 1.1 The map (server-side, built per request, never from the URL)

Add one discovery function to `scripts/massoh-dashboard`, modeled on `_discover_tasks_for_repo`
(lines 176-206):

```
_discover_files_for_repo(repo_path) -> dict   # opaque_id (str) -> relative_path (str, repo-relative)
```

How it is built (server-side only):
1. Start from the **trusted** `repo_path` taken from `self.repo_name_map[name]` (NEVER the URL).
2. For each entry in the **artifact taxonomy** (§3) — a fixed `(category, glob, label)` list baked into
   the server — run the glob **rooted at `repo_path`** using Python `glob.glob(root=repo_path, ...)` or
   an explicit `os.walk` confined to the allowlisted subtrees. The glob patterns are **server-owned
   constants**; none come from the request.
3. For every matched file, apply the **confinement + exclusion filter** (§2). Survivors only.
4. Assign each survivor a **stable opaque id**:
   ```
   opaque_id = hashlib.sha256(relative_path.encode("utf-8")).hexdigest()[:16]
   ```
   - **Stable:** same relative path → same id across requests/restarts (no per-run salt). The owner can
     bookmark a file URL.
   - **Opaque:** the id is a hex digest, not a path. It carries no traversal payload and cannot be
     "decoded" into a path by an attacker.
   - **Collision policy:** 16 hex chars = 64 bits; with the ≤ a few-hundred-file cap (§2) collision
     probability is negligible. On the astronomically unlikely collision, **first-glob-wins is
     deterministic** (insertion order); the loser is simply not addressable (degrade, never crash).
5. Cap the map at **500 entries per repo** (mirrors the FL4 `head -n 200` / task cap discipline; pick
   500 because artifacts span tasks×stages + briefs + governance). Beyond the cap: stop globbing, render
   a "list truncated — N shown of many" notice. Append-only spirit: nothing is deleted, just not listed.

The map is built **fresh per view request** (like `_discover_tasks_for_repo`), so newly generated
artifacts appear on the next page load — consistent with the 30s meta-refresh model. (Optional, NOT
required: cache it for the listing+view of a single request to avoid a double glob.)

### 1.2 The routes (extend the existing allowlist — `do_GET`, lines 367-427)

Two new GET routes, slotted into the existing route-allowlist `if`-ladder. **GET-only.** Both validated
by **double set-membership** (repo name in `repo_name_map`, then file id in the file map):

| Route | Purpose | Validation |
|---|---|---|
| `GET /repo/<name>/files` | the **listing** (taxonomy table: label · category · id-link) | `<name>` ∈ `repo_name_map` else 404 |
| `GET /repo/<name>/file/<id>` | **view one file's contents** (escaped, size-capped) | `<name>` ∈ `repo_name_map` AND `<id>` ∈ `_discover_files_for_repo(repo_path)` else 404 |

Regexes (mirror `_REPO_NAME_RE` / `_TASK_VIEW_RE`, lines 293-299; `<id>` is `[a-f0-9]{16}` — hex only,
so even the regex rejects any traversal/encoding before the set-membership check):

```python
_FILES_LIST_RE = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/files$")
_FILE_VIEW_RE  = re.compile(r"^/repo/([A-Za-z0-9_.~\-]+)/file/([a-f0-9]{16})$")
```

**Route precedence (insert order in `do_GET`):** check `/file/<id>` and `/files` **before** the
existing `_REPO_NAME_RE` branch (so `/repo/x/files` isn't mis-matched). Place them right after the
`_TASK_VIEW_RE` block (after line 406), exactly where the task route sits relative to the repo route.

### 1.3 The view handler (the only place a file is read — server-side, from the map value)

```
do_GET → _FILE_VIEW_RE match:
  repo_name = unquote(group1)
  if repo_name not in self.repo_name_map: 404            # set-membership #1
  repo_path = self.repo_name_map[repo_name]               # trusted value, NOT from URL
  file_map = _discover_files_for_repo(repo_path)           # server-built id->relpath
  file_id = group2                                         # already [a-f0-9]{16} by regex
  if file_id not in file_map: 404                          # set-membership #2  (NO path-from-URL)
  rel = file_map[file_id]                                  # trusted relpath from the map
  abs_path = os.path.join(repo_path, rel)                  # repo_path trusted, rel server-built
  # FINAL belt-and-suspenders confinement re-check (§2.1) before any read:
  if not _is_confined(abs_path, repo_path): 404
  body = _render_file_view(repo_name, repo_path, rel, abs_path)   # Seam A: bash renders+escapes
  self._send_html(body)
```

`abs_path` is built from a **trusted root** + a **server-generated relative path**; the only attacker
input (`file_id`) is used solely as a dict key. This is byte-for-byte the task-route discipline.

---

## 2. Confinement + hardening

### 2.1 Repo-root confinement (defense-in-depth, even though rel is server-built)

`_is_confined(abs_path, repo_path)` (server-side, before any read):
```python
real_root = os.path.realpath(repo_path)
real_file = os.path.realpath(abs_path)             # resolves symlinks
return (real_file == real_root or
        real_file.startswith(real_root + os.sep)) and os.path.isfile(real_file)
```
- `os.path.realpath` resolves symlinks, so a **symlink inside an allowlisted dir pointing outside the
  repo** (e.g. `agent-project/briefs/evil -> /etc/passwd`) resolves to `/etc/passwd`, fails the
  `startswith(real_root)` test, and 404s. **Symlink-escape closed.**
- The glob step in §1.1 must also skip symlinks at enumeration time (`os.path.islink` → skip) so escaped
  symlinks never even get an id. Confinement is enforced **twice** (enumerate + view).
- `..`, `%2e`, absolute paths: cannot occur — `rel` is server-built from a glob rooted at `repo_path`,
  and the URL `<id>` is hex-only and used only as a dict key. The realpath check is the backstop.

### 2.2 Secret / dotfile / binary exclusion (enumeration filter — survivors only get an id)

A file is **excluded from the map** (so it has no id and is unreachable) if ANY holds:
- **Dotfile / dot-dir:** any path component starts with `.` — EXCEPT the two allowlisted artifact
  roots `.agent_tasks/` (task packets) and the project marker is irrelevant. (We allow descent **into**
  `.agent_tasks/` because it is an artifact root, but reject `.git/`, `.env`, `.ssh`, `.massoh`,
  `.DS_Store`, any other dotfile.) Implementation: split the **repo-relative** path on `os.sep`; reject
  if any component other than the literal `.agent_tasks` begins with `.`.
- **Secret-name denylist** (case-insensitive substring on basename): `secret`, `token`, `password`,
  `passwd`, `credential`, `.pem`, `.key`, `id_rsa`, `.env`, `apikey`, `api_key`, `htpasswd`.
- **Binary / non-text:** extension allowlist is the primary gate — only `.md`, `.txt`, `.tsv`, `.csv`,
  `.log`, `.json`, `.yml`, `.yaml` are eligible (the taxonomy globs already encode this). As a backstop,
  read the first 1024 bytes and if a NUL byte (`\x00`) is present, exclude (binary-sniff).
- **Not a regular file:** dirs, FIFOs, sockets, symlinks → excluded.

Because exclusion happens **at enumeration**, an excluded file has **no opaque id at all** → its view
URL cannot be constructed → 404 by set-membership. This is strictly stronger than per-request filtering.

### 2.3 Size cap (concrete)

- **`MAX_VIEW_BYTES = 262144` (256 KiB).** Named constant next to `MAX_BODY_BYTES = 8192` (line 65).
- Read at most `MAX_VIEW_BYTES + 1` bytes. If the file is larger, pass **only the first 256 KiB** to the
  bash renderer plus a `truncated=1` flag; the renderer prepends a visible notice:
  *"⚠ Showing first 256 KiB of N KiB — file truncated for display (read-only view)."* Never load the
  whole file into memory; never stream an unbounded body.
- Rationale: artifacts are markdown/TSV; 256 KiB covers every realistic packet/brief/ledger while
  bounding render time + escape cost (escaping is O(n)). 256 KiB is well above the largest plausible
  artifact and well below a memory/DoS concern on loopback single-user.

### 2.4 Method + transport hardening (reuse existing guards)

- **GET-only.** `do_POST` already 404s without `--control` (lines 432-435); A2 adds **no POST route** —
  even `--control` mode gains no write surface here. `do_HEAD` already 404s (lines 429-430). No exec, no
  write, no token spend (N6).
- **Loopback-only** unchanged: `BIND_HOST = "127.0.0.1"`, host not configurable (N1, lines 59, 694-697).
- **No auth required** for the view: this matches the existing read-only trust model — `massoh fleet`
  already prints these same artifacts to stdout, and `board --local` already writes a readable HTML of
  task data. A2 surfaces the **same already-local-readable content** through the same loopback GET
  surface; it adds **no new exposure** beyond what 1a/1b already established. (The §4 R4 ruling: "read =
  contained under existing trust model.")
- **Graceful degrade / `set -euo pipefail`:** missing file/dir → "—" / "(file not found)" notice, never
  crash (N4 + the panel-degrade discipline used throughout `fleet.sh`).

---

## 3. Artifact taxonomy (category → glob → label)

Baked into the server as a fixed ordered list of `(category, glob, label_template)`. Globs are rooted at
`repo_path` (§1.1). The **label** is what makes the owner "understand what each file is." All globs use
the extension allowlist (§2.2). `**` = recursive within the named root only.

| # | Category | Glob (rooted at repo_path) | Human label (per file) |
|---|---|---|---|
| 1 | Task packet | `.agent_tasks/TASK-*/0*_*.md` | `Packet · <TASK-id> · <stage from NN prefix>` (00=request, 01/02=product-scope, 03=arch-safety, 04=impl-packet, 05=handoff, 06=review) |
| 2 | Task ledger | `.agent_tasks/ledger.tsv` | `Ledger · time/token/cost (TSV)` |
| 3 | Task other | `.agent_tasks/TASK-*/*.md` (not matched by #1) | `Task note · <TASK-id> · <basename>` |
| 4 | Brief | `agent-project/briefs/*.md` | `Brief · <basename>` |
| 5 | Proposed draft | `**/*.proposed.md` (within `agent-project/` + repo root) | `Proposed draft · <relpath>` |
| 6 | Governance — sync | `AGENT_SYNC.md` | `Governance · AGENT_SYNC (mode / handoff / decisions)` |
| 7 | Governance — backlog | `AGENT_BACKLOG.md` | `Governance · AGENT_BACKLOG (queue)` |
| 8 | Governance — now/next | `agent-project/NOW_NEXT_LATER.md` | `Governance · NOW/NEXT/LATER` |
| 9 | Governance — charter | `agent-project/CHARTER.md`, `agent-project/NON_NEGOTIABLES.md` | `Governance · <basename>` |
| 10 | Metrics | `agent-project/METRICS.md` | `Metrics · snapshots` |
| 11 | Learnings | `agent-project/LEARNINGS.proposed.md`, `agent-project/FLEET_LEARNINGS.proposed.md`, `agent-project/META.proposed.md` | `Learnings · <basename>` |
| 12 | ADR | `docs/adr/*.md` | `Decision (ADR) · <basename>` |

Notes:
- The list is **closed**: nothing outside these roots is enumerated. `bin/`, `lib/`, `scripts/`,
  `templates/`, `manifest.yml`, `VERSION`, source code — **not in the taxonomy → no id → unreachable.**
  (The viewer is for *generated artifacts*, not source. This also keeps safety-critical files off the
  surface entirely.)
- Category #5 (`*.proposed.md`) deliberately surfaces drafts so the owner can review proposals — these
  are exactly "generated artifacts," already local-readable, advisory-only.
- Stage parsing for label #1 is a small server-side dict (`{"00":"request", "01":"product-scope", ...}`)
  keyed off the `NN_` filename prefix — pure presentation, no path use.

---

## 4. Rendering (Seam A — bash renders + escapes; server is transport)

Add **one** renderer to `lib/verbs/fleet.sh`, mirroring `_fleet_render_task` (fleet.sh lines 894-1091):

```
_fleet_render_file_list <repo> <repo_name> <map_tsv>      # the /files listing
_fleet_render_file_view <repo_name> <rel> <abs_path> <truncated:0|1>   # the /file/<id> view
```

- **`_fleet_render_file_list`** receives the server-built map as a TSV passed as **one argv element**
  (`opaque_id<TAB>category<TAB>label<TAB>relpath\n...`, like the ledger TSV pattern at fleet.sh
  1023-1047). It emits a `task-list` table: **Label · Category · [view]** where `[view]` links to
  `/repo/<url_name>/file/<id>`. Every cell goes through `_board_html_escape` (N4). It reuses
  `_fleet_html_header` / `_fleet_html_footer` and the breadcrumb pattern (lines 325, 915-919). The
  server builds the map (ids/relpaths) — bash only renders it (no globbing in bash; no business logic in
  the server beyond globbing the allowlist).
- **`_fleet_render_file_view`** receives the **already-size-capped** content via stdin (the server pipes
  ≤256 KiB to `bash -c` stdin; the renderer does `cat`/`read` it) OR reads `abs_path` itself with a
  `head -c 262144` cap — **prefer the latter**: bash reads the file with `head -c "$MAX"`, pipes through
  `_board_html_escape`, and wraps it in `<pre>`. This keeps the file read + escape in the one audited
  bash place and matches `_fleet_render_task`'s "bash reads, bash escapes" model. The server passes
  `abs_path` (trusted) + `truncated` flag as argv (like `_fleet_render_task`'s `task_dir` arg, line 660).
  - The view shows: breadcrumb (`/ › /repo/<name> › /repo/<name>/files › <label>`), the human label +
    relpath (escaped), the truncation notice if `truncated=1`, then `<pre>ESCAPED CONTENT</pre>`.
  - **N4 critical:** file **contents** are repo data → `_board_html_escape` before `<pre>`. File
    **name/label/relpath** are also escaped. A `*.md` containing `<script>` renders inert.

The server adds **zero** HTML interpolation (the existing `_run_bash_renderer` discipline, lines
213-278; the token-sentinel trick is irrelevant here — no token, no form, GET-only).

The `/files` listing link is surfaced from `_fleet_render_repo` (fleet.sh 316-406): add one line in the
per-repo view — e.g. under a new `<h2>Generated files</h2>` — linking to `/repo/<url_name>/files`
(reusing the existing `url_name` minimal-percent-encoding at line 686). Additive, read-only.

---

## 5. Required tests (T-FB-*, additive to `test/run.sh`)

Mirror the live-HTTP T-FS style (`test/run.sh` ~3155-3448): free-port helper `_fs_free_port`, start
`python3 "$DASHBOARD" --port "$PORT"` with `MASSOH_FLEET_ROOT="$FS_FLEET_ROOT" MASSOH_HOME="$REPO_ROOT"`,
poll readiness with `curl --connect-timeout`, assert with `check`, and a SIGTERM/no-orphan teardown.
Reuse the existing fake fleet repos (`FS_REPO_A`/`FS_REPO_B`, `_mk_fleet_repo` at ~3284) plus a few new
fixture files. Guard the whole block on `command -v python3`.

Fixtures to add to `FS_REPO_A` before the suite:
- `agent-project/briefs/sample-brief.md` (normal),
- a `*.proposed.md` draft,
- a file whose **contents** contain `<script>alert("fb")</script> & "x"` (XSS-in-contents),
- a file whose **name** contains markup-ish chars within the safe class (XSS-in-name path is mostly
  blocked by the regex/escape; assert the rendered listing escapes the label),
- a **secret-named** file `agent-project/secret-token.md` (must NOT be enumerated),
- a **large** file `> 256 KiB` (truncation),
- a **symlink** `agent-project/briefs/escape.md -> /etc/hostname` (symlink-escape must 404),
- a `.git/config`-style dotfile already present (must NOT be enumerated).

| Test | Asserts |
|---|---|
| **T-FB-1** | `GET /repo/alpha-repo/files` → 200, contains the `task-list` table + a `Brief` label + a `/file/` link. |
| **T-FB-2** | `GET /repo/alpha-repo/files` → contains the **stage label** for a packet (e.g. `Packet`/`request`) — owner can tell what each file is. |
| **T-FB-3** | Extract a real id from the listing; `GET /repo/alpha-repo/file/<id>` → 200, contains the file content in `<pre>`. |
| **T-FB-4** | `GET /repo/alpha-repo/file/<unknown-16-hex>` (valid shape, not in map) → **404** (set-membership). |
| **T-FB-5** | `GET /repo/alpha-repo/file/..%2f..%2fetc%2fpasswd` → **404** (regex rejects non-hex id; no path-from-URL). |
| **T-FB-5b** | `GET /repo/alpha-repo/file/../../../../etc/passwd` (raw `..`) → **404**. |
| **T-FB-5c** | `GET /repo/alpha-repo/file/0000000000000000` (absolute-path-like / all-zero id not in map) → **404**. |
| **T-FB-6** | `GET /repo/<unknown-repo>/files` and `/file/<id>` → **404** (repo set-membership). |
| **T-FB-7** | Symlink-escape: the file map does **not** contain `escape.md`; constructing its would-be view → 404 (assert listing has no link whose realpath leaves repo; and that `/etc/hostname` content never appears in any view body). |
| **T-FB-8** | Secret exclusion: `secret-token.md` is **absent** from the listing (no id, unreachable). |
| **T-FB-9** | Dotfile exclusion: nothing under `.git/` appears in the listing. |
| **T-FB-10** | Size cap: the >256 KiB file's view contains the **truncation notice** and the body length is bounded (≤ ~256 KiB + chrome); the tail bytes are absent. |
| **T-FB-11** | XSS-in-contents: view body has **no raw** `<script>alert("fb")`; the **escaped** `&lt;script&gt;` IS present in `<pre>`. |
| **T-FB-12** | XSS-in-name: the listing escapes the label/relpath (no raw markup from the filename). |
| **T-FB-13** | POST: `POST /repo/alpha-repo/file/<id>` and `POST /repo/alpha-repo/files` → **404** (GET-only; no write surface even with `--control`). |
| **T-FB-14** | Read-only byte-snapshot: md5 of `FS_REPO_A` (excluding `.git`) **unchanged** after listing + viewing several files (reuse the T-FS-12 snapshot idiom). |
| **T-FB-15** | No orphan: SIGTERM the server; assert `! kill -0 $PID` (reuse T-FS-14 idiom). |
| **T-FB-16** | Source guard (static): `scripts/massoh-dashboard` file-view path uses `realpath`-confinement and the map lookup; assert no `translate_path`/`SimpleHTTPRequestHandler` introduced (mirror T-FS-3 source checks). |
| **T-FB-17** | Loopback still hard-coded (`BIND_HOST = 127.0.0.1`) after the A2 edit (mirror T-FS-13). |

T-FB-4/5/5b/5c/6/7/8/9 are the **load-bearing** "no arbitrary read" battery; T-FB-10 the cap; T-FB-11/12
the escape; T-FB-13 GET-only; T-FB-14 read-only. All additive; no existing test changed.

---

## 6. Where it hooks in (file:line anchors for the implementer)

`scripts/massoh-dashboard`:
- Add `MAX_VIEW_BYTES = 262144` next to `MAX_BODY_BYTES` (line 65).
- Add `_discover_files_for_repo(repo_path)` + the taxonomy constant + `_is_confined()` near
  `_discover_tasks_for_repo` (lines 176-206).
- Add `_FILES_LIST_RE` / `_FILE_VIEW_RE` next to `_TASK_VIEW_RE` (lines 293-299).
- Add the two route branches in `do_GET` **after** the `_TASK_VIEW_RE` block (after line 406), **before**
  the `_REPO_NAME_RE` branch (line 409).
- Add `_render_file_list` / `_render_file_view` methods next to `_render_task` (lines 645-662), each
  shelling `_run_bash_renderer` (lines 213-278) — no new server-side HTML.

`lib/verbs/fleet.sh`:
- Add `_fleet_render_file_list` / `_fleet_render_file_view` after `_fleet_render_task` (after line 1091),
  reusing `_fleet_html_header`/`_fleet_html_footer`/`_board_html_escape` and the breadcrumb + `url_name`
  encoding (lines 686, 915-919). File read uses `head -c "$MAX"` (cap) → `_board_html_escape` → `<pre>`.
- Add the `<h2>Generated files</h2>` + `/repo/<url_name>/files` link inside `_fleet_render_repo`
  (lines 316-406), additive.

`test/run.sh`: add the `== T-FB: fleet read-only file browser ==` block after the T-FS suite (after
line 3448), reusing `_fs_free_port`, `_mk_fleet_repo`, the start/poll/teardown idiom, and `check`.

**No edits** to `bin/massoh`, `manifest.yml`, `templates/*`, `NON_NEGOTIABLES.md`, or any safety-critical
file. `scripts/` and `lib/verbs/fleet.sh` already ride the existing install/doctor wiring (per the prior
review §2). No new verb; no new dispatch line. The `fleet serve` lifecycle is unchanged.

---

## 7. Gating verdict — SHIPS under the read-only model + away-grant

**Recommendation: PROCEED to a `04_A2-file-browser.md` license now. No fresh owner sign-off required.**

Reasoning, mapped to the grant's three reserved triggers:

1. **New safety-critical risk class?** No. The grant + prior review (§4) already established that
   **read-only GET over loopback of the owner's own already-local-readable artifacts** is *within* the
   envelope (1a/1b shipped on exactly that basis). A2 is the **same risk class, same transport, same
   set-membership discipline** — it just adds a third (file-level) set lookup beneath the existing repo
   and task lookups. Crucially, the one thing that *would* make a file browser a new risk class —
   **path-from-URL / arbitrary filesystem read** — is **structurally impossible** here: opaque hex ids,
   server-built map, double set-membership, allowlist-glob enumeration, realpath confinement, symlink +
   secret + dotfile + binary exclusion, 256 KiB cap, GET-only. The N2 "index-not-path" invariant the
   architect flagged is **honored, not violated** — A2 is its natural extension.
2. **Irreversible / destructive op?** No. Zero writes (append-only spirit is trivially satisfied — there
   are no writes at all). Read-only byte-snapshot is a required test (T-FB-14).
3. **Paid-API spend / cost?** No. Zero tokens, no agent exec, no network egress (loopback-only). N6 holds.

This is precisely the line the request anticipated: *"a file VIEWER that strictly cannot read arbitrary
paths is arguably within [the away-grant]."* The allowlist + no-path-from-URL guard **does** hold (it is
the same guard already shipped and tested for repos/tasks), so the conditional resolves to **covered**.

**Distinction from track B (which DID need signature #1):** B is **write/exec** on the loopback surface
(POST → intake, file edits, restart) — a genuinely new risk class the owner signed off on per-tier. A2
is **read-only VIEW** — the opposite end. It belongs with A1's read panels, not with B's write tiers.
Surfacing it under the existing read-only authorization is consistent and not an over-reach.

**One honest caveat (does not change the verdict):** A2 makes artifact contents *one click more
visible* in the browser than the prior task drill-down (which showed only first-lines, fleet.sh
958-961). The content was always local-readable (the files are on the owner's disk; `cat`/`massoh fleet`
already expose them), the surface is still loopback-only GET, and the exclusion filter keeps
secrets/dotfiles/source off it. So this is a *convenience* delta, not a *risk-class* delta. If the owner
later wants the file VIEW gated behind `--control` like the write form (defense-in-depth, not necessity),
that is a trivial, reversible follow-up — but it is **not required** to ship safely under the grant.

---

## 8. Handoff

```
Agent: massoh-system-architect
Mode: ARCHITECTURE_SAFETY (design-only)
Task: TASK-2026-06-21-control-plane / slice A2 (read-only file browser)
Status: DESIGN COMPLETE. Verdict: SHIPS under read-only model + 8h away-grant (no fresh sign-off).

Model: per-repo server-built map opaque_id(sha256[:16] of repo-relative path) -> relpath, built by
       globbing a CLOSED artifact taxonomy rooted at the TRUSTED repo_path; GET /repo/<name>/file/<id>
       accepts ONLY a known id (double set-membership: name in repo_name_map, id in file map) — 404
       otherwise; NO byte of the URL is ever joined onto a path. Mirrors repo_name_map + the task set.
Hardening: allowlist-glob enumeration (survivors only get an id) → secret/dotfile/binary/symlink
       excluded at enumeration; realpath repo-root confinement re-check before read; 256 KiB size cap
       with truncation notice; GET-only (no POST even with --control); loopback-only; escape in bash
       (_board_html_escape) — contents + names + labels.
Tests: T-FB-1..17 additive to test/run.sh, live-HTTP T-FS style (traversal/unknown-id/secret/symlink →
       404; size-cap truncation; XSS-in-contents + in-name escape; POST → 404; read-only byte-snapshot;
       no-orphan; loopback source guard).
Hooks: scripts/massoh-dashboard (discovery + 2 routes + 2 render methods); lib/verbs/fleet.sh (2 bash
       renderers + a files link in _fleet_render_repo); test/run.sh (T-FB block). NO safety-critical
       file touched; no bin/massoh / manifest.yml / templates edit; no new verb.

Next agent: massoh-implementer (after a 04_A2-file-browser.md license is cut)
Next action: cut 04_A2-file-browser.md from this design, branch feat/fleet-filebrowser, build straight
             from §1-§6, run T-FB-* green, route to reviewer-qa, auto-merge on green per the grant.
```
