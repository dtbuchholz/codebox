# AGENTS.md

Configuration for AI assistants working on this codebase.

## Project Overview

**Agent Box** - Remote Claude Code environment on Fly.io. See [README.md](./README.md) for full user documentation.

This repo contains:

- Docker image for the VM (Dockerfile, config/entrypoint.sh)
- Agent lifecycle scripts (scripts/cc-\*)
- VM setup wizard (scripts/vm-setup.sh)
- Webhook server for reply-from-phone (webhook/main.go)
- Configuration templates (fly.toml.example, config/\*.example)

## Quick Commands

```bash
# Quality checks
make lint         # Run all linters
make test         # Run tests
make qa           # Full QA: lint + test + build

# Build & Deploy
make build        # Build Docker image
make deploy       # Deploy to Fly.io

# Formatting
pnpm format       # Format MD/JSON/YAML with Prettier
```

## Repository Structure

```
codebox/
├── webhook/              # Go HTTP server for reply-from-phone
│   ├── main.go           # HTTP handlers: /inbox, /send, /agents
│   ├── go.mod
│   └── .golangci.yml     # Go linter config
├── scripts/              # Agent lifecycle CLI tools
│   ├── cc-new            # Create new agent (supports @project/branch worktrees)
│   ├── cc-stop           # Stop agent (graceful + force)
│   ├── cc-ls             # List running agents
│   ├── cc-attach         # Attach to agent session
│   ├── config.sh         # TOML config utilities
│   ├── healthcheck.sh    # Service monitoring (60s interval)
│   ├── vm-setup.sh       # Interactive VM setup wizard
│   ├── claude-config-sync # Sync Claude config from remote repo
│   ├── claude-hook-check-push # PreToolUse hook to block main/master pushes
│   ├── takopi-restart    # Restart Takopi bot
│   └── bootstrap.sh      # Fresh VM setup script
├── config/               # Container configuration
│   ├── entrypoint.sh     # Container startup (tailscale, sshd, webhook, etc.)
│   ├── claude-settings.json # Claude Code settings template for VM
│   ├── git-hooks/        # Git hooks (pre-push blocks main/master)
│   └── *.example         # Config templates
├── Makefile              # Build/deploy commands
├── justfile              # Alternative task runner (uses app_name variable)
├── Dockerfile            # Multi-stage build (Go webhook + Debian runtime)
└── fly.toml.example      # Fly.io config template (shared-cpu-4x, 8gb, 10gb volume)
```

## Code Style

### Go

- Standard Go conventions with `golangci-lint`
- Error handling: always check errors, use descriptive messages
- Format with `go fmt` and `goimports`

### Shell Scripts

- Shebang: `#!/bin/bash`
- Error handling: `set -e` at top
- Quote variables: `"$VAR"` not `$VAR`
- Use `shellcheck` for linting (ignore SC1091 for sourced files)
- Scripts in `scripts/` should be idempotent where possible

### Dockerfile

- Multi-stage builds to minimize image size
- Pin base image versions (e.g., `debian:bookworm-slim`)
- Combine RUN commands to reduce layers
- Use `hadolint` for linting (ignore DL3008, DL3013)

### Markdown/JSON/YAML

- Format with Prettier: `pnpm format`
- Check formatting: `pnpm format:check`

## Git Workflow

### Pre-commit Hooks

Automatically run on `git commit`:

- Trailing whitespace / EOF fixes
- YAML/JSON/TOML validation
- Shell script linting (shellcheck)
- Dockerfile linting (hadolint)
- Go formatting and linting

### Pre-push Hooks

Automatically run on `git push`:

- Go build verification
- Full syntax check on shell scripts

### Commit Messages

- Use imperative mood: "Add feature" not "Added feature"
- Keep first line under 72 characters
- Use conventional commit prefixes: `feat:`, `fix:`, `docs:`, `refactor:`

## Testing

```bash
# Go tests
cd webhook && go test -v ./...

# Shell script syntax
bash -n scripts/vm-setup.sh
shellcheck -e SC1091 scripts/* config/*.sh config/git-hooks/*

# Docker build
make build
```

## Key Implementation Details

### VM Environment Setup

The `vm-setup.sh` script configures:

1. **Git identity** - user.name, user.email
2. **SSH key** - generates ed25519 key for GitHub
3. **SSH commit signing** - configures git to sign commits with SSH key
4. **Git author env vars** - `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL` in `~/.bashrc` (required for verified commits when using API key auth)
5. **GitHub CLI** - `gh auth login` + `gh auth setup-git` (enables HTTPS clones)
6. **Takopi** - Telegram bot setup

### Fly.io Secrets

These env vars are set via `fly secrets set` and exported to the agent user by `entrypoint.sh`:

| Variable             | Description                     |
| -------------------- | ------------------------------- |
| `TAILSCALE_AUTHKEY`  | Tailscale auth key (required)   |
| `AUTHORIZED_KEYS`    | SSH public keys (required)      |
| `ANTHROPIC_API_KEY`  | Claude API key                  |
| `OPENAI_API_KEY`     | For Takopi voice transcription  |
| `CLAUDE_CONFIG_REPO` | Git repo for Claude config sync |
| `AUTO_UPDATE_CLAUDE` | Auto-update Claude Code on boot |

### Branch Protection

Claude Code on the VM is blocked from pushing to main/master via:

1. **PreToolUse hook** (`config/claude-settings.json`) - runs `claude-hook-check-push` before Bash commands
2. **Git pre-push hook** (`config/git-hooks/pre-push`) - optional additional protection

---

## Agent Configurations

### verify-app

Verification agent for this project.

**Commands:**

```bash
make lint
make test
make build
```

**Success Criteria:**

- All linters pass (Go, shell, Docker)
- All tests pass
- Docker build succeeds

**On Failure:**

- For Go lint errors: run `make format`
- For shell errors: fix shellcheck warnings manually
- For test failures: investigate and fix

### code-simplifier

**Focus Areas:**

- Remove unused code and imports
- Simplify complex shell logic
- Use Go idioms (error wrapping, defer)
- Keep functions focused and small

**Constraints:**

- Preserve all existing functionality
- Don't change CLI interfaces without explicit approval
- Shell scripts should remain POSIX-compatible where practical

### code-reviewer

**Review Checklist:**

- Error handling in Go (no ignored errors)
- Shell scripts use `set -e` and quote variables
- Dockerfile follows best practices (multi-stage, minimal layers)
- No hardcoded secrets
- Proper logging in Go code

**Project-Specific Rules:**

- Agent lifecycle scripts (cc-\*) must be idempotent
- Webhook endpoints must validate input
- Notification hooks must handle missing environment gracefully
- Always update README.md when adding new Fly.io secrets or VM features
