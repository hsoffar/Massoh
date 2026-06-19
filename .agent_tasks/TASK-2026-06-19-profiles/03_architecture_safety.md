# 03 — Architecture / Safety: TASK-2026-06-19-profiles

**Reviewer:** massoh-architecture-safety  
**Date:** 2026-06-19  
**Verdict: APPROVED (with conditions PC1–PC9)**

---

## 1. Backend / service impact

No backend or service. This is a pure-bash CLI project. Impact is confined to:
- A new helper function (e.g. `massoh_config_get`) added to a new file `lib/verbs/_config.sh` (or
  inlined into an existing shared-bootstrap section of bin/massoh before the sourcing loop).
- Three consuming verbs: `lib/verbs/meta.sh` (OUTLIER_FACTOR, REPEAT_THRESHOLD),
  `lib/verbs/recommend.sh` (currently no tunables surfaced, but could expose rework/cycle
  thresholds), `bin/massoh-cron` (IDLE_MIN idleness window). No other verb need change for MVP.
- An optional new scaffold template `templates/config.yml.template` if `massoh on` is to create a
  starter file (see §8 scaffold decision below — owner sign-off required if scaffold is added).

---

## 2. Client / app impact

No GUI client. End-user-visible change is purely opt-in: absent `agent-project/config.yml` = zero
behavioral change, byte-identical CLI output. That is the central guarantee.

---

## 3. API contract / seam impact

No network API. The relevant contract seam (per CHARTER.md §3) is:  
`manifest.yml` <-> `bin/massoh` (install + uninstall + status must stay in sync with manifest).

If `massoh on` does NOT scaffold `config.yml`, manifest.yml is unchanged. That is the
recommended MVP path (see §8 below). If a scaffold template IS added, manifest.yml must be
updated in lockstep — that part requires owner sign-off because manifest.yml is a
designated safety-critical file.

---

## 4. DB / migration impact

No database. The new file (`agent-project/config.yml`) is additive, optional, and committable.
Existing repos with no `config.yml` are unchanged. Backward compatibility is guaranteed by the
fallback-to-default rule (PC1). No migration needed.

---

## 5. LLM / prompt impact

No LLM calls in the affected verbs. No prompt changes. No safety rules involved.

---

## 6. Safety / guardrail risks

**Highest risk: parser crash under `set -euo pipefail`.**  
If the config reader emits an error or a non-integer value flows into an arithmetic context, the
verb dies silently. The `|| true` + integer-validation pattern (same as ledger.sh L2) must be
applied everywhere a config value is consumed.

**Second risk: secrets in config.yml.**  
Config.yml is designed to be committed. If an implementer (or user) adds a secret key
(e.g. `plane_api_token`), it enters git history. A guard/warning at read time is required for any
key whose name matches a secret-sounding pattern; and the template must carry a prominent comment.
The BOARD verb's credential (`PLANE_API_TOKEN`) must remain in `.env.massoh` (gitignored),
not in `config.yml` — the config reader must never be used for secrets.

**Third risk: scope creep.**  
There are 13 verbs in lib/verbs/. The task permits migrating only a small named set. The
implementer must not wire config reads into every verb "while there."

---

## 7. Expansion / localization risks

Config.yml is a per-repo file, which is correct for the expansion principle
(12_EXPANSION_READY_ARCHITECTURE.md). The key namespace should use plain English snake_case
(`cron_idle_min`, `meta_outlier_factor`, `meta_repeat_threshold`) — no locale-specific naming.
The parser being pure-bash with no locale-aware parsing (no `LC_*` sensitivity) is correct.

No region/locale hard-coding introduced; this feature is itself an expansion-readiness
improvement (making tunables parameterized rather than hard-coded).

---

## 8. Scaffold / manifest decision (owner sign-off flag)

**Recommended MVP path: do NOT scaffold `agent-project/config.yml` via `massoh on`.**

Rationale: the feature's central guarantee is "absent = no-op." Scaffolding a template with
default values would change the behavior of `massoh on` for all future repos, touches the
manifest.yml `project_scaffold` list (safety-critical), and risks confusing users who see a
config file they did not explicitly request. The config file is discoverable-on-demand; users
who want it create it.

