.PHONY: build deploy logs ssh status clean help setup bootstrap lint format test qa

APP_NAME ?= agent-box
REGION ?= sjc

# Detect if we're in CI (non-interactive)
CI ?= false

# =============================================================================
# Help
# =============================================================================
help:
	@echo "Agent Box - Makefile targets"
	@echo ""
	@echo "Setup:"
	@echo "  make bootstrap  Full setup (install tools + hooks) - for fresh machines"
	@echo "  make setup      Install git hooks (assumes tools exist)"
	@echo "  make check-tools Check if required tools are installed"
	@echo ""
	@echo "Quality:"
	@echo "  make lint       Run all linters"
	@echo "  make format     Auto-format code"
	@echo "  make test       Run tests"
	@echo "  make qa         Run full QA suite (lint + test + build)"
	@echo ""
	@echo "Build:"
	@echo "  make build      Build Docker image locally"
	@echo "  make deploy     Deploy to Fly.io"
	@echo ""
	@echo "Operations:"
	@echo "  make logs       View Fly.io logs"
	@echo "  make ssh        SSH into the machine"
	@echo "  make status     Check machine status"
	@echo "  make console    Open Fly console"
	@echo "  make clean      Remove local build artifacts"
	@echo ""
	@echo "Variables:"
	@echo "  APP_NAME=$(APP_NAME)"
	@echo "  REGION=$(REGION)"
	@echo "  CI=$(CI)"

# =============================================================================
# Setup
# =============================================================================

# Full bootstrap - use this on fresh machines
bootstrap:
	@./scripts/bootstrap.sh

# Quick setup - just install hooks (assumes tools exist)
setup: check-tools setup-hooks
	@echo ""
	@echo "Setup complete! Run 'make lint' to verify."

setup-hooks:
	@echo "Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type pre-push

# Check if required tools are installed (non-interactive)
check-tools:
	@echo "Checking required tools..."
	@MISSING=""; \
	command -v go >/dev/null 2>&1 || MISSING="$$MISSING go"; \
	command -v shellcheck >/dev/null 2>&1 || MISSING="$$MISSING shellcheck"; \
	command -v hadolint >/dev/null 2>&1 || MISSING="$$MISSING hadolint"; \
	command -v golangci-lint >/dev/null 2>&1 || MISSING="$$MISSING golangci-lint"; \
	command -v pre-commit >/dev/null 2>&1 || MISSING="$$MISSING pre-commit"; \
	(command -v pnpm >/dev/null 2>&1 || command -v npm >/dev/null 2>&1 || command -v npx >/dev/null 2>&1) || MISSING="$$MISSING node/pnpm"; \
	if [ -n "$$MISSING" ]; then \
		echo "Missing tools:$$MISSING"; \
		echo "Run 'make bootstrap' to install them, or install manually:"; \
		echo "  brew install go shellcheck hadolint golangci-lint node"; \
		echo "  pip install pre-commit"; \
		echo "  npm install -g pnpm"; \
		exit 1; \
	fi; \
	echo "All required tools are installed."

# Install tools via Homebrew (macOS/Linux with linuxbrew)
install-tools-brew:
	brew install go shellcheck hadolint golangci-lint node
	npm install -g pnpm
	pip3 install --user pre-commit || pip install --user pre-commit

# Install Node dependencies (for Prettier)
install-deps:
	@if command -v pnpm >/dev/null 2>&1; then \
		pnpm install; \
	elif command -v npm >/dev/null 2>&1; then \
		npm install; \
	else \
		echo "Neither pnpm nor npm found. Install Node.js first."; \
		exit 1; \
	fi

# =============================================================================
# Quality Assurance
# =============================================================================
lint: lint-go lint-shell lint-docker lint-format
	@echo ""
	@echo "All linters passed!"

lint-go:
	@echo "Linting Go code..."
	@cd webhook && golangci-lint run

lint-shell:
	@echo "Linting shell scripts..."
	@shellcheck -e SC1091 scripts/* hooks/*.sh config/*.sh

lint-docker:
	@echo "Linting Dockerfile..."
	@hadolint --ignore DL3008 --ignore DL3013 Dockerfile

lint-format:
	@echo "Checking formatting (Prettier)..."
	@if command -v pnpm >/dev/null 2>&1; then \
		pnpm format:check; \
	elif command -v npx >/dev/null 2>&1; then \
		npx prettier --check .; \
	else \
		echo "Warning: pnpm/npx not found, skipping format check"; \
	fi

format: format-prettier format-go
	@echo ""
	@echo "Formatting complete!"

format-prettier:
	@echo "Formatting with Prettier (MD, JSON, YAML)..."
	@if command -v pnpm >/dev/null 2>&1; then \
		pnpm format; \
	elif command -v npx >/dev/null 2>&1; then \
		npx prettier --write .; \
	else \
		echo "Warning: pnpm/npx not found, skipping Prettier"; \
	fi

format-go:
	@echo "Formatting Go code..."
	@cd webhook && go fmt ./...
	@cd webhook && goimports -w . 2>/dev/null || true

test: test-go
	@echo ""
	@echo "All tests passed!"

test-go:
	@echo "Running Go tests..."
	@cd webhook && go test -v ./...

# Full QA - run before commits/pushes
qa: lint test build
	@echo ""
	@echo "QA passed!"

# CI mode - non-interactive, fails fast
ci: check-tools
	@echo "Running CI checks..."
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) build
	@echo ""
	@echo "CI passed!"

# =============================================================================
# Build & Deploy
# =============================================================================
build:
	@echo "Building Docker image..."
	docker build -t $(APP_NAME):local .

# Deploy with all checks
deploy: qa
	./deploy.sh

# Deploy without checks (use with caution)
deploy-force:
	./deploy.sh

logs:
	fly logs -a $(APP_NAME)

ssh:
	@echo "Getting Tailscale IP..."
	@IP=$$(fly ssh console -a $(APP_NAME) -C 'tailscale ip -4' 2>/dev/null | tr -d '\r\n'); \
	if [ -n "$$IP" ]; then \
		echo "Connecting to $$IP:2222..."; \
		ssh -p 2222 agent@$$IP; \
	else \
		echo "Could not get Tailscale IP. Try: fly ssh console -a $(APP_NAME)"; \
	fi

status:
	fly status -a $(APP_NAME)

console:
	fly ssh console -a $(APP_NAME)

# =============================================================================
# Local Development
# =============================================================================
dev-build:
	docker build -t $(APP_NAME):dev .

dev-run:
	docker run -it --rm \
		-p 2222:2222 \
		-p 8080:8080 \
		-v $$(pwd)/data:/data \
		-e AUTHORIZED_KEYS="$$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_rsa.pub)" \
		$(APP_NAME):dev

# =============================================================================
# Cleanup
# =============================================================================
clean:
	rm -f webhook/webhook-receiver
	docker rmi $(APP_NAME):local $(APP_NAME):dev 2>/dev/null || true
	rm -rf webhook/.golangci-lint-cache

# Deep clean - removes all generated files
clean-all: clean
	rm -rf .pre-commit-cache
	cd webhook && go clean -cache -modcache
