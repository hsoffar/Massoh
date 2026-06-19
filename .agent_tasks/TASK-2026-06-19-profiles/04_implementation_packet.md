# 04 — Implementation Packet (LICENSE TO CODE): profiles + config.yml (24h queue #9)

- **Task ID:** TASK-2026-06-19-profiles
- **Issued after:** arch-safety APPROVED (`03`, PC1–PC9) + owner batch-auth + auto-merge-on-green. No sign-off (manifest untouched).
- **Target VERSION:** **0.14.0** (#6 fleet takes 0.13.0 and merges first; rebase onto post-#6 main).
- **Branch:** `feat/profiles`. Implement AFTER #6 merges (serialize on main tree; correct VERSION).

## Scope
Optional `agent-project/config.yml` (project override > global `~/.claude/massoh/config.yml` >
built-in default) read by verbs via a new `lib/verbs/_config.sh` helper (`massoh_config_get <key>
<default>`). **Absent/empty/malformed = today's exact defaults (byte-identical).** MVP migrates
EXACTLY 3 named tunables: cron idleness window (bin/massoh-cron), meta `OUTLIER_FACTOR` +
`REPEAT_THRESHOLD` (lib/verbs/meta.sh). NO scaffold/manifest change (no-scaffold path). Additive.

## Mandatory conditions PC1–PC9 (from `03`; cite file:line in `05`)
- **PC1** absent config → byte-identical existing behavior (the central guarantee).
- **PC2** (highest) any config value entering arithmetic is integer-validated (mirror ledger.sh L2);
  never crash under `set -euo pipefail`.
- **PC3** parser = pure-bash grep/sed in `_config.sh` — **no yq, no new dep**; handle comments,
  whitespace, missing keys, quoting; missing/malformed key → return the provided default.
- **PC4** secret guard: keys matching `_token|_key|_secret|_password|_credential` → warn + return
  default (config.yml is committable; no secrets); template/header warning.
- **PC5** `|| true` / default-fallback throughout; malformed YAML → all defaults, exit 0.
- **PC6** scope: EXACTLY 3 `massoh_config_get` call sites (no broad refactor).
- **PC7** precedence project > global > built-in, implemented exactly.
- **PC8** `_config.sh` sourced/usable after the bin/massoh sourcing loop (load order).
- **PC9** VERSION 0.14.0 + CHANGELOG; bin/massoh-cron change minimal (≤2 lines); manifest untouched.

## Required tests T-PR-a…g (7; suite → target ≥334 over then-current baseline)
no-config byte-identical (both verbs); project value overrides default (all 3) + revert regression;
malformed integer → default, exit 0; malformed YAML → all defaults; secret-key guard warns + default;
scope = exactly 3 `massoh_config_get` calls (grep count); helper callable after sourcing loop.
Run `bash test/run.sh`, confirm green.

## Acceptance criteria
1. PC1–PC9 satisfied (file:line each). 2. T-PR-* green; suite green; verbatim output + no-config
byte-identical proof. 3. Zero regressions. 4. No manifest/scaffold change. 5. VERSION 0.14.0.

## Rollback
Remove `lib/verbs/_config.sh`; revert the 3 verb lines + cron line. No manifest/user-file impact.

## Routing
`massoh-implementer` (branch `feat/profiles`, off post-#6 main) → `05` → `massoh-reviewer-qa` (06) →
auto-merge on green.
