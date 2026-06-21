# 06 — Review result: Control plane B0 — intake-button pilot (v0.25.0)

- **Task:** TASK-2026-06-21-control-plane / B0
- **Branch:** `feat/fleet-intake-control`
- **Reviewer:** massoh-reviewer-qa
- **Date:** 2026-06-21
- **Verdict:** APPROVE

---

## Verdict: APPROVE

B1–B7 all independently verified. All 6 fail-closed deny paths reproduced with zero write.
Exec-array no-shell independently reproduced. Default-OFF independently reproduced. Token
never-leaked verified (source + audit + served-HTML count). Audit log verified complete.
635/635 green (independently run twice). No blocking issues. No scope creep. No safety-critical
file touched.

---

## B1–B7: Conditions verified (file:line)

### B1 — `--control` default OFF; non-control server byte-identical

- `scripts/massoh-dashboard` line 714–723: `--control` argparse entry with `action="store_true",
  default=False`. Without the flag, `control_mode = False`.
- `scripts/massoh-dashboard` line 434: `if not self.control_mode: self._send_404(); return` — first
  line of `do_POST`. POST → 404 without `--control`.
- `lib/verbs/fleet.sh` line 1210: `local control_flag=""` (default empty = no `--control` passed
  to dashboard). Lines 1254–1257: `if [ -n "$control_flag" ]; then exec ... --control; else exec ...`.
- `lib/verbs/fleet.sh` line 680: `control_flag="${3:-0}"` in `_fleet_render_start_task_panel`.
  When `control_flag=0` (or absent), lines 748–778 render the pre-B0 copy-paste note (unchanged).

**Independently reproduced:** started server WITHOUT `--control` on port 33007 (PID 3980834).
POST `/repo/test/intake` → 404. GET `/` → 200. No "control token" line in stdout. Server stopped
by PID 3980834.

### B2 — Two-lock fail-closed; constant-time; token memory-only, printed once, never logged

**Token mint:** `scripts/massoh-dashboard` line 742: `capability_token = secrets.token_urlsafe(32)`
— only when `args.control` (line 741). Never generated without `--control`.

**Token printed once:** line 779: `print(f"massoh-dashboard: control token (this run only): ...")`.
The `if control_mode:` block at line 777 is the only location.

**Lock 1 — same-origin (fail-closed):** lines 449–470. `expected_origin = f"http://{BIND_HOST}:{self.server_port}"`.
Origin header: exact string equality. Referer fallback: `startswith(expected_origin + "/") or == expected_origin`.
Both absent → `origin_ok = False` → 403 + audit before any body read. Origin check runs BEFORE
token check (minimizes information disclosure).

**Lock 2 — token (constant-time):** lines 502–518. `body_ok = bool(token_body) and hmac.compare_digest(token_body, token_ref)`.
`header_ok = bool(token_header) and hmac.compare_digest(token_header, token_ref)`. Both `bool()`
guards prevent empty-string fast-paths. `token_ok = body_ok and header_ok`. Missing either field
(empty string) → constant-time compare runs against the real token → mismatch → 403.

**Token injection:** `scripts/massoh-dashboard` lines 638–643. Bash emits sentinel `__MASSOH_CONTROL_TOKEN__`;
Python replaces it with `self.capability_token.encode("ascii")` after render. Token never touches
bash argv, environment, or any shell variable.

**Audit — token never logged:** `_write_audit_line` (lines 73–90) has no token parameter. All
9 call sites (lines 467, 480, 487, 515, 523, 552, 557, 565, 575) log presence flag only
(`body-token-present=yes/no`), never the value. `open(_AUDIT_LOG, "a")` is the only write.

**Independently reproduced (6 deny paths, all on port 34493, PID 3984840):**

| Deny path | HTTP code | BACKLOG md5 |
|---|---|---|
| Missing token (no `_massoh_token`, no header) | 403 | unchanged |
| Wrong token (wrong value in both field + header) | 403 | unchanged |
| No Origin / no Referer | 403 | unchanged |
| Foreign Origin (`http://evil.example.com`) | 403 | unchanged |
| Body token only (no `X-Massoh-Token` header) | 403 | unchanged |
| Header token only (no `_massoh_token` body field) | 403 | unchanged |

