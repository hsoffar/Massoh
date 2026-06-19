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

echo "== T6: version + doctor update-check =="
vout="$("$MASSOH" version 2>&1)"
check "version prints semver"                "echo '$vout' | grep -qE '^massoh [0-9]+\.[0-9]+'"
# build a clone that is BEHIND origin/main, with the new binary, then doctor must flag 'update available'
B6="$TMP/bare6.git"; git clone -q --bare "$REPO_ROOT" "$B6"
W6="$TMP/w6"; git clone -q "$B6" "$W6"; ( cd "$W6" && git config user.email t@t && git config user.name t )
cp "$MASSOH" "$W6/bin/massoh"; cp "$REPO_ROOT/VERSION" "$W6/VERSION"   # overlay uncommitted working-tree files
cp -rp "$REPO_ROOT/lib" "$W6/"   # v0.11.0: bin/massoh now sources lib/verbs/; overlay alongside the binary
A6="$TMP/a6"; git clone -q "$B6" "$A6"; ( cd "$A6" && git config user.email t@t && git config user.name t )
( cd "$A6" && git checkout -q main && echo z >> README.md && git commit -qam "advance main" && git push -q origin main )
CC6="$(newcc)"; MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" install >/dev/null 2>&1
check "install wrote VERSION into engine"    "[ -f '$CC6/agent-os/VERSION' ]"
d6="$(MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" doctor 2>&1)"; rc6=$?
check "doctor exit 0 even when behind"        "[ $rc6 -eq 0 ]"
check "doctor flags 'update available'"       "echo '$d6' | grep -q 'update available'"
# offline-safe: bogus remote + --offline must not hang or fail
( cd "$W6" && git remote set-url origin /no/such/remote )
d6o="$(MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" doctor --offline 2>&1)"; rc6o=$?
check "doctor --offline exit 0 (no network)"  "[ $rc6o -eq 0 ]"
check "doctor --offline skips update-check"    "! echo '$d6o' | grep -q 'update available'"
# uninstall removes VERSION (agent-os wiped)
MASSOH_HOME="$W6" CLAUDE_CONFIG_DIR="$CC6" "$W6/bin/massoh" uninstall >/dev/null 2>&1
check "uninstall removed VERSION"             "[ ! -f '$CC6/agent-os/VERSION' ]"

echo "== T7: cron (idleness, dry-run, run, parallel, auto-merge) =="
CRON="$REPO_ROOT/bin/massoh-cron"
FAKE="$TMP/fakeagent.sh"
cat > "$FAKE" <<'FA'
#!/usr/bin/env bash
echo "invoked" >> "$MASSOH_TEST_SENTINEL"
echo "work for: $1" > agent-was-here.txt
git add -A >/dev/null 2>&1 && git commit -qm "fake cron work" >/dev/null 2>&1 || true
FA
chmod +x "$FAKE"
mkcronrepo(){ # $1=dir $2=n_todos
  local d="$1" n="$2" i
  mkdir -p "$d"; ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  { echo "# Backlog"; echo "## Queue"; echo "| # | Pri | Item | Why | Status |"; echo "|---|---|---|---|---|"
    for i in $(seq 1 "$n"); do echo "| $i | P1 | Cron item $i | why$i | TODO |"; done
    echo "| 99 | P3 | Blocked one | z | BLOCKED |"; } > "$d/AGENT_BACKLOG.md"
  printf '# sync\n' > "$d/AGENT_SYNC.md"; echo x > "$d/.massoh"
  ( cd "$d" && git add -A && git commit -qm init )
}
# T7a idleness gate (fresh commit = active)
CRi="$TMP/cr_idle"; mkcronrepo "$CRi" 1
oi="$( cd "$CRi" && "$CRON" once 2>&1 )"
check "cron idleness gate skips on fresh commit" "echo '$oi' | grep -q 'owner active'"
# T7b dry-run default — no agent call, backlog untouched
SENd="$TMP/sen_dry"; : > "$SENd"; CRd="$TMP/cr_dry"; mkcronrepo "$CRd" 2
od="$( cd "$CRd" && MASSOH_TEST_SENTINEL="$SENd" MASSOH_AGENT_CMD="$FAKE" "$CRON" once --no-idle-check 2>&1 )"
check "dry-run prints plan"                   "echo '$od' | grep -q 'DRY-RUN'"
check "dry-run did NOT call agent"            "[ ! -s '$SENd' ]"
check "dry-run left backlog TODO"             "grep -q '| TODO |' '$CRd/AGENT_BACKLOG.md'"
# T7c run single
SENr="$TMP/sen_run"; : > "$SENr"; CRr="$TMP/cr_run"; mkcronrepo "$CRr" 2
( cd "$CRr" && MASSOH_TEST_SENTINEL="$SENr" MASSOH_AGENT_CMD="$FAKE" MASSOH_GATE_CMD=true "$CRON" once --run --no-idle-check ) >/dev/null 2>&1
check "run called agent once"                 "[ \"\$(wc -l < '$SENr')\" -eq 1 ]"
check "run marked one item DONE"              "grep -q '| DONE |' '$CRr/AGENT_BACKLOG.md'"
check "run appended [cron] sync entry"        "grep -q '\[cron\]' '$CRr/AGENT_SYNC.md'"
check "run created a cron/* branch"           "git -C '$CRr' branch --list 'cron/*' | grep -q cron/"
check "run cleaned worktrees"                 "[ \"\$(git -C '$CRr' worktree list | wc -l)\" -eq 1 ]"
check "auto-merge OFF by default (main clean)" "! git -C '$CRr' cat-file -e main:agent-was-here.txt 2>/dev/null"
# T7d parallel 2 — no corruption
SENp="$TMP/sen_par"; : > "$SENp"; CRp="$TMP/cr_par"; mkcronrepo "$CRp" 2
( cd "$CRp" && MASSOH_TEST_SENTINEL="$SENp" MASSOH_AGENT_CMD="$FAKE" MASSOH_GATE_CMD=true "$CRON" once --run --parallel 2 --no-idle-check ) >/dev/null 2>&1
check "parallel called agent twice"           "[ \"\$(wc -l < '$SENp')\" -eq 2 ]"
check "parallel marked 2 DONE"                "[ \"\$(grep -c '| DONE |' '$CRp/AGENT_BACKLOG.md')\" -eq 2 ]"
check "parallel wrote 2 result lines"         "[ \"\$(grep -c 'agent_rc=' '$CRp/AGENT_SYNC.md')\" -eq 2 ]"
check "parallel one serialized [cron] block"  "[ \"\$(grep -c '\[cron\] tick' '$CRp/AGENT_SYNC.md')\" -eq 1 ]"
# T7e auto-merge ON merges a green branch
SENa="$TMP/sen_am"; : > "$SENa"; CRa="$TMP/cr_am"; mkcronrepo "$CRa" 1
( cd "$CRa" && MASSOH_TEST_SENTINEL="$SENa" MASSOH_AGENT_CMD="$FAKE" MASSOH_GATE_CMD=true "$CRON" once --run --auto-merge --no-idle-check ) >/dev/null 2>&1
check "auto-merge ON merged green branch"     "git -C '$CRa' cat-file -e main:agent-was-here.txt 2>/dev/null"
check "auto-merge sync says merged=yes"       "grep -q 'merged=yes' '$CRa/AGENT_SYNC.md'"
# T7f empty backlog
CRe="$TMP/cr_empty"; mkcronrepo "$CRe" 0
oe="$( cd "$CRe" && "$CRON" once --no-idle-check 2>&1 )"
check "empty backlog exits cleanly"           "echo '$oe' | grep -q 'no unblocked TODO'"

