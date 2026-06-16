# 10 — Agent history audit ledger (template)

The `massoh-history-maintainer` keeps this ledger (the project keeps its own copy). It records every
cleanup pass so history is **compressed, never lost**. ADRs are append-only — never rewritten.

## Pass log
| Date | Scope audited | Keep | Merge | Deprecate | Archive | New source of truth |
|---|---|---|---|---|---|---|
| _e.g._ 2026-01-01 | root `*.md`, `.claude/` | … | … | … | … | … |

## Rules
- **Preserve before pruning.** Archive or summarize; never delete useful content (keep-older-data).
- Replaced file → deprecation header (`> Deprecated: replaced by [x]. Preserved for history.`).
- Reusable workflow content that surfaces in a project belongs **upstream in Massoh** — note it for
  promotion rather than copying it per project.
- Keep `AGENT_SYNC.md` a dashboard; long history goes to `archive/`.

## Migration notes
Free-text: what moved where, and why it's safe.
