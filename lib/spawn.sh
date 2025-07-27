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
# shellcheck source=lib/debug.sh
source "${BASH_SOURCE[0]%/*}/debug.sh"
# shellcheck source=lib/template.sh
source "${BASH_SOURCE[0]%/*}/template.sh"
# shellcheck source=lib/path.sh
source "${BASH_SOURCE[0]%/*}/path.sh"

# ── Core Spawning Functions ────────────────────────────────────────────────

# Convert base64-encoded resources to JSON array with template expansion
spawn_prepare_resources_json() {
    local resources="$1"  # Base64-encoded resource entries
    
    debug_section "Resource Preparation"
    verbose_log "Processing resource entries for spawning..."
    
    local resources_json="[]"
    local processed_count=0
    
    while read -r entry; do
        if [[ -z $entry ]]; then
            continue
        fi
        
        local name raw_cmd rendered_cmd expanded_cmd
        
        # Decode and extract resource data
        debug_log "Processing resource entry: $entry"
        name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
        raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue
        
        verbose_log "Processing resource '$name': $raw_cmd"

        # Render template variables
        debug_log "Rendering templates for: $raw_cmd"
        rendered_cmd=$(template_render "$raw_cmd")
        if [[ "$rendered_cmd" != "$raw_cmd" ]]; then
            debug_log "Template rendered: $raw_cmd -> $rendered_cmd"
        fi
        
        # Expand relative paths to absolute paths
        debug_log "Expanding paths for: $rendered_cmd"
        expanded_cmd=$(path_expand_relative "$rendered_cmd")
        if [[ "$expanded_cmd" != "$rendered_cmd" ]]; then
            debug_log "Paths expanded: $rendered_cmd -> $expanded_cmd"
        fi
        
        # Add to resources JSON array
        local resource_entry
        local final_cmd="pls-open $expanded_cmd"
        resource_entry=$(jq -n \
            --arg name "$name" \
            --arg cmd "$final_cmd" \
            '{name: $name, cmd: $cmd}')
        
        resources_json=$(printf '%s' "$resources_json" | jq ". + [$resource_entry]")
        processed_count=$((processed_count + 1))
        
        success_log "Prepared resource '$name': $final_cmd"
        
    done <<<"$resources"
    
    verbose_log "Processed $processed_count resources for spawning"
    printf '%s' "$resources_json"
}

