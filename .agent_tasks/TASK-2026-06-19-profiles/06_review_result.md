# 06 — Review Result: TASK-2026-06-19-profiles (profiles + config.yml, v0.14.0)

**Reviewer:** massoh-reviewer-qa
**Date:** 2026-06-19
**Verdict: APPROVE**

---

## 1. Verdict

**APPROVE** — all PC1–PC9 independently verified; 361/361 green (self-witnessed, run twice);
no-config byte-identical proven; scope clean; safety-critical files untouched; no blocking findings.

---

## 2. Blocking Issues

None.

---

## 3. Non-Blocking Issues

**NB-1 — PC8 handoff justification is factually inaccurate (code is safe; documentation wrong).**

The handoff (`05`, §PC8) claims: "`_config.sh` — underscore prefix ensures it sorts alphabetically
before all other `*.sh` files in `lib/verbs/`." This is incorrect. In the en_US.UTF-8 locale
(the system locale on this machine), `_` sorts AFTER `a`–`b` (ISO 14651 collation order), so
`board.sh` is sourced before `_config.sh` in the glob loop at `bin/massoh:172`.

**Why this is non-blocking:** `board.sh` does not call `massoh_config_get` (independently
verified: `grep -n 'massoh_config_get' lib/verbs/board.sh` returns nothing). All three
consumer call sites (`meta.sh`, and the two lines in `meta.sh` at lines 31/34) sort after
`_config.sh` in glob order. The load-order guarantee holds by scope: no verb that sorts before
`_config.sh` depends on it. The code path is safe.

**Risk note (for future verbs):** if a new verb starting with `a` or `b` were to call
`massoh_config_get`, it would get a "command not found" crash. The correct long-term fix is to
verify the sourcing loop is locale-independent (e.g. `LC_COLLATE=C` before the glob), or to
explicitly source `_config.sh` first before the loop. This should be addressed in the next
arch-safety pass that touches the verb-loading loop. Non-blocking for this merge.

**NB-2 — 2-tier vs 3-tier precedence deviation documented, not built — non-blocking.**

See §7 below. The 04 packet described project > global > built-in (3-tier). The implementation
delivers project > built-in (2-tier only). The arch-safety doc (03, §PC5) explicitly approved
the 2-tier MVP and deferred the global tier. This is consistent with the approved scope.
The CHANGELOG and `_config.sh` header both document the deferral. Non-blocking.

---

## 4. Missing Tests

None. All 7 T-PR-* test cases are present and substantive (independently read and verified below).

---

## 5. Safety/Guardrail Concerns

None. Safety-critical files (`bin/massoh`, `manifest.yml`, `templates/`, `NON_NEGOTIABLES.md`,
global-block markers) are all untouched. Verified:
- `git diff HEAD -- bin/massoh` → empty (exit 0).
- `git diff HEAD -- manifest.yml` → empty (exit 0).
- `git diff HEAD -- templates/` → empty (exit 0).
- `git diff HEAD -- AGENT_SYNC.md AGENT_BACKLOG.md` → empty (exit 0).

Secret guard (PC4): keys matching `*_token|*_key|*_secret|*_password|*_credential` emit a
warning to stderr and return the built-in default. `_config.sh:30-37` confirms the `case`
pattern. The `PLANE_API_TOKEN` board credential path is unaffected — board.sh reads it from
env/`.env.massoh`, not from config.yml.

No eval, no dynamic execution, no outbound network in `_config.sh`.

---

## 6. Hidden Scope Concerns

None. Changed files:
- `lib/verbs/_config.sh` (NEW) — helper only, not a verb, not dispatch-registered.
- `lib/verbs/meta.sh` — exactly 2 call sites (lines 31, 34).
- `bin/massoh-cron` — exactly 1 source line + 1 read/validate line (net 2 functional lines; replaces the previous `IDLE_MIN=25` single-line assignment).
- `test/run.sh` — 17 assertions across 7 T-PR test cases.
- `VERSION` → 0.14.0.
- `CHANGELOG.md` — [0.14.0] entry.

Working tree status: the `.agent_tasks/TASK-2026-06-19-agentsmd/` folder and `deck/` directory
are untracked but belong to a different task or pre-existing artifact — not part of this change.

Scope check T-PR-f (`grep -r 'massoh_config_get' lib/verbs/ bin/massoh-cron | grep -v '_config.sh' | wc -l`) = 3. Independently verified.

---

## 7. 2-Tier vs 3-Tier Precedence Call

**Non-blocking — the 2-tier MVP is acceptable and properly documented.**

The `04_implementation_packet.md` (§Scope) described a 3-tier precedence chain:
project > global (`~/.claude/massoh/config.yml`) > built-in. The implementation delivers
project > built-in (2-tier). The arch-safety doc `03_architecture_safety.md` §PC5 explicitly
approved this deviation:
> "For this release: project-level (`agent-project/config.yml`) overrides built-in defaults.
> Global-level is deferred — adding a global tier touches the install layout and risks the
> manifest seam."

