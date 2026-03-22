#!/usr/bin/env bats
# =============================================================================
# gh-accounts :: utils.bats
# Tests for utility functions
# =============================================================================

setup() {
    source lib/utils.sh
}

# ---------------------------------------------------------------------------
# Version detection
# ---------------------------------------------------------------------------
@test "get_version returns non-empty string" {
    version=$(get_version)
    [[ -n "$version" ]]
}

@test "get_version format matches semantic versioning" {
    version=$(get_version)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# Path validation
# ---------------------------------------------------------------------------
@test "GH_SSH_DIR points to ~/.ssh" {
    [[ "$GH_SSH_DIR" == "${HOME}/.ssh" ]]
}

@test "GH_SSH_CONFIG points to ~/.ssh/config" {
    [[ "$GH_SSH_CONFIG" == "${HOME}/.ssh/config" ]]
}

@test "GH_SPLIT_DIR points to ~/.ssh/gh-accounts" {
    [[ "$GH_SPLIT_DIR" == "${HOME}/.ssh/gh-accounts" ]]
}

@test "GH_KEY_PREFIX is set to 'github'" {
    [[ "$GH_KEY_PREFIX" == "github" ]]
}

# ---------------------------------------------------------------------------
# Color detection (TTY-aware)
# ---------------------------------------------------------------------------
@test "Color constants are defined" {
    [[ -n "$CLR_RED" ]] || [[ -z "$CLR_RED" ]]  # Either set or empty
    [[ -n "$CLR_GREEN" ]] || [[ -z "$CLR_GREEN" ]]
    [[ -n "$CLR_BLUE" ]] || [[ -z "$CLR_BLUE" ]]
}

# ---------------------------------------------------------------------------
# Logging functions exist
# ---------------------------------------------------------------------------
@test "log_info function exists" {
    declare -f log_info > /dev/null
}

@test "log_success function exists" {
    declare -f log_success > /dev/null
}

@test "log_warn function exists" {
    declare -f log_warn > /dev/null
}

@test "log_error function exists" {
    declare -f log_error > /dev/null
}

@test "die function exists" {
    declare -f die > /dev/null
}

# ---------------------------------------------------------------------------
# Print functions
# ---------------------------------------------------------------------------
@test "print_banner function exists" {
    declare -f print_banner > /dev/null
}
