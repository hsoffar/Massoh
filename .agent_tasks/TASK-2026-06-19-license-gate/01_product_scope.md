# 01 — Product Scope: license-to-code gate enforcement

- **Task ID:** TASK-2026-06-19-license-gate
- **Date:** 2026-06-19
- **Agent:** massoh-product-scope
- **Decision: BUILD**

---

## Why build this now

The core Massoh value proposition is governed, gated delivery — "the moat = governance +
self-measurement + autonomy coupled" (CHARTER.md §1). Every shipped version so far has relied on
agents *choosing* to honor the no-code-without-a-license rule. Nothing mechanical stops a
code commit that bypasses the gate. The license-gate feature closes that gap: it makes the
governance claim verifiable, not aspirational. That directly supports the current strategic
mode (validate that a gated agent OS reduces build-trap) and the `packet_merged` activation
metric — a gate that actually blocks unlicensed commits demonstrates that the packet flow
matters in practice.

This is the sole open NEXT item in `NOW_NEXT_LATER.md`. No frozen items are involved.

---

## Target segment and region

- **Segment:** solo owner + Claude Code (current wedge). The hook runs in the local git
  repo; CI runs in GitHub Actions. No multi-harness work here.
- **Region/locale:** no locale dimension. Bash output is English; this is a developer tool.
- **Expansion note:** the check mechanism (a repo-local script + a CI workflow) is
  harness-neutral by construction. Nothing in the design hard-codes Claude Code. When
  multi-harness lands (LATER), the gate script travels unchanged.

---

## Metric affected

`packet_merged` — the gate enforces that code only reaches merge through the full packet
`00→06` flow. A gate that fires in real use proves the packet discipline holds mechanically,
not just by convention. Secondary: `trust` (the owner can point to a CI badge as evidence
that no code merged without a license, auditable in the PR history).

---

## The 6 scoping decisions (load-bearing — resolved here)

### 1. MVP surface — pre-commit vs pre-push vs CI; which is MVP?

**Decision: pre-push hook only for the local surface, with a companion CI workflow for
server-side enforcement. Pre-commit is deferred.**

Rationale:

- Pre-push fires once per push, after all commits are assembled. It can inspect the full
  diff of "what is about to land on the remote" without firing on every `wip` commit. This
  avoids the DX annoyance of pre-commit firing mid-flow on partial work.
- CI is non-optional for server-side trust. The hook is bypassable (`--no-verify`); CI is
  not. If Massoh's mission is governed delivery, at least one machine-enforced check must
  exist that cannot be silently skipped.
- Pre-commit is deferred. Re-entry condition: owner requests it explicitly, OR feedback
  from at least one repo shows that pre-push fires too late (e.g., large rebases landing
  without any packet check during authoring).

**MVP = pre-push local hook + CI workflow (both shipped together as a single slice).**
They are thin: both call the same shared checker script so logic lives in one place.

### 2. What mechanically counts as "a license"?

**Decision: the presence of an approved `04_implementation_packet.md` file anywhere under
`.agent_tasks/`.**

Exact rule a bash hook can implement without an LLM:

```
find .agent_tasks -name "04_implementation_packet.md" | grep -q .
```

If at least one `04_implementation_packet.md` exists under `.agent_tasks/`, the push is
licensed. If none exists, the gate fails.

Why this definition:

- It is purely file-system testable. No parsing, no LLM, no network.
- It matches the policy exactly: "an approved `04_implementation_packet.md`" is the
  canonical license artifact (policies/03_AGENT_WORKFLOW.md, §"the one hard gate").
- It does not require reading packet content or checking a state field. The file's
  *existence* in the task folder is the signal — the gated workflow guarantees that
  `04_implementation_packet.md` is only created after architecture-safety approval.
- The "or approved issue with acceptance criteria" alternative is not mechanically
  detectable without a network call to GitHub. It is honored by the escape hatch (§4).

**No path-matching between changed files and packet scope.** That would require parsing
the implementation packet's scope section to extract paths — fragile and LLM-territory.
The simpler rule is: if the repo has ever received a licensed packet, a code push is
allowed. The packet's scope discipline is enforced by the reviewer (as it is today).

**Defer:** packet-to-path matching, state-field inspection, issue-link parsing.