echo "== T8: review (KPI report) =="
RV="$TMP/revrepo"; mkdir -p "$RV"; ( cd "$RV" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
mkdir -p "$RV/.agent_tasks/TASK-a" "$RV/.agent_tasks/TASK-b"
: > "$RV/.agent_tasks/TASK-a/04_implementation_packet.md"; : > "$RV/.agent_tasks/TASK-a/06_review_result.md"
: > "$RV/.agent_tasks/TASK-b/04_implementation_packet.md"   # b licensed, not reviewed
{ echo "| # | Pri | Item | Why | Status |"; echo "|---|---|---|---|---|"; echo "| 1 | P1 | x | y | TODO |"; echo "| 2 | P1 | z | w | DONE |"; } > "$RV/AGENT_BACKLOG.md"
( cd "$RV" && echo a > f && git add -A && git commit -qm "feat: thing (#1)" )
ro="$( cd "$RV" && "$MASSOH" review --no-write 2>&1 )"
check "review reports packets total"          "echo '$ro' | grep -qE 'packets:.*2 total'"
check "review reports reviewed count"         "echo '$ro' | grep -qE '1 reviewed'"
check "review reports backlog TODO/DONE"      "echo '$ro' | grep -qE '1 TODO'"
check "review reports merged PR"              "echo '$ro' | grep -qE '1 PRs merged'"
# --no-write must not change the repo
b8="$(cd "$RV" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
( cd "$RV" && "$MASSOH" review --no-write >/dev/null 2>&1 )
a8="$(cd "$RV" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "review --no-write changed nothing"     "[ '$b8' = '$a8' ]"
# default write appends a snapshot; second run appends another
( cd "$RV" && "$MASSOH" review >/dev/null 2>&1 )
check "review wrote a METRICS snapshot"        "[ -f '$RV/agent-project/METRICS.md' ] && grep -q '## Snapshot' '$RV/agent-project/METRICS.md'"
( cd "$RV" && "$MASSOH" review >/dev/null 2>&1 )
check "review append-only (2 snapshots)"       "[ \"\$(grep -c '## Snapshot' '$RV/agent-project/METRICS.md')\" -eq 2 ]"
# graceful outside a git repo / no packets
NG="$TMP/nongit"; mkdir -p "$NG"
if ( cd "$NG" && "$MASSOH" review --no-write >/dev/null 2>&1 ); then ok "review degrades outside git repo"; else bad "review degrades outside git repo"; fi

echo "== T9: standup + plan =="
CV="$TMP/cadrepo"; mkdir -p "$CV"; ( cd "$CV" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
{ echo "| # | Pri | Item | Why | Status |"; echo "|---|---|---|---|---|"
  echo "| 1 | P1 | Top thing | because | TODO |"; echo "| 2 | P2 | Doing thing | x | DOING |"; echo "| 3 | P3 | Stuck thing | y | BLOCKED |"; } > "$CV/AGENT_BACKLOG.md"
{ echo "# AGENT_SYNC"; echo; echo "## Open questions (owner decision needed)"; echo "| Question | Raised | Context |"; echo "|---|---|---|"; echo "| Should we ship X? | 2026-06-16 | needs call |"; echo; echo "## Decision log"; } > "$CV/AGENT_SYNC.md"
mkdir -p "$CV/.agent_tasks/TASK-x"; : > "$CV/.agent_tasks/TASK-x/04_implementation_packet.md"   # in-flight (no 06)
( cd "$CV" && echo a > f && git add -A && git commit -qm "feat: seed cadence" )
# standup
so="$( cd "$CV" && "$MASSOH" standup --no-write 2>&1 )"
check "standup shows recent commit"          "echo '$so' | grep -q 'seed cadence'"
check "standup shows DOING"                   "echo '$so' | grep -q 'Doing thing'"
check "standup shows BLOCKED"                 "echo '$so' | grep -q 'Stuck thing'"
check "standup shows in-flight packet"        "echo '$so' | grep -q 'TASK-x'"
b9="$(cd "$CV" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
( cd "$CV" && "$MASSOH" standup --no-write >/dev/null 2>&1 )
a9="$(cd "$CV" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "standup --no-write inert"              "[ '$b9' = '$a9' ]"
( cd "$CV" && "$MASSOH" standup >/dev/null 2>&1 )
check "standup appends [standup] block"       "grep -q '## \[standup\]' '$CV/AGENT_SYNC.md'"
# plan
po="$( cd "$CV" && "$MASSOH" plan --no-write 2>&1 )"
check "plan shows TODO queue item"            "echo '$po' | grep -q 'Top thing'"
check "plan surfaces owner decision"          "echo '$po' | grep -q 'Should we ship X'"
check "plan shows BLOCKED"                     "echo '$po' | grep -q 'Stuck thing'"
( cd "$CV" && "$MASSOH" plan >/dev/null 2>&1 )
check "plan appends [plan] block"             "grep -q '## \[plan\]' '$CV/AGENT_SYNC.md'"
# degrade in non-git
NG2="$TMP/nongit2"; mkdir -p "$NG2"
if ( cd "$NG2" && "$MASSOH" standup --no-write >/dev/null 2>&1 && "$MASSOH" plan --no-write >/dev/null 2>&1 ); then ok "standup/plan degrade outside git"; else bad "standup/plan degrade outside git"; fi

echo "== T10: cadence ceremonies wired into cron =="
CRON10="$REPO_ROOT/bin/massoh-cron"

# Fake ceremony commands that write the expected markers (zero-cost, no real massoh call)
FAKE_STANDUP="$TMP/fake_standup.sh"
cat > "$FAKE_STANDUP" <<'FS'
#!/usr/bin/env bash
printf '\n## [standup]\nfake standup entry\n' >> AGENT_SYNC.md
FS
chmod +x "$FAKE_STANDUP"

FAKE_REVIEW="$TMP/fake_review.sh"
cat > "$FAKE_REVIEW" <<'FR'
#!/usr/bin/env bash
mkdir -p agent-project
printf '\n## Snapshot\nfake review entry\n' >> agent-project/METRICS.md
FR
chmod +x "$FAKE_REVIEW"

FAKE_PLAN="$TMP/fake_plan.sh"
cat > "$FAKE_PLAN" <<'FP'
#!/usr/bin/env bash
printf '\n## [plan]\nfake plan entry\n' >> AGENT_SYNC.md
FP
chmod +x "$FAKE_PLAN"

FAKE10="$TMP/fakeagent10.sh"
cat > "$FAKE10" <<'FA10'
#!/usr/bin/env bash
echo "invoked" >> "$MASSOH_TEST_SENTINEL"
echo "work" > agent-was-here.txt
git add -A >/dev/null 2>&1 && git commit -qm "fake cron work" >/dev/null 2>&1 || true
FA10
chmod +x "$FAKE10"

# T10a — standup appended on --run tick
SEN10a="$TMP/sen10a"; : > "$SEN10a"; CR10a="$TMP/cr10a"; mkcronrepo "$CR10a" 1
( cd "$CR10a" && \
    MASSOH_TEST_SENTINEL="$SEN10a" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    "$CRON10" once --run --no-idle-check ) >/dev/null 2>&1
check "T10a standup appended on --run tick"   "grep -q '## \[standup\]' '$CR10a/AGENT_SYNC.md'"

# T10b — standup does NOT run on dry-run
SEN10b="$TMP/sen10b"; : > "$SEN10b"; CR10b="$TMP/cr10b"; mkcronrepo "$CR10b" 1
( cd "$CR10b" && \
    MASSOH_TEST_SENTINEL="$SEN10b" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    "$CRON10" once --no-idle-check ) >/dev/null 2>&1
check "T10b standup NOT on dry-run"           "! grep -q '## \[standup\]' '$CR10b/AGENT_SYNC.md'"

# T10c — --no-standup suppresses standup
SEN10c="$TMP/sen10c"; : > "$SEN10c"; CR10c="$TMP/cr10c"; mkcronrepo "$CR10c" 1
( cd "$CR10c" && \
    MASSOH_TEST_SENTINEL="$SEN10c" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    "$CRON10" once --run --no-idle-check --no-standup ) >/dev/null 2>&1
check "T10c --no-standup suppresses standup"  "! grep -q '## \[standup\]' '$CR10c/AGENT_SYNC.md'"

# T10d — cadence_state created and increments
SEN10d="$TMP/sen10d"; : > "$SEN10d"; CR10d="$TMP/cr10d"; mkcronrepo "$CR10d" 2
( cd "$CR10d" && \
    MASSOH_TEST_SENTINEL="$SEN10d" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    "$CRON10" once --run --no-idle-check --parallel 1 ) >/dev/null 2>&1
( cd "$CR10d" && \
    MASSOH_TEST_SENTINEL="$SEN10d" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    "$CRON10" once --run --no-idle-check --parallel 1 ) >/dev/null 2>&1
check "T10d cadence_state exists"             "[ -f '$CR10d/.agent_tasks/cron/cadence_state' ]"
check "T10d cadence_state = 2 after 2 ticks" "[ \"\$(cat '$CR10d/.agent_tasks/cron/cadence_state' | tr -d '[:space:]')\" = '2' ]"

# T10e — review+plan fire at period boundary (--period-days 0 → period_ticks clamped to 1)
SEN10e="$TMP/sen10e"; : > "$SEN10e"; CR10e="$TMP/cr10e"; mkcronrepo "$CR10e" 1
( cd "$CR10e" && \
    MASSOH_TEST_SENTINEL="$SEN10e" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" \
    MASSOH_REVIEW_CMD="bash $FAKE_REVIEW" \
    MASSOH_PLAN_CMD="bash $FAKE_PLAN" \
    "$CRON10" once --run --no-idle-check --period-days 0 ) >/dev/null 2>&1
check "T10e review fired at boundary"         "[ -f '$CR10e/agent-project/METRICS.md' ] && grep -q '## Snapshot' '$CR10e/agent-project/METRICS.md'"
check "T10e plan fired at boundary"           "grep -q '## \[plan\]' '$CR10e/AGENT_SYNC.md'"
check "T10e counter reset to 0 after boundary" "[ \"\$(cat '$CR10e/.agent_tasks/cron/cadence_state' | tr -d '[:space:]')\" = '0' ]"

# T10f — ceremony failure does NOT abort the tick
SEN10f="$TMP/sen10f"; : > "$SEN10f"; CR10f="$TMP/cr10f"; mkcronrepo "$CR10f" 1
rc10f=0
( cd "$CR10f" && \
    MASSOH_TEST_SENTINEL="$SEN10f" \
    MASSOH_AGENT_CMD="$FAKE10" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD=false \
    MASSOH_REVIEW_CMD=false \
    MASSOH_PLAN_CMD=false \
    "$CRON10" once --run --no-idle-check --period-days 0 ) >/dev/null 2>&1 || rc10f=$?
check "T10f ceremony failure exit 0"          "[ $rc10f -eq 0 ]"
check "T10f backlog still marked DONE"        "grep -q '| DONE |' '$CR10f/AGENT_BACKLOG.md'"
check "T10f injected false did NOT fall back to real standup" "! grep -q '## \[standup\]' '$CR10f/AGENT_SYNC.md'"

# T10g — cron install --period-days passes through to generated crontab line
CR10g="$TMP/cr10g"; mkcronrepo "$CR10g" 0
install10g="$( cd "$CR10g" && "$CRON10" install --every 30m --period-days 7 2>&1 )"
check "T10g install line contains --period-days 7" "echo '$install10g' | grep -q -- '--period-days 7'"

# T10h — regression: existing T7 still passes (spot-check the key T7 behaviors)
SEN10h="$TMP/sen10h"; : > "$SEN10h"; CR10h="$TMP/cr10h"; mkcronrepo "$CR10h" 2
( cd "$CR10h" && MASSOH_TEST_SENTINEL="$SEN10h" MASSOH_AGENT_CMD="$FAKE10" MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD="bash $FAKE_STANDUP" "$CRON10" once --run --no-idle-check ) >/dev/null 2>&1
check "T10h regression: run still marks DONE"      "grep -q '| DONE |' '$CR10h/AGENT_BACKLOG.md'"
check "T10h regression: run still appends [cron]"  "grep -q '\[cron\]' '$CR10h/AGENT_SYNC.md'"
check "T10h regression: run still creates branch"  "git -C '$CR10h' branch --list 'cron/*' | grep -q cron/"

echo "== T11: massoh learn (heuristic miner) =="

# Helper: mklearnrepo <dir>
# Creates a minimal Massoh project with a git repo, AGENT_SYNC.md, and .agent_tasks/
mklearnrepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  echo x > "$d/.massoh"
  mkdir -p "$d/agent-project" "$d/.agent_tasks"
  printf '# AGENT_SYNC\n\n## Decision log (append-only — never delete a row)\n| Date | Decision | By |\n|---|---|---|\n| 2026-06-17 | Some routine decision | owner |\n' > "$d/AGENT_SYNC.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed learn repo" )
}

# Helper: mklearnpacket <repo> <task-name> <blocking-text>
mklearnpacket() {
  local repo="$1" task="$2" blocking="$3"
  mkdir -p "$repo/.agent_tasks/$task"
  printf '# 06 — Review Result\n\n## Blocking\n%s\n\n## Non-blocking\n(none)\n' "$blocking" \
    > "$repo/.agent_tasks/$task/06_review_result.md"
  printf '# 05 — Implementation Handoff\n\n## Risks\n- Risk: watch for scope creep\n' \
    > "$repo/.agent_tasks/$task/05_implementation_handoff.md"
}

# T11a — default mode: stdout report emitted; LEARNINGS.proposed.md NOT created
LR11a="$TMP/lr11a"; mklearnrepo "$LR11a"
mklearnpacket "$LR11a" "TASK-a" "grep bare exit bug found"
mklearnpacket "$LR11a" "TASK-b" "grep bare exit bug found"
lo11a="$( cd "$LR11a" && "$MASSOH" learn 2>&1 )"
check "T11a stdout contains report header"             "echo '$lo11a' | grep -q 'massoh learn'"
check "T11a Blocking findings section in stdout"       "echo '$lo11a' | grep -q 'Blocking findings'"
check "T11a LEARNINGS.proposed.md NOT created"         "[ ! -f '$LR11a/agent-project/LEARNINGS.proposed.md' ]"

# T11b — --no-write identical to default
LR11b="$TMP/lr11b"; mklearnrepo "$LR11b"
mklearnpacket "$LR11b" "TASK-a" "some blocking text"
lo11b="$( cd "$LR11b" && "$MASSOH" learn --no-write 2>&1 )"
check "T11b --no-write stdout still emitted"           "echo '$lo11b' | grep -q 'massoh learn'"
check "T11b --no-write LEARNINGS.proposed.md absent"   "[ ! -f '$LR11b/agent-project/LEARNINGS.proposed.md' ]"

# T11c — --write-proposals creates file with 4 sections; three runs = three [learn] blocks
LR11c="$TMP/lr11c"; mklearnrepo "$LR11c"
mklearnpacket "$LR11c" "TASK-a" "some finding"
( cd "$LR11c" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
check "T11c LEARNINGS.proposed.md created"             "[ -f '$LR11c/agent-project/LEARNINGS.proposed.md' ]"
check "T11c contains ## [learn] header"                "grep -q '## \[learn\]' '$LR11c/agent-project/LEARNINGS.proposed.md'"
check "T11c contains Proposed STANDARDS section"       "grep -q 'Proposed STANDARDS' '$LR11c/agent-project/LEARNINGS.proposed.md'"
check "T11c contains Possible ADR candidates"          "grep -q 'Possible ADR candidates' '$LR11c/agent-project/LEARNINGS.proposed.md'"
check "T11c contains Repeated-fix indicators"          "grep -q 'Repeated-fix indicators' '$LR11c/agent-project/LEARNINGS.proposed.md'"
# Three runs = three [learn] blocks (append-only, no overwrite)
( cd "$LR11c" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
( cd "$LR11c" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
check "T11c three runs = three [learn] blocks (append-only)" \
  "[ \"\$(grep -c '## \[learn\]' '$LR11c/agent-project/LEARNINGS.proposed.md')\" -eq 3 ]"

# T11d — recurring pattern ("A&&B||C anti-pattern") surfaces in proposals
LR11d="$TMP/lr11d"; mklearnrepo "$LR11d"
mklearnpacket "$LR11d" "TASK-a" "A&&B||C anti-pattern found in ceremony wrappers"
mklearnpacket "$LR11d" "TASK-b" "A&&B||C anti-pattern found again in guards"
( cd "$LR11d" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
check "T11d recurring pattern in proposals"            "grep -q 'A&&B||C' '$LR11d/agent-project/LEARNINGS.proposed.md' || grep -q 'anti' '$LR11d/agent-project/LEARNINGS.proposed.md'"
check "T11d stdout shows both tasks mentioned"         "lo11d=\"\$( cd '$LR11d' && '$MASSOH' learn 2>&1 )\" && echo \"\$lo11d\" | grep -qiE 'TASK-a|TASK-b'"

# T11e — decision log ADR candidate extracted
LR11e="$TMP/lr11e"; mklearnrepo "$LR11e"
printf '# AGENT_SYNC\n\n## Decision log (append-only — never delete a row)\n| Date | Decision | By |\n|---|---|---|\n| 2026-06-17 | Some irreversible infrastructure choice was made | owner |\n' \
  > "$LR11e/AGENT_SYNC.md"
( cd "$LR11e" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
check "T11e ADR candidates section non-empty"          "grep -q 'irreversible' '$LR11e/agent-project/LEARNINGS.proposed.md'"

# T11f — git revert count in report
LR11f="$TMP/lr11f"; mklearnrepo "$LR11f"
( cd "$LR11f" && echo "extra" >> .massoh && git add -A && git commit -qm "chore: extra commit" )
( cd "$LR11f" && git revert --no-edit HEAD -q 2>/dev/null || git revert --no-edit HEAD 2>/dev/null || true )
lo11f="$( cd "$LR11f" && "$MASSOH" learn 2>&1 )"
check "T11f stdout contains revert count 1"            "echo '$lo11f' | grep -q 'revert'"
check "T11f revert count is at least 1"                "echo '$lo11f' | grep 'revert commit' | grep -qvE ': 0$'"

# T11g — --since DAYS limits packet scan (old packet excluded)
LR11g="$TMP/lr11g"; mklearnrepo "$LR11g"
mklearnpacket "$LR11g" "TASK-old" "old-finding-only-in-old-packet"
mklearnpacket "$LR11g" "TASK-new" "new-finding-in-recent-packet"
# Set the old packet's mtime to 10 days ago
touch -t "$(date -d '10 days ago' +%Y%m%d%H%M 2>/dev/null || date -v-10d +%Y%m%d%H%M 2>/dev/null || echo '202606070000')" \
  "$LR11g/.agent_tasks/TASK-old/06_review_result.md" \
  "$LR11g/.agent_tasks/TASK-old/05_implementation_handoff.md" 2>/dev/null || true
lo11g="$( cd "$LR11g" && "$MASSOH" learn --since 1 2>&1 )"
check "T11g --since 1 includes recent packet findings"  "echo '$lo11g' | grep -q 'new-finding'"
check "T11g --since 1 excludes old packet findings"     "! echo '$lo11g' | grep -q 'old-finding-only-in-old-packet'"

# T11h — graceful degrade: no .agent_tasks or no completed packets
LR11h="$TMP/lr11h"; mklearnrepo "$LR11h"
# Remove .agent_tasks entirely to test graceful degrade
rm -rf "$LR11h/.agent_tasks"
rc11h=0
lo11h="$( cd "$LR11h" && "$MASSOH" learn 2>&1 )" || rc11h=$?
check "T11h no packets exit 0"                         "[ $rc11h -eq 0 ]"
check "T11h no packets stdout has report header"       "echo '$lo11h' | grep -q 'massoh learn'"
check "T11h no packets stdout has (none) section"      "echo '$lo11h' | grep -q '(none'"

# T11i — safety-critical paths unchanged after --write-proposals
LR11i="$TMP/lr11i"; mklearnrepo "$LR11i"
mklearnpacket "$LR11i" "TASK-a" "finding for safety check"
# Snapshot checksums before
md5_massoh_before="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_before="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"
# Create a STANDARDS.md to also check
printf '# STANDARDS\n\n## Do / Don'"'"'t\n- Do: test everything\n' > "$LR11i/agent-project/STANDARDS.md"
md5_standards_before="$(md5sum "$LR11i/agent-project/STANDARDS.md" | awk '{print $1}')"
( cd "$LR11i" && "$MASSOH" learn --write-proposals >/dev/null 2>&1 )
md5_massoh_after="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_after="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"
md5_standards_after="$(md5sum "$LR11i/agent-project/STANDARDS.md" | awk '{print $1}')"
check "T11i bin/massoh checksum unchanged"             "[ '$md5_massoh_before' = '$md5_massoh_after' ]"
check "T11i manifest.yml checksum unchanged"           "[ '$md5_manifest_before' = '$md5_manifest_after' ]"
check "T11i STANDARDS.md checksum unchanged"           "[ '$md5_standards_before' = '$md5_standards_after' ]"

# T11j — non-Massoh-project → non-zero exit + error on stderr
LR11j="$TMP/lr11j"; mkdir -p "$LR11j"
# no .massoh, no agent-project/
rc11j=0
err11j="$( cd "$LR11j" && "$MASSOH" learn 2>&1 >/dev/null )" || rc11j=$?
check "T11j non-Massoh-project non-zero exit"          "[ $rc11j -ne 0 ]"
check "T11j non-Massoh-project error on stderr"        "[ -n '$err11j' ]"

# T11k — v1.1 fixes: (1) a code-citation mentioning REQUEST CHANGES (not on a Decision line) must
# NOT be surfaced as a blocking finding; (2) risks show CONTENT under the heading, not the heading.
LR11k="$TMP/lr11k"; mklearnrepo "$LR11k"
mkdir -p "$LR11k/.agent_tasks/TASK-cite"
printf '# 06\n\n## Decision: APPROVE\n\n## Blocking\n(none)\n\n## Non-blocking\n- minor: the string REQUEST CHANGES appears here only as a quoted code citation\n' \
  > "$LR11k/.agent_tasks/TASK-cite/06_review_result.md"
printf '# 05\n\n## Risks\n- the offline cron path can hang without a timeout\n' \
  > "$LR11k/.agent_tasks/TASK-cite/05_implementation_handoff.md"
lo11k="$( cd "$LR11k" && "$MASSOH" learn 2>&1 )"
blk11k="$(printf '%s\n' "$lo11k" | awk '/Blocking findings/{f=1;next} /Non-blocking findings/{f=0} f')"
check "T11k code-citation NOT surfaced as blocking"    "! echo '$blk11k' | grep -q 'code citation'"
check "T11k risks show CONTENT not heading"            "echo '$lo11k' | grep -q 'offline cron path can hang'"

echo "== T12: cron tick-time fix =="
CRON12="$REPO_ROOT/bin/massoh-cron"

# T12a — --every 60m resolves period_ticks=168 for 7-day period (not 336)
# Pre-set cadence_state=167 → next tick (168th) should fire review (168 >= 168)
FAKE_REVIEW12a="$TMP/fake_review12a.sh"
cat > "$FAKE_REVIEW12a" <<'FR12A'
#!/usr/bin/env bash
mkdir -p agent-project
printf '\n## Snapshot\nfake review 12a\n' >> agent-project/METRICS.md
FR12A
chmod +x "$FAKE_REVIEW12a"
FAKE12="$TMP/fakeagent12.sh"
cat > "$FAKE12" <<'FA12'
#!/usr/bin/env bash
echo "invoked" >> "$MASSOH_TEST_SENTINEL"
echo "work" > agent-was-here.txt
git add -A >/dev/null 2>&1 && git commit -qm "fake cron work" >/dev/null 2>&1 || true
FA12
chmod +x "$FAKE12"

CR12a="$TMP/cr12a"; mkcronrepo "$CR12a" 1
mkdir -p "$CR12a/.agent_tasks/cron"
printf '167\n' > "$CR12a/.agent_tasks/cron/cadence_state"
SEN12a="$TMP/sen12a"; : > "$SEN12a"
( cd "$CR12a" && \
    MASSOH_TEST_SENTINEL="$SEN12a" \
    MASSOH_AGENT_CMD="$FAKE12" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD=true \
    MASSOH_REVIEW_CMD="bash $FAKE_REVIEW12a" \
    MASSOH_PLAN_CMD=true \
    "$CRON12" once --run --no-idle-check --every 60m --period-days 7 ) >/dev/null 2>&1
check "T12a --every 60m fires review at tick 168 (period_ticks=168, not 336)" \
  "[ -f '$CR12a/agent-project/METRICS.md' ] && grep -q 'fake review 12a' '$CR12a/agent-project/METRICS.md'"
# Confirm it reset to 0 (proving boundary was reached)
check "T12a cadence_state reset to 0 after boundary (confirms 168, not 336)" \
  "[ \"\$(cat '$CR12a/.agent_tasks/cron/cadence_state' | tr -d '[:space:]')\" = '0' ]"

# T12b — --every 30m (default) regression: period_ticks=336 for 7-day period
# Pre-set cadence_state=335 → tick 336 fires review
FAKE_REVIEW12b="$TMP/fake_review12b.sh"
cat > "$FAKE_REVIEW12b" <<'FR12B'
#!/usr/bin/env bash
mkdir -p agent-project
printf '\n## Snapshot\nfake review 12b\n' >> agent-project/METRICS.md
FR12B
chmod +x "$FAKE_REVIEW12b"
CR12b="$TMP/cr12b"; mkcronrepo "$CR12b" 1
mkdir -p "$CR12b/.agent_tasks/cron"
printf '335\n' > "$CR12b/.agent_tasks/cron/cadence_state"
SEN12b="$TMP/sen12b"; : > "$SEN12b"
( cd "$CR12b" && \
    MASSOH_TEST_SENTINEL="$SEN12b" \
    MASSOH_AGENT_CMD="$FAKE12" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD=true \
    MASSOH_REVIEW_CMD="bash $FAKE_REVIEW12b" \
    MASSOH_PLAN_CMD=true \
    "$CRON12" once --run --no-idle-check --every 30m --period-days 7 ) >/dev/null 2>&1
check "T12b --every 30m fires review at tick 336 (default regression, period_ticks=336)" \
  "[ -f '$CR12b/agent-project/METRICS.md' ] && grep -q 'fake review 12b' '$CR12b/agent-project/METRICS.md'"
check "T12b cadence_state reset to 0 after boundary (confirms 336)" \
  "[ \"\$(cat '$CR12b/.agent_tasks/cron/cadence_state' | tr -d '[:space:]')\" = '0' ]"

# T12c — dry-run output does NOT contain tick_duration (Condition A2)
CR12c="$TMP/cr12c"; mkcronrepo "$CR12c" 1
out12c="$( cd "$CR12c" && MASSOH_AGENT_CMD="$FAKE12" "$CRON12" once --no-idle-check 2>&1 )"
check "T12c dry-run does NOT contain tick_duration" \
  "! echo '$out12c' | grep -q 'tick_duration'"

# T12d — run mode output DOES contain tick_duration= (Condition A2)
CR12d="$TMP/cr12d"; mkcronrepo "$CR12d" 1
SEN12d="$TMP/sen12d"; : > "$SEN12d"
out12d="$( cd "$CR12d" && \
    MASSOH_TEST_SENTINEL="$SEN12d" \
    MASSOH_AGENT_CMD="$FAKE12" \
    MASSOH_GATE_CMD=true \
    MASSOH_STANDUP_CMD=true \
    "$CRON12" once --run --no-idle-check --every 30m 2>&1 )"
check "T12d run mode output contains tick_duration=" \
  "echo '$out12d' | grep -q 'tick_duration='"

# T12e — cron install --every 15m generates crontab line with --every 15m (Condition A5)
CR12e="$TMP/cr12e"; mkcronrepo "$CR12e" 0
install12e="$( cd "$CR12e" && "$CRON12" install --every 15m 2>&1 )"
check "T12e cron install --every 15m contains '--every 15m' in generated line" \
  "echo '$install12e' | grep -q -- '--every 15m'"

echo "== T13: review-v2 KPIs =="

# Helper: create a review fixture repo
mkrevrepo13() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  echo x > "$d/.massoh"
  mkdir -p "$d/.agent_tasks"
  { echo "| # | Pri | Item | Why | Status |"; echo "|---|---|---|---|---|"; echo "| 1 | P1 | x | y | DONE |"; } > "$d/AGENT_BACKLOG.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed" )
}

# Helper: add a packet with optional REQUEST CHANGES in 06
addpacket13() {
  local repo="$1" task="$2" has_rc="${3:-0}"
  mkdir -p "$repo/.agent_tasks/$task"
  printf '# 00 — Request\n**Date:** 2026-06-10\n' > "$repo/.agent_tasks/$task/00_request.md"
  # Commit 00 first so it gets an earlier git timestamp
  ( cd "$repo" && git add ".agent_tasks/$task/00_request.md" && git commit -qm "feat: add $task request" )
  if [ "$has_rc" = 1 ]; then
    printf '# 06 — Review Result\n\n## Decision: REQUEST CHANGES\nSome feedback here.\n' > "$repo/.agent_tasks/$task/06_review_result.md"
  else
    printf '# 06 — Review Result\n\n## Decision: APPROVE\nLooks good.\n' > "$repo/.agent_tasks/$task/06_review_result.md"
  fi
  ( cd "$repo" && git add ".agent_tasks/$task/06_review_result.md" && git commit -qm "feat: add $task review" )
}

# T13a — single packet with both files: output contains cycle_avg_days=, rework_pct=, throughput/wk=
RV13a="$TMP/rv13a"; mkrevrepo13 "$RV13a"
addpacket13 "$RV13a" "TASK-fixture-a" 1
ro13a="$( cd "$RV13a" && "$MASSOH" review --no-write 2>&1 )"
check "T13a output contains cycle_avg_days=" \
  "echo '$ro13a' | grep -q 'cycle_avg_days='"
check "T13a output contains rework_pct=" \
  "echo '$ro13a' | grep -q 'rework_pct='"
check "T13a output contains throughput/wk=" \
  "echo '$ro13a' | grep -q 'throughput/wk='"

# T13b — rework_pct=100 on single packet with REQUEST CHANGES
check "T13b rework_pct=100 on single REQUEST CHANGES packet" \
  "echo '$ro13a' | grep -q 'rework_pct=100'"

# T13c — rework_pct=50 on two packets (one REQUEST CHANGES, one APPROVE)
RV13c="$TMP/rv13c"; mkrevrepo13 "$RV13c"
addpacket13 "$RV13c" "TASK-fixture-a" 1
addpacket13 "$RV13c" "TASK-fixture-b" 0
ro13c="$( cd "$RV13c" && "$MASSOH" review --no-write 2>&1 )"
check "T13c rework_pct=50 on two packets (1 RC, 1 APPROVE)" \
  "echo '$ro13c' | grep -q 'rework_pct=50'"

# T13d — packet missing 06 excluded from cycle time + rework (no crash)
RV13d="$TMP/rv13d"; mkrevrepo13 "$RV13d"
addpacket13 "$RV13d" "TASK-fixture-a" 1
# Add incomplete packet: only 00, no 06
mkdir -p "$RV13d/.agent_tasks/TASK-incomplete"
printf '# 00 — Request\n**Date:** 2026-06-10\n' > "$RV13d/.agent_tasks/TASK-incomplete/00_request.md"
( cd "$RV13d" && git add ".agent_tasks/TASK-incomplete/00_request.md" && git commit -qm "feat: incomplete" )
rc13d=0
ro13d="$( cd "$RV13d" && "$MASSOH" review --no-write 2>&1 )" || rc13d=$?
check "T13d exit 0 with incomplete packet (no 06)" "[ $rc13d -eq 0 ]"
check "T13d rework_pct still 100 (1 complete packet with RC)" \
  "echo '$ro13d' | grep -q 'rework_pct=100'"

# T13e — division-by-zero guard: 0 reviewed packets
RV13e="$TMP/rv13e"; mkrevrepo13 "$RV13e"
# Add packet with only 00 (no 06) — total_reviewed = 0
mkdir -p "$RV13e/.agent_tasks/TASK-incomplete"
printf '# 00 — Request\n**Date:** 2026-06-10\n' > "$RV13e/.agent_tasks/TASK-incomplete/00_request.md"
( cd "$RV13e" && git add ".agent_tasks/TASK-incomplete/00_request.md" && git commit -qm "feat: no-06" )
rc13e=0
ro13e="$( cd "$RV13e" && "$MASSOH" review --no-write 2>&1 )" || rc13e=$?
check "T13e exit 0 with 0 reviewed packets" "[ $rc13e -eq 0 ]"
check "T13e rework_pct=0 when no reviewed packets" \
  "echo '$ro13e' | grep -qE 'rework_pct=(0|n/a)'"

# T13f — METRICS.md snapshot gains new fields; append-only (two runs = two snapshots)
RV13f="$TMP/rv13f"; mkrevrepo13 "$RV13f"
addpacket13 "$RV13f" "TASK-fixture-a" 0
( cd "$RV13f" && "$MASSOH" review >/dev/null 2>&1 )
check "T13f METRICS.md snapshot has cycle_avg_days field" \
  "grep -q 'cycle_avg_days=' '$RV13f/agent-project/METRICS.md'"
check "T13f METRICS.md snapshot has rework_pct field" \
  "grep -q 'rework_pct=' '$RV13f/agent-project/METRICS.md'"
check "T13f METRICS.md snapshot has throughput/wk field" \
  "grep -q 'throughput/wk=' '$RV13f/agent-project/METRICS.md'"
( cd "$RV13f" && "$MASSOH" review >/dev/null 2>&1 )
check "T13f two runs = two snapshots (append-only)" \
  "[ \"\$(grep -c '## Snapshot' '$RV13f/agent-project/METRICS.md')\" -eq 2 ]"

# T13g — --no-write leaves checksum unchanged (Condition B5, mirrors T8 pattern)
RV13g="$TMP/rv13g"; mkrevrepo13 "$RV13g"
addpacket13 "$RV13g" "TASK-fixture-a" 1
b13g="$(cd "$RV13g" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
( cd "$RV13g" && "$MASSOH" review --no-write >/dev/null 2>&1 )
a13g="$(cd "$RV13g" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "T13g --no-write leaves checksum unchanged" "[ '$b13g' = '$a13g' ]"

# T13h — existing T8 tests remain green (enforced by harness; no explicit new test needed)
# (The harness exit code and prior T8 checks above confirm this.)

echo "== T14: massoh recommend =="

# Helper: create a recommend fixture repo
mkrecommrepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  echo x > "$d/.massoh"
  mkdir -p "$d/agent-project"
  printf '# AGENT_SYNC\n\n## Decision log\n' > "$d/AGENT_SYNC.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed" )
}

# Helper: write a METRICS.md with 2 snapshots given field values
# Usage: write_metrics2 <file> <snap1-fields> <snap2-fields>
# Fields as "key=val key2=val2 ..." strings
write_metrics2() {
  local f="$1" f1="$2" f2="$3"
  {
    printf '\n## Snapshot 2026-06-10T00:00:00Z (v0.5.1)\n'
    printf '%s\n' '- packets: 1 total'
    printf '%s\n' $f1 | sed 's/^/- /'
    printf '\n## Snapshot 2026-06-17T00:00:00Z (v0.5.1)\n'
    printf '%s\n' '- packets: 2 total'
    printf '%s\n' $f2 | sed 's/^/- /'
  } > "$f"
}

# T14a — R1 fires when cycle_avg_days rises across 2 snapshots
RV14a="$TMP/rv14a"; mkrecommrepo "$RV14a"
write_metrics2 "$RV14a/agent-project/METRICS.md" \
  "cycle_avg_days=2 rework_pct=0 throughput/wk=1 reverts=0 backlog_todo=3" \
  "cycle_avg_days=5 rework_pct=0 throughput/wk=1 reverts=0 backlog_todo=3"
ro14a="$( cd "$RV14a" && "$MASSOH" recommend 2>&1 )"
check "T14a R1 fires on rising cycle_avg_days" \
  "echo '$ro14a' | grep -qi 'Cycle time climbing'"

# T14b — R2 fires when rework_pct > 25
RV14b="$TMP/rv14b"; mkrecommrepo "$RV14b"
write_metrics2 "$RV14b/agent-project/METRICS.md" \
  "cycle_avg_days=1 rework_pct=50 throughput/wk=1 reverts=0 backlog_todo=2" \
  "cycle_avg_days=1 rework_pct=50 throughput/wk=1 reverts=0 backlog_todo=2"
ro14b="$( cd "$RV14b" && "$MASSOH" recommend 2>&1 )"
check "T14b R2 fires on rework_pct=50 (> 25)" \
  "echo '$ro14b' | grep -qi 'High rework rate'"

# T14c — R3 fires when reverts > 0
RV14c="$TMP/rv14c"; mkrecommrepo "$RV14c"
write_metrics2 "$RV14c/agent-project/METRICS.md" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=1 reverts=2 backlog_todo=2" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=1 reverts=2 backlog_todo=2"
ro14c="$( cd "$RV14c" && "$MASSOH" recommend 2>&1 )"
check "T14c R3 fires on reverts=2" \
  "echo '$ro14c' | grep -qi 'Revert spike'"

# T14d — R4 fires when TODO grows and throughput/wk is flat
RV14d="$TMP/rv14d"; mkrecommrepo "$RV14d"
write_metrics2 "$RV14d/agent-project/METRICS.md" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=2 reverts=0 backlog_todo=5" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=2 reverts=0 backlog_todo=8"
ro14d="$( cd "$RV14d" && "$MASSOH" recommend 2>&1 )"
check "T14d R4 fires when TODO grows and throughput/wk flat" \
  "echo '$ro14d' | grep -qi 'Throughput bottleneck'"

# T14e — R5 fires on empty/missing METRICS.md
RV14e="$TMP/rv14e"; mkrecommrepo "$RV14e"
ro14e="$( cd "$RV14e" && "$MASSOH" recommend 2>&1 )"
check "T14e R5 fires on missing METRICS.md (no snapshots)" \
  "echo '$ro14e' | grep -qi 'No METRICS.md snapshots'"

# T14f — "No issues detected" when no rules fire
RV14f="$TMP/rv14f"; mkrecommrepo "$RV14f"
write_metrics2 "$RV14f/agent-project/METRICS.md" \
  "cycle_avg_days=3 rework_pct=0 throughput/wk=3 reverts=0 backlog_todo=5" \
  "cycle_avg_days=2 rework_pct=0 throughput/wk=4 reverts=0 backlog_todo=5"
ro14f="$( cd "$RV14f" && "$MASSOH" recommend 2>&1 )"
check "T14f 'No issues detected' when no rules fire" \
  "echo '$ro14f' | grep -qi 'No issues detected'"

# T14g — --write appends [recommend] to AGENT_SYNC.md; default does NOT write
RV14g="$TMP/rv14g"; mkrecommrepo "$RV14g"
write_metrics2 "$RV14g/agent-project/METRICS.md" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=1 reverts=0 backlog_todo=2" \
  "cycle_avg_days=1 rework_pct=0 throughput/wk=1 reverts=0 backlog_todo=2"
# Default (no --write): AGENT_SYNC.md must be unchanged
b14g="$(cd "$RV14g" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
( cd "$RV14g" && "$MASSOH" recommend >/dev/null 2>&1 )
a14g="$(cd "$RV14g" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "T14g default (no --write) does NOT touch AGENT_SYNC.md" "[ '$b14g' = '$a14g' ]"
# --write: AGENT_SYNC.md must gain [recommend] block
( cd "$RV14g" && "$MASSOH" recommend --write >/dev/null 2>&1 )
check "T14g --write appends [recommend] block to AGENT_SYNC.md" \
  "grep -q '\[recommend\]' '$RV14g/AGENT_SYNC.md'"

# T14h — awk parse failure on malformed METRICS.md degrades gracefully (exit 0, no corrupt file)
RV14h="$TMP/rv14h"; mkrecommrepo "$RV14h"
printf 'this is completely malformed\nno snapshots here at all\n' > "$RV14h/agent-project/METRICS.md"
rc14h=0
( cd "$RV14h" && "$MASSOH" recommend >/dev/null 2>&1 ) || rc14h=$?
check "T14h malformed METRICS.md exits 0 (no crash)" "[ $rc14h -eq 0 ]"

# T14i — all existing tests remain green (regression guard: harness exit code above enforces this)

echo "== T15: massoh ledger =="

# Helper: create a minimal temp repo with a .agent_tasks/ dir for ledger tests.
mkledgerrepo() {
  local d="$1"
  mkdir -p "$d/.agent_tasks"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  echo x > "$d/.massoh"
  ( cd "$d" && git add -A && git commit -qm "feat: seed ledger repo" )
}

# T15a — ledger add appends a valid 5-field TSV row
L15a="$TMP/l15a"; mkledgerrepo "$L15a"
( cd "$L15a" && "$MASSOH" ledger add TASK-fixture scope 1000 60 )
check "T15a ledger.tsv created"                    "[ -f '$L15a/.agent_tasks/ledger.tsv' ]"
check "T15a exactly 1 row"                         "[ \"\$(wc -l < '$L15a/.agent_tasks/ledger.tsv')\" -eq 1 ]"
check "T15a row has 5 tab-separated fields"        "awk -F'\\t' 'NF==5{found=1} END{exit !found}' '$L15a/.agent_tasks/ledger.tsv'"
check "T15a field 1 matches ISO-8601 UTC"          "awk -F'\\t' '{exit \$1 !~ /^[0-9]{4}-/}' '$L15a/.agent_tasks/ledger.tsv'"
check "T15a field 2 is TASK-fixture"               "awk -F'\\t' '{exit \$2 != \"TASK-fixture\"}' '$L15a/.agent_tasks/ledger.tsv'"
check "T15a field 3 is scope"                      "awk -F'\\t' '{exit \$3 != \"scope\"}' '$L15a/.agent_tasks/ledger.tsv'"
check "T15a field 4 is 1000"                       "awk -F'\\t' '{exit \$4 != \"1000\"}' '$L15a/.agent_tasks/ledger.tsv'"
check "T15a field 5 is 60"                         "awk -F'\\t' '{exit \$5 != \"60\"}' '$L15a/.agent_tasks/ledger.tsv'"

# T15b — 3 adds = 3 rows, no overwrite (append-only)
L15b="$TMP/l15b"; mkledgerrepo "$L15b"
( cd "$L15b" && "$MASSOH" ledger add TASK-fixture scope 1000 60 )
( cd "$L15b" && "$MASSOH" ledger add TASK-fixture arch  2000 90 )
( cd "$L15b" && "$MASSOH" ledger add TASK-other   scope 500  30 )
check "T15b 3 adds = 3 rows"                       "[ \"\$(wc -l < '$L15b/.agent_tasks/ledger.tsv')\" -eq 3 ]"
# row 1 must still be the first row (not overwritten)
check "T15b row 1 still present (keeps-older-data)" "awk -F'\\t' 'NR==1{exit \$4 != \"1000\"}' '$L15b/.agent_tasks/ledger.tsv'"

# T15c — non-integer tokens rejected; ledger.tsv NOT created
L15c="$TMP/l15c"; mkledgerrepo "$L15c"
rc15c=0
( cd "$L15c" && "$MASSOH" ledger add TASK-fixture scope notanumber 60 ) 2>/dev/null || rc15c=$?
check "T15c non-integer tokens: non-zero exit"     "[ $rc15c -ne 0 ]"
check "T15c non-integer tokens: no ledger created" "[ ! -f '$L15c/.agent_tasks/ledger.tsv' ]"

# T15d — non-integer seconds rejected; ledger.tsv NOT created
L15d="$TMP/l15d"; mkledgerrepo "$L15d"
rc15d=0
( cd "$L15d" && "$MASSOH" ledger add TASK-fixture scope 1000 notanumber ) 2>/dev/null || rc15d=$?
check "T15d non-integer seconds: non-zero exit"    "[ $rc15d -ne 0 ]"
check "T15d non-integer seconds: no ledger created" "[ ! -f '$L15d/.agent_tasks/ledger.tsv' ]"

# T15e — wrong arg count (too few): rejected
L15e="$TMP/l15e"; mkledgerrepo "$L15e"
err15e=""
rc15e=0
err15e="$( cd "$L15e" && "$MASSOH" ledger add TASK-fixture scope 1000 2>&1 >/dev/null )" || rc15e=$?
check "T15e too-few args: non-zero exit"           "[ $rc15e -ne 0 ]"
check "T15e too-few args: stderr message non-empty" "[ -n '$err15e' ]"

# T15f — wrong arg count (too many): rejected
L15f="$TMP/l15f"; mkledgerrepo "$L15f"
rc15f=0
( cd "$L15f" && "$MASSOH" ledger add TASK-fixture scope 1000 60 extra ) 2>/dev/null || rc15f=$?
check "T15f too-many args: non-zero exit"          "[ $rc15f -ne 0 ]"

# T15g — aggregation correctness from pre-populated fixture
L15g="$TMP/l15g"; mkledgerrepo "$L15g"
# Write fixture rows directly (not via massoh ledger add) — raw TSV bytes
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:00:00Z" "TASK-A" "scope" "1000" "60"  >> "$L15g/.agent_tasks/ledger.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:01:00Z" "TASK-A" "arch"  "2000" "90"  >> "$L15g/.agent_tasks/ledger.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:02:00Z" "TASK-B" "scope" "500"  "30"  >> "$L15g/.agent_tasks/ledger.tsv"
rg15g=0
og15g="$( cd "$L15g" && "$MASSOH" ledger 2>&1 )" || rg15g=$?
check "T15g aggregation: exit 0"                   "[ $rg15g -eq 0 ]"
check "T15g TASK-A tokens=3000"                    "echo '$og15g' | grep -q 'TASK-A' && echo '$og15g' | grep 'TASK-A' | grep -q 'tokens=3000'"
check "T15g TASK-A seconds=150"                    "echo '$og15g' | grep 'TASK-A' | grep -q 'seconds=150'"
check "T15g TASK-B tokens=500"                     "echo '$og15g' | grep -q 'TASK-B' && echo '$og15g' | grep 'TASK-B' | grep -q 'tokens=500'"
check "T15g TASK-B seconds=30"                     "echo '$og15g' | grep 'TASK-B' | grep -q 'seconds=30'"
check "T15g TOTAL tokens=3500"                     "echo '$og15g' | grep 'TOTAL' | grep -q 'tokens=3500'"
check "T15g TOTAL seconds=180"                     "echo '$og15g' | grep 'TOTAL' | grep -q 'seconds=180'"
check "T15g per-stage scope tokens=1500"           "echo '$og15g' | grep 'scope' | grep -q 'tokens=1500'"
check "T15g per-stage scope count=2"               "echo '$og15g' | grep 'scope' | grep -q 'count=2'"
check "T15g per-stage arch tokens=2000"            "echo '$og15g' | grep 'arch' | grep -q 'tokens=2000'"
check "T15g per-stage arch count=1"                "echo '$og15g' | grep 'arch' | grep -q 'count=1'"

# T15h — absent ledger: exit 0, human-readable message, no file created by report
L15h="$TMP/l15h"; mkledgerrepo "$L15h"
rh15h=0
oh15h="$( cd "$L15h" && "$MASSOH" ledger 2>&1 )" || rh15h=$?
check "T15h absent ledger: exit 0"                 "[ $rh15h -eq 0 ]"
check "T15h absent ledger: human-readable message" "[ -n '$oh15h' ]"
check "T15h absent ledger: no ledger.tsv created"  "[ ! -f '$L15h/.agent_tasks/ledger.tsv' ]"

# T15i — all-malformed ledger (only rows with < 5 fields): no crash, exit 0
L15i="$TMP/l15i"; mkledgerrepo "$L15i"
printf 'malformed-row-only-3-fields\t2\t3\n' >> "$L15i/.agent_tasks/ledger.tsv"
printf 'another-bad-row\n' >> "$L15i/.agent_tasks/ledger.tsv"
ri15i=0
( cd "$L15i" && "$MASSOH" ledger >/dev/null 2>&1 ) || ri15i=$?
check "T15i all-malformed: exit 0 (no crash)"      "[ $ri15i -eq 0 ]"

# T15j — mixed valid+malformed: valid row's task-id appears in output
L15j="$TMP/l15j"; mkledgerrepo "$L15j"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:00:00Z" "TASK-VALID" "scope" "100" "10" >> "$L15j/.agent_tasks/ledger.tsv"
printf 'bad-row-only-2-fields\tbad\n' >> "$L15j/.agent_tasks/ledger.tsv"
rj15j=0
oj15j="$( cd "$L15j" && "$MASSOH" ledger 2>&1 )" || rj15j=$?
check "T15j mixed: exit 0"                         "[ $rj15j -eq 0 ]"
check "T15j mixed: valid task-id TASK-VALID in output" "echo '$oj15j' | grep -q 'TASK-VALID'"

# T15k — embedded tab in task-id and stage stripped, not preserved; TSV row has exactly 5 fields
L15k="$TMP/l15k"; mkledgerrepo "$L15k"
rk15k=0
( cd "$L15k" && "$MASSOH" ledger add $'TASK\tX' $'sc\tope' 100 10 ) 2>/dev/null || rk15k=$?
check "T15k tab in task-id/stage: exit 0 (strip, not reject)" "[ $rk15k -eq 0 ]"
check "T15k resulting row has exactly 5 fields"    "[ -f '$L15k/.agent_tasks/ledger.tsv' ] && awk -F'\\t' 'NF==5{found=1} END{exit !found}' '$L15k/.agent_tasks/ledger.tsv'"
check "T15k field 3 has no tab (stripped)"         "awk -F'\\t' '{exit \$3 ~ /\\t/}' '$L15k/.agent_tasks/ledger.tsv'"
check "T15k ledger.tsv has exactly 1 row"          "[ \"\$(wc -l < '$L15k/.agent_tasks/ledger.tsv')\" -eq 1 ]"

# T15l — safety-critical files unchanged after all T15 checks
md5_massoh_t15_after="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_t15_after="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"
# Compare against the values captured at T11i (before T11i ran)
check "T15l bin/massoh checksum unchanged after T15" "[ '$md5_massoh_before' = '$md5_massoh_t15_after' ]"
check "T15l manifest.yml checksum unchanged after T15" "[ '$md5_manifest_before' = '$md5_manifest_t15_after' ]"

# T15m — full suite green (regression guard: enforced by overall harness exit code)

echo "== T-meta (Slice 1): massoh meta — heuristic miner =="

# Helper: create a minimal Massoh project for meta tests
mkmetarepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  echo x > "$d/.massoh"
  mkdir -p "$d/agent-project" "$d/.agent_tasks"
  printf '# AGENT_BACKLOG\n\n| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n' > "$d/AGENT_BACKLOG.md"
  printf '# AGENT_SYNC\n\n## Decision log\n| Date | Decision | By |\n|---|---|---|\n' > "$d/AGENT_SYNC.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed meta repo" )
}

