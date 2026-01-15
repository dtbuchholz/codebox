#!/bin/bash
# Claude Code Prompt Hook
#
# Triggered when Claude is waiting for user input.
# Sends a notification so you can respond from your phone.

INPUT=$(cat)

AGENT="${AGENT_NAME:-unknown}"
MESSAGE="Claude is waiting for input"

# Check if there's a specific prompt message
PROMPT_TEXT=$(echo "$INPUT" | jq -r '.prompt // .message // empty')
if [ -n "$PROMPT_TEXT" ]; then
    # Truncate long prompts
    if [ ${#PROMPT_TEXT} -gt 100 ]; then
        PROMPT_TEXT="${PROMPT_TEXT:0:100}..."
    fi
    MESSAGE="$PROMPT_TEXT"
fi

# Send high-priority notification
/usr/local/bin/notify.sh \
    -a "$AGENT" \
    -t "Input Needed" \
    -p "high" \
    --tags "question,speech_balloon" \
    "$MESSAGE"

# Log
LOG_DIR="${AGENT_LOG_DIR:-/data/logs/$AGENT}"
mkdir -p "$LOG_DIR"
echo "[$(date -Iseconds)] [prompt] $MESSAGE" >> "$LOG_DIR/notifications.log"
