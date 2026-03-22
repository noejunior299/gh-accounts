#!/usr/bin/env bash
# gh-accounts :: agent.sh — SSH agent management (clean, reset, load, harden)
set -euo pipefail

# List github-* keys currently loaded in ssh-agent.
# Uses config_list_accounts to match loaded keys by their key file path.
# Output: key_path lines for matching github keys
_agent_list_github_keys() {
    local agent_keys
    agent_keys="$(ssh-add -l 2>/dev/null)" || true
    [[ -z "${agent_keys}" || "${agent_keys}" == *"no identities"* ]] && return 0

    local accounts
    accounts="$(config_list_accounts 2>/dev/null)" || true
    [[ -z "${accounts}" ]] && return 0

    while IFS='|' read -r acct email _alias _kp _mode _managed; do
        [[ -z "${acct}" ]] && continue
        # Match by key fingerprint: compute fingerprint and check if in agent
        kp=$(config_get_key_path "${acct}")
        [[ -z "${kp}" ]] && continue
        if [[ -f "${kp}.pub" ]]; then
            local fp
            fp="$(ssh-keygen -lf "${kp}.pub" 2>/dev/null | awk '{print $2}')" || continue
            if echo "${agent_keys}" | grep -q "${fp}"; then
                echo "${acct}|${email}|$(host_alias_for "${acct}")"
            fi
        fi
    done <<< "${accounts}"
}

# Count github keys in the agent
_agent_github_key_count() {
    local keys
    keys="$(_agent_list_github_keys)"
    if [[ -z "${keys}" ]]; then
        echo "0"
    else
        echo "${keys}" | wc -l
    fi
}

# Remove all GitHub identities from ssh-agent, preserving non-GitHub keys.
# Note: GNOME Keyring or system agents may re-inject keys. Use 'harden' for
# a permanent fix that ensures only per-host keys are offered.
agent_clean() {
    ensure_ssh_agent

    local keys
    keys="$(_agent_list_github_keys)"

    if [[ -z "${keys}" ]]; then
        log_info "No GitHub identities found in ssh-agent. Nothing to clean."
        return 0
    fi

    local removed=0 failed=0
    while IFS='|' read -r key_path acct email; do
        [[ -z "${key_path}" ]] && continue
        local success=0
        # Try pub key first, then private key
        for f in "${key_path}.pub" "${key_path}"; do
            if [[ -f "${f}" ]] && ssh-add -d "${f}" 2>/dev/null; then
                log_info "Removed: ${acct} (${key_path})"
                removed=$((removed + 1))
                success=1
                break
            fi
        done
        [[ ${success} -eq 0 ]] && failed=$((failed + 1))
    done <<< "${keys}"

    if [[ ${removed} -gt 0 ]]; then
        log_success "Cleaned ${removed} GitHub identity(ies) from ssh-agent."
    fi

    if [[ ${failed} -gt 0 ]]; then
        echo ""
        log_warn "${failed} key(s) could not be removed (system agent may re-inject them)."
        log_warn "For a permanent fix, run: gh-accounts harden"
        log_warn "This adds 'IdentitiesOnly yes' to SSH config, preventing agent key pollution."
    fi

    # Show remaining keys
    local remaining
    remaining="$(ssh-add -l 2>/dev/null)" || true
    if [[ -n "${remaining}" && "${remaining}" != *"no identities"* ]]; then
        echo ""
        log_info "Remaining keys in agent:"
        while IFS= read -r line; do
            echo "  ${line}"
        done <<< "${remaining}"
    else
        log_info "Agent is now empty."
    fi
}

# Remove all managed identities, then re-apply correct config.
agent_reset() {
    log_info "Resetting agent state for GitHub identities..."
    echo ""
    agent_clean
    echo ""
    log_success "Agent reset complete. GitHub keys removed, non-GitHub keys preserved."
    log_info "Use 'gh-accounts agent-load <name>' to selectively load a key when needed."
}

