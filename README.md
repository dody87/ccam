# claude-accounts

Manage multiple Claude Code accounts on macOS — check usage at a glance and switch between them instantly.

```
╔══════════════════════════════════╗
║      Claude Account Status       ║
╚══════════════════════════════════╝

▸ personal  [active]
  ~/.claude-personal
  ████████████░░░░░░░░ 62% used
  Plan:  Claude Pro
  Reset: in 1h 23m

▸ work
  ~/.claude-work
  ███░░░░░░░░░░░░░░░░░ 18% used
  Plan:  Claude Team
  Reset: in 3h 41m
```

## How it works

Claude Code stores credentials in the macOS Keychain under a key derived from the `CLAUDE_CONFIG_DIR` environment variable. By using separate directories (e.g. `~/.claude-personal`, `~/.claude-work`), each account gets its own isolated credentials and usage limits.

`claude-status` reads the OAuth token for each detected account and queries `api.anthropic.com/api/oauth/usage` to show real-time utilization.

`claude-switch` activates an account by pointing `~/.claude` (a symlink) to the target config directory, so the bare `claude` command always uses whichever account is active.

Account discovery is automatic: any directory matching `~/.claude-*` is treated as an account. No config files to maintain.

## Requirements

- **macOS only** — `claude-status` uses `security find-generic-password` (macOS Keychain) to retrieve OAuth tokens; there is no Linux equivalent
- Claude Code installed (`npm install -g @anthropic-ai/claude-code`)
- Python 3 (pre-installed on macOS)
- zsh or bash

## Installation

```bash
git clone https://github.com/dody87/ccam
cd ccam
bash install.sh
source ~/.zshrc
```

## Setup

Create a directory for each account:

```bash
mkdir ~/.claude-personal
mkdir ~/.claude-work
```

Authenticate each one (Claude Code's `/login` flow saves credentials to the macOS Keychain):

```bash
claude-personal   # opens Claude Code with ~/.claude-personal as config dir
# inside Claude Code: /login

claude-work
# inside Claude Code: /login
```

That's it. The `claude-<name>` aliases are generated automatically for every `~/.claude-*` directory at shell startup.

## Usage

### See all accounts

```bash
claude-status
```

Shows usage bar (5-hour limit), plan name, and time until reset for every detected account. The active account is highlighted.

### Switch accounts

```bash
# Interactive menu
claude-switch

# Direct switch
claude-switch personal
claude-switch work

# List available accounts
claude-switch --list
```

Switching creates a symlink `~/.claude → ~/.claude-<name>`, so the bare `claude` command immediately picks up the new account without any extra flags.

### Use a specific account directly

```bash
claude-personal
claude-work
```

These aliases set `CLAUDE_CONFIG_DIR` on the fly without modifying `~/.claude`. Useful for running two accounts in parallel in separate terminal tabs.

## How `claude-switch` works

```
~/.claude  →  ~/.claude-personal   (symlink managed by claude-switch)
~/.claude-personal/               (credentials, settings, projects)
~/.claude-work/                   (credentials, settings, projects)
```

If `~/.claude` is a real directory (not a symlink) when you first run `claude-switch`, it's backed up to `~/.claude-default-backup` automatically.

## Acknowledgements

Based on the multi-account pattern documented in [this gist by KMJ-007](https://gist.github.com/KMJ-007/0979814968722051620461ab2aa01bf2). The OAuth usage endpoint and Keychain derivation were documented by the community in that thread.

## License

MIT
