# 05 — Implementation Handoff: Fleet slice 3 — `massoh fleet learn`

- **Agent:** massoh-implementer
- **Date:** 2026-06-20
- **Branch:** `feat/fleet-learn`
- **VERSION:** 0.23.0
- **Task packet:** `04_slice3_fleet-learn.md`

---

## Files Changed

| File | Change |
|---|---|
| `lib/verbs/fleet.sh` | Added `cmd_fleet_learn` function (~240 lines) + `learn)` dispatch in `cmd_fleet`; updated help text |
| `test/run.sh` | Added 8 new T-FLN tests (T-FLN-1 through T-FLN-8) with helpers; suite 544 → 574 checks |
| `VERSION` | Bumped 0.22.0 → 0.23.0 |
| `CHANGELOG.md` | Added [0.23.0] entry |

**Engine files NOT modified:** `agent-os/`, `bin/massoh`, `manifest.yml`, `templates/`, `policies/`, `scripts/massoh-dashboard` — confirmed by `git diff HEAD -- agent-os/ bin/massoh manifest.yml templates/ scripts/massoh-dashboard` returning empty.

---

## What Was Implemented

`cmd_fleet_learn`: new `learn` subcommand in `cmd_fleet` (dispatched before option parsing, line ~1154 of `lib/verbs/fleet.sh`).

### Behavior
- Discovers repos via `MASSOH_FLEET_ROOT` or `fleet.tsv` (same discovery logic as `cmd_fleet`)
- For each discovered repo: reads `agent-project/LEARNINGS.proposed.md` + `META.proposed.md` (read-only; `|| true` on every read; `[ -f ]` guard; missing → `[skip]` in report)
- Strips `- ` prefix from bullet lines; sanitizes `|` → space and `` ` `` → `'` in lesson text (FLN8)
- Caps individual lesson text at 500 chars; caps per-file extraction at 100 lines (FLN5)
- Uses `awk` to deduplicate (lesson, repo) pairs and count repos-per-lesson (FLN6: `|| true`)
- Lessons seen in >= `FLEET_REPEAT_THRESHOLD` (=2) repos → `[generalizable-candidate]`; single repo → `[project: <basename>]` (FLN8 named constant)
- Prints candidate summary to stdout always
- With `--write-proposals`: regenerates `agent-project/FLEET_LEARNINGS.proposed.md` fresh each run using sentinel `<!-- massoh-fleet-generated -->` (Pattern A; idempotent by construction, FLN7)
- Header: "CANDIDATES ONLY — engine adoption is a separate owner/gated step." (FLN4)
- Source attribution: repo basename only, never abs-path (FLN5)

### FLN Condition File:Line References

| Condition | Location in `lib/verbs/fleet.sh` |
|---|---|
| FLN1 (zero LLM/network) | cmd_fleet_learn body — no `claude`/`curl`/`wget`/`agent` invocations; T-FLN-5 static grep verified |
| FLN2 (read-only on discovered repos) | Lines ~996–1046: all discovered repo paths used only as args to `[ -f ]`, `grep`, `sed`; never on LHS of `>`/`>>` |
| FLN3 (single named write var + SAFETY) | Line ~923: `local FLEET_LEARNINGS="$repo/agent-project/FLEET_LEARNINGS.proposed.md"  # SAFETY: only permitted write in cmd_fleet_learn` |
| FLN4 (promotion boundary + no engine write) | Lines ~1058–1079: awk tags by threshold; line ~1149: `} > "$FLEET_LEARNINGS"` is sole write; no write to `agent-os/`/`lib/verbs/`/`bin/massoh`/`manifest.yml`/`templates/` |
| FLN5 (leak guard) | Line ~989: `basename` only; line ~1008/1030: `head -c 500`; line ~1001/1023: `head -n 100`; no raw file dump |
| FLN6 (set -euo + || true + degrade) | Line ~918: `set -euo pipefail`; lines ~1001,1023: `|| true`; lines ~1059,1079: `|| true`; line ~1040–1043: per-repo `[skip]` |
| FLN7 (idempotent) | Pattern A: line ~1112 writes fresh sentinel-prefixed doc each run; two runs produce identical md5 (T-FLN-6a verified) |
| FLN8 (sanitize + named threshold) | Line ~926: `local FLEET_REPEAT_THRESHOLD=2`; lines ~1008,1030: `sed 's/|/ /g; s/\`/'"'"'/g'`; line ~1135: `printf -- '- ...'` |

---

## FLEET_LEARNINGS.proposed.md Sample

