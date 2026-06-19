#!/usr/bin/env bash
# massoh verb: work — open an interactive Claude session in a repo.
# Sourced by bin/massoh at startup. Requires: MASSOH_HOME (set in bin/massoh bootstrap).
# shellcheck source=/dev/null

# work — open an interactive Claude session in the given repo directory.
cmd_work() { local r="${1:?usage: massoh work <repo>}"; cd "$r"; exec "${MASSOH_CLAUDE:-claude}"; }
