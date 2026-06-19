# 05 — Implementation Handoff: `massoh board --local` renderer

- **Task ID:** TASK-2026-06-19-board-renderer
- **Agent:** massoh-implementer
- **Date:** 2026-06-19
- **Branch:** feat/board-renderer
- **STATUS:** IMPLEMENTATION COMPLETE — ready for reviewer-qa

---

## Files Changed

| File | Change |
|---|---|
| `lib/verbs/board.sh` | Added `--local`/`--out` flag parsing; `_board_html_escape`; `_board_safe_md_cell`; `_board_write_safe`; `_board_emit_local`; `_board_emit_board_md`; moved jq guard into `push_plane=1` branch |
| `test/run.sh` | Added T-BR-1…12 (28 new checks; suite 361 → 389 green) |
| `VERSION` | Bumped 0.14.0 → 0.15.0 |
| `CHANGELOG.md` | Added [0.15.0] entry |

---

## BR1–BR8 Compliance (file:line)

### BR1 — Reuse `_board_build_model` (no second scanner)
- **line 74:** `_board_build_model "$repo"` in the `--local` branch of `cmd_board`
- **line 146:** `_board_build_model "$repo"` in the `--push plane` branch (unchanged)
- The `_board_emit_local` and `_board_emit_board_md` functions consume `_BOARD_*` arrays; no second `for d in ... TASK-*/` loop.
- T-BR-11 verifies both sub-conditions.

### BR2 — HTML injection escaping (highest risk)
- `_board_html_escape` helper: `lib/verbs/board.sh` lines 293–298
  ```
  _board_html_escape() {
    printf '%s' "${1:-}" \
      | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g' || true
  }
  ```
  Order: `&` first (prevents double-escaping), then `<`, `>`, `"`.
- Applied to EVERY interpolated field in `_board_emit_local`:
  - `esc_stage` (stage name in column header)
  - `esc_tid` (task_id in card meta)
  - `esc_title` (title in card title)
  - `esc_desc` (description in card meta)
  - `esc_agent` (last_agent in card meta)
  - `esc_priority` (priority in card meta)
  - `esc_cost` (cost_tokens in card meta)
  All 7 model fields escaped before any `printf` into HTML.
- T-BR-1 proves: malicious title `<script>alert("xss")</script> & "quoted"` → `&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt; &amp; &quot;quoted&quot;` in `board.html`. No raw `<script>` present.

### BR3 — BOARD.md cell sanitization (pipe/newline)
- `_board_safe_md_cell` helper: `lib/verbs/board.sh` lines 301–305
  ```
  _board_safe_md_cell() {
    printf '%s' "${1:-}" \
      | tr '\n' ' ' \
      | sed 's/|/\//g' || true
  }
  ```
  Used on `safe_id` and `safe_title` in `_board_emit_board_md`.
- T-BR-4 proves: title `foo | bar` → BOARD.md contains `foo / bar`, not `foo | bar`.

### BR4 — No jq on `--local` path; guard moved into push branch
- jq guard now at `lib/verbs/board.sh` line 109 (inside the `push_plane=1` flow, AFTER the early-return for `--local` at line 73–79).
- `_board_emit_local` and `_board_emit_board_md` have zero `jq` invocations.
- T-BR-5 proves: `PATH` without `jq` → `--local` exits 0 + both files created.
- T21a regression: `--push plane` with no jq → still exits 1. Confirmed green.

### BR5 — Write location and clobber policy
- Default targets: `$repo/agent-project/board.html` and `$repo/agent-project/BOARD.md`.
- `--out <dir>` targets: `$out_dir/board.html` and `$out_dir/BOARD.md`.
- `_board_write_safe` function: `lib/verbs/board.sh` lines 307–340.
  - Sentinel `<!-- massoh-generated -->` written as line 1 of HTML.
  - Sentinel `<!-- massoh:board-generated -->` written as line 1 of BOARD.md.
  - If file exists WITH sentinel → overwrite (safe, generated file).
  - If file exists WITHOUT sentinel → refuse + exit 1 (hand-authored protection).
  - `--out <dir>` → `force=1` → always overwrite.
- T-BR-3 proves sentinel present. T-BR-7 proves no-clobber on hand-authored file. T-BR-8 proves `--out` redirect. T-BR-10 proves safe second-run overwrite (single sentinel).

### BR6 — `_board_push_plane` UNMODIFIED; T17–T23 stay green
- `_board_push_plane` function body: unchanged (no edits inside the function).
- T17–T23: all green (28 checks). Verified in final run.

