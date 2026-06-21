# 01 — Design: Control plane track B (auth + write/exec) — DESIGN ONLY, FOR OWNER SIGN-OFF

- **Task:** TASK-2026-06-21-control-plane (track B)
- **Author:** massoh-system-architect
- **Date:** 2026-06-21 · base: main v0.23.0
- **Mode:** ARCHITECTURE_SAFETY (design-for-approval — **NO BUILD**)
- **Reads of record:** `00_B_design_request.md` · `TASK-2026-06-20-fleet-observability/00_architecture_review.md`
  (the prior platform ruling that PARKED the POST→write path) · `scripts/massoh-dashboard` ·
  `lib/verbs/fleet.sh` (`_fleet_serve`, `_fleet_render_*`) · `lib/verbs/intake.sh` (IK1–IK11) ·
  `agent-project/NON_NEGOTIABLES.md`.

> **VERDICT LINE:** Track B is **APPROVED-TO-DESIGN**. Every build slice needs **fresh OWNER
> SIGN-OFF** — the 8h away-grant of record (AGENT_SYNC §decision-log 2026-06-20) explicitly
> **does NOT** cover B: it parked "any new safety-critical risk class the architect flags," and a
> write/exec control plane on an unauthenticated loopback surface **is** that class. The
> **intake-button pilot may proceed to implementation ONLY after the owner signs off on this design +
> the auth model below.** No B code ships before that signature.

---

## 0. Where B was parked, and what changed

The 2026-06-20 platform ruling shipped the dashboard as **loopback + GET-only + route-allowlist +
`do_POST → 404`** (see `scripts/massoh-dashboard` lines 355–357) and **PARKED 1c (POST→intake)** as a
"NEW safety-critical risk class" for two reasons (R3 + R4 of that review):

- **R3 — first HTTP-input-to-write path:** untrusted POST body routed into a shelled command
  (shell-injection, repo-target spoofing, unbounded body).
- **R4 — no auth on localhost / CSRF:** *any* local process or *any* browser tab on the machine can
  POST to `127.0.0.1:<port>`. A drive-by page (`<form action="http://127.0.0.1:8787/...">` auto-
  submitted by JS on any site the owner visits) can trigger the write with **zero** owner intent.

R3 has a known, proven containment (argv-not-shell + server-side index + body cap — the review
already specified it as N6). **R4 is the open problem this design must solve** before any write
endpoint exists. This document supplies the auth model that closes R4, then layers the risk tiers,
the pilot, audit, and a build order on top.

---

## 1. AUTH model — the crux (closes R4)

### 1.1 The threat, precisely

The server is unauthenticated loopback. Loopback is **not** a trust boundary against:
1. **CSRF / drive-by** — a malicious web page the owner visits can issue a cross-origin POST (or an
   auto-submitting form) to `127.0.0.1:8787`. The browser will send it. This is the primary threat.
2. **Other local processes / other browser tabs** — anything on the machine can reach the port.

For **read-only GET**, the existing platform ruling accepted this under the local-trust model (the
owner's own repos, on the owner's own machine, `board --local` already writes a world-readable file).
For **writes/exec**, that acceptance does **not** carry. We need a real, minimal authentication +
CSRF defense.

### 1.2 The model (minimal-but-real): per-run capability token + same-origin + confirm

Three layers, all stdlib, all enforced **server-side**:

**(A) Per-run capability token (the secret).**
- On startup, `massoh fleet serve` generates a high-entropy token via `secrets.token_urlsafe(32)`
  (Python stdlib `secrets`, CSPRNG — **not** `random`). It lives **only in the server process memory**
  for that run's lifetime. It is **never** written to disk, **never** in a tracked file, **never**
  logged (mirrors board.sh BG1–BG7 secret discipline).