### 3. What triggers the gate vs what is exempt?

**Decision: the gate fires only when the push contains changes to non-exempt paths. The
exemption list is explicit and conservative.**

Exempt (gate does NOT fire, regardless of packet presence):

- All files matching `*.md` (markdown artifacts; explicitly allowed in every mode per
  guardrail A1 in `09_GUARDRAILS.md`).
- All files under `.agent_tasks/` (packet artifacts — these are the governance layer
  itself; blocking them would be self-defeating and cause a bootstrap paradox).
- All files under `agent-project/` (project governance docs; markdown-only in practice).
- `AGENT_SYNC.md`, `AGENT_BACKLOG.md`, `memory/` (housekeeping / sync-only commits).
- `.massoh` marker file.
- `LICENSE`, `.gitignore`, `.gitattributes`, `.github/` workflows and config files
  (meta-repo tooling; the gate's own CI workflow must not gate itself).

Trigger (gate fires and requires a packet):

- Any file under `bin/` (the install logic).
- Any file under `claude/` (agent/skill files).
- Any file under `templates/` (scaffolded project files).
- Any file under `test/` (the bats suite).
- `manifest.yml`, `VERSION`.
- Any other file not matching an exempt pattern above.

The check is: if the diff for the push contains at least one non-exempt path, AND no
`04_implementation_packet.md` exists, the gate blocks. If all changed paths are exempt,
the gate exits 0 silently.

**Self-consistency check (Q6 answered here):** this definition ensures that all of Massoh's
normal markdown/governance/sync commits — `AGENT_SYNC.md`, `NOW_NEXT_LATER.md`,
`.agent_tasks/*/00_request.md`, `01_product_scope.md`, etc. — are fully exempt. The gate
will NOT fire on any pure-markdown or pure-governance push. Confirmed.

### 4. Escape hatch — how an owner intentionally bypasses

**Decision: two bypass mechanisms, both explicit and logged.**

**Mechanism 1 — standard git bypass:**

```
git push --no-verify
```

This is the standard git mechanism. It is well-known, not Massoh-specific, and already
familiar to any git user. The hook must print a visible warning when bypassed (it cannot
intercept `--no-verify`, but the CI check will still run).

**Mechanism 2 — environment variable for CI bypass (emergency use):**

```
MASSOH_GATE_OVERRIDE=1 git push
```

The hook checks for `MASSOH_GATE_OVERRIDE=1` in the environment and exits 0 with a printed
warning: `[massoh-gate] OVERRIDE active — gate bypassed. Record justification in commit message.`

For CI: the `MASSOH_GATE_OVERRIDE` secret can be set in the repo's GitHub Actions
environment. When set to `1`, the CI step exits 0 with the same warning printed to the
workflow log.

**What the gate does NOT do:** it does not write to any file, does not create any override
log entry automatically. Logging the justification is the owner's responsibility (commit
message). This keeps the hook side-effect-free and non-trapping.

**The gate is reversible:** removing/uninstalling the hook (see §5) returns the repo to
the pre-gate state instantly.

### 5. Install path — `massoh` verb or opt-in repo file?

**Decision: a new `massoh gate` verb that installs/uninstalls the hook in the current repo.
This touches `bin/massoh` (safety-critical) and the install contract. Architecture-safety
stage is mandatory.**

Rationale:

- A plain repo file (e.g., `.git/hooks/pre-push` checked in separately) cannot be shipped
  by the scaffold (`cmd_on`) because `.git/` is not tracked by git. Users would have to
  manually copy it. That is not the Massoh UX.
- A `massoh gate` verb follows the existing pattern (`massoh on`, `massoh off`, `massoh
  discover`) — one explicit, idempotent verb that the owner runs once in a repo.
- The verb is **additive + reversible**: `massoh gate on` installs the hook;
  `massoh gate off` removes it. Neither changes anything globally. Existing repos are
  unaffected until the owner runs `massoh gate on` in them.
- The CI workflow is shipped as a template file (`templates/massoh-gate.yml`) and copied
  into `.github/workflows/massoh-gate.yml` by `massoh gate on` (create-if-missing only,
  consistent with `scaffold()`). Owner wires it into their GitHub repo; no automatic
  GitHub API calls.