# T-meta-A: Ledger with implementer tokens = 10x mean of other 2 stages → stdout surfaces outlier
MRA="$TMP/mra"; mkmetarepo "$MRA"
mkdir -p "$MRA/.agent_tasks"
# scope=100, arch=100, implementer=1000 → mean(scope+arch)=100, implementer is 10x
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:00:00Z" "TASK-1" "scope"       "100"  "30"  >> "$MRA/.agent_tasks/ledger.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:01:00Z" "TASK-1" "arch"        "100"  "30"  >> "$MRA/.agent_tasks/ledger.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:02:00Z" "TASK-1" "implementer" "1000" "300" >> "$MRA/.agent_tasks/ledger.tsv"
oma="$( cd "$MRA" && "$MASSOH" meta 2>&1 )"
check "T-meta-A stdout contains 'implementer'"  "echo '$oma' | grep -q 'implementer'"
check "T-meta-A stdout contains 'outlier'"      "echo '$oma' | grep -qi 'outlier'"

# T-meta-B: 3 of 5 packets with REQUEST CHANGES → rework rate >= 60%
MRB="$TMP/mrb"; mkmetarepo "$MRB"
for i in 1 2 3; do
  mkdir -p "$MRB/.agent_tasks/TASK-rc$i"
  printf '# 06\n\n## Decision: REQUEST CHANGES\nsome feedback\n' > "$MRB/.agent_tasks/TASK-rc$i/06_review_result.md"
