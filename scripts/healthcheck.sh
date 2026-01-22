#!/bin/bash
# healthcheck.sh - Monitor Agent Box services and auto-restart Takopi
#
# Checks:
#   - Takopi running (if configured) - auto-restarts if down
#   - Tailscale connected
#   - SSH daemon running
#   - Memory usage
#
# Usage:
#   healthcheck.sh          # Run once
#   healthcheck.sh --watch  # Run continuously (every 60s)

set -e

AGENT_HOME="${AGENT_HOME:-/data/home/agent}"
CHECK_INTERVAL="${CHECK_INTERVAL:-60}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
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
        return 0
    else
        log "Takopi: NOT RUNNING - attempting restart..."

        # Attempt restart
        if start_takopi; then
            log "Takopi: restarted successfully"
        else
            log "Takopi: restart failed"
        fi
        return 1
    fi
}

check_tailscale() {
    if tailscale status &>/dev/null; then
        local ip
        ip=$(tailscale ip -4 2>/dev/null || echo "unknown")
        log "Tailscale: connected ($ip)"
        return 0
    else
        log "Tailscale: NOT CONNECTED"
        return 1
    fi
}

check_sshd() {
    if pgrep -x sshd > /dev/null; then
        log "SSH: running"
        return 0
    else
        log "SSH: NOT RUNNING"
        return 1
    fi
}

check_memory() {
    # Log memory stats and warn if low
    local mem_info
    mem_info=$(free -m | awk '/^Mem:/ {printf "used=%dMB free=%dMB total=%dMB (%.0f%% used)", $3, $4, $2, $3/$2*100}')
    local swap_info
    swap_info=$(free -m | awk '/^Swap:/ {if($2>0) printf "swap=%dMB/%dMB", $3, $2; else print "swap=none"}')

    log "Memory: $mem_info $swap_info"

    # Warn if less than 200MB free
    local free_mb
    free_mb=$(free -m | awk '/^Mem:/ {print $4}')
    if [ "$free_mb" -lt 200 ]; then
        log "WARNING: Low memory detected (${free_mb}MB free)"
        return 1
    fi
    return 0
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
    # Kill tmux server first to ensure fresh environment with current secrets
    su - agent -c "tmux kill-server 2>/dev/null || true"
    sleep 1
    # Explicitly source env.secrets to ensure API keys are available
    su - agent -c "tmux new-session -d -s takopi 'source ~/.env.secrets 2>/dev/null; bash -l -c takopi'" 2>/dev/null

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
    check_memory || true  # Don't count memory warning as failure

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