**If the owner later wants a scaffold template**, that requires:
- a new `templates/config.yml.template` file,
- an additive entry in `manifest.yml` `project_scaffold.create_if_missing`,
- owner sign-off on manifest.yml change (NON_NEGOTIABLES §Designated safety-critical files),
- a new condition and test (T-PR-g-scaffold).

**For this task, no manifest change is required; no owner sign-off beyond the existing
batch-authorization is needed.** The batch-authorization covers `bin/massoh` edits.
`manifest.yml` is NOT touched in the no-scaffold path.

---

## 9. Parser decision: pure-bash `key: value` reader (no new dependency)

**Decision: pure-bash grep/sed reader. No yq, no python, no jq.**

The Massoh hard rule (NON_NEGOTIABLES §Localization / UX invariants): "CLI must stay
POSIX-bash, `set -euo pipefail`, no non-portable deps."

**Exact safe parse pattern for a `key: value` line in config.yml:**

```bash
# massoh_config_get <file> <key> <default>
# Returns the value for <key>: from <file>, or <default> if absent/missing/malformed.
# Safe under set -euo pipefail: never crashes on missing file or missing key.
massoh_config_get() {
  local file="$1" key="$2" default="$3"
  [ -f "$file" ] || { printf '%s' "$default"; return 0; }
  local val
  # grep for "^<key>:" (anchored), strip leading/trailing whitespace and optional quotes,
  # strip inline comments (# ...). || true: never errors on missing key or grep failure.
  val="$(grep -E "^${key}[[:space:]]*:" "$file" 2>/dev/null \
         | head -n1 \
         | sed 's/^[^:]*:[[:space:]]*//' \
         | sed "s/[[:space:]]*#.*//" \
         | sed "s/^['\"]//; s/['\"]$//" \
         | tr -d '[:space:]' \
         || true)"
  if [ -z "$val" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}
```

This handles:
- missing file (returns default)
- missing key (grep finds nothing, val="", returns default)
- inline comments (`meta_outlier_factor: 2  # multiplier`)
- single or double quoted values
- extra whitespace around the value
- malformed lines (grep anchoring means unrecognized lines are silently skipped)

What it does NOT handle (and does not need to):
- nested YAML maps, arrays, multi-line values — the config schema for this task is
  entirely flat `key: scalar`, so YAML-complex structures are out of scope and unsupported.
  The config.yml template must document this.
- Duplicate keys — `head -n1` takes the first occurrence (predictable, documented).

**The helper must live in its own file `lib/verbs/_config.sh`** (underscore prefix = not a
verb, not dispatch-registered) sourced by bin/massoh's sourcing loop. This keeps it testable
in isolation and prevents it from appearing in the `massoh --help` dispatch.

---

## 10. Conditions (PC1–PC9)

**PC1 — No-op when absent (central guarantee)**  
Every call to `massoh_config_get` must supply the current hard-coded default as the `<default>`
argument. If `agent-project/config.yml` is missing OR the key is absent OR the key parses to
empty, the verb behaves byte-identically to today. Test: T-PR-a.

**PC2 — `|| true` and integer validation on every consumed value**  
Every config value used in an arithmetic context (`OUTLIER_FACTOR`, `REPEAT_THRESHOLD`,
`IDLE_MIN`) must be validated as a non-empty integer before use, with a fallback to the
built-in default. Pattern (mirrors ledger.sh L2):
```bash
local raw; raw="$(massoh_config_get "$cfg" "meta_outlier_factor" "2")"
case "$raw" in ''|*[!0-9]*) OUTLIER_FACTOR=2 ;; *) OUTLIER_FACTOR="$raw" ;; esac
```
The validator itself must not fail under `set -euo pipefail`. Test: T-PR-c.

**PC3 — Parser never crashes on malformed config**  
A config.yml containing YAML-complex content (nested maps, `---` document markers, multiline
strings, tabs) must degrade silently to all defaults. No verb may exit non-zero due to a
malformed config. Test: T-PR-d.