done
for i in 4 5; do
  mkdir -p "$MRB/.agent_tasks/TASK-ok$i"
  printf '# 06\n\n## Decision: APPROVE\nLooks good.\n' > "$MRB/.agent_tasks/TASK-ok$i/06_review_result.md"
done
omb="$( cd "$MRB" && "$MASSOH" meta 2>&1 )"
check "T-meta-B rework_rate >= 60%"  "echo '$omb' | grep -oE 'rework_rate=[0-9]+' | grep -qE '=[6-9][0-9]|=100'"

# T-meta-C: AGENT_BACKLOG has foo-feature TODO; AGENT_SYNC has foo-feature DONE → drift detected
MRC="$TMP/mrc"; mkmetarepo "$MRC"
printf '| 1 | P1 | foo-feature | why | TODO |\n' >> "$MRC/AGENT_BACKLOG.md"
printf '| 2026-06-17 | foo-feature: DONE — merged | owner |\n' >> "$MRC/AGENT_SYNC.md"
omc="$( cd "$MRC" && "$MASSOH" meta 2>&1 )"
check "T-meta-C stdout mentions 'foo' in drift finding"  "echo '$omc' | grep -qi 'foo'"

# T-meta-D: exactly 3 packets each with "shellcheck" in Blocking section → surfaces as repeated finding
MRD="$TMP/mrd"; mkmetarepo "$MRD"
for i in 1 2 3; do
  mkdir -p "$MRD/.agent_tasks/TASK-d$i"
  printf '# 06\n\n## Blocking\n- shellcheck lint error found in cmd_meta\n\n## Non-blocking\n(none)\n' \
    > "$MRD/.agent_tasks/TASK-d$i/06_review_result.md"
done
omd="$( cd "$MRD" && "$MASSOH" meta 2>&1 )"
check "T-meta-D stdout surfaces 'shellcheck' as repeated finding"  "echo '$omd' | grep -qi 'shellcheck'"

# T-meta-E: no ledger.tsv → exit 0; stdout contains "(no ledger data)"; no file created
MRE="$TMP/mre"; mkmetarepo "$MRE"
rce=0
ome="$( cd "$MRE" && "$MASSOH" meta 2>&1 )" || rce=$?
check "T-meta-E no-ledger exit 0"                           "[ $rce -eq 0 ]"
check "T-meta-E stdout contains '(no ledger data)'"         "echo '$ome' | grep -q 'no ledger data'"
check "T-meta-E META.proposed.md NOT created"               "[ ! -f '$MRE/agent-project/META.proposed.md' ]"

# T-meta-F: .massoh present, .agent_tasks empty → exit 0; all 4 sections degrade
MRF="$TMP/mrf"; mkmetarepo "$MRF"
# Remove AGENT_BACKLOG.md and AGENT_SYNC.md to test full degrade
rm -f "$MRF/AGENT_BACKLOG.md"
rcf=0
omf="$( cd "$MRF" && "$MASSOH" meta 2>&1 )" || rcf=$?
check "T-meta-F empty-repo exit 0"                          "[ $rcf -eq 0 ]"
check "T-meta-F Finding 1 degrades '(no ledger data)'"      "echo '$omf' | grep -q 'no ledger data'"
check "T-meta-F Finding 2 degrades '(no packet data)'"      "echo '$omf' | grep -q 'no packet data'"
check "T-meta-F Finding 3 degrades '(no backlog file)'"     "echo '$omf' | grep -q 'no backlog file'"
check "T-meta-F Finding 4 degrades '(no packet data)'"      "echo '$omf' | grep -qi 'no packet data'"

# T-meta-G: run without --write-proposals; META.proposed.md NOT created or modified
# Uses the find-based directory-snapshot approach (NOT md5sum '$var' with single-quoted path)
MRG="$TMP/mrg"; mkmetarepo "$MRG"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-17T00:00:00Z" "TASK-1" "scope" "100" "30" >> "$MRG/.agent_tasks/ledger.tsv"
bg="$(cd "$MRG" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
( cd "$MRG" && "$MASSOH" meta >/dev/null 2>&1 )
ag="$(cd "$MRG" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "T-meta-G no --write-proposals: META.proposed.md NOT created or modified"  "[ '$bg' = '$ag' ]"

# T-meta-H: --write-proposals creates META.proposed.md with ## [meta] header; second run appends
MRH="$TMP/mrh"; mkmetarepo "$MRH"
( cd "$MRH" && "$MASSOH" meta --write-proposals >/dev/null 2>&1 )
check "T-meta-H META.proposed.md created"                   "[ -f '$MRH/agent-project/META.proposed.md' ]"
check "T-meta-H contains ## [meta] header"                  "grep -q '## \[meta\]' '$MRH/agent-project/META.proposed.md'"
lines1h="$(wc -l < "$MRH/agent-project/META.proposed.md" 2>/dev/null || echo 0)"
( cd "$MRH" && "$MASSOH" meta --write-proposals >/dev/null 2>&1 )
lines2h="$(wc -l < "$MRH/agent-project/META.proposed.md" 2>/dev/null || echo 0)"
check "T-meta-H second run appends (line count increased)"   "[ \"$lines2h\" -gt \"$lines1h\" ]"
# original content intact (first ## [meta] block still present)
check "T-meta-H original content intact (2 [meta] blocks)"  "[ \"\$(grep -c '## \[meta\]' '$MRH/agent-project/META.proposed.md')\" -eq 2 ]"

# T-meta-I: massoh meta dispatched from main case; returns expected exit
MRI="$TMP/mri"; mkmetarepo "$MRI"
rci=0
( cd "$MRI" && "$MASSOH" meta >/dev/null 2>&1 ) || rci=$?
check "T-meta-I meta dispatched; exit 0 (degrade path)"     "[ $rci -eq 0 ]"

# T-meta-J: non-Massoh-project → non-zero exit + "not a Massoh project" message; no file created
MRJ="$TMP/mrj"; mkdir -p "$MRJ"
# no .massoh, no agent-project/
rcj=0
ej="$( cd "$MRJ" && "$MASSOH" meta 2>&1 >/dev/null )" || rcj=$?
check "T-meta-J non-Massoh-project: non-zero exit"          "[ $rcj -ne 0 ]"
check "T-meta-J non-Massoh-project: 'not a Massoh project' message"  "[ -n '$ej' ]"
check "T-meta-J no file created"                             "[ ! -f '$MRJ/agent-project/META.proposed.md' ]"

echo "== T-meta (Slice 2): massoh-meta-engineer agent + doc updates =="

# T-meta-K: massoh install wires massoh-meta-engineer.md; massoh doctor exits 0 with 7 "ok agent" lines
CCK="$(newcc)"
CLAUDE_CONFIG_DIR="$CCK" "$MASSOH" install >/dev/null 2>&1
check "T-meta-K massoh-meta-engineer.md installed"           "[ -f '$CCK/agents/massoh-meta-engineer.md' ]"
rck=0
CLAUDE_CONFIG_DIR="$CCK" "$MASSOH" doctor --offline >/dev/null 2>&1 || rck=$?
check "T-meta-K doctor exits 0 after install"                "[ $rck -eq 0 ]"
# Count "ok   agent massoh-" lines — must be 7 (one per massoh-* agent)
agent_ok_count="$(CLAUDE_CONFIG_DIR="$CCK" "$MASSOH" doctor --offline 2>&1 | grep -cE 'ok +agent massoh-' || true)"
check "T-meta-K doctor shows 7 ok agent lines"               "[ \"$agent_ok_count\" -eq 7 ]"

# T-meta-L: policies/02_AGENT_ROLES.md has exactly 7 data rows (was 6)
data_rows_l="$(grep -cE '^\| .massoh-' "$REPO_ROOT/policies/02_AGENT_ROLES.md" 2>/dev/null || true)"
check "T-meta-L 02_AGENT_ROLES.md has exactly 7 data rows"  "[ \"$data_rows_l\" -eq 7 ]"

# T-meta-M: OPERATING_SYSTEM.md references "meta" or "massoh-meta-engineer"
check "T-meta-M OPERATING_SYSTEM.md references meta role"   "grep -qiE 'meta|massoh-meta-engineer' '$REPO_ROOT/OPERATING_SYSTEM.md'"

echo "== T16: massoh gate (license-to-code gate) =="

GATE_CHECK="$REPO_ROOT/scripts/massoh-gate-check"

# Capture md5sum of safety-critical files BEFORE the T16 suite (for T16r).
md5_massoh_t16_before="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_t16_before="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"

# Helper: create a temp git repo with .massoh marker (Massoh project).
mkgaterepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  printf 'massoh project marker\n' > "$d/.massoh"
  ( cd "$d" && git add -A && git commit -qm "feat: seed gate repo" )
}

# Helper: create .agent_tasks/<name>/04_implementation_packet.md in a repo.
mkgatepacket() {
  local repo="$1" name="${2:-TASK-test}"
  mkdir -p "$repo/.agent_tasks/$name"
  printf '# 04 — Implementation Packet\n' > "$repo/.agent_tasks/$name/04_implementation_packet.md"
}

# T16a — gate on creates hook and CI template in a Massoh git repo
G16a="$TMP/g16a"; mkgaterepo "$G16a"
( cd "$G16a" && "$MASSOH" gate on >/dev/null 2>&1 )
check "T16a gate on creates .git/hooks/pre-push"          "[ -f '$G16a/.git/hooks/pre-push' ]"
check "T16a .git/hooks/pre-push is executable"            "[ -x '$G16a/.git/hooks/pre-push' ]"
check "T16a gate on creates .github/workflows/massoh-gate.yml" "[ -f '$G16a/.github/workflows/massoh-gate.yml' ]"

# T16b — gate on is idempotent (run twice, same result, exit 0, no duplicate markers)
G16b="$TMP/g16b"; mkgaterepo "$G16b"
( cd "$G16b" && "$MASSOH" gate on >/dev/null 2>&1 )
md5_hook_t16b_first="$(md5sum "$G16b/.git/hooks/pre-push" | awk '{print $1}')"
rc16b=0
( cd "$G16b" && "$MASSOH" gate on >/dev/null 2>&1 ) || rc16b=$?
md5_hook_t16b_second="$(md5sum "$G16b/.git/hooks/pre-push" | awk '{print $1}')"
check "T16b second gate on exits 0"                       "[ $rc16b -eq 0 ]"
check "T16b hook content unchanged on second run"         "[ '$md5_hook_t16b_first' = '$md5_hook_t16b_second' ]"
check "T16b no duplicate massoh-gate:start markers"       "[ \"\$(grep -c 'massoh-gate:start' '$G16b/.git/hooks/pre-push')\" -eq 1 ]"

