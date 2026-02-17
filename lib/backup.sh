#!/usr/bin/env bash
# =============================================================================
# gh-accounts :: backup.sh
# Backup and restore SSH configuration and keys managed by gh-accounts.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Create a timestamped backup
# ---------------------------------------------------------------------------
backup_create() {
    ensure_backup_dir

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${GH_BACKUP_DIR}/${timestamp}"

    mkdir -p "${backup_path}"
    chmod 700 "${backup_path}"

    local count=0

    # Backup unified config
    if [[ -f "${GH_SSH_CONFIG}" ]]; then
        cp -p "${GH_SSH_CONFIG}" "${backup_path}/config"
        count=$((count + 1))
    fi

    # Backup all gh-accounts keys
    for key_file in "${GH_SSH_DIR}"/${GH_KEY_PREFIX}-*; do
        [[ -f "${key_file}" ]] || continue
        cp -p "${key_file}" "${backup_path}/"
        count=$((count + 1))
    done

    # Backup split configs
    if [[ -d "${GH_SPLIT_DIR}" ]]; then
        local split_backup="${backup_path}/split"
        mkdir -p "${split_backup}"
        for split_file in "${GH_SPLIT_DIR}"/github-*; do
            [[ -f "${split_file}" ]] || continue
            cp -p "${split_file}" "${split_backup}/"
            count=$((count + 1))
        done
    fi

    if [[ ${count} -eq 0 ]]; then
        rm -rf "${backup_path}"
        log_warn "Nothing to back up."
        return 0
    fi

    log_success "Backup created: ${backup_path} (${count} file(s))."
}

# ---------------------------------------------------------------------------
# Auto-backup (silent, before destructive operations)
# ---------------------------------------------------------------------------
backup_create_auto() {
    ensure_backup_dir

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local backup_path="${GH_BACKUP_DIR}/auto_${timestamp}"

    mkdir -p "${backup_path}"
    chmod 700 "${backup_path}"

    # Backup config silently
    if [[ -f "${GH_SSH_CONFIG}" ]]; then
        cp -p "${GH_SSH_CONFIG}" "${backup_path}/config"
    fi

    # Backup keys silently
    for key_file in "${GH_SSH_DIR}"/${GH_KEY_PREFIX}-*; do
        [[ -f "${key_file}" ]] || continue
        cp -p "${key_file}" "${backup_path}/"
    done

    # Backup split configs silently
    if [[ -d "${GH_SPLIT_DIR}" ]]; then
        local split_backup="${backup_path}/split"
        mkdir -p "${split_backup}"
        for split_file in "${GH_SPLIT_DIR}"/github-*; do
            [[ -f "${split_file}" ]] || continue
            cp -p "${split_file}" "${split_backup}/"
        done
    fi
}

# ---------------------------------------------------------------------------
# List available backups
# ---------------------------------------------------------------------------
backup_list() {
    ensure_backup_dir

    local backups=()
    for d in "${GH_BACKUP_DIR}"/*/; do
        [[ -d "${d}" ]] || continue
        backups+=("$(basename "${d}")")
    done

    if [[ ${#backups[@]} -eq 0 ]]; then
        log_info "No backups found."
        return 0
    fi

    echo ""
    log_info "Available backups:"
    echo ""
    for b in "${backups[@]}"; do
        local file_count
        file_count="$(find "${GH_BACKUP_DIR}/${b}" -type f | wc -l)"
        local prefix=""
        if [[ "${b}" == auto_* ]]; then
            prefix=" ${CLR_YELLOW}(auto)${CLR_RESET}"
        fi
        echo -e "  ${CLR_BOLD}${b}${CLR_RESET}  —  ${file_count} file(s)${prefix}"
    done
    echo ""
}

# ---------------------------------------------------------------------------
# Restore from a backup (interactive selection)
# ---------------------------------------------------------------------------
backup_restore() {
    ensure_backup_dir

    local backups=()
    for d in "${GH_BACKUP_DIR}"/*/; do
        [[ -d "${d}" ]] || continue
        backups+=("$(basename "${d}")")
    done

    if [[ ${#backups[@]} -eq 0 ]]; then
        die "No backups available to restore."
    fi

    echo ""
    log_info "Available backups:"
    echo ""
    local i=1
    for b in "${backups[@]}"; do
        local file_count
        file_count="$(find "${GH_BACKUP_DIR}/${b}" -type f | wc -l)"
        echo "  [${i}] ${b}  (${file_count} files)"
        i=$((i + 1))
    done
    echo ""

    local choice
    echo -n "  Select backup number to restore: "
    read -r choice

    if [[ ! "${choice}" =~ ^[0-9]+$ ]] || [[ ${choice} -lt 1 ]] || [[ ${choice} -gt ${#backups[@]} ]]; then
        die "Invalid selection."
    fi

    local selected="${backups[$((choice - 1))]}"
    local restore_path="${GH_BACKUP_DIR}/${selected}"

    if ! confirm "Restore from '${selected}'? Current config and keys will be overwritten."; then
        log_info "Aborted."
        return 0
    fi

    # Create a safety backup first
    backup_create_auto

    # Restore unified config
    if [[ -f "${restore_path}/config" ]]; then
        cp -p "${restore_path}/config" "${GH_SSH_CONFIG}"
        chmod 600 "${GH_SSH_CONFIG}"
        log_info "Restored ${GH_SSH_CONFIG}."
    fi

    # Restore keys
    for key_file in "${restore_path}"/${GH_KEY_PREFIX}-*; do
        [[ -f "${key_file}" ]] || continue
        local basename
        basename="$(basename "${key_file}")"
        cp -p "${key_file}" "${GH_SSH_DIR}/${basename}"
        set_key_permissions "${GH_SSH_DIR}/${basename}"
        log_info "Restored ${GH_SSH_DIR}/${basename}."
    done

    # Restore split configs
    if [[ -d "${restore_path}/split" ]]; then
        ensure_split_dir
        for split_file in "${restore_path}/split"/github-*; do
            [[ -f "${split_file}" ]] || continue
            local basename
            basename="$(basename "${split_file}")"
            cp -p "${split_file}" "${GH_SPLIT_DIR}/${basename}"
            chmod 600 "${GH_SPLIT_DIR}/${basename}"
            log_info "Restored ${GH_SPLIT_DIR}/${basename}."
        done
    fi

    log_success "Restore from '${selected}' completed."
}
