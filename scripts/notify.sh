#!/bin/bash
# notify.sh - Send push notification via ntfy
#
# Used by Claude Code hooks to notify when agent needs attention.
# Configure NTFY_TOPIC and NTFY_SERVER via environment or /data/config/notify.conf

# Load config if exists
CONFIG_FILE="/data/config/notify.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Defaults
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"
NTFY_TOPIC="${NTFY_TOPIC:-agent-box}"
NTFY_PRIORITY="${NTFY_PRIORITY:-default}"

usage() {
    echo "Usage: notify.sh [options] <message>"
    echo ""
    echo "Send a push notification via ntfy."
    echo ""
    echo "Options:"
    echo "  -t, --title <title>     Notification title"
    echo "  -p, --priority <level>  Priority: min, low, default, high, urgent"
    echo "  -a, --agent <name>      Agent name (adds to title)"
    echo "  -c, --click <url>       URL to open on click"
    echo "  --tags <tags>           Comma-separated tags (emoji shortcodes)"
    echo ""
    echo "Environment:"
    echo "  NTFY_SERVER   Server URL (default: https://ntfy.sh)"
    echo "  NTFY_TOPIC    Topic name (default: agent-box)"
    echo ""
    echo "Config file: /data/config/notify.conf"
    exit 1
}

# Parse arguments
TITLE=""
AGENT=""
CLICK=""
TAGS=""
MESSAGE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--title)
            TITLE="$2"
            shift 2
            ;;
        -p|--priority)
            NTFY_PRIORITY="$2"
            shift 2
            ;;
        -a|--agent)
            AGENT="$2"
            shift 2
            ;;
        -c|--click)
            CLICK="$2"
            shift 2
            ;;
        --tags)
            TAGS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            MESSAGE="$1"
            shift
            ;;
    esac
done

if [ -z "$MESSAGE" ]; then
    usage
fi

# Build title
if [ -n "$AGENT" ]; then
    if [ -n "$TITLE" ]; then
        TITLE="[$AGENT] $TITLE"
    else
        TITLE="Agent: $AGENT"
    fi
fi

# Build curl command
CURL_ARGS=("-s" "-o" "/dev/null" "-w" "%{http_code}")
CURL_ARGS+=("-d" "$MESSAGE")

if [ -n "$TITLE" ]; then
    CURL_ARGS+=("-H" "Title: $TITLE")
fi

CURL_ARGS+=("-H" "Priority: $NTFY_PRIORITY")

if [ -n "$CLICK" ]; then
    CURL_ARGS+=("-H" "Click: $CLICK")
fi

if [ -n "$TAGS" ]; then
    CURL_ARGS+=("-H" "Tags: $TAGS")
fi

# Send notification
URL="${NTFY_SERVER}/${NTFY_TOPIC}"
HTTP_CODE=$(curl "${CURL_ARGS[@]}" "$URL")

if [ "$HTTP_CODE" = "200" ]; then
    echo "Notification sent to $NTFY_TOPIC"
    exit 0
else
    echo "Error: Failed to send notification (HTTP $HTTP_CODE)"
    exit 1
fi
