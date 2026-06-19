# 04 — Implementation Packet (LICENSE TO CODE): `massoh board --local` (24h queue #8)

- **Task ID:** TASK-2026-06-19-board-renderer
- **Issued after:** arch-safety APPROVED (`03`, BR1–BR8) + owner batch-auth + auto-merge-on-green. No sign-off (manifest untouched).
- **Target VERSION:** **0.15.0** (after #6=0.13.0, #9=0.14.0). Rebase onto latest main; set VERSION to current-main minor + 1 at implementation time if order shifts.
- **Branch:** `feat/board-renderer`. Implement after #6 + #9 land (serialize on main tree).

## Scope
Add `--local [--out <dir>]` to `massoh board`: emit a self-contained HTML kanban (`agent-project/board.html`)
+ an Obsidian-Kanban `BOARD.md` (`agent-project/BOARD.md`) from the SAME model `_board_build_model`
produces. **No network, no token, no jq on the --local path.** `--push plane` byte-identical.

## Mandatory conditions BR1–BR8 (from `03`; cite file:line in `05`)
- **BR1** reuse `_board_build_model` (no second TASK-*/ scanner; exactly 2 call sites).
- **BR2** (highest) `_board_html_escape` (sed: `&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`, in that
  order) applied to EVERY interpolated field (title, desc, task_id, stage, last_agent, priority,
  cost_tokens) before printf into HTML. Enumerate all fields — missing one = injection.
- **BR3** BOARD.md cells strip `|`→`/` and newlines→space (tr/sed, no jq).
- **BR4** move the jq guard from the top of `cmd_board` INTO the `push_plane=1` branch; zero jq in the
  local emitters (`grep -n jq` confirms).
- **BR5** write to `agent-project/board.html` + `BOARD.md` (or `--out <dir>`); overwrite only if the
  file carries the generator sentinel `<!-- massoh-generated -->` (HTML) / equivalent (MD); refuse +
  error if it exists WITHOUT the sentinel (hand-authored); `--out` always overwrites in that dir.
- **BR6** `_board_push_plane` unmodified; T17–T23 stay 100% green.
- **BR7** no network / no secret reads on --local (move `.env.massoh` source + curl into push branch).
- **BR8** set -euo pipefail + `|| true` on new grep/awk/sed/git; clean abort on write failure.

## Required tests T-BR-1…12 (12 new; suite → target baseline+12)
Per `03`: malicious-title HTML-escaped (no raw `<script>`); both files emitted; sentinel present;
`|` stripped in BOARD.md; jq-absent PATH → --local exits 0 + both files; T17–T23 regression green;
hand-authored file (no sentinel) → refuse, unchanged; `--out` redirects, no default-path side effect;
static grep curl only in `_board_push_plane`; two sequential runs ok single sentinel; exactly 2
`_board_build_model` call sites; zero TASK dirs → exit 0 empty board. Run `bash test/run.sh` green.

## Acceptance criteria
1. BR1–BR8 satisfied (file:line). 2. T-BR-1…12 green; suite green; verbatim output + the
malicious-title escape proof. 3. `--push plane` unchanged (T17–T23 green). 4. VERSION 0.15.0.

## Rollback
`git revert`; `rm agent-project/board.html agent-project/BOARD.md`. No irreversible state.

## Routing
`massoh-implementer` (branch `feat/board-renderer`, off latest main) → `05` → `massoh-reviewer-qa` (06)
→ auto-merge on green.
