# 05_implementation_handoff.md — TASK-2026-06-19-dogfood-ci

## Status
COMPLETE — ready for review / merge.

## Files created (additive only)
- `.github/workflows/ci.yml` — GitHub Actions CI workflow (NEW)
- `.agent_tasks/TASK-2026-06-19-dogfood-ci/00_request.md` — request trail (NEW)
- `.agent_tasks/TASK-2026-06-19-dogfood-ci/05_implementation_handoff.md` — this file (NEW)

## Files NOT touched
bin/massoh, lib/verbs/*.sh, manifest.yml, templates/, agent-os/policies/,
NON_NEGOTIABLES.md, AGENT_SYNC.md, AGENT_BACKLOG.md — none modified.

## What was implemented

### `.github/workflows/ci.yml`
Triggers on `push` to `main` and on `pull_request` (all branches). Runs on `ubuntu-latest`.

Steps:
1. `actions/checkout@v4` — standard checkout
2. `sudo apt-get install -y jq` — installs jq (required by T19-T21 board tests which capture
   Plane API request bodies via curl interceptors)
3. `bash test/run.sh` — runs the full suite

### How a failing suite fails the job (exact mechanism)
`test/run.sh` unconditionally exits via `[ "$fails" -eq 0 ]` as its last line (line ~1813).
When any check fails, `$fails` is incremented, and this final `[ ... ]` expression evaluates to
false, causing `test/run.sh` to exit with code 1. The GA step has no `continue-on-error` and
no output-grep fallback needed — the non-zero exit from `test/run.sh` directly fails the
`Run test suite` step, which fails the job, which fails the CI check. No grep-for-marker is
needed because the exit-code path is clean.

### Why jq is needed
The test suite T21 tests the jq-guard path (T21a: jq absent → exit 1), and T18/T19/T20 tests
use `jq` to verify request bodies captured from mock curl calls. `ubuntu-latest` does not ship
jq by default; without it, T21a (the "absent jq" test) constructs a stripped PATH to simulate
absence, but the outer test harness itself needs jq available for the other board tests. Adding
`sudo apt-get install -y jq` ensures the full suite passes cleanly.

## Tests run locally
```
bash test/run.sh
ALL GREEN — 301 checks passed.
Exit code: 0
```
Witnessed 2026-06-19 on feat/dogfood-ci (same working tree as this PR).

## YAML validation
Parsed with Python `yaml.safe_load` — all required keys present:
- `name: CI`
- trigger block: `push.branches=[main]` + `pull_request`
- `jobs.test.runs-on: ubuntu-latest`
- 3 steps: checkout, jq install, `bash test/run.sh`
Note: bare `on` parses as boolean `True` in YAML 1.1 (Python quirk); GitHub Actions handles
this correctly — this is a well-known, harmless parser discrepancy.

## Regarding `massoh gate on`
The task explicitly defers running `massoh gate on` in this session to avoid installing a
local pre-push hook mid-session on feat/dogfood-ci. The CI workflow (`.github/workflows/ci.yml`)
is the durable enforcement — every PR and push to main goes through `bash test/run.sh` in CI.
To also enforce locally, the owner can run:
```
massoh gate on
```
from the repo root after merging. This installs `.git/hooks/pre-push` (which calls the gate
checker) and the gate CI workflow is already present.

## Risks
- None material. The workflow is additive; removing it is a one-line git revert.
- `ubuntu-latest` image changes could affect jq availability; the explicit `apt-get install -y jq`
  step makes this explicit and immune to image changes.
- If GitHub ever retires `actions/checkout@v4`, pin to a SHA or bump to v5.

## Incomplete items
None. Acceptance criteria fully met:
- [x] `.github/workflows/ci.yml` triggers on PR + push to main
- [x] Runs `bash test/run.sh`
- [x] Non-zero exit from suite fails the job (no grep-for-marker needed — clean exit path)
- [x] 301/301 green locally confirmed
- [x] Zero changes to existing verbs or safety-critical files

## Handoff for reviewer
Branch: `feat/dogfood-ci`
Changes: 3 new files, 0 existing files modified.

Reviewer checks:
1. Read `.github/workflows/ci.yml` — confirm `bash test/run.sh` is the run command, trigger
   covers `pull_request` and `push.branches: [main]`, runner is `ubuntu-latest`, jq is installed.
2. Confirm no existing file was modified (`git diff main -- bin/massoh lib/ manifest.yml` = empty).
3. Confirm `bash test/run.sh` exits non-zero when a test fails (mechanism: `[ "$fails" -eq 0 ]`
   final line in test/run.sh — independently verify by reading the last 5 lines of test/run.sh).
4. The 3 new `.agent_tasks/TASK-2026-06-19-dogfood-ci/` files are trail only; content is
   additive and append-only.

This is a safe, low-risk merge. No owner sign-off needed beyond normal review (`.github/` is
exempt from the license-gate; no safety-critical files touched).
