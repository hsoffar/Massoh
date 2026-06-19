# 05 — Implementation Handoff: TASK-2026-06-19-fix-t6

**Implementer:** massoh-implementer
**Date:** 2026-06-19
**Branch:** feat/fix-t6
**Routed to:** massoh-reviewer-qa

---

## 1. Files changed

`test/run.sh` — the ONLY file modified. `bin/massoh`, `VERSION`, manifests, policies: untouched.

---

## 2. T6 diff (lines 92–114)

### Before (original — network-dependent setup)

```bash
# build a clone that is BEHIND origin/main, with the new binary, then doctor must flag 'update available'
B6="$TMP/bare6.git"; git clone -q --bare "$REPO_ROOT" "$B6"
W6="$TMP/w6"; git clone -q "$B6" "$W6"; ( cd "$W6" && git config user.email t@t && git config user.name t )
cp "$MASSOH" "$W6/bin/massoh"; cp "$REPO_ROOT/VERSION" "$W6/VERSION"   # overlay uncommitted working-tree files
cp -rp "$REPO_ROOT/lib" "$W6/"   # v0.11.0: bin/massoh now sources lib/verbs/; overlay alongside the binary
A6="$TMP/a6"; git clone -q "$B6" "$A6"; ( cd "$A6" && git config user.email t@t && git config user.name t )
( cd "$A6" && git checkout -q main && echo z >> README.md && git commit -qam "advance main" && git push -q origin main )
```

### After (Option A — zero outbound network)

```bash
# build a clone that is BEHIND origin/main, with the new binary, then doctor must flag 'update available'
# Option A: synthetic local bare repo — zero outbound network (FT1, FT5).
# Seed from a plain git init + filesystem copy of REPO_ROOT; never clone REPO_ROOT or touch its remotes.
B6="$TMP/bare6.git"; git -c init.defaultBranch=main init -q --bare "$B6"
S6="$TMP/seed6"; mkdir -p "$S6"
# copy tracked working tree content (exclude .git/) then commit and push to B6 — pure local filesystem
( cd "$REPO_ROOT" && git ls-files ) | while IFS= read -r f; do
  mkdir -p "$S6/$(dirname "$f")" && cp "$REPO_ROOT/$f" "$S6/$f"
done
( cd "$S6" && git -c init.defaultBranch=main init -q \
  && git config user.email t@t && git config user.name t \
  && git add -A \
  && git commit -q -m "seed" \
  && git remote add origin "$B6" \
  && git push -q origin main )
rm -rf "$S6"
# clone bare into W6 (this is the "behind" working tree — W6 is one commit behind after A6 advances)
W6="$TMP/w6"; git clone -q "$B6" "$W6"; ( cd "$W6" && git config user.email t@t && git config user.name t )
cp "$MASSOH" "$W6/bin/massoh"; cp "$REPO_ROOT/VERSION" "$W6/VERSION"   # overlay uncommitted working-tree files
cp -rp "$REPO_ROOT/lib" "$W6/"   # v0.11.0: bin/massoh now sources lib/verbs/; overlay alongside the binary
# advance origin/main via a second clone so W6 is behind (all local, no network)
A6="$TMP/a6"; git clone -q "$B6" "$A6"; ( cd "$A6" && git config user.email t@t && git config user.name t )
( cd "$A6" && git checkout -q main && echo z >> README.md && git commit -qam "advance main" && git push -q origin main )
```

Key changes:
- `git clone -q --bare "$REPO_ROOT" "$B6"` → `git -c init.defaultBranch=main init -q --bare "$B6"` (no REPO_ROOT clone)
- New seed block (`S6`): `git ls-files` to enumerate tracked files, `cp` each to `$S6`, `git init` + `git push` to prime `$B6` with a real `main` branch — 100% local filesystem
- `rm -rf "$S6"` cleans the temporary seed dir before `$W6` is cloned
- `cp -rp "$REPO_ROOT/lib" "$W6/"` line is kept verbatim (FT3 / arch-safety mandate)
- `A6` advance block unchanged

---

## 3. FT1–FT6 — file:line evidence

