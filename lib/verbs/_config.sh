#!/usr/bin/env bash
# _config.sh — massoh_config_get helper (pure-bash YAML-lite key: value reader).
# Sourced by bin/massoh's verb-loading loop (underscore prefix = not a verb, not dispatch-registered).
# Supports: optional project-level agent-project/config.yml > built-in default.
# Global-level config tier is deferred (requires fresh arch-safety pass).
#
# WARNING: config.yml is a committable file. NEVER place secrets in it.
# Keys matching _token|_key|_secret|_password|_credential are refused with a warning.
#
# Usage:
#   massoh_config_get <config_file_path> <key> <default>
# Returns: value from config file for <key>, or <default> on any error/absence/malformed input.
# Safe under set -euo pipefail: never crashes.
#
# Parser handles:
#   - missing file                → returns default
#   - missing key                 → returns default
#   - inline comments (# ...)     → stripped
#   - single or double quoted values → unquoted
#   - leading/trailing whitespace → stripped
#   - malformed / complex YAML   → returns default (grep anchoring silently skips unrecognised lines)
#   - duplicate keys             → head -n1 (first occurrence; predictable)
# Does NOT handle: nested maps, arrays, multi-line values (flat key: scalar only).

# shellcheck disable=SC2120
massoh_config_get() {
  local cfg="$1" key="$2" default="$3"

  # PC4: secret-key guard — keys matching secret-sounding patterns warn + return default.
  case "$key" in
    *_token|*_key|*_secret|*_password|*_credential)
      printf 'massoh config: WARNING: key "%s" looks like a secret — use .env.massoh, not config.yml. Returning default.\n' \
        "$key" >&2
      printf '%s' "$default"
      return 0
      ;;
  esac

  # PC3: missing file → return default immediately (never error).
  [ -f "$cfg" ] || { printf '%s' "$default"; return 0; }

  local val
  # PC3/PC5: grep anchored to ^<key>[whitespace]*: ; || true ensures no crash on missing key.
  # sed strips: "key: " prefix, inline comments, surrounding quotes, whitespace.
  val="$(grep -E "^${key}[[:space:]]*:" "$cfg" 2>/dev/null \
         | head -n1 \
         | sed 's/^[^:]*:[[:space:]]*//' \
         | sed 's/[[:space:]]*#.*//' \
         | sed "s/^['\"]//; s/['\"]$//" \
         | tr -d '[:space:]' \
         || true)"

  if [ -z "$val" ]; then
    printf '%s' "$default"
  else
    printf '%s' "$val"
  fi
}
