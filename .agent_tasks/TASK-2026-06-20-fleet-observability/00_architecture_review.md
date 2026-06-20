# 00 — Architecture review: Massoh Fleet (observability + self-learning platform)

- **Task:** TASK-2026-06-20-fleet-observability
- **Reviewer:** massoh-system-architect
- **Date:** 2026-06-20
- **Mode:** ARCHITECTURE_SAFETY (consult under the 8h owner-away autonomy grant)
- **Spec under review:** `agent-project/briefs/fleet-observability-spec.md`
- **Vision steered by:** `agent-project/briefs/fleet-multi-repo-self-curing.md` · `[[massoh-fleet-vision]]` · `[[massoh-north-star]]`
- **Grant of record:** AGENT_SYNC.md decision log, 2026-06-20 (8h away-autonomy)
- **Verdict in one line:** Plan endorsed. **GREEN-LIGHT slice 0 (ledger-capture) now.** Slices 0 / 1a / 1b proceed under the away-envelope. **Slice 1c (POST intake) and slice 3 (fleet learn) do NOT proceed unattended** — the listening HTTP surface plus first POST-handling is a new safety-critical risk class; build them read-only first and **PARK the write/POST path for owner sign-off.**

---

## 1. Decomposition + sequence — ENDORSED (one refinement)