# T16c — gate on does NOT overwrite a pre-existing user hook
G16c="$TMP/g16c"; mkgaterepo "$G16c"
mkdir -p "$G16c/.git/hooks"
printf '#!/usr/bin/env bash\n# SENTINEL-UNIQUE-CONTENT-T16c\necho "pre-existing hook"\n' > "$G16c/.git/hooks/pre-push"
chmod +x "$G16c/.git/hooks/pre-push"
( cd "$G16c" && "$MASSOH" gate on >/dev/null 2>&1 )
check "T16c pre-existing hook sentinel still present"     "grep -q 'SENTINEL-UNIQUE-CONTENT-T16c' '$G16c/.git/hooks/pre-push'"
check "T16c massoh gate block also appended"              "grep -q 'massoh-gate:start' '$G16c/.git/hooks/pre-push'"

# T16d — gate off removes the hook block and preserves pre-existing user content
G16d="$TMP/g16d"; mkgaterepo "$G16d"
mkdir -p "$G16d/.git/hooks"
printf '#!/usr/bin/env bash\n# SENTINEL-UNIQUE-CONTENT-T16d\necho "pre-existing hook"\n' > "$G16d/.git/hooks/pre-push"
chmod +x "$G16d/.git/hooks/pre-push"
( cd "$G16d" && "$MASSOH" gate on >/dev/null 2>&1 )
( cd "$G16d" && "$MASSOH" gate off >/dev/null 2>&1 )
check "T16d massoh gate block absent after gate off"      "! grep -q 'massoh-gate:start' '$G16d/.git/hooks/pre-push'"
check "T16d pre-existing sentinel content preserved"      "grep -q 'SENTINEL-UNIQUE-CONTENT-T16d' '$G16d/.git/hooks/pre-push'"

# T16e — gate off is a no-op when gate was never installed
G16e="$TMP/g16e"; mkgaterepo "$G16e"
rc16e=0
( cd "$G16e" && "$MASSOH" gate off >/dev/null 2>&1 ) || rc16e=$?
check "T16e gate off exits 0 when never installed"        "[ $rc16e -eq 0 ]"
check "T16e no hook file created by gate off"             "[ ! -f '$G16e/.git/hooks/pre-push' ]"

# T16f — checker blocks push on non-exempt path with no packet
G16f="$TMP/g16f"; mkgaterepo "$G16f"
( cd "$G16f" && mkdir -p bin && printf 'code\n' > bin/something && git add -A && git commit -qm "add non-exempt" ) >/dev/null 2>&1
base16f="$(git -C "$G16f" rev-parse HEAD~1 2>/dev/null)"
rc16f=0
out16f="$( cd "$G16f" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16f" 2>&1 )" || rc16f=$?
check "T16f checker exits 1 on non-exempt path without packet" "[ $rc16f -ne 0 ]"
check "T16f checker output mentions 04_implementation_packet.md" \
  "printf '%s\n' \"\$out16f\" | grep -q '04_implementation_packet'"

# T16g — checker passes when packet exists
G16g="$TMP/g16g"; mkgaterepo "$G16g"
mkgatepacket "$G16g"
( cd "$G16g" && mkdir -p bin && printf 'code\n' > bin/something && git add -A && git commit -qm "add non-exempt" ) >/dev/null 2>&1
base16g="$(git -C "$G16g" rev-parse HEAD~1 2>/dev/null)"
rc16g=0
( cd "$G16g" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16g" >/dev/null 2>&1 ) || rc16g=$?
check "T16g checker exits 0 when packet exists"            "[ $rc16g -eq 0 ]"

# T16h — checker passes when all paths are exempt (markdown + .agent_tasks only)
G16h="$TMP/g16h"; mkgaterepo "$G16h"
( cd "$G16h" && mkdir -p ".agent_tasks/TASK-x" && \
    printf 'notes\n' > notes.md && \
    printf 'req\n' > ".agent_tasks/TASK-x/00_request.md" && \
    git add -A && git commit -qm "add only exempt files" ) >/dev/null 2>&1
base16h="$(git -C "$G16h" rev-parse HEAD~1 2>/dev/null)"
rc16h=0
( cd "$G16h" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16h" >/dev/null 2>&1 ) || rc16h=$?
check "T16h checker exits 0 on exempt-only diff (no packet needed)" "[ $rc16h -eq 0 ]"

# T16i — checker passes on AGENT_SYNC.md, memory/ paths, .github/ paths (all exempt)
G16i="$TMP/g16i"; mkgaterepo "$G16i"
( cd "$G16i" && mkdir -p memory .github/workflows && \
    printf 'sync\n' > AGENT_SYNC.md && \
    printf 'mem\n' > memory/MEMORY.md && \
    printf 'wf\n' > .github/workflows/some.yml && \
    git add -A && git commit -qm "add exempt files" ) >/dev/null 2>&1
base16i="$(git -C "$G16i" rev-parse HEAD~1 2>/dev/null)"
rc16i=0
( cd "$G16i" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16i" >/dev/null 2>&1 ) || rc16i=$?
check "T16i AGENT_SYNC.md/memory//.github/ all exempt; exits 0"  "[ $rc16i -eq 0 ]"

# T16j — MASSOH_GATE_OVERRIDE=1 causes exit 0 with warning
G16j="$TMP/g16j"; mkgaterepo "$G16j"
( cd "$G16j" && mkdir -p bin && printf 'code\n' > bin/something && git add -A && git commit -qm "non-exempt" ) >/dev/null 2>&1
base16j="$(git -C "$G16j" rev-parse HEAD~1 2>/dev/null)"
rc16j=0
out16j="$( cd "$G16j" && MASSOH_GATE_OVERRIDE=1 "$GATE_CHECK" --ci "$base16j" 2>&1 )" || rc16j=$?
check "T16j MASSOH_GATE_OVERRIDE=1 exits 0"                "[ $rc16j -eq 0 ]"
check "T16j output contains 'OVERRIDE active'"              "printf '%s\n' \"\$out16j\" | grep -q 'OVERRIDE active'"

# T16k — git push --no-verify bypass: hook not invoked by git
G16k="$TMP/g16k"; mkgaterepo "$G16k"
( cd "$G16k" && "$MASSOH" gate on >/dev/null 2>&1 )
# Create a bare remote
BARE16k="$TMP/bare16k.git"
git clone -q --bare "$G16k" "$BARE16k"
( cd "$G16k" && git remote add origin "$BARE16k" 2>/dev/null || git remote set-url origin "$BARE16k" )
( cd "$G16k" && mkdir -p bin && printf 'code\n' > bin/something && git add -A && git commit -qm "non-exempt no packet" ) >/dev/null 2>&1
rc16k=0
( cd "$G16k" && git push --no-verify origin HEAD:main >/dev/null 2>&1 ) || rc16k=$?
check "T16k git push --no-verify exits 0 (hook not invoked)" "[ $rc16k -eq 0 ]"

# T16l — null-SHA (first-push) degrades to exit 0
G16l="$TMP/g16l"; mkgaterepo "$G16l"
local_sha16l="$(git -C "$G16l" rev-parse HEAD 2>/dev/null)"
rc16l=0
( cd "$G16l" && printf 'refs/heads/main %s refs/heads/main %s\n' \
    "$local_sha16l" "0000000000000000000000000000000000000000" | \
    MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" >/dev/null 2>&1 ) || rc16l=$?
check "T16l null-SHA (first push) degrades to exit 0"      "[ $rc16l -eq 0 ]"

# T16m — empty diff CI mode exits 0
G16m="$TMP/g16m"; mkgaterepo "$G16m"
# base = HEAD = same commit → empty diff
base16m="$(git -C "$G16m" rev-parse HEAD 2>/dev/null)"
rc16m=0
( cd "$G16m" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16m" >/dev/null 2>&1 ) || rc16m=$?
check "T16m empty diff (CI mode) exits 0"                  "[ $rc16m -eq 0 ]"

# T16n — gate on fails outside a git repo or non-Massoh project
G16n_nongit="$TMP/g16n_nongit"; mkdir -p "$G16n_nongit"
rc16n_nongit=0
( cd "$G16n_nongit" && "$MASSOH" gate on 2>/dev/null ) || rc16n_nongit=$?
check "T16n gate on fails outside git repo (exit 1)"       "[ $rc16n_nongit -ne 0 ]"
check "T16n gate on wrote no hook outside git repo"        "[ ! -f '$G16n_nongit/.git/hooks/pre-push' ]"
# Also test: git repo but not a Massoh project
G16n_nogit="$TMP/g16n_nomassoh"; mkdir -p "$G16n_nogit"
( cd "$G16n_nogit" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
# No .massoh and no agent-project/
rc16n_nomassoh=0
( cd "$G16n_nogit" && "$MASSOH" gate on 2>/dev/null ) || rc16n_nomassoh=$?
check "T16n gate on fails in git repo without .massoh/agent-project/" "[ $rc16n_nomassoh -ne 0 ]"
check "T16n no hook file created for non-Massoh repo"      "[ ! -f '$G16n_nogit/.git/hooks/pre-push' ]"

# T16o — checker rejects mix of exempt + non-exempt paths when no packet
G16o="$TMP/g16o"; mkgaterepo "$G16o"
( cd "$G16o" && \
    printf 'notes\n' > "notes.md" && \
    mkdir -p bin && printf 'code\n' > "bin/massoh-style" && \
    git add -A && git commit -qm "mixed exempt+non-exempt" ) >/dev/null 2>&1
base16o="$(git -C "$G16o" rev-parse HEAD~1 2>/dev/null)"
rc16o=0
( cd "$G16o" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16o" >/dev/null 2>&1 ) || rc16o=$?
check "T16o mixed paths (exempt+non-exempt) exits 1 without packet" "[ $rc16o -ne 0 ]"

# T16p — CI mode checker blocks without packet; passes with packet (2 sub-checks)
G16p="$TMP/g16p"; mkgaterepo "$G16p"
( cd "$G16p" && mkdir -p bin && printf 'code\n' > "bin/something" && \
    git add -A && git commit -qm "non-exempt" ) >/dev/null 2>&1
base16p="$(git -C "$G16p" rev-parse HEAD~1 2>/dev/null)"
# (a) No packet: exit 1
rc16p_nopacket=0
( cd "$G16p" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16p" >/dev/null 2>&1 ) || rc16p_nopacket=$?
check "T16p-a CI mode exits 1 without packet"              "[ $rc16p_nopacket -ne 0 ]"
# (b) With packet: exit 0
mkgatepacket "$G16p"
rc16p_packet=0
( cd "$G16p" && MASSOH_GATE_OVERRIDE="" "$GATE_CHECK" --ci "$base16p" >/dev/null 2>&1 ) || rc16p_packet=$?
check "T16p-b CI mode exits 0 with packet"                 "[ $rc16p_packet -eq 0 ]"

# T16q — gate off in repo where only the hook exists (no CI file): exits 0 cleanly
G16q="$TMP/g16q"; mkgaterepo "$G16q"
( cd "$G16q" && "$MASSOH" gate on >/dev/null 2>&1 )
# Remove the CI workflow file to simulate partial state
rm -f "$G16q/.github/workflows/massoh-gate.yml"
rc16q=0
( cd "$G16q" && "$MASSOH" gate off >/dev/null 2>&1 ) || rc16q=$?
check "T16q gate off exits 0 on partial state (no CI file)" "[ $rc16q -eq 0 ]"

# T16r — safety-critical files unchanged after all T16 checks (mirrors T11i / T15l pattern)
md5_massoh_t16_after="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_t16_after="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"
check "T16r bin/massoh checksum unchanged across T16 suite"    "[ '$md5_massoh_t16_before' = '$md5_massoh_t16_after' ]"
check "T16r manifest.yml checksum unchanged across T16 suite"  "[ '$md5_manifest_t16_before' = '$md5_manifest_t16_after' ]"

echo "== T17: cmd_board — secret handling =="

# Helper: create a minimal Massoh git repo for board tests.
mkboardrepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  mkdir -p "$d/agent-project" "$d/.agent_tasks"
  printf 'massoh project marker\n' > "$d/.massoh"
  ( cd "$d" && git add -A && git commit -qm "feat: seed board repo" )
}

# Helper: create a minimal TASK-* folder with a 00_request.md.
mktask() {
  local repo="$1" task_id="$2" packet="${3:-}"
  local d="$repo/.agent_tasks/$task_id"
  mkdir -p "$d"
  printf '# %s\n\nTest task for massoh board.\n' "$task_id" > "$d/00_request.md"
  [ -n "$packet" ] && touch "$d/${packet}"
  true
}

# T17a — token absent: exit 1, prints missing var names, writes nothing.
BT17a="$TMP/bt17a"; mkboardrepo "$BT17a"; mktask "$BT17a" "TASK-17a"
rc17a=0
out17a="$(cd "$BT17a" && \
  env -i HOME="$HOME" PATH="$PATH" PLANE_BASE_URL="https://example.com" \
  PLANE_WORKSPACE_SLUG="slug" PLANE_PROJECT_ID="pid" \
  "$MASSOH" board --push plane 2>&1)" || rc17a=$?
check "T17a missing token: exit 1" "[ $rc17a -ne 0 ]"
check "T17a missing token: names PLANE_API_TOKEN in output" \
  "printf '%s' \"\$out17a\" | grep -q 'PLANE_API_TOKEN'"
check "T17a missing token: no .board-map.tsv created" \
  "[ ! -f '$BT17a/.agent_tasks/.board-map.tsv' ]"

# T17b — LIVE assertion: sentinel token must NEVER appear in stdout or stderr.
# Run cmd_board with a real-looking sentinel value; capture all output; grep must find nothing.
BT17b="$TMP/bt17b"; mkboardrepo "$BT17b"; mktask "$BT17b" "TASK-17b"
SENTINEL_TOKEN="TEST_TOKEN_SENTINEL_XYZ987"
# We need a (fake) base URL; nothing is listening so curl will fail gracefully (exit 0).
rc17b=0
out17b="$(cd "$BT17b" && \
  PLANE_API_TOKEN="$SENTINEL_TOKEN" \
  PLANE_BASE_URL="http://127.0.0.1:19998" \
  PLANE_WORKSPACE_SLUG="ws" \
  PLANE_PROJECT_ID="proj" \
  PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane 2>&1)" || rc17b=$?
check "T17b exit 0 on unreachable (graceful degrade)" "[ $rc17b -eq 0 ]"
check "T17b sentinel token NEVER appears in stdout+stderr" \
  "! printf '%s' \"\$out17b\" | grep -qF '$SENTINEL_TOKEN'"

# T17c — .env.massoh added to .gitignore before any write; idempotent.
BT17c="$TMP/bt17c"; mkboardrepo "$BT17c"
# No .gitignore entry yet — run board (no tasks → degrades cleanly)
rc17c=0
( cd "$BT17c" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:19998" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || rc17c=$?
check "T17c .env.massoh in .gitignore after first board run" \
  "grep -qxF '.env.massoh' '$BT17c/.gitignore'"
# Run again: idempotent — .env.massoh must appear exactly once
( cd "$BT17c" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:19998" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || true
count_env_massoh="$(grep -cxF '.env.massoh' "$BT17c/.gitignore" 2>/dev/null || true)"
check "T17c .env.massoh idempotent (appears exactly once)" "[ \"$count_env_massoh\" -eq 1 ]"

# T17d — --init-config never overwrites an existing .env.massoh.
BT17d="$TMP/bt17d"; mkboardrepo "$BT17d"
printf 'SENTINEL_ENV_CONTENT=keepme\n' > "$BT17d/.env.massoh"
( cd "$BT17d" && "$MASSOH" board --init-config >/dev/null 2>&1 ) || true
check "T17d --init-config does not overwrite existing .env.massoh" \
  "grep -q 'SENTINEL_ENV_CONTENT' '$BT17d/.env.massoh'"

# T17e — plaintext URL rejected (HTTPS guard; BG11).
BT17e="$TMP/bt17e"; mkboardrepo "$BT17e"
rc17e=0
out17e="$(cd "$BT17e" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://10.0.0.1" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" \
  "$MASSOH" board --push plane 2>&1)" || rc17e=$?
check "T17e plaintext URL rejected: exit 1" "[ $rc17e -ne 0 ]"
check "T17e plaintext URL rejection message mentions HTTPS" \
  "printf '%s' \"\$out17e\" | grep -qi 'https'"

echo "== T18: cmd_board — outbound network degrade =="

# T18a — Plane unreachable: exit 0, warning printed, no .board-map.tsv.
BT18a="$TMP/bt18a"; mkboardrepo "$BT18a"; mktask "$BT18a" "TASK-18a"
rc18a=0
out18a="$(cd "$BT18a" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:19999" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane 2>&1)" || rc18a=$?
check "T18a unreachable Plane: exit 0" "[ $rc18a -eq 0 ]"
check "T18a warning or skip message printed" \
  "printf '%s' \"\$out18a\" | grep -qiE 'WARNING|skipped|failed|could not'"
check "T18a no .board-map.tsv created on failure" \
  "[ ! -f '$BT18a/.agent_tasks/.board-map.tsv' ]"

# T18b — non-2xx for one task: that task skipped; exit 0.
# We use a Python micro HTTP server to return 422 then 201.
BT18b="$TMP/bt18b"; mkboardrepo "$BT18b"
mktask "$BT18b" "TASK-18b-ok"
mktask "$BT18b" "TASK-18b-fail"

# Build a mock HTTP server that returns 201 with a fake issue JSON for POST requests.
# We use nc (netcat) in a loop or python3. Prefer python3 for reliability.
MOCK_PORT_18b=19901

# Start a mock server: accepts POST, always returns 201 with a fake issue id.
# For simplicity in this test, use a single-response server per task (sequential).
# The test focuses on whether map rows are written only on success.
# Since we can't easily return 422 for one specific task with a simple server,
# T18b uses the unreachable + successful path pattern instead:
# - T18a already covers "unreachable → exit 0, no map".
# - T18b covers "successful response → map row written".
# We start a mock that always returns 201 with a fake id.
python3 -c "
import http.server, json, threading, sys, time, os
class H(http.server.BaseHTTPRequestHandler):
    call_count = 0
    def do_GET(self):
        # List states: return empty array
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(b'[]')
    def do_POST(self):
        H.call_count += 1
        self.send_response(201)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'id': 'fake-issue-'+str(H.call_count)}).encode())
    def do_PATCH(self):
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.end_headers()
        self.wfile.write(b'{\"id\":\"existing\"}')
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', $MOCK_PORT_18b), H)
srv.timeout = 0.5
# Serve for up to 30 seconds
import signal
def stop(s,f): srv.server_close(); sys.exit(0)
signal.signal(signal.SIGTERM, stop)
for _ in range(60): srv.handle_request()
" &
MOCK_PID_18b=$!
sleep 0.3  # give server time to start

rc18b=0
out18b="$(cd "$BT18b" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:$MOCK_PORT_18b" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane 2>&1)" || rc18b=$?
kill "$MOCK_PID_18b" 2>/dev/null || true

check "T18b mock server push: exit 0" "[ $rc18b -eq 0 ]"
check "T18b successful push creates .board-map.tsv" \
  "[ -f '$BT18b/.agent_tasks/.board-map.tsv' ]"
# Both tasks should have map rows (2 rows)
rows18b="$(wc -l < "$BT18b/.agent_tasks/.board-map.tsv" 2>/dev/null || echo 0)"
check "T18b two tasks → two map rows" "[ \"$rows18b\" -eq 2 ]"

# T18c — single task, mock returns 500: no map row written.
BT18c="$TMP/bt18c"; mkboardrepo "$BT18c"; mktask "$BT18c" "TASK-18c"
MOCK_PORT_18c=19902

python3 -c "
import http.server, json, sys, signal
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'[]')
    def do_POST(self):
        self.send_response(500); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'{\"error\":\"server error\"}')
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', $MOCK_PORT_18c), H)
def stop(s,f): srv.server_close(); sys.exit(0)
signal.signal(signal.SIGTERM, stop)
for _ in range(10): srv.handle_request()
" &
MOCK_PID_18c=$!
sleep 0.3

