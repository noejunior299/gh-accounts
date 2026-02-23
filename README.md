# gh-accounts

> Manage multiple GitHub SSH identities on Linux & macOS — securely, scalably, and without external dependencies.

---

## Why This Tool Exists

When you work with multiple GitHub accounts (personal, work, freelance, open-source orgs), SSH key and config management becomes error-prone and tedious. Manually editing `~/.ssh/config`, juggling key files, and remembering host aliases is fragile at scale.

**gh-accounts** automates this entirely — creating keys, configuring SSH, testing auth, and maintaining backups — while enforcing correct permissions and providing clear diagnostics.

---

## Features

- **Create** SSH key pairs and config entries in one command
- **List** all managed accounts with status indicators
- **Delete** accounts and clean up keys + config
- **Update** account email addresses
- **Test** SSH authentication against GitHub
- **Backup** and **restore** your entire SSH configuration
- **Doctor** — diagnostics for permissions, agent, duplicates, integrity
- **Split mode** — optional per-account config files for team/org setups
- **Merge / split** configs between unified and split modes
- **Export** accounts as structured JSON
- Zero external dependencies — only native Linux tools

---

## Installation

### From source (recommended)

```bash
git clone https://github.com/noejunior792/gh-accounts.git
cd gh-accounts
sudo bash install.sh
```

### One-liner (remote)

```bash
curl -fsSL https://raw.githubusercontent.com/noejunior792/gh-accounts/main/install.sh | sudo bash
```

### Uninstall

```bash
sudo bash uninstall.sh
```

Or if installed remotely:

```bash
sudo rm -f /usr/local/bin/gh-accounts
sudo rm -rf /usr/local/share/gh-accounts
```

---

## Usage

### Create an account

```bash
gh-accounts create work work@company.com
gh-accounts create personal me@gmail.com
```

This will:
1. Generate an `ed25519` SSH key pair at `~/.ssh/github-<name>`
2. Add a `Host github-<name>` block to `~/.ssh/config`
3. Add the key to `ssh-agent`
4. Print the public key for you to add to GitHub

### List accounts

```bash
gh-accounts list
```

### Test authentication

```bash
gh-accounts test work
```

### Update email

```bash
gh-accounts update work --email new@company.com
```

### Delete an account

```bash
gh-accounts delete personal
```

### Backup & Restore

```bash
gh-accounts backup
gh-accounts restore
```

### Diagnostics

```bash
gh-accounts doctor
```

### Export as JSON

```bash
gh-accounts export --json
```

### Split mode

```bash
gh-accounts split-mode enable     # Per-account files in ~/.ssh/gh-accounts/
gh-accounts split-mode disable    # Remove Include directive
gh-accounts merge-configs         # Merge split files back into unified config
```

### Switch git identity

```bash
gh-accounts switch work              # sets user.name + user.email in the current repo
gh-accounts switch personal --global  # sets them globally (~/.gitconfig)
```

This runs `git config user.name` and `git config user.email` so your commits are attributed to the correct account — no manual editing needed.

### Clone with a specific account

```bash
git clone git@github-work:org/repo.git
git clone git@github-personal:user/repo.git
```

---

## Architecture

```
gh-accounts/
├── bin/
│   └── gh-accounts          # CLI entry point — command router
├── lib/
│   ├── utils.sh             # Colors, logging, validation, constants
│   ├── config.sh            # SSH config read/write (unified + split)
│   ├── account.sh           # Account CRUD, test, export
│   ├── backup.sh            # Backup and restore
│   └── doctor.sh            # Diagnostic checks
├── install.sh               # System-wide installer
├── uninstall.sh             # Clean uninstaller
├── VERSION                  # Semantic version
├── LICENSE                  # MIT
└── README.md
```

Each module is independently sourced by the CLI. The entry point (`bin/gh-accounts`) resolves the library directory whether run from source or from `/usr/local/`.

---

## Unified vs. Split Mode

### Unified (default)

All account host blocks live in a single file:

```
~/.ssh/config
```

```ssh-config
# gh-accounts :: work <work@company.com>
Host github-work
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-work
    IdentitiesOnly yes

# gh-accounts :: personal <me@gmail.com>
Host github-personal
    HostName github.com
    User git
    IdentityFile ~/.ssh/github-personal
    IdentitiesOnly yes
```

### Split mode

Each account gets its own file under `~/.ssh/gh-accounts/`:

```
~/.ssh/gh-accounts/github-work
~/.ssh/gh-accounts/github-personal
```

The main config includes them via:

```ssh-config
Include ~/.ssh/gh-accounts/*
```

Split mode is useful when:
- You share config snippets across machines via dotfiles
- You want per-account version control
- You manage a large number of identities

Switch freely between modes — `merge-configs` and `split-mode enable/disable` handle the migration.

---

## Security

- **Private keys** are generated with `ed25519` (modern, fast, secure)
- **Permissions** are enforced automatically:
  - `~/.ssh/` → `700`
  - Private keys → `600`
  - Public keys → `644`
  - Config files → `600`
- **Automatic backups** are created before any destructive operation
- **ssh-agent** is validated and started if needed
- **Duplicate detection** prevents alias collisions
- **No secrets** are ever printed or logged (only public keys)

---

## Compatibility

| Requirement | Supported |
|---|---|
| Linux (any distro) | ✅ |
| macOS | ✅ |
| Bash 4.3+ / 5.x | ✅ |
| Fish shell | ✅ (CLI is bash, works from any shell) |
| OpenSSH | ✅ (ssh, ssh-keygen, ssh-agent, ssh-add) |
| External deps | None — only coreutils, grep, sed, awk |

---

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit with clear messages
4. Open a Pull Request against `main`

### Guidelines

- Keep modules under 300 lines
- Use functions — no inline logic
- Add color-coded output for user-facing messages
- Validate all inputs
- Fail safely — never leave config in a broken state
- Test on Ubuntu 22.04+ with bash 5.x

---

## Roadmap

- [x] `gh-accounts switch <name> [--global]` — set `user.name` and `user.email` for the current repo (default) or globally, so commits are attributed to the correct identity
- [ ] `gh-accounts import` — import existing SSH keys into management
- [ ] `gh-accounts config` — interactive setup wizard
- [ ] Shell completions for bash and fish
- [ ] Man page generation
- [ ] Optional GPG-signed key metadata
- [ ] CI/CD pipeline with ShellCheck and BATS tests
- [ ] AUR / PPA / Snap packaging

---

## License

[MIT](LICENSE)

---

**gh-accounts** — One machine. Many GitHub identities. Zero friction.
