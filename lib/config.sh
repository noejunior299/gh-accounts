#!/usr/bin/env bash
# gh-accounts :: config.sh — SSH config management (unified + split mode)
set -euo pipefail

build_host_block() {
    local account="${1}" email="${2}"
    local alias kp
    alias="$(host_alias_for "${account}")"
    kp="$(key_path_for "${account}")"
    cat <<EOF
# gh-accounts :: ${account} <${email}>
Host ${alias}
    HostName github.com
    User git
    IdentityFile ${kp}
    IdentitiesOnly yes
EOF
}

config_add_unified() {
    local account="${1}" email="${2}"
    ensure_ssh_config
    { echo ""; build_host_block "${account}" "${email}"; } >> "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"
    log_info "Added host block for '${account}' to ${GH_SSH_CONFIG}."
}

config_add_split() {
    local account="${1}" email="${2}"
    ensure_split_dir
    local alias split_file
    alias="$(host_alias_for "${account}")"
    split_file="${GH_SPLIT_DIR}/${alias}"
    [[ -f "${split_file}" ]] && die "Split config already exists: ${split_file}"
    build_host_block "${account}" "${email}" > "${split_file}"
    chmod 600 "${split_file}"
    log_info "Created split config ${split_file}."
}

config_remove_unified() {
    local account="${1}"
    [[ ! -f "${GH_SSH_CONFIG}" ]] && return 0
    local tmp_file
    tmp_file="$(mktemp)"
    sed -n '/^# gh-accounts :: '"${account}"' /,/^$/{ d }; p' "${GH_SSH_CONFIG}" > "${tmp_file}"
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${tmp_file}" 2>/dev/null || true
    mv "${tmp_file}" "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"
    log_info "Removed host block for '${account}' from ${GH_SSH_CONFIG}."
}

config_remove_split() {
    local account="${1}" alias split_file
    alias="$(host_alias_for "${account}")"
    split_file="${GH_SPLIT_DIR}/${alias}"
    [[ -f "${split_file}" ]] && rm -f "${split_file}" && log_info "Removed split config ${split_file}."
}

config_update_email_unified() {
    local account="${1}" new_email="${2}"
    [[ ! -f "${GH_SSH_CONFIG}" ]] && die "SSH config not found: ${GH_SSH_CONFIG}"
    grep -q "^# gh-accounts :: ${account} " "${GH_SSH_CONFIG}" 2>/dev/null || return 1
    sed -i "s/^# gh-accounts :: ${account} <.*>/# gh-accounts :: ${account} <${new_email}>/" "${GH_SSH_CONFIG}"
    log_info "Updated email for '${account}' in unified config."
}

config_update_email_split() {
    local account="${1}" new_email="${2}" alias split_file
    alias="$(host_alias_for "${account}")"
    split_file="${GH_SPLIT_DIR}/${alias}"
    [[ ! -f "${split_file}" ]] && return 1
    sed -i "s/^# gh-accounts :: ${account} <.*>/# gh-accounts :: ${account} <${new_email}>/" "${split_file}"
    log_info "Updated email for '${account}' in split config."
}

# Parse Host blocks from a single config file.
# Detects any Host entry whose HostName is github.com.
# Output per entry: account|email|alias|key_path|mode|managed
# "managed" is "yes" if the block has a gh-accounts comment, "no" otherwise.
_config_parse_file() {
    local file="${1}" mode="${2}"
    [[ -f "${file}" ]] || return 0
    local current_alias="" current_identity="" current_hostname="" is_managed="no" managed_email=""

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ ^#\ gh-accounts\ ::\ ([^\ ]+)\ \<([^>]+)\> ]]; then
            managed_email="${BASH_REMATCH[2]}"; is_managed="yes"; continue
        fi
        if [[ "${line}" =~ ^Host\ +(.+)$ ]]; then
            local new_alias="${BASH_REMATCH[1]}"
            _config_flush_block "${current_alias}" "${current_identity}" "${current_hostname}" "${mode}" "${is_managed}" "${managed_email}"
            current_alias="${new_alias}"
            current_identity="" current_hostname="" is_managed="no" managed_email=""
            continue
        fi
        if [[ -n "${current_alias}" ]]; then
            [[ "${line}" =~ ^[[:space:]]+HostName[[:space:]]+(.+)$ ]] && current_hostname="${BASH_REMATCH[1]}"
            [[ "${line}" =~ ^[[:space:]]+IdentityFile[[:space:]]+(.+)$ ]] && current_identity="${BASH_REMATCH[1]}"
        fi
    done < "${file}"
    _config_flush_block "${current_alias}" "${current_identity}" "${current_hostname}" "${mode}" "${is_managed}" "${managed_email}"
}