The proposed order is correct: independent, each independently gate-able, lowest-risk-first, and each
slice is provable alone (the autonomous-fleet packet's own lesson, restated in the vision brief §74).

```
0  ledger-capture        ← prereq; KPIs are empty without it. Pure append-only TSV (verb exists).
1a index + repo KPI views + A↔B nav   ← READ-ONLY render of fleet+board+review+ledger
1b task drill-down       ← READ-ONLY render of one packet trail + that task's ledger cost
--- containment line: everything above is read-only / no network input handling beyond GET ---
1c start-task (POST→intake)            ← FIRST write + FIRST POST handling → PARK for owner
3  fleet learn + button  ← propose-only engine drafts → PARK adoption for owner (already in grant)
```

**Why this order holds:**
- Slice 0 is a true prerequisite — `lib/verbs/board.sh` and the KPI panels read `.agent_tasks/ledger.tsv`
  (`_board_build_model` sums per-task tokens at lines 256–264). Without capture the KPI columns render
  zeros and the whole observability value proposition is hollow. Build it first.
- 1a/1b are pure read renders over already-shipped, write-isolated verbs. They carry the *new network
  surface* risk (see §4) but **no new write risk** — they only GET and shell read-only verbs.
- 1c and 3 are the only side-effecting slices and are correctly sequenced last.

**Refinement (one, non-blocking):** Insert an explicit **sub-slice 1a-0 "serve skeleton"** — the bare
`massoh fleet serve` that binds 127.0.0.1, serves a single static "hello / fleet index stub" page, and
proves clean start/stop with no lingering process — **before** wiring any verb output. Rationale: the
listening socket is the genuinely novel risk (§4); prove the socket lifecycle and bind-scope in
isolation, with its own test, before layering content on it. This makes the network surface itself the
smallest reviewable unit. It does not change the slice count; it front-loads the risk inside 1a.

**Sequence endorsed: YES**, with 1a internally split skeleton → content.

---

## 2. Architecture ruling — ENDORSED ("server shells verbs"), with two named seams

**Endorsed as specified:**
- `massoh fleet serve [--port 8787]` → Python-stdlib `http.server` bound to **127.0.0.1 only**.
- Thin server: **no business logic in the server**; each request shells the existing bash verbs and
  serves their output. **Bash remains the source of truth.** This is the correct call — it preserves
  the FL1 write-isolation guarantees, the board.sh HTML-escape + sentinel guards, and the intake
  append-only discipline *without re-implementing any of them in Python*. The server is a transport.
- File: `scripts/massoh-dashboard` (Python). Opt-in Python dep; the bash CLI stays dep-free.
- Self-contained HTML like `board --local`, meta-refresh 30s.

**This rides existing wiring with NO safety-critical edit:** `scripts/` is already a whole-directory
copy in `manifest.yml` (lines 39–40) and is already in both the `cmd_install` and `cmd_doctor` loops in
`bin/massoh` (lines 80 and 161). Adding `scripts/massoh-dashboard` therefore needs **no manifest.yml
change and no install/doctor logic change** — exactly the RMT `scripts/req-check` precedent. The only
`bin/massoh` edit is the additive `serve` dispatch line for the `fleet` verb, which is pre-authorized
under the grant (arch-safety + reviewer + green still required).

**"Server shells verbs per request" — sound, with one minimal seam I am adding:**

The raw shape ("server runs `massoh board --local` and serves the resulting `board.html`") is sound for
the **per-repo board** because board.sh already emits a self-contained, HTML-escaped, sentinel-guarded
file. But two outputs are *not yet HTML*: `massoh fleet` (plain-text rollup) and `massoh review`/ledger
(plain-text KPIs). Re-rendering those into the index/KPI panels needs a rendering decision. I rule:

- **SEAM A — render in bash, not Python.** Add read-only `--local`/HTML-emit sub-modes to the *bash*
  verbs (mirroring `board --local`'s `_board_emit_local` + `_board_html_escape` at board.sh lines
  291–296, 347–435), so HTML escaping stays in the one audited place and the server keeps zero business
  logic. The fleet index = a new `fleet --html` (or the server composes per-repo `board --local`
  fragments + the `fleet` rollup). **Do NOT introduce a Python templating/JSON layer** — that would
  migrate escaping/logic into the server and break the "bash is source of truth" invariant. Keep it
  minimal: every byte the browser sees is produced and escaped by bash.
- **SEAM B — the server's only job is: parse method+path → map to an allowlisted verb invocation →
  stream stdout with `Content-Type: text/html; charset=utf-8`.** No path is ever turned into a
  filesystem path (see §4 path-traversal). The route table is a **fixed allowlist**, not a file server.

This keeps the server a ~150-line transport. If, during 1a, the team finds it is tempted to put parsing
or escaping logic in Python, that is the signal to stop and re-render in bash instead.

**Architecture ruling: ENDORSED.** Thin transport + bash-rendered HTML + fixed route allowlist. No
JSON/templating seam in the server.

---

## 3. Safety envelope — CONFIRMED (with the conditions in §4)

Each claim in the spec §53–58 is confirmed against shipped code:

| Envelope claim | Confirmed by | Ruling |
|---|---|---|
| 127.0.0.1-only bind | New (must be enforced + tested) | REQUIRED CONDITION N1 (§4) |
| Read-only against discovered repos (FL1) | `lib/verbs/fleet.sh` header + `_fleet_report_repo` (never a write target) | CONFIRMED — reuse, do not re-derive |
| Only writes = intake (append-only) | `lib/verbs/intake.sh` IK1 single `printf >>` | CONFIRMED — but POST path is owner-gated (§4) |
| fleet-learn = propose-only | `lib/verbs/meta.sh` write_meta=0 default, sole write `META.proposed.md` | CONFIRMED — adoption already PARKed by grant |
| Zero browser-side token spend | New (must be enforced) | CONFIRMED as design rule — REQUIRED CONDITION N6 (§4) |
| No server-side exec of agents | New | CONFIRMED as design rule — REQUIRED CONDITION N6 |
| Engine never auto-mutated | meta.sh propose-only + grant PARKs adoption | CONFIRMED |
| Promotion boundary (de-identified/generalizable only) | vision brief §47; meta-engineer prompt PROPOSE-ONLY | CONFIRMED — enforced at slice 3 (owner-gated) |

The envelope is sound. The one place it is *new* and unproven is the network surface — §4.

---

## 4. The one risk to scrutinize — the first listening network surface + first HTTP-input surface

This is the correct thing to flag. To date Massoh's only network surface was **outbound** (board.sh
curl to Plane, with 26 BG conditions). `fleet serve` is the **first inbound listening socket** and the
**first code that handles attacker-influenceable HTTP input**. Enumerated risks and containment:

