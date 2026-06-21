# 00 — Design request: Control plane track A, slice A2 — file browser (READ-ONLY)

- **Date:** 2026-06-21 · owner asked: *"access each file generated, understand what it is."*
- **Covered by:** the read-only fleet model (N1–N7) + the 8h away-grant (read-only, zero-spend, no
  new safety-critical risk class). **This is a DESIGN call** because a "file browser" is precisely the
  risk the architect flagged for the fleet server: *"server = route-allowlist transport, NOT a file
  server."* The load-bearing question is how to let the owner view generated artifacts **without** the
  server becoming an arbitrary-filesystem-read surface.

## What the owner wants (read-only)
On the per-repo dashboard view (`/repo/<name>`), let the owner:
1. **See the generated artifacts** for that repo, grouped by what they are — task packets
   (`.agent_tasks/TASK-*/0X_*.md`), briefs (`agent-project/briefs/*.md`), proposed drafts
   (`*.proposed.md`), governance (AGENT_SYNC / AGENT_BACKLOG), ledger/metrics.
2. **Understand what each file is** — a human-readable label/category per file (not just a path).
3. **View a file's contents** read-only, HTML-escaped, in the browser.

## The design must answer (load-bearing safety)
- **No path-from-URL / no arbitrary read.** Mirror the existing set-membership model: the server
  enumerates an **allowlisted set** of files server-side (per repo, by known category/glob), assigns
  each a stable opaque id, and a view route accepts only that id (404 on anything else). NO user-
  supplied path is ever joined to the filesystem. Reject `..`, `%2e`, absolute paths, symlinks-escape.
- **Confine to the repo root + the known artifact categories.** Never serve outside the discovered
  repo's tree; never serve secrets/dotfiles/binaries; cap file size (truncate large files w/ notice).
- **Read-only / GET-only.** No POST, no exec, no write. Loopback-only unchanged. (Writes = track B.)
- **Escape everything** via `_board_html_escape` (file contents, names, labels).
- **Degrade per panel** (missing dir/file → "—", never crash); `set -euo pipefail`.
- Classify the risk: is read-only file VIEW (allowlisted-id, no path-from-URL, size-capped, repo-
  confined, escaped) covered by the existing read-only model + away-grant, or does it need its own
  owner sign-off? (Recommendation expected: covered IF the allowlist/no-path-from-URL guard holds.)

## Deliverable
`.agent_tasks/TASK-2026-06-21-control-plane/01_A2_design.md` — the safe file-enumeration model
(allowlist + opaque-id route, no path-from-URL), confinement + size cap + secret-exclusion rules,
the per-repo artifact taxonomy (categories → globs → labels), required tests (incl. traversal/`..`/
absolute-path/unknown-id → 404, size-cap, escape, read-only byte-snapshot), and whether it ships
under the away-grant or needs a fresh sign-off. Then route to implementer if green under the grant.

## Routing
`massoh-system-architect` → `01_A2_design.md` → (if read-only & covered by grant) `04_A2-file-browser.md`
license → `massoh-implementer` (branch `feat/fleet-filebrowser`) → `massoh-reviewer-qa` → auto-merge on green.
If the architect says it needs a fresh owner sign-off → PARK for owner, do not build.
