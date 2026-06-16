# 05 — Implementation Handoff

**Agent:** massoh-implementer · **Date:** 2026-06-16 · **Branch:** `feat/massoh-version-notify`

## Files changed
| File | Change |
|---|---|
| `bin/massoh` | +`mver`/`msha` helpers; +`cmd_version`; `version`/`--version`/`-v` dispatch; `status` shows version; `doctor` reports VERSION + best-effort update-check (opt-out `--offline`/`MASSOH_NO_FETCH`); install copies `VERSION`; `doctor` forwards args |
| `VERSION` | **new** — `0.2.0` |
| `CHANGELOG.md` | **new** — Keep-a-Changelog; `0.2.0` + `0.1.0` + "how to update" |
| `manifest.yml` | documents `VERSION` in the `agent-os/` payload (+ note to keep manifest ↔ install loop in sync) |
| `test/run.sh` | +T6 (version, update-check behind-origin, offline-safe, VERSION install/uninstall) |

## What was implemented
The whole `04` scope. `doctor`'s update-check is best-effort + opt-out + **exit-code-stable**
(staleness never flips exit). `doctor` stays filesystem-read-only (only `git fetch` touches `.git`).

## Tests run (verbatim)
```
$ bash test/run.sh
... T1–T5 unchanged ...
== T6: version + doctor update-check ==
  ok version prints semver / install wrote VERSION / doctor exit 0 even when behind
  ok doctor flags 'update available' / doctor --offline exit 0 / skips update-check / uninstall removed VERSION
ALL GREEN — 28 checks passed.   (exit 0)
```

## Live verification on this machine
`massoh version` → `massoh 0.2.0 (778e06a)`; `status` shows the version line. `massoh doctor`
reports `MISS agent-os/VERSION → drift` — **expected, not a defect**: the global install was stamped
from `main` (before VERSION existed); a `massoh install` after merge clears it. doctor correctly did
**not** print "update available" (this clone is ahead of main, not behind). Honest drift detection.

## Risks
- `doctor` now makes a network call (opt-out). Mitigated: `2>/dev/null || true`, `--offline`,
  `MASSOH_NO_FETCH=1`; tested offline-safe with a bogus remote.
- Two versions now exist: product `VERSION` (0.2.0) vs `manifest.yml version: 1` (install-schema).
  Documented in CHANGELOG to avoid confusion.

## Handoff for reviewer
Verify: manifest ↔ install loop in sync; doctor exit-stable on staleness; read-only md5 test still
green; offline-safe. Independence caveat: one session — owner is final reviewer/merger.