### R1 — Bind scope (listening beyond localhost)
- **Risk:** binding `0.0.0.0` would expose the dashboard (which reads every opted-in repo on the
  machine) to the LAN — a real exfiltration surface.
- **Containment — REQUIRED CONDITION N1:** bind **literally `127.0.0.1`** (not `""`, not `0.0.0.0`,
  not hostname). `--port` may vary; the host is **not configurable** in this phase. Test: assert the
  server is reachable on `127.0.0.1:<port>` and **not** reachable on a non-loopback interface address.
- **Verdict: contained.** Loopback-only is a hard, testable boundary.

### R2 — Path traversal on served files (board.html, packet files)
- **Risk:** a request like `GET /../../../../etc/passwd` or `GET /repo/<repo>/../../secret` could read
  arbitrary files if the server maps URL path → filesystem path. This is the classic `http.server`
  `SimpleHTTPRequestHandler` footgun.
- **Containment — REQUIRED CONDITION N2:** the server is **NOT a static file server.** Do **not** use
  `SimpleHTTPRequestHandler` / `translate_path`. Use a custom handler with a **fixed route allowlist**
  (`/`, `/repo?id=<n>`, `/task?repo=<n>&id=<m>`). Repos and tasks are addressed by **index into an
  in-memory list built from `massoh fleet` discovery**, never by a caller-supplied path. Any byte of a
  caller-supplied path is used only to look up an integer index; it is never `os.path.join`-ed onto a
  filesystem root. Reject anything not on the allowlist with 404. Test: `GET` with `..`, encoded
  `%2e%2e`, absolute paths, and null bytes all return 404 and read nothing outside the discovered set.
- **Verdict: contained — IF AND ONLY IF the index-not-path rule holds.** This is the single highest-care
  item for slices 1a/1b and must be a named, tested condition.

### R3 — POST handling for intake (slice 1c)
- **Risk:** the first endpoint that accepts attacker-influenceable input and triggers a **write**.
  Even though `intake` is append-only and sanitizes (`lib/verbs/intake.sh` IK2), routing untrusted
  POST bodies into a shelled command is a new class: shell-injection via the idea string, repo-target
  spoofing (writing intake to a repo the user did not choose), unbounded body size, CSRF from a
  malicious local web page (a browser tab on the same machine can POST to `127.0.0.1:8787`).
- **Containment (when built):** pass the idea as a **single argv element to `massoh intake`, never via
  a shell string** (Python `subprocess` with an arg list, `shell=False`); the target repo is selected
  by **server-side index** (R2 discipline), never by a free-form path in the body; bound the body size;
  require a same-origin / token guard against drive-by CSRF (localhost has no auth, and any local
  process/page can reach the port — this is the real residual risk).
- **Verdict: NEW SAFETY-CRITICAL RISK CLASS → PARK for owner.** See ruling below.

### R4 — No auth on localhost
- **Risk:** anything running on the machine (any local process, any browser tab) can reach
  `127.0.0.1:<port>`. For **read-only GET** of the owner's own repos on the owner's own machine, this
  matches the existing trust model (`board --local` already writes a readable `board.html`; `massoh
  fleet` already prints everything to stdout). For **POST that writes**, it is a CSRF/drive-by vector.
- **Containment:** read paths inherit the existing local-trust model — acceptable. Write paths (1c) need
  the same-origin/token guard in R3 and owner eyes.
- **Verdict: read = contained under existing trust model; write = owner-gated.**

### R5 — Leaving a process running (lifecycle / lingering socket)
- **Risk:** a backgrounded server outlives the session, holds the port, or lingers in test runs (the
  spec testing section explicitly calls this out).
