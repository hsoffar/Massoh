---
name: req-check
description: Run the Massoh RMT requirements validator and print a structured summary. Only active when the project has agent-project/requirements.config.yml.
---

# /req-check

Input (optional):
$ARGUMENTS

## What this skill does

Runs the `req-check` reference validator against this project's requirements
registry and prints a summary of findings. If the project has no RMT config,
the skill exits silently (RMT is dormant — no error, no action needed).

## Steps

1. Check whether `agent-project/requirements.config.yml` exists in the project
   root. If it does not: print `RMT not enabled for this project (no config found).`
   and stop. This is not an error.

2. Locate the `req-check` script. Look in order:
   a. `scripts/req-check` (local copy in the project — preferred if present).
   b. `~/.claude/agent-os/scripts/req-check` (installed engine copy).
   If neither is found: print an error explaining where to find the script and
   that `pip install pyyaml` may be required.

3. Run the validator:
   ```
   python3 <req-check-path> \
     --config agent-project/requirements.config.yml \
     --registry requirements/registry.yml \
     [--baseline HEAD~1]
   ```
   Pass any arguments from `$ARGUMENTS` through (e.g. `--baseline main`).

4. Print a structured summary:
   ```
   req-check summary
   -----------------
   Config:   agent-project/requirements.config.yml
   Registry: requirements/registry.yml
   Baseline: HEAD~1

   Result: PASSED / FAILED
   Errors:   <N>
   Warnings: <N>

   [list each ERROR and WARN line from the validator output]
   ```

5. If the result is FAILED:
   - State which check IDs failed (C01–C12) and what each means.
   - Suggest the specific fix for each finding (e.g. "add removed_reason",
     "set owner_approved: true", "fix the code path").
   - Do NOT auto-edit the registry or config. The registry is append-only;
     edits go through the normal workflow.

6. If the result is PASSED:
   - Confirm all checks green.
   - Note any warnings and suggest whether they need follow-up.

## Rules

- Read-only: this skill never edits the registry or config.
- Append-only: if a finding is "ID disappeared", the fix is always to restore
  the entry with `status: removed` — never to silence the check.
- Safety guard: if C10 fires, remind the owner that removing a safety-locked
  requirement requires explicit sign-off (`owner_approved: true`) and cannot
  be bypassed.
- If PyYAML is not installed, suggest: `pip install pyyaml` (adopting project
  only; the Massoh engine itself does not require it).

## Dependency note

`req-check` requires Python 3.8+ and PyYAML. This dependency is scoped to the
adopting project's CI / local environment. The Massoh engine ships the script
as a template; projects that have not opted in to RMT never run it.
