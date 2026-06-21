# 05 — Implementation handoff: Control plane B0 — intake-button pilot (v0.25.0)

- **Task:** TASK-2026-06-21-control-plane / B0
- **Branch:** `feat/fleet-intake-control`
- **Author:** massoh-implementer
- **Date:** 2026-06-21
- **License:** `04_B0-intake-button.md` + Owner SIGNATURE #1 (AGENT_SYNC decision log 2026-06-21)

---

## 1. Files changed

| File | Change |
|---|---|
| `scripts/massoh-dashboard` | Added `--control` flag, token mint, `do_POST` handler, 403/413 responses, audit, token injection |
| `lib/verbs/fleet.sh` | `_fleet_serve`: `--control` pass-through; `_fleet_render_start_task_panel`: real form (control=1) vs read-only note (control=0); `_fleet_render_repo`: accepts `control_flag` 4th arg |
| `test/run.sh` | Added B-PILOT-1..12 (38 new checks); updated T-FL-h to exclude `__MASSOH_CONTROL_TOKEN__` sentinel |
| `VERSION` | 0.24.0 → 0.25.0 |
| `CHANGELOG.md` | Added [0.25.0] entry |

No safety-critical files touched. `manifest.yml` untouched (scripts/ glob covers dashboard). `bin/massoh` untouched (the `--control` pass-through is additive in `lib/verbs/fleet.sh`).

---

## 2. B1–B7 conditions: file:line

### B1 — `--control` default OFF; non-control server byte-identical to today

- `scripts/massoh-dashboard` line 716–717: `action="store_true", default=False`
- `lib/verbs/fleet.sh` `_fleet_serve()`: `local control_flag=""` (default empty = no flag)
- `scripts/massoh-dashboard` `do_POST()`: lines ~433–435: `if not self.control_mode: self._send_404(); return`
- `_fleet_render_start_task_panel` `lib/verbs/fleet.sh` line ~676: `control_flag="${3:-0}"` — when 0, renders the read-only copy-paste note identical to the pre-B0 function body.

### B2 — Two-lock fail-closed; constant-time; token in memory only, printed once, never logged

- Token mint: `scripts/massoh-dashboard` `main()` line ~741: `capability_token = secrets.token_urlsafe(32)` — only when `args.control`.
- Token printed ONCE: line ~779: `print(f"massoh-dashboard: control token (this run only): {capability_token}")` — never again.
- Same-origin check (Lock 1): `do_POST()` — `origin_ok` logic using `Origin`/`Referer` headers. Absent both → `origin_ok = False` → 403.
- Token check (Lock 2): `body_ok = bool(token_body) and hmac.compare_digest(token_body, token_ref)` AND `header_ok = bool(token_header) and hmac.compare_digest(token_header, token_ref)`. Both must be True.
- `_write_audit_line()`: token parameter intentionally absent from all call sites. Audit log contains `body-token-present=yes/no` not the value.
- Token injection in HTML: `_render_repo()` replaces `__MASSOH_CONTROL_TOKEN__` sentinel (emitted by bash) after render — token never in any bash variable, argv, or env.

### B3 — exec-array (shell=False), idea as single argv element, IK sanitize reused

- `scripts/massoh-dashboard` `do_POST()`: `subprocess.run([massoh_bin, "intake", idea_raw], cwd=repo_path, shell=False, ...)` — `idea_raw` is ONE argv element. The shell never sees it.
- Sanitization IK1–IK11 is entirely handled by `cmd_intake` in `lib/verbs/intake.sh` (pipe-stripping, newline-strip, 200-char truncation, priority heuristic, append-only write). This server adds zero sanitization of its own.

### B4 — repo set-membership, unknown → 404

- `scripts/massoh-dashboard` `do_POST()`: `if repo_name not in self.repo_name_map: ... self._send_404(); return` — after the auth checks, the repo name is validated against the startup-time discovered map. The repo path comes from the map value, never from the request.

### B5 — append-only via cmd_intake only; no safety-critical file touched

