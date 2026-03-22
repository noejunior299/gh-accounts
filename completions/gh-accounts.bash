# =============================================================================
# gh-accounts :: bash completion script
# Install to /usr/share/bash-completion/completions/gh-accounts
# =============================================================================

_gh_accounts_completion() {
    local cur prev words cword
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    local commands="create list delete update switch test agent-status agent-load agent-clean agent-reset harden backup restore doctor split-mode merge-configs export version help"

    # Get all existing account names (if possible)
    local accounts=""
    if [[ -f ~/.ssh/config ]]; then
        accounts=$(grep -E "^Host github-" ~/.ssh/config | awk '{print $2}' | sed 's/github-//' | tr '\n' ' ')
    fi

    case "${COMP_CWORD}" in
        1)
            # First argument: complete with commands
            COMPREPLY=($(compgen -W "${commands}" -- "${cur}"))
            ;;
        2)
            # Second argument: context-dependent
            case "${prev}" in
                create)
                    # No completion for account name
                    ;;
                delete|rm)
                    COMPREPLY=($(compgen -W "${accounts}" -- "${cur}"))
                    ;;
                update)
                    COMPREPLY=($(compgen -W "${accounts}" -- "${cur}"))
                    ;;
                switch)
                    COMPREPLY=($(compgen -W "${accounts}" -- "${cur}"))
                    ;;
                test)
                    COMPREPLY=($(compgen -W "${accounts}" -- "${cur}"))
                    ;;
                agent-load)
                    COMPREPLY=($(compgen -W "${accounts}" -- "${cur}"))
                    ;;
                split-mode)
                    COMPREPLY=($(compgen -W "enable disable" -- "${cur}"))
                    ;;
                export)
                    COMPREPLY=($(compgen -W "--json" -- "${cur}"))
                    ;;
            esac
            ;;
        3)
            # Third argument: options
            case "${prev}" in
                --email)
                    # Email argument - no completion
                    ;;
            esac
            ;;
    esac

    return 0
}

complete -o bashdefault -o default -o nospace -F _gh_accounts_completion gh-accounts
