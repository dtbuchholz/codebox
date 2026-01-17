# justfile - Modern task runner for Agent Box
# Install: brew install just
# Usage: just <recipe>

# Default recipe - show help
default:
    @just --list

# =============================================================================
# Setup
# =============================================================================

# Full bootstrap for fresh machines
bootstrap:
    ./scripts/bootstrap.sh

# Quick setup (install hooks, check tools)
setup: check-tools
    pre-commit install
    pre-commit install --hook-type pre-push
    @echo "Setup complete! Run 'just lint' to verify."

# Check if required tools are installed
check-tools:
    #!/usr/bin/env bash
    set -e
    echo "Checking required tools..."
    MISSING=""
    command -v go >/dev/null 2>&1 || MISSING="$MISSING go"
    command -v shellcheck >/dev/null 2>&1 || MISSING="$MISSING shellcheck"
    command -v hadolint >/dev/null 2>&1 || MISSING="$MISSING hadolint"
    command -v golangci-lint >/dev/null 2>&1 || MISSING="$MISSING golangci-lint"
    command -v pre-commit >/dev/null 2>&1 || MISSING="$MISSING pre-commit"
    (command -v pnpm >/dev/null 2>&1 || command -v npx >/dev/null 2>&1) || MISSING="$MISSING node/pnpm"
    if [ -n "$MISSING" ]; then
        echo "Missing tools:$MISSING"
        echo "Run 'just bootstrap' to install them"
        exit 1
    fi
    echo "All tools installed."

# Install Node dependencies
deps:
    pnpm install

# =============================================================================
# Quality Assurance
# =============================================================================

# Run all checks (lint + test + build)
check: lint test build
    @echo ""
    @echo "All checks passed!"

# Alias for check
qa: check

# Run all linters
lint: lint-go lint-shell lint-docker lint-format
    @echo ""
    @echo "All linters passed!"

# Lint Go code
lint-go:
    @echo "Linting Go code..."
    cd webhook && golangci-lint run

# Lint shell scripts
lint-shell:
    @echo "Linting shell scripts..."
    shellcheck -e SC1091 scripts/* hooks/*.sh config/*.sh

# Lint Dockerfile
lint-docker:
    @echo "Linting Dockerfile..."
    hadolint --ignore DL3008 --ignore DL3013 Dockerfile

# Check formatting
lint-format:
    @echo "Checking formatting..."
    pnpm format:check

# Format all code
format: format-prettier format-go
    @echo ""
    @echo "Formatting complete!"

# Format with Prettier (MD, JSON, YAML)
format-prettier:
    @echo "Formatting with Prettier..."
    pnpm format

# Format Go code
format-go:
    @echo "Formatting Go code..."
    cd webhook && go fmt ./...
    cd webhook && goimports -w . 2>/dev/null || true

# Run tests
test:
    @echo "Running Go tests..."
    cd webhook && go test -v ./...

# =============================================================================
# Build & Deploy
# =============================================================================

# Build Docker image
build:
    @echo "Building Docker image..."
    docker build -t agent-box:local .

# Deploy to Fly.io (runs checks first)
deploy: check
    ./deploy.sh

# Deploy without checks (use with caution)
deploy-force:
    ./deploy.sh

# =============================================================================
# Operations
# =============================================================================

# View Fly.io logs
logs:
    fly logs -a agent-box

# Check machine status
status:
    fly status -a agent-box

# Open Fly console
console:
    fly ssh console -a agent-box

# SSH into the machine via Tailscale
ssh:
    #!/usr/bin/env bash
    echo "Getting Tailscale IP..."
    IP=$(fly ssh console -a agent-box -C 'tailscale ip -4' 2>/dev/null | tr -d '\r\n')
    if [ -n "$IP" ]; then
        echo "Connecting to $IP:2222..."
        ssh -p 2222 agent@$IP
    else
        echo "Could not get Tailscale IP. Try: fly ssh console -a agent-box"
    fi

# =============================================================================
# Local Development
# =============================================================================

# Build dev image
dev-build:
    docker build -t agent-box:dev .

# Run dev container
dev-run:
    #!/usr/bin/env bash
    docker run -it --rm \
        -p 2222:2222 \
        -p 8080:8080 \
        -v $(pwd)/data:/data \
        -e AUTHORIZED_KEYS="$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)" \
        agent-box:dev

# =============================================================================
# Cleanup
# =============================================================================

# Remove build artifacts
clean:
    rm -f webhook/webhook-receiver
    docker rmi agent-box:local agent-box:dev 2>/dev/null || true
    rm -rf webhook/.golangci-lint-cache

# Deep clean (includes caches)
clean-all: clean
    rm -rf node_modules .pre-commit-cache
    cd webhook && go clean -cache -modcache
