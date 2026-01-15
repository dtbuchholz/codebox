#!/bin/bash
# Deploy script for Agent Box
set -e

echo "=== Agent Box Deployment ==="
echo ""

# Check prerequisites
if ! command -v fly &> /dev/null; then
    echo "Error: flyctl not installed. Install from https://fly.io/docs/hands-on/install-flyctl/"
    exit 1
fi

# Check if logged in
if ! fly auth whoami &> /dev/null; then
    echo "Please log in to Fly.io first:"
    fly auth login
fi

APP_NAME="${FLY_APP_NAME:-agent-box}"
REGION="${FLY_REGION:-sjc}"

echo "App name: $APP_NAME"
echo "Region: $REGION"
echo ""

# Create app if it doesn't exist
if ! fly apps list | grep -q "$APP_NAME"; then
    echo "Creating Fly app: $APP_NAME"
    fly apps create "$APP_NAME"
fi

# Create volume if it doesn't exist
if ! fly volumes list -a "$APP_NAME" 2>/dev/null | grep -q "agent_data"; then
    echo "Creating 10GB volume in $REGION..."
    fly volumes create agent_data --size 10 --region "$REGION" -a "$APP_NAME"
fi

# Check for required secrets
echo ""
echo "Checking secrets..."

MISSING_SECRETS=""

if ! fly secrets list -a "$APP_NAME" 2>/dev/null | grep -q "TAILSCALE_AUTHKEY"; then
    MISSING_SECRETS="$MISSING_SECRETS TAILSCALE_AUTHKEY"
fi

if ! fly secrets list -a "$APP_NAME" 2>/dev/null | grep -q "AUTHORIZED_KEYS"; then
    MISSING_SECRETS="$MISSING_SECRETS AUTHORIZED_KEYS"
fi

if [ -n "$MISSING_SECRETS" ]; then
    echo ""
    echo "Missing required secrets:$MISSING_SECRETS"
    echo ""
    echo "Set them with:"
    echo "  fly secrets set TAILSCALE_AUTHKEY='tskey-auth-xxx' -a $APP_NAME"
    echo "  fly secrets set AUTHORIZED_KEYS='ssh-ed25519 AAAA...' -a $APP_NAME"
    echo ""
    echo "Optional secrets:"
    echo "  fly secrets set NTFY_TOPIC='your-unique-topic' -a $APP_NAME"
    echo "  fly secrets set WEBHOOK_AUTH_TOKEN='your-secret' -a $APP_NAME"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Deploy
echo ""
echo "Deploying..."
fly deploy -a "$APP_NAME"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "1. Wait for the machine to start: fly status -a $APP_NAME"
echo "2. Check logs: fly logs -a $APP_NAME"
echo "3. Get Tailscale IP: fly ssh console -a $APP_NAME -C 'tailscale ip -4'"
echo "4. Connect: ssh -p 2222 agent@<tailscale-ip>"
