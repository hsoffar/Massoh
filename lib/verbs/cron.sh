#!/usr/bin/env bash
# massoh verb: cron — the autonomous loop runner (separate script; safe-by-default: dry-run, no auto-merge).
# Sourced by bin/massoh at startup. Requires: MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# cron — the autonomous loop runner (separate script; safe-by-default: dry-run, no auto-merge).
cmd_cron() { exec "$MASSOH_HOME/bin/massoh-cron" "$@"; }
