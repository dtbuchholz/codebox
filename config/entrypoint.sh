#!/bin/bash
set -e

echo "=== Agent Box Starting ==="

# Set up swap space to handle memory spikes (Claude Code can be memory-hungry)
SWAP_FILE="/data/swapfile"
SWAP_SIZE="${SWAP_SIZE_MB:-2048}"  # 2GB swap by default
if [ ! -f "$SWAP_FILE" ]; then
    echo "Creating ${SWAP_SIZE}MB swap file..."
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE" 2>/dev/null
    chmod 600 "$SWAP_FILE"
    mkswap "$SWAP_FILE" >/dev/null
fi
if ! swapon -s | grep -q "$SWAP_FILE"; then
    swapon "$SWAP_FILE" 2>/dev/null || echo "Warning: Could not enable swap"
fi

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

# Start PostgreSQL if installed (wrapped to not fail entrypoint)
start_postgresql() {
    if ! command -v pg_ctlcluster &> /dev/null; then
        return 0
    fi

    echo "Starting PostgreSQL..."
    PG_VERSION=$(ls /etc/postgresql/ 2>/dev/null | head -1)
    if [ -z "$PG_VERSION" ]; then
        echo "Warning: PostgreSQL installed but no version found"
        return 0
    fi

    PG_DATA="/data/postgresql/$PG_VERSION"
    PG_CONF="/etc/postgresql/$PG_VERSION/main"

    if [ ! -d "$PG_DATA" ]; then
        echo "Initializing PostgreSQL data directory..."
        mkdir -p "$PG_DATA"
        chown postgres:postgres "$PG_DATA"
        chmod 700 "$PG_DATA"
        su - postgres -c "/usr/lib/postgresql/$PG_VERSION/bin/initdb -D $PG_DATA" || return 0
    fi

    # Configure to use persistent data and allow local trust auth
    if [ -d "$PG_DATA" ]; then
        # Update data_directory in postgresql.conf
        sed -i "s|^data_directory.*|data_directory = '$PG_DATA'|g" "$PG_CONF/postgresql.conf" 2>/dev/null || true

        # Allow trust auth for local connections (dev environment)
        if [ -f "$PG_CONF/pg_hba.conf" ]; then
            sed -i 's/peer$/trust/g' "$PG_CONF/pg_hba.conf" 2>/dev/null || true
            sed -i 's/scram-sha-256$/trust/g' "$PG_CONF/pg_hba.conf" 2>/dev/null || true
        fi

        pg_ctlcluster "$PG_VERSION" main start 2>/dev/null || echo "Warning: PostgreSQL failed to start"
    fi
}
start_postgresql || echo "PostgreSQL setup skipped"

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

# Export API keys to agent's environment (from Fly secrets)
AGENT_ENV_FILE="$AGENT_HOME/.env.secrets"
{
    [ -n "$ANTHROPIC_API_KEY" ] && echo "export ANTHROPIC_API_KEY=\"$ANTHROPIC_API_KEY\""
    [ -n "$ANTHROPIC_BASE_URL" ] && echo "export ANTHROPIC_BASE_URL=\"$ANTHROPIC_BASE_URL\""
    [ -n "$OPENAI_API_KEY" ] && echo "export OPENAI_API_KEY=\"$OPENAI_API_KEY\""
} > "$AGENT_ENV_FILE"
chown agent:agent "$AGENT_ENV_FILE"
chmod 600 "$AGENT_ENV_FILE"

# Add source to bashrc if not already there
if ! grep -q ".env.secrets" "$AGENT_HOME/.bashrc" 2>/dev/null; then
    echo '[ -f ~/.env.secrets ] && source ~/.env.secrets' >> "$AGENT_HOME/.bashrc"
fi

# Auto-start Takopi if configured
if [ -f "$AGENT_HOME/.takopi/takopi.toml" ]; then
    echo "Starting Takopi (Telegram bot)..."
    if command -v takopi &> /dev/null || [ -x "$AGENT_HOME/.local/bin/takopi" ]; then
        # Kill any existing tmux server to ensure fresh environment with new secrets
        su - agent -c "tmux kill-server 2>/dev/null || true"
        sleep 1
        # Explicitly source env.secrets to ensure API keys are available
        su - agent -c "tmux new-session -d -s takopi 'source ~/.env.secrets 2>/dev/null; bash -l -c takopi'" 2>/dev/null && \
            echo "Takopi started in tmux session 'takopi'" || \
            echo "Warning: Failed to start Takopi"
    else
        echo "Takopi configured but not installed. Run: uv tool install takopi"
    fi
else
    echo "Takopi not configured (no ~/.takopi/takopi.toml)"
fi

# Start health check watchdog in background
if [ "${ENABLE_HEALTHCHECK:-1}" = "1" ]; then
    echo "Starting health check watchdog..."
    /usr/local/bin/healthcheck.sh --watch >> /data/logs/healthcheck.log 2>&1 &
    HEALTHCHECK_PID=$!
fi

echo "=== Agent Box Ready ==="
echo "SSH: port 2222"
echo "Webhook: port 8080"
echo "Tailscale: $(tailscale ip -4 2>/dev/null || echo 'pending auth')"
echo "Takopi: $(su - agent -c 'tmux has-session -t takopi 2>/dev/null' && echo 'running' || echo 'not running')"

# Send startup notification if configured
if [ -f "/data/config/notify.conf" ]; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo 'pending')
    /usr/local/bin/notify.sh -t "Agent Box Started" --tags "rocket" \
        "Agent Box is ready. Tailscale IP: $TAILSCALE_IP" 2>/dev/null || true
fi

# Keep container running (wait for any child process)
# shellcheck disable=SC2086
wait -n $SSHD_PID ${WEBHOOK_PID:-} ${HEALTHCHECK_PID:-}