# Execute AwesomeWM Lua script with embedded configuration
spawn_execute_lua_script() {
    local session_file="$1"
    local resources_json="$2"
    local layout_json="${3:-}"
    
    debug_section "Lua Script Execution"
    
    # Prepare configuration for Lua script
    verbose_log "Preparing Lua script configuration..."
    local spawn_config
    if [[ -n $layout_json && $layout_json != "null" && $layout_json != "[]" ]]; then
        debug_log "Using layout-based configuration"
        spawn_config=$(jq -n \
            --arg session_file "$session_file" \
            --argjson resources "$resources_json" \
            --argjson layout "$layout_json" \
            '{session_file: $session_file, resources: $resources, layout: $layout}')
    else
        debug_log "Using sequential configuration (no layout)"
        spawn_config=$(jq -n \
            --arg session_file "$session_file" \
            --argjson resources "$resources_json" \
            '{session_file: $session_file, resources: $resources}')
    fi
    
    debug_var "spawn_config"
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '📋 Spawn Config JSON:\n%s\n' "$spawn_config" >&2
    fi
    
    # Escape the JSON for Lua string literal
    verbose_log "Escaping JSON configuration for Lua..."
    local escaped_config
    escaped_config=$(printf '%s' "$spawn_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    debug_var "escaped_config"
    
    # Prepare Lua code
    local workon_dir="${WORKON_DIR:-$PWD}"
    local lua_code="
        WORKON_DIR = '$workon_dir'
        WORKON_SPAWN_CONFIG = '$escaped_config'
        dofile('$workon_dir/lib/spawn_resources.lua')
    "
    
    # Execute the spawn script with enhanced error capture
    verbose_log "Executing AwesomeWM Lua script..."
    debug_awesome_client "$lua_code" "spawn-script"
}

# Wait for session file to be created/updated with timeout
spawn_wait_for_session_update() {
    local session_file="$1"
    local initial_count="$2"
    local timeout="$3"
    
    debug_section "Session File Monitoring"
    verbose_log "Waiting for session file updates (timeout: ${timeout}s)..."
    debug_var "session_file"
    debug_var "initial_count"
    
    local wait_count=0
    while [[ $timeout -gt 0 ]]; do
        if [[ -f "$session_file" ]]; then
            local current_count
            current_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
            
            debug_log "Session file check: $current_count entries (was $initial_count)"
            
            # Check if we have new entries (allowing for partial success)
            if [[ $current_count -gt $initial_count ]]; then
                success_log "Session file updated with $current_count entries"
                debug_file "$session_file" "session file contents"
                return 0
            fi
        else
            debug_log "Session file does not exist yet"
        fi
        
        sleep 0.5
        timeout=$((timeout - 1))
        wait_count=$((wait_count + 1))
        
        # Show progress every 5 seconds in verbose mode
        if [[ $((wait_count % 10)) -eq 0 ]]; then
            verbose_log "Still waiting for session updates... (${timeout}s remaining)"
        fi
    done
    
    error_log "session-wait" "Session file not updated within timeout"
    if [[ -f "$session_file" ]]; then
        debug_file "$session_file" "final session file state"
    fi
    return 1
}

# Complete resource spawning orchestration
spawn_launch_all_resources() {
    local session_file="$1"
    local resources="$2"  # Base64-encoded resource entries
    local layout="${3:-}"  # Optional layout JSON
    
    debug_section "Resource Spawning Orchestration"
    
    if [[ -n $layout && $layout != "null" ]]; then
        verbose_log "Preparing resources for layout-based spawning"
        debug_var "layout"
    else
        verbose_log "Preparing resources for sequential spawning (no layout)"
    fi
    
    # Prepare resources JSON with template expansion and path resolution
    verbose_log "Starting resource preparation pipeline..."
    local resources_json
    resources_json=$(spawn_prepare_resources_json "$resources")
    
    # Check if we have any resources to spawn
    local resource_count
    resource_count=$(printf '%s' "$resources_json" | jq 'length')
    debug_var "resource_count"
    
    if [[ $resource_count -eq 0 ]]; then
        error_log "spawn" "No resources to spawn"
        return 1
    fi
    
    success_log "Prepared $resource_count resources for spawning"
    
    # Display prepared resources in non-debug mode
    if [[ "${WORKON_VERBOSE:-0}" == "1" ]] && [[ "${WORKON_DEBUG:-0}" != "1" ]]; then
        verbose_log "Resources to spawn:"
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
    fi
    
    verbose_log "Spawning $resource_count resources via AwesomeWM Lua script..."
    
    # Get initial count for monitoring before executing script
    local initial_count=0
    if [[ -f "$session_file" ]]; then
        initial_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
    fi
    debug_var "initial_count"
    
    # In dry-run mode, show what would be executed but don't actually do it
    if [[ "${WORKON_DRY_RUN:-0}" == "1" ]]; then
        printf '🚫 DRY-RUN: Would execute Lua script to spawn %d resources\n' "$resource_count" >&2
        printf '🚫 DRY-RUN: Session file would be: %s\n' "$session_file" >&2
        return 0
    fi
    
    # Execute Lua script
    verbose_log "Executing AwesomeWM spawn script..."
    if ! spawn_execute_lua_script "$session_file" "$resources_json" "$layout"; then
        error_log "spawn" "Failed to execute AwesomeWM Lua script"
        return 1
    fi
    
    # Wait for session file update with 15 second timeout
    verbose_log "Monitoring session file for spawn results..."
    spawn_wait_for_session_update "$session_file" "$initial_count" 15
}

# ── Legacy Function Aliases ────────────────────────────────────────────────
# These maintain backward compatibility with existing code

launch_all_resources_with_session() { spawn_launch_all_resources "$@"; }