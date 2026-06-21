# 04 — License: Control plane track A, slice A2 — file browser (READ-ONLY)

- **Gate:** architect `01_A2_design.md` (safe enumeration model + confinement + T-FB-1..17) + the 8h
  away-grant. Verdict: **SHIPS read-only under the grant — NO fresh owner sign-off** (same read-only
  GET-over-loopback risk class as 1a/1b; path-from-URL structurally impossible). Build straight from
  `01_A2_design.md` §1–§6 (file:line hooks, route shapes, id scheme, cap, taxonomy, tests).
- **Branch:** `feat/fleet-filebrowser` (off current main — serialize after B0; both touch
  fleet.sh/dashboard). **VERSION → 0.26.0**; CHANGELOG [0.26.0].

## Scope (read-only file VIEW on the per-repo view `/repo/<name>`)
Let the owner see + read generated artifacts per repo, grouped by what they are. NO write/exec.
1. **Files panel** in `_fleet_render_repo` (lib/verbs/fleet.sh): list the repo's allowlisted artifacts
   grouped by the design's category taxonomy (task packets, briefs, *.proposed.md, governance,
   ledger/metrics, …), each with a human-readable label + a link to its view route.
2. **View route** `GET /repo/<name>/file/<id>` (scripts/massoh-dashboard): renders one file read-only,
   HTML-escaped. `<id>` = the design's opaque id (`[a-f0-9]{16}` = `sha256(relpath)[:16]`).

## Mandatory conditions (from `01_A2_design.md`; cite file:line in `05`)
- **No path-from-URL / no arbitrary read.** Server builds the per-repo `opaque_id → repo-relative-path`
  map server-side by globbing the closed taxonomy rooted at the **trusted** `repo_path` (from
  `repo_name_map`, NEVER the URL). View route accepts ONLY a known id via **double set-membership**
  (name ∈ repo_name_map, then id ∈ that repo's file map); 404 everything else. No byte of the URL is
  ever joined onto a filesystem path. `<id>` must match `^[a-f0-9]{16}$` before lookup.
- **Confinement + hardening:** exclude secrets/dotfiles/binaries/escaped-symlinks **at enumeration**
  (no id ⇒ unreachable); `realpath` repo-root re-check before any read; **256 KiB size cap** (truncate
  large files with a visible notice). GET-only — no POST/exec/write; loopback-only unchanged.
- **Escape everything** via `_board_html_escape` (file contents, names, labels, category headers).
- `set -euo pipefail`; degrade per panel (missing dir/file → "—", never crash); no new write target.
- Non-control + control modes both unchanged except the additive read route/panel; bin/massoh +
  manifest.yml + safety-critical files **diff = 0**.

## Required tests T-FB-1..17 (from `01_A2_design.md`; live-HTTP style mirroring T-FS-*)
incl: `/repo/<name>` shows the Files panel grouped by category with escaped labels; known id → 200 +
escaped content; `..` / `%2e%2e` / absolute-path / unknown-id / non-hex id → 404; a dotfile/secret/
binary has NO id and is unreachable (404); >256 KiB file truncated with notice; file with
`<script>`/`|` in content+name → escaped; read-only byte-snapshot of discovered fake repos unchanged
across renders; POST → 404; no orphan server (PID-scoped teardown — NOT broad pkill). Run
`bash test/run.sh` green.

## Acceptance
1. Conditions (file:line). 2. T-FB-1..17 green; suite green; paste: a repo-view Files-panel sample,
a known-id 200 with escaped content, the traversal/unknown-id/non-hex 404s, the secret-unreachable
proof, the size-cap truncation, read-only snapshot. 3. VERSION 0.26.0 + CHANGELOG. 4. No safety-critical
file; GET-only (POST=404); bin/massoh + manifest untouched.

## Routing
`massoh-implementer` (branch `feat/fleet-filebrowser`, off current main) → `05_A2_handoff.md` →
`massoh-reviewer-qa` (verify no-path-from-URL + confinement + size-cap + escape + read-only + audit-N/A)
→ auto-merge on green.
