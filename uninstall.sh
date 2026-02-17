#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: uninstall.sh
# Remove gh-accounts from the system.
# =============================================================================

set -euo pipefail

readonly INSTALL_BIN="/usr/local/bin/gh-accounts"
readonly INSTALL_SHARE="/usr/local/share/gh-accounts"

# Colors
if [[ -t 1 ]]; then
    CLR_GREEN='\033[0;32m'
    CLR_RED='\033[0;31m'
    CLR_YELLOW='\033[0;33m'
    CLR_CYAN='\033[0;36m'
    CLR_BOLD='\033[1m'
    CLR_RESET='\033[0m'
else
    CLR_GREEN='' CLR_RED='' CLR_YELLOW='' CLR_CYAN='' CLR_BOLD='' CLR_RESET=''
fi

info()    { echo -e "${CLR_CYAN}[info]${CLR_RESET}    $*"; }
success() { echo -e "${CLR_GREEN}[success]${CLR_RESET} $*"; }
warn()    { echo -e "${CLR_YELLOW}[warn]${CLR_RESET}    $*"; }
error()   { echo -e "${CLR_RED}[error]${CLR_RESET}   $*" >&2; }
die()     { error "$@"; exit 1; }

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
    echo -e "  ${CLR_BOLD}Uninstaller${CLR_RESET}"
    echo ""

    if [[ "${EUID}" -ne 0 ]]; then
        die "Please run as root: sudo bash uninstall.sh"
    fi

    local removed=0

    if [[ -f "${INSTALL_BIN}" ]]; then
        rm -f "${INSTALL_BIN}"
        info "Removed ${INSTALL_BIN}"
        removed=1
    fi

    if [[ -d "${INSTALL_SHARE}" ]]; then
        rm -rf "${INSTALL_SHARE}"
        info "Removed ${INSTALL_SHARE}"
        removed=1
    fi

    if [[ ${removed} -eq 0 ]]; then
        warn "gh-accounts does not appear to be installed."
        return 0
    fi

    echo ""
    success "gh-accounts uninstalled."
    echo ""
    warn "Your SSH keys and config in ~/.ssh/ were NOT removed."
    echo "  To remove account keys manually:  rm ~/.ssh/github-*"
    echo "  To remove backups:                rm -rf ~/.ssh/gh-accounts-backups/"
    echo "  To remove split configs:          rm -rf ~/.ssh/gh-accounts/"
    echo ""
}

main "$@"