_config_flush_block() {
    local alias="${1}" identity="${2}" hostname="${3}" mode="${4}" is_managed="${5}" managed_email="${6}"
    [[ "${hostname}" == "github.com" ]] || return 0
    [[ -n "${alias}" ]] || return 0
    local acct
    if [[ "${alias}" == "github.com" ]]; then acct="default"
    elif [[ "${alias}" =~ ^github-(.+)$ ]]; then acct="${BASH_REMATCH[1]:-${alias}}"
    else acct="${alias}"; fi
    local key_path="${identity/#\~/$HOME}"
    local email
    if [[ -n "${managed_email}" ]]; then email="${managed_email}"
    else email="$(email_from_pubkey "${key_path}")"; fi
    echo "${acct}|${email}|${alias}|${key_path}|${mode}|${is_managed}"
}

# List all GitHub SSH accounts. Output: account|email|alias|key_path|mode|managed
config_list_accounts() {
    local found=0
    local seen_aliases=""

    # 1. Parse unified config
    if [[ -f "${GH_SSH_CONFIG}" ]]; then
        local results
        results="$(_config_parse_file "${GH_SSH_CONFIG}" "unified")" || true
        if [[ -n "${results}" ]]; then
            echo "${results}"
            # Track aliases to avoid duplicates from split
            while IFS='|' read -r _ _ a _ _ _; do
                seen_aliases="${seen_aliases}|${a}|"
            done <<< "${results}"
            found=1
        fi
    fi

    # 2. Parse split config files
    if [[ -d "${GH_SPLIT_DIR}" ]]; then
        for split_file in "${GH_SPLIT_DIR}"/github-*; do
            [[ -f "${split_file}" ]] || continue
            local results
            results="$(_config_parse_file "${split_file}" "split")" || true
            if [[ -n "${results}" ]]; then
                while IFS='|' read -r acct email alias kp mode managed; do
                    # Skip if already seen in unified config
                    if [[ "${seen_aliases}" == *"|${alias}|"* ]]; then
                        continue
                    fi
                    echo "${acct}|${email}|${alias}|${kp}|${mode}|${managed}"
                    found=1
                done <<< "${results}"
            fi
        done
    fi

    return $(( found == 0 ))
}

# Enable split mode: add Include directive to top of main config
config_enable_split_mode() {
    ensure_ssh_config
    ensure_split_dir
    local include_line="Include ${GH_SPLIT_DIR}/*"
    if grep -qF "${include_line}" "${GH_SSH_CONFIG}" 2>/dev/null; then
        log_warn "Split mode is already enabled."
        return 0
    fi
    local tmp_file
    tmp_file="$(mktemp)"
    { echo "${include_line}"; echo ""; cat "${GH_SSH_CONFIG}"; } > "${tmp_file}"
    mv "${tmp_file}" "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"
    log_success "Split mode enabled. Include directive added to ${GH_SSH_CONFIG}."
}

# Disable split mode: remove Include directive from main config
config_disable_split_mode() {
    [[ ! -f "${GH_SSH_CONFIG}" ]] && { log_warn "No SSH config found."; return 0; }
    local include_line="Include ${GH_SPLIT_DIR}/*"
    grep -qF "${include_line}" "${GH_SSH_CONFIG}" 2>/dev/null || { log_warn "Split mode is not enabled."; return 0; }
    sed -i "\|^${include_line}$|d" "${GH_SSH_CONFIG}"
    sed -i '/./,$!d' "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"
    log_success "Split mode disabled. Include directive removed from ${GH_SSH_CONFIG}."
}

