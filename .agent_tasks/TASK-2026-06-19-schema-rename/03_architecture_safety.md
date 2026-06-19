# 03 — Architecture / Safety Review
## Task: rename `manifest.yml version:` → `schema_version:` (queue #11)

**Reviewer:** massoh-architecture-safety
**Date:** 2026-06-19
**Sign-off on file:** Owner BATCH-AUTHORIZED `bin/massoh` edits (AGENT_SYNC decision log 2026-06-19)
  AND Owner SIGNED OFF on `manifest.yml + bin/massoh` for #11 specifically (AGENT_SYNC 2026-06-19,
  same decision row as #7 RMT). No fresh sign-off required.

---

## 1. Backend / service impact

None. Massoh is a local CLI; there is no remote backend. The manifest is a local file read only by
`bin/massoh` during install, uninstall, doctor, and status. The rename affects only the YAML key
name used to stamp the install-boundary schema version.

## 2. Client / app impact

No client or app layer. `massoh status` and `massoh version` print the product version from the
`VERSION` file via `mver()` — that helper reads `$MASSOH_HOME/VERSION`, not `manifest.yml`. Those
commands are unaffected by this rename.

## 3. API / contract impact

The manifest.yml is the install/uninstall contract boundary. The `version:` key in that file is
the schema stamp for that contract — it is distinct from the product `VERSION` file. The rename
is a key-name change within the contract, not a change to what the contract governs. **No external
API, no network protocol, no inter-process contract is involved.**

Contract-seam rule (NON_NEGOTIABLES.md): manifest.yml and bin/massoh must change in the same
commit (lockstep). This is addressed by SR1 below.

## 4. DB / migration impact

No database. The equivalent of a migration is the installed copy of `manifest.yml` written to
`~/.claude/agent-os/manifest.yml` by `massoh install`. An old installed manifest (still carrying
`version: 1`) must be readable by the updated binary for one release — the backward-compat fallback
handles this (SR2).

## 5. LLM / prompt impact

None. The manifest is not read by any agent prompt. `mver()` reads `VERSION`, not `manifest.yml`.
No prompt layer is touched.

## 6. Safety / guardrail risks and conditions

### Manifest-version readers found in bin/massoh: ZERO (0)

Exhaustive grep result: `bin/massoh` contains **no code that reads the `version:` key from
`manifest.yml`**. The `mver()` helper (line 17) reads the `VERSION` file. The `version:`/
`schema_version:` key in `manifest.yml` is currently purely documentary — it is written there as
a schema stamp but is not parsed or consumed by any code path in `bin/massoh`, `lib/verbs/*.sh`,
or `test/run.sh`.

Confirmation commands run:
- `grep -n "version" bin/massoh` — all matches are `cmd_version`, `mver()` (reads VERSION file),
  and `say "  version: ..."` (status output). None parse `manifest.yml`.
- `grep -rn "version:" lib/ test/` — no matches for manifest key reads.
- `grep -rn "schema_version"` — only backlog/sync references.
- `grep -rn "version:" *.yml` — only `manifest.yml` itself and GitHub workflow files.

This makes the operational risk of this change very low: there is currently no reader to break.
The backward-compat fallback (SR2) is still required by NON_NEGOTIABLES.md policy because the
installed `~/.claude/agent-os/manifest.yml` constitutes the live contract, and a future reader
must not crash on the old key.

### SR1 — Lockstep commit
The rename of `version:` in `manifest.yml` and any new reader logic in `bin/massoh` must land in
**a single atomic commit**. No intermediate state where the key name is inconsistent between the
two files.

Acceptance: PR diff contains both files; CI runs against the combined state.

### SR2 — Backward-compat fallback (one release)
Although no current code reads the manifest `version:` key, NON_NEGOTIABLES.md requires that
changes to the install/uninstall contract be backward-compatible for one release so an old installed
layout still uninstalls cleanly. The implementer MUST add a reader helper to `bin/massoh` that
prefers `schema_version:` and falls back to `version:` with a deprecation note. Shape:

```bash
manifest_schema_ver() {
  local f="$MASSOH_HOME/manifest.yml"
  local v
  v=$(grep -m1 '^schema_version:' "$f" 2>/dev/null | awk '{print $2}') || true
  if [ -z "$v" ]; then
    v=$(grep -m1 '^version:' "$f" 2>/dev/null | awk '{print $2}') || true
    [ -n "$v" ] && say "  note: manifest uses deprecated 'version:' key; update to 'schema_version:' (compat until v0.19)" >&2 || true
  fi
  printf '%s' "${v:-unknown}"
}
```

The helper must be safe under `set -euo pipefail`: all grep/awk calls guarded with `|| true`; the
result defaults to `unknown` rather than empty. It must not crash when called against an old
installed manifest that still has `version:` only.

### SR3 — No other key-name dependents
The comprehensive grep confirmed: `lib/verbs/*.sh` contains no reads of the manifest `version:`
key. `test/run.sh` line 1727 (`grep -q 'version:'`) matches the `  version:` string in
`massoh status` output (which comes from `say "  version: $(mver) ($(msha))"` in `cmd_status`,
line 126 of `bin/massoh`) — this is NOT a manifest key read; the test will continue to pass
unchanged. No action required on `test/run.sh` for this check.

### SR4 — Comment in manifest.yml header updated
`manifest.yml` line 2 is a comment `# version: 1`. After the rename the comment line must also
become `# schema_version: 1` (or be removed) to stay consistent with the live key on line 8.

