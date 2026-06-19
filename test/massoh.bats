#!/usr/bin/env bats
# test/massoh.bats — Native bats pilot: T1 (install / doctor) section.
#
# SCOPE: This file is a parallel test harness — it does NOT replace test/run.sh.
# test/run.sh remains the source of truth for all 457 checks (CI runs both).
#
# MIGRATION TEMPLATE: To port a future section, follow this pattern:
#   1. One @test per logical check (not per bash one-liner).
#   2. Use $BATS_TEST_TMPDIR for all temp state — bats provides a unique dir per
#      @test, so no cross-test variable sharing is needed.
#   3. Invoke $MASSOH directly; assert real output/exit codes (not stub checks).
#   4. Sections with cross-test variable sharing (e.g., T11i→T15l→T16r→T22b checksum
#      chain) CANNOT be naively ported to bats @test isolation — defer those until
#      test/run.sh is modularized with file-based state handoff.
#   5. Sections with inline Python3 mock servers (T18–T19) need setup_file/teardown_file
#      to spin up/tear down the server once per file, not per @test.
#
# BA7: This file shares no global state with test/run.sh. Each harness is self-contained.

# ---------------------------------------------------------------------------
# Global setup (runs once before all @tests in this file)
# ---------------------------------------------------------------------------
setup_file() {
  # Locate the massoh binary relative to this test file.
  MASSOH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/massoh"
  export MASSOH
}

# ---------------------------------------------------------------------------
# Per-test setup: $BATS_TEST_TMPDIR is automatically a unique temp dir per @test.
# No shared mutable state between @test blocks.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# T1 — install / doctor (6 checks, mirroring test/run.sh lines 19–33)
# ---------------------------------------------------------------------------

# T1-1: install creates the agent-os engine directory
@test "T1: install copies agent-os engine into CLAUDE_CONFIG_DIR" {
  local cc
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  [ -d "$cc/agent-os" ]
}

# T1-2: install places at least one massoh-* agent
@test "T1: install copies massoh-* agent files" {
  local cc
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  ls "$cc"/agents/massoh-*.md >/dev/null 2>&1
}

# T1-3: install injects the global block into CLAUDE.md
@test "T1: install adds massoh:start global block to CLAUDE.md" {
  local cc
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  grep -qF 'massoh:start' "$cc/CLAUDE.md"
}

# T1-4: doctor exits 0 on a healthy (freshly installed) layout
@test "T1: doctor exits 0 on healthy install" {
  local cc
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" doctor >/dev/null 2>&1
}

# T1-5: doctor is read-only — running it must not change any file in CLAUDE_CONFIG_DIR
@test "T1: doctor wrote nothing (read-only)" {
  local cc before after
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  before="$(cd "$cc" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"
  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" doctor >/dev/null 2>&1 || true
  after="$(cd "$cc" && find . -type f | sort | xargs ls -la 2>/dev/null | md5sum)"

  [ "$before" = "$after" ]
}

# T1-6: doctor exits non-zero when an agent is missing (drift detected)
@test "T1: doctor exits non-zero on agent drift" {
  local cc
  cc="$(mktemp -d "$BATS_TEST_TMPDIR/cc.XXXXXX")"

  CLAUDE_CONFIG_DIR="$cc" "$MASSOH" install >/dev/null 2>&1

  # Simulate drift: remove one required agent
  rm -f "$cc"/agents/massoh-implementer.md

  # doctor must exit non-zero; use a subshell so the env var is properly scoped for run.
  run bash -c "CLAUDE_CONFIG_DIR='$cc' '$MASSOH' doctor" >/dev/null 2>&1
  [ "$status" -ne 0 ]
}
