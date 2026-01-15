#!/bin/bash
# Claude Code Notification Hook
#
# This hook is triggered when Claude Code emits a notification event.
# It parses the hook JSON and sends a push notification.

# Read JSON from stdin
INPUT=$(cat)

# Parse fields from the hook JSON
# Hook JSON structure varies by event type, but typically includes:
# - type: the event type
# - message: the notification message
# - title: optional title

EVENT_TYPE=$(echo "$INPUT" | jq -r '.type // "notification"')
MESSAGE=$(echo "$INPUT" | jq -r '.message // .content // "Agent needs attention"')
TITLE=$(echo "$INPUT" | jq -r '.title // empty')

# Get agent name from environment (set by cc-new)
AGENT="${AGENT_NAME:-unknown}"

# Determine priority based on event type
case "$EVENT_TYPE" in
    "error"|"failure")
        PRIORITY="high"
        TAGS="warning"
        ;;
    "question"|"input_required"|"prompt")
        PRIORITY="high"
        TAGS="question"
        ;;
    "success"|"complete")
        PRIORITY="default"
        TAGS="white_check_mark"
        ;;
    *)
        PRIORITY="default"
        TAGS="robot"
        ;;
esac

# Build notification command
NOTIFY_ARGS=("-a" "$AGENT" "-p" "$PRIORITY" "--tags" "$TAGS")

if [ -n "$TITLE" ]; then
    NOTIFY_ARGS+=("-t" "$TITLE")
fi

# Send the notification
/usr/local/bin/notify.sh "${NOTIFY_ARGS[@]}" "$MESSAGE"

# Log the notification
LOG_DIR="${AGENT_LOG_DIR:-/data/logs/$AGENT}"
mkdir -p "$LOG_DIR"
echo "[$(date -Iseconds)] [$EVENT_TYPE] $MESSAGE" >> "$LOG_DIR/notifications.log"
