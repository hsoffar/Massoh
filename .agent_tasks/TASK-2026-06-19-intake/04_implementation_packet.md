# 04 — Implementation Packet (LICENSE TO CODE): `massoh intake` (24h queue #4)

- **Task ID:** TASK-2026-06-19-intake
- **Date issued:** 2026-06-19
- **Issued after:** arch-safety APPROVED (`03`, IK1–IK11) + owner **batch-authorization** +
  **auto-merge-on-green** (AGENT_SYNC decision log 2026-06-19). No separate sign-off.
- **Target VERSION:** 0.12.0
- **Branch:** `feat/intake`
- **No merge dependency** — `bin/massoh` already modular (v0.11.0).

## Scope
New verb `massoh intake "<idea>"`: append ONE ranked row to a dedicated `## Intake inbox` section of
`AGENT_BACKLOG.md` (bootstrapped via `>>` on first use, after Done/Frozen) + a one-line pointer to
`memory/MEMORY.md`; assign value×safety priority (P0–P3) if unstated; idempotent; **never reads-for-
rewrite or touches Queue/Done/Frozen**. New `lib/verbs/intake.sh` + one dispatch line + `intake` in
usage. No manifest change (`lib/verbs/` already a dir). VERSION→0.12.0; CHANGELOG `[0.12.0]`.

## Mandatory conditions IK1–IK11 (from `03`; all required, cite file:line in `05`)
- **IK1** (highest risk) named `BACKLOG` var + `# SAFETY` comment; **single `printf >>`** to the
  `## Intake inbox` section only; **zero `sed -i`, zero `> file`, zero `mv tmp file`, zero awk
  full-file rewrite** — Queue/Done/Frozen never touched.
- **IK2** sanitize `|`, `\n`, `\r`, tab from the idea; truncate 200 chars; reject empty-after-strip.
- **IK3** arg guard first executable statement; missing idea → die, exit non-zero, **write nothing**.
- **IK4** idempotent — `grep -qF "$idea_clean" "$BACKLOG" || true`; if present, notice + exit 0, no append.
- **IK5** deterministic priority heuristic (keyword scan → P0–P3), zero LLM, documented in-file.
- **IK6** memory pointer appended to `memory/MEMORY.md` (named `MEMORY` var, `>>`); failure `|| true` (non-fatal); never clobber the index.
- **IK7** `|| true` on all reads; absent BACKLOG bootstraps via `>>`; degrade exit 0.
- **IK8** Massoh-project guard (`.massoh`/`agent-project/`) before any write.
- **IK9** no calls into other `cmd_*`; read-only isolation.
- **IK10** one dispatch line in `bin/massoh` + `intake` in usage (batch-authorized); no manifest change.
- **IK11** VERSION 0.12.0 + CHANGELOG.

## Required tests T-IK-a…k (11 new; suite 301 → 312)
Per `03`: append-only (existing Queue/Done/Frozen rows byte-identical after an intake — capture
before/after); `grep -c 'sed -i' lib/verbs/intake.sh` == 0; pipe/newline/tab sanitization; idempotent
re-run = no dup; empty-arg dies writing nothing; priority assignment correct for sample inputs;
degrade on missing/oddball file; non-Massoh-dir guard; memory pointer appended; suite green.

## Acceptance criteria
1. IK1–IK11 satisfied — file:line each in `05`.
2. T-IK-a…k present + green; suite ≥312; verbatim output.
3. **Append-only proof:** diff of Queue/Done/Frozen before vs after an intake run = empty.
4. Zero regressions; bin/massoh diff = 2 additive lines (dispatch + usage).
5. VERSION 0.12.0; CHANGELOG.

## Rollback
Revert the PR; delete `lib/verbs/intake.sh`; the `## Intake inbox` section is additive/harmless.

## Routing
`massoh-implementer` (branch `feat/intake`) → `05` → `massoh-reviewer-qa` (06) → **auto-merge on green**.
