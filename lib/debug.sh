#!/usr/bin/env bash
# WorkOn Debug Utilities Module
# 
# This module provides debugging and logging utilities for WorkOn including:
# - Debug and verbose logging functions
# - Pre-flight system validation checks
# - Error capture and reporting utilities
# - Dry-run mode support
# - Troubleshooting helpers
#
# Functions:
#   debug_log() - Log debug messages when WORKON_DEBUG=1
#   verbose_log() - Log verbose messages when WORKON_VERBOSE=1
#   error_log() - Log error messages with context
#   debug_section() - Mark debug sections for clarity
#   debug_var() - Show variable values in debug mode
#   debug_command() - Show command execution in debug mode
#   debug_file() - Show file contents in debug mode

set -euo pipefail

# ── Debug Logging Functions ────────────────────────────────────────────────

# Log debug messages (only when WORKON_DEBUG=1)
debug_log() {
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '🐛 DEBUG: %s\n' "$*" >&2
    fi
}

# Log verbose messages (when WORKON_VERBOSE=1 or WORKON_DEBUG=1)
verbose_log() {
    if [[ "${WORKON_VERBOSE:-0}" == "1" ]] || [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '📝 %s\n' "$*" >&2
    fi
}

# Log error messages with context
error_log() {
    local context="${1:-}"
    local message="${2:-}"
    
    if [[ -n $context && -n $message ]]; then
        printf '❌ ERROR [%s]: %s\n' "$context" "$message" >&2
    else
        printf '❌ ERROR: %s\n' "$*" >&2
    fi
}

# Log warning messages
warn_log() {
    printf '⚠️  WARNING: %s\n' "$*" >&2
}

# Log success messages
success_log() {
    if [[ "${WORKON_VERBOSE:-0}" == "1" ]] || [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '✅ %s\n' "$*" >&2
    fi
}

# Mark debug sections for clarity
debug_section() {
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '\n🔍 DEBUG SECTION: %s\n' "$*" >&2
        printf '%s\n' "$(printf '─%.0s' {1..50})" >&2
    fi
}

# Show variable values in debug mode
debug_var() {
    local var_name="$1"
    local var_value="${!var_name:-<unset>}"
    
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '🔧 %s=%s\n' "$var_name" "$var_value" >&2
    fi
}

# Show command execution in debug mode
debug_command() {
    local cmd="$*"
    
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '💻 EXECUTING: %s\n' "$cmd" >&2
    fi
    
    # If dry-run mode, show command but don't execute
    if [[ "${WORKON_DRY_RUN:-0}" == "1" ]]; then
        printf '🚫 DRY-RUN: Would execute: %s\n' "$cmd" >&2
        return 0
    fi
    
    # Execute the command and capture output
    "$@"
}

# Show file contents in debug mode
debug_file() {
    local file_path="$1"
    local description="${2:-file contents}"
    
    if [[ "${WORKON_DEBUG:-0}" == "1" ]] && [[ -f "$file_path" ]]; then
        printf '📄 DEBUG: %s (%s):\n' "$description" "$file_path" >&2
        printf '%s\n' "$(printf '─%.0s' {1..40})" >&2
        cat "$file_path" >&2 || printf '(failed to read file)\n' >&2
        printf '%s\n' "$(printf '─%.0s' {1..40})" >&2
    fi
}

# ── System Validation Functions ────────────────────────────────────────────

# Check if AwesomeWM is running and accessible
debug_check_awesome() {
    debug_section "AwesomeWM Connectivity Check"
    
    # Check if awesome process is running
    if ! pgrep -x awesome >/dev/null 2>&1; then
        error_log "awesome-check" "AwesomeWM is not running"
        return 1
    fi
    success_log "AwesomeWM process is running"
    
    # Test awesome-client connectivity
    local test_result
    if test_result=$(awesome-client 'return "connectivity-test"' 2>&1); then
        # Trim whitespace from the response
        test_result=$(printf '%s' "$test_result" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$test_result" == 'string "connectivity-test"' ]]; then
            success_log "awesome-client connectivity confirmed"
            return 0
        else
            error_log "awesome-check" "awesome-client returned unexpected response: '$test_result'"
            return 1
        fi
    else
        error_log "awesome-check" "awesome-client failed: $test_result"
        return 1
    fi
}

# Check if required tools are available
debug_check_dependencies() {
    debug_section "Dependency Check"
    
    local -a required_tools=("yq" "jq" "pls-open" "awesome-client")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            success_log "Found required tool: $tool"
        else
            missing_tools+=("$tool")
            error_log "dependency-check" "Missing required tool: $tool"
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error_log "dependency-check" "Missing tools: ${missing_tools[*]}"
        return 1
    fi
    
    success_log "All required dependencies are available"
    return 0
}

# Run comprehensive pre-flight checks
debug_preflight_checks() {
    debug_section "Pre-flight System Validation"
    
    local checks_passed=0
    local total_checks=2
    
    # Check dependencies
    if debug_check_dependencies; then
        checks_passed=$((checks_passed + 1))
    fi
    
    # Check AwesomeWM
    if debug_check_awesome; then
        checks_passed=$((checks_passed + 1))
    fi
    
    if [[ $checks_passed -eq $total_checks ]]; then
        success_log "All pre-flight checks passed ($checks_passed/$total_checks)"
        return 0
    else
        error_log "preflight" "Some checks failed ($checks_passed/$total_checks passed)"
        return 1
    fi
}

# ── Error Capture and Reporting ─────────────────────────────────────────────

# Execute awesome-client with error capture
debug_awesome_client() {
    local lua_code="$1"
    local context="${2:-awesome-client}"
    
    debug_section "AwesomeWM Lua Execution"
    debug_log "Executing Lua code: $lua_code"
    
    if [[ "${WORKON_DRY_RUN:-0}" == "1" ]]; then
        printf '🚫 DRY-RUN: Would execute awesome-client with:\n%s\n' "$lua_code" >&2
        return 0
    fi
    
    local output stderr_file
    stderr_file=$(mktemp)
    
    # Execute awesome-client and capture both stdout and stderr
    if output=$(awesome-client "$lua_code" 2>"$stderr_file"); then
        debug_log "awesome-client succeeded"
        debug_log "Output: $output"
        
        # Show stderr if any (even on success, there might be warnings)
        if [[ -s "$stderr_file" ]]; then
            debug_log "Stderr output:"
            cat "$stderr_file" >&2
        fi
        
        rm -f "$stderr_file"
        printf '%s' "$output"
        return 0
    else
        local exit_code=$?
        error_log "$context" "awesome-client failed (exit code: $exit_code)"
        
        if [[ -s "$stderr_file" ]]; then
            error_log "$context" "Stderr output:"
            cat "$stderr_file" >&2
        fi
        
        rm -f "$stderr_file"
        return $exit_code
    fi
}

# ── Dry-run Support Functions ───────────────────────────────────────────────

# Check if we're in dry-run mode
is_dry_run() {
    [[ "${WORKON_DRY_RUN:-0}" == "1" ]]
}

# Execute command only if not in dry-run mode
dry_run_command() {
    if is_dry_run; then
        printf '🚫 DRY-RUN: Would execute: %s\n' "$*" >&2
        return 0
    else
        "$@"
    fi
}

# ── Troubleshooting Helpers ─────────────────────────────────────────────────

# Show environment information for debugging
debug_show_environment() {
    debug_section "Environment Information"
    
    debug_var "WORKON_DEBUG"
    debug_var "WORKON_VERBOSE" 
    debug_var "WORKON_DRY_RUN"
    debug_var "PWD"
    debug_var "USER"
    debug_var "DISPLAY"
    debug_var "XDG_CACHE_HOME"
    debug_var "XDG_DATA_HOME"
    debug_var "XDG_DATA_DIRS"
}

# Show system information for troubleshooting
debug_show_system_info() {
    debug_section "System Information"
    
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        printf '🖥️  OS: %s\n' "$(uname -a)" >&2
        printf '🪟 Display: %s\n' "${DISPLAY:-<not set>}" >&2
        printf '👤 User: %s\n' "$(whoami)" >&2
        printf '📁 Working Directory: %s\n' "$PWD" >&2
        
        # Show AwesomeWM version if available
        if command -v awesome >/dev/null 2>&1; then
            local awesome_version
            awesome_version=$(awesome --version 2>&1 | head -1 || echo "unknown")
            printf '🏗️  AwesomeWM: %s\n' "$awesome_version" >&2
        fi
    fi
}