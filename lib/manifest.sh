#!/usr/bin/env bash
# WorkOn Manifest Management Module
# 
# This module handles manifest file operations including:
# - Discovery of workon.yaml files by walking directory tree
# - Project name-based lookup using configured project paths
# - YAML parsing and JSON conversion with error handling
# - Manifest structure validation and resource extraction
# - Security validation for project names (path traversal prevention)
#
# Functions:
#   manifest_find() - Locate workon.yaml by path or project name
#   manifest_parse() - Convert YAML manifest to JSON with validation
#   manifest_validate_syntax() - Check YAML syntax without full parsing
#   manifest_validate_structure() - Validate required manifest sections
#   manifest_extract_resources() - Extract resource definitions as base64 entries
#   manifest_extract_layout() - Extract layout configuration with validation

# Source config module for project directory loading
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/config.sh disable=SC1091
source "$SCRIPT_DIR/config.sh"

# Find workon.yaml by walking up directory tree or searching configured project paths
manifest_find() {
    local target="${1:-$PWD}"

    if [[ -d $target || -f $target ]]; then
        local dir
        dir=$(realpath "$target")
        while [[ $dir != / ]]; do
            if [[ -f $dir/workon.yaml ]]; then
                printf '%s/workon.yaml' "$dir"
                return 0
            fi
            dir=$(dirname "$dir")
        done
    else
        local project_name="$target"
        
        # Validate project name to prevent path traversal attacks
        if [[ ! $project_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
            config_die "Invalid project name: '$project_name'. Project names must contain only alphanumeric characters, hyphens, and underscores."
        fi
        
        local search_dirs
        search_dirs=$(config_load_project_dirs)
        if [[ -n $search_dirs ]]; then
            while read -r base; do
                [[ -z $base ]] && continue
                
                # Expand tilde and validate directory exists
                local expanded_base
                expanded_base=$(eval echo "$base" 2>/dev/null) || continue
                [[ -d $expanded_base ]] || continue
                
                local candidate="$expanded_base/$project_name/workon.yaml"
                if [[ -f $candidate ]]; then
                    printf '%s' "$(realpath "$candidate")"
                    return 0
                fi
            done <<<"$search_dirs"
        fi
    fi

    return 1
}

# Parse and validate manifest JSON
manifest_parse() {
    local manifest="$1"
    local manifest_json
    
    # Parse YAML to JSON
    if ! manifest_json=$(yq eval -o=json '.' "$manifest" 2>/dev/null); then
        config_die "Failed to parse $manifest (check YAML syntax)"
    fi
    
    # Validate structure
    if ! jq -e '.resources' <<<"$manifest_json" >/dev/null 2>&1; then
        config_die "Invalid manifest: missing 'resources' section"
    fi
    
    # Check if resources is empty
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    if [[ "$resource_count" == "0" ]] || [[ "$resource_count" == "null" ]]; then
        config_die "No resources defined in manifest"
    fi
    
    printf '%s' "$manifest_json"
}

# Validate YAML syntax and print status
manifest_validate_syntax() {
    local manifest="$1"
    
    if manifest_parse_yaml_to_json "$manifest" >/dev/null; then
        return 0
    else
        return 1
    fi
}

# Parse YAML to JSON with error handling (helper function)
manifest_parse_yaml_to_json() {
    local yaml_file="$1"
    
    local manifest_json
    if ! manifest_json=$(yq eval -o=json '.' "$yaml_file" 2>/dev/null); then
        return 1
    fi
    
    printf '%s' "$manifest_json"
}

# Validate manifest structure and print status
manifest_validate_structure() {
    local manifest_json="$1"
    
    if ! jq -e '.resources' <<<"$manifest_json" >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if resources is empty
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    if [[ "$resource_count" == "0" ]] || [[ "$resource_count" == "null" ]]; then
        return 1
    fi
    
    return 0
}

# Extract resources from manifest JSON
manifest_extract_resources() {
    local manifest_json="$1"
    
    if ! jq -r '.resources | to_entries[] | @base64' <<<"$manifest_json" 2>/dev/null; then
        config_die "Failed to extract resources from manifest"
    fi
}

# Extract layout configuration from manifest JSON
# Returns JSON array where each element represents a tag with its resources
# If no layouts are defined, returns empty string (falls back to current behavior)
# Usage: layout=$(manifest_extract_layout "$manifest_json" "desktop")
manifest_extract_layout() {
    local manifest_json="$1"
    local layout_name="${2:-}"
    
    # Check if layouts section exists
    if ! jq -e '.layouts' <<<"$manifest_json" >/dev/null 2>&1; then
        # No layouts defined - return empty to maintain backward compatibility
        return 0
    fi
    
    # If no layout name provided, try to use default_layout
    if [[ -z $layout_name ]]; then
        layout_name=$(jq -r '.default_layout // empty' <<<"$manifest_json" 2>/dev/null)
        if [[ -z $layout_name || $layout_name == "null" ]]; then
            # No default layout - return empty to maintain backward compatibility
            return 0
        fi
    fi
    
    # Validate that the requested layout exists
    if ! jq -e --arg layout "$layout_name" '.layouts[$layout]' <<<"$manifest_json" >/dev/null 2>&1; then
        config_die "Layout '$layout_name' not found in manifest"
    fi
    
    # Extract the layout array and validate structure
    local layout_json
    if ! layout_json=$(jq -c --arg layout "$layout_name" '.layouts[$layout]' <<<"$manifest_json" 2>/dev/null); then
        config_die "Failed to extract layout '$layout_name'"
    fi
    
    # Validate that layout is an array
    if ! jq -e 'type == "array"' <<<"$layout_json" >/dev/null 2>&1; then
        config_die "Layout '$layout_name' must be an array of resource groups"
    fi
    
    # Validate row count (max 9 tags for AwesomeWM)
    local row_count
    row_count=$(jq 'length' <<<"$layout_json" 2>/dev/null)
    if [[ "$row_count" -gt 9 ]]; then
        config_die "Layout '$layout_name' has $row_count rows, but maximum is 9 (AwesomeWM tag limit)"
    fi
    
    # Validate that all referenced resources exist
    local resources_json
    resources_json=$(jq -c '.resources | keys' <<<"$manifest_json" 2>/dev/null)
    
    while IFS= read -r row_json; do
        [[ -z $row_json ]] && continue
        
        # Check each resource in the row
        while IFS= read -r resource; do
            [[ -z $resource || $resource == "null" ]] && continue
            
            if ! jq -e --arg res "$resource" '. | contains([$res])' <<<"$resources_json" >/dev/null 2>&1; then
                config_die "Layout '$layout_name' references undefined resource: '$resource'"
            fi
        done < <(jq -r '.[]' <<<"$row_json" 2>/dev/null)
    done < <(jq -c '.[]' <<<"$layout_json" 2>/dev/null)
    
    # Return the validated layout
    printf '%s' "$layout_json"
}