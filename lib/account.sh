#!/usr/bin/env bash
# gh-accounts :: account.sh — Account lifecycle (create, delete, update, switch, test, list, export)
set -euo pipefail

account_create() {
    local account="${1}"
    local email="${2}"

    validate_account_name "${account}"
    validate_email "${email}"

    local kp
    kp="$(key_path_for "${account}")"

    # Guard: duplicate key
    if account_key_exists "${account}"; then
        die "SSH key already exists for account '${account}': ${kp}"
    fi

    # Guard: duplicate alias
    if account_host_exists "${account}"; then
        die "Host alias already exists for account '${account}'."
    fi

    ensure_ssh_dir

    # Auto-backup before modifying config
    backup_create_auto

    # Generate ed25519 key
    log_info "Generating SSH key pair for '${account}'..."
    ssh-keygen -t ed25519 -C "${email}" -f "${kp}" -N "" -q
    set_key_permissions "${kp}"
    log_success "Key pair created: ${kp}"

    # Add key to ssh-agent
    ensure_ssh_agent
    ssh-add "${kp}" 2>/dev/null || log_warn "Could not add key to ssh-agent."

    # Write config entry
    if is_split_mode_enabled; then
        config_add_split "${account}" "${email}"
    else
        config_add_unified "${account}" "${email}"
    fi

    log_success "Account '${account}' created successfully."
    echo ""
    log_info "Public key (add this to GitHub → Settings → SSH keys):"
    echo ""
    cat "${kp}.pub"
    echo ""
    log_info "Git clone usage:"
    echo "  git clone git@$(host_alias_for "${account}"):username/repo.git"
}

account_delete() {
    local account="${1}"
    validate_account_name "${account}"

    if ! account_key_exists "${account}" && ! account_host_exists "${account}"; then
        die "Account '${account}' does not exist."
    fi

    if ! confirm "Delete account '${account}' and its SSH keys? This cannot be undone."; then
        log_info "Aborted."
        return 0
    fi

    # Auto-backup
    backup_create_auto

    local kp
    kp="$(key_path_for "${account}")"

    # Remove key from agent (best effort)
    if [[ -f "${kp}" ]]; then
        ssh-add -d "${kp}" 2>/dev/null || true
    fi

    # Remove key files
    rm -f "${kp}" "${kp}.pub"
    log_info "Removed key files."

    # Remove config entries
    config_remove_unified "${account}"
    config_remove_split "${account}"

    log_success "Account '${account}' deleted."
}

account_update() {
    local account="${1}"
    local new_email="${2}"

    validate_account_name "${account}"
    validate_email "${new_email}"

    if ! account_key_exists "${account}" && ! account_host_exists "${account}"; then
        die "Account '${account}' does not exist."
    fi

    # Auto-backup
    backup_create_auto

    local updated=0

    if config_update_email_unified "${account}" "${new_email}" 2>/dev/null; then
        updated=1
    fi

    if config_update_email_split "${account}" "${new_email}" 2>/dev/null; then
        updated=1
    fi

    if [[ ${updated} -eq 0 ]]; then
        die "Could not find config entry for account '${account}'."
    fi

    # Update the key comment
    local kp
    kp="$(key_path_for "${account}")"
    if [[ -f "${kp}" ]]; then
        ssh-keygen -c -C "${new_email}" -f "${kp}" -q -N "" 2>/dev/null || true
    fi

    log_success "Account '${account}' updated with email '${new_email}'."
}

account_test() {
    local account="${1}"
    validate_account_name "${account}"

    local alias
    alias="$(host_alias_for "${account}")"

    if ! account_key_exists "${account}" && ! account_host_exists "${account}"; then
        die "Account '${account}' does not exist."
    fi

    log_info "Testing SSH connection for '${account}' (${alias})..."
    echo ""

    # GitHub closes the connection after printing the greeting, exit code 1 is normal
    local output
    output="$(ssh -T "git@${alias}" 2>&1)" || true

    if echo "${output}" | grep -qi "successfully authenticated"; then
        log_success "Authentication successful!"
        echo "  ${output}"
    elif echo "${output}" | grep -qi "permission denied"; then
        log_error "Authentication failed. Ensure the public key is added to GitHub."
        echo "  ${output}"
    else
        log_warn "Unexpected response:"
        echo "  ${output}"
    fi
}

