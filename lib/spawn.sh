#!/usr/bin/env bash
# WorkOn Resource Spawning Module
# 
# This module handles resource spawning coordination and Lua script integration:
# - Resource preparation with template expansion and path resolution
# - JSON configuration building for Lua script execution
# - AwesomeWM Lua script execution coordination
# - Session file monitoring and timeout handling
#
# Functions:
#   spawn_prepare_resources_json() - Convert base64 resources to JSON array
#   spawn_execute_lua_script() - Execute AwesomeWM Lua spawning script
#   spawn_wait_for_session_update() - Monitor session file for updates
#   spawn_launch_all_resources() - Complete resource spawning orchestration

set -euo pipefail

# Source required modules
# shellcheck source=lib/config.sh
source "${BASH_SOURCE[0]%/*}/config.sh"
# shellcheck source=lib/template.sh
source "${BASH_SOURCE[0]%/*}/template.sh"
# shellcheck source=lib/path.sh
source "${BASH_SOURCE[0]%/*}/path.sh"

# ── Core Spawning Functions ────────────────────────────────────────────────

# Convert base64-encoded resources to JSON array with template expansion
spawn_prepare_resources_json() {
    local resources="$1"  # Base64-encoded resource entries
    
    local resources_json="[]"
    
    while read -r entry; do
        if [[ -z $entry ]]; then
            continue
        fi
        
        local name raw_cmd rendered_cmd expanded_cmd
        
        # Decode and extract resource data
        name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
        raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue

        # Render template variables
        rendered_cmd=$(template_render "$raw_cmd")
        
        # Expand relative paths to absolute paths
        expanded_cmd=$(path_expand_relative "$rendered_cmd")
        
        # Add to resources JSON array
        local resource_entry
        resource_entry=$(jq -n \
            --arg name "$name" \
            --arg cmd "pls-open $expanded_cmd" \
            '{name: $name, cmd: $cmd}')
        
        resources_json=$(printf '%s' "$resources_json" | jq ". + [$resource_entry]")
        
    done <<<"$resources"
    
    printf '%s' "$resources_json"
}

# Execute AwesomeWM Lua script with embedded configuration
spawn_execute_lua_script() {
    local session_file="$1"
    local resources_json="$2"
    
    # Prepare configuration for Lua script
    local spawn_config
    spawn_config=$(jq -n \
        --arg session_file "$session_file" \
        --argjson resources "$resources_json" \
        '{session_file: $session_file, resources: $resources}')
    
    # Escape the JSON for Lua string literal
    local escaped_config
    escaped_config=$(printf '%s' "$spawn_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    
    # Execute the spawn script with configuration embedded directly in Lua
    local workon_dir="${WORKON_DIR:-$PWD}"
    awesome-client "
        WORKON_DIR = '$workon_dir'
        WORKON_SPAWN_CONFIG = '$escaped_config'
        dofile('$workon_dir/lib/spawn_resources.lua')
    "
}

# Wait for session file to be created/updated with timeout
spawn_wait_for_session_update() {
    local session_file="$1"
    local initial_count="$2"
    local timeout="$3"
    
    while [[ $timeout -gt 0 ]]; do
        if [[ -f "$session_file" ]]; then
            local current_count
            current_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
            
            # Check if we have new entries (allowing for partial success)
            if [[ $current_count -gt $initial_count ]]; then
                printf 'Session file updated with %d entries\n' "$current_count" >&2
                return 0
            fi
        fi
        
        sleep 0.5
        timeout=$((timeout - 1))
    done
    
    printf 'Warning: Session file not updated within timeout\n' >&2
    return 1
}

# Complete resource spawning orchestration
spawn_launch_all_resources() {
    local session_file="$1"
    local resources="$2"  # Base64-encoded resource entries
    
    printf 'Preparing resources for spawning:\n' >&2
    
    # Prepare resources JSON with template expansion and path resolution
    local resources_json
    resources_json=$(spawn_prepare_resources_json "$resources")
    
    # Check if we have any resources to spawn
    local resource_count
    resource_count=$(printf '%s' "$resources_json" | jq 'length')
    
    if [[ $resource_count -eq 0 ]]; then
        printf 'No resources to spawn\n' >&2
        return 1
    fi
    
    # Display prepared resources
    while read -r entry; do
        if [[ -z $entry ]]; then
            continue
        fi
        
        local name raw_cmd rendered_cmd expanded_cmd
        name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
        raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue
        rendered_cmd=$(template_render "$raw_cmd")
        expanded_cmd=$(path_expand_relative "$rendered_cmd")
        
        printf '  %s: %s\n' "$name" "$expanded_cmd" >&2
    done <<<"$resources"
    
    printf 'Spawning %d resources via single Lua script...\n' "$resource_count" >&2
    
    # Get initial count for monitoring before executing script
    local initial_count=0
    if [[ -f "$session_file" ]]; then
        initial_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
    fi
    
    # Execute Lua script
    printf 'Executing awesome-client with embedded configuration\n' >&2
    spawn_execute_lua_script "$session_file" "$resources_json"
    
    # Wait for session file update with 15 second timeout
    spawn_wait_for_session_update "$session_file" "$initial_count" 15
}

# ── Legacy Function Aliases ────────────────────────────────────────────────
# These maintain backward compatibility with existing code

launch_all_resources_with_session() { spawn_launch_all_resources "$@"; }