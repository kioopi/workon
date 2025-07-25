#!/usr/bin/env bash
#
# WorkOn Resolve Command Module
#
# This module handles resource resolution functionality for WorkOn including:
# - Resource command extraction from manifests
# - Template variable resolution and analysis
# - Path expansion and command resolution
# - File/command existence checking
#
# Functions:
#   resolve_get_command() - Extract command for a specific resource
#   resolve_show_info() - Display resource information and availability
#   resolve_show_results() - Show complete resolution with template analysis
#   resolve_resource() - Main resolve function with full workflow

set -euo pipefail

# Get resource command from manifest
resolve_get_command() {
    local resource_name="$1"
    local manifest_json="$2"
    
    jq -r --arg resource "$resource_name" '.resources[$resource] // empty' <<<"$manifest_json" 2>/dev/null
}

# Show resource resolution info
resolve_show_info() {
    local resource_name="$1"
    local raw_command="$2"
    local manifest_json="$3"
    
    if [[ -z $raw_command ]]; then
        printf "❌ Resource '%s' not found in manifest\n" "$resource_name"
        printf "\nAvailable resources:\n"
        jq -r '.resources | keys[] | "  • " + .' <<<"$manifest_json" 2>/dev/null
        return 1
    fi
    
    printf "🎯 Resource: %s\n" "$resource_name"
    printf "📝 Raw command: %s\n" "$raw_command"
    return 0
}

# Show resolution results with template analysis
resolve_show_results() {
    local raw_command="$1"
    
    # Show template analysis
    template_analyze "$raw_command" || true
    
    # Resolve template variables
    local resolved_command
    resolved_command=$(template_render "$raw_command")
    
    # Expand relative paths to absolute paths
    local expanded_command
    expanded_command=$(path_expand_relative "$resolved_command")
    
    printf "✅ Resolved command: pls-open %s\n" "$expanded_command"
    
    # Check if file/command exists
    printf "📋 File/Command exists: %s\n" "$(resolve_check_existence "$expanded_command")"
}

# Check if file or command exists
resolve_check_existence() {
    local expanded_command="$1"
    
    # path_resource_exists already provides the formatted output
    path_resource_exists "$expanded_command"
}

# Show resolved command for a specific resource
resolve_resource() {
    local resource_name="$1"
    local project_path="${2:-$PWD}"
    
    if [[ -z $resource_name ]]; then
        printf "Usage: workon resolve <resource> [project_path]\n" >&2
        return 2
    fi
    
    printf "WorkOn Resource Resolution\n"
    printf "==========================\n\n"
    
    # Find manifest file
    local manifest
    if ! manifest=$(manifest_find "$project_path"); then
        printf "❌ No workon.yaml found in %s or parent directories\n" "$project_path"
        return 2
    fi
    
    printf "📁 Manifest: %s\n" "$manifest"
    
    # Change to manifest directory for relative path resolution
    local manifest_dir
    manifest_dir=$(dirname "$manifest")
    local orig_pwd="$PWD"
    cd "$manifest_dir" || {
        printf "❌ Cannot change to manifest directory: %s\n" "$manifest_dir"
        return 1
    }
    
    # Parse manifest
    local manifest_json
    if ! manifest_json=$(utils_parse_yaml "$manifest"); then
        cd "$orig_pwd" || return 1
        printf "❌ Failed to parse manifest (YAML syntax error)\n"
        return 1
    fi
    
    # Get the resource command
    local raw_command
    raw_command=$(resolve_get_command "$resource_name" "$manifest_json")
    
    # Show resource info
    if ! resolve_show_info "$resource_name" "$raw_command" "$manifest_json"; then
        cd "$orig_pwd" || return 1
        return 1
    fi
    
    # Show resolution results
    resolve_show_results "$raw_command"
    
    # Restore original directory
    cd "$orig_pwd" || return 1
    
    return 0
}