#!/usr/bin/env bash
# WorkOn Resource Cleanup Module
# 
# This module handles multi-strategy resource cleanup and session teardown:
# - PID-based process termination with graceful and force killing
# - Window-based cleanup using xdotool for GUI applications
# - Fallback window management using wmctrl
# - Complete session teardown with comprehensive error handling
#
# Functions:
#   cleanup_stop_by_pid() - Terminate process by PID (TERM then KILL)
#   cleanup_stop_by_xdotool() - Close windows using xdotool by PID/class/instance
#   cleanup_stop_by_wmctrl() - Fallback window closure using wmctrl
#   cleanup_stop_resource() - Multi-strategy cleanup for single resource
#   cleanup_stop_session() - Complete session teardown with all resources

set -euo pipefail

# Source required modules
# shellcheck source=lib/config.sh
source "${BASH_SOURCE[0]%/*}/config.sh"
# shellcheck source=lib/session.sh
source "${BASH_SOURCE[0]%/*}/session.sh"

# ── Core Cleanup Functions ─────────────────────────────────────────────────

# Strategy 1: Stop by PID with graceful termination
cleanup_stop_by_pid() {
    local pid="$1"
    local name="$2"
    
    if [[ -n $pid && $pid != "0" ]] && kill -0 "$pid" 2>/dev/null; then
        printf '  Using PID %s for cleanup\n' "$pid" >&2
        if kill -TERM "$pid" 2>/dev/null; then
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                printf '  Force killing PID %s\n' "$pid" >&2
                kill -KILL "$pid" 2>/dev/null || true
            fi
            return 0
        fi
    fi
    return 1
}

# Strategy 2: Stop by xdotool window management
cleanup_stop_by_xdotool() {
    local pid="$1"
    local class="$2"
    local instance="$3"
    
    if ! command -v xdotool >/dev/null 2>&1; then
        return 1
    fi
    
    printf '  Trying window-based cleanup with xdotool\n' >&2
    
    # Try using PID to find windows
    if [[ -n $pid && $pid != "0" ]]; then
        if xdotool search --pid "$pid" windowclose 2>/dev/null; then
            printf '  Closed windows for PID %s\n' "$pid" >&2
            return 0
        fi
    fi
    
    # Try using window class
    if [[ -n $class ]]; then
        if xdotool search --class "$class" windowclose 2>/dev/null; then
            printf '  Closed windows with class "%s"\n' "$class" >&2
            return 0
        fi
    fi
    
    # Try using window instance
    if [[ -n $instance ]]; then
        if xdotool search --classname "$instance" windowclose 2>/dev/null; then
            printf '  Closed windows with instance "%s"\n' "$instance" >&2
            return 0
        fi
    fi
    
    return 1
}

# Strategy 3: Stop by wmctrl fallback
cleanup_stop_by_wmctrl() {
    local class="$1"
    
    if ! command -v wmctrl >/dev/null 2>&1; then
        return 1
    fi
    
    printf '  Trying wmctrl fallback\n' >&2
    
    # Try to close windows by class name
    if [[ -n $class ]]; then
        if wmctrl -c "$class" 2>/dev/null; then
            printf '  Closed window with wmctrl (class: %s)\n' "$class" >&2
            return 0
        fi
    fi
    
    return 1
}

# Multi-strategy cleanup for a single resource
cleanup_stop_resource() {
    local entry="$1"
    local pid class instance name
    
    # Extract metadata from session entry
    pid=$(printf '%s' "$entry" | jq -r '.pid // empty' 2>/dev/null)
    class=$(printf '%s' "$entry" | jq -r '.class // empty' 2>/dev/null)
    instance=$(printf '%s' "$entry" | jq -r '.instance // empty' 2>/dev/null)
    name=$(printf '%s' "$entry" | jq -r '.name // empty' 2>/dev/null)
    
    printf 'Stopping %s (PID: %s)\n' "${name:-unknown}" "${pid:-unknown}" >&2
    
    # Try cleanup strategies in order
    if cleanup_stop_by_pid "$pid" "$name"; then
        return 0
    fi
    
    if cleanup_stop_by_xdotool "$pid" "$class" "$instance"; then
        return 0
    fi
    
    if cleanup_stop_by_wmctrl "$class"; then
        return 0
    fi
    
    printf '  Warning: Could not stop %s (no reliable method found)\n' "${name:-unknown}" >&2
    return 1
}

# Complete session teardown
cleanup_stop_session() {
    local session_file="$1"
    local session_data
    
    # Read and validate session file
    if ! session_data=$(session_read "$session_file"); then
        printf 'Warning: No valid session data found\n' >&2
        return 1
    fi
    
    # Parse session entries
    local entries
    mapfile -t entries < <(printf '%s' "$session_data" | jq -c '.[]' 2>/dev/null)
    
    if [[ ${#entries[@]} -eq 0 ]]; then
        printf 'No resources found in session\n' >&2
    else
        printf 'Stopping %d resources...\n' "${#entries[@]}" >&2
        
        local success_count=0
        
        # Stop each resource using multiple strategies
        for entry in "${entries[@]}"; do
            if cleanup_stop_resource "$entry"; then
                success_count=$((success_count + 1))
            fi
        done
        
        printf 'Successfully stopped %d/%d resources\n' "$success_count" "${#entries[@]}" >&2
    fi
    
    # Clean up session file and lock
    rm -f "$session_file" "${session_file}.lock"
    
    return 0
}

# ── Legacy Function Aliases ────────────────────────────────────────────────
# These maintain backward compatibility with existing code

stop_by_pid() { cleanup_stop_by_pid "$@"; }
stop_by_xdotool() { cleanup_stop_by_xdotool "$@"; }
stop_by_wmctrl() { cleanup_stop_by_wmctrl "$@"; }
stop_resource() { cleanup_stop_resource "$@"; }
stop_session_impl() { cleanup_stop_session "$@"; }