**Because `bin/massoh` is safety-critical (`NON_NEGOTIABLES.md` §Designated), this task
requires owner sign-off before the implementer touches it. That sign-off is obtained in
the architecture-safety stage (`03_architecture_safety.md`), as happened for every prior
`bin/massoh` change.**

**Defer:** auto-installing the hook via `cmd_on` (scaffold). Re-entry condition: at least
two repos have opted in and feedback shows manual `massoh gate on` is friction. Auto-wiring
it in `cmd_on` is a one-line addition once the verb is stable.

### 6. Self-consistency — confirmed

As resolved in Q3 above: all `.md` files, all `.agent_tasks/` paths, all `agent-project/`
paths, `AGENT_SYNC.md`, and `memory/` are exempt. The gate will never fire on Massoh's own
governance, sync, or housekeeping commits. The gate's own CI workflow file (`.github/`) is
also exempt. Confirmed: no bootstrap paradox.

---

## Minimal version (smallest slice that tests the hypothesis)

A single new file `scripts/massoh-gate-check` (POSIX bash, no new deps) that:
1. Reads the list of changed paths from stdin (pre-push) or from `git diff --name-only`
   (CI mode with base ref passed as argument).
2. Applies the exempt list.
3. If any non-exempt path is present AND no `.agent_tasks/*/04_implementation_packet.md`
   exists: prints a clear error message and exits 1.
4. If `MASSOH_GATE_OVERRIDE=1`: prints a warning and exits 0.
5. If all paths are exempt OR a packet exists: exits 0 silently.

Plus:
- `templates/massoh-pre-push` — the hook wrapper (sources the checker script).
- `templates/massoh-gate.yml` — the CI workflow template.
- `bin/massoh` additions: `cmd_gate()` verb with `on`/`off` sub-commands
  (installs/removes hook + CI template in the current repo).
- `manifest.yml` update: register the new templates under `project_scaffold` (no uninstall
  obligation added — the hook lives in `.git/`, not tracked).

**No new external dependencies. No LLM call. No network in the hook.**

---

## Non-goals (explicit)

- Path-to-packet scope matching (would require parsing packet content — LLM territory).
- Checking packet *state* fields or approval metadata inside the packet file.
- Parsing linked GitHub issue URLs for acceptance criteria.
- Auto-installing the hook during `massoh on` (deferred).
- Pre-commit hook (deferred).
- Any form of telemetry or automatic logging of bypass events.
- Modifying the global install (`~/.claude/`) — this is a per-repo opt-in verb only.
- Changing the existing behavior of any other `massoh` verb.

---

## Required events (named)

From `METRICS.md`:

- **`packet_merged`** — the gate enforces this path; every merged code PR after the gate
  is installed in a repo is evidence of the discipline holding. No new instrumentation
  needed beyond what already exists (`.agent_tasks/` packet history + git log).
- No new named events required for MVP. The gate's value is observable in CI pass/fail
  history and in the absence of unpacketed merges.

---

## Safety / guardrail impact

- **Guardrail A1 (no code without a license):** this feature *mechanically enforces* A1.
  No regression possible.
- **Guardrail A2 (branch + PR per feature):** unaffected.
- **Guardrail A3 (keep older data):** the hook installs into `.git/hooks/` (not tracked)
  and a template into `.github/workflows/`. No history is deleted. `massoh gate off`
  removes the hook file; the CI workflow file remains (owner deletes if desired — Massoh
  never deletes user files per NON_NEGOTIABLES.md).
- **Safety-critical files:** `bin/massoh` will be modified. This requires owner sign-off
  in the architecture-safety stage, as designated in NON_NEGOTIABLES.md. The implementer
  MUST NOT touch `bin/massoh` without an approved `03_architecture_safety.md`.
- **Additive + reversible:** `massoh gate on` installs; `massoh gate off` removes. No
  global state changed. Existing installs unaffected until `massoh gate on` is run.
- **Idempotent:** running `massoh gate on` twice is safe (hook file is overwritten to
  same content; CI template is create-if-missing).
- **POSIX bash, set -euo pipefail, no non-portable deps:** mandatory for all new bash
  in `bin/massoh` and in the checker script.

---

## Expansion / localization impact

