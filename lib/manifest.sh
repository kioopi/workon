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