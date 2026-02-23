#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: utils.sh
# Shared utility functions: colors, logging, validation, permissions.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Directory & file constants
# ---------------------------------------------------------------------------
readonly GH_SSH_DIR="${HOME}/.ssh"
readonly GH_SSH_CONFIG="${GH_SSH_DIR}/config"
readonly GH_SPLIT_DIR="${GH_SSH_DIR}/gh-accounts"
readonly GH_BACKUP_DIR="${GH_SSH_DIR}/gh-accounts-backups"
readonly GH_KEY_PREFIX="github"

# ---------------------------------------------------------------------------
# ANSI color helpers (safe for piped / non-tty output)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    readonly CLR_RED='\033[0;31m'
    readonly CLR_GREEN='\033[0;32m'
    readonly CLR_YELLOW='\033[0;33m'
    readonly CLR_BLUE='\033[0;34m'
    readonly CLR_CYAN='\033[0;36m'
    readonly CLR_BOLD='\033[1m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_RED=''
    readonly CLR_GREEN=''
    readonly CLR_YELLOW=''
    readonly CLR_BLUE=''
    readonly CLR_CYAN=''
    readonly CLR_BOLD=''
    readonly CLR_RESET=''
fi

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_info()    { echo -e "${CLR_BLUE}[info]${CLR_RESET}    $*"; }
log_success() { echo -e "${CLR_GREEN}[success]${CLR_RESET} $*"; }
log_warn()    { echo -e "${CLR_YELLOW}[warn]${CLR_RESET}    $*"; }
log_error()   { echo -e "${CLR_RED}[error]${CLR_RESET}   $*" >&2; }

die() {
    log_error "$@"
    exit 1
}

# ---------------------------------------------------------------------------
# ASCII banner
# ---------------------------------------------------------------------------
print_banner() {
    echo -e "${CLR_CYAN}"
    cat << 'EOF'
        __                               __         
  ___ _/ /  ___ _______ ___  __ _____   / /____
 / _ `/ _ \/ _ `/ __/ __/ _ \/ // / _ \/ __(_-<
 \_, /_//_/\_,_/\__/\__/\___/\_,_/_//_/\__/___/
/___/
EOF
    echo -e "${CLR_RESET}"
    echo -e "  ${CLR_BOLD}GitHub SSH Account Manager${CLR_RESET}  ·  v$(get_version)"
    echo ""
}

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
get_version() {
    local version_file
    # Resolve from installed location or source tree
    for version_file in \
        "/usr/local/share/gh-accounts/VERSION" \
        "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/VERSION"; do
        if [[ -f "${version_file}" ]]; then
            cat "${version_file}" | tr -d '[:space:]'
            return 0
        fi
    done
    echo "unknown"
}

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------
validate_account_name() {
    local name="${1:-}"
    if [[ -z "${name}" ]]; then
        die "Account name is required."
    fi
    if [[ ! "${name}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        die "Invalid account name '${name}'. Use only alphanumerics, dots, hyphens, and underscores."
    fi
}

validate_email() {
    local email="${1:-}"
    if [[ -z "${email}" ]]; then
        die "Email address is required."
    fi
    if [[ ! "${email}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        die "Invalid email address '${email}'."
    fi
}

# ---------------------------------------------------------------------------
# SSH directory & permissions
# ---------------------------------------------------------------------------
ensure_ssh_dir() {
    if [[ ! -d "${GH_SSH_DIR}" ]]; then
        mkdir -p "${GH_SSH_DIR}"
        log_info "Created ${GH_SSH_DIR}"
    fi
    chmod 700 "${GH_SSH_DIR}"
}

ensure_split_dir() {
    if [[ ! -d "${GH_SPLIT_DIR}" ]]; then
        mkdir -p "${GH_SPLIT_DIR}"
        log_info "Created ${GH_SPLIT_DIR}"
    fi
    chmod 700 "${GH_SPLIT_DIR}"
}

ensure_backup_dir() {
    if [[ ! -d "${GH_BACKUP_DIR}" ]]; then
        mkdir -p "${GH_BACKUP_DIR}"
        log_info "Created ${GH_BACKUP_DIR}"
    fi
    chmod 700 "${GH_BACKUP_DIR}"
}

set_key_permissions() {
    local key_path="${1}"
    if [[ -f "${key_path}" ]]; then
        chmod 600 "${key_path}"
    fi
    if [[ -f "${key_path}.pub" ]]; then
        chmod 644 "${key_path}.pub"
    fi
}

# ---------------------------------------------------------------------------
# SSH config touch helper (creates if missing)
# ---------------------------------------------------------------------------
ensure_ssh_config() {
    ensure_ssh_dir
    if [[ ! -f "${GH_SSH_CONFIG}" ]]; then
        touch "${GH_SSH_CONFIG}"
        chmod 600 "${GH_SSH_CONFIG}"
        log_info "Created ${GH_SSH_CONFIG}"
    fi
}

# ---------------------------------------------------------------------------
# Key path helpers
# ---------------------------------------------------------------------------
key_path_for() {
    local account="${1}"
    echo "${GH_SSH_DIR}/${GH_KEY_PREFIX}-${account}"
}

host_alias_for() {
    local account="${1}"
    echo "github-${account}"
}

# ---------------------------------------------------------------------------
# Account existence checks
# ---------------------------------------------------------------------------
account_key_exists() {
    local account="${1}"
    local kp
    kp="$(key_path_for "${account}")"
    [[ -f "${kp}" ]]
}

account_host_exists() {
    local account="${1}"
    local alias
    alias="$(host_alias_for "${account}")"
    # Check unified config
    if [[ -f "${GH_SSH_CONFIG}" ]] && grep -q "^Host ${alias}$" "${GH_SSH_CONFIG}" 2>/dev/null; then
        return 0
    fi
    # Check split config
    if [[ -f "${GH_SPLIT_DIR}/${alias}" ]]; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# ssh-agent helpers
# ---------------------------------------------------------------------------
ensure_ssh_agent() {
    if ! ssh-add -l &>/dev/null; then
        if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
            eval "$(ssh-agent -s)" >/dev/null 2>&1
            log_info "Started ssh-agent (PID ${SSH_AGENT_PID:-unknown})."
        fi
    fi
}

# ---------------------------------------------------------------------------
# Split-mode detection
# ---------------------------------------------------------------------------
is_split_mode_enabled() {
    if [[ -f "${GH_SSH_CONFIG}" ]] && grep -q "^Include ${GH_SPLIT_DIR}/\*" "${GH_SSH_CONFIG}" 2>/dev/null; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Extract email from a public key file comment (3rd field)
# Falls back to gh-accounts comment marker if present, else "unknown"
# ---------------------------------------------------------------------------
email_from_pubkey() {
    local key_path="${1}"
    local pub_file="${key_path}.pub"
    if [[ -f "${pub_file}" ]]; then
        local comment
        comment="$(awk '{print $NF}' "${pub_file}" 2>/dev/null)"
        if [[ -n "${comment}" ]]; then
            echo "${comment}"
            return 0
        fi
    fi
    echo "unknown"
}

# ---------------------------------------------------------------------------
# Confirm prompt
# ---------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Are you sure?}"
    local answer
    echo -en "${CLR_YELLOW}${prompt} [y/N]: ${CLR_RESET}"
    read -r answer
    [[ "${answer}" =~ ^[Yy]$ ]]
}