account_list() {
    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true

    if [[ -z "${accounts}" ]]; then
        log_info "No GitHub SSH accounts found."
        return 0
    fi

    echo ""
    printf "  ${CLR_BOLD}%-20s %-30s %-22s %-8s %-8s${CLR_RESET}\n" "ACCOUNT" "EMAIL" "HOST ALIAS" "MODE" "SOURCE"
    printf "  %-20s %-30s %-22s %-8s %-8s\n" "───────" "─────" "──────────" "────" "──────"

    while IFS='|' read -r acct email alias kp mode managed; do
        local key_status="${CLR_GREEN}●${CLR_RESET}"
        if [[ ! -f "${kp}" ]]; then
            key_status="${CLR_RED}✗${CLR_RESET}"
        fi
        local source_label
        if [[ "${managed}" == "yes" ]]; then
            source_label="managed"
        else
            source_label="manual"
        fi
        printf "  ${key_status} %-18s %-30s %-22s %-8s %-8s\n" "${acct}" "${email}" "${alias}" "${mode}" "${source_label}"
    done <<< "${accounts}"

    echo ""
}

account_export_json() {
    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true

    if [[ -z "${accounts}" ]]; then
        echo "[]"
        return 0
    fi

    local first=1
    echo "["

    while IFS='|' read -r acct email alias kp mode managed; do
        local key_exists="true"
        [[ ! -f "${kp}" ]] && key_exists="false"

        local pub_key=""
        if [[ -f "${kp}.pub" ]]; then
            pub_key="$(cat "${kp}.pub" | tr -d '\n')"
        fi

        local managed_bool="true"
        [[ "${managed}" != "yes" ]] && managed_bool="false"

        if [[ ${first} -eq 0 ]]; then
            echo ","
        fi
        first=0

        cat <<ENTRY
  {
    "account": "${acct}",
    "email": "${email}",
    "host_alias": "${alias}",
    "key_path": "${kp}",
    "key_exists": ${key_exists},
    "public_key": "${pub_key}",
    "mode": "${mode}",
    "managed": ${managed_bool}
  }
ENTRY
    done <<< "${accounts}"

    echo ""
    echo "]"
}

account_switch() {
    local account="${1}"
    local scope="${2:-local}"   # "local" (default) or "global"

    validate_account_name "${account}"

    # Look up account in config
    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true

    if [[ -z "${accounts}" ]]; then
        die "No GitHub SSH accounts found."
    fi

    local found_email="" found_alias=""
    while IFS='|' read -r acct email alias kp mode managed; do
        if [[ "${acct}" == "${account}" ]]; then
            found_email="${email}"
            found_alias="${alias}"
            break
        fi
    done <<< "${accounts}"

    if [[ -z "${found_email}" ]]; then
        die "Account '${account}' not found. Run 'gh-accounts list' to see available accounts."
    fi

    # Derive user.name from account (or alias for default)
    local git_name="${account}"

    local git_flag="--local"
    local scope_label="this repository"
    if [[ "${scope}" == "global" ]]; then
        git_flag="--global"
        scope_label="global config"
    else
        # Ensure we are inside a git repo for --local
        if ! git rev-parse --is-inside-work-tree &>/dev/null; then
            die "Not inside a git repository. Use --global or navigate to a repo first."
        fi
    fi

    git config "${git_flag}" user.name "${git_name}"
    git config "${git_flag}" user.email "${found_email}"

    log_success "Switched git identity for ${scope_label}:"
    echo ""
    echo "  user.name  = ${git_name}"
    echo "  user.email = ${found_email}"
    echo ""

    if [[ "${scope}" != "global" ]]; then
        log_info "Clone/push via: git@${found_alias}:<org>/<repo>.git"
    fi
}