### SR5 — Documentation references
Three documentation strings reference `manifest.yml version:` by name:
- `CHANGELOG.md` line 4: "the engine's `manifest.yml version:` is separate"
- `CHARTER.md` line 43: "engine carries `manifest.yml version:`"
- `manifest.yml` line 2: comment `# version: 1`

These are documentation, not code. They do not affect runtime behavior. The implementer SHOULD
update them in the same PR for consistency, but a failure to do so is not a safety issue — it is
a documentation drift issue. Flag for reviewer-qa.

### SR6 — set -euo pipefail safety
Any new reader logic must not cause an unguarded subshell failure that kills the process. All grep
invocations against manifest.yml must be `|| true` so a missing key or missing file does not exit
the script. The `|| true` pattern is already used elsewhere in `bin/massoh` (lines 24-26) and is
the established idiom in this codebase.

### SR7 — Product VERSION file untouched
The `VERSION` file (read by `mver()`) is NOT part of this change. `massoh version` and
`massoh status` output are unaffected. This must be verified in the PR diff.

## 7. Expansion / localization risks

None. The manifest key name is internal to the CLI tool. It is not user-visible in any localized
surface. The POSIX-bash constraint is not affected.

## 8. Required tests

| ID | Description | Assertion |
|----|-------------|-----------|
| T-SR-1 | New key present in manifest | `grep -q '^schema_version:' manifest.yml` |
| T-SR-2 | Old key absent from manifest | `! grep -q '^version: ' manifest.yml` |
| T-SR-3 | Reader with new key returns correct value | Install with new manifest; `manifest_schema_ver` (or equivalent call site) outputs `1` |
| T-SR-4 | Backward-compat fallback: old key still readable | Inject a synthetic manifest with only `version: 1` (no `schema_version:`); call the new reader; assert it returns `1` and emits a deprecation note to stderr |
| T-SR-5 | No crash under set -euo pipefail with missing key | Supply a manifest with neither key; call the reader; assert it exits 0 and outputs `unknown` |
| T-SR-6 | `massoh doctor` exits 0 and reports correctly | Run `massoh doctor` with new install; assert exit 0; assert "healthy" in output |
| T-SR-7 | `massoh status` output unchanged | `massoh status` still prints `  version: <semver>` (from VERSION file, not manifest) |
| T-SR-8 | `massoh version` output unchanged | `massoh version` still matches `^massoh [0-9]+\.[0-9]+` |
| T-SR-9 | Existing T-MB-a passes | `massoh status` output still contains `version:` (the status line, not manifest key) |
| T-SR-10 | manifest.yml checksum tests (T11i, T15l, T16r, T22b) | These check that non-install verbs do not modify manifest.yml at runtime — they will require a new baseline checksum after the rename. Update the baseline captures in test/run.sh or let them recompute naturally. |
| T-SR-11 | Full test suite green | `test/run.sh` exits 0 (current suite count + SR tests) |

Test target: current suite total + 11 new SR assertions. Suite must remain green.

## 9. Rollback plan

The change is purely additive and reversible:

1. Revert the PR (GitHub revert button): restores `manifest.yml` to `version: 1` and removes the
   new reader helper.
2. Run `massoh install` to push the reverted manifest to `~/.claude/agent-os/manifest.yml`.
3. No data is lost; no user files are affected; no backup restoration needed.
4. The backward-compat fallback (SR2) ensures that during the one-release overlap window, a user
   who already installed the new manifest but rolls back the binary will have the old binary read
   `version:` (which the new manifest no longer has) — the old binary also has no manifest-key
   reader, so there is no failure. The only effect is the schema stamp is not verified, which was
   always the case before this change.

## 10. Verdict

**APPROVED for implementation.**

Owner sign-off is on record in `AGENT_SYNC.md` decision log (2026-06-19, row citing #11
schema-rename). No fresh sign-off is required.

This is a clean rename with fallback. Zero readers currently consume the manifest `version:` key,
so operational risk is minimal. The backward-compat fallback (SR2) is required by policy and must
be implemented even though no current reader would break without it — it future-proofs against any
reader added in the same or subsequent release.

Conditions that must be satisfied for the PR to merge (all are implementation-time checks):

- SR1: lockstep commit (both files in same PR, same commit)
- SR2: backward-compat reader helper present in bin/massoh (prefers schema_version:, falls back to
  version: with deprecation note, safe under set -euo pipefail)
- SR3: confirmed no other readers (already confirmed; implementer re-checks with grep before merge)
- SR4: manifest.yml comment line updated to match new key name
- SR5: documentation references updated (CHANGELOG.md, CHARTER.md) — reviewer-qa flags if missed
- SR6: all grep/awk in new reader guarded with || true
- SR7: VERSION file untouched (verify in PR diff)
- T-SR-1 through T-SR-11: test suite green

**Condition count: 7 SR conditions + 11 test assertions = 18 total checkpoints.**

**Manifest-version readers found in bin/massoh: 0** (the key is documentary-only in the current
codebase; `mver()` reads the `VERSION` file, not `manifest.yml`).

**Backward-compat mechanism:** new reader helper in `bin/massoh` — `grep '^schema_version:'` first,
then `grep '^version:'` fallback with deprecation note to stderr; both paths guarded `|| true`;
default `unknown` on empty result.

**Test target:** current suite + 11 new T-SR-* assertions.

**Highest risk:** SR2 (implementer forgets to add the reader helper at all, leaving no fallback for
a future reader). Mitigated by T-SR-4 and T-SR-5 which would fail if the helper is missing.

**Version target:** v0.18.0 (as specified in 00_request.md; serial after #7 done, before #12).
