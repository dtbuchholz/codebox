#!/bin/bash
# vm-setup.sh - Interactive setup wizard for Agent Box VM
#
# Run this after first SSH into the VM to configure essentials.
# Usage: vm-setup

set -e

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BOLD}=== $1 ===${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-y}"
    local response

    if [ "$default" = "y" ]; then
        read -p "$prompt [Y/n]: " response
        response="${response:-y}"
    else
        read -p "$prompt [y/N]: " response
        response="${response:-n}"
    fi

    [[ "$response" =~ ^[Yy] ]]
}

# ============================================================================
# Welcome
# ============================================================================
clear
echo -e "${BOLD}"
cat << 'EOF'
     _                    _     ____
    / \   __ _  ___ _ __ | |_  | __ )  _____  __
   / _ \ / _` |/ _ \ '_ \| __| |  _ \ / _ \ \/ /
  / ___ \ (_| |  __/ | | | |_  | |_) | (_) >  <
 /_/   \_\__, |\___|_| |_|\__| |____/ \___/_/\_\
         |___/
EOF
echo -e "${NC}"
echo "Welcome to Agent Box setup!"
echo "This wizard will help you configure the essentials."
echo ""
echo "Press Enter to continue..."
read -r

# ============================================================================
# Check what's already configured
# ============================================================================
print_header "Checking current configuration"

# Git config
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
GIT_NAME=$(git config --global user.name 2>/dev/null || echo "")

if [ -n "$GIT_EMAIL" ] && [ -n "$GIT_NAME" ]; then
    print_success "Git identity: $GIT_NAME <$GIT_EMAIL>"
    NEED_GIT=false
else
    print_warning "Git identity not configured"
    NEED_GIT=true
fi

# GitHub CLI
if gh auth status &>/dev/null; then
    GH_USER=$(gh api user --jq .login 2>/dev/null || echo "authenticated")
    print_success "GitHub CLI: logged in as $GH_USER"
    NEED_GH=false
else
    print_warning "GitHub CLI not authenticated"
    NEED_GH=true
fi

# SSH key
if [ -f ~/.ssh/id_ed25519.pub ]; then
    print_success "SSH key exists: ~/.ssh/id_ed25519.pub"
    NEED_SSH=false
else
    print_warning "No SSH key found"
    NEED_SSH=true
fi

# SSH commit signing
GIT_SIGNING=$(git config --global gpg.format 2>/dev/null || echo "")
if [ "$GIT_SIGNING" = "ssh" ] && [ -f ~/.ssh/allowed_signers ]; then
    print_success "SSH commit signing configured"
    NEED_SIGNING=false
else
    print_warning "SSH commit signing not configured"
    NEED_SIGNING=true
fi

# Takopi
if [ -f ~/.takopi/takopi.toml ]; then
    print_success "Takopi config exists"
    NEED_TAKOPI=false
else
    print_warning "Takopi not configured"
    NEED_TAKOPI=true
fi

# Claude Code
if [ -n "$ANTHROPIC_API_KEY" ] || [ -f ~/.env.secrets ]; then
    print_success "Claude API key configured"
    NEED_CLAUDE=false
else
    print_warning "Claude API key not set"
    NEED_CLAUDE=true
fi

echo ""

# ============================================================================
# Git Identity
# ============================================================================
if [ "$NEED_GIT" = true ]; then
    print_header "Git Identity"
    echo "Git needs your name and email for commits."
    echo ""

    read -p "Your name: " git_name
    read -p "Your email: " git_email

    if [ -n "$git_name" ] && [ -n "$git_email" ]; then
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        print_success "Git identity configured"
    else
        print_warning "Skipped - you'll need to configure this manually"
    fi
fi

# ============================================================================
# SSH Key
# ============================================================================
if [ "$NEED_SSH" = true ]; then
    print_header "SSH Key"
    echo "An SSH key is needed for cloning private repos."
    echo ""

    if ask_yes_no "Generate a new SSH key?"; then
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -q
        print_success "SSH key generated"
        echo ""
        echo "Add this public key to GitHub (https://github.com/settings/keys):"
        echo ""
        cat ~/.ssh/id_ed25519.pub
        echo ""
        echo "Press Enter after adding the key to GitHub..."
        read -r
    else
        print_warning "Skipped - add your own key to ~/.ssh/"
    fi
fi

# ============================================================================
# SSH Commit Signing
# ============================================================================
if [ "$NEED_SIGNING" = true ] && [ -f ~/.ssh/id_ed25519.pub ]; then
    print_header "SSH Commit Signing"
    echo "SSH signing creates verified commits on GitHub without GPG complexity."
    echo ""

    if ask_yes_no "Enable SSH commit signing?"; then
        # Get email for allowed_signers
        signing_email=$(git config --global user.email 2>/dev/null || echo "")
        if [ -z "$signing_email" ]; then
            read -r -p "Email for signing (same as git email): " signing_email
        fi

        if [ -n "$signing_email" ]; then
            # Configure git for SSH signing
            git config --global gpg.format ssh
            git config --global user.signingkey ~/.ssh/id_ed25519.pub
            git config --global commit.gpgsign true
            git config --global tag.gpgsign true

            # Create allowed_signers file for verification
            mkdir -p ~/.ssh
            echo "$signing_email $(cat ~/.ssh/id_ed25519.pub)" > ~/.ssh/allowed_signers
            git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers

            print_success "SSH signing configured"

            # Set GIT_AUTHOR/COMMITTER env vars for Claude Code (API key auth)
            # Without these, Claude Code defaults to claude@anthropic.com as author
            if ! grep -q "GIT_AUTHOR_NAME" ~/.bashrc 2>/dev/null; then
                git_name=$(git config --global user.name)
                cat >> ~/.bashrc << EOF

# Git author/committer for Claude Code (required for verified commits with API key auth)
export GIT_AUTHOR_NAME="$git_name"
export GIT_AUTHOR_EMAIL="$signing_email"
export GIT_COMMITTER_NAME="$git_name"
export GIT_COMMITTER_EMAIL="$signing_email"
EOF
                print_success "Git author env vars added to ~/.bashrc"
            fi

            echo ""
            echo -e "${YELLOW}IMPORTANT:${NC} Add this key to GitHub as a ${BOLD}Signing Key${NC}:"
            echo "  https://github.com/settings/ssh/new"
            echo "  Key type: ${BOLD}Signing Key${NC} (not Authentication Key)"
            echo ""
            cat ~/.ssh/id_ed25519.pub
            echo ""
            echo "Press Enter after adding the signing key to GitHub..."
            read -r
        else
            print_warning "Skipped - no email provided"
        fi
    else
        print_warning "Skipped - commits will not be signed"
    fi
fi

# ============================================================================
# GitHub CLI
# ============================================================================
if [ "$NEED_GH" = true ]; then
    print_header "GitHub CLI"
    echo "The GitHub CLI (gh) lets Claude create issues, PRs, etc."
    echo ""

    if ask_yes_no "Authenticate with GitHub now?"; then
        echo ""
        echo "Choose 'GitHub.com', 'HTTPS', and 'Login with a web browser' or 'Paste token'"
        echo ""
        gh auth login
        # Configure git to use gh for HTTPS authentication
        gh auth setup-git
        print_success "GitHub CLI authenticated + git credential helper configured"
    else
        print_warning "Skipped - run 'gh auth login' later"
    fi
else
    # Even if already authenticated, ensure git credential helper is configured
    if ! git config --global credential.helper 2>/dev/null | grep -q "gh"; then
        gh auth setup-git 2>/dev/null && print_success "Git credential helper configured for gh"
    fi
fi

# ============================================================================
# Takopi (Telegram)
# ============================================================================
if [ "$NEED_TAKOPI" = true ]; then
    print_header "Takopi (Telegram Bot)"
    echo "Takopi lets you chat with Claude via Telegram."
    echo ""

    if ask_yes_no "Set up Telegram integration?" "n"; then
        echo ""
        echo "First, create a bot:"
        echo "  1. Message @BotFather on Telegram"
        echo "  2. Send /newbot and follow prompts"
        echo "  3. Copy the bot token"
        echo ""

        # Check if uv/takopi is installed
        if ! command -v takopi &>/dev/null; then
            if ask_yes_no "Takopi not installed. Install it now?"; then
                if ! command -v uv &>/dev/null; then
                    echo "Installing uv..."
                    curl -LsSf https://astral.sh/uv/install.sh | sh
                    source ~/.bashrc
                fi
                uv python install 3.13
                uv tool install -U takopi
                print_success "Takopi installed"
            fi
        fi

        if command -v takopi &>/dev/null; then
            echo ""
            echo "Running Takopi setup wizard..."
            takopi

            # Configure file uploads after wizard completes
            if [ -f ~/.takopi/takopi.toml ]; then
                echo ""
                echo "Configuring file uploads..."

                # Extract chat_id from config
                chat_id=$(grep -E "^chat_id\s*=" ~/.takopi/takopi.toml | head -1 | sed 's/.*=\s*//' | tr -d ' ')

                if [ -n "$chat_id" ] && [ "$chat_id" != "0" ]; then
                    takopi config set "transports.telegram.files.enabled" "true"
                    takopi config set "transports.telegram.files.auto_put" "true"
                    takopi config set "transports.telegram.files.uploads_dir" "incoming"
                    takopi config set "transports.telegram.files.allowed_user_ids" "[$chat_id]"
                    takopi config set "transports.telegram.files.deny_globs" '[".git/**", ".env", ".envrc", "**/*.pem", "**/.ssh/**", "**/secrets/**"]'
                    print_success "File uploads enabled for chat_id $chat_id"
                else
                    print_warning "Could not detect chat_id - file uploads may need manual config"
                fi
            fi
        else
            print_warning "Install takopi manually: uv tool install takopi"
        fi
    else
        print_warning "Skipped - run 'takopi' later to set up Telegram"
    fi
fi

# ============================================================================
# Summary
# ============================================================================
print_header "Setup Complete!"

echo "Current status:"
echo ""

# Re-check status
GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
if [ -n "$GIT_EMAIL" ]; then
    print_success "Git: $(git config --global user.name) <$GIT_EMAIL>"
else
    print_error "Git: not configured - run: git config --global user.email/name"
fi

if gh auth status &>/dev/null; then
    print_success "GitHub CLI: authenticated"
else
    print_error "GitHub CLI: not authenticated - run: gh auth login"
fi

if [ -f ~/.ssh/id_ed25519.pub ]; then
    print_success "SSH key: exists"
else
    print_error "SSH key: missing - run: ssh-keygen -t ed25519"
fi

GIT_SIGNING=$(git config --global gpg.format 2>/dev/null || echo "")
if [ "$GIT_SIGNING" = "ssh" ]; then
    print_success "Commit signing: SSH"
else
    print_warning "Commit signing: disabled - re-run vm-setup to enable"
fi

if [ -f ~/.takopi/takopi.toml ]; then
    print_success "Takopi: configured"
else
    print_warning "Takopi: not configured (optional) - run: takopi"
fi

if [ -n "$ANTHROPIC_API_KEY" ] || [ -f ~/.env.secrets ]; then
    print_success "Claude API: configured"
else
    print_warning "Claude API: set via 'fly secrets set ANTHROPIC_API_KEY=...' from local machine"
fi

echo ""
echo "Next steps:"
echo "  1. Clone repos: cd /data/repos && git clone <repo-url>"
echo "  2. Start an agent: cc-new myproject /data/repos/myproject"
echo "  3. Or use Telegram: /claude <your message>"
echo ""
