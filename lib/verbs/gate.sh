#!/usr/bin/env bash
# massoh verb: gate — per-repo, opt-in license-to-code gate (installs/removes pre-push hook + CI workflow).
# Sourced by bin/massoh at startup. Requires: say, die, MASSOH_HOME, GATE_MARKER_START, GATE_MARKER_END
# (globals defined in bin/massoh bootstrap before this file is sourced).
# shellcheck source=/dev/null

# gate — per-repo, opt-in license-to-code gate (installs/removes pre-push hook + CI workflow).
# G12: requires git repo AND (.massoh OR agent-project/) before writing anything.
# G3: hook install is create-if-missing; appends Massoh block if hook already exists.
# G4: gate off strips only the massoh-gate:start…end block via awk (mirrors remove_block()).
# G11: both on/off are idempotent (safe to run twice; no-op if already in target state).
cmd_gate() {
  local subcmd="${1:-}"
  case "$subcmd" in
    on)  _gate_on ;;
    off) _gate_off ;;
    *)   die "gate: usage: massoh gate on|off" ;;
  esac
}

_gate_on() {
  local repo
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" \
    || die "gate on: not inside a git repository."
  { [ -e "$repo/.massoh" ] || [ -d "$repo/agent-project" ]; } \
    || die "gate on: not a Massoh project (run: massoh on)."

  say "massoh gate on → $repo"

  # 1. Install pre-push hook (G3: create-if-missing; append-safe with namespace markers).
  local hook="$repo/.git/hooks/pre-push"
  mkdir -p "$repo/.git/hooks"
  if [ ! -f "$hook" ]; then
    # G3a: Hook absent — create it from the Massoh template (template already has shebang).
    cp "$MASSOH_HOME/templates/massoh-pre-push" "$hook"
    chmod +x "$hook"
    say "  create .git/hooks/pre-push"
  elif grep -qF "$GATE_MARKER_START" "$hook" 2>/dev/null; then
    # G3b: Hook already contains Massoh marker — idempotent, skip.
    say "  keep   .git/hooks/pre-push (massoh gate already installed)"
  else
    # G3c: Hook exists but no Massoh marker — APPEND only the massoh block (never truncate with >).
    # Strip the leading shebang from the template so the append is clean (the existing hook
    # already has a shebang; adding another would produce a spurious bare shebang after gate off).
    printf '\n' >> "$hook"
    grep -v '^#!/usr/bin/env bash' "$MASSOH_HOME/templates/massoh-pre-push" >> "$hook"
    say "  append .git/hooks/pre-push (pre-existing hook preserved)"
  fi

  # 2. Install CI workflow template (create-if-missing, mirrors scaffold()).
  local ci_dest="$repo/.github/workflows/massoh-gate.yml"
  mkdir -p "$repo/.github/workflows"
  if [ -e "$ci_dest" ]; then
    say "  keep   .github/workflows/massoh-gate.yml (exists)"
  else
    cp "$MASSOH_HOME/templates/massoh-gate.yml" "$ci_dest"
    say "  create .github/workflows/massoh-gate.yml"
  fi

  say "done. gate on. Commit .github/workflows/massoh-gate.yml to enable CI enforcement."
  say "  To remove: massoh gate off"
}

_gate_off() {
  local repo
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" \
    || { say "massoh gate off — not in a git repo; nothing to do."; return 0; }

  say "massoh gate off → $repo"

  local hook="$repo/.git/hooks/pre-push"
  if [ ! -f "$hook" ]; then
    # G11: already absent — no-op.
    say "  .git/hooks/pre-push not found — nothing to remove."
  elif ! grep -qF "$GATE_MARKER_START" "$hook" 2>/dev/null; then
    # G11: no Massoh block in the file — no-op.
    say "  no massoh gate block found in .git/hooks/pre-push — nothing to remove."
  else
    # G4: strip only the massoh-gate:start…end block via awk (mirrors remove_block()).
    awk -v s="$GATE_MARKER_START" -v e="$GATE_MARKER_END" '
      index($0,s){skip=1} !skip{print} index($0,e){skip=0}' \
      "$hook" > "$hook.massoh-tmp"
    # If the remaining content is only blank lines / shebang added by gate on (case G3a),
    # check whether the file has any meaningful content beyond a bare shebang line.
    local remaining
    remaining="$(grep -vE '^[[:space:]]*$' "$hook.massoh-tmp" || true)"
    if [ -z "$remaining" ] || [ "$remaining" = '#!/usr/bin/env bash' ]; then
      # Massoh created this file from scratch (G3a path); safe to remove entirely.
      rm -f "$hook" "$hook.massoh-tmp"
      say "  removed .git/hooks/pre-push (was created by massoh gate on)"
    else
      mv "$hook.massoh-tmp" "$hook"
      say "  stripped massoh gate block from .git/hooks/pre-push (pre-existing content preserved)"
    fi
  fi

  # Note: .github/workflows/massoh-gate.yml is NOT removed by gate off.
  # Per NON_NEGOTIABLES §Prohibited, Massoh never deletes user-tracked files.
  # Owner deletes .github/workflows/massoh-gate.yml manually if desired.
  say "  NOTE: .github/workflows/massoh-gate.yml is left on disk (user-tracked file)."
  say "        Delete it manually if you no longer want CI enforcement."
  say "done. gate off."
}
