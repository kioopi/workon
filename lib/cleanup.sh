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

# Set up stop debug logging
cleanup_debug_log() {
    local message="$1"
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        local stop_debug_file="/tmp/workon-stop-debug.log"
        echo "$(date '+%H:%M:%S') $message" >> "$stop_debug_file"
    fi
}

# ── Core Cleanup Functions ─────────────────────────────────────────────────

# Strategy 1: Stop by PID with graceful termination
cleanup_stop_by_pid() {
    local pid="$1"
    local name="$2"
    
    cleanup_debug_log "cleanup_stop_by_pid: Attempting to stop $name (PID: $pid)"
    
    if [[ -n $pid && $pid != "0" ]] && kill -0 "$pid" 2>/dev/null; then
        verbose_log "Using PID $pid for cleanup of $name"
        cleanup_debug_log "Process $pid is running, sending TERM signal"
        
        if kill -TERM "$pid" 2>/dev/null; then
            cleanup_debug_log "TERM signal sent to $pid, waiting 1 second"
            sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                warn_log "Process $pid still running, force killing"
                kill -KILL "$pid" 2>/dev/null || true
                cleanup_debug_log "KILL signal sent to $pid"
            else
                cleanup_debug_log "Process $pid terminated gracefully"
            fi
            return 0
        else
            cleanup_debug_log "Failed to send TERM signal to $pid"
        fi
    else
        cleanup_debug_log "Process $pid not running or invalid PID"
    fi
    return 1
}

# Strategy 2: Stop by xdotool window management
cleanup_stop_by_xdotool() {
    local pid="$1"
    local class="$2"
    local instance="$3"
    local entry="$4"
    
    cleanup_debug_log "cleanup_stop_by_xdotool: Attempting window cleanup for PID=$pid, class=$class, instance=$instance"
    
    if ! command -v xdotool >/dev/null 2>&1; then
        cleanup_debug_log "xdotool not available, skipping window-based cleanup"
        return 1
    fi
    
    verbose_log "Trying window-based cleanup with xdotool"
    
    # Try using PID to find windows
    if [[ -n $pid && $pid != "0" ]]; then
        cleanup_debug_log "Searching for windows with PID $pid"
        local window_ids
        if window_ids=$(xdotool search --pid "$pid" 2>/dev/null) && [[ -n $window_ids ]]; then
            cleanup_debug_log "Found windows for PID $pid: $window_ids"
            if xdotool search --pid "$pid" windowclose 2>/dev/null; then
                success_log "Closed windows for PID $pid"
                return 0
            else
                cleanup_debug_log "Failed to close windows for PID $pid"
            fi
        else
            cleanup_debug_log "No windows found for PID $pid"
        fi
    fi
    
    # Try using specific window ID if available (safer than class-based search)
    local window_id
    window_id=$(printf '%s' "$entry" | jq -r '.window_id // empty' 2>/dev/null)
    if [[ -n $window_id ]]; then
        cleanup_debug_log "Attempting to close specific window ID: $window_id"
        if xdotool windowclose "$window_id" 2>/dev/null; then
            success_log "Closed specific window ID: $window_id"
            cleanup_debug_log "Successfully closed window ID: $window_id"
            return 0
        else
            cleanup_debug_log "Failed to close window ID: $window_id"
        fi
    fi
    
    # Try using window class only as fallback (but avoid broad searches)
    if [[ -n $class ]]; then
        cleanup_debug_log "Searching for windows with class '$class' (fallback only)"
        # Don't use broad class search - too dangerous for terminals
        cleanup_debug_log "Skipping class-based search for '$class' to prevent closing unrelated windows"
    fi
    
    # Skip instance-based search - also too broad and dangerous for terminals
    if [[ -n $instance ]]; then
        cleanup_debug_log "Skipping instance-based search for '$instance' - too broad, could close unrelated windows"
    fi
    
    return 1
}

# Strategy 3: Stop by wmctrl fallback
cleanup_stop_by_wmctrl() {
    local class="$1"
    
    cleanup_debug_log "cleanup_stop_by_wmctrl: Attempting wmctrl fallback for class='$class'"
    
    if ! command -v wmctrl >/dev/null 2>&1; then
        cleanup_debug_log "wmctrl not available, skipping wmctrl fallback"
        return 1
    fi
    
    verbose_log "Trying wmctrl fallback"
    cleanup_debug_log "wmctrl is available, proceeding with fallback"
    
    # List all windows for debugging
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        local window_list
        if window_list=$(wmctrl -l 2>/dev/null); then
            cleanup_debug_log "Current windows via wmctrl:"
            cleanup_debug_log "$window_list"
        fi
    fi
    
    # Try to close windows by class name (but skip dangerous ones)
    if [[ -n $class ]]; then
        # Skip terminal classes that could close unrelated windows
        if [[ "$class" == "Alacritty" || "$class" == "kitty" || "$class" == "xterm" || "$class" == "gnome-terminal" ]]; then
            cleanup_debug_log "Skipping wmctrl cleanup for terminal class '$class' - too dangerous"
        else
            cleanup_debug_log "Attempting to close windows with class '$class'"
            if wmctrl -c "$class" 2>/dev/null; then
                success_log "Closed window with wmctrl (class: $class)"
                cleanup_debug_log "Successfully closed windows with class '$class'"
                return 0
            else
                cleanup_debug_log "Failed to close windows with class '$class'"
            fi
        fi
    else
        cleanup_debug_log "No class provided for wmctrl cleanup"
    fi
    
    return 1
}