**PC4 — No secrets in config.yml (committable contract)**  
The config.yml template (if created by the user manually or via a future scaffold) must carry
a top-of-file comment warning that it is committable and must not contain secrets. The helper
function itself must never accept or return keys that end in `_token`, `_key`, `_secret`,
`_password`, or `_credential` (or it must emit a loud warning and return the default). The
board verb's `PLANE_API_TOKEN` must continue to be read from `.env.massoh`/env, never from
config.yml. Test: T-PR-e (guard emits warning on secret-sounding key attempt).

**PC5 — Precedence: project > built-in (two-tier only for MVP)**  
For this release: project-level (`agent-project/config.yml`) overrides built-in defaults.
Global-level (`~/.claude/massoh/config.yml` or similar) is deferred — adding a global tier
touches the install layout and risks the manifest seam. If global is added later, it must go
through a fresh arch-safety pass.
The two-tier lookup is: `massoh_config_get "$repo/agent-project/config.yml" <key> <builtin>`.
No additional lookup chain. Test: T-PR-b (project value overrides built-in).

**PC6 — Scope: only three named tunables in MVP**  
The implementer may wire `massoh_config_get` only for:
- `meta_outlier_factor` (meta.sh, current default 2)
- `meta_repeat_threshold` (meta.sh, current default 3)
- `cron_idle_min` (bin/massoh-cron, current default 25)

Wiring config reads into any other verb or adding any other config key is out of scope for
this task. Test: grep count on `massoh_config_get` calls must equal 3 (T-PR-f).

**PC7 — `_config.sh` helper sourced before verbs; loud-fail if missing**  
`lib/verbs/_config.sh` must be sourced by bin/massoh's existing sourcing loop. Because the
loop already exits loudly (`exit 1`) on a missing lib file (line 173–174 of bin/massoh), PC7
is satisfied by the existing pattern — the implementer just needs to ensure the file is
present and named with a leading underscore so it sorts first alphabetically (guaranteeing it
is sourced before the verbs that depend on it). No change to the sourcing loop logic required.
Test: T-PR-g (helper sourced + massoh_config_get callable).

**PC8 — No change to manifest.yml in this task**  
The no-scaffold path means manifest.yml is untouched. The implementer must not add
`config.yml` to `project_scaffold.create_if_missing`. If any manifest change appears in the
diff, it must be blocked until owner sign-off is obtained on that specific change.

**PC9 — bin/massoh-cron change is minimal and additive**  
`bin/massoh-cron` is not inside lib/verbs/ and is not covered by the sourcing loop.
`massoh_config_get` is defined in `_config.sh` which is sourced by `bin/massoh`. When cron
calls itself via `_massoh_bin`, the helper is unavailable unless cron sources it directly.
Therefore: cron must source `_config.sh` directly if it reads config. The safe pattern is:
```bash
[ -f "${MASSOH_HOME:-}/lib/verbs/_config.sh" ] \
  && . "${MASSOH_HOME:-}/lib/verbs/_config.sh" || true
```
followed by the integer-validation pattern from PC2 with a hard-coded fallback. This is the
only change to bin/massoh-cron; no other cron logic is touched. Test: T-PR-b exercises cron's
idle-min override path.

---

## 11. Required tests (T-PR-a through T-PR-g)

All tests run in throwaway temp repos (matching the existing `test/run.sh` pattern). No real
`~/.claude` touched. Target total: **327 (current baseline) + 7 = 334 checks**.

**T-PR-a — No-op when absent (byte-identical output)**  
In a Massoh project with NO `agent-project/config.yml`, run `massoh meta` and `massoh cron
once --dry-run`. Capture output. Compare against a run where `config.yml` is present but
completely empty. Both outputs must be byte-identical, and both must match the baseline
(hard-coded defaults visible in output: `OUTLIER_FACTOR=2x`, `threshold=3`, `idle=25`).
Assert: `diff output_no_config output_empty_config` exits 0.

**T-PR-b — Project value overrides built-in default**  
Create `agent-project/config.yml` with:
```
meta_outlier_factor: 5
meta_repeat_threshold: 7
cron_idle_min: 10
```
Run `massoh meta` — assert output contains `5x` (not `2x`) and `threshold=7` (not `3`).
Run `massoh cron once --dry-run` (with `NO_IDLE=1`) — assert idle check uses 10m. Assert that
removing config.yml reverts to 2x / 3 / 25m (PC1 regression).

