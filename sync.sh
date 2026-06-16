#!/usr/bin/env bash
# Thin wrapper: `./sync.sh --global` == `bin/massoh install`. The CLI is the real entry point.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
case "${1:-}" in
  --global|"" ) shift || true; exec "$HERE/bin/massoh" install "$@" ;;
  * )           exec "$HERE/bin/massoh" "$@" ;;
esac
