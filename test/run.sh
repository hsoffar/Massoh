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

echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN — $tests checks passed."; else echo "$fails/$tests checks FAILED."; fi
[ "$fails" -eq 0 ]