- The only write path is `subprocess.run([massoh_bin, "intake", idea_raw], ...)` which invokes `cmd_intake`. That function's only permitted write is `printf >> "$BACKLOG"` with IK1 `# SAFETY` comment.
- `bin/massoh` is NOT modified (the `--control` pass-through lives in `lib/verbs/fleet.sh`).
- `manifest.yml` is NOT modified.
- No `templates/`, no `agent-os/`, no `NON_NEGOTIABLES.md` changes.

### B6 — audit every attempt (allow+deny); token never logged

- `_write_audit_line()` called at EVERY exit point in `do_POST()`: denied-origin, denied-token, denied-size, denied-unknown-repo, error, ok.
- Format: `<ISO-8601-UTC>\tlocal\tintake\t<repo-basename>\t<result>\t<arg-summary>` — token is absent from every field.
- Write: `open(_AUDIT_LOG, "a")` — single append, exception-safe (audit failure does not crash server).

### B7 — set -euo pipefail; loopback-only unchanged

- `_fleet_render_start_task_panel` runs inside bash context already gated by `set -euo pipefail` (set in `_run_bash_renderer` inline script).
- `BIND_HOST = "127.0.0.1"` unchanged (line 56 of dashboard). The `--control` flag does not add any network binding.
- All fallible reads in the bash renderer use `|| true` patterns (inherited from pre-B0 code; unchanged).

---

## 3. Proof: three fail-closed 403 paths

### 3a. Missing token → 403

```
curl -s -o /dev/null -w '%{http_code}' \
  -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "idea=test no token" \
  "http://127.0.0.1:$PORT/repo/bp-test-repo/intake"
→ 403  (B-PILOT-2a: OK)
```

### 3b. Wrong token → 403 (constant-time path)

```
curl -s -o /dev/null -w '%{http_code}' \
  -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H "X-Massoh-Token: wrong-token-value-not-matching" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "_massoh_token=wrong-token-value-not-matching" \
  --data-urlencode "idea=test wrong token" \
  "http://127.0.0.1:$PORT/repo/bp-test-repo/intake"
→ 403  (B-PILOT-3a: OK)
```

### 3c. Missing/foreign Origin → 403 (CSRF drive-by simulation)

```
# No Origin:
curl -s -o /dev/null -w '%{http_code}' \
  -X POST \
  -H "X-Massoh-Token: $TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "_massoh_token=$TOKEN" \
  --data-urlencode "idea=csrf attempt no origin" \
  "http://127.0.0.1:$PORT/repo/bp-test-repo/intake"
→ 403  (B-PILOT-4a: OK)

# Foreign Origin:
curl ... -H "Origin: http://evil.example.com" ...
→ 403  (B-PILOT-4c: OK)
```

---

## 4. Proof: successful gated intake (row appended)

```
# Valid token + correct Origin:
curl -s -X POST \
  -H "Origin: http://127.0.0.1:$PORT" \
  -H "X-Massoh-Token: $TOKEN" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "_massoh_token=$TOKEN" \
  --data-urlencode "idea=add a happy-path integration test feature" \
  "http://127.0.0.1:$PORT/repo/bp-test-repo/intake"
→ 200 "intake ok\nmassoh intake: queued [P1] ..."

AGENT_BACKLOG.md row count before: N
AGENT_BACKLOG.md row count after:  N+1
grep "add a happy-path integration test feature" AGENT_BACKLOG.md → PRESENT
(B-PILOT-5 happy: OK)
```

---

## 5. Proof: exec-array no-shell (metachars not executed)

```
# Idea with shell metachars:
idea="; rm -rf /tmp/harmless_bp7 \$(touch '$BP7_MARKER') \`echo hi\` | cat"
curl -X POST ... --data-urlencode "idea=$idea" ...
→ 200 (queued)

# Marker file check:
[ ! -f "$BP7_MARKER" ]   → TRUE (file NOT created)
# exec-array: subprocess.run(["massoh", "intake", idea_raw], shell=False)
# The shell never sees the idea; "$(...)" and ";" are treated as literal text.
grep "rm -rf" AGENT_BACKLOG.md → PRESENT (literal text stored)
(B-PILOT-7b/c/d: OK)
```

