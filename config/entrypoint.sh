#!/bin/bash
set -e

echo "=== Agent Box Starting ==="

# Ensure /data directories exist with correct ownership
mkdir -p /data/repos /data/worktrees /data/logs /data/home/agent /data/inbox /data/config
chown agent:agent /data/repos /data/worktrees /data/logs /data/inbox

# Set up agent home directory on persistent volume
AGENT_HOME="/data/home/agent"
if [ ! -f "$AGENT_HOME/.bashrc" ]; then
    cp /etc/skel/.bashrc "$AGENT_HOME/" 2>/dev/null || true
    cp /etc/skel/.profile "$AGENT_HOME/" 2>/dev/null || true
fi

# Link agent's home to persistent storage
usermod -d "$AGENT_HOME" agent 2>/dev/null || true

# Set up SSH authorized_keys from environment or mounted file
SSH_DIR="$AGENT_HOME/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ -n "$AUTHORIZED_KEYS" ]; then
    echo "$AUTHORIZED_KEYS" > "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
elif [ -f "/data/config/authorized_keys" ]; then
    cp /data/config/authorized_keys "$SSH_DIR/authorized_keys"
    chmod 600 "$SSH_DIR/authorized_keys"
fi

chown -R agent:agent "$AGENT_HOME"

# Add MOTD with agent status
cat > /etc/motd << 'EOF'

  ___                    _     ___
 / _ \  __ _  ___  _ __ | |_  | _ ) ___ __ __
| (_) |/ _` |/ -_)| '  \|  _| | _ \/ _ \\ \ /
 \__,_|\__, |\___||_||_| \__| |___/\___//_\_\
       |___/

Commands:
  cc-ls              - List running agents
  cc-new <name> <dir> - Start new agent
  cc-attach <name>   - Attach to agent
  cc-stop <name>     - Stop agent

EOF

# Append current agent status to MOTD
{
    echo "Current agents:"
    su - agent -c "tmux ls 2>/dev/null || echo '  (none running)'"
    echo ""
} >> /etc/motd

# Start Tailscale daemon
echo "Starting Tailscale..."
tailscaled --state=/data/config/tailscale.state --socket=/var/run/tailscale/tailscaled.sock &

# Wait for tailscaled to be ready
sleep 2

# Authenticate Tailscale if auth key is provided
if [ -n "$TAILSCALE_AUTHKEY" ]; then
    echo "Authenticating with Tailscale..."
    tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="${FLY_APP_NAME:-agent-box}" --ssh || true
else
    echo "No TAILSCALE_AUTHKEY provided. Run 'tailscale up' manually to authenticate."
    tailscale up --hostname="${FLY_APP_NAME:-agent-box}" --ssh || true
fi

# Generate SSH host keys if they don't exist (persist them)
if [ ! -f "/data/config/ssh_host_rsa_key" ]; then
    echo "Generating SSH host keys..."
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* /data/config/ 2>/dev/null || true
else
    echo "Restoring SSH host keys..."
    cp /data/config/ssh_host_* /etc/ssh/ 2>/dev/null || true
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub
fi

# Start SSH daemon
echo "Starting SSH daemon on port 2222..."
/usr/sbin/sshd -D -e &
SSHD_PID=$!

# Start webhook receiver if enabled
if [ "${ENABLE_WEBHOOK:-1}" = "1" ]; then
    echo "Starting webhook receiver on port 8080..."
    /usr/local/bin/webhook-receiver &
    WEBHOOK_PID=$!
fi

# Install Claude Code if not already installed
if ! command -v claude &> /dev/null; then
    echo "Installing Claude Code..."
    npm install -g @anthropic-ai/claude-code || echo "Claude Code install will complete on first run"
fi

# Set up Claude Code hooks directory
CLAUDE_HOOKS_DIR="$AGENT_HOME/.claude/hooks"
mkdir -p "$CLAUDE_HOOKS_DIR"
if [ -d "/opt/hooks" ]; then
    cp /opt/hooks/* "$CLAUDE_HOOKS_DIR/" 2>/dev/null || true
fi
chown -R agent:agent "$AGENT_HOME/.claude" 2>/dev/null || true

echo "=== Agent Box Ready ==="
echo "SSH: port 2222"
echo "Webhook: port 8080"
echo "Tailscale: $(tailscale ip -4 2>/dev/null || echo 'pending auth')"

# Keep container running (wait for any child process)
# shellcheck disable=SC2086
wait -n $SSHD_PID ${WEBHOOK_PID:-}
