# 00 — Request: profiles + single config.yml (24h queue #9)

- **Task ID:** TASK-2026-06-19-profiles
- **Date:** 2026-06-19 · owner (24h queue #9) · batch-authorized + auto-merge-on-green.
- **Classification:** ARCHITECTURE_SAFETY → IMPLEMENTATION.

## Goal (AGENT_BACKLOG acceptance stub #9)
A single `agent-project/config.yml` (global default + project override) read by the verbs; **absent =
current defaults** (pure no-op for existing repos); additive.

## Scope intent
Introduce an optional config file consolidating tunables already scattered as defaults/env (e.g.
cron idleness window, OUTLIER_FACTOR/REPEAT_THRESHOLD for meta, recommend thresholds, board config
pointers). Verbs read it if present; fall back to today's hard-coded defaults if absent or a key is
missing. No new runtime deps (bash-parseable; avoid requiring yq — likely a small `key: value` grep
parser, arch-safety to decide).

## Risks for arch-safety
- **No behavior change when absent/empty** (the central guarantee — existing repos unaffected).
- Parser safety under `set -euo pipefail`; malformed/missing keys degrade to defaults, never crash.
- No secrets in config.yml (it's committable); document that.
- Precedence rules (project override > global default > built-in default) — define clearly.
- Decide the parse mechanism (pure-bash `key: value` reader vs requiring yq — prefer no new dep).
- Which existing tunables migrate (keep minimal; additive).

## Routing
`massoh-architecture-safety` → `03` (conditions + tests + parser decision) → (batch-auth) → `04` →
implementer → reviewer-qa → auto-merge on green. No merge dependency.
