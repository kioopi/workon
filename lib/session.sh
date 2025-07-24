#!/usr/bin/env bash
# WorkOn Session Management Module
# 
# This module handles all session-related functionality including:
# - Session file reading and validation
# - Atomic session file writing
# - File locking for concurrent access
# - Session data retrieval and validation
#
# Functions:
#   session_read() - Validate and read session file with JSON validation
#   session_write_atomic() - Write session file atomically to prevent corruption
#   session_with_lock() - Execute command with file lock protection
#   session_get_valid_data() - Get valid session data with error handling

set -euo pipefail

# Source required modules
# shellcheck source=lib/config.sh
source "${BASH_SOURCE[0]%/*}/config.sh"

# ── Core Session Functions ─────────────────────────────────────────────────

# Validate and read session file
session_read() {
    local session_file="$1"
    
    if [[ ! -f $session_file ]]; then
        return 1
    fi
    
    # Validate JSON format
    if ! jq -e 'type == "array"' "$session_file" >/dev/null 2>&1; then
        printf 'Warning: Corrupted session file, removing: %s\n' "$session_file" >&2
        rm -f "$session_file"
        return 1
    fi
    
    cat "$session_file"
}

# Write session file atomically to prevent corruption
session_write_atomic() {
    local session_file="$1"
    local data="$2"
    
    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$session_file")
    if ! mkdir -p "$parent_dir" 2>/dev/null; then
        printf 'workon session: Cannot create session directory: %s\n' "$parent_dir" >&2
        return 1
    fi
    
    # Write to temporary file first, then move atomically
    local temp_file="${session_file}.tmp.$$"
    
    if ! printf '%s' "$data" > "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        printf 'workon session: Cannot write session file: %s\n' "$session_file" >&2
        return 1
    fi
    
    # Atomic move
    if ! mv "$temp_file" "$session_file" 2>/dev/null; then
        rm -f "$temp_file"
        printf 'workon session: Cannot move session file: %s\n' "$session_file" >&2
        return 1
    fi
    
    return 0
}

# Execute command with file lock protection
session_with_lock() {
    local lock_file="$1"
    shift
    local cache_dir_path
    cache_dir_path=$(dirname "$lock_file")

    # Ensure cache directory exists
    mkdir -p "$cache_dir_path" || config_die "Cannot create cache directory: $cache_dir_path"
    
    # Use flock with file descriptor 200
    {
        flock -n 200 || config_die "Session file busy (another workon process may be running)"
        "$@"
    } 200>"${lock_file}.lock"
}

# Get valid session data with error handling
session_get_valid_data() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        return 1
    fi
    
    local session_data
    if ! session_data=$(session_read "$session_file"); then
        return 1
    fi
    
    printf '%s' "$session_data"
}

# ── Legacy Function Aliases ────────────────────────────────────────────────
# These maintain backward compatibility with existing code

read_session() { session_read "$@"; }
with_lock() { session_with_lock "$@"; }
get_valid_session_data() { session_get_valid_data "$@"; }