- The token is **printed once to the controlling terminal** at startup (stdout the owner already
  watches — `scripts/massoh-dashboard` main() lines 488–490 already print the URL there):
  ```
  massoh-dashboard: serving at http://127.0.0.1:8787/
  massoh-dashboard: control token (this run only): kQ7…<32 url-safe chars>
  ```
  Possession of the terminal that launched `serve` == possession of the token. A drive-by page cannot
  read the launching terminal; another local process generally cannot read another process's stdout/
  memory without already having escalated privileges (out of this threat model).
- **Lifecycle:** generated at startup, valid only while that process runs, gone on shutdown. A new
  `serve` invocation mints a **new** token — no persistence, no rotation logic, no revocation list
  needed (the process *is* the session). Restarting the server invalidates every outstanding form.

**(B) Token delivery — server-injected, never browser-stored.**
- The token is **never** sent to a GET page that an attacker could trigger and scrape. Instead: when
  the owner navigates to a **write-bearing page** (a control form), the server **injects the token as
  a hidden form field** into that page's HTML at render time (the server has the token in memory; it
  is the only party that can mint a valid form). The token is **not** placed in a cookie (cookies are
  auto-attached cross-origin → defeats CSRF defense), **not** in `localStorage`, **not** in a GET
  response body that a no-token request can fetch.
- **Critically:** a write-form page is itself served **only with a valid token in its request**, OR
  it is the *one* bootstrap exception (see 1.3) — so an attacker cannot simply `GET` the form page to
  harvest a fresh token. The token an attacker would need to forge a POST is exactly the token they
  cannot obtain without the launching terminal.

**(C) Every write/exec POST requires ALL of:**
1. **Valid capability token** present in the POST body as `_massoh_token` (form field) **AND** echoed
   in an `X-Massoh-Token` header — both must match the in-memory token via **constant-time compare**
   (`hmac.compare_digest`). Missing/wrong on either → **403**, no side effect, audit-logged.
2. **Same-origin enforcement:** the request's `Origin` header (or, if absent, `Referer`) must equal
   `http://127.0.0.1:<port>` exactly. A cross-site auto-submitting form **cannot forge `Origin`** (the
   browser sets it). Absent **both** `Origin` and `Referer` on a state-changing POST → **403** (we
   fail closed; a legitimate same-origin form always carries one). This blocks the classic
   simple-`<form>` CSRF that does not send a custom header.
3. **`Content-Type: application/x-www-form-urlencoded`** only; bodies over a hard cap (e.g. 8 KiB)
   → **413**. (The custom `X-Massoh-Token` header in (1) also forces a **CORS preflight** for any
   cross-origin scripted attempt, which a no-credentials attacker page cannot satisfy — defense in
   depth on top of same-origin.)
4. **Explicit confirm step** for any tier-(b)/(c) action (see §2): a two-phase POST — the form first
   returns a **server-rendered review page** ("you are about to X; confirm") carrying a *fresh*
   single-use nonce; the action executes only on the second POST that returns that nonce + the token.
   Tier-(a) append-only writes (intake) may be single-phase (token + same-origin is sufficient for the
   lowest-risk write).

**Why this is minimal-but-real:** no user database, no password, no session store, no cookies, no
external dependency — it is one CSPRNG token in process memory + a same-origin check + a hidden field,
all Python stdlib. It defeats every R4 vector: drive-by pages (no token, wrong/absent Origin),
cross-origin script (preflight blocked + no token), and casual local snooping (token only on the
launching terminal, never on disk). It is fully reversible (delete the POST routes → back to today's
GET-only server) and flag-equivalent-dark (no write route exists until a slice is built + signed off).

### 1.3 The one bootstrap subtlety (named, so it is not missed)

The **first** write-form page the owner loads needs the token to embed. Resolution: the **fleet index
(`GET /`) and per-repo page render a "control" entry point** that, *when the server is running with
control enabled*, includes the **already-in-memory token** in the control-form markup it serves to
**that GET** — acceptable because: (i) a drive-by page can *trigger* this GET but **cannot read the
response** (Same-Origin Policy blocks cross-origin reads of the HTML body — the attacker's JS gets an
opaque response), and (ii) the token alone is useless without also satisfying same-origin on the POST.
So the SOP read-block is the second lock: the attacker can neither read the token (SOP) nor forge the
Origin (browser-set). **Both** must fail for an attack to succeed; neither can. This is the standard
"synchronizer token + same-origin" CSRF pattern, reduced to stdlib.

