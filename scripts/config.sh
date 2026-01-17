#!/bin/bash
# config.sh - Configuration utilities for Agent Box
#
# Source this file to use config functions:
#   source /usr/local/bin/config.sh
#   value=$(config_get "section.key" "default")

# Config file location
CONFIG_FILE="${AGENTBOX_CONFIG:-/data/config/agentbox.toml}"

# Read a value from the TOML config
# Usage: config_get "section.key" "default_value"
# Example: config_get "notifications.topic" "agent-box"
config_get() {
    local key="$1"
    local default="$2"

    # If config file doesn't exist, return default
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "$default"
        return
    fi

    # Split key into section and field
    local section="${key%%.*}"
    local field="${key#*.}"

    # Handle nested sections (e.g., projects.myproject.path)
    if [[ "$field" == *"."* ]]; then
        local subsection="${field%%.*}"
        field="${field#*.}"
        section="${section}.${subsection}"
    fi

    # Parse TOML - find section and extract value
    local in_section=false
    local section_pattern="^\[${section}\]"
    local value=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Check for section header
        if [[ "$line" =~ ^\[.*\] ]]; then
            if [[ "$line" =~ $section_pattern ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # If in the right section, look for the key
        if $in_section; then
            # Match key = value or key = "value"
            if [[ "$line" =~ ^[[:space:]]*${field}[[:space:]]*=[[:space:]]*(.*) ]]; then
                value="${BASH_REMATCH[1]}"
                # Remove quotes if present
                value="${value#\"}"
                value="${value%\"}"
                # Remove inline comments
                value="${value%%#*}"
                # Trim whitespace
                value="${value%"${value##*[![:space:]]}"}"
                echo "$value"
                return
            fi
        fi
    done < "$CONFIG_FILE"

    # Return default if not found
    echo "$default"
}

# Check if a boolean config value is true
# Usage: config_enabled "section.key"
config_enabled() {
    local key="$1"
    local value
    value=$(config_get "$key" "false")

    case "${value,,}" in
        true|yes|1|on) return 0 ;;
        *) return 1 ;;
    esac
}

# Get project path from alias
# Usage: project_path "myproject"
project_path() {
    local alias="$1"
    config_get "projects.${alias}.path" ""
}

# Get project worktrees directory
# Usage: project_worktrees_dir "myproject"
project_worktrees_dir() {
    local alias="$1"
    local project_dir
    project_dir=$(project_path "$alias")

    if [[ -z "$project_dir" ]]; then
        echo ""
        return
    fi

    local worktrees_dir
    worktrees_dir=$(config_get "projects.${alias}.worktrees_dir" "")

    if [[ -z "$worktrees_dir" ]]; then
        worktrees_dir=$(config_get "worktrees.dir" ".worktrees")
    fi

    echo "${project_dir}/${worktrees_dir}"
}

# Get project base branch
# Usage: project_base_branch "myproject"
project_base_branch() {
    local alias="$1"
    local branch
    branch=$(config_get "projects.${alias}.base_branch" "")

    if [[ -z "$branch" ]]; then
        branch=$(config_get "worktrees.base_branch" "main")
    fi

    echo "$branch"
}

# List all configured projects
# Usage: list_projects
list_projects() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return
    fi

    grep -E '^\[projects\.' "$CONFIG_FILE" | sed 's/\[projects\.\(.*\)\]/\1/'
}

# Export for use in other scripts
export -f config_get config_enabled project_path project_worktrees_dir project_base_branch list_projects
