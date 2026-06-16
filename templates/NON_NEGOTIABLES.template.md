# NON_NEGOTIABLES — {{PROJECT}}

The project's hard constraints. The Massoh guardrails (`09_GUARDRAILS.md`) are portable; this file
supplies the **project-specific** content the agents enforce literally. Fill every section.

## Designated safety-critical files / policies (no change without owner sign-off)
{{ exact paths. e.g.:
   - backend/.../safety_filter.py
   - the safety rules inside prompt templates
   - the auth boundary at ...
   - the billing/cost calculation at ... }}

## Prohibited content (the product must never produce)
{{ e.g. medical/financial certainty; specific dosages; brand recommendations; PII echoes; ... }}

## Advisory / over-claim rules (if the product is advisory)
{{ the calibration that must stay: confidence levels, hedges, disclaimers. What would be false
   certainty (and is therefore blocked). If not advisory, write "N/A". }}

## Localization / UX invariants
{{ e.g. RTL must not break; primary language is X; accessibility floor is Y }}

## Data + migration policy
- Keep older data: append-only / soft-delete; never hard-delete or overwrite history.
- Migrations: {{ e.g. backward-compatible one release, expand→migrate→contract }}.

## Feature flags
{{ does this project flag-gate new features? default OFF? where is the flag registry? does the
   client mirror defaults (→ require a drift test)? }}

## Frozen (do not build without an explicit unfreeze)
{{ list, or "see AGENT_SYNC.md §Frozen" }}