### 1.4 Auth model — the 2-3 sentence summary (for the report)

`massoh fleet serve` mints a per-run high-entropy capability token (`secrets`, CSPRNG) held only in
process memory and printed once to the launching terminal; the server injects it as a hidden form
field into control pages, and **every** write/exec POST must present that exact token (body field +
header, constant-time compared) **and** an `Origin`/`Referer` equal to `http://127.0.0.1:<port>`,
else 403 with an audit line. Because a drive-by page can neither read the token (Same-Origin Policy
blocks reading the response) nor forge the `Origin` header (the browser sets it), CSRF and other-tab/
drive-by writes are closed — with no cookies, no password store, and no external dependency.

---

## 2. Risk tiers + per-action gating

Three tiers by blast radius. **The capability token is necessary for ALL three but sufficient for
none of (b)/(c).** Safety-critical-file edits and exec each need a **fresh per-action owner sign-off**
*and* architecture conditions on top of the token.

| Tier | Actions | What it touches | Token covers? | Extra gate required |
|---|---|---|---|---|
| **(a) Append-only write** | submit idea→intake; open/queue task; add ticket | `AGENT_BACKLOG.md` intake section, append-only (IK1) — never a safety-critical file | **Token + same-origin = sufficient** (single-phase). Lowest blast radius; fully reversible (append-only, soft-delete only). | None beyond §1 + §3 conditions. **One owner sign-off authorizes tier (a) as a class** (proven by the pilot). |
| **(b) Safety-critical-file edit** | change agent personality (`claude/agents/massoh-*.md`); add/edit hooks (`settings.json`) | **Designated safety-critical** / auto-running engine behavior | **Token NOT sufficient.** | **PROPOSE-ONLY, never raw web-overwrite** (see §2.1) **+ a FRESH, separate owner sign-off per sub-action** (personality and hooks are two distinct sign-offs) **+ confirm step + arch conditions.** Hooks are the highest scrutiny (auto-run code). |
| **(c) Exec** | server restart; `massoh update` (deploy) | Process / install state — irreversible-ish, exec | **Token NOT sufficient.** | **FRESH owner sign-off per action + confirm step + audit + arch conditions.** `massoh update` mutates the install boundary (`bin/massoh`/`manifest.yml` surface) → NON_NEGOTIABLES §6 sign-off in addition. |

### 2.1 Per-action safety rules (the load-bearing constraints)

- **Tier (a) intake / tickets:** route through the **existing bash verb** (`massoh intake`), passing
  the idea as a **single argv element** via `subprocess` arg-list `shell=False` (R3 containment).
  Append-only is *already proven* by IK1 (`scripts/massoh-dashboard` must not re-implement it). The
  server is a transport; **bash stays the source of truth and the only writer**. Repo target is
  selected by **server-side index** into the discovered-repo map (the same N2 set-membership the
  dashboard already uses — `_build_repo_name_map`), never from a free-form body path.