# Multi-strategy cleanup for a single resource
cleanup_stop_resource() {
    local entry="$1"
    local pid class instance name cmd tracking_method
    
    cleanup_debug_log "cleanup_stop_resource: Processing entry: $entry"
    
    # Extract metadata from session entry
    pid=$(printf '%s' "$entry" | jq -r '.pid // empty' 2>/dev/null)
    class=$(printf '%s' "$entry" | jq -r '.class // empty' 2>/dev/null)
    instance=$(printf '%s' "$entry" | jq -r '.instance // empty' 2>/dev/null)
    name=$(printf '%s' "$entry" | jq -r '.name // empty' 2>/dev/null)
    cmd=$(printf '%s' "$entry" | jq -r '.cmd // empty' 2>/dev/null)
    tracking_method=$(printf '%s' "$entry" | jq -r '.tracking_method // empty' 2>/dev/null)
    
    cleanup_debug_log "Extracted metadata: name='$name', pid='$pid', class='$class', instance='$instance', cmd='$cmd', tracking='$tracking_method'"
    
    verbose_log 'Stopping %s (PID: %s)\n' "${name:-unknown}" "${pid:-unknown}" >&2
    
    # Try cleanup strategies in order
    cleanup_debug_log "Attempting cleanup strategy 1: PID-based cleanup"
    if cleanup_stop_by_pid "$pid" "$name"; then
        cleanup_debug_log "SUCCESS: PID-based cleanup succeeded for $name"
        return 0
    fi
    
    cleanup_debug_log "PID-based cleanup failed, attempting strategy 2: xdotool cleanup"
    if cleanup_stop_by_xdotool "$pid" "$class" "$instance" "$entry"; then
        cleanup_debug_log "SUCCESS: xdotool cleanup succeeded for $name"
        return 0
    fi
    
    cleanup_debug_log "xdotool cleanup failed, attempting strategy 3: wmctrl cleanup"
    if cleanup_stop_by_wmctrl "$class"; then
        cleanup_debug_log "SUCCESS: wmctrl cleanup succeeded for $name"
        return 0
    fi
    
    cleanup_debug_log "ALL cleanup strategies failed for $name"
    warn_log "Could not stop ${name:-unknown} (no reliable method found)"
    return 1
}

# Complete session teardown
cleanup_stop_session() {
    local session_file="$1"
    local session_data
    
    cleanup_debug_log "cleanup_stop_session: Starting session teardown for file: $session_file"
    
    # Check if debug mode is enabled
    if [[ "${WORKON_DEBUG:-0}" == "1" ]]; then
        cleanup_debug_log "=== STOP SESSION DEBUG START ==="
        cleanup_debug_log "Session file path: $session_file"
        if [[ -f "$session_file" ]]; then
            cleanup_debug_log "Session file exists, size: $(wc -c < "$session_file") bytes"
            cleanup_debug_log "Session file contents:"
            cleanup_debug_log "$(cat "$session_file")"
        else
            cleanup_debug_log "Session file does not exist"
        fi
    fi
    
    # Read and validate session file
    if ! session_data=$(session_read "$session_file"); then
        cleanup_debug_log "Failed to read session data from $session_file"
        warn_log "No valid session data found"
        return 1
    fi
    
    cleanup_debug_log "Successfully read session data, length: ${#session_data} characters"
    
    # Parse session entries
    local entries
    mapfile -t entries < <(printf '%s' "$session_data" | jq -c '.[]' 2>/dev/null)
    
    cleanup_debug_log "Parsed ${#entries[@]} session entries"
    
    if [[ ${#entries[@]} -eq 0 ]]; then
        cleanup_debug_log "No entries found in session data"
        printf 'No resources found in session\n' >&2
    else
        cleanup_debug_log "Processing ${#entries[@]} resources for cleanup"
        printf 'Stopping %d resources...\n' "${#entries[@]}" >&2
        
        local success_count=0
        
        # Stop each resource using multiple strategies
        for i in "${!entries[@]}"; do
            local entry="${entries[$i]}"
            cleanup_debug_log "Processing entry $((i+1))/${#entries[@]}: $entry"
            
            if cleanup_stop_resource "$entry"; then
                success_count=$((success_count + 1))
                cleanup_debug_log "Resource $((i+1)) stopped successfully"
            else
                cleanup_debug_log "Resource $((i+1)) failed to stop"
            fi
        done
        
        cleanup_debug_log "Cleanup complete: $success_count/${#entries[@]} resources stopped successfully"
        printf 'Successfully stopped %d/%d resources\n' "$success_count" "${#entries[@]}" >&2
    fi
    
    # Clean up session file and lock
    cleanup_debug_log "Removing session file and lock: $session_file"
    rm -f "$session_file" "${session_file}.lock"
    cleanup_debug_log "Session cleanup completed"
    
    return 0
}

# ── Legacy Function Aliases ────────────────────────────────────────────────
# These maintain backward compatibility with existing code

stop_by_pid() { cleanup_stop_by_pid "$@"; }
stop_by_xdotool() { cleanup_stop_by_xdotool "$@"; }
stop_by_wmctrl() { cleanup_stop_by_wmctrl "$@"; }
stop_resource() { cleanup_stop_resource "$@"; }
stop_session_impl() { cleanup_stop_session "$@"; }
