# AGENTS.md

Configuration for AI assistants working on this codebase.

## Project Overview

**Agent Box** - Remote Claude Code environment on Fly.io with tmux sessions, Tailscale access, and push notifications. Run long-lived AI coding agents in the cloud, reconnect from anywhere (including iOS), and get notified when they need input.

## Tech Stack

- **Go 1.22+**: Webhook receiver (`webhook/`)
- **Shell (Bash)**: Agent lifecycle scripts, hooks, entrypoint
- **Docker**: Multi-stage build for Fly.io deployment
- **Fly.io**: Cloud platform with persistent volumes
- **Tailscale**: Private network access (no public SSH)
- **ntfy**: Push notifications

## Quick Commands

```bash
# First-time setup (installs tools + git hooks)
make setup

# Or run the bootstrap script (for fresh VMs)
./scripts/bootstrap.sh

# Quality checks
make lint         # Run all linters
make format       # Auto-format code
make test         # Run tests
make qa           # Full QA: lint + test + build

# Build & Deploy
make build        # Build Docker image locally
make deploy       # Deploy to Fly.io

# Operations
make status       # Check Fly machine status
make logs         # View Fly logs
make ssh          # SSH into the machine
```

## Architecture

```
codebox/
├── webhook/              # Go HTTP server for reply-from-phone
│   ├── main.go           # HTTP handlers: /inbox, /send, /agents
│   ├── go.mod
│   └── .golangci.yml     # Go linter config
├── scripts/              # Agent lifecycle CLI tools
│   ├── cc-new            # Create new agent (tmux + claude)
│   ├── cc-stop           # Stop agent
│   ├── cc-ls             # List running agents
│   ├── cc-attach         # Attach to agent session
│   ├── notify.sh         # Send ntfy push notification
│   └── bootstrap.sh      # Fresh VM setup script
├── hooks/                # Claude Code notification hooks
│   ├── notification-hook.sh  # General notifications → push
│   └── prompt-hook.sh        # Input needed → push
├── config/               # Container configuration
│   ├── entrypoint.sh     # Container startup (tailscale, sshd, webhook)
│   ├── claude-settings.json  # Claude Code hook config
│   └── notify.conf.example   # Notification settings template
├── Dockerfile            # Multi-stage build
├── fly.toml              # Fly.io deployment config
└── deploy.sh             # Deployment script
```

## Code Style

### Go

- Standard Go conventions with `golangci-lint`
- Error handling: always check errors, use descriptive messages
- Naming: camelCase, exported names start with uppercase
- Format with `go fmt` and `goimports`

### Shell Scripts

- Shebang: `#!/bin/bash`
- Error handling: `set -e` at top
- Quote variables: `"$VAR"` not `$VAR`
- Use `shellcheck` for linting (ignore SC1091 for sourced files)

### Dockerfile

- Multi-stage builds to minimize image size
- Pin base image versions (e.g., `debian:bookworm-slim`)
- Combine RUN commands to reduce layers
- Use `hadolint` for linting

## Git Workflow

### Pre-commit Hooks

Automatically run on `git commit`:

- Trailing whitespace / EOF fixes
- YAML/JSON/TOML validation
- Shell script linting (shellcheck)
- Dockerfile linting (hadolint)
- Go formatting and linting (golangci-lint)

### Pre-push Hooks

Automatically run on `git push`:

- Go build verification
- Full syntax check on shell scripts

### Commit Messages

- Use imperative mood: "Add feature" not "Added feature"
- Keep first line under 72 characters
- Reference issues if applicable

## Testing

### Go Tests

```bash
cd webhook && go test -v ./...
```

### Shell Script Testing

```bash
bash -n script.sh      # Syntax check
shellcheck script.sh   # Lint
```

### Docker Build

```bash
make build             # Full build
make dev-build && make dev-run  # Local testing
```

## Directory Conventions (On Deployed Machine)

```
/data/                    # Persistent Fly volume
├── repos/                # Clone repositories here
├── worktrees/            # Git worktrees (one per agent/branch)
├── logs/<agent>/         # Logs per agent
├── inbox/<agent>.txt     # Reply-from-phone messages
├── home/agent/           # Persistent home directory
│   ├── .claude/          # Claude Code config & hooks
│   └── .ssh/             # SSH authorized_keys
└── config/
    ├── authorized_keys   # SSH keys (alternative location)
    ├── notify.conf       # Notification settings
    ├── tailscale.state   # Tailscale state
    └── ssh_host_*        # SSH host keys
```

## Security Notes

- SSH key auth only (no passwords)
- Tailscale-only network access (no public ports)
- Webhook auth token optional but recommended
- Secrets via Fly.io secrets, not env files

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

- For Go lint errors: run `make format-go`
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