- **Tier (b) agent-personality:** these are engine-behavior files. **The web action MUST be
  propose-only** — it writes a **`*.proposed.md` draft** (mirroring `meta.sh` write_meta=0 default and
  `fleet learn`'s `FLEET_LEARNINGS.proposed.md`), **never** the live `massoh-*.md`. Adoption of the
  proposal stays a **human, off-web, owner-gated** step (same boundary as the existing engine-adoption
  park). The web never overwrites a live personality file. Period.
- **Tier (b) hooks:** `settings.json` runs code automatically — **highest scrutiny.** Same rule,
  stricter: the web action may at most **emit a proposed hook diff to a `.proposed` artifact** for the
  owner to review and apply by hand. **No raw write to `settings.json` from the web, ever.** This is a
  designated-safety-critical-adjacent surface; treat any live edit as owner-hand-applied only.
- **Tier (c) restart / update:** **exec.** Requires confirm step + token + same-origin + a **fresh
  owner sign-off** + audit. `restart` is reversible (re-launch); `massoh update` touches the install
  boundary and is the **most** gated (it intersects NON_NEGOTIABLES §6 — `bin/massoh`/`manifest.yml`).
  Default posture: design restart/update as **"print the exact command for the owner to run,"** i.e.
  advisory-by-default like today's start-task panel (`_fleet_render_start_task_panel`), and only
  promote to a real exec endpoint under a specific, separate owner sign-off.

### 2.2 What the away-grant covers vs. not (explicit)

The 2026-06-20 grant pre-authorized **read-only fleet** work and parked "any new safety-critical risk
class." **Track B in its entirety is that parked class.** Therefore:
- The grant covers **none** of B's build slices.
- **Nothing in B builds without a fresh owner signature**, even tier (a). The lowest bar (the pilot)
  is "owner signs off on *this design + the auth model*"; the higher tiers each need their own
  signature **per sub-action**.

---

## 3. Intake-button pilot (flagship) — end-to-end

The smallest real write that proves the auth model. **Tier (a), single-phase, append-only, reuses
intake's IK rules verbatim.** Build this first; it validates §1 before any higher-risk endpoint.

### 3.1 Flow (request-by-request)

1. **GET the control surface.** On `GET /repo/<name>` (existing route), when the server is launched
   with control enabled (a `--control` opt-in flag, **default OFF** — see §3.4), the bash renderer's
   existing `_fleet_render_start_task_panel` (`lib/verbs/fleet.sh` 403–442) is extended to emit a
   **real form** instead of the parked copy-paste note:
   ```html
   <form method="POST" action="/repo/<name>/intake">
     <input type="hidden" name="_massoh_token" value="<INJECTED-BY-SERVER>">
     <input type="text" name="idea" maxlength="200" required>
     <button type="submit">Queue idea</button>
   </form>
   ```
   The token value is injected **by the Python server** post-render (the bash renderer emits a
   sentinel placeholder `__MASSOH_CONTROL_TOKEN__`; the server replaces that single, known token
   string with the real value before sending — keeping the secret out of bash/argv entirely, and out
   of any rendered artifact written to disk). N4 escaping still owns all *repo-data* fields.
2. **POST `/repo/<name>/intake`** carries `_massoh_token` (form) + `X-Massoh-Token` (header, set by a
   tiny same-origin JS shim the server's own form ships) + `idea` + `Origin: http://127.0.0.1:<port>`.
3. **Server validation (fail-closed, in order):**
   - method == POST, route on allowlist, else 404.
   - body ≤ 8 KiB, `Content-Type` form-urlencoded, else 413.
   - `Origin`/`Referer` == `http://127.0.0.1:<port>`, else **403** + audit.
   - `_massoh_token` **and** `X-Massoh-Token` both `hmac.compare_digest`-equal to the in-memory token,
     else **403** + audit.
   - `<name>` ∈ discovered-repo map (server-side index), else 404. Resolve to the trusted abs-path.
4. **Append-only write (reuse, do not re-derive):** `subprocess.run(["massoh","intake", idea],
   cwd=<resolved-repo-abs-path>, shell=False, timeout=…)`. **All sanitization, truncation,
   priority, idempotency, append-only-ness come from `cmd_intake` IK1–IK11** — the server adds none.
   The idea is a **single argv element** (R3 closed). No shell string is ever built from the body.
5. **Success echo:** server renders a server-built confirmation page (escaped) showing the queued
   priority + text as returned by `massoh intake`'s stdout (`say "...queued [P?] ..."`), plus a link
   back to the repo board. On non-zero exit from intake → render the intake error verbatim (escaped),
   no partial state (intake is atomic single-`printf >>`).
6. **Audit line** (always, success or 403) — see §4.

### 3.2 Why it is cleanly buildable under the auth model — YES

- The **write primitive already exists, is tested, and is append-only** (`cmd_intake`, 327 green at
  ship, IK1 = single `printf >>`). The pilot adds **no new write logic** — only a transport + the
  auth gate.
- The **repo-selection primitive already exists** (`_build_repo_name_map` server-side index, N2).
- The **renderer seam already exists** (`_fleet_render_start_task_panel`) — it flips from a parked
  note to a real form; the change is additive and reversible (control OFF → it renders today's note).
- The auth model is **stdlib-only** (`secrets`, `hmac`, header reads) — consistent with N7.
- **No safety-critical file is edited:** intake writes only `AGENT_BACKLOG.md` (not designated
  safety-critical). `bin/massoh` needs at most an additive `--control` flag pass-through on
  `fleet serve` (the `fleet` dispatch line is already pre-authorized; this is additive + reversible).
  `manifest.yml` unchanged (`scripts/` glob already covers the dashboard).

**Conclusion: the intake-button pilot is cleanly buildable under the proposed auth model, with no
safety-critical-file edit and full reversibility — pending the one owner signature.**

### 3.3 Pilot tests + conditions (carry into the pilot's 03/04)

Required tests (extend `test/run.sh` / `test/massoh.bats`):
- **B-PILOT-1 happy path:** POST with valid token + correct Origin → one new append-only row in the
  fixture repo's `AGENT_BACKLOG.md` intake section; Queue/Done/Frozen md5 unchanged (reuse the
  intake append-only proof).
- **B-PILOT-2 no token → 403, ZERO write** (BACKLOG md5 identical before/after).
- **B-PILOT-3 wrong token → 403, zero write** (constant-time path exercised).
- **B-PILOT-4 missing/foreign Origin → 403, zero write** (CSRF drive-by simulation).
- **B-PILOT-5 token present in body but absent in header (or vice-versa) → 403.**
- **B-PILOT-6 oversize body → 413, zero write.**
- **B-PILOT-7 idea with shell metacharacters (`; rm -rf`, `$()`, backticks, `|`) → queued as inert
  literal text** (proves argv-not-shell + IK2 sanitize); no command executes.
- **B-PILOT-8 unknown repo name → 404, zero write** (server-side index).
- **B-PILOT-9 control OFF (default) → POST route returns 404** (flag-dark proof; identical to today).
- **B-PILOT-10 audit line written for both a success and a 403** (append-only; see §4).
- **B-PILOT-11 token never on disk:** grep the repo + any rendered artifact for the live token value
  after a run → zero matches (BG1-style secret-leak assertion).
- **B-PILOT-12 lifecycle:** server restart mints a new token; an old form's token → 403.

Conditions (B-tier, in addition to N1–N8 from the platform review which all still hold):
- **B1 control default-OFF:** no POST route exists unless `serve --control` is passed; default
  `serve` is byte-for-byte today's GET-only server.
- **B2 token:** CSPRNG (`secrets.token_urlsafe(32)`), memory-only, terminal-printed once, never on
  disk/in args/in logs; constant-time compare; new token per run.
- **B3 same-origin fail-closed:** Origin/Referer must match exactly; absent both → 403.
- **B4 argv-not-shell:** idea passed as a single `subprocess` arg, `shell=False`; repo by server-side
  index; body ≤ 8 KiB.
- **B5 reuse:** the write is `massoh intake` (IK1–IK11); the server re-implements no sanitize/append
  logic.
- **B6 audit:** every control POST (allow + deny) → one append-only audit line (§4).
- **B7 reversible + additive:** removing the POST route restores today's behavior; `bin/massoh` change
  is an additive `--control` pass-through only; `manifest.yml` untouched.

### 3.4 The `--control` opt-in (flag-equivalent discipline, default OFF)

Per NON_NEGOTIABLES "Feature flags" (new CLI behavior must be additive + reversible; nothing changes
without an explicit verb), the write surface is gated behind **`massoh fleet serve --control`**,
**default OFF**. Plain `massoh fleet serve` stays the v0.23.0 read-only/GET-only server. This is the
runtime kill-switch: no flag → no token minted, no POST routes, identical to today.

---

## 4. Audit — every control action, append-only

- **File:** `~/.claude/massoh/control-audit.log` (per-machine, single-user; outside any tracked repo
  so it never lands in git, mirroring the fleet cache location `~/.claude/massoh/`). **Append-only**
  (single `>>`), **never rotated by delete** (per NON_NEGOTIABLES Data policy: keep older data, no
  hard-delete). One line per attempt.
- **Format (tab-separated, parseable like `ledger.tsv`):**
  ```
  <ISO-8601-UTC>\t<who=local-single-user>\t<action>\t<target-repo-basename>\t<result>\t<arg-summary>
  ```
  - `who` = `local` (single-user model; we do not have nor claim multi-user identity — **no
    over-claim**).
  - `action` = `intake` | `ticket` | `personality-propose` | `hook-propose` | `restart` | `update`.
  - `target` = **basename only** (leak guard, mirrors `fleet learn` FLN5 — never abs-path).
  - `result` = `ok` | `denied-token` | `denied-origin` | `denied-size` | `error`.
  - `arg-summary` = sanitized, capped (e.g. first 60 chars of the idea, pipe-stripped — reuse IK2
    discipline). **The token is NEVER in the audit line.**
- **Written by:** the Python server (it is the one that sees the auth result), via a single
  append. It is the **only** dashboard-written file besides the (off-by-default) fleet cache, and it
  respects the same sentinel/append discipline (N8). A denied attempt is itself the security signal —
  logging denials is the point.

---

## 5. Sliced build order (pilot first; each higher tier separately owner-signed)

Lowest blast radius first; each slice independently provable; each side-effecting tier its own
signature. **No slice starts before its owner sign-off.**

```
B0  intake-button PILOT          ← tier (a), single-phase. PROVES the auth model end-to-end.
                                    Owner signs off on THIS DESIGN + AUTH MODEL → then B0 → impl.
--- everything below is a SEPARATE, FRESH owner sign-off, gated on B0 having proven the model ---
B1  tickets / queue writes       ← tier (a), reuse B0 auth + transport for the next append-only write.
                                    One marginal sign-off (same risk class as B0).
B2  agent-personality PROPOSE    ← tier (b). Writes *.proposed.md only; adoption stays off-web/owner.
                                    OWN sign-off + confirm step + arch conditions. Never live-overwrite.
B3  hooks PROPOSE                 ← tier (b), highest scrutiny (auto-run code). Diff-to-.proposed only.
                                    OWN sign-off; no raw settings.json write from web, ever.
B4  restart                       ← tier (c) exec. Confirm + OWN sign-off + audit. Reversible.
B5  massoh update                 ← tier (c) exec + install boundary. Confirm + OWN sign-off
                                    + NON_NEGOTIABLES §6 sign-off (touches bin/massoh/manifest surface).
```

**Rationale for the order:** B0/B1 are append-only + reversible + reuse a tested writer → the cheapest
way to validate auth in production. B2/B3 introduce safety-critical surfaces but **only ever as
propose-only drafts**, so even those add no live-overwrite risk (adoption stays the existing human
gate). B4/B5 are exec and last; B5 is the single most gated because it intersects the install
boundary. The sequence mirrors the proven platform pattern (read-only → append-only → propose-only →
exec), each layer provable alone.

---

## 6. The single biggest risk

**CSRF / drive-by writes from a malicious browser tab against the unauthenticated loopback port
(R4).** It is the one new threat class the read-only platform never had to solve, and it is what
parked B. The §1 model closes it with two independent locks that **both** must fail for an attack to
succeed — (i) a per-run capability token the attacker cannot read (Same-Origin Policy blocks reading
the response that carries it), and (ii) an `Origin`/`Referer` same-origin check the attacker cannot
forge (the browser sets it). The **highest-care implementation detail** is fail-closed ordering:
absent-Origin and absent-token must both **deny**, never default-allow; that ordering must be its own
test (B-PILOT-4, B-PILOT-2). Secondary risk: the token leaking (mitigated by memory-only + never-on-
disk + B-PILOT-11). If the auth model is ever weakened (e.g. token put in a cookie, or Origin check
made optional), the whole tier collapses — so B1/B2 must **reuse B0's exact gate**, never re-derive it.

---

## 7. What needs OWNER SIGN-OFF before any B build (explicit)

1. **B0 intake-button pilot** builds to impl **only after the owner signs off on (this design + the
   auth model in §1).** This is the gating signature for tier (a) as a class. *(The away-grant does
   NOT cover it — write/exec on the loopback surface is the parked safety-critical risk class.)*
2. **B1 tickets/queue writes** — a marginal sign-off (same tier-(a) class; reuses B0's gate).
3. **B2 agent-personality propose** — its **own** fresh sign-off (safety-critical file class), even
   though propose-only.
4. **B3 hooks propose** — its **own** fresh sign-off (highest scrutiny; auto-run code).
5. **B4 restart** — its **own** fresh sign-off (exec).
6. **B5 `massoh update`** — its **own** fresh sign-off **plus** a NON_NEGOTIABLES §6 sign-off (touches
   the `bin/massoh` / `manifest.yml` install boundary).

Until signature #1, B ships nothing. The dashboard stays exactly the v0.23.0 read-only/GET-only
server, and the existing `_fleet_render_start_task_panel` keeps rendering its parked copy-paste note.

---

## 8. Handoff

```
Agent: massoh-system-architect
Mode: ARCHITECTURE_SAFETY (design-for-approval — no build)
Task: TASK-2026-06-21-control-plane (track B)
Status: B APPROVED-TO-DESIGN. Design complete. AWAITING OWNER SIGN-OFF before ANY build slice.
        The 8h away-grant does NOT cover B (write/exec on loopback = the parked new risk class).

Auth model: per-run CSPRNG capability token (memory-only, terminal-printed once) + same-origin
            (Origin/Referer fail-closed) + hidden-field token on every write POST (constant-time
            compare, body field + header). Closes CSRF/drive-by (R4) with two independent locks
            (SOP read-block + unforgeable Origin). Stdlib-only; no cookies, no password store.
Risk tiers: (a) append-only write — token+same-origin sufficient, ONE class sign-off (intake/tickets);
            (b) safety-critical-file edit (personality, hooks) — PROPOSE-ONLY *.proposed drafts,
                never live web-overwrite, FRESH per-sub-action sign-off + confirm;
            (c) exec (restart, update) — confirm + FRESH per-action sign-off + audit; update also
                needs NON_NEGOTIABLES §6 sign-off (install boundary).
Pilot: intake button — CLEANLY BUILDABLE under the auth model. Reuses cmd_intake IK1–IK11 (append-
       only, tested), server-side repo index, existing render seam; argv-not-shell; --control opt-in
       default OFF (flag-dark). 12 tests (B-PILOT-1..12) + 7 conditions (B1–B7) specified.
Audit: ~/.claude/massoh/control-audit.log, append-only, one line per attempt (incl. denials),
       who=local single-user (no multi-user over-claim), basename-only target, token NEVER logged.
Biggest risk: CSRF/drive-by on the unauthenticated loopback port — closed by §1's two locks;
              highest-care detail = fail-closed ordering (tested by B-PILOT-2/4).
Owner sign-off needed: #1 on THIS design + auth model → unlocks B0 pilot to impl; then B1
            (marginal), and B2/B3/B4/B5 EACH a separate fresh sign-off; B5 also NON_NEGOTIABLES §6.
Next agent (only AFTER signature #1): massoh-implementer → build B0 under B1–B7 + N1–N8.
Deliverable: .agent_tasks/TASK-2026-06-21-control-plane/01_B_design.md (this file).
```
