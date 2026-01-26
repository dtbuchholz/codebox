# AGENTS.md

Configuration for AI assistants working on this codebase.

## Project Overview

**Agent Box** - Remote Claude Code environment on Fly.io. See [README.md](./README.md) for full documentation, architecture, and setup instructions.

## Quick Commands

```bash
# Quality checks
make lint         # Run all linters
make test         # Run tests
make qa           # Full QA: lint + test + build

# Build & Deploy
make build        # Build Docker image
make deploy       # Deploy to Fly.io

# Or use just (alternative)
just check        # Same as make qa
```

## Repository Structure

```
codebox/
├── webhook/              # Go HTTP server for reply-from-phone
│   ├── main.go           # HTTP handlers: /inbox, /send, /agents
│   ├── go.mod
│   └── .golangci.yml     # Go linter config
├── scripts/              # Agent lifecycle CLI tools
│   ├── cc-new            # Create new agent
│   ├── cc-stop           # Stop agent
│   ├── cc-ls             # List running agents
│   ├── cc-attach         # Attach to agent session
│   ├── config.sh         # TOML config utilities
│   ├── healthcheck.sh    # Service monitoring
│   ├── vm-setup.sh       # Interactive VM setup wizard
│   └── bootstrap.sh      # Fresh VM setup script
├── config/               # Container configuration
│   ├── entrypoint.sh     # Container startup
│   ├── git-hooks/        # Git hooks (pre-push)
│   └── *.example         # Config templates
├── Makefile              # Build/deploy commands
├── justfile              # Alternative task runner
├── Dockerfile            # Multi-stage build
└── fly.toml.example      # Fly.io config template
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

### Dockerfile

- Multi-stage builds to minimize image size
- Pin base image versions
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

```bash
# Go tests
cd webhook && go test -v ./...

# Shell script syntax
bash -n script.sh
shellcheck script.sh

# Docker build
make build
```

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
