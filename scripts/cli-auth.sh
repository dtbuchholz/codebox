#!/bin/bash
# cli-auth.sh - Set up CLI OAuth auth on Agent Box VM
#
# Opens an SSH session on the Fly VM where you can run:
#   - claude setup-token   (Claude Code OAuth)
#   - codex login --device-auth  (Codex OAuth)
#
# Usage: ./scripts/cli-auth.sh [app-name]

set -e

# Resolve app name: argument > fly.toml > default
APP_NAME="${1:-}"
if [ -z "$APP_NAME" ] && [ -f fly.toml ]; then
    APP_NAME=$(grep '^app\s*=' fly.toml | sed 's/^app[[:space:]]*=[[:space:]]*//; s/^"//; s/"$//')
fi
APP_NAME="${APP_NAME:-agent-box}"

echo "=== Agent Box CLI Auth Setup ==="
echo ""
echo "App: $APP_NAME"
echo ""
echo "This will open an SSH session on the VM."
echo "Once connected, run these commands:"
echo ""
echo "  1. Claude Code OAuth:"
echo "     claude setup-token"
echo "     (Follow the URL, copy the token)"
echo ""
echo "  2. Codex OAuth:"
echo "     /usr/bin/codex login --device-auth"
echo "     (Follow the device code flow in your browser)"
echo ""
echo "After setup, set the Claude token as a Fly secret (from your local machine):"
echo "  fly secrets set CLAUDE_CODE_OAUTH_TOKEN=\"sk-ant-oat-...\" -a $APP_NAME"
echo ""
echo "Codex credentials are saved to /data/.codex/auth.json (persisted on volume)."
echo ""
echo "Press Enter to connect..."
read -r

fly ssh console -a "$APP_NAME" -u agent
