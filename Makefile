.PHONY: build deploy logs ssh status clean help setup lint format test qa

APP_NAME ?= agent-box
REGION ?= sjc

# =============================================================================
# Help
# =============================================================================
help:
	@echo "Agent Box - Makefile targets"
	@echo ""
	@echo "Setup:"
	@echo "  make setup      Install dev dependencies and git hooks"
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

# =============================================================================
# Setup
# =============================================================================
setup: setup-hooks setup-tools
	@echo "Setup complete!"

setup-hooks:
	@echo "Installing pre-commit hooks..."
	@if command -v pre-commit >/dev/null 2>&1; then \
		pre-commit install && pre-commit install --hook-type pre-push; \
	else \
		echo "pre-commit not found. Install with: pip install pre-commit"; \
		exit 1; \
	fi

setup-tools:
	@echo "Checking required tools..."
	@command -v go >/dev/null 2>&1 || { echo "go not found - install from https://go.dev"; exit 1; }
	@command -v shellcheck >/dev/null 2>&1 || echo "shellcheck not found - install with: brew install shellcheck"
	@command -v hadolint >/dev/null 2>&1 || echo "hadolint not found - install with: brew install hadolint"
	@command -v golangci-lint >/dev/null 2>&1 || echo "golangci-lint not found - install with: brew install golangci-lint"

# =============================================================================
# Quality Assurance
# =============================================================================
lint: lint-go lint-shell lint-docker
	@echo "All linters passed!"

lint-go:
	@echo "Linting Go code..."
	cd webhook && golangci-lint run

lint-shell:
	@echo "Linting shell scripts..."
	shellcheck -e SC1091 scripts/* hooks/*.sh config/*.sh 2>/dev/null || true

lint-docker:
	@echo "Linting Dockerfile..."
	hadolint --ignore DL3008 --ignore DL3013 Dockerfile

format: format-go format-shell
	@echo "Formatting complete!"

format-go:
	@echo "Formatting Go code..."
	cd webhook && go fmt ./...
	cd webhook && goimports -w .

format-shell:
	@echo "Shell scripts don't have auto-format (use shellcheck warnings)"

test: test-go
	@echo "All tests passed!"

test-go:
	@echo "Running Go tests..."
	cd webhook && go test -v ./...

qa: lint test build
	@echo ""
	@echo "QA passed!"

# Pre-commit hook (called by git)
pre-commit:
	pre-commit run --all-files

# Pre-push hook (called by git)
pre-push:
	pre-commit run --all-files --hook-stage pre-push
	$(MAKE) qa

# =============================================================================
# Build & Deploy
# =============================================================================
build:
	docker build -t $(APP_NAME):local .

deploy:
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
