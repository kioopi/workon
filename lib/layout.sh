#!/usr/bin/env bash
# WorkOn Layout Utilities Module
# 
# This module provides reusable layout utility functions for manifest processing:
# - Layout existence checking and validation
# - Default layout extraction and resolution
# - Layout structure validation
# - Configuration constants and limits
#
# Functions:
#   layout_exists() - Check if layouts section exists in manifest
#   layout_get_default() - Extract default_layout from manifest
#   layout_validate_exists() - Validate specific layout exists
#   layout_get_tag_limit() - Get maximum tag count for AwesomeWM
#   layout_has_valid_structure() - Check if layout is a valid array
#   layout_get_row_count() - Get number of rows in a layout

set -euo pipefail

# ── Constants ───────────────────────────────────────────────────────────────

# Maximum number of tags supported by AwesomeWM
# Using conditional assignment to avoid readonly conflicts in tests
if [[ -z "${LAYOUT_MAX_TAGS:-}" ]]; then
    declare -r LAYOUT_MAX_TAGS=9
fi

# ── Layout Existence Functions ─────────────────────────────────────────────

# Check if layouts section exists in manifest JSON
layout_exists() {
    local manifest_json="$1"
    
    jq -e '.layouts' <<<"$manifest_json" >/dev/null 2>&1
}

# Extract default_layout from manifest JSON
# Returns empty string if no default_layout is specified
layout_get_default() {
    local manifest_json="$1"
    
    local default_layout
    default_layout=$(jq -r '.default_layout // empty' <<<"$manifest_json" 2>/dev/null)
    
    if [[ -z $default_layout || $default_layout == "null" ]]; then
        return 1  # No default layout
    fi
    
    printf '%s' "$default_layout"
}

# Validate that a specific layout exists in the manifest
layout_validate_exists() {
    local manifest_json="$1"
    local layout_name="$2"
    
    jq -e --arg layout "$layout_name" '.layouts[$layout]' <<<"$manifest_json" >/dev/null 2>&1
}

# ── Layout Structure Functions ─────────────────────────────────────────────

# Get maximum tag count limit
layout_get_tag_limit() {
    printf '%d' "${LAYOUT_MAX_TAGS:-9}"
}

# Check if layout has valid array structure
layout_has_valid_structure() {
    local layout_json="$1"
    
    jq -e 'type == "array"' <<<"$layout_json" >/dev/null 2>&1
}

# Get number of rows in a layout
layout_get_row_count() {
    local layout_json="$1"
    
    jq -r 'length' <<<"$layout_json" 2>/dev/null
}

# ── Layout Extraction Functions ────────────────────────────────────────────

# Extract layout JSON by name from manifest
layout_extract_by_name() {
    local manifest_json="$1"
    local layout_name="$2"
    
    jq -c --arg layout "$layout_name" '.layouts[$layout]' <<<"$manifest_json" 2>/dev/null
}

# Get all layout names from manifest
layout_get_all_names() {
    local manifest_json="$1"
    
    if ! layout_exists "$manifest_json"; then
        return 1
    fi
    
    jq -r '.layouts | keys[]' <<<"$manifest_json" 2>/dev/null
}

# Get layout count from manifest
layout_get_count() {
    local manifest_json="$1"
    
    if ! layout_exists "$manifest_json"; then
        printf '0'
        return 0
    fi
    
    jq -r '.layouts | length' <<<"$manifest_json" 2>/dev/null
}

# ── Resource Validation Functions ──────────────────────────────────────────

# Validate that layout references only existing resources
layout_validate_resource_references() {
    local manifest_json="$1"
    local layout_json="$2"
    local layout_name="$3"
    
    local resources_json
    resources_json=$(jq -c '.resources | keys' <<<"$manifest_json" 2>/dev/null)
    
    while IFS= read -r row_json; do
        [[ -z $row_json ]] && continue
        
        # Check each resource in the row
        while IFS= read -r resource; do
            [[ -z $resource || $resource == "null" ]] && continue
            
            if ! jq -e --arg res "$resource" '. | contains([$res])' <<<"$resources_json" >/dev/null 2>&1; then
                printf "Layout '%s' references undefined resource: '%s'" "$layout_name" "$resource"
                return 1
            fi
        done < <(jq -r '.[]' <<<"$row_json" 2>/dev/null)
    done < <(jq -c '.[]' <<<"$layout_json" 2>/dev/null)
    
    return 0
}

# ── Validation Convenience Functions ───────────────────────────────────────

# Comprehensive layout validation
# Returns 0 if valid, 1 if invalid (with error message on stdout)
layout_validate_comprehensive() {
    local manifest_json="$1"
    local layout_name="$2"
    
    # Check if layout exists
    if ! layout_validate_exists "$manifest_json" "$layout_name"; then
        printf "Layout '%s' not found in manifest" "$layout_name"
        return 1
    fi
    
    # Extract layout
    local layout_json
    if ! layout_json=$(layout_extract_by_name "$manifest_json" "$layout_name"); then
        printf "Failed to extract layout '%s'" "$layout_name"
        return 1
    fi
    
    # Validate structure
    if ! layout_has_valid_structure "$layout_json"; then
        printf "Layout '%s' must be an array of resource groups" "$layout_name"
        return 1
    fi
    
    # Validate row count
    local row_count max_tags
    row_count=$(layout_get_row_count "$layout_json")
    max_tags=$(layout_get_tag_limit)
    if [[ "$row_count" -gt "$max_tags" ]]; then
        printf "Layout '%s' has %s rows, but maximum is %d (AwesomeWM tag limit)" "$layout_name" "$row_count" "$max_tags"
        return 1
    fi
    
    # Validate resource references
    local validation_error
    if ! validation_error=$(layout_validate_resource_references "$manifest_json" "$layout_json" "$layout_name"); then
        printf '%s' "$validation_error"
        return 1
    fi
    
    return 0
}