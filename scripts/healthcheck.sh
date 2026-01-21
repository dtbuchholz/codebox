#!/bin/bash
# healthcheck.sh - Monitor Agent Box services and notify on issues
#
# Checks:
#   - Takopi running (if configured)
#   - Tailscale connected
#   - SSH daemon running
#
# Usage:
#   healthcheck.sh          # Run once
#   healthcheck.sh --watch  # Run continuously (every 60s)

set -e

AGENT_HOME="${AGENT_HOME:-/data/home/agent}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"
NOTIFY_COOLDOWN="${NOTIFY_COOLDOWN:-300}"  # Don't spam notifications

# Track last notification time per service
NOTIFY_STATE_DIR="/tmp/healthcheck-state"
mkdir -p "$NOTIFY_STATE_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

should_notify() {
    local service="$1"
    local state_file="$NOTIFY_STATE_DIR/$service.last_notify"
    local now
    now=$(date +%s)

    if [ ! -f "$state_file" ]; then
        echo "$now" > "$state_file"
        return 0
    fi

    local last_notify
    last_notify=$(cat "$state_file")
    local elapsed=$((now - last_notify))

    if [ "$elapsed" -ge "$NOTIFY_COOLDOWN" ]; then
        echo "$now" > "$state_file"
        return 0
    fi

    return 1
}

clear_notify_state() {
    local service="$1"
    rm -f "$NOTIFY_STATE_DIR/$service.last_notify"
}

notify_if_enabled() {
    local service="$1"
    local title="$2"
    local message="$3"
    local priority="${4:-high}"

    if ! should_notify "$service"; then
        log "Skipping notification for $service (cooldown)"
        return
    fi

    if command -v notify.sh &> /dev/null; then
        notify.sh -t "$title" -p "$priority" --tags "warning" "$message" || true
    fi
}

check_takopi() {
    local takopi_config="$AGENT_HOME/.takopi/takopi.toml"

    # Skip if takopi not configured
    if [ ! -f "$takopi_config" ]; then
        log "Takopi: not configured (no config file)"
        return 0
    fi

    # Check if takopi tmux session exists
    if su - agent -c "tmux has-session -t takopi 2>/dev/null"; then
        log "Takopi: running"
        clear_notify_state "takopi"
        return 0
    else
        log "Takopi: NOT RUNNING"
        notify_if_enabled "takopi" "Takopi Down" "Takopi is not running. Attempting restart..."

        # Attempt restart
        if start_takopi; then
            log "Takopi: restarted successfully"
            notify_if_enabled "takopi-recovered" "Takopi Recovered" "Takopi has been restarted successfully" "default"
        else
            log "Takopi: restart failed"
            notify_if_enabled "takopi" "Takopi Restart Failed" "Failed to restart Takopi. Manual intervention required."
        fi
        return 1
    fi
}

check_tailscale() {
    if tailscale status &>/dev/null; then
        local ip
        ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
        log "Tailscale: connected ($ip)"
        clear_notify_state "tailscale"
        return 0
    else
        log "Tailscale: NOT CONNECTED"
        notify_if_enabled "tailscale" "Tailscale Down" "Tailscale is not connected. SSH access may be unavailable."
        return 1
    fi
}

check_sshd() {
    if pgrep -x sshd > /dev/null; then
        log "SSH: running"
        clear_notify_state "sshd"
        return 0
    else
        log "SSH: NOT RUNNING"
        notify_if_enabled "sshd" "SSH Down" "SSH daemon is not running."
        return 1
    fi
}

start_takopi() {
    local takopi_config="$AGENT_HOME/.takopi/takopi.toml"

    if [ ! -f "$takopi_config" ]; then
        log "Cannot start Takopi: no config file"
        return 1
    fi

    if ! command -v takopi &> /dev/null; then
        # Check if takopi is installed via uv for the agent user
        if [ ! -x "$AGENT_HOME/.local/bin/takopi" ]; then
            log "Cannot start Takopi: not installed"
            return 1
        fi
    fi

    log "Starting Takopi..."
    su - agent -c "tmux new-session -d -s takopi 'bash -l -c takopi'" 2>/dev/null

    # Wait a moment and verify it started
    sleep 2
    if su - agent -c "tmux has-session -t takopi 2>/dev/null"; then
        return 0
    else
        return 1
    fi
}

run_checks() {
    local failed=0

    check_tailscale || ((failed++))
    check_sshd || ((failed++))
    check_takopi || ((failed++))

    return $failed
}

# Main
case "${1:-}" in
    --watch)
        log "Starting health check watchdog (interval: ${CHECK_INTERVAL}s)"
        while true; do
            run_checks || true
            sleep "$CHECK_INTERVAL"
        done
        ;;
    --start-services)
        # Called from entrypoint to start optional services
        log "Starting optional services..."
        start_takopi || log "Takopi not started (not configured or not installed)"
        ;;
    *)
        run_checks
        ;;
esac