The CHANGELOG [0.14.0] documents: "Precedence: project (`agent-project/config.yml`) > built-in
default. Global tier deferred." The `_config.sh` header also states: "Global-level config tier
is deferred (requires fresh arch-safety pass)."

**Call: NON-BLOCKING.** The 04 packet's 3-tier description was aspirational; the 03 arch-safety
document — which is the binding spec — approved 2-tier for MVP. The deferral is documented in
both the product file and CHANGELOG. No owner decision required; no scope block.

---

## 8. Expansion/Localization Concerns

None. Config key namespace uses plain English snake_case (`cron_idle_min`,
`meta_outlier_factor`, `meta_repeat_threshold`). Parser is locale-neutral (pure grep/sed/tr;
no `LC_*`-sensitive operations). Per-repo file placement is correct for the expansion principle.
No region/locale hard-coding introduced.

---

## 9. PC1–PC9 Independent Verification (file:line)

**PC1 — Absent/empty config → byte-identical:**
- `lib/verbs/_config.sh:40` — `[ -f "$cfg" ] || { printf '%s' "$default"; return 0; }` (missing file → default).
- `lib/verbs/meta.sh:31` — default `"2"` passed; `lib/verbs/meta.sh:34` — default `"3"` passed.
- `bin/massoh-cron:21` — default `"25"` passed.
- T-PR-a: md5sum comparison of no-config vs empty-config outputs = byte-identical. VERIFIED GREEN.

**PC2 — Integer validation, never crash under set -euo pipefail:**
- `lib/verbs/meta.sh:32` — `case "$_raw_of" in ''|*[!0-9]*) OUTLIER_FACTOR=2 ;; *) OUTLIER_FACTOR="$_raw_of" ;; esac`.
- `lib/verbs/meta.sh:35` — `case "$_raw_rt" in ''|*[!0-9]*) REPEAT_THRESHOLD=3 ;; *) REPEAT_THRESHOLD="$_raw_rt" ;; esac`.
- `bin/massoh-cron:21` — `case "$_raw_idle" in ''|*[!0-9]*) IDLE_MIN=25 ;; *) IDLE_MIN="$_raw_idle" ;; esac`.
- Pattern mirrors `ledger.sh` L2 `case` guard. POSIX `case` is safe under `set -e`. VERIFIED.
- T-PR-c: `meta_outlier_factor: not_a_number` → exit 0, output shows `2x`. GREEN.

**PC3 — Pure-bash parser, no yq/jq/python; malformed YAML → defaults, exit 0:**
- `lib/verbs/_config.sh:45-51` — grep/head/sed/tr pipeline with `|| true`.
- `grep -r 'yq\|python\|jq' lib/verbs/_config.sh` → empty (exit 1 = no match). VERIFIED.
- T-PR-d: complex YAML (nested, `!!python/object` tag) → exit 0, defaults shown. GREEN.

**PC4 — Secret-key guard:**
- `lib/verbs/_config.sh:30-37` — `case "$key" in *_token|*_key|*_secret|*_password|*_credential)` → warns to stderr, returns default, `return 0`.
- Header warning at `_config.sh:7-8`.
- T-PR-e: `plane_api_token` → warning contains "WARNING" in stderr; stdout returns `"mydefault"`. GREEN.

**PC5 — `|| true` / default-fallback throughout; malformed YAML → all defaults, exit 0:**
- `lib/verbs/_config.sh:51` — the grep/sed pipeline ends with `|| true`.
- `lib/verbs/meta.sh:31` — `|| true` after config_get call-site 1.
- `lib/verbs/meta.sh:34` — `|| true` after config_get call-site 2.
- `bin/massoh-cron:19` — source line itself has `|| true`.
- `bin/massoh-cron:21` — config_get call has `2>/dev/null || true`.
- VERIFIED by code reading and T-PR-c/d green tests.

**PC6 — EXACTLY 3 `massoh_config_get` call sites:**
- Call site 1: `lib/verbs/meta.sh:31` (`meta_outlier_factor`).
- Call site 2: `lib/verbs/meta.sh:34` (`meta_repeat_threshold`).
- Call site 3: `bin/massoh-cron:21` (`cron_idle_min`).
- `grep -r 'massoh_config_get' lib/verbs/ bin/massoh-cron | grep -v '_config.sh' | wc -l` = **3**. INDEPENDENTLY VERIFIED.
- T-PR-f passes. GREEN.

**PC7 — Precedence project > built-in (2-tier MVP; global deferred):**
- `lib/verbs/meta.sh:29` — `local _cfg="$repo/agent-project/config.yml"`.
- `bin/massoh-cron:21` — `"$REPO/agent-project/config.yml"`.
- T-PR-b: config values override defaults for all 3 tunables. Regression: removing config.yml reverts. GREEN.
- Global tier intentionally absent per arch-safety §PC5 (see §7 above — non-blocking).

