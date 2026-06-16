# 08 — Feature-gate template (portable)

If the project opts into feature flags (recommended), **every new user-facing feature ships behind a
flag, default OFF**, per-scope (per-user / per-cohort / global). Flag-dark = existing users see no
change → safe to merge + deploy even on an autonomous tick.

## Checklist per flagged feature
- [ ] Flag name chosen (stable, descriptive, e.g. `feature_x`).
- [ ] Registered in the **single source of truth** for flags (the project's flag registry).
- [ ] **Default OFF** everywhere — server default + any client default **mirror each other** (add a
      drift test if the client hard-codes defaults).
- [ ] New behavior is reachable **only** when the flag is ON; OFF path is byte-identical to before.
- [ ] A **real test** covers both flag states (OFF = unchanged, ON = new behavior).
- [ ] Enable path documented (how the owner turns it on for a tester / cohort).
- [ ] Rollback = flip the flag OFF (no redeploy needed).

## Why default-OFF + mirrored defaults
The owner enables a feature deliberately, per audience, after seeing it. A client that hard-codes a
default which drifts from the server is a silent bug — a drift test catches it. Keep the OFF path
identical so "merge" never means "behavior change for everyone".

## Project fills in
- the flag registry location + the enable mechanism (admin panel / config / API),
- the scopes it supports (per-user / cohort / global),
- whether the client mirrors defaults (→ require the drift test).
