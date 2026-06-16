# METRICS + activation — Massoh

Product Scope requires every "Build" to name an event here, or the answer is Defer.

## Funnel / activation events (named)
| Event | Meaning | Stage |
|---|---|---|
| `install` | `massoh install` run → global team present | acquisition |
| `repo_opted_in` | `massoh on` run in a repo (`.massoh` created) | activation (start) |
| `packet_merged` | a task taken `00→06` and merged | activation (complete) |
| `second_repo` | a 2nd distinct repo opted in | retention |

## Activation definition
A repo opts in **and** lands one packet through the full gate to a merge, within ~7 days of install.

## What we do NOT instrument yet
No telemetry wiring (local CLI tool). Events are counted by hand from `git` + `.agent_tasks/` until
`massoh report` exists (LATER).