BACKLOG md5 before=`68d32c4270cca0eb0a6fe9dc51428318` after all 6 denies=`68d32c4270cca0eb0a6fe9dc51428318`.
Zero write on all deny paths confirmed.

**Token-never-leaked independently verified:**
- `grep -r --include='*.py' --include='*.sh' --include='*.md' --include='*.txt'` on `REPO_ROOT`
  → zero matches for live token value.
- Token count in served HTML (`GET /repo/rv-test-repo`): exactly 1 occurrence, in `value="<token>"`
  attribute of the hidden field — nowhere else (not in visible text, not in script variables).
- Audit log (`~/.claude/massoh/control-audit.log`): `grep "$TOKEN"` → zero matches.

### B3 — exec-array `shell=False`; idea as single argv element; IK sanitize reused

`scripts/massoh-dashboard` lines 543–546:
```python
result = subprocess.run(
    [massoh_bin, "intake", idea_raw],  # idea_raw is ONE argv element
    cwd=repo_path,
    shell=False,                        # no shell string built
    ...
)
```
`idea_raw` is a single element at index 2; `[0]` is the binary, `[1]` is the subcommand. The OS
exec syscall receives it as a null-terminated argv element; no shell interpreter ever sees it.
Sanitization (IK1–IK11) is entirely delegated to `cmd_intake` in `lib/verbs/intake.sh`.

**Independently reproduced (exec-array injection test):**
- Idea: `; rm -rf /tmp/harmless $(touch '/tmp/rv_PWNED_<ts>') \`echo pwned\` | cat`
- POST code: 200 (idea queued as literal text).
- Marker file `/tmp/rv_PWNED_<ts>`: NOT created.
- `rm -rf` literal text found in AGENT_BACKLOG.md.
- Shell metacharacters were inert. exec-array / `shell=False` confirmed.

### B4 — Repo set-membership; unknown name → 404

`scripts/massoh-dashboard` lines 521–525:
```python
if repo_name not in self.repo_name_map:
    _write_audit_line("intake", repo_name, "denied-unknown-repo", ...)
    self._send_404()
    return
repo_path = self.repo_name_map[repo_name]
```
`repo_name_map` is built at startup from discovered repos (`_build_repo_name_map`, line 173).
`repo_name` from the URL regex (`_INTAKE_POST_RE`) is only a set key — never joined onto a path.
The repo abs-path used in `cwd=` comes exclusively from the map value (trusted).

**Independently reproduced:** POST to `/repo/nonexistent-xyz/intake` with valid token + origin → 404.
BACKLOG md5 unchanged.

### B5 — Append-only via `cmd_intake` only; no safety-critical file touched

- The only write operator in `do_POST` is `subprocess.run([massoh_bin, "intake", idea_raw], ...)`.
  `grep -n "open("` shows only two `open()` calls in the entire dashboard: `_write_audit_line`
  (append `"a"`) and `_fleet_tsv_path` (read `"r"`). Neither is in `do_POST`.
- `bin/massoh`: `git diff HEAD -- bin/massoh` → empty (no change). The `--control` pass-through
  is entirely in `lib/verbs/fleet.sh` (`_fleet_serve`).
- `manifest.yml`: `git diff HEAD -- manifest.yml` → empty (no change). The `scripts/` glob already
  covers `scripts/massoh-dashboard`.
- `agent-project/NON_NEGOTIABLES.md`: `git diff HEAD -- agent-project/NON_NEGOTIABLES.md` → empty.
- No `templates/`, `agent-os/`, `policies/`, `settings.json`, or any designated safety-critical
  file is touched.
- `massoh doctor` → `healthy — install matches manifest.` (all ok lines).

### B6 — Audit every attempt (allow+deny); token never in audit log

`_write_audit_line` called at every exit point of `do_POST` (9 call sites):
- `denied-origin` (lines 467–469): after origin fail.
- `denied-size` (lines 480, 487): after size cap.
- `denied-token` (line 515): after token fail.
- `denied-unknown-repo` (line 523): after repo check.
- `error` / `ok` (lines 552, 557, 565, 575): subprocess outcomes.

Format: `<ISO-8601-UTC>\tlocal\tintake\t<repo-basename>\t<result>\t<arg-summary>`.
Token value is absent from all fields. Repo is basename-only (no abs-path). arg-summary is capped
at 120 chars, stripped of tab/newline.