# Load a specific account's key into ssh-agent (on-demand).
agent_load() {
    local account="${1}"
    validate_account_name "${account}"

    local kp
    kp="$(key_path_for "${account}")"

    if [[ ! -f "${kp}" ]]; then
        die "Private key not found: ${kp}"
    fi

    ensure_ssh_agent

    # Check if already loaded by fingerprint
    if [[ -f "${kp}.pub" ]]; then
        local fp
        fp="$(ssh-keygen -lf "${kp}.pub" 2>/dev/null | awk '{print $2}')" || true
        if [[ -n "${fp}" ]] && ssh-add -l 2>/dev/null | grep -q "${fp}"; then
            log_info "Key for '${account}' is already loaded in ssh-agent."
            return 0
        fi
    fi

    ssh-add "${kp}" 2>/dev/null || die "Failed to add key to ssh-agent: ${kp}"
    log_success "Loaded key for '${account}' into ssh-agent."
}

# Show current agent status with GitHub key breakdown.
agent_status() {
    ensure_ssh_agent

    local all_keys
    all_keys="$(ssh-add -l 2>/dev/null)" || true

    if [[ -z "${all_keys}" || "${all_keys}" == *"no identities"* ]]; then
        log_info "No identities loaded in ssh-agent."
        return 0
    fi

    local total gh_count other_count
    total="$(echo "${all_keys}" | wc -l)"
    gh_count="$(_agent_github_key_count)"
    other_count=$((total - gh_count))

    echo ""
    log_info "Agent status:"
    echo "  Total keys:    ${total}"
    echo "  GitHub keys:   ${gh_count}"
    echo "  Other keys:    ${other_count}"
    echo ""

    if [[ ${gh_count} -gt 0 ]]; then
        log_info "GitHub identities loaded:"
        _agent_list_github_keys | while IFS='|' read -r kp acct email; do
            echo "  ● ${acct}  (${email})"
        done
        echo ""
    fi

    if [[ ${gh_count} -gt 1 ]]; then
        log_warn "Multiple GitHub keys loaded. This may cause 'Too many authentication failures'"
        log_warn "on non-GitHub SSH connections. Run 'gh-accounts agent-clean' to fix."
    fi
}

# Add 'Host * / IdentitiesOnly yes' to SSH config (safe, idempotent).
agent_harden() {
    ensure_ssh_config

    # Check if already hardened
    if grep -q "^Host \*" "${GH_SSH_CONFIG}" 2>/dev/null; then
        # Check if IdentitiesOnly is already set under Host *
        local in_wildcard=0
        while IFS= read -r line; do
            if [[ "${line}" =~ ^Host\ [*]$ ]]; then
                in_wildcard=1
                continue
            fi
            if [[ ${in_wildcard} -eq 1 ]]; then
                if [[ "${line}" =~ ^Host\  ]] && [[ "${line}" != "Host *" ]]; then
                    break
                fi
                if [[ "${line}" =~ ^[[:space:]]+IdentitiesOnly[[:space:]]+yes ]]; then
                    log_info "SSH config is already hardened (Host * / IdentitiesOnly yes)."
                    return 0
                fi
            fi
        done < "${GH_SSH_CONFIG}"
    fi

    # Auto-backup
    backup_create_auto

    # Prepend Host * block (must come before other Host blocks but after Include)
    local tmp_file
    tmp_file="$(mktemp)"

    # Preserve any Include lines at the top
    local header_done=0
    while IFS= read -r line; do
        if [[ ${header_done} -eq 0 ]]; then
            if [[ "${line}" == Include* ]]; then
                echo "${line}" >> "${tmp_file}"
                continue
            elif [[ -z "${line}" ]]; then
                echo "${line}" >> "${tmp_file}"
                continue
            fi
            header_done=1
            # Insert the hardening block
            {
                echo "Host *"
                echo "    IdentitiesOnly yes"
                echo ""
            } >> "${tmp_file}"
        fi
        echo "${line}" >> "${tmp_file}"
    done < "${GH_SSH_CONFIG}"

    # If file was empty or only had Include lines
    if [[ ${header_done} -eq 0 ]]; then
        {
            echo "Host *"
            echo "    IdentitiesOnly yes"
            echo ""
        } >> "${tmp_file}"
    fi

    mv "${tmp_file}" "${GH_SSH_CONFIG}"
    chmod 600 "${GH_SSH_CONFIG}"

    log_success "SSH config hardened. Added:"
    echo ""
    echo "  Host *"
    echo "      IdentitiesOnly yes"
    echo ""
    log_info "SSH will now only use keys explicitly specified per-host."
    log_info "This prevents agent key pollution on non-GitHub connections."
}
