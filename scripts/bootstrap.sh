#!/bin/bash
# bootstrap.sh - Set up development environment on a fresh machine
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/you/codebox/main/scripts/bootstrap.sh | bash
#   # or
#   ./scripts/bootstrap.sh
#
# This script:
#   1. Detects the OS (macOS or Linux)
#   2. Installs required tools (Go, shellcheck, hadolint, golangci-lint, pre-commit)
#   3. Sets up git hooks
#   4. Verifies the installation

set -e

echo "=== Agent Box Development Environment Setup ==="
echo ""

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
fi

echo "Detected OS: $OS"
echo ""

# Check if we're in the codebox directory
if [[ ! -f "Makefile" ]] || [[ ! -f "fly.toml" ]]; then
    echo "Error: Please run this script from the codebox project root"
    echo "  cd /path/to/codebox && ./scripts/bootstrap.sh"
    exit 1
fi

# =============================================================================
# Tool Installation
# =============================================================================

install_brew() {
    if ! command -v brew &> /dev/null; then
        echo "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

        # Add to PATH for this session
        if [[ "$OS" == "macos" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)"
        else
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
        fi
    fi
}

install_go() {
    if command -v go &> /dev/null; then
        echo "Go already installed: $(go version)"
        return 0
    fi

    echo "Installing Go..."
    if [[ "$OS" == "macos" ]]; then
        brew install go
    else
        # Linux: use official installer
        GO_VERSION="1.22.0"
        curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | sudo tar -C /usr/local -xzf -
        export PATH="$PATH:/usr/local/go/bin"
        # shellcheck disable=SC2016
        echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    fi
}

install_shellcheck() {
    if command -v shellcheck &> /dev/null; then
        echo "shellcheck already installed: $(shellcheck --version | head -2 | tail -1)"
        return 0
    fi

    echo "Installing shellcheck..."
    if [[ "$OS" == "macos" ]]; then
        brew install shellcheck
    else
        sudo apt-get update && sudo apt-get install -y shellcheck
    fi
}

install_hadolint() {
    if command -v hadolint &> /dev/null; then
        echo "hadolint already installed: $(hadolint --version)"
        return 0
    fi

    echo "Installing hadolint..."
    if [[ "$OS" == "macos" ]]; then
        brew install hadolint
    else
        HADOLINT_VERSION="v2.12.0"
        sudo curl -fsSL "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64" -o /usr/local/bin/hadolint
        sudo chmod +x /usr/local/bin/hadolint
    fi
}

install_golangci_lint() {
    if command -v golangci-lint &> /dev/null; then
        echo "golangci-lint already installed: $(golangci-lint --version | head -1)"
        return 0
    fi

    echo "Installing golangci-lint..."
    if [[ "$OS" == "macos" ]]; then
        brew install golangci-lint
    else
        curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin" v1.55.2
        GOPATH_BIN="$(go env GOPATH)/bin"
        export PATH="$PATH:$GOPATH_BIN"
    fi
}

install_pre_commit() {
    if command -v pre-commit &> /dev/null; then
        echo "pre-commit already installed: $(pre-commit --version)"
        return 0
    fi

    echo "Installing pre-commit..."
    if command -v pip3 &> /dev/null; then
        pip3 install --user pre-commit
    elif command -v pip &> /dev/null; then
        pip install --user pre-commit
    elif [[ "$OS" == "macos" ]]; then
        brew install pre-commit
    else
        sudo apt-get update && sudo apt-get install -y python3-pip
        pip3 install --user pre-commit
    fi

    # Add to PATH if installed via pip
    export PATH=$PATH:~/.local/bin
}

install_node() {
    if command -v node &> /dev/null; then
        echo "Node.js already installed: $(node --version)"
        return 0
    fi

    echo "Installing Node.js..."
    if [[ "$OS" == "macos" ]]; then
        brew install node
    else
        # Linux: use NodeSource
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi
}

install_pnpm() {
    if command -v pnpm &> /dev/null; then
        echo "pnpm already installed: $(pnpm --version)"
        return 0
    fi

    echo "Installing pnpm..."
    if command -v npm &> /dev/null; then
        npm install -g pnpm
    else
        # Install via corepack (comes with Node.js 16.10+)
        corepack enable 2>/dev/null || true
        corepack prepare pnpm@latest --activate 2>/dev/null || npm install -g pnpm
    fi
}

install_flyctl() {
    if command -v fly &> /dev/null; then
        echo "flyctl already installed: $(fly version)"
        return 0
    fi

    echo "Installing flyctl..."
    curl -L https://fly.io/install.sh | sh
    export FLYCTL_INSTALL="${HOME}/.fly"
    export PATH="$FLYCTL_INSTALL/bin:$PATH"
}

install_docker() {
    if command -v docker &> /dev/null; then
        echo "Docker already installed: $(docker --version)"
        return 0
    fi

    echo "Installing Docker..."
    if [[ "$OS" == "macos" ]]; then
        echo "Please install Docker Desktop from https://docker.com/products/docker-desktop"
        echo "Then re-run this script."
        return 1
    else
        curl -fsSL https://get.docker.com | sh
        sudo usermod -aG docker "$USER"
        echo "NOTE: You may need to log out and back in for Docker permissions to take effect"
    fi
}

# =============================================================================
# Main Installation
# =============================================================================

echo "Installing required tools..."
echo ""

# On macOS, use Homebrew for most things
if [[ "$OS" == "macos" ]]; then
    install_brew
fi

# Core tools
install_go
install_shellcheck
install_hadolint
install_golangci_lint
install_pre_commit
install_node
install_pnpm
install_flyctl
install_docker || true  # Don't fail if Docker install needs manual step

# Install Node dependencies (for Prettier)
echo ""
echo "Installing Node dependencies..."
if command -v pnpm &> /dev/null; then
    pnpm install
elif command -v npm &> /dev/null; then
    npm install
fi

echo ""
echo "=== Setting up git hooks ==="
echo ""

# Initialize git repo if needed
if [[ ! -d ".git" ]]; then
    echo "Initializing git repository..."
    git init
fi

# Install pre-commit hooks
if command -v pre-commit &> /dev/null; then
    echo "Installing pre-commit hooks..."
    pre-commit install
    pre-commit install --hook-type pre-push
else
    echo "Warning: pre-commit not found in PATH. Add ~/.local/bin to your PATH and re-run."
fi

echo ""
echo "=== Verifying installation ==="
echo ""

# Verify all tools
MISSING=""
command -v go &> /dev/null || MISSING="$MISSING go"
command -v shellcheck &> /dev/null || MISSING="$MISSING shellcheck"
command -v hadolint &> /dev/null || MISSING="$MISSING hadolint"
command -v golangci-lint &> /dev/null || MISSING="$MISSING golangci-lint"
command -v pre-commit &> /dev/null || MISSING="$MISSING pre-commit"
command -v node &> /dev/null || MISSING="$MISSING node"
command -v pnpm &> /dev/null || MISSING="$MISSING pnpm"
command -v fly &> /dev/null || MISSING="$MISSING flyctl"
command -v docker &> /dev/null || MISSING="$MISSING docker"

if [[ -n "$MISSING" ]]; then
    echo "Warning: The following tools are not in PATH:$MISSING"
    echo ""
    echo "You may need to:"
    echo "  - Add ~/.local/bin to your PATH (for pre-commit)"
    echo "  - Add \$(go env GOPATH)/bin to your PATH (for golangci-lint)"
    echo "  - Add ~/.fly/bin to your PATH (for flyctl)"
    echo "  - Restart your shell"
    echo ""
else
    echo "All tools installed successfully!"
fi

echo ""
echo "=== Running initial lint check ==="
echo ""

# Try running lint to verify setup
if make lint 2>/dev/null; then
    echo ""
    echo "Lint check passed!"
else
    echo ""
    echo "Lint check had issues (this is expected on first run if Go modules aren't downloaded)"
    echo "Run 'cd webhook && go mod download' then 'make lint' again"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Run 'make lint' to verify everything works"
echo "  2. Run 'make build' to build the Docker image"
echo "  3. Run 'make deploy' to deploy to Fly.io (requires secrets)"
echo ""
echo "See AGENTS.md for full documentation."