- **Containment — REQUIRED CONDITION N3:** foreground, blocking server with clean SIGINT/SIGTERM
  shutdown and `SO_REUSEADDR` off-by-default semantics handled; **never auto-daemonized**; tests start
  it as a child and assert it terminates with no lingering process (mirror the spec's "starts/stops
  cleanly, no lingering proc"). The cron/orchestrator must **never** auto-start `serve`.
- **Verdict: contained** with explicit lifecycle test.

### R6 — Reflected content / XSS in rendered repo data
- **Risk:** repo data (task titles, handoff text) rendered into the dashboard HTML could carry markup.
- **Containment — REQUIRED CONDITION N4:** every interpolated field is HTML-escaped by the **bash**
  renderer (reuse `_board_html_escape`, board.sh 291–296). Since the server serves bash output verbatim
  and adds no unescaped interpolation of its own, escaping stays in one audited place. Test: a fixture
  repo with `<script>` in a task title renders escaped.
- **Verdict: contained** by reusing the proven board.sh escaping.

### Per-slice ruling (the requested clear verdict)

| Slice | Surface | Ruling |
|---|---|---|
| **0 ledger-capture** | none (append-only TSV via existing verb) | **PROCEED unattended.** No network, no new risk class. GREEN-LIT. |
| **1a-0 serve skeleton** | listening socket, GET only, static stub | **PROCEED unattended** under N1+N3 (bind 127.0.0.1, clean lifecycle, tested). Smallest unit of the new surface; build + prove it in isolation. |
| **1a index + KPI + nav** | GET only, route allowlist, bash-rendered HTML | **PROCEED unattended** under N1–N4 (no static file server, index-not-path, escape, lifecycle). Read-only; inherits local-trust model. |
| **1b task drill-down** | GET only, route allowlist | **PROCEED unattended** under N1–N4. Same read-only profile as 1a. |
| **1c start-task (POST→intake)** | **inbound POST that writes** | **DO NOT PROCEED unattended — PARK for owner.** First HTTP-input-to-write path + CSRF-on-localhost is a new safety-critical risk class (R3/R4). Build the *form UI read-only* (renders, but the submit endpoint returns "owner sign-off pending" / prints the launch command without POSTing) so the slice is demonstrable; the actual `POST → massoh intake` write stays dark behind owner sign-off. |
| **3 fleet learn + button** | GET triggers propose-only draft; adoption | **DO NOT PROCEED to adoption — already PARKed by grant.** The *propose-only draft generation* (`massoh fleet learn` → `META.proposed.md` append, owner adopts later) MAY be built as a read/propose slice IF it adds no new write target beyond the existing meta.sh append and no new network-input-to-exec path; the **button that triggers it from the browser is a POST and inherits the 1c POST ruling → PARK the browser trigger.** CLI `massoh fleet learn` (no browser) is fine to build propose-only. Engine **adoption** stays owner-gated per the grant. |

**Net network-surface verdict:** GET/read paths (1a, 1b, skeleton) are **within the away-autonomy
envelope** under conditions N1–N4 + N6. The POST/write path (1c) and the browser-triggered learn button
(slice 3) are a **NEW safety-critical risk class → WAIT for owner.** This is exactly the kind of call
the grant reserves ("any NEW safety-critical risk class the architect says needs human eyes").

---

## 5. Pre-answered defaults — CONFIRMED (with two clarifications)

| # | Default (spec/grant) | Ruling |
|---|---|---|
| Verb name | `massoh fleet serve` (sub-verb of existing `fleet`) | **CONFIRM.** Reuses the registered `fleet` verb; only an additive sub-command dispatch. No new top-level verb to register. |
| Port | `8787`, `--port` overridable | **CONFIRM.** Host is **not** overridable (N1). Document that the port is informational; the bind host is hard-coded loopback. |
| File location | `scripts/massoh-dashboard` (Python) | **CONFIRM.** Rides existing `scripts/` manifest + install/doctor wiring (no safety-critical edit). |
| KPI set | open/blocked · throughput/wk · rework% · tokens/cost · last-handoff agent/mode · version | **CONFIRM.** Every metric already exists: `review.sh` (cycle/rework/throughput, lines 53–59), `ledger.sh` (tokens/cost), `fleet.sh` (blocked, last-handoff). Reuse — do not recompute in Python. |
| Refresh | meta-refresh 30s | **CONFIRM.** Matches `board --local`. Acceptable cost (re-shells read-only verbs); document that each refresh re-runs the verbs. |
| HTML reuse | self-contained, sentinel-marked like `board --local` | **CONFIRM** + extend the sentinel + clobber-guard discipline (board.sh `_board_write_safe`, lines 306–345) to any file the dashboard writes locally. |
| start-task = intake (not exec) | POST → `massoh intake` (append-only); returns launch command; no server-side exec, no token spend | **CONFIRM the design**, but the *implementation of the POST* is PARKed (§4, R3). The "intake-not-exec, zero browser spend" rule is the correct invariant and a REQUIRED CONDITION (N6) for when 1c is later approved. |

**Clarification 1 (Python dep):** follow the `scripts/req-check` precedent — Python 3 **stdlib only**
(`http.server`, `socketserver`, `subprocess`, `html`, `urllib`). **No PyYAML, no pip dependency** for
the dashboard (req-check needs PyYAML; the dashboard must not). Add a startup guard: if `python3` is
absent, `massoh fleet serve` prints an install hint and exits non-zero (mirror the board.sh `jq` guard
at board.sh 109–110). CI already installs nothing extra for Python (it ships in ubuntu-latest); add a
fleet-serve smoke test to `test/run.sh` / `test/massoh.bats`.

**Clarification 2 (bash-renders-HTML):** confirmed in §2 SEAM A — the index/KPI HTML is emitted by bash
(`fleet --html` or composed board fragments), not by Python templating. This is a correction to any
reading of the spec that implies the Python server builds HTML.

---

## 6. Owner-park list — CONFIRMED + extended

Do **NOT** do unattended (park with a clear queued decision; continue independent slices meanwhile):

1. **Slice 1c POST→intake write path** (NEW: HTTP-input-to-write + localhost CSRF). Build the form
   read-only; PARK the actual write. *(architect-added to the grant's park list)*
2. **Slice 3 browser-triggered learn button** (POST → inherits 1c ruling). CLI propose-only `fleet
   learn` is fine; the browser trigger is parked. *(architect-added)*
3. **Engine ADOPTION of any self-learning / `fleet learn` proposal** — drafts only; adoption owner-gated.
   *(grant)*
4. **Engine-extraction sub-project #2** (engine-as-separate-repo) — DEFERRED. *(grant + spec §17)*
5. **Any irreversible op / real paid-API spend** — none of slices 0/1a/1b incur either; confirm zero
   token spend stays an invariant (N6). *(grant)*
6. **Binding to any host other than 127.0.0.1, or making the host configurable** — out of scope this
   phase; would be a new exposure decision for the owner. *(architect-added)*
7. **Any change to a designated safety-critical file** (`bin/massoh` install/uninstall/block logic,
   `manifest.yml` install boundary, `templates/CLAUDE.*`, NON_NEGOTIABLES.md). The additive `fleet`
   sub-verb dispatch line in `bin/massoh` is pre-authorized; the install/uninstall/block logic is not.
   *(NON_NEGOTIABLES §6 + grant)*

---

## 7. Required conditions (carry into each slice's 03/04)

- **N1 — Loopback bind:** server binds literally `127.0.0.1`; host not configurable; tested reachable on
  loopback and unreachable off-loopback.
- **N2 — No static file server / index-not-path:** custom handler, fixed route allowlist; repos/tasks
  addressed by server-side index into the `massoh fleet` discovery list; caller path never joined onto a
  filesystem root; `..`/encoded-traversal/null-byte → 404, zero reads outside the discovered set.
- **N3 — Clean lifecycle:** foreground, never auto-daemonized, clean SIGINT/SIGTERM, no lingering
  process in tests; cron/orchestrator never auto-starts `serve`.
- **N4 — Escape in bash, once:** every interpolated field HTML-escaped by the bash renderer
  (reuse `_board_html_escape`); the server adds no unescaped interpolation.
- **N5 — Reuse, don't re-derive:** KPIs/rollups/discovery come from `fleet`/`review`/`ledger`/`board`/
  `meta` verbs; the server shells them; no business logic, no recomputation in Python.
- **N6 — Zero browser spend / no agent exec:** no request ever spends paid API tokens or execs an agent;
  read paths only read; the (later, owner-gated) intake POST passes the idea as a single argv element
  (`shell=False`), selects the repo by server-side index, bounds body size, and guards CSRF.
- **N7 — Stdlib only:** `scripts/massoh-dashboard` uses Python 3 stdlib only (no pip dep); startup guard
  if `python3` absent.
- **N8 — Append-only / no hard-delete everywhere:** ledger capture (slice 0) and any local dashboard
  file write respect append-only + sentinel clobber-guard; never delete or overwrite history
  (NON_NEGOTIABLES §Data + migration policy).

---

## 8. GREEN-LIGHT — start here

> **GREEN-LIGHT: slice 0 (ledger-capture) — PROCEED NOW.**

Slice 0 is the right first build: it is the prerequisite for every KPI, it uses the **already-shipped,
already-arch-approved** `massoh ledger add` verb (append-only TSV, 8 conditions L1–L9), it touches **no
network surface**, and it is fully reversible (append-only; an over-counted row is corrected by a
correcting row, never a delete). Scope for slice 0:

1. Backfill this session's real per-stage costs into `.agent_tasks/ledger.tsv` via `massoh ledger add
   <task-id> <stage> <tokens> <seconds>` (append-only; the verb guards the write).
2. Document the orchestrator-called capture convention (RE-ENTRY-C from the deferred auto-ledger #5):
   the orchestrator calls `massoh ledger add` at each stage boundary with its real token + clock data.
3. No code change to a safety-critical file. No new verb. No network.

Route slice 0 → implementer (or finish it directly — it is small, safe, append-only, and the verb is
already tested). Then proceed to **1a-0 serve skeleton** under conditions N1 + N3, with its own test,
before adding any rendered content. **Hold 1c and the slice-3 browser button for owner sign-off** with a
queued decision; the CLI-only `fleet learn` propose-only path and all read-only GET views may proceed.

---

## 9. Handoff

```
Agent: massoh-system-architect
Mode: ARCHITECTURE_SAFETY (consult)
Task: TASK-2026-06-20-fleet-observability
Status: Plan ENDORSED. GREEN-LIGHT slice 0. Read paths (1a/1b) proceed under N1–N8.
        PARK 1c POST-write + slice-3 browser button for owner (new safety-critical risk class).

Sequence: ENDORSED (0 → 1a[skeleton→content] → 1b → [PARK 1c] → 3 propose-only/[PARK button]).
Architecture: ENDORSED — thin Python-stdlib http.server (127.0.0.1), shells bash verbs, bash
              renders+escapes HTML, fixed route allowlist (NOT a static file server). No JSON/
              templating seam in the server. scripts/massoh-dashboard rides existing scripts/
              manifest+install+doctor wiring — no safety-critical edit; only additive fleet-serve
              dispatch line in bin/massoh (pre-authorized).
Network verdict: GET/read = WITHIN envelope (N1–N4,N6,N7). POST/write (1c) + browser learn-button
              (3) = NEW safety-critical risk class → WAIT FOR OWNER.
Defaults: all CONFIRMED (verb=fleet serve, port=8787 host-fixed-loopback, scripts/massoh-dashboard,
              KPI set reused from review/ledger/fleet, 30s refresh, sentinel HTML, intake-not-exec).
              Two clarifications: stdlib-only (no PyYAML), HTML rendered in bash not Python.
Next agent: massoh-implementer
Next action: build slice 0 (backfill ledger + document orchestrator capture convention), then
             1a-0 serve skeleton under N1+N3 with lifecycle test. Queue owner decision for 1c+button.
```