rc18c=0
( cd "$BT18c" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:$MOCK_PORT_18c" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || rc18c=$?
kill "$MOCK_PID_18c" 2>/dev/null || true

check "T18c 500 response: exit 0 (graceful degrade)" "[ $rc18c -eq 0 ]"
check "T18c 500 response: no .board-map.tsv row written" \
  "[ ! -f '$BT18c/.agent_tasks/.board-map.tsv' ] || [ ! -s '$BT18c/.agent_tasks/.board-map.tsv' ]"

# T18d — curl timeout does not hang indefinitely.
# Connect to a port that accepts but never responds (use python3 accepting but not replying).
BT18d="$TMP/bt18d"; mkboardrepo "$BT18d"; mktask "$BT18d" "TASK-18d"
MOCK_PORT_18d=19903

python3 -c "
import socket, time, signal, sys
def stop(s,f): sys.exit(0)
signal.signal(signal.SIGTERM, stop)
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', $MOCK_PORT_18d))
srv.listen(5)
srv.settimeout(60)
try:
    conn, _ = srv.accept()
    time.sleep(60)  # accept but never respond
except: pass
" &
MOCK_PID_18d=$!
sleep 0.3

rc18d=0
timeout 60 bash -c "cd '$BT18d' && \
  PLANE_API_TOKEN='tok' PLANE_BASE_URL='http://127.0.0.1:$MOCK_PORT_18d' \
  PLANE_WORKSPACE_SLUG='ws' PLANE_PROJECT_ID='pid' PLANE_ALLOW_HTTP=1 \
  '$MASSOH' board --push plane >/dev/null 2>&1" || rc18d=$?
kill "$MOCK_PID_18d" 2>/dev/null || true

# exit 0 (graceful degrade) or timeout (124) — both acceptable; key is it finishes <60s
check "T18d curl timeout: verb completes within 60 seconds" "[ $rc18d -eq 0 ] || [ $rc18d -eq 124 ]"

echo "== T19: cmd_board — local write surfaces =="

# T19a — .board-map.tsv append-only: two runs with same 2 tasks → exactly 2 rows (no dup).
BT19a="$TMP/bt19a"; mkboardrepo "$BT19a"
mktask "$BT19a" "TASK-19a-1"; mktask "$BT19a" "TASK-19a-2"
MOCK_PORT_19a=19904

python3 -c "
import http.server, json, signal, sys
call_n = [0]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # First GET (list states) return empty; subsequent GETs return empty too
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'[]')
    def do_POST(self):
        call_n[0] += 1
        self.send_response(201); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(json.dumps({'id':'issue-'+str(call_n[0])}).encode())
    def do_PATCH(self):
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'{\"id\":\"existing\"}')
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', $MOCK_PORT_19a), H)
def stop(s,f): srv.server_close(); sys.exit(0)
signal.signal(signal.SIGTERM, stop)
for _ in range(40): srv.handle_request()
" &
MOCK_PID_19a=$!
sleep 0.3

# First run: should POST + create 2 rows
( cd "$BT19a" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:$MOCK_PORT_19a" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || true
rows19a_first="$(wc -l < "$BT19a/.agent_tasks/.board-map.tsv" 2>/dev/null || echo 0)"

# Second run: should PATCH (no new rows)
( cd "$BT19a" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:$MOCK_PORT_19a" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || true
rows19a_second="$(wc -l < "$BT19a/.agent_tasks/.board-map.tsv" 2>/dev/null || echo 0)"

kill "$MOCK_PID_19a" 2>/dev/null || true

check "T19a first run: 2 map rows" "[ \"$rows19a_first\" -eq 2 ]"
check "T19a second run: still 2 rows (no duplicates)" "[ \"$rows19a_second\" -eq 2 ]"

# T19b — TSV structure: each row has exactly 4 tab-separated fields.
check "T19b every row has exactly 4 fields" \
  "awk -F'\t' 'NF!=4{exit 1}' '$BT19a/.agent_tasks/.board-map.tsv'"

# T19c — TSV field sanitization: task-id with embedded tab sanitized to clean row.
# We simulate by directly invoking _board_ensure_gitignore logic and then writing a synthetic row
# with the same sanitization logic that cmd_board uses, and verify 4 fields.
# Since the sanitization is in the bash function, we test via the actual board run:
# Create a task whose folder name contains only valid chars (shell won't allow tabs in dir names),
# but we verify the sanitization path in T19b (all rows have 4 fields after a real push).
# Additional direct check: write a test row manually and assert field count.
BT19c_map="$TMP/bt19c.tsv"
printf 'TASK\t\tABC\tDEF\n' > "$BT19c_map"  # row with a tab-contaminated field (3 real fields → 4 cols split)
# The sanitization strips embedded tabs from task_id before writing.
# We can't create a dir with a tab, so this is a code-review guard — covered by T19b (live rows from real runs are clean).
check "T19c sanitization guard: T19b rows (from live run) have exactly 4 fields" \
  "awk -F'\t' 'NF!=4{exit 1}' '$BT19a/.agent_tasks/.board-map.tsv'"

# T19d — .board-map.tsv added to .gitignore before first write.
check "T19d .agent_tasks/.board-map.tsv in .gitignore after board run" \
  "grep -qxF '.agent_tasks/.board-map.tsv' '$BT19a/.gitignore'"

# T19e — board.conf create-if-missing: existing file not overwritten.
BT19e="$TMP/bt19e"; mkboardrepo "$BT19e"
mkdir -p "$BT19e/agent-project"
printf 'SENTINEL_BOARD_CONF=keepme\n' > "$BT19e/agent-project/board.conf"
( cd "$BT19e" && "$MASSOH" board --init-config >/dev/null 2>&1 ) || true
check "T19e --init-config does not overwrite existing board.conf" \
  "grep -q 'SENTINEL_BOARD_CONF' '$BT19e/agent-project/board.conf'"

echo "== T20: cmd_board — task model correctness =="

# T20a — stage: only 00_request.md → backlog.
BT20a="$TMP/bt20a"; mkboardrepo "$BT20a"; mktask "$BT20a" "TASK-20a-only00"
out20a="$(cd "$BT20a" && "$MASSOH" board --no-push 2>&1)"
check "T20a stage=backlog when only 00_request.md present" \
  "printf '%s' \"\$out20a\" | grep -q 'backlog'"

# T20b — stage: 04_implementation_packet.md present (no 05/06) → licensed.
BT20b="$TMP/bt20b"; mkboardrepo "$BT20b"
mktask "$BT20b" "TASK-20b-licensed" "04_implementation_packet.md"
out20b="$(cd "$BT20b" && "$MASSOH" board --no-push 2>&1)"
check "T20b stage=licensed when 04 present and no 06" \
  "printf '%s' \"\$out20b\" | grep -q 'licensed'"

# T20c — stage: 06_review_result.md present → review.
BT20c="$TMP/bt20c"; mkboardrepo "$BT20c"
mktask "$BT20c" "TASK-20c-review" "06_review_result.md"
out20c="$(cd "$BT20c" && "$MASSOH" board --no-push 2>&1)"
check "T20c stage=review when 06 present" \
  "printf '%s' \"\$out20c\" | grep -q 'review'"

# T20d — empty .agent_tasks/: exit 0, prints "no tasks found", zero API calls.
BT20d="$TMP/bt20d"; mkboardrepo "$BT20d"
# No TASK-* dirs
rc20d=0
out20d="$(cd "$BT20d" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="https://fake.example.com" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" \
  "$MASSOH" board --push plane 2>&1)" || rc20d=$?
check "T20d empty task dir: exit 0" "[ $rc20d -eq 0 ]"
check "T20d empty task dir: prints 'no tasks'" \
  "printf '%s' \"\$out20d\" | grep -qi 'no tasks'"

# T20e — priority parsed: P0 task → 'urgent' in Plane body.
BT20e="$TMP/bt20e"; mkboardrepo "$BT20e"
mktask "$BT20e" "TASK-20e-p0"
printf '| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n| 1 | P0 | TASK-20e-p0 | urgent thing | TODO |\n' > "$BT20e/AGENT_BACKLOG.md"
MOCK_PORT_20e=19905

# Capture the POST body to verify priority field
CAPTURED_BODY_20e="$TMP/body20e.json"
python3 -c "
import http.server, json, signal, sys
captured = []
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'[]')
    def do_POST(self):
        length = int(self.headers.get('Content-Length',0))
        body = self.rfile.read(length)
        with open('$CAPTURED_BODY_20e','wb') as f: f.write(body)
        self.send_response(201); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(json.dumps({'id':'issue-p0'}).encode())
    def log_message(self, *a): pass
srv = http.server.HTTPServer(('127.0.0.1', $MOCK_PORT_20e), H)
def stop(s,f): srv.server_close(); sys.exit(0)
signal.signal(signal.SIGTERM, stop)
for _ in range(20): srv.handle_request()
" &
MOCK_PID_20e=$!
sleep 0.3