**PC8 — `_config.sh` sourced before consumer verbs (load order):**
- `bin/massoh:172` — `for _verb_file in "$MASSOH_HOME/lib/verbs/"*.sh`.
- Glob order on this system: `board.sh` → `_config.sh` → `cron.sh` → ... → `meta.sh`.
- `board.sh` does NOT call `massoh_config_get` (verified by grep). All consumers (`meta.sh`) sort after `_config.sh`. Load order is safe. (See NB-1 for inaccuracy in handoff justification.)
- `bin/massoh-cron:19` — sources `_config.sh` directly, bypassing the glob loop.
- T-PR-g: `massoh meta` exits 0 (transitively proves helper loaded). GREEN.

**PC9 — VERSION 0.14.0 + CHANGELOG; bin/massoh-cron ≤2 functional lines; manifest untouched:**
- `VERSION` file: `0.14.0`. VERIFIED.
- `CHANGELOG.md`: `[0.14.0]` section present above `[0.13.0]`. VERIFIED.
- `bin/massoh-cron` diff: removed `IDLE_MIN=25` (+1 source line + 1 read/validate line = 2 functional lines added). Net change ≤2. VERIFIED via `git diff HEAD -- bin/massoh-cron`.
- `git diff HEAD -- manifest.yml` → empty. VERIFIED.

---

## 10. No-Config Byte-Identical Proof

Test T-PR-a at `test/run.sh:2116-2128`:
1. Creates a Massoh project with NO `agent-project/config.yml`.
2. Runs `massoh meta` → `out_pra_nofile`.
3. Creates EMPTY `agent-project/config.yml` (zero bytes, `printf ''`).
4. Runs `massoh meta` → `out_pra_empty`.
5. Asserts: `md5sum(out_pra_nofile) == md5sum(out_pra_empty)` — PASS.
6. Also asserts output contains `2x` and `>=3` confirming built-in defaults are active.

Independently run and confirmed GREEN.

---

## 11. Test Suite Results (self-witnessed)

```
bash test/run.sh (run 1)
ALL GREEN — 361 checks passed.

bash test/run.sh (run 2)
ALL GREEN — 361 checks passed.
```

344 pre-existing checks + 17 new T-PR-* assertions = 361. Zero regressions.

T-PR-a: substantive — md5sum comparison of real `massoh meta` outputs, content assertions.
T-PR-b: substantive — config values exercised in real verb output + cron status.
T-PR-c: substantive — bad integer, real meta invocation, exit code + output assertions.
T-PR-d: substantive — malicious/complex YAML file, real meta invocation, exit code + output assertions.
T-PR-e: substantive — real _config.sh sourced in subshell; stdout/stderr separated and asserted independently.
T-PR-f: substantive — live grep count against real source tree.
T-PR-g: substantive — real `massoh meta` invocation in project without config.yml, exit code checked.

---

## 12. Suggested Patch Instructions for NB-1 (non-blocking, for future)

In a future task that touches the verb-loading loop in `bin/massoh`, add `LC_COLLATE=C` before
the glob, or explicitly source `_config.sh` before the loop starts:

```bash
# At bin/massoh, before the verb loop:
. "$MASSOH_HOME/lib/verbs/_config.sh"  # load config helper first, explicitly
for _verb_file in "$MASSOH_HOME/lib/verbs/"*.sh; do
  [ "$_verb_file" = "$MASSOH_HOME/lib/verbs/_config.sh" ] && continue  # already sourced
  ...
done
```

This makes the load-order guarantee explicit and locale-independent. Does not need to block this merge.

---

## 13. Owner Decision Needed

None. The 2-tier precedence decision was already made by arch-safety (03, §PC5). All other
decisions are within reviewer scope.

---

## Summary Table

| Criterion | Result | Evidence |
|---|---|---|
| PC1 no-config byte-identical | PASS | T-PR-a green; md5sum match; `[ -f "$cfg" ] || return default` at _config.sh:40 |
| PC2 integer validation | PASS | case guards at meta.sh:32,35 + cron:21; T-PR-c green |
| PC3 pure-bash, no dep | PASS | grep yq/jq/python empty; T-PR-d green |
| PC4 secret-key guard | PASS | _config.sh:30-37; T-PR-e green |
| PC5 || true throughout | PASS | 5 guard sites independently read |
| PC6 exactly 3 call sites | PASS | grep count = 3; T-PR-f green |
| PC7 precedence (2-tier MVP) | PASS (NB-2) | meta.sh:29, cron:21; T-PR-b green; global tier documented-deferred |
| PC8 load order | PASS (NB-1) | board.sh doesn't use helper; meta.sh sorts after _config.sh; T-PR-g green |
| PC9 version + cron + manifest | PASS | VERSION=0.14.0; cron diff=2 lines; manifest diff empty |
| Tests 361/361 | PASS | Self-witnessed twice |
| Scope clean | PASS | 6 files changed; manifest/templates/bin/massoh/AGENT_SYNC/AGENT_BACKLOG untouched |
| Safety-critical files | PASS | All git diffs empty |
| 2-tier precedence call | NON-BLOCKING | Arch-safety §PC5 approved; documented in CHANGELOG + _config.sh header |
