#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: install.sh
# Install gh-accounts system-wide to /usr/local/{bin,share}/gh-accounts.
# =============================================================================

set -euo pipefail

readonly INSTALL_BIN="/usr/local/bin/gh-accounts"
readonly INSTALL_SHARE="/usr/local/share/gh-accounts"

# Colors
if [[ -t 1 ]]; then
    CLR_GREEN='\033[0;32m'
    CLR_RED='\033[0;31m'
    CLR_CYAN='\033[0;36m'
    CLR_BOLD='\033[1m'
    CLR_RESET='\033[0m'
else
    CLR_GREEN='' CLR_RED='' CLR_CYAN='' CLR_BOLD='' CLR_RESET=''
fi

info()    { echo -e "${CLR_CYAN}[info]${CLR_RESET}    $*"; }
success() { echo -e "${CLR_GREEN}[success]${CLR_RESET} $*"; }
error()   { echo -e "${CLR_RED}[error]${CLR_RESET}   $*" >&2; }
die()     { error "$@"; exit 1; }

# ---------------------------------------------------------------------------
# Resolve source directory (supports piped install or local execution)
# ---------------------------------------------------------------------------
resolve_source_dir() {
    # If running from a cloned repo
    if [[ -f "${BASH_SOURCE[0]}" ]]; then
        local dir
        dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -d "${dir}/bin" ]] && [[ -d "${dir}/lib" ]]; then
            echo "${dir}"
            return
        fi
    fi

    # If piped via curl, clone to tmp
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    info "Downloading gh-accounts..." >&2
    if command -v git &>/dev/null; then
        git clone --depth 1 https://github.com/noejunior792/gh-accounts.git "${tmp_dir}/gh-accounts" 2>/dev/null \
            || die "Failed to clone repository."
        echo "${tmp_dir}/gh-accounts"
    else
        die "git is required for remote installation. Install git first."
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    echo -e "${CLR_CYAN}"
    cat << 'EOF'
        __                                       __
  ___ _/ /  ___ _______ ___  __ _____  / /____
 / _ `/ _ \/ _ `/ __/ __/ _ \/ // / _ \/ __(_-<
 \_, /_//_/\_,_/\__/\__/\___/\_,_/_//_/\__/___/
/___/
EOF
    echo -e "${CLR_RESET}"
    echo -e "  ${CLR_BOLD}Installer${CLR_RESET}"
    echo ""

    # Require root for system-wide install
    if [[ "${EUID}" -ne 0 ]]; then
        die "Please run as root: sudo bash install.sh"
    fi

    local source_dir
    source_dir="$(resolve_source_dir)"

    # Validate source
    for required in bin/gh-accounts lib/utils.sh lib/config.sh lib/account.sh lib/backup.sh lib/doctor.sh VERSION; do
        if [[ ! -f "${source_dir}/${required}" ]]; then
            die "Missing required file: ${required}"
        fi
    done

    # Install shared files
    info "Installing to ${INSTALL_SHARE}/..."
    rm -rf "${INSTALL_SHARE}"
    mkdir -p "${INSTALL_SHARE}"

    cp -r "${source_dir}/lib" "${INSTALL_SHARE}/lib"
    cp "${source_dir}/VERSION" "${INSTALL_SHARE}/VERSION"
    [[ -f "${source_dir}/LICENSE" ]] && cp "${source_dir}/LICENSE" "${INSTALL_SHARE}/LICENSE"

    chmod -R 755 "${INSTALL_SHARE}"

    # Install binary
    info "Installing CLI to ${INSTALL_BIN}..."
    cp "${source_dir}/bin/gh-accounts" "${INSTALL_BIN}"
    chmod 755 "${INSTALL_BIN}"

    echo ""
    success "gh-accounts installed successfully!"
    echo ""
    echo "  Run:  gh-accounts help"
    echo "  Version: $(cat "${INSTALL_SHARE}/VERSION" | tr -d '[:space:]')"
    echo ""
}

main "$@"
