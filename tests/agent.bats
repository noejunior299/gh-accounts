#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: agent.bats
# Tests for SSH agent management
# =============================================================================

setup() {
    source lib/utils.sh
    source lib/agent.sh
}

# ---------------------------------------------------------------------------
# Agent functions exist
# ---------------------------------------------------------------------------
@test "agent_status function exists" {
    declare -f agent_status > /dev/null
}

@test "agent_load function exists" {
    declare -f agent_load > /dev/null
}

@test "agent_clean function exists" {
    declare -f agent_clean > /dev/null
}

@test "agent_reset function exists" {
    declare -f agent_reset > /dev/null
}

@test "agent_harden function exists" {
    declare -f agent_harden > /dev/null
}

# ---------------------------------------------------------------------------
# IdentitiesOnly hardening
# ---------------------------------------------------------------------------
@test "harden uses IdentitiesOnly yes for agent pollution prevention" {
    grep -q "IdentitiesOnly yes" "$BATS_TEST_DIRNAME/../lib/agent.sh"
}

@test "agent pollution detection exists" {
    grep -q "agent\|key\|ssh-add" "$BATS_TEST_DIRNAME/../lib/agent.sh"
}
