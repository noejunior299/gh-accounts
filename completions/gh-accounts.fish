# =============================================================================
# gh-accounts :: fish completion script
# Install to ~/.config/fish/completions/gh-accounts.fish
# =============================================================================

# Main commands
set -l commands 'create' 'list' 'ls' 'delete' 'rm' 'update' 'switch' 'test' \
    'agent-status' 'agent-load' 'agent-clean' 'agent-reset' 'harden' \
    'backup' 'restore' 'doctor' 'split-mode' 'merge-configs' 'export' \
    'version' 'help'

# Main command completions
complete -c gh-accounts -n '__fish_use_subcommand_from_list $commands' -f
complete -c gh-accounts -n '__fish_seen_subcommand_from $commands' -f

# Create command
complete -c gh-accounts -n '__fish_use_subcommand_from_list create' -f -a '<name>' -d 'Account name'
complete -c gh-accounts -n '__fish_seen_subcommand_from create' -f -a '<email>' -d 'Email address'

# Delete/remove command
complete -c gh-accounts -n '__fish_use_subcommand_from_list delete rm' -f -a '(__fish_seen_subcommand_from delete rm && string match "github-*" ~/.ssh/config | sed "s/.*Host github-//")' -d 'Account name'

# Update command
complete -c gh-accounts -n '__fish_use_subcommand_from_list update' -f -a '(__fish_seen_subcommand_from update && string match "github-*" ~/.ssh/config | sed "s/.*Host github-//")' -d 'Account name'
complete -c gh-accounts -n '__fish_seen_subcommand_from update' -f -a '--email' -d 'Set new email'

# Switch command
complete -c gh-accounts -n '__fish_use_subcommand_from_list switch' -f -a '(__fish_seen_subcommand_from switch && string match "github-*" ~/.ssh/config | sed "s/.*Host github-//")' -d 'Account name'
complete -c gh-accounts -n '__fish_seen_subcommand_from switch' -f -a '--global' -d 'Set globally instead of locally'

# Test command
complete -c gh-accounts -n '__fish_use_subcommand_from_list test' -f -a '(__fish_seen_subcommand_from test && string match "github-*" ~/.ssh/config | sed "s/.*Host github-//")' -d 'Account name'

# Agent-load command
complete -c gh-accounts -n '__fish_use_subcommand_from_list agent-load' -f -a '(__fish_seen_subcommand_from agent-load && string match "github-*" ~/.ssh/config | sed "s/.*Host github-//")' -d 'Account name'

# Split-mode command
complete -c gh-accounts -n '__fish_use_subcommand_from_list split-mode' -f -a 'enable disable' -d 'Enable or disable split mode'

# Export command
complete -c gh-accounts -n '__fish_use_subcommand_from_list export' -f -a '--json' -d 'Export as JSON'

# Global commands
complete -c gh-accounts -n '__fish_use_subcommand_from_list list ls' -f -d 'List all configured accounts'
complete -c gh-accounts -n '__fish_use_subcommand_from_list agent-status' -f -d 'Show agent key breakdown'
complete -c gh-accounts -n '__fish_use_subcommand_from_list agent-clean' -f -d 'Remove GitHub keys from agent'
complete -c gh-accounts -n '__fish_use_subcommand_from_list agent-reset' -f -d 'Reset SSH agent'
complete -c gh-accounts -n '__fish_use_subcommand_from_list harden' -f -d 'Add IdentitiesOnly to SSH config'
complete -c gh-accounts -n '__fish_use_subcommand_from_list backup' -f -d 'Create a backup'
complete -c gh-accounts -n '__fish_use_subcommand_from_list restore' -f -d 'Restore from backup'
complete -c gh-accounts -n '__fish_use_subcommand_from_list doctor' -f -d 'Run diagnostic checks'
complete -c gh-accounts -n '__fish_use_subcommand_from_list merge-configs' -f -d 'Merge split configs'
complete -c gh-accounts -n '__fish_use_subcommand_from_list version' -f -d 'Print version'
complete -c gh-accounts -n '__fish_use_subcommand_from_list help' -f -d 'Show help message'