No locale dimension. The checker script and verb output are English CLI strings. When
multi-harness lands, the checker script (`scripts/massoh-gate-check`) is portable as-is —
it is a plain bash script with no Claude Code dependencies.

---

## Acceptance criteria (testable by the implementer and reviewer)

**AC1 — Gate blocks unlicensed code push (local hook):**
In a test repo with `massoh gate on` installed and no `.agent_tasks/*/04_implementation_packet.md`:
pushing a commit that changes `bin/massoh` (or any non-exempt path) exits 1 with a message
containing "no approved 04_implementation_packet.md".

**AC2 — Gate passes licensed code push (local hook):**
Same repo, after creating `.agent_tasks/TASK-test/04_implementation_packet.md`:
pushing the same commit exits 0.

**AC3 — Exempt paths never trigger the gate:**
Pushing a commit that changes only `.md` files (e.g., `AGENT_SYNC.md`, any file under
`.agent_tasks/`, `agent-project/`) exits 0 with no error, even with no packet present.

**AC4 — Override env var bypasses the gate:**
`MASSOH_GATE_OVERRIDE=1 git push` exits 0 and prints a warning containing "OVERRIDE active".

**AC5 — `--no-verify` bypass is unblocked (standard git behavior):**
`git push --no-verify` succeeds regardless of gate state (this is standard git; test
confirms hook is not invoked).

**AC6 — CI check blocks PR with non-exempt changes and no packet:**
GitHub Actions run of `massoh-gate.yml` on a branch that adds a non-exempt file and has
no `04_implementation_packet.md` exits 1. (Test: run the checker script in `--ci` mode
in the bats suite using a temp git repo.)

**AC7 — `massoh gate on` is idempotent:**
Running `massoh gate on` twice produces the same hook file with no error.

**AC8 — `massoh gate off` removes the hook:**
After `massoh gate off`, the `.git/hooks/pre-push` file no longer exists (or is not
the Massoh hook). A subsequent push that would have been blocked by AC1 now succeeds.

**AC9 — Gate does not fire on this repo's normal workflow:**
In the Massoh repo itself (post-installation): pushing a commit that changes only
`AGENT_SYNC.md`, `NOW_NEXT_LATER.md`, or any file under `.agent_tasks/` exits 0 with
no gate error.

**AC10 — No new non-portable deps introduced:**
The checker script and hook use only: `bash`, `git`, `find`, `grep`, `printf`. No
`jq`, `python`, `node`, `curl`, or external binaries.

**AC11 — Bats test suite covers all ACs:**
New bats tests cover AC1–AC9. All existing tests (currently 204) continue to pass.
Test count after this feature: ≥ 204 + 9 new tests = ≥ 213.

---

## Kill / defer criteria

**Defer this feature if:**
- Owner decides the policy-only approach is sufficient and the DX cost of wiring a hook
  in each repo is not worth the enforcement gain.
- A simpler mechanism (e.g., a CODEOWNERS file or GitHub branch protection rule requiring
  a PR template checkbox) is judged equivalent.

**Kill this feature if:**
- The gate proves to block legitimate Massoh governance commits in practice (the exempt
  list is wrong) AND the fix requires LLM-mediated path analysis (too complex for a
  mechanical check → governance is better enforced by convention + reviewer).
- Re-entry condition for kill: redesign the exemption model or accept policy-only
  enforcement.

---

## Recommended next route

**Route to: `massoh-architecture-safety`**

Rationale: `bin/massoh` is a designated safety-critical file (NON_NEGOTIABLES.md).
This change adds a new verb (`cmd_gate`) to it, adds new template files, and updates
`manifest.yml`. Architecture-safety must approve the exact change surface, the hook
install/uninstall contract, and the CI workflow template before a `04_implementation_packet.md`
is issued. Owner sign-off on `bin/massoh` changes must be recorded in `03_architecture_safety.md`
(as it was for every prior `bin/massoh` change per the decision log in AGENT_SYNC.md).

UX review is not required: no user-facing copy changes; the output strings are
developer-facing CLI messages with no design complexity.

---

## Version note

This feature will ship as **v0.9.0** (new verb, new install behavior, new templates —
constitutes a change to the install/scaffold contract per CHARTER.md §5 versioning policy).
