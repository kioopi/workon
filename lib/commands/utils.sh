#!/usr/bin/env bash
#
# WorkOn Command Utilities Module
#
# This module provides shared utility functions used by multiple command modules:
# - YAML parsing utilities
# - Resource entry parsing
# - Dependency checking
#
# Functions:
#   utils_parse_yaml() - Parse YAML to JSON using yq
#   utils_parse_resource() - Parse a single resource entry from JSON
#   utils_check_dependency() - Check if a single dependency is available

set -euo pipefail

# Parse YAML to JSON using yq
utils_parse_yaml() {
    local yaml_file="$1"
    yq eval -o=json '.' "$yaml_file" 2>/dev/null
}

# Parse a single resource entry from JSON format
utils_parse_resource() {
    local resource_entry="$1"
    local name cmd
    
    if ! name=$(jq -r '.key' <<<"$resource_entry" 2>/dev/null); then
        return 1
    fi
    
    if ! cmd=$(jq -r '.value' <<<"$resource_entry" 2>/dev/null); then
        return 1
    fi
    
    printf '%s\t%s' "$name" "$cmd"
}

# Check if a single dependency is available
utils_check_dependency() {
    local cmd="$1"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "✅ available"
    else
        printf "❌ missing"
    fi
}