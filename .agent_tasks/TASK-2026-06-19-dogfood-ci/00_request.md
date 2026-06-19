# 00_request.md — TASK-2026-06-19-dogfood-ci

## Request
Dogfood the Massoh gate + add GitHub Actions CI (24h queue item #2).

## License
Licensed by the owner-authorized 24h queue in `AGENT_BACKLOG.md` §"24h queue — acceptance stubs",
item #2, plus the batch-authorized queue approval recorded in `AGENT_SYNC.md` (2026-06-19).
This is an exempt-path task (`.github/` only — no `bin/massoh`, no `manifest.yml`, no
safety-critical files); no `04_implementation_packet.md` required, but this trail is created for
audit completeness.

## Acceptance criteria (from AGENT_BACKLOG.md)
- `.github/workflows/ci.yml` runs `bash test/run.sh` on PR + push to main
- The job goes red on any test failure
- Zero changes to existing verbs (bin/massoh, lib/verbs/*)

## Scope
1. `.github/workflows/ci.yml` — GitHub Actions workflow (additive, new file)
2. `.agent_tasks/TASK-2026-06-19-dogfood-ci/00_request.md` — this file
3. `.agent_tasks/TASK-2026-06-19-dogfood-ci/05_implementation_handoff.md` — trail

## Out of scope
- `massoh gate on` — the local pre-push hook; owner runs this manually after review.
  The CI workflow is the durable enforcement; the hook is optional local convenience.
- No changes to bin/massoh, lib/verbs, manifest.yml, templates/, agent-os/policies/.

## Date
2026-06-19

## Requested by
Owner (via authorized 24h queue fan-out)
