#!/usr/bin/env bash
#
# WorkOn Info Command Module
#
# This module handles all info-related subcommands for WorkOn including:
# - Basic system information display
# - Session listing and details
# - Debug output and dependency checking
#
# Functions:
#   info_show_basic() - Display basic WorkOn system information
#   info_show_sessions_list() - List all active sessions
#   info_show_session_details() - Show detailed information for a specific session
#   info_route_commands() - Route info subcommands to appropriate handlers

set -euo pipefail

# Display basic WorkOn system information
info_show_basic() {
    printf "WorkOn - one-shot project workspace bootstrapper\n\n"
    printf "Version: %s\n" "${VERSION:-0.1.0}"
    printf "Installation directory: %s\n" "${WORKON_DIR:-${PROJECT_ROOT:-}}"
    printf "Working directory: %s\n" "$PWD"
    printf "Cache directory: %s\n" "$(config_cache_dir)"
    printf "\n"
    
    # Check manifest status
    local manifest
    if manifest=$(manifest_find "$PWD" 2>/dev/null); then
        printf "Manifest: Found (%s)\n" "$manifest"
    else
        printf "Manifest: Not found\n"
    fi
    printf "\n"
    
    # Show dependency status
    printf "Dependencies:\n"
    printf "  yq: %s\n" "$(info_check_dependency yq)"
    printf "  jq: %s\n" "$(info_check_dependency jq)"
    printf "  awesome-client: %s\n" "$(info_check_dependency awesome-client)"
    printf "  realpath: %s\n" "$(info_check_dependency realpath)"
    printf "  sha1sum: %s\n" "$(info_check_dependency sha1sum)"
    printf "  flock: %s\n" "$(info_check_dependency flock)"
}

# Show list of all active sessions
info_show_sessions_list() {
    printf "Active WorkOn Sessions\n"
    printf "=====================\n\n"
    
    local cache_path
    cache_path="$(config_cache_dir)"
    
    if [[ ! -d "$cache_path" ]]; then
        printf "No cache directory found (%s)\n" "$cache_path"
        return 0
    fi
    
    local session_files
    mapfile -t session_files < <(find "$cache_path" -name "*.json" -type f 2>/dev/null | sort)
    
    if [[ ${#session_files[@]} -eq 0 ]]; then
        printf "No active sessions found\n"
        return 0
    fi
    
    printf "Found %d active session(s):\n\n" "${#session_files[@]}"
    
    for session_file in "${session_files[@]}"; do
        local session_name
        session_name=$(basename "$session_file" .json)
        
        local session_data resource_count
        if session_data=$(session_get_valid_data "$session_file"); then
            resource_count=$(printf '%s' "$session_data" | jq 'length' 2>/dev/null || echo "0")
        else
            resource_count="0"
        fi
        
        local parent_dir
        parent_dir=$(dirname "$session_file")
        printf "  • %s (%s resources)\n" "$session_name" "$resource_count"
        printf "    📄 %s\n\n" "$session_file"
    done
}

# Show detailed information for a specific session
info_show_session_details() {
    local project_path="${1:-$PWD}"
    
    printf "WorkOn Session Details\n"
    printf "======================\n\n"
    
    local session_file
    session_file=$(config_cache_file "$project_path")
    
    printf "📁 Project: %s\n" "$project_path"
    printf "📄 Session file: %s\n" "$session_file"
    
    local session_data
    if ! session_data=$(session_get_valid_data "$session_file"); then
        printf "❌ No active session found\n"
        return 1
    fi
    
    local resource_count
    resource_count=$(printf '%s' "$session_data" | jq 'length' 2>/dev/null || echo "0")
    
    printf "📦 Resources: %s\n\n" "$resource_count"
    
    if [[ "$resource_count" -gt 0 ]]; then
        local entries
        mapfile -t entries < <(printf '%s' "$session_data" | jq -c '.[]' 2>/dev/null)
        
        for entry in "${entries[@]}"; do
            local name pid cmd class instance spawn_time
            name=$(jq -r '.name // "unknown"' <<<"$entry" 2>/dev/null)
            pid=$(jq -r '.pid // "unknown"' <<<"$entry" 2>/dev/null)
            cmd=$(jq -r '.cmd // "unknown"' <<<"$entry" 2>/dev/null)
            class=$(jq -r '.class // "unknown"' <<<"$entry" 2>/dev/null)
            instance=$(jq -r '.instance // "unknown"' <<<"$entry" 2>/dev/null)
            spawn_time=$(jq -r '.spawn_time // "unknown"' <<<"$entry" 2>/dev/null)
            
            printf "🚀 Resource: %s\n" "$name"
            printf "   Command: %s\n" "$cmd"
            printf "   PID: %s\n" "$pid"
            printf "   Window: %s.%s\n" "$class" "$instance"
            printf "   Started: %s\n\n" "$spawn_time"
        done
    fi
}

# Check if a single dependency is available
info_check_dependency() {
    local cmd="$1"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "✅ available"
    else
        printf "❌ missing"
    fi
}

# Route info subcommands to appropriate handlers
info_route_commands() {
    local subcommand="${1:-}"
    [[ $# -gt 0 ]] && shift
    
    case "$subcommand" in
        "")
            info_show_basic
            ;;
        sessions)
            info_show_sessions_list
            ;;
        session)
            info_show_session_details "$@"
            ;;
        *)
            printf "Unknown info subcommand: %s\n" "$subcommand" >&2
            return 2
            ;;
    esac
}