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

    # Get memory values for threshold checks
    local free_mb used_percent
    free_mb=$(free -m | awk '/^Mem:/ {print $4}')
    used_percent=$(free -m | awk '/^Mem:/ {printf "%.0f", $3/$2*100}')

    # Log top memory consumers when usage is high (>70%) or free is low (<500MB)
    if [ "$used_percent" -gt 70 ] || [ "$free_mb" -lt 500 ]; then
        log "Top memory consumers:"
        ps aux --sort=-%mem | head -6 | tail -5 | while read -r line; do
            local user pid mem cmd
            user=$(echo "$line" | awk '{print $1}')
            pid=$(echo "$line" | awk '{print $2}')
            mem=$(echo "$line" | awk '{print $4}')
            cmd=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-60)
            log "  ${mem}% (PID $pid, $user): $cmd"
        done
    fi

    # Critical warning if less than 200MB free
    if [ "$free_mb" -lt 200 ]; then
        log "CRITICAL: Very low memory (${free_mb}MB free) - OOM kill imminent!"
        # Log all node processes specifically since they tend to be memory hogs
        local node_procs
        node_procs=$(pgrep -a node 2>/dev/null | head -5 || true)
        if [ -n "$node_procs" ]; then
            log "Node.js processes:"
            echo "$node_procs" | while read -r line; do
                local pid
                pid=$(echo "$line" | awk '{print $1}')
                local mem_kb
                mem_kb=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
                local mem_mb=$((mem_kb / 1024))
                log "  PID $pid: ${mem_mb}MB - $(echo "$line" | cut -d' ' -f2- | cut -c1-50)"
            done
        fi
        return 1
    fi

    # Warning if less than 500MB free
    if [ "$free_mb" -lt 500 ]; then
        log "WARNING: Low memory detected (${free_mb}MB free)"
    fi

    return 0
}

start_takopi() {
    local takopi_config="$AGENT_HOME/.takopi/takopi.toml"
    local takopi_lock="$AGENT_HOME/.takopi/takopi.lock"

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

    # Remove stale lockfile if it exists but no takopi process is running
    if [ -f "$takopi_lock" ]; then
        if ! pgrep -f "takopi" > /dev/null 2>&1; then
            log "Removing stale Takopi lockfile"
            rm -f "$takopi_lock"
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

sync_claude_config() {
    # Sync Claude config from remote repo daily
    # Only runs if CLAUDE_CONFIG_REPO is set and repo is initialized
    if [ -z "$CLAUDE_CONFIG_REPO" ]; then
        return 0
    fi

    if [ ! -d "$AGENT_HOME/.claude/.git" ]; then
        return 0
    fi

    # Only sync once per day
    SYNC_MARKER_FILE="/tmp/claude-config-sync-$(date +%Y%m%d)"
    if [ -f "$SYNC_MARKER_FILE" ]; then
        return 0
    fi

    log "Syncing Claude config (daily)..."
    if su - agent -c "CLAUDE_CONFIG_REPO='$CLAUDE_CONFIG_REPO' claude-config-sync" 2>/dev/null; then
        touch "$SYNC_MARKER_FILE"
        log "Claude config: synced"
    else
        log "Claude config: sync failed"
    fi
}

run_checks() {
    local failed=0

    check_tailscale || ((failed++))
    check_sshd || ((failed++))
    check_takopi || ((failed++))
    check_memory || true  # Don't count memory warning as failure
    sync_claude_config || true  # Don't count sync failure

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
