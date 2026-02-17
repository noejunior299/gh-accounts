#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: doctor.sh
# Diagnostic checks: agent, permissions, config integrity, duplicates.
# =============================================================================

set -euo pipefail

# Accumulator — incremented by each check function, read by doctor_run.
_doctor_issues=0

# ---------------------------------------------------------------------------
# Main doctor routine
# ---------------------------------------------------------------------------
doctor_run() {
    echo ""
    log_info "${CLR_BOLD}Running diagnostics...${CLR_RESET}"
    echo ""

    _doctor_issues=0

    doctor_check_agent
    doctor_check_permissions
    doctor_check_config_integrity
    doctor_check_keys
    doctor_check_duplicates
    doctor_check_split_mode

    echo ""
    if [[ ${_doctor_issues} -eq 0 ]]; then
        log_success "All checks passed. Your setup is healthy."
    else
        log_warn "${_doctor_issues} issue(s) found. Review the warnings above."
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Check: ssh-agent running
# ---------------------------------------------------------------------------
doctor_check_agent() {
    echo -n "  Checking ssh-agent... "

    if ssh-add -l &>/dev/null; then
        echo -e "${CLR_GREEN}running${CLR_RESET}"
    elif [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        echo -e "${CLR_YELLOW}socket exists but no keys loaded${CLR_RESET}"
        _doctor_issues=$((_doctor_issues + 1))
    else
        echo -e "${CLR_RED}not running${CLR_RESET}"
        echo -e "    ${CLR_YELLOW}→ Start it with: eval \"\$(ssh-agent -s)\"${CLR_RESET}"
        _doctor_issues=$((_doctor_issues + 1))
    fi
}

# ---------------------------------------------------------------------------
# Check: directory & file permissions
# ---------------------------------------------------------------------------
doctor_check_permissions() {
    echo -n "  Checking ~/.ssh permissions... "

    if [[ ! -d "${GH_SSH_DIR}" ]]; then
        echo -e "${CLR_RED}directory missing${CLR_RESET}"
        _doctor_issues=$((_doctor_issues + 1))
        return
    fi

    local dir_perms
    dir_perms="$(stat -c '%a' "${GH_SSH_DIR}" 2>/dev/null)"
    if [[ "${dir_perms}" != "700" ]]; then
        echo -e "${CLR_RED}${dir_perms} (expected 700)${CLR_RESET}"
        echo -e "    ${CLR_YELLOW}→ Fix: chmod 700 ~/.ssh${CLR_RESET}"
        _doctor_issues=$((_doctor_issues + 1))
    else
        echo -e "${CLR_GREEN}700${CLR_RESET}"
    fi

    # Check config file
    if [[ -f "${GH_SSH_CONFIG}" ]]; then
        echo -n "  Checking config permissions... "
        local cfg_perms
        cfg_perms="$(stat -c '%a' "${GH_SSH_CONFIG}" 2>/dev/null)"
        if [[ "${cfg_perms}" != "600" && "${cfg_perms}" != "644" ]]; then
            echo -e "${CLR_RED}${cfg_perms} (expected 600)${CLR_RESET}"
            echo -e "    ${CLR_YELLOW}→ Fix: chmod 600 ~/.ssh/config${CLR_RESET}"
            _doctor_issues=$((_doctor_issues + 1))
        else
            echo -e "${CLR_GREEN}${cfg_perms}${CLR_RESET}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Check: config file integrity (parseable, no syntax errors)
# ---------------------------------------------------------------------------
doctor_check_config_integrity() {
    echo -n "  Checking config integrity... "

    if [[ ! -f "${GH_SSH_CONFIG}" ]]; then
        echo -e "${CLR_YELLOW}no config file${CLR_RESET}"
        return
    fi

    local block_issues=0
    local current_account=""
    local has_hostname=0
    local has_identity=0

    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ gh-accounts\ ::\ ([^\ ]+) ]]; then
            if [[ -n "${current_account}" ]]; then
                if [[ ${has_hostname} -eq 0 ]] || [[ ${has_identity} -eq 0 ]]; then
                    echo -e "${CLR_RED}incomplete block for '${current_account}'${CLR_RESET}"
                    block_issues=$((block_issues + 1))
                fi
            fi
            current_account="${BASH_REMATCH[1]}"
            has_hostname=0
            has_identity=0
        fi

        if [[ "${line}" =~ ^[[:space:]]+HostName ]]; then
            has_hostname=1
        fi
        if [[ "${line}" =~ ^[[:space:]]+IdentityFile ]]; then
            has_identity=1
        fi
    done < "${GH_SSH_CONFIG}"

    # Check last block
    if [[ -n "${current_account}" ]]; then
        if [[ ${has_hostname} -eq 0 ]] || [[ ${has_identity} -eq 0 ]]; then
            echo -e "${CLR_RED}incomplete block for '${current_account}'${CLR_RESET}"
            block_issues=$((block_issues + 1))
        fi
    fi

    if [[ ${block_issues} -eq 0 ]]; then
        echo -e "${CLR_GREEN}valid${CLR_RESET}"
    fi

    _doctor_issues=$((_doctor_issues + block_issues))
}

# ---------------------------------------------------------------------------
# Check: key files exist and have correct permissions
# ---------------------------------------------------------------------------
doctor_check_keys() {
    echo -n "  Checking SSH keys... "

    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true

    if [[ -z "${accounts}" ]]; then
        echo -e "${CLR_YELLOW}no accounts configured${CLR_RESET}"
        return
    fi

    local key_issues=0
    while IFS='|' read -r acct email alias kp mode; do
        if [[ ! -f "${kp}" ]]; then
            if [[ ${key_issues} -eq 0 ]]; then
                echo ""
            fi
            echo -e "    ${CLR_RED}✗ Missing private key for '${acct}': ${kp}${CLR_RESET}"
            key_issues=$((key_issues + 1))
            continue
        fi

        local perms
        perms="$(stat -c '%a' "${kp}" 2>/dev/null)"
        if [[ "${perms}" != "600" ]]; then
            if [[ ${key_issues} -eq 0 ]]; then
                echo ""
            fi
            echo -e "    ${CLR_YELLOW}⚠ Key '${acct}' has permissions ${perms} (expected 600)${CLR_RESET}"
            key_issues=$((key_issues + 1))
        fi

        if [[ ! -f "${kp}.pub" ]]; then
            if [[ ${key_issues} -eq 0 ]]; then
                echo ""
            fi
            echo -e "    ${CLR_YELLOW}⚠ Missing public key for '${acct}': ${kp}.pub${CLR_RESET}"
            key_issues=$((key_issues + 1))
        fi
    done <<< "${accounts}"

    if [[ ${key_issues} -eq 0 ]]; then
        echo -e "${CLR_GREEN}all keys valid${CLR_RESET}"
    fi

    _doctor_issues=$((_doctor_issues + key_issues))
}

# ---------------------------------------------------------------------------
# Check: duplicate host aliases
# ---------------------------------------------------------------------------
doctor_check_duplicates() {
    echo -n "  Checking for duplicate aliases... "

    local aliases
    aliases="$(config_get_all_aliases 2>/dev/null)" || true

    if [[ -z "${aliases}" ]]; then
        echo -e "${CLR_GREEN}none${CLR_RESET}"
        return
    fi

    local duplicates
    duplicates="$(echo "${aliases}" | sort | uniq -d)" || true

    if [[ -n "${duplicates}" ]]; then
        echo -e "${CLR_RED}found duplicates${CLR_RESET}"
        local dup_count=0
        while IFS= read -r dup; do
            echo -e "    ${CLR_RED}✗ Duplicate alias: ${dup}${CLR_RESET}"
            dup_count=$((dup_count + 1))
        done <<< "${duplicates}"
        _doctor_issues=$((_doctor_issues + dup_count))
    else
        echo -e "${CLR_GREEN}none${CLR_RESET}"
    fi
}

# ---------------------------------------------------------------------------
# Check: split mode consistency
# ---------------------------------------------------------------------------
doctor_check_split_mode() {
    echo -n "  Checking split mode... "

    if is_split_mode_enabled; then
        echo -e "${CLR_CYAN}enabled${CLR_RESET}"

        if [[ ! -d "${GH_SPLIT_DIR}" ]]; then
            echo -e "    ${CLR_YELLOW}⚠ Include directive exists but directory is missing: ${GH_SPLIT_DIR}${CLR_RESET}"
            _doctor_issues=$((_doctor_issues + 1))
        fi

        if [[ -d "${GH_SPLIT_DIR}" ]]; then
            local split_perms
            split_perms="$(stat -c '%a' "${GH_SPLIT_DIR}" 2>/dev/null)"
            if [[ "${split_perms}" != "700" ]]; then
                echo -e "    ${CLR_YELLOW}⚠ Split dir permissions: ${split_perms} (expected 700)${CLR_RESET}"
                _doctor_issues=$((_doctor_issues + 1))
            fi
        fi
    else
        echo -e "${CLR_CYAN}disabled (unified mode)${CLR_RESET}"
    fi
}