# Merge all split configs into unified config
config_merge_all() {
    [[ ! -d "${GH_SPLIT_DIR}" ]] && { log_warn "No split config directory found."; return 0; }
    local count=0
    for split_file in "${GH_SPLIT_DIR}"/github-*; do
        [[ -f "${split_file}" ]] || continue
        echo "" >> "${GH_SSH_CONFIG}"
        cat "${split_file}" >> "${GH_SSH_CONFIG}"
        rm -f "${split_file}"
        count=$((count + 1))
    done
    if [[ ${count} -eq 0 ]]; then
        log_warn "No split config files found to merge."
        return 0
    fi
    chmod 600 "${GH_SSH_CONFIG}"
    log_success "Merged ${count} split config(s) into ${GH_SSH_CONFIG}."
    config_disable_split_mode
}

# Split gh-accounts blocks from unified config into per-account files
config_split_all() {
    [[ ! -f "${GH_SSH_CONFIG}" ]] && die "No SSH config found: ${GH_SSH_CONFIG}"
    ensure_split_dir
    local count=0 current_account="" current_block="" in_block=0
    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ gh-accounts\ ::\ ([^\ ]+) ]]; then
            if [[ -n "${current_account}" ]]; then
                _config_write_split_block "${current_account}" "${current_block}"
                count=$((count + 1))
            fi
            current_account="${BASH_REMATCH[1]}"
            current_block="${line}"
            in_block=1
        elif [[ ${in_block} -eq 1 ]]; then
            if [[ -z "${line}" ]]; then
                _config_write_split_block "${current_account}" "${current_block}"
                count=$((count + 1))
                current_account="" current_block="" in_block=0
            else
                current_block="${current_block}
${line}"
            fi
        fi
    done < "${GH_SSH_CONFIG}"
    if [[ -n "${current_account}" ]]; then
        _config_write_split_block "${current_account}" "${current_block}"
        count=$((count + 1))
    fi
    [[ ${count} -eq 0 ]] && { log_warn "No gh-accounts blocks found in unified config."; return 0; }
    # Remove blocks from unified config
    local tmp_file skip=0
    tmp_file="$(mktemp)"
    while IFS= read -r line; do
        if [[ "${line}" =~ ^#\ gh-accounts\ :: ]]; then skip=1; continue; fi
        if [[ ${skip} -eq 1 ]]; then
            [[ -z "${line}" ]] && { skip=0; continue; }
            continue
        fi
        echo "${line}" >> "${tmp_file}"
    done < "${GH_SSH_CONFIG}"
    mv "${tmp_file}" "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"
    config_enable_split_mode
    log_success "Split ${count} account(s) into ${GH_SPLIT_DIR}/."
}

# Internal: write a single block to a split config file
_config_write_split_block() {
    local account="${1}" block="${2}"
    local alias
    alias="$(host_alias_for "${account}")"
    echo "${block}" > "${GH_SPLIT_DIR}/${alias}"
    chmod 600 "${GH_SPLIT_DIR}/${alias}"
}

# Collect all host aliases managed by gh-accounts (for duplicate detection)
config_get_all_aliases() {
    local aliases=()
    if [[ -f "${GH_SSH_CONFIG}" ]]; then
        while IFS= read -r line; do
            [[ "${line}" =~ ^Host\ (github-[a-zA-Z0-9._-]+)$ ]] && aliases+=("${BASH_REMATCH[1]}")
        done < "${GH_SSH_CONFIG}"
    fi
    if [[ -d "${GH_SPLIT_DIR}" ]]; then
        for f in "${GH_SPLIT_DIR}"/github-*; do
            [[ -f "${f}" ]] || continue
            aliases+=("$(basename "${f}")")
        done
    fi
    printf '%s\n' "${aliases[@]}" | sort -u
}
