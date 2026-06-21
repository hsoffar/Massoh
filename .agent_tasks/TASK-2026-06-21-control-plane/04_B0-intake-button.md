# 04 — License: Control plane B0 — intake-button pilot (write, auth-gated)

- **Gate:** architect `01_B_design.md` (auth model + B1–B7 + B-PILOT-1..12) + **OWNER SIGNATURE #1**
  (2026-06-21: signed off on the B auth model + authorized building the B0 intake pilot). This is the
  ONLY B slice authorized — later tiers (b/c) each need a fresh sign-off.
- **Branch:** `feat/fleet-intake-control` (off post-A1 main — serialize after A1; both touch fleet.sh/dashboard).
- **VERSION → after A1's bump** (A1 = 0.24.0 → this 0.25.0); CHANGELOG.

## Scope (tier-a append-only write, behind auth, opt-in OFF)
Turn the read-only start-task panel into a real **"Add idea" form** that POSTs to the server →
`massoh intake "<idea>"` in the selected repo (append-only). Gated by the §1 auth model. Default OFF.
- `massoh fleet serve --control` flag (default OFF = today's read-only server). Only with `--control`
  does the server mint the capability token, print it once to the terminal, render the form, and accept the POST.
- POST `/repo/<name>/intake` (or similar): validate token (hidden field + `X-Massoh-Token`,
  constant-time) AND same-origin (`Origin`/`Referer` == `http://127.0.0.1:<port>`) — else **403 + audit**.
  Then run `cmd_intake` for that repo (idea as a single argv element, `shell=False`/exec-array — no shell
  string), reusing intake's IK1–IK11 (append-only, sanitized). Echo success; audit the action.

## Mandatory conditions B1–B7 (from `01_B_design.md`; cite file:line in `05`)
- **B1** `--control` default OFF — without it the server is byte-identical to today (GET-only, no token, POST→404).
- **B2** (highest) two-lock auth, **fail-closed**: absent/!match token → 403; absent/!match same-origin
  → 403; BOTH required; constant-time token compare; token in memory only, printed once, never logged.
- **B3** idea passed to intake as a single argv element via exec-array (`shell=False`) — no shell string,
  no interpolation; reuse cmd_intake IK sanitization (pipes/newlines/200-cap).
- **B4** repo `<name>` validated by the existing server-side set-membership map (no path use) — 404 unknown.
- **B5** append-only: the ONLY write is via `cmd_intake` (→ AGENT_BACKLOG inbox); NO safety-critical file
  touched; bin/massoh at most an additive `--control` pass-through.
- **B6** audit: every control attempt (allow AND deny) → one append-only line in
  `~/.claude/massoh/control-audit.log` (ts, who=local, action, repo-basename, result, arg-summary); token never logged.
- **B7** set -euo pipefail; loopback-only unchanged; non-control mode unchanged.

## Required tests B-PILOT-1..12 (from `01_B_design.md`; suite + ~12)
incl: default (no --control) → POST 404, no token minted (B-PILOT-1); fail-closed — missing token →403,
missing/foreign Origin →403, both-absent →403 (B-PILOT-2/3/4); valid token+origin → intake appends one
row to the right repo (B-PILOT-5); idea with shell metachars NOT executed (exec-array proof) (B-PILOT-6);
unknown repo →404; audit line written on allow + on deny; token never in logs/HTML-source beyond the
hidden field; read-only repos elsewhere unchanged (byte-snapshot). Run `bash test/run.sh` green.

## Acceptance
1. B1–B7 (file:line). 2. B-PILOT-1..12 green; suite green; paste: default-mode-unchanged proof,
the 3 fail-closed 403s, a successful gated intake (row appended), the exec-array no-shell proof, an
audit-log sample. 3. VERSION bump + CHANGELOG. 4. No safety-critical file; --control default OFF.

## PARKED (still): tiers b (agent personality, hooks — propose-only + fresh sign-off) and c (restart,
update — exec + fresh sign-off). NOT this slice.

## Routing
`massoh-implementer` (branch `feat/fleet-intake-control`, off post-A1 main) → `05` → `massoh-reviewer-qa`
(verify fail-closed auth + exec-array + append-only + audit) → owner merge.
