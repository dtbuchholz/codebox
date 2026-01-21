#!/bin/bash
# Initialize Fly.io configuration for Agent Box
#
# Usage:
#   ./scripts/fly-init.sh <app-name> [region]
#
# Examples:
#   ./scripts/fly-init.sh agent-box-dtb
#   ./scripts/fly-init.sh agent-box-dtb sjc
#
# This script will:
#   1. Generate fly.toml from fly.toml.example
#   2. Optionally create the Fly app and volume

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${1:-}"
REGION="${2:-sjc}"

if [ -z "$APP_NAME" ]; then
    echo "Usage: $0 <app-name> [region]"
    echo ""
    echo "Examples:"
    echo "  $0 agent-box-dtb          # Uses default region (sjc)"
    echo "  $0 agent-box-dtb iad      # Uses IAD region"
    echo ""
    echo "App name must be globally unique on Fly.io."
    echo "Suggestion: agent-box-<your-username>"
    exit 1
fi

# Check if fly.toml already exists
if [ -f "$REPO_ROOT/fly.toml" ]; then
    echo "fly.toml already exists."
    read -p "Overwrite? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Generate fly.toml from template
echo "Generating fly.toml..."
sed -e "s/{{APP_NAME}}/$APP_NAME/g" \
    -e "s/{{REGION}}/$REGION/g" \
    "$REPO_ROOT/fly.toml.example" > "$REPO_ROOT/fly.toml"

echo "Created fly.toml:"
echo "  app: $APP_NAME"
echo "  region: $REGION"
echo ""

# Check if flyctl is available
if ! command -v fly &> /dev/null && ! command -v flyctl &> /dev/null; then
    echo "flyctl not found. Install from: https://fly.io/docs/hands-on/install-flyctl/"
    echo ""
    echo "After installing, run:"
    echo "  fly apps create $APP_NAME"
    echo "  fly volumes create agent_data --size 10 --region $REGION"
    echo "  fly secrets set TAILSCALE_AUTHKEY='tskey-auth-xxx'"
    echo "  fly secrets set AUTHORIZED_KEYS='ssh-ed25519 AAAA...'"
    echo "  fly deploy"
    exit 0
fi

FLY_CMD="fly"
command -v fly &> /dev/null || FLY_CMD="flyctl"

# Ask to create app and volume
echo "Would you like to create the Fly app and volume now?"
read -p "Create app '$APP_NAME'? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo "Next steps:"
    echo "  fly apps create $APP_NAME"
    echo "  fly volumes create agent_data --size 10 --region $REGION"
    echo "  fly secrets set TAILSCALE_AUTHKEY='tskey-auth-xxx'"
    echo "  fly secrets set AUTHORIZED_KEYS='ssh-ed25519 AAAA...'"
    echo "  fly deploy"
    exit 0
fi

# Create app
echo "Creating Fly app..."
$FLY_CMD apps create "$APP_NAME" || {
    echo "App creation failed. It may already exist or the name is taken."
    echo "Try a different name or check: fly apps list"
}

# Create volume
echo ""
read -p "Create volume 'agent_data' (10GB) in $REGION? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Creating volume..."
    $FLY_CMD volumes create agent_data --size 10 --region "$REGION" -a "$APP_NAME" || {
        echo "Volume creation failed. It may already exist."
    }
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo ""
echo "1. Set required secrets:"
echo "   fly secrets set TAILSCALE_AUTHKEY='tskey-auth-xxx' -a $APP_NAME"
echo "   fly secrets set AUTHORIZED_KEYS=\"\$(cat ~/.ssh/id_ed25519.pub)\" -a $APP_NAME"
echo ""
echo "2. Deploy:"
echo "   fly deploy"
echo ""
echo "3. Connect:"
echo "   ssh agent@$APP_NAME"
