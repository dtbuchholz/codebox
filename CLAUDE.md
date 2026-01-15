# Claude Code Guidelines

## Project Overview

Agent Box - Remote Claude Code environment on Fly.io with tmux sessions, Tailscale access, and push notifications.

## Tech Stack

- **Go 1.22+**: Webhook receiver (`webhook/`)
- **Shell (Bash)**: Agent lifecycle scripts (`scripts/`), hooks (`hooks/`), entrypoint (`config/`)
- **Docker**: Container image for Fly.io deployment
- **Fly.io**: Cloud platform for deployment

## Directory Structure

```
codebox/
├── webhook/           # Go HTTP server for reply-from-phone
│   ├── main.go
│   ├── go.mod
│   └── .golangci.yml  # Go linter config
├── scripts/           # Agent lifecycle CLI tools
│   ├── cc-new         # Create agent
│   ├── cc-stop        # Stop agent
│   ├── cc-ls          # List agents
│   ├── cc-attach      # Attach to agent
│   └── notify.sh      # Send ntfy notification
├── hooks/             # Claude Code notification hooks
├── config/            # Container config files
└── Dockerfile         # Multi-stage build
```

## Development Commands

```bash
make setup      # Install pre-commit hooks and check tools
make lint       # Run all linters (Go, shell, Docker)
make format     # Auto-format Go code
make test       # Run Go tests
make qa         # Full QA: lint + test + build
make build      # Build Docker image locally
```

## Code Style

### Go
- Follow standard Go conventions
- Use `golangci-lint` for static analysis
- Error handling: always check errors, use descriptive messages
- Naming: use camelCase, exported names start with uppercase

### Shell Scripts
- Use `#!/bin/bash` shebang
- Set `set -e` for error handling
- Quote variables: `"$VAR"` not `$VAR`
- Use `shellcheck` for linting (ignore SC1091 for sourced files)

### Dockerfile
- Use multi-stage builds to minimize image size
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
- Go formatting and linting

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
Manual testing with:
```bash
bash -n script.sh  # Syntax check
shellcheck script.sh  # Lint
```

### Docker Build
```bash
make build  # Full build
make dev-build && make dev-run  # Local testing
```

## Key Files

- `Dockerfile`: Main container image
- `fly.toml`: Fly.io deployment config
- `config/entrypoint.sh`: Container startup script
- `webhook/main.go`: HTTP server for phone replies
- `scripts/cc-*`: Agent lifecycle commands

## Security Notes

- SSH key auth only (no passwords)
- Tailscale-only network access (no public ports)
- Webhook auth token optional but recommended
- Secrets via Fly.io secrets, not env files