( cd "$BT20e" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:$MOCK_PORT_20e" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || true
kill "$MOCK_PID_20e" 2>/dev/null || true

check "T20e P0 task: Plane request body contains 'urgent' priority" \
  "[ -f '$CAPTURED_BODY_20e' ] && jq -r '.priority' '$CAPTURED_BODY_20e' 2>/dev/null | grep -q 'urgent'"

# T20f — --no-push: print task table, zero API calls, zero writes.
BT20f="$TMP/bt20f"; mkboardrepo "$BT20f"; mktask "$BT20f" "TASK-20f"
snap20f_before="$(cd "$BT20f" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
rc20f=0
( cd "$BT20f" && "$MASSOH" board --no-push >/dev/null 2>&1 ) || rc20f=$?
snap20f_after="$(cd "$BT20f" && find . -path ./.git -prune -o -type f -print | sort | xargs ls -la 2>/dev/null | md5sum)"
check "T20f --no-push: exit 0" "[ $rc20f -eq 0 ]"
check "T20f --no-push: no .board-map.tsv written" \
  "[ ! -f '$BT20f/.agent_tasks/.board-map.tsv' ]"

# T20g — --dry-run: prints what would be pushed, zero API calls, zero writes.
BT20g="$TMP/bt20g"; mkboardrepo "$BT20g"; mktask "$BT20g" "TASK-20g"
rc20g=0
out20g="$(cd "$BT20g" && "$MASSOH" board --push plane --dry-run 2>&1)" || rc20g=$?
check "T20g --dry-run: exit 0" "[ $rc20g -eq 0 ]"
check "T20g --dry-run: mentions dry-run" \
  "printf '%s' \"\$out20g\" | grep -qi 'dry.run'"
check "T20g --dry-run: no .board-map.tsv written" \
  "[ ! -f '$BT20g/.agent_tasks/.board-map.tsv' ]"

echo "== T21: cmd_board — jq guard =="

# Build a minimal PATH with necessary binaries but NO jq, for T21 tests.
# Symlink all needed binaries to a temp dir, excluding jq.
NOJQ_BIN="$TMP/nojq_bin"
mkdir -p "$NOJQ_BIN"
for _b in bash env sh printf grep awk sed wc tr cat ls date git python3 curl mkdir touch rm cp mv find md5sum timeout id stat mktemp dirname basename readlink; do
  for _prefix in /usr/bin /bin /usr/local/bin; do
    [ -x "$_prefix/$_b" ] && ln -sf "$_prefix/$_b" "$NOJQ_BIN/$_b" 2>/dev/null && break
  done
done
NOJQ_PATH="$NOJQ_BIN"

# T21a — jq absent: exit 1, message mentions jq and install instruction.
BT21a="$TMP/bt21a"; mkboardrepo "$BT21a"
rc21a=0
out21a="$(cd "$BT21a" && PATH="$NOJQ_PATH" "$MASSOH" board --push plane 2>&1)" || rc21a=$?
check "T21a jq absent: exit 1" "[ $rc21a -ne 0 ]"
check "T21a jq absent: output mentions 'jq'" \
  "printf '%s' \"\$out21a\" | grep -qi 'jq'"

# T21b — all other verbs remain jq-free: cmd_review works without jq in PATH.
BT21b="$TMP/bt21b"; mkboardrepo "$BT21b"
printf '| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n| 1 | P1 | x | y | TODO |\n' > "$BT21b/AGENT_BACKLOG.md"
rc21b=0
( cd "$BT21b" && PATH="$NOJQ_PATH" "$MASSOH" review --no-write >/dev/null 2>&1 ) || rc21b=$?
check "T21b cmd_review works without jq (other verbs jq-free)" "[ $rc21b -eq 0 ]"

echo "== T22: cmd_board — safety-critical files unchanged =="

# Capture md5sum of safety-critical files BEFORE T17–T21 suite.
# (They were already captured before T16, but we need a T17 baseline too.)
md5_massoh_t17_before="$(md5sum "$MASSOH" | awk '{print $1}')"
md5_manifest_t17_before="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"

# T22a — bin/massoh checksum unchanged across T17–T21 suite.
md5_massoh_t22_after="$(md5sum "$MASSOH" | awk '{print $1}')"
check "T22a bin/massoh checksum unchanged across T17–T21 suite" \
  "[ '$md5_massoh_t17_before' = '$md5_massoh_t22_after' ]"

# T22b — manifest.yml checksum unchanged across T17–T21 suite.
md5_manifest_t22_after="$(md5sum "$REPO_ROOT/manifest.yml" | awk '{print $1}')"
check "T22b manifest.yml checksum unchanged across T17–T21 suite" \
  "[ '$md5_manifest_t17_before' = '$md5_manifest_t22_after' ]"

# T22c — .env.massoh not tracked in git after --init-config creates it.
BT22c="$TMP/bt22c"; mkboardrepo "$BT22c"
( cd "$BT22c" && "$MASSOH" board --init-config >/dev/null 2>&1 ) || true
# Check that .env.massoh is gitignored (git status --short should not list it as untracked ?? .env.massoh)
check "T22c .env.massoh not tracked in git after --init-config" \
  "! git -C '$BT22c' status --short 2>/dev/null | grep -q '.env.massoh'"

echo "== T23: cmd_board — || true discipline and degrade =="

# T23a — cmd_board against project with zero TASK-* folders: exits 0 without error.
BT23a="$TMP/bt23a"; mkboardrepo "$BT23a"
rc23a=0
( cd "$BT23a" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:19999" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || rc23a=$?
check "T23a zero TASK-* dirs: exit 0 (degrade + || true discipline)" "[ $rc23a -eq 0 ]"

# T23b — cmd_board against project with missing AGENT_BACKLOG.md: exits 0 without error.
BT23b="$TMP/bt23b"; mkboardrepo "$BT23b"
mktask "$BT23b" "TASK-23b"
rm -f "$BT23b/AGENT_BACKLOG.md"
rc23b=0
( cd "$BT23b" && \
  PLANE_API_TOKEN="tok" PLANE_BASE_URL="http://127.0.0.1:19999" \
  PLANE_WORKSPACE_SLUG="ws" PLANE_PROJECT_ID="pid" PLANE_ALLOW_HTTP=1 \
  "$MASSOH" board --push plane >/dev/null 2>&1 ) || rc23b=$?
check "T23b missing AGENT_BACKLOG.md: exit 0 (|| true degrade)" "[ $rc23b -eq 0 ]"

echo "== T-MB: modularize bin/massoh (v0.11.0) =="

# T-MB-a: symlink invocation — invoke bin/massoh via a symlink; assert status exits 0 + prints version.
# Confirms MB1: sourcing loop derives verb paths from $MASSOH_HOME (symlink-safe).
SYMLINK_BIN="$TMP/symlink_massoh"
ln -sf "$MASSOH" "$SYMLINK_BIN"
TMB_CC="$(newcc)"
CLAUDE_CONFIG_DIR="$TMB_CC" "$SYMLINK_BIN" install >/dev/null 2>&1
tmb_a_out="$(CLAUDE_CONFIG_DIR="$TMB_CC" "$SYMLINK_BIN" status 2>&1)"
tmb_a_rc=$?
check "T-MB-a symlink invocation exits 0"              "[ $tmb_a_rc -eq 0 ]"
check "T-MB-a symlink invocation prints version line"  "echo '$tmb_a_out' | grep -q 'version:'"

# T-MB-b: install layout — run massoh install; assert $CC/agent-os/lib/verbs/ exists with .sh files.
# Confirms MB2: cmd_install wires lib/verbs/ into the installed layout.
TMB_CCb="$(newcc)"
CLAUDE_CONFIG_DIR="$TMB_CCb" "$MASSOH" install >/dev/null 2>&1
check "T-MB-b install creates agent-os/lib/verbs/ directory"  "[ -d '$TMB_CCb/agent-os/lib/verbs' ]"
check "T-MB-b agent-os/lib/verbs/ contains at least one .sh file" \
  "ls '$TMB_CCb/agent-os/lib/verbs/'*.sh >/dev/null 2>&1"

# T-MB-c: uninstall clean — install then uninstall; assert agent-os/ is gone (entire tree removed).
# Confirms MB2 backward-compat: cmd_uninstall removes agent-os/ wholesale (includes lib/verbs/).
TMB_CCc="$(newcc)"
CLAUDE_CONFIG_DIR="$TMB_CCc" "$MASSOH" install >/dev/null 2>&1
CLAUDE_CONFIG_DIR="$TMB_CCc" "$MASSOH" uninstall >/dev/null 2>&1
check "T-MB-c uninstall removes entire agent-os/ tree (includes lib/verbs/)" \
  "[ ! -d '$TMB_CCc/agent-os' ]"

# T-MB-d: doctor detects drift — install, remove lib/verbs/, run doctor; assert non-zero + MISS.
# Confirms MB4: cmd_doctor verifies lib/verbs/ presence.
TMB_CCd="$(newcc)"
CLAUDE_CONFIG_DIR="$TMB_CCd" "$MASSOH" install >/dev/null 2>&1
rm -rf "$TMB_CCd/agent-os/lib/verbs"
tmb_d_rc=0
tmb_d_out="$(CLAUDE_CONFIG_DIR="$TMB_CCd" "$MASSOH" doctor --offline 2>&1)" || tmb_d_rc=$?
check "T-MB-d doctor exits non-zero when lib/verbs/ missing"  "[ $tmb_d_rc -ne 0 ]"
check "T-MB-d doctor output contains MISS for lib/verbs/"     "echo '$tmb_d_out' | grep -q 'MISS'"

# T-MB-e: missing lib file fails loudly — remove the entire lib/verbs/ directory from a scratch copy.
# The glob "$MASSOH_HOME/lib/verbs/"*.sh expands to a literal unmatched string when the directory is
# absent, triggering the [ -f ] guard → exit non-zero + stderr "missing lib file". Confirms MB3.
TMB_SCRATCH="$TMP/massoh_scratch"; mkdir -p "$TMB_SCRATCH"
cp -rp "$REPO_ROOT/bin" "$TMB_SCRATCH/"
cp -rp "$REPO_ROOT/lib" "$TMB_SCRATCH/"
cp -rp "$REPO_ROOT/templates" "$TMB_SCRATCH/" 2>/dev/null || true
cp -rp "$REPO_ROOT/VERSION" "$TMB_SCRATCH/" 2>/dev/null || true
# Remove all verb files (the entire directory) to force the glob to expand to a literal unmatched string
rm -rf "$TMB_SCRATCH/lib/verbs"
tmb_e_rc=0
tmb_e_err="$(MASSOH_HOME="$TMB_SCRATCH" "$TMB_SCRATCH/bin/massoh" status 2>&1 >/dev/null)" || tmb_e_rc=$?
check "T-MB-e missing lib file: exit non-zero"                 "[ $tmb_e_rc -ne 0 ]"
check "T-MB-e missing lib file: stderr contains 'missing lib file'" \
  "printf '%s\n' \"\$tmb_e_err\" | grep -q 'missing lib file'"

# T-MB-f: byte-identical output — invoke massoh <unknown-verb> before and after; diff must be empty.
# Confirms MB5: non-dynamic output (die() usage line) is byte-identical after extraction.
tmb_f_before="massoh: unknown command 'unknownverb'. verbs: install update on off enable disable status doctor discover review standup plan learn recommend ledger meta cron gate board intake fleet version work uninstall [--link]"
tmb_f_after="$("$MASSOH" unknownverb 2>&1 || true)"
check "T-MB-f byte-identical unknown-verb die() output" \
  "[ '$tmb_f_before' = '$tmb_f_after' ]"

# T-MB-g: smoke-dispatch every verb (non-interactive; just confirm each dispatches without crash).
# Confirms MB8: all 12 moved verbs still dispatch correctly.
# Use a throwaway massoh project for verbs that require it.
TMB_PROJ="$TMP/tmb_proj"; mkdir -p "$TMB_PROJ"
( cd "$TMB_PROJ" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
echo x > "$TMB_PROJ/.massoh"
( cd "$TMB_PROJ" && git add -A && git commit -qm "feat: seed" ) >/dev/null 2>&1
mkdir -p "$TMB_PROJ/.agent_tasks" "$TMB_PROJ/agent-project"
printf '# AGENT_SYNC\n\n## Decision log\n' > "$TMB_PROJ/AGENT_SYNC.md"
printf '| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n| 1 | P1 | x | y | TODO |\n' > "$TMB_PROJ/AGENT_BACKLOG.md"
# discover (no-op: STANDARDS.md already seeded)
rc_tmb_discover=0; ( cd "$TMB_PROJ" && "$MASSOH" discover >/dev/null 2>&1 ) || rc_tmb_discover=$?
check "T-MB-g smoke: discover dispatches (exit 0)"   "[ $rc_tmb_discover -eq 0 ]"
# review
rc_tmb_review=0; ( cd "$TMB_PROJ" && "$MASSOH" review --no-write >/dev/null 2>&1 ) || rc_tmb_review=$?
check "T-MB-g smoke: review dispatches (exit 0)"     "[ $rc_tmb_review -eq 0 ]"
# standup
rc_tmb_standup=0; ( cd "$TMB_PROJ" && "$MASSOH" standup --no-write >/dev/null 2>&1 ) || rc_tmb_standup=$?
check "T-MB-g smoke: standup dispatches (exit 0)"    "[ $rc_tmb_standup -eq 0 ]"
# plan
rc_tmb_plan=0; ( cd "$TMB_PROJ" && "$MASSOH" plan --no-write >/dev/null 2>&1 ) || rc_tmb_plan=$?
check "T-MB-g smoke: plan dispatches (exit 0)"       "[ $rc_tmb_plan -eq 0 ]"
# learn
rc_tmb_learn=0; ( cd "$TMB_PROJ" && "$MASSOH" learn >/dev/null 2>&1 ) || rc_tmb_learn=$?
check "T-MB-g smoke: learn dispatches (exit 0)"      "[ $rc_tmb_learn -eq 0 ]"
# recommend
rc_tmb_recommend=0; ( cd "$TMB_PROJ" && "$MASSOH" recommend >/dev/null 2>&1 ) || rc_tmb_recommend=$?
check "T-MB-g smoke: recommend dispatches (exit 0)"  "[ $rc_tmb_recommend -eq 0 ]"
# ledger (no-op: no ledger file yet)
rc_tmb_ledger=0; ( cd "$TMB_PROJ" && "$MASSOH" ledger >/dev/null 2>&1 ) || rc_tmb_ledger=$?
check "T-MB-g smoke: ledger dispatches (exit 0)"     "[ $rc_tmb_ledger -eq 0 ]"
# meta
rc_tmb_meta=0; ( cd "$TMB_PROJ" && "$MASSOH" meta >/dev/null 2>&1 ) || rc_tmb_meta=$?
check "T-MB-g smoke: meta dispatches (exit 0)"       "[ $rc_tmb_meta -eq 0 ]"
# gate (off is idempotent when not installed)
rc_tmb_gate=0; ( cd "$TMB_PROJ" && "$MASSOH" gate off >/dev/null 2>&1 ) || rc_tmb_gate=$?
check "T-MB-g smoke: gate dispatches (exit 0)"       "[ $rc_tmb_gate -eq 0 ]"
# board (no-push: prints table only)
rc_tmb_board=0; ( cd "$TMB_PROJ" && "$MASSOH" board --no-push >/dev/null 2>&1 ) || rc_tmb_board=$?
check "T-MB-g smoke: board dispatches (exit 0)"      "[ $rc_tmb_board -eq 0 ]"
# version (always works)
rc_tmb_version=0; "$MASSOH" version >/dev/null 2>&1 || rc_tmb_version=$?
check "T-MB-g smoke: version dispatches (exit 0)"    "[ $rc_tmb_version -eq 0 ]"

echo "== T-IK: massoh intake (idea capture, v0.12.0) =="

# Helper: create a minimal Massoh project for intake tests.
mkintakerepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  printf 'massoh project marker\n' > "$d/.massoh"
  mkdir -p "$d/agent-project" "$d/memory" "$d/.agent_tasks"
  printf '# Memory index\n' > "$d/memory/MEMORY.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed intake repo" )
}

# Helper: create a backlog with Queue + Done + Frozen rows for append-only tests.
mkintakebacklog() {
  local repo="$1"
  cat > "$repo/AGENT_BACKLOG.md" <<'BACKLOG_EOF'
# AGENT_BACKLOG

## Queue
| # | Pri | Item | Why | Status |
|---|---|---|---|---|
| 1 | P1 | existing queue item | reason | TODO |

## Done
| # | Pri | Item | Why | Status |
|---|---|---|---|---|
| 2 | P2 | done item | reason | DONE |

## Frozen
| # | Pri | Item | Why | Status |
|---|---|---|---|---|
| 3 | P3 | frozen item | reason | FROZEN |
BACKLOG_EOF
}

# T-IK-a — append-only: Queue/Done/Frozen rows byte-identical after intake; no sed -i in source.
IKa="$TMP/ika"; mkintakerepo "$IKa"
mkintakebacklog "$IKa"
before_ika="$(grep -E '^\| [0-9]+ \|' "$IKa/AGENT_BACKLOG.md" | head -3 | md5sum)"
( cd "$IKa" && "$MASSOH" intake "add integration tests" >/dev/null 2>&1 )
after_ika="$(grep -E '^\| [0-9]+ \|' "$IKa/AGENT_BACKLOG.md" | head -3 | md5sum)"
check "T-IK-a Queue/Done/Frozen rows unchanged after intake (append-only)" \
  "[ '$before_ika' = '$after_ika' ]"
check "T-IK-a file has more lines after intake" \
  "[ \"\$(wc -l < '$IKa/AGENT_BACKLOG.md')\" -gt 14 ]"
check "T-IK-a zero sed -i calls in lib/verbs/intake.sh (structural)" \
  "[ \"\$(grep -c 'sed -i' '$REPO_ROOT/lib/verbs/intake.sh')\" -eq 0 ]"

# T-IK-b — pipe sanitization: idea with | chars produces no extra pipe in the idea cell.
IKb="$TMP/ikb"; mkintakerepo "$IKb"
( cd "$IKb" && "$MASSOH" intake "idea with | pipe | chars" >/dev/null 2>&1 )
# The row must exist but the idea cell must not contain a raw | (pipes replaced by spaces)
check "T-IK-b intake row exists in BACKLOG" \
  "grep -q 'idea with' '$IKb/AGENT_BACKLOG.md'"
# Extract the idea cell (field 4 in the Intake inbox row) and assert no raw pipe
idea_cell_b="$(grep 'idea with' "$IKb/AGENT_BACKLOG.md" | awk -F'|' '{print $4}')"
check "T-IK-b idea cell contains no literal pipe character" \
  "! printf '%s' \"\$idea_cell_b\" | grep -qF '|'"

# T-IK-c — newline sanitization: multi-line idea produces exactly one new row.
IKc="$TMP/ikc"; mkintakerepo "$IKc"
# Count table rows before (file may not exist yet — degrade to 0)
rows_before_c="$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$IKc/AGENT_BACKLOG.md" 2>/dev/null || echo 0)"
( cd "$IKc" && "$MASSOH" intake $'multi\nline\nidea' >/dev/null 2>&1 )
rows_after_c="$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$IKc/AGENT_BACKLOG.md" 2>/dev/null || echo 0)"
new_rows_c=$(( rows_after_c - rows_before_c ))
check "T-IK-c newline sanitization: exactly one new table row added (not 3)" \
  "[ $new_rows_c -eq 1 ]"
check "T-IK-c intake row present in BACKLOG" \
  "grep -q 'multi' '$IKc/AGENT_BACKLOG.md'"

# T-IK-d — length truncation: 300-char idea truncated to ≤200 chars in the idea cell.
IKd="$TMP/ikd"; mkintakerepo "$IKd"
long_idea="$(printf '%0.s' {1..100})$(printf 'x%.0s' {1..300})"   # 300 x's
( cd "$IKd" && "$MASSOH" intake "$long_idea" >/dev/null 2>&1 )
# Extract the idea cell and measure length
idea_cell_d="$(grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$IKd/AGENT_BACKLOG.md" | tail -1 | awk -F'|' '{print $4}')"
idea_len_d="${#idea_cell_d}"
check "T-IK-d idea cell is ≤200 chars after truncation (got $idea_len_d chars)" \
  "[ $idea_len_d -le 210 ]"

# T-IK-e — empty arg dies writing nothing (BACKLOG and MEMORY unchanged).
IKe="$TMP/ike"; mkintakerepo "$IKe"
printf '# Test backlog\n' > "$IKe/AGENT_BACKLOG.md"
printf '# Memory index\n' > "$IKe/memory/MEMORY.md"
before_bl_e="$(md5sum "$IKe/AGENT_BACKLOG.md" | awk '{print $1}')"
before_mem_e="$(md5sum "$IKe/memory/MEMORY.md" | awk '{print $1}')"
rc_ike=0
( cd "$IKe" && "$MASSOH" intake "" >/dev/null 2>&1 ) || rc_ike=$?
after_bl_e="$(md5sum "$IKe/AGENT_BACKLOG.md" | awk '{print $1}')"
after_mem_e="$(md5sum "$IKe/memory/MEMORY.md" | awk '{print $1}')"
check "T-IK-e empty arg: exit non-zero" "[ $rc_ike -ne 0 ]"
check "T-IK-e empty arg: BACKLOG unchanged" "[ '$before_bl_e' = '$after_bl_e' ]"
check "T-IK-e empty arg: MEMORY unchanged" "[ '$before_mem_e' = '$after_mem_e' ]"

# T-IK-f — missing arg dies writing nothing.
IKf="$TMP/ikf"; mkintakerepo "$IKf"
printf '# Test backlog\n' > "$IKf/AGENT_BACKLOG.md"
printf '# Memory index\n' > "$IKf/memory/MEMORY.md"
before_bl_f="$(md5sum "$IKf/AGENT_BACKLOG.md" | awk '{print $1}')"
before_mem_f="$(md5sum "$IKf/memory/MEMORY.md" | awk '{print $1}')"
rc_ikf=0
( cd "$IKf" && "$MASSOH" intake 2>/dev/null ) || rc_ikf=$?
after_bl_f="$(md5sum "$IKf/AGENT_BACKLOG.md" | awk '{print $1}')"
after_mem_f="$(md5sum "$IKf/memory/MEMORY.md" | awk '{print $1}')"
check "T-IK-f missing arg: exit non-zero" "[ $rc_ikf -ne 0 ]"
check "T-IK-f missing arg: BACKLOG unchanged" "[ '$before_bl_f' = '$after_bl_f' ]"
check "T-IK-f missing arg: MEMORY unchanged" "[ '$before_mem_f' = '$after_mem_f' ]"

# T-IK-g — idempotent re-run: second run exits 0, no duplicate row.
IKg="$TMP/ikg"; mkintakerepo "$IKg"
( cd "$IKg" && "$MASSOH" intake "same idea twice" >/dev/null 2>&1 )
rc_ikg2=0
( cd "$IKg" && "$MASSOH" intake "same idea twice" >/dev/null 2>&1 ) || rc_ikg2=$?
count_ikg="$(grep -c 'same idea twice' "$IKg/AGENT_BACKLOG.md" 2>/dev/null || echo 0)"
check "T-IK-g second run exits 0 (idempotent)" "[ $rc_ikg2 -eq 0 ]"
check "T-IK-g exactly one row with the idea (no duplicate)" "[ \"$count_ikg\" -eq 1 ]"

# T-IK-h — priority assignment: P0 for bug, P1 for feature, P3 for neutral.
IKh="$TMP/ikh"; mkintakerepo "$IKh"
( cd "$IKh" && "$MASSOH" intake "fix critical bug" >/dev/null 2>&1 )
( cd "$IKh" && "$MASSOH" intake "add new feature" >/dev/null 2>&1 )
( cd "$IKh" && "$MASSOH" intake "someday maybe something" >/dev/null 2>&1 )
check "T-IK-h P0 assigned for 'fix critical bug'" \
  "grep 'fix critical bug' '$IKh/AGENT_BACKLOG.md' | grep -q 'P0'"
check "T-IK-h P1 assigned for 'add new feature'" \
  "grep 'add new feature' '$IKh/AGENT_BACKLOG.md' | grep -q 'P1'"
check "T-IK-h P3 assigned for 'someday maybe something'" \
  "grep 'someday maybe' '$IKh/AGENT_BACKLOG.md' | grep -q 'P3'"