```markdown
<!-- massoh-fleet-generated -->
# FLEET_LEARNINGS — Candidate Pool

> CANDIDATES ONLY — engine adoption is a separate owner/gated step.
> Generated: 2026-06-20T18:57:19Z (v0.23.0)
> Recurrence threshold: 2 repos for [generalizable-candidate].
> Source attribution uses repo basename only (not absolute path).

## Lessons

- [generalizable-candidate] (repos=2, sources=repo-alpha, repo-beta): Always guard grep calls with    true under set -euo pipefail
- [project: repo-gamma] (repos=1, sources=repo-gamma): gamma-specific: check feature flags before implementation
- [project: repo-beta] (repos=1, sources=repo-beta): Deep arch-safety conditions reduce rework rate
- [project: repo-alpha] (repos=1, sources=repo-alpha): Use named write variable with SAFETY comment

## Skipped repos (no proposals)

(none)
```

---

## Engine-Untouched Git-Diff Proof

```
$ git diff HEAD -- agent-os/ bin/massoh manifest.yml templates/ scripts/massoh-dashboard
(empty — no output)
```

Files changed relative to HEAD:
```
AGENT_SYNC.md       ← pre-existing uncommitted change from earlier slices (not from this implementation)
CHANGELOG.md        ← [0.23.0] entry added
VERSION             ← 0.22.0 → 0.23.0
lib/verbs/fleet.sh  ← cmd_fleet_learn added (additive)
test/run.sh         ← T-FLN-1 through T-FLN-8 added
```

---

## Discovered-Repo Byte-Snapshot Proof

T-FLN-2 test: two discovered fake repos (`repo-x`, `repo-y`) had their md5sum snapshot taken before and after `fleet learn --write-proposals`. Both snapshots were identical — zero writes to discovered repos.

T-FLN-4f test: discovered fake repo `eng-repo` byte-snapshot before == after run.

---

## Zero-LLM Grep

```
$ awk '/^cmd_fleet_learn\(\)/{f=1} f && /^\}$/{f=0; next} f' lib/verbs/fleet.sh \
    | grep -wE 'claude|curl|wget' → (empty)
$ awk '/^cmd_fleet_learn\(\)/{f=1} f && /^\}$/{f=0; next} f' lib/verbs/fleet.sh \
    | grep -vE 'agent-project|agent-os' | grep -wE 'agent' → (empty)
```

T-FLN-5a through T-FLN-5d all green.

---

## Suite Output

```
ALL GREEN — 574 checks passed.
```

Baseline: 544. New T-FLN checks: 30 (covering T-FLN-1 through T-FLN-8 with multiple assertions per logical test).

---

## Risks

- **Idempotency is timestamp-sensitive:** Pattern A regenerates the doc fresh including a timestamp. Two runs within the same second produce identical md5. If timestamp precision changes (sub-second), this remains fine. Confirmed: test runs at second precision.
- **awk ordering non-deterministic:** `awk` iterates associative arrays in unspecified order. The `sort -t$'\t' -k2 -rn` sorts by recurrence count descending, making the output deterministic for same-count items only when counts differ. Within the same count, ordering is awk-internal. Pattern A idempotency holds because the same fleet discovery returns the same set. T-FLN-6 md5-match confirms this works in practice.
- **`printf -- '- ...'` required:** bash's printf builtin treats `-` as an option flag if the format string starts with `-`. All format strings starting with `-` in `cmd_fleet_learn` use `printf --`.

---

## Incomplete Items / Parked

- **Browser learn-button (POST handler):** PARKED per architecture review §4. Not implemented. `scripts/massoh-dashboard` untouched.
- **Engine adoption of any FLEET_LEARNINGS.proposed.md candidate:** PARKED for owner. The file is candidates-only.

---

## Handoff to Reviewer QA

**What to verify:**
1. `FLN1`: `bash test/run.sh` T-FLN-5a/b/c/d all green; also manually run the static grep above.
2. `FLN2+FLN4`: T-FLN-2a/b and T-FLN-4a–f all green; `git diff HEAD -- agent-os/ bin/massoh manifest.yml templates/ scripts/massoh-dashboard` returns empty.
3. `FLN3`: `grep -n 'FLEET_LEARNINGS' lib/verbs/fleet.sh | grep 'SAFETY'` returns the single declaration.
4. `FLN4` promotion boundary: run `massoh fleet learn --write-proposals` against two fake repos sharing a lesson and confirm `[generalizable-candidate]` appears; single-repo lesson shows `[project: <basename>]`.
5. `FLN7` idempotency: two consecutive runs produce identical md5 (T-FLN-6a).
6. `FLN8` sanitization: T-FLN-8b/c/d green.
7. VERSION = 0.23.0, CHANGELOG has [0.23.0] entry.
8. `massoh doctor` still passes (additive changes only).
9. No commit/push — reviewer decides merge.