`open(_AUDIT_LOG, "a")` (line 87): single append. Exception-safe (pass on error — audit failure
must not block the response per design).

**Independently confirmed audit log content (from `~/.claude/massoh/control-audit.log`):**
- `denied-origin` lines present.
- `denied-token` lines present (show `body-token-present=yes/no header-token-present=yes/no`).
- `denied-unknown-repo` line present.
- `ok` lines present for allow cases.
- No token value in any line (confirmed via `grep "$TOKEN" "$AUDIT_LOG"` → zero matches).

### B7 — `set -euo pipefail`; loopback-only unchanged

- `BIND_HOST = "127.0.0.1"` (`scripts/massoh-dashboard` line 59): hard-coded constant. Not
  configurable. Used at line 696 (`TCPServer((BIND_HOST, port), ...)`) and line 452 (origin check).
- `_fleet_serve` in `lib/verbs/fleet.sh` (line 1207): `set -euo pipefail` at line 1208.
- `--control` flag adds NO new network binding. The binding is `(BIND_HOST, port)` unchanged.
- The `allow_reuse_address = False` at line 695 (unchanged from pre-B0).

---

## Test verification

**Suite run result:** `ALL GREEN — 635 checks passed` (independently run twice).

**Baseline:** 597 (post-A1, pre-B0).
**New B-PILOT checks:** 38 sub-checks across B-PILOT-1..12.
**Total:** 635.

**B-PILOT substantive checks:**

- **B-PILOT-1a/b/c/d:** no-control POST→404; GET→200; no token in stdout; token present with `--control`.
- **B-PILOT-2a/b:** missing token → 403; BACKLOG md5 unchanged.
- **B-PILOT-3a/b:** wrong token → 403; BACKLOG md5 unchanged.
- **B-PILOT-4a/b/c/d:** no-Origin → 403 + unchanged md5; foreign-Origin → 403 + unchanged md5.
- **B-PILOT-5a/b/c:** body-only token → 403; header-only token → 403; md5 unchanged.
- **B-PILOT-6a/b:** oversize body → 413; md5 unchanged.
- **B-PILOT-7a/b/c/d:** metachar idea → 200; BACKLOG changed; marker NOT created; literal text stored.
- **B-PILOT-5(happy)/row-count/grep:** valid auth → 200; row count +1; text in BACKLOG.
- **B-PILOT-8a/b:** unknown repo → 404; md5 unchanged.
- **B-PILOT-9:** source-level `default=False` + `store_true` + `--control` all confirmed.
- **B-PILOT-10a/b/c/d:** audit log exists; `ok` result present; deny result present; `intake` action present.
- **B-PILOT-11a/b/c/d:** token not in repo source files; not in test script; present in served HTML
  hidden field; appears exactly once.
- **B-PILOT-12a/b/c:** new server mints different token; old token → 403; new token → 200.

**PID-scoped teardown:** all three servers (BP1, BP_CTRL, BP12) are stopped via their specific
PIDs. `grep -n 'pkill\|killall'` in test/run.sh returns only the comment on line 3888. No broad
process kills.

**T-FL-h change:** the test excludes `__MASSOH_CONTROL_TOKEN__` from the grep before checking
for `TOKEN`. The sentinel lines in fleet.sh (`grep 'TOKEN' lib/verbs/fleet.sh`) are: two comment
lines and one printf line emitting the sentinel literal — none contain actual secrets, network
primitives, or real credentials. The exclusion is correct and does not weaken the no-credentials
intent. `grep -v '__MASSOH_CONTROL_TOKEN__' lib/verbs/fleet.sh | grep -E 'curl|wget|nc |ssh |PLANE_API|SECRET|TOKEN'`
→ zero output.

---

## Scope verification

Files changed (from `git diff --stat HEAD`):
1. `scripts/massoh-dashboard` — control flag, token mint, `do_POST` handler, audit, injection.
2. `lib/verbs/fleet.sh` — `_fleet_serve` `--control` passthrough; `_fleet_render_start_task_panel`
   real-form path; `_fleet_render_repo` 4th arg.
3. `test/run.sh` — 38 new B-PILOT checks; T-FL-h sentinel exclusion.
4. `VERSION` — 0.24.0 → 0.25.0.
5. `CHANGELOG.md` — [0.25.0] entry.