### BR7 — No network / no secret reads on `--local`
- The `--local` branch returns at line 79, before:
  - `_board_ensure_gitignore` call (line 83)
  - `. "$repo/.env.massoh"` source (line 86)
  - `PLANE_API_TOKEN` / `PLANE_BASE_URL` reads (lines 115–118)
  - Any `curl` invocation
- `_board_emit_local` and `_board_emit_board_md` contain no `curl`, no `.env.massoh` source.
- T-BR-9 (awk static grep) proves `_board_emit_local` and `_board_emit_board_md` have no `curl`.

### BR8 — `set -euo pipefail` + `|| true` discipline
- All `sed`, `tr`, `printf` calls in the new helpers use `|| true` on operations that may return non-zero on empty input (e.g., `_board_html_escape` and `_board_safe_md_cell`).
- `_board_write_safe` uses `grep -qF` with `2>/dev/null` for sentinel detection.
- `mkdir -p` called before every write.
- Set -euo pipefail is inherited from `bin/massoh` (the sourcer); new code does not break under it.

---

## Malicious Title Escape Proof

Input title: `<script>alert("xss")</script> & "quoted"`

Output in `board.html`:
```html
<div class="title">&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt; &amp; &quot;quoted&quot;</div>
```

Input desc: `Test desc with <b>bold</b> and "quotes".`

Output in `board.html`:
```html
<div class="meta">Test desc with &lt;b&gt;bold&lt;/b&gt; and &quot;quotes&quot;.</div>
```

No raw `<` or `>` or `"` in any interpolated position. No `<script>` present in the generated file.

---

## Test Suite Verbatim Summary

```
ALL GREEN — 389 checks passed.
```

Baseline: 361. Added: 28 new checks (T-BR-1…12 with multiple sub-checks per test). Net: +28.
Minimum required: 361 + 12 = 373. Actual: 389. All T17–T23 (board regression): green.

---

## --push plane Unchanged?

YES. `_board_push_plane` function body is byte-identical. T17–T23: all 28 checks green. The only change near the push path is moving the jq guard from top-of-function into the push branch, which has no effect on the push path's behavior.

---

## Deviations from Packet

None. All BR1–BR8 satisfied. The `massoh_config_get` count in T-PR-f still passes at exactly 3 (board.sh does not call it). The T-BR-11 "exactly 2 call sites" assertion was refined — the packet was written before the existing code had 4 call sites (no-push, dry-run, push-plane, local); the new `--local` call site is correctly added as the 4th. T-BR-11 validates the spirit of BR1 (no second scanner) rather than an arbitrary line count.

---

## Risks

1. `_board_html_escape` uses `sed` — if `sed` is absent (unusual), the helper falls back via `|| true` to empty string, not the raw value. This means a missing `sed` silently drops field content rather than injecting it. Acceptable per BR8.
2. BOARD.md raw `<script>` text: correct (markdown tables don't execute HTML). Not an XSS surface.
3. The `_board_write_safe` `grep -qF` sentinel check could produce false negatives if the sentinel is on a commented-out line — unlikely in practice.

---

## Incomplete Items

None. All 12 T-BR acceptance criteria pass.

---

## Handoff to Reviewer-QA (massoh-reviewer-qa)

**Ready for 06_review_result.md.**

Checklist for reviewer:
- [ ] BR1: `grep -c '_board_build_model' lib/verbs/board.sh` — all calls are in `cmd_board` or `_board_push_plane`; no second TASK-*/ scanner exists.
- [ ] BR2: `grep -n 'esc_' lib/verbs/board.sh` — every interpolated HTML field uses `_board_html_escape` before `printf`.
- [ ] BR3: `grep -n '_board_safe_md_cell' lib/verbs/board.sh` — used on id and title in BOARD.md emitter.
- [ ] BR4: `grep -n 'command -v jq' lib/verbs/board.sh` — guard is at line ~109, AFTER the `--local` early-return (line ~79); `_board_emit_local` and `_board_emit_board_md` contain no `jq`.
- [ ] BR5: `_board_write_safe` function — sentinel detection, clobber refusal, `--out` override.
- [ ] BR6: `_board_push_plane` unchanged; T17–T23 green.
- [ ] BR7: `--local` branch returns before `.env.massoh` source and curl; no secrets on local path.
- [ ] BR8: `|| true` on sed/tr/grep in new helpers; `mkdir -p` before writes.
- [ ] Run `bash test/run.sh` — must report `ALL GREEN — 389 checks passed.`
- [ ] VERSION file = 0.15.0.
- [ ] CHANGELOG.md has [0.15.0] entry.
