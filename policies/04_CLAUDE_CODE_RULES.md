# 04 — Code-edit rules (portable)

When may an agent edit product code?
- Only in `IMPLEMENTATION` mode, with a **license** (`04_implementation_packet.md` or an approved
  issue with acceptance criteria), with acceptance criteria, on a **non-default branch**.
- Markdown artifacts (packets, docs, sync) are editable in any mode.
- An explicit owner request can override — say so in the preflight block.

## The rules (every implementation)
1. Implement **exactly** the approved scope. No hidden features, no broad refactors.
2. **Flag-gate** new user-facing behavior if the project requires it (default OFF).
3. Add a **real test** that exercises the actual path; run the project's integration suite.
4. **Keep older data** — append-only / soft-delete; never hard-delete or overwrite history.
5. Preserve **API compatibility** unless the packet changes the contract — then ship **both sides**
   of the seam (named in `agent-project/CHARTER.md`) together.
6. Never touch a **designated safety-critical file/policy** (`NON_NEGOTIABLES.md`) without sign-off.
7. **Branch + PR per feature.** Small Conventional Commits with the project's `Co-Authored-By`
   trailer. Never commit secrets, local config, build outputs, or datasets.
8. **Bump the version** on shipped client changes if the project versions its client.
9. Leave a **reviewer handoff** (`05_implementation_handoff.md` or the PR description).
10. **Report honestly** — failing tests are reported with output; "done" means verified.

## Owner-gated (stop — see `09_GUARDRAILS.md` §B)
safety-critical files · irreversible/destructive ops · production deploy to a real-user environment
· significant cost · unfreezing a frozen feature.
