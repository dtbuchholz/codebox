# CLAUDE.md

Guidance for Claude Code when working with this repository.

## Project Overview

**Agent Box** - Remote Claude Code environment on Fly.io with tmux sessions, Tailscale access, and Telegram integration. This repo contains the infrastructure code for deploying and managing the VM.

## Quick Reference

```bash
make setup    # First-time setup (hooks + tool check)
make lint     # Run all linters
make qa       # Full QA: lint + test + build
make deploy   # Deploy to Fly.io
```

## Key Files

| File                          | Purpose                            |
| ----------------------------- | ---------------------------------- |
| `webhook/main.go`             | HTTP server for reply-from-phone   |
| `scripts/cc-*`                | Agent lifecycle commands           |
| `scripts/vm-setup.sh`         | Interactive VM setup wizard        |
| `config/entrypoint.sh`        | Container startup                  |
| `config/claude-settings.json` | Claude Code settings template (VM) |
| `Dockerfile`                  | Multi-stage build                  |
| `fly.toml.example`            | Fly.io config template             |

## Workflow Guidelines

1. **Read AGENTS.md** for code style and testing instructions
2. **Run `make setup`** before starting work (installs hooks)
3. **Commit frequently** - Small, focused commits after each logical change
4. **Never bypass hooks** - Fix issues, don't use `--no-verify`
5. **Format before committing** - `pnpm format` for MD/JSON/YAML

## VM Configuration Context

When modifying VM setup or documentation, be aware of these key configurations:

### Fly.io Secrets

| Variable             | Description                     |
| -------------------- | ------------------------------- |
| `TAILSCALE_AUTHKEY`  | Tailscale auth key (required)   |
| `AUTHORIZED_KEYS`    | SSH public keys (required)      |
| `ANTHROPIC_API_KEY`  | Claude API key                  |
| `OPENAI_API_KEY`     | For Takopi voice transcription  |
| `CLAUDE_CONFIG_REPO` | Git repo for Claude config sync |

### SSH Commit Signing

The VM uses SSH keys for commit signing. Key files:

- `~/.ssh/id_ed25519.pub` - SSH key (also used as signing key)
- `~/.ssh/allowed_signers` - Maps email to public key
- `~/.bashrc` - Contains `GIT_AUTHOR_*` and `GIT_COMMITTER_*` env vars

**Why env vars?** With API key auth (not OAuth), Claude Code defaults to `claude@anthropic.com` as commit author. The env vars override this to use the user's identity.

### Git Credential Helper

`gh auth setup-git` configures git to use GitHub CLI for HTTPS authentication, enabling clones like `git clone https://github.com/...` without password prompts.

## Common Issues

### Disk Space

The 10GB default volume fills quickly with JS projects. Common space hogs:

- `~/.local/share/pnpm` (2-5GB) - prune with `pnpm store prune`
- `~/.cache/ms-playwright` (900MB) - safe to delete
- `/data/swapfile` (2GB) - do NOT delete

Extend volume: `fly volumes extend <vol-id> -s 20`

### Linting

Shell scripts: `shellcheck -e SC1091 scripts/* config/*.sh config/git-hooks/*`

The `-e SC1091` ignores "can't follow sourced file" warnings.
