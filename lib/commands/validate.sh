#!/usr/bin/env bash
#
# WorkOn Validate Command Module
#
# This module handles all validation-related functionality for WorkOn including:
# - YAML syntax validation
# - Manifest structure validation
# - Resource listing and analysis
# - Template variable detection and display
#
# Functions:
#   validate_syntax() - Validate YAML syntax and print status
#   validate_structure() - Validate manifest structure and content
#   validate_show_resources() - Display resources from manifest
#   validate_show_templates() - Show template variables in manifest
#   validate_show_layouts() - Display layout information and validation
#   validate_manifest() - Main validation function with complete analysis

set -euo pipefail

# Validate YAML syntax and print status
validate_syntax() {
    local manifest="$1"
    
    printf "🔍 YAML syntax: "
    if utils_parse_yaml "$manifest" >/dev/null; then
        printf "✅ Valid\n"
        return 0
    else
        printf "❌ YAML syntax error\n"
        yq eval -o=json '.' "$manifest" 2>&1 | head -5
        return 1
    fi
}

# Validate manifest structure and print status
validate_structure() {
    local manifest_json="$1"
    
    printf "🏗️  Structure: "
    
    # Check if resources section exists and is not null
    local resource_check
    resource_check=$(jq -r '.resources | if . == null then "null" elif . == false then "missing" elif length == 0 then "empty" else "valid" end' <<<"$manifest_json" 2>/dev/null)
    
    case "$resource_check" in
        "null"|"missing")
            if jq -e 'has("resources")' <<<"$manifest_json" >/dev/null 2>&1; then
                printf "❌ Invalid - No resources defined in manifest\n"
            else
                printf "❌ Invalid - missing 'resources' section\n"
            fi
            return 1
            ;;
        "empty")
            printf "❌ Invalid - No resources defined in manifest\n"
            return 1
            ;;
        "valid")
            printf "✅ Valid\n"
            return 0
            ;;
        *)
            printf "❌ Invalid - unexpected resources format\n"
            return 1
            ;;
    esac
}

# Show manifest resources
validate_show_resources() {
    local manifest_json="$1"
    local resource_count="$2"
    
    printf "📦 Resources: %s found\n" "$resource_count"
    
    # List each resource
    while IFS= read -r resource_entry; do
        local result
        if result=$(utils_parse_resource "$resource_entry"); then
            local name cmd
            IFS=$'\t' read -r name cmd <<<"$result"
            printf "  • %s: %s\n" "$name" "$cmd"
        fi
    done < <(jq -c '.resources | to_entries[]' <<<"$manifest_json" 2>/dev/null)
}

# Show template variables in manifest
validate_show_templates() {
    local manifest_json="$1"
    
    printf "\n🔧 Template variables: "
    local all_commands
    all_commands=$(jq -r '.resources | to_entries[] | .value' <<<"$manifest_json" 2>/dev/null)
    
    validate_process_template_variables "$all_commands" || printf "None found\n"
}

# Process template variables for validation display
validate_process_template_variables() {
    local all_commands="$1"
    
    # Use the template module to extract variables
    local template_vars
    template_vars=$(template_extract_variables "$all_commands")
    
    if [[ -n "$template_vars" ]]; then
        printf "Found\n"
        printf "\n"
        while IFS= read -r var; do
            # Extract variable name from {{VAR}} or {{VAR:-default}} format
            local clean_var
            clean_var=$(echo "$var" | sed 's/^{{//; s/}}$//; s/:-.*//')
            
            # Safely get environment variable value
            local env_value=""
            if [[ -n "$clean_var" ]] && [[ "$clean_var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                env_value="${!clean_var:-}"
            fi
            
            if [[ -n "$env_value" ]]; then
                printf "  ✅ %s = %s\n" "$clean_var" "$env_value"
            else
                printf "  ⚠️  %s = (undefined)\n" "$clean_var"
            fi
        done <<<"$template_vars"
        return 0  
    else
        return 1
    fi
}

# Show layout information and validation
validate_show_layouts() {
    local manifest_json="$1"
    
    # Check if layouts section exists
    if ! jq -e '.layouts' <<<"$manifest_json" >/dev/null 2>&1; then
        printf "\n🏷️  Layouts: None defined (using sequential spawning)\n"
        return 0
    fi
    
    local layout_count
    layout_count=$(jq -r '.layouts | length' <<<"$manifest_json" 2>/dev/null)
    
    printf "\n🏷️  Layouts: %s defined\n" "$layout_count"
    
    # List all layouts
    while IFS= read -r layout_entry; do
        local layout_name row_count
        layout_name=$(echo "$layout_entry" | jq -r '.key' 2>/dev/null)
        row_count=$(echo "$layout_entry" | jq -r '.value | length' 2>/dev/null)
        
        printf "  • %s: %s tag%s" "$layout_name" "$row_count" "$([ "$row_count" -ne 1 ] && echo "s" || echo "")"
        
        # Validate this layout
        local validation_result
        if validation_result=$(manifest_extract_layout "$manifest_json" "$layout_name" 2>&1); then
            printf " ✅\n"
        else
            printf " ❌\n"
            printf "    Error: %s\n" "$validation_result"
        fi
    done < <(jq -c '.layouts | to_entries[]' <<<"$manifest_json" 2>/dev/null)
    
    # Check default_layout
    local default_layout
    default_layout=$(jq -r '.default_layout // empty' <<<"$manifest_json" 2>/dev/null)
    
    if [[ -n $default_layout && $default_layout != "null" ]]; then
        printf "\n🎯 Default Layout: %s" "$default_layout"
        
        # Validate default layout exists
        if jq -e --arg layout "$default_layout" '.layouts[$layout]' <<<"$manifest_json" >/dev/null 2>&1; then
            printf " ✅\n"
        else
            printf " ❌ (layout not found)\n"
        fi
    else
        printf "\n🎯 Default Layout: None specified\n"
    fi
}

# Validate workon.yaml manifest file
validate_manifest() {
    local project_path="${1:-$PWD}"
    local manifest
    
    printf "WorkOn Manifest Validation\n"
    printf "=========================\n\n"
    
    # Find manifest file
    if ! manifest=$(manifest_find "$project_path"); then
        printf "❌ No workon.yaml found in %s or parent directories\n" "$project_path"
        return 2
    fi
    
    printf "📁 Manifest file: %s\n" "$manifest"
    
    # Validate syntax
    if ! validate_syntax "$manifest"; then
        return 1
    fi
    
    # Get JSON for further processing
    local manifest_json
    if ! manifest_json=$(utils_parse_yaml "$manifest"); then
        printf "❌ Unexpected error parsing manifest\n"
        return 1
    fi
    
    # Validate structure
    if ! validate_structure "$manifest_json"; then
        return 1
    fi
    
    # Get resource count for display
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    
    # Show resources
    validate_show_resources "$manifest_json" "$resource_count"
    
    # Show template variables
    validate_show_templates "$manifest_json"
    
    # Show layout information and validation
    validate_show_layouts "$manifest_json"
    
    printf "\n✅ Valid manifest - ready to use!\n"
    return 0
}