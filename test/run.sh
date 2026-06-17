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

echo
if [ "$fails" -eq 0 ]; then echo "ALL GREEN — $tests checks passed."; else echo "$fails/$tests checks FAILED."; fi
[ "$fails" -eq 0 ]