| ID | Condition | File:Line | Evidence |
|----|-----------|-----------|---------|
| FT1 | Zero outbound network | test/run.sh:95–107 | `git init --bare` + `git ls-files \| cp` seed; no `git clone REPO_ROOT`; `$B6` is a temp-dir path; doctor fetch targets `$B6` (line 169 bin/massoh) which is a local path |
| FT2 | "update available" grep is live | test/run.sh:119 | `check "doctor flags 'update available'" "echo '$d6' \| grep -q 'update available'"` — real doctor output, not vacuous |
| FT3 | 4 offline-safe assertions intact | test/run.sh:120–123 | bogus remote set-url (120), `--offline` run (121–122), exit-0 check (122), no-update check (123) — all preserved verbatim; `cp -rp "$REPO_ROOT/lib" "$W6/"` on line 111 kept verbatim |
| FT4 | Total check count = 463 | test/run.sh (whole file) | Both test runs output `ALL GREEN — 463 checks passed.` |
| FT5 | Setup vars isolated to `$TMP`, no cross-test state | test/run.sh:95,96,108,113 | `B6=$TMP/bare6.git`, `S6=$TMP/seed6`, `W6=$TMP/w6`, `A6=$TMP/a6` — all under `$TMP`; `trap 'rm -rf "$TMP"' EXIT` on line 10 covers cleanup; no other test section reads these vars |
| FT6 | CI green end-to-end | test/run.sh (full run) | `ALL GREEN — 463 checks passed.` in both normal and network-blocked runs |

---

## 4. Test runs

### Run 1 — normal (with network)

Command: `bash test/run.sh`

Result (last 3 lines):
```
  ok   T-SR-11 full suite green (enforced by harness exit code)

ALL GREEN — 463 checks passed.
```

T6 section:
```
== T6: version + doctor update-check ==
  ok   version prints semver
  ok   install wrote VERSION into engine
  ok   doctor exit 0 even when behind
  ok   doctor flags 'update available'
  ok   doctor --offline exit 0 (no network)
  ok   doctor --offline skips update-check
  ok   uninstall removed VERSION
```

### Run 2 — network-blocked (offline determinism proof)

Command: `FAKE_GITCONFIG=$(mktemp) && printf '[http]\n\tproxy = http://127.0.0.1:9\n[https]\n\tproxy = https://127.0.0.1:9\n[core]\n\tsshCommand = false\n' > "$FAKE_GITCONFIG" && GIT_CONFIG_GLOBAL="$FAKE_GITCONFIG" GIT_TERMINAL_PROMPT=0 bash test/run.sh`

(Proxy port 9 is an unroutable discard port; SSH command set to `false`; `GIT_TERMINAL_PROMPT=0` suppresses auth prompts. Any real outbound git fetch would fail or timeout immediately.)

T6 section (network blocked):
```
== T6: version + doctor update-check ==
  ok   version prints semver
  ok   install wrote VERSION into engine
  ok   doctor exit 0 even when behind
  ok   doctor flags 'update available'
  ok   doctor --offline exit 0 (no network)
  ok   doctor --offline skips update-check
  ok   uninstall removed VERSION
```

Final count (network blocked):
```
ALL GREEN — 463 checks passed.
```

Offline-determinism: PROVEN. T6 passes identically with all outbound HTTP/SSH git operations blocked.

---

## 5. Risks

- Low. Test-only change. `bin/massoh` untouched.
- The `git ls-files` seed copies only git-tracked files, so any untracked file needed by the test
  (there are none — the `cp "$MASSOH"` and `cp -rp lib` overlays cover uncommitted working-tree
  files) would be absent. This is identical to what a `git clone` would produce.
- `rm -rf "$S6"` cleanup of the seed dir happens before `$W6` clone; `$S6` is under `$TMP` so
  the `trap` also covers it on abnormal exit.
- `init.defaultBranch=main` is passed via `-c` (inline, no global config mutation) so there is no
  risk of polluting the test runner's git config.

---

## 6. Incomplete items

None. All FT1–FT6 satisfied. No deviations from approved scope.

---

## 7. Handoff to massoh-reviewer-qa

**Task:** Review the T6 fix in `test/run.sh` (lines 92–114) against FT1–FT6.

**Branch:** `feat/fix-t6`

**Checklist for reviewer:**
- [ ] Confirm `bin/massoh`, `VERSION`, `manifest.yml`, policies, lib/verbs/* are unmodified
- [ ] Confirm `test/run.sh` diff is limited to T6 setup block (lines 92–114)
- [ ] Confirm `cp -rp "$REPO_ROOT/lib" "$W6/"` line is verbatim (line 111)
- [ ] Confirm the 4 offline-safe assertions (lines 120–123) are verbatim
- [ ] Run `bash test/run.sh` → `ALL GREEN — 463 checks passed.`
- [ ] Run with `GIT_CONFIG_GLOBAL` proxy block → `ALL GREEN — 463 checks passed.`
- [ ] FT1: no REPO_ROOT clone in T6 setup (grep for `clone.*REPO_ROOT` in T6 block)
- [ ] FT2: `grep -q 'update available'` assertion still live (line 119)
- [ ] FT4: check count exactly 463
- [ ] FT5: all T6 vars use `$TMP/...` prefix
- [ ] Approve for auto-merge on green (test-only; no safety-critical files; no owner sign-off required per 03)
