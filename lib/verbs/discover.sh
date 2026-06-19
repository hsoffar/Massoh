#!/usr/bin/env bash
# massoh verb: discover — mine the current repo's conventions into agent-project/STANDARDS.md
# Sourced by bin/massoh at startup. Requires: say, die, mver, msha, MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# discover — mine the current repo's conventions into agent-project/STANDARDS.md (create-if-missing).
cmd_discover() {
  local repo="$PWD" force=0 a
  for a in "$@"; do [ "$a" = "--force" ] && force=1; done
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } || die "not a Massoh project (run: massoh on)."
  mkdir -p "$repo/agent-project"
  local dest="$repo/agent-project/STANDARDS.md"
  if [ -e "$dest" ] && [ "$force" = 0 ]; then say "massoh discover — keep $dest (exists; --force to refresh)"; return 0; fi
  say "massoh discover → scanning $repo"
  local langs="" testcmd="" commitconv="" layout=""
  [ -f "$repo/package.json" ]   && langs="$langs JavaScript/TypeScript,"
  [ -f "$repo/go.mod" ]         && langs="$langs Go,"
  [ -f "$repo/Cargo.toml" ]     && langs="$langs Rust,"
  { [ -f "$repo/pyproject.toml" ] || [ -f "$repo/requirements.txt" ]; } && langs="$langs Python,"
  { [ -f "$repo/pom.xml" ] || [ -f "$repo/build.gradle" ]; }            && langs="$langs Java/JVM,"
  ls "$repo"/*.sh "$repo"/bin/* >/dev/null 2>&1 && langs="$langs Shell,"
  langs="${langs% }"; langs="${langs%,}"; [ -n "$langs" ] || langs="(none detected — fill in)"
  if [ -f "$repo/package.json" ] && grep -q '"test"' "$repo/package.json" 2>/dev/null; then testcmd="npm test"
  elif [ -f "$repo/Makefile" ] && grep -qiE '^test:' "$repo/Makefile" 2>/dev/null;     then testcmd="make test"
  elif [ -d "$repo/test" ] || [ -d "$repo/tests" ];                                     then testcmd="(test dir present — fill in runner)"
  else testcmd="(none detected — fill in)"; fi
  if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    local conv; conv=$(git -C "$repo" log --pretty=%s -50 2>/dev/null | grep -cE '^(feat|fix|chore|docs|refactor|test|build|ci)(\(.+\))?(!)?:' || true)
    [ "${conv:-0}" -ge 5 ] && commitconv="Conventional Commits (seen in recent history)" || commitconv="(no clear convention — fill in)"
  else commitconv="(not a git repo)"; fi
  layout=$(ls -1 "$repo" 2>/dev/null | grep -vxE '\.git' | head -20 | sed 's/^/  - /')
  sed -e "s|{{LANGS}}|$langs|g" -e "s|{{TESTCMD}}|$testcmd|g" \
      -e "s|{{COMMITCONV}}|$commitconv|g" -e "s|{{DATE}}|$(date +%Y-%m-%d)|g" \
      "$MASSOH_HOME/templates/STANDARDS.template.md" \
    | awk -v L="$layout" '/\{\{LAYOUT\}\}/{print L; next} {print}' > "$dest"
  say "  wrote $dest — review + fill the (…) placeholders."
}
