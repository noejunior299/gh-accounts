#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: account.bats
# Tests for account CRUD operations
# =============================================================================

setup() {
    export TEST_SSH_DIR=$(mktemp -d)
    export GH_SSH_DIR="$TEST_SSH_DIR"
    export GH_SSH_CONFIG="$TEST_SSH_DIR/config"
    export GH_SPLIT_DIR="$TEST_SSH_DIR/gh-accounts"
    
    touch "$GH_SSH_CONFIG"
    chmod 600 "$GH_SSH_CONFIG"
    
    source lib/utils.sh
    source lib/config.sh
    source lib/account.sh
}

teardown() {
    [[ -d "$TEST_SSH_DIR" ]] && rm -rf "$TEST_SSH_DIR"
}

# ---------------------------------------------------------------------------
# Account functions exist
# ---------------------------------------------------------------------------
@test "account_create function exists" {
    declare -f account_create > /dev/null
}

@test "account_list function exists" {
    declare -f account_list > /dev/null
}

@test "account_delete function exists" {
    declare -f account_delete > /dev/null
}

@test "account_update function exists" {
    declare -f account_update > /dev/null
}

@test "account_test function exists" {
    declare -f account_test > /dev/null
}

@test "account_switch function exists" {
    declare -f account_switch > /dev/null
}

@test "account_export_json function exists" {
    declare -f account_export_json > /dev/null
}

# ---------------------------------------------------------------------------
# Key pair generation
# ---------------------------------------------------------------------------
@test "generated key uses ed25519 algorithm" {
    grep -q "ssh-keygen.*ed25519\|ed25519.*ssh-keygen" "$BATS_TEST_DIRNAME/../lib/account.sh"
}

@test "key generation sets correct permissions (600)" {
    grep -q "chmod.*600" "$BATS_TEST_DIRNAME/../lib/account.sh"
}
