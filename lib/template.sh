#!/usr/bin/env bash
# WorkOn Template Processing Module
# 
# This module handles template variable processing and environment expansion including:
# - Template variable expansion with {{VAR}} and {{VAR:-default}} syntax
# - Variable extraction and analysis for debugging
# - Environment variable validation and reporting
# - Safe template processing with undefined variable handling
#
# Functions:
#   template_render() - Expand {{VAR}} and {{VAR:-default}} patterns using environment
#   template_extract_variables() - Find all template variables in text with deduplication
#   template_analyze() - Show template usage with environment values for debugging
#   template_process_variables() - Process and validate template usage (simple format)

# Expand {{VAR}} and {{VAR:-default}} templates using environment variables
template_render() {
    local input="$1"
    # Convert {{VAR}} and {{VAR:-default}} to ${VAR} and ${VAR:-default} format
    local converted
    converted=$(printf '%s' "$input" | sed -E 's/\{\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}\}/${\1\2}/g')
    # Use bash parameter expansion (temporarily disable -u for undefined vars)
    (set +u; eval "printf '%s' \"$converted\"")
}

# Extract template variables from a string
template_extract_variables() {
    local input="$1"
    # Find all {{VAR}} and {{VAR:-default}} patterns
    printf '%s' "$input" | grep -oE '\{\{[A-Za-z_][A-Za-z0-9_]*(:[-][^}]*)?\}\}' | sort | uniq || true
}

# Process template variables and show analysis
template_process_variables() {
    local text="$1"
    local template_vars
    
    template_vars=$(template_extract_variables "$text")
    
    if [[ -n $template_vars ]]; then
        printf "Found\n"
        while IFS= read -r var; do
            if [[ -n $var ]]; then
                printf "  • %s\n" "$var"
            fi
        done <<<"$template_vars"
        return 0
    else
        printf "None\n"
        return 1
    fi
}

# Show template variable analysis with environment values
template_analyze() {
    local text="$1"
    local template_vars
    
    template_vars=$(template_extract_variables "$text")
    
    if [[ -n $template_vars ]]; then
        printf "🔧 Template variables: "
        local var_count=0
        while IFS= read -r var; do
            if [[ -n $var ]]; then
                if [[ $var_count -eq 0 ]]; then
                    printf "%s" "$var"
                else
                    printf ", %s" "$var"
                fi
                var_count=$((var_count + 1))
            fi
        done <<<"$template_vars"
        printf "\n"
        
        # Show environment variable values
        printf "🌍 Environment variables:\n"
        while IFS= read -r var; do
            if [[ -n $var ]]; then
                # Extract just the variable name (without {{}} and default)
                local var_name
                var_name=$(printf '%s' "$var" | sed 's/{{//g; s/}}//g; s/:-.*//')
                local var_value="${!var_name:-<unset>}"
                printf "  • %s=%s\n" "$var_name" "$var_value"
            fi
        done <<<"$template_vars"
        return 0
    else
        printf "🔧 Template variables: None\n"
        return 1
    fi
}