---

## 6. Audit log sample (allow + deny)

```
2026-06-21T10:XX:XXZ	local	intake	bp-test-repo	denied-origin	origin='' referer=''
2026-06-21T10:XX:XXZ	local	intake	bp-test-repo	denied-token	body-token-present=no header-token-present=no
2026-06-21T10:XX:XXZ	local	intake	bp-test-repo	denied-origin	origin='http://evil.example.com' referer=''
2026-06-21T10:XX:XXZ	local	intake	bp-test-repo	ok	idea='; rm -rf /tmp/harmless_bp7 $(touch ...'
2026-06-21T10:XX:XXZ	local	intake	bp-test-repo	ok	idea='add a happy-path integration test feature'
```

Token NEVER in any line. Repo = basename only. arg-summary capped at 120 chars.

---

## 7. Default-mode-unchanged proof

```
# Without --control:
python3 scripts/massoh-dashboard --port $PORT1 &
curl -X POST -d 'idea=x&_massoh_token=anything' \
  http://127.0.0.1:$PORT1/repo/bp-test-repo/intake
→ 404  (B-PILOT-1a: OK)

curl http://127.0.0.1:$PORT1/
→ 200  (B-PILOT-1b: OK — GET still works)

grep 'control token' startup_stderr
→ (no match)  (B-PILOT-1c: OK — token not minted)
```

---

## 8. Suite output

```
ALL GREEN — 635 checks passed.
```

Baseline (main before B0): 597 checks.
New B-PILOT checks: 38 (B-PILOT-1..12 with sub-checks a/b/c/d).
T-FL-h: updated to exclude `__MASSOH_CONTROL_TOKEN__` sentinel (additive clarification, same intent).
Pre-existing flakes T-FLN-6a and T-PR-a (timestamp at second boundary): neither introduced by this change; both pass on re-run.

---

## 9. Incomplete items / PARKED

- **B1 tickets/queue writes** — NOT built (separate marginal sign-off required per 04).
- **B2 agent-personality PROPOSE** — NOT built (separate own sign-off, propose-only).
- **B3 hooks PROPOSE** — NOT built (separate own sign-off, highest scrutiny).
- **B4 restart** — NOT built (exec tier, separate sign-off).
- **B5 massoh update** — NOT built (exec + install boundary, NON_NEGOTIABLES §6 sign-off).

---

## 10. Handoff to reviewer-qa

**Route:** massoh-reviewer-qa

**What to verify:**
1. B1: Run `python3 scripts/massoh-dashboard --port $P` (no --control) → POST /repo/*/intake → 404. Run with --control → token in stdout → POST with token+origin → 200.
2. B2 fail-closed: three 403 proofs above; confirm `hmac.compare_digest` call sites in `do_POST`; confirm token absent from `_write_audit_line` calls.
3. B3: grep `subprocess.run` in `scripts/massoh-dashboard` → `shell=False`; confirm `idea_raw` is a single argv element.
4. B4: grep `repo_name not in self.repo_name_map` in `do_POST`.
5. B5: grep for any `>` or `>>` or `open(..., 'w')` in `do_POST` → zero (all writes go through subprocess intake).
6. B6: `_write_audit_line` called at every exit; token never passed; confirm file uses `open(..., 'a')`.
7. B7: `BIND_HOST = "127.0.0.1"` line unchanged; `_fleet_render_start_task_panel` unchanged in control=0 path.
8. Run `bash test/run.sh` → expect 635/635 green (or 634/635 with pre-existing T-FLN-6a/T-PR-a timestamp flake).

**Security-critical review focus:**
- The two-lock ordering in `do_POST`: same-origin check runs BEFORE token check (minimizes info leak).
- Token injection: `rendered.replace(b"__MASSOH_CONTROL_TOKEN__", ...)` in Python — token never in bash argv.
- Audit line: all 6 result paths have `_write_audit_line` call before the response.
- exec-array: `subprocess.run([massoh_bin, "intake", idea_raw], shell=False)` — no shell string.
