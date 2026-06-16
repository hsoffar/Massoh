#!/usr/bin/env bash
# Massoh CLI tests — POSIX bash, no bats dependency.
# EVERY test runs against a throwaway CLAUDE_CONFIG_DIR + temp git repos. The real ~/.claude is
# NEVER touched. Exercises real paths (Guardrail A5). Exit non-zero if any test fails.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASSOH="$REPO_ROOT/bin/massoh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0; tests=0

ok()   { tests=$((tests+1)); printf '  ok   %s\n' "$1"; }
bad()  { tests=$((tests+1)); fails=$((fails+1)); printf '  FAIL %s\n' "$1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1 [$2]"; fi; }

newcc() { mktemp -d "$TMP/cc.XXXXXX"; }   # throwaway CLAUDE_CONFIG_DIR

echo "== T1: install / status / doctor =="
CC="$(newcc)"
CLAUDE_CONFIG_DIR="$CC" "$MASSOH" install >/dev/null 2>&1
check "install copied agent-os engine"      "[ -d '$CC/agent-os' ]"
check "install copied a massoh-* agent"     "ls '$CC'/agents/massoh-*.md >/dev/null 2>&1"
check "install added global block"          "grep -qF 'massoh:start' '$CC/CLAUDE.md'"
if CLAUDE_CONFIG_DIR="$CC" "$MASSOH" doctor >/dev/null 2>&1; then ok "doctor exits 0 on healthy install"; else bad "doctor exits 0 on healthy install"; fi
# doctor must be READ-ONLY: snapshot the dir, run doctor, assert nothing changed
before="$(cd "$CC" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
CLAUDE_CONFIG_DIR="$CC" "$MASSOH" doctor >/dev/null 2>&1 || true
after="$(cd "$CC" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
check "doctor wrote nothing (read-only)"     "[ '$before' = '$after' ]"
# drift: remove one agent -> doctor must fail non-zero
rm -f "$CC"/agents/massoh-implementer.md
if CLAUDE_CONFIG_DIR="$CC" "$MASSOH" doctor >/dev/null 2>&1; then bad "doctor non-zero on drift"; else ok "doctor non-zero on drift"; fi

echo "== T2: discover =="
PROJ="$TMP/proj"; mkdir -p "$PROJ"; ( cd "$PROJ" && git init -q && git config user.email t@t && git config user.name t )
printf '{ "scripts": { "test": "echo hi" } }\n' > "$PROJ/package.json"
echo "x" > "$PROJ/.massoh"   # mark as Massoh project
( cd "$PROJ" && git add -A && git commit -qm "feat: seed" )
( cd "$PROJ" && "$MASSOH" discover >/dev/null 2>&1 )
check "discover created STANDARDS.md"        "[ -s '$PROJ/agent-project/STANDARDS.md' ]"
check "discover detected JS/TS"              "grep -q 'JavaScript/TypeScript' '$PROJ/agent-project/STANDARDS.md'"
check "discover detected npm test"           "grep -q 'npm test' '$PROJ/agent-project/STANDARDS.md'"
cp "$PROJ/agent-project/STANDARDS.md" "$TMP/std.first"
( cd "$PROJ" && "$MASSOH" discover >/dev/null 2>&1 )
check "discover create-if-missing (no clobber)" "diff -q '$TMP/std.first' '$PROJ/agent-project/STANDARDS.md' >/dev/null"
( cd "$PROJ" && "$MASSOH" discover --force >/dev/null 2>&1 )
check "discover --force refreshes"           "[ -s '$PROJ/agent-project/STANDARDS.md' ]"
NOPROJ="$TMP/noproj"; mkdir -p "$NOPROJ"
if ( cd "$NOPROJ" && "$MASSOH" discover >/dev/null 2>&1 ); then bad "discover refuses outside project"; else ok "discover refuses outside project"; fi

echo "== T3: update preserves dirty local edits (stash->pull->pop) =="
CLONE="$TMP/clone"; git clone -q "$REPO_ROOT" "$CLONE"
( cd "$CLONE" && git config user.email t@t && git config user.name t )
cp "$MASSOH" "$CLONE/bin/massoh"   # test the working-tree (uncommitted) hardened binary
echo "# dirty-marker-$$" >> "$CLONE/README.md"     # uncommitted tracked change
CC3="$(newcc)"
MASSOH_HOME="$CLONE" CLAUDE_CONFIG_DIR="$CC3" "$CLONE/bin/massoh" update >/dev/null 2>&1 || true
check "update kept uncommitted local edit"   "grep -q 'dirty-marker-$$' '$CLONE/README.md'"

echo "== T4: update aborts non-ff cleanly, preserves local commit =="
BARE="$TMP/bare.git"; git clone -q --bare "$REPO_ROOT" "$BARE"
WORK="$TMP/work"; git clone -q "$BARE" "$WORK"; ( cd "$WORK" && git config user.email t@t && git config user.name t )
cp "$MASSOH" "$WORK/bin/massoh"   # test the working-tree hardened binary
ADV="$TMP/adv";  git clone -q "$BARE" "$ADV";  ( cd "$ADV" && git config user.email t@t && git config user.name t )
( cd "$ADV"  && echo a >> README.md && git commit -qam "upstream advance" && git push -q origin HEAD )
( cd "$WORK" && echo b >> README.md && git commit -qam "local-divergent" )
CC4="$(newcc)"
if MASSOH_HOME="$WORK" CLAUDE_CONFIG_DIR="$CC4" "$WORK/bin/massoh" update >/dev/null 2>&1; then
  bad "update non-zero on non-ff pull"
else
  ok "update non-zero on non-ff pull"
fi
check "update preserved local commit"        "git -C '$WORK' log -1 --pretty=%s | grep -q 'local-divergent'"

echo "== T5: regression — on/off + uninstall happy path =="
RP="$TMP/regrepo"; mkdir -p "$RP"; ( cd "$RP" && git init -q )
"$MASSOH" on "$RP" >/dev/null 2>&1
check "on scaffolds agent-project"           "[ -f '$RP/agent-project/CHARTER.md' ]"
check "on writes .massoh marker"             "[ -f '$RP/.massoh' ]"
"$MASSOH" off "$RP" >/dev/null 2>&1
check "off removes marker, keeps files"      "[ ! -f '$RP/.massoh' ] && [ -f '$RP/agent-project/CHARTER.md' ]"
CC5="$(newcc)"; CLAUDE_CONFIG_DIR="$CC5" "$MASSOH" install >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$CC5" "$MASSOH" uninstall >/dev/null 2>&1
check "uninstall removed engine"             "[ ! -d '$CC5/agent-os' ]"
check "uninstall removed agents"             "! ls '$CC5'/agents/massoh-*.md >/dev/null 2>&1"
check "uninstall removed global block"       "! grep -qF 'massoh:start' '$CC5/CLAUDE.md'"

echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN — $tests checks passed."; else echo "$fails/$tests checks FAILED."; fi
[ "$fails" -eq 0 ]