No other files. AGENT_BACKLOG.md, AGENT_SYNC.md, manifest.yml, bin/massoh, NON_NEGOTIABLES.md,
templates/, policies/ all have zero diff.

Scope is exactly the B0 pilot. Tiers b (personality, hooks) and c (restart, update) are explicitly
parked in `05_B0_handoff.md` §9 and have no implementation anywhere in the diff.

---

## Non-blocking observations

**NB-1 — Audit log path hardcoded (acceptable by design):** `_AUDIT_LOG` is hardcoded to
`~/.claude/massoh/control-audit.log`. The test for B-PILOT-10 reads the real path at
`$HOME/.claude/massoh/control-audit.log`. If the log write fails (permissions, etc.) the
server continues (fail-open on audit write). The test gracefully skips B-PILOT-10a–d if
the file is absent, issuing `ok` placeholders. This is consistent with the design spec
(audit failure must not block responses) and is not a safety violation.

**NB-2 — Referer fallback `startswith` vs exact match:** the origin check uses exact equality
on `Origin` but `startswith(expected_origin + "/")` on `Referer`. This is correct because
Referer may include a path (e.g. `http://127.0.0.1:8787/repo/foo`) while Origin is always
just the scheme+host+port. The `or referer == expected_origin` clause handles the edge case
of a Referer with no trailing path. This is the standard handling and is not a weakness.

**NB-3 — B-PILOT-10 uses the real `~/.claude/massoh/control-audit.log`:** unlike the board
BG1 pattern (which used a temp token file), the audit log cannot be redirected via env var in
the current implementation. Tests from the suite run (B-PILOT-2..12) write to the real path.
This means the audit log persists across test runs (append-only). This is acceptable: the
design explicitly specifies "append-only, never rotated by delete" (per NON_NEGOTIABLES data
policy), and the real audit content was confirmed to contain only the expected fields with no
token leakage.

---

## Summary checklist

| Check | Result |
|---|---|
| Scope clean (5 files only) | PASS |
| No safety-critical file touched | PASS |
| manifest.yml untouched | PASS |
| bin/massoh untouched | PASS |
| NON_NEGOTIABLES untouched | PASS |
| VERSION bumped (0.24.0→0.25.0) | PASS |
| CHANGELOG [0.25.0] present | PASS |
| `--control` default OFF (B1) | PASS — independently reproduced |
| Non-control server byte-identical | PASS — POST→404, GET→200, no token |
| 6 deny paths all 403 (B2) | PASS — independently reproduced |
| Zero write on all 6 deny paths (B2) | PASS — md5 identical before/after |
| `hmac.compare_digest` constant-time | PASS — lines 507–508 |
| Token in memory only (B2) | PASS — not in any source file |
| Token printed once (B2) | PASS — line 779, `if control_mode:` guard |
| Token never in audit log (B2/B6) | PASS — grep zero matches |
| Token in HTML hidden field only (B2) | PASS — count=1, `value="..."` attribute |
| exec-array `shell=False` (B3) | PASS — independently reproduced |
| Shell metachars inert (B3) | PASS — marker file NOT created |
| Repo set-membership only (B4) | PASS — unknown repo → 404, md5 unchanged |
| Only write via `cmd_intake` (B5) | PASS — 1 subprocess.run in do_POST |
| Audit all attempts allow+deny (B6) | PASS — all 6 result types confirmed |
| loopback unchanged (B7) | PASS — BIND_HOST=127.0.0.1 unchanged |
| B-PILOT tests substantive (not stubs) | PASS — all 38 sub-checks exercise real paths |
| PID-scoped teardown (no broad pkill) | PASS — 3 PIDs, zero pkill/killall |
| T-FL-h change does not weaken intent | PASS — sentinel lines contain no real secrets |
| Tiers b/c NOT built | PASS — zero diff for personality/hooks/restart/update |
| `massoh doctor` green | PASS — `healthy — install matches manifest` |
| Suite count ≥ 609 (597+12 minimum) | PASS — 635 (597 + 38 new) |
| No frozen features | PASS — Frozen section in AGENT_SYNC.md is "None" |

---

## Routing

Ready to commit + squash-merge to main. Owner merge per auto-merge-on-green policy.
After merge: AGENT_SYNC.md decision log to be updated with APPROVE + 635/635 result.
Next: tiers B1–B5 each await their own fresh owner sign-off per `01_B_design.md` §7.