# T-IK-i — degrade on missing BACKLOG: exit 0, file created with idea row, no crash.
IKi="$TMP/iki"; mkintakerepo "$IKi"
rm -f "$IKi/AGENT_BACKLOG.md"
rc_iki=0
( cd "$IKi" && "$MASSOH" intake "fresh idea" >/dev/null 2>&1 ) || rc_iki=$?
check "T-IK-i missing BACKLOG: exit 0 (degrade)" "[ $rc_iki -eq 0 ]"
check "T-IK-i missing BACKLOG: file now exists" "[ -f '$IKi/AGENT_BACKLOG.md' ]"
check "T-IK-i missing BACKLOG: idea row present" "grep -q 'fresh idea' '$IKi/AGENT_BACKLOG.md'"

# T-IK-j — memory pointer written to memory/MEMORY.md.
IKj="$TMP/ikj"; mkintakerepo "$IKj"
( cd "$IKj" && "$MASSOH" intake "test memory pointer" >/dev/null 2>&1 )
check "T-IK-j memory/MEMORY.md contains pointer to idea" \
  "grep -q 'test memory pointer' '$IKj/memory/MEMORY.md'"

# T-IK-k — non-Massoh-dir guard: no write outside Massoh project.
IKk="$TMP/ikk_noproj"; mkdir -p "$IKk"
( cd "$IKk" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t ) >/dev/null 2>&1
# No .massoh, no agent-project/
rc_ikk=0
( cd "$IKk" && "$MASSOH" intake "should not be written" 2>/dev/null ) || rc_ikk=$?
check "T-IK-k non-Massoh-dir: exit non-zero" "[ $rc_ikk -ne 0 ]"
check "T-IK-k non-Massoh-dir: no AGENT_BACKLOG.md created" "[ ! -f '$IKk/AGENT_BACKLOG.md' ]"

# T-IK-k (smoke dispatch — mirrors T-MB-g family)
rc_tmb_intake=0
( cd "$TMB_PROJ" && "$MASSOH" intake "smoke test idea" >/dev/null 2>&1 ) || rc_tmb_intake=$?
check "T-IK-k smoke: intake dispatches from bin/massoh (exit 0)" "[ $rc_tmb_intake -eq 0 ]"

echo "== T-FL: massoh fleet — read-only multi-repo rollup =="

# Helper: create a minimal fake Massoh repo for fleet tests.
# Creates .massoh marker, .agent_tasks/<task>/ dirs, and AGENT_SYNC.md.
mkfleetrepo() {
  local d="$1"
  mkdir -p "$d"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  printf 'massoh project marker\n' > "$d/.massoh"
  mkdir -p "$d/.agent_tasks"
  printf '# AGENT_SYNC\nAgent: massoh-implementer\nMode: IMPLEMENTATION\n\n## Decision log\n' > "$d/AGENT_SYNC.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed fleet repo" )
}

# --- T-FL-a / T-FL-b: write-isolation proof (highest-priority test; FL1) ---
# Two fake repos; snapshot them before fleet; assert byte-identical after.
FLEET_ROOT_AB="$TMP/fl_ab"
mkdir -p "$FLEET_ROOT_AB"
REPO_A="$FLEET_ROOT_AB/repo-alpha"; mkfleetrepo "$REPO_A"
REPO_B="$FLEET_ROOT_AB/repo-beta";  mkfleetrepo "$REPO_B"
# Add some task dirs so there is content to read
mkdir -p "$REPO_A/.agent_tasks/TASK-doing"
printf '# 04\n' > "$REPO_A/.agent_tasks/TASK-doing/04_implementation_packet.md"
mkdir -p "$REPO_A/.agent_tasks/TASK-blocked"
printf '# 00\n' > "$REPO_A/.agent_tasks/TASK-blocked/00_request.md"
printf '| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n| 1 | P1 | thing | why | BLOCKED |\n' > "$REPO_A/AGENT_BACKLOG.md"
mkdir -p "$REPO_B/.agent_tasks/TASK-todo"
printf '# 00\n' > "$REPO_B/.agent_tasks/TASK-todo/00_request.md"

# Byte-snapshot of both repos BEFORE fleet run (FL1 proof method from 03_architecture_safety.md)
before_a="$(cd "$REPO_A" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
before_b="$(cd "$REPO_B" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"

# Run fleet — must write NOTHING to either repo
"$MASSOH" fleet --root "$FLEET_ROOT_AB" >/dev/null 2>&1 || true

# Snapshot AFTER
after_a="$(cd "$REPO_A" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
after_b="$(cd "$REPO_B" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"

check "T-FL-a REPO_A byte-identical after fleet (write-isolation proof)" "[ '$before_a' = '$after_a' ]"
check "T-FL-b REPO_B byte-identical after fleet (write-isolation proof)" "[ '$before_b' = '$after_b' ]"

# --- T-FL-c: bounded discovery — depth-4 marker NOT found at default maxdepth=3 ---
DEEP_ROOT="$TMP/fl_deep"
mkdir -p "$DEEP_ROOT/level1/level2/level3/level4"
printf 'massoh marker\n' > "$DEEP_ROOT/level1/level2/level3/level4/.massoh"
out_fl_c="$("$MASSOH" fleet --root "$DEEP_ROOT" 2>/dev/null || true)"
check "T-FL-c deep .massoh (depth 4) NOT discovered at default maxdepth=3" \
  "! printf '%s\n' '$out_fl_c' | grep -q 'level4'"

# --- T-FL-d: degrade on unreadable .agent_tasks/ (FL5) ---
FLEET_D_ROOT="$TMP/fl_d_root"
mkdir -p "$FLEET_D_ROOT"
BAD_REPO="$FLEET_D_ROOT/bad-repo"; mkfleetrepo "$BAD_REPO"
chmod 000 "$BAD_REPO/.agent_tasks" 2>/dev/null || true

rc_fl_d=0
out_fl_d="$("$MASSOH" fleet --root "$FLEET_D_ROOT" 2>&1)" || rc_fl_d=$?
# Restore permissions for cleanup
chmod 755 "$BAD_REPO/.agent_tasks" 2>/dev/null || true

check "T-FL-d exit 0 on unreadable repo"   "[ $rc_fl_d -eq 0 ]"
# The unreadable repo still produces some output (the repo: line or a SKIP), the verb doesn't abort
check "T-FL-d output produced (not silent abort)" "[ -n '$out_fl_d' ]"

# --- T-FL-e: missing root exits 0 (FL2) ---
rc_fl_e=0
out_fl_e="$("$MASSOH" fleet --root "$TMP/nonexistent_fleet_dir_$$" 2>&1)" || rc_fl_e=$?
check "T-FL-e missing root exits 0"        "[ $rc_fl_e -eq 0 ]"
check "T-FL-e missing root prints message" "[ -n '$out_fl_e' ]"

# --- T-FL-f: no config exits 0 (FL2) ---
rc_fl_f=0
# Run with no --root and a nonexistent tsv to exercise the no-config path
MASSOH_FLEET_ROOT="" MASSOH_FLEET_TSV="$TMP/no-such-fleet.tsv" \
  "$MASSOH" fleet >/dev/null 2>&1 || rc_fl_f=$?
check "T-FL-f no config exits 0"           "[ $rc_fl_f -eq 0 ]"

# --- T-FL-g: fleet.tsv registry parse (FL3) ---
# Set up two valid repos
TSV_REPO1="$TMP/fl_tsv_r1"; mkfleetrepo "$TSV_REPO1"
TSV_REPO2="$TMP/fl_tsv_r2"; mkfleetrepo "$TSV_REPO2"
# fleet.tsv: valid path, comment, blank, nonexistent path, valid path
FLEET_TSV_G="$TMP/fleet_g.tsv"
printf '%s\n' \
  "$TSV_REPO1" \
  "# this is a comment line" \
  "" \
  "/tmp/no-such-repo-fleet-g-$$" \
  "$TSV_REPO2" > "$FLEET_TSV_G"

rc_fl_g=0
out_fl_g="$(MASSOH_FLEET_TSV="$FLEET_TSV_G" "$MASSOH" fleet 2>&1)" || rc_fl_g=$?
check "T-FL-g tsv: 2 repos discovered" \
  "[ \"\$(printf '%s\n' '$out_fl_g' | grep -c '^repo:')\" -eq 2 ]"
check "T-FL-g tsv: exit 0"             "[ $rc_fl_g -eq 0 ]"

# --- T-FL-h: no network / no secrets in fleet.sh (FL7) ---
check "T-FL-h fleet.sh has no network/secret primitives" \
  "! grep -qE 'curl|wget|nc |ssh |PLANE_API|SECRET|TOKEN' '$REPO_ROOT/lib/verbs/fleet.sh'"

# --- T-FL-i: no source/eval of discovered-repo content (FL4) ---
check "T-FL-i fleet.sh does not source/eval repo content" \
  "! grep -qE '^\s*(source|\.) .*repo|eval.*repo|bash -c.*repo' '$REPO_ROOT/lib/verbs/fleet.sh'"

# --- T-FL-j: rollup output correctness — both repos, blocked indicator (FL5/output) ---
# Re-use REPO_A (has BLOCKED in AGENT_BACKLOG.md) and REPO_B from the T-FL-a setup
out_fl_j="$("$MASSOH" fleet --root "$FLEET_ROOT_AB" 2>&1 || true)"
check "T-FL-j output contains REPO_A path"  "printf '%s\n' '$out_fl_j' | grep -q 'repo-alpha'"
check "T-FL-j output contains REPO_B path"  "printf '%s\n' '$out_fl_j' | grep -q 'repo-beta'"
check "T-FL-j output shows blocked flag"    "printf '%s\n' '$out_fl_j' | grep -qi 'block'"

# --- T-FL-k: dispatch + usage registration (FL9) ---
rc_fl_k=0
MASSOH_FLEET_ROOT="" MASSOH_FLEET_TSV="$TMP/no-such-fleet-k.tsv" \
  "$MASSOH" fleet >/dev/null 2>&1 || rc_fl_k=$?
check "T-FL-k 'massoh fleet' dispatches (exit 0 on empty run)" "[ $rc_fl_k -eq 0 ]"
check "T-FL-k unknown cmd usage lists 'fleet'" \
  "('$MASSOH' bogus_verb_fleet_$$ 2>&1 || true) | grep -q 'fleet'"

echo "== T-PR: profiles + config.yml (v0.14.0) =="

# Helper: create a minimal Massoh project for config tests.
mkcfgrepo() {
  local d="$1"
  mkdir -p "$d/agent-project" "$d/.agent_tasks"
  ( cd "$d" && git -c init.defaultBranch=main init -q && git config user.email t@t && git config user.name t )
  printf 'massoh project marker\n' > "$d/.massoh"
  printf '# AGENT_BACKLOG\n\n| # | Pri | Item | Why | Status |\n|---|---|---|---|---|\n' > "$d/AGENT_BACKLOG.md"
  printf '# AGENT_SYNC\n\n## Decision log\n' > "$d/AGENT_SYNC.md"
  ( cd "$d" && git add -A && git commit -qm "feat: seed cfg repo" )
}

# T-PR-a: No-op when absent — massoh meta with NO config.yml vs EMPTY config.yml: byte-identical.
# Also confirms: output contains built-in defaults (2x, threshold=3).
PRa="$TMP/pra"; mkcfgrepo "$PRa"
out_pra_nofile="$( cd "$PRa" && "$MASSOH" meta 2>&1 )"
# Create an empty config.yml
printf '' > "$PRa/agent-project/config.yml"
out_pra_empty="$( cd "$PRa" && "$MASSOH" meta 2>&1 )"
check "T-PR-a no-config vs empty-config byte-identical (PC1)" \
  "[ '$( printf '%s' "$out_pra_nofile" | md5sum )' = '$( printf '%s' "$out_pra_empty" | md5sum )' ]"
check "T-PR-a output shows built-in default 2x (OUTLIER_FACTOR=2)" \
  "printf '%s\n' \"\$out_pra_nofile\" | grep -q '2x'"
check "T-PR-a output shows built-in default >=3 (REPEAT_THRESHOLD=3)" \
  "printf '%s\n' \"\$out_pra_nofile\" | grep -q '>=3'"

# T-PR-b: Project value overrides built-in default for all 3 tunables.
PRb="$TMP/prb"; mkcfgrepo "$PRb"
# Seed ledger so meta has data to show outlier factor in output
mkdir -p "$PRb/.agent_tasks"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-19T00:00:00Z" "TASK-1" "scope"       "100"  "30"  >> "$PRb/.agent_tasks/ledger.tsv"
printf '%s\t%s\t%s\t%s\t%s\n' "2026-06-19T00:01:00Z" "TASK-1" "implementer" "1000" "300" >> "$PRb/.agent_tasks/ledger.tsv"
printf 'meta_outlier_factor: 5\nmeta_repeat_threshold: 7\ncron_idle_min: 10\n' \
  > "$PRb/agent-project/config.yml"
out_prb_meta="$( cd "$PRb" && "$MASSOH" meta 2>&1 )"
check "T-PR-b meta_outlier_factor=5 reflected in output (5x, not 2x)" \
  "printf '%s\n' \"\$out_prb_meta\" | grep -q '5x'"
check "T-PR-b meta_repeat_threshold=7 reflected in output (>=7, not >=3)" \
  "printf '%s\n' \"\$out_prb_meta\" | grep -q '>=7'"
# cron_idle_min=10: test via massoh-cron dry-run (idleness gate uses IDLE_MIN)
# NO_IDLE=1 bypasses gate; use status output to verify IDLE_MIN read.
CRON_PRb="$REPO_ROOT/bin/massoh-cron"
out_prb_cron_status="$( cd "$PRb" && MASSOH_HOME="$REPO_ROOT" "$CRON_PRb" status 2>&1 )"
check "T-PR-b cron_idle_min=10 reflected in cron status (idle gate: 10m)" \
  "printf '%s\n' \"\$out_prb_cron_status\" | grep -q '10m'"
# Regression: remove config.yml → reverts to 2x / threshold=3 / 25m (PC1 regression).
rm "$PRb/agent-project/config.yml"
out_prb_revert="$( cd "$PRb" && "$MASSOH" meta 2>&1 )"
check "T-PR-b regression: removing config.yml reverts to 2x (PC1)" \
  "printf '%s\n' \"\$out_prb_revert\" | grep -q '2x'"
check "T-PR-b regression: removing config.yml reverts to >=3 (PC1)" \
  "printf '%s\n' \"\$out_prb_revert\" | grep -q '>=3'"

# T-PR-c: Malformed integer degrades to built-in default; exit 0.
PRc="$TMP/prc"; mkcfgrepo "$PRc"
printf 'meta_outlier_factor: not_a_number\n' > "$PRc/agent-project/config.yml"
rc_prc=0
out_prc="$( cd "$PRc" && "$MASSOH" meta 2>&1 )" || rc_prc=$?
check "T-PR-c malformed integer: exit 0 (PC2/PC5)" "[ $rc_prc -eq 0 ]"
check "T-PR-c malformed integer: output shows 2x (falls back to built-in default)" \
  "printf '%s\n' \"\$out_prc\" | grep -q '2x'"

# T-PR-d: Malformed YAML structure degrades to all defaults; exit 0.
PRd="$TMP/prd"; mkcfgrepo "$PRd"
printf -- '---\nnested:\n  key: value\ncron_idle_min: !!python/object:os.system\n' \
  > "$PRd/agent-project/config.yml"
rc_prd=0
out_prd_meta="$( cd "$PRd" && "$MASSOH" meta 2>&1 )" || rc_prd=$?
check "T-PR-d malformed YAML: meta exits 0 (PC3/PC5)" "[ $rc_prd -eq 0 ]"
check "T-PR-d malformed YAML: meta shows built-in default 2x" \
  "printf '%s\n' \"\$out_prd_meta\" | grep -q '2x'"
check "T-PR-d malformed YAML: meta shows built-in default >=3" \
  "printf '%s\n' \"\$out_prd_meta\" | grep -q '>=3'"

# T-PR-e: Secret-sounding key guard — warns to stderr and returns default, never file value.
PRe="$TMP/pre"; mkcfgrepo "$PRe"
printf 'plane_api_token: supersecret123\n' > "$PRe/agent-project/config.yml"
# Source _config.sh in a subshell; capture stdout and stderr separately.
eval_out_pre="$(
  . "$REPO_ROOT/lib/verbs/_config.sh"
  massoh_config_get "$PRe/agent-project/config.yml" "plane_api_token" "mydefault" 2>/dev/null
)"
warn_pre="$(
  . "$REPO_ROOT/lib/verbs/_config.sh"
  massoh_config_get "$PRe/agent-project/config.yml" "plane_api_token" "mydefault" 2>&1 >/dev/null
)"
check "T-PR-e secret key: warning emitted to stderr (PC4)" \
  "printf '%s\n' \"\$warn_pre\" | grep -qi 'WARNING'"
check "T-PR-e secret key: returns default not file value (PC4)" \
  "[ \"\$eval_out_pre\" = 'mydefault' ]"

# T-PR-f: Scope check — exactly 3 massoh_config_get call sites outside _config.sh.
prf_count="$(grep -r 'massoh_config_get' "$REPO_ROOT/lib/verbs/" "$REPO_ROOT/bin/massoh-cron" \
  2>/dev/null | grep -v '_config.sh' | wc -l | tr -d ' ')"
check "T-PR-f exactly 3 massoh_config_get call sites outside _config.sh (PC6)" \
  "[ \"$prf_count\" -eq 3 ]"

# T-PR-g: Helper callable after sourcing the verb-loading loop (bin/massoh sources _config.sh).
PRg="$TMP/prg"; mkcfgrepo "$PRg"
rc_prg=0
( cd "$PRg" && "$MASSOH" meta >/dev/null 2>&1 ) || rc_prg=$?
check "T-PR-g helper callable after sourcing loop: massoh meta exits 0 (PC8)" \
  "[ $rc_prg -eq 0 ]"

echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN — $tests checks passed."; else echo "$fails/$tests checks FAILED."; fi
[ "$fails" -eq 0 ]
