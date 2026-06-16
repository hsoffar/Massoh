# NOW / NEXT / LATER — Massoh

## NOW (in flight)
None. Shipped v0.1→v0.3 (discover, doctor, version+update-check, cron). Designing **v0.4 cadence**.

## NEXT (queued, agreed)
- **v0.4 — cadence / ceremonies** (owner request): agent-native "meetings" — a *sense of time* where
  progress is revisited, KPIs gathered, decisions taken. `massoh standup` (DOING/DONE/BLOCKED delta),
  `massoh review` (KPI report → `METRICS.md`), `massoh plan` (re-rank + surface owner decisions),
  retro→memory. Driven by the `cron` cadence. cron = *do* work; cadence = *review* + *decide*.
- Enforce the license-to-code gate mechanically (pre-commit / pre-push + CI check).

## LATER (someday / maybe)
- Emit `AGENTS.md` → multi-harness (Cursor / Codex / Antigravity).
- Profiles (global default + project override) + a single `config.yml`.
- Package as a Claude Code plugin / marketplace entry.

## FROZEN (do not build without an explicit owner unfreeze)
None yet. Mirror the authoritative list in `AGENT_SYNC.md` §Frozen.

## DEFERRED / KILLED (kept — never deleted)
| Item | Decision | Reason | Re-entry condition | Date |
|---|---|---|---|---|
| Multi-harness (`AGENTS.md`) | Defer | Prove Claude-Code flow first | ≥2 repos through gates | 2026-06-16 |