**T-PR-c — Malformed integer degrades to default**  
Create `agent-project/config.yml` with `meta_outlier_factor: not_a_number`.
Run `massoh meta` — assert exit 0 AND output contains `2x` (fallback to built-in default).
Assert no crash, no error output to stderr beyond normal.

**T-PR-d — Malformed YAML structure degrades to all defaults**  
Create `agent-project/config.yml` with:
```yaml
---
nested:
  key: value
cron_idle_min: !!python/object:os.system
```
Run `massoh meta` and `massoh cron once --dry-run`. Assert exit 0 and all outputs show
built-in defaults. Assert no stderr output from the config reader itself.

**T-PR-e — Secret-sounding key guard**  
Call `massoh_config_get <file> "plane_api_token" "default"` (a key matching a secret pattern).
Assert the function emits a warning to stderr and returns `"default"`, never the file's value.
(Implementation note: the guard is a simple `case` pattern match on the key name.)

**T-PR-f — Scope check: exactly 3 config reads**  
```bash
grep -r 'massoh_config_get' lib/verbs/ bin/massoh-cron | grep -v '_config.sh' | wc -l
```
Assert the count equals 3. This prevents silent scope creep into other verbs.

**T-PR-g — Helper is callable after sourcing bin/massoh**  
In a subshell that sources bin/massoh's verb-loading loop, assert `declare -f massoh_config_get`
exits 0 (function is defined). Alternatively: run `CLAUDE_CONFIG_DIR=<tmp> massoh meta` in a
project without config.yml and assert exit 0 (which transitively proves the helper was sourced
and did not crash).

---

## 12. Rollback plan

- The config reader is additive and the central guarantee (PC1) ensures no behavior change
  when config.yml is absent.
- To roll back: remove `lib/verbs/_config.sh`, revert the 3 lines in meta.sh + massoh-cron
  that call `massoh_config_get`, restore the hard-coded local variable assignments. This is a
  3-file diff, no data migration, no manifest change.
- No `agent-project/config.yml` files are created by the install path, so no user files need
  removal.

---

## 13. Impact summary table

| Area | File(s) changed | Additive? | Safety-critical? | Sign-off needed? |
|---|---|---|---|---|
| Config helper | lib/verbs/_config.sh (NEW) | yes | no | batch-auth covers |
| meta.sh | 3 lines: local var init replaced with massoh_config_get | yes | no | batch-auth covers |
| bin/massoh-cron | 1 source line + 1 integer-validation line | yes | no | batch-auth covers |
| bin/massoh | no change required | — | yes | n/a |
| manifest.yml | NO CHANGE (no-scaffold path) | — | yes | n/a (no change) |
| templates/ | NO CHANGE | — | yes | n/a |
| tests | test/run.sh +7 T-PR-* checks | yes | no | n/a |

---

## 14. Verdict

**APPROVED — batch-authorized for `bin/massoh` (owner 2026-06-19); no separate sign-off
required for this task, PROVIDED the no-scaffold path is followed (manifest.yml untouched).**

**Conditions count: 9 (PC1–PC9). All must be verified by massoh-reviewer-qa before merge.**

**If the implementer adds a scaffold template or any manifest.yml entry, that specific
change must STOP and obtain fresh owner sign-off on manifest.yml before merging. The
batch-authorization does NOT cover manifest changes.**

---

## Summary for orchestrator / implementer

| Field | Value |
|---|---|
| Verdict | APPROVED |
| Condition count | 9 (PC1–PC9) |
| Parser decision | Pure-bash grep/sed helper in lib/verbs/_config.sh — no yq, no jq, no new dep |
| Scaffold/manifest change | NOT required; NOT approved for this task; would need owner sign-off |
| Test target | 334 (327 baseline + 7 T-PR-* checks) |
| Highest risk | Parser crash under set -euo pipefail when config value flows into arithmetic (PC2) |
| New files | lib/verbs/_config.sh |
| Changed files | lib/verbs/meta.sh (3 lines), bin/massoh-cron (2 lines), test/run.sh (+7) |
| Safety-critical files touched | None |
| VERSION bump | v0.14.0 (following fleet-rollup v0.13.0) |
