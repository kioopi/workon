#!/usr/bin/env bash
# WorkOn Path Utilities Module
# 
# This module handles path manipulation, expansion, and validation utilities including:
# - Intelligent relative path expansion to absolute paths
# - URL preservation and command flag recognition
# - Smart path detection with fallback mechanisms
# - Special pattern handling (file=@path, option=path)
# - Resource existence validation for files and commands
#
# Functions:
#   path_expand_relative() - Convert relative paths to absolute in command strings
#   path_expand_word_if_path() - Smart path detection and expansion for single words
#   path_should_expand_as_path() - Determine if a word should be treated as a path
#   path_expand_to_absolute() - Robust absolute path conversion with fallbacks
#   path_resource_exists() - Check if file or command exists with descriptive output

# Expand relative paths in a command to absolute paths
# This function identifies potential file paths and expands them to absolute paths
# - Preserves URLs (http://, https://, ftp://, etc.)
# - Preserves absolute paths (starting with /)
# - Expands relative paths to absolute paths based on current working directory
path_expand_relative() {
    local cmd="$1"
    local -a words
    
    # Use eval to let bash handle quote parsing properly
    eval "words=($cmd)"
    
    local result=""
    for word in "${words[@]}"; do
        local expanded_word
        expanded_word=$(path_expand_word_if_path "$word")
        
        # Use printf %q to properly quote the result
        result+="$(printf '%q' "$expanded_word") "
    done
    
    # Remove trailing space and output
    printf '%s' "${result% }"
}

# Helper function to expand a word if it's a path
path_expand_word_if_path() {
    local word="$1"
    
    # Skip URLs (contain :// or start with known protocols)
    if [[ $word =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// ]]; then
        printf '%s' "$word"
        return
    fi
    
    # Skip absolute paths (start with /)
    if [[ $word == /* ]]; then
        printf '%s' "$word"
        return
    fi
    
    # Skip if it looks like a command flag (starts with -)
    if [[ $word == -* ]]; then
        printf '%s' "$word"
        return
    fi
    
    # Skip if it's just a single dot (current directory)
    if [[ $word == "." ]]; then
        printf '%s' "$word"
        return
    fi
    
    # Check if it's a command in PATH first
    if command -v "$word" >/dev/null 2>&1; then
        # It's a command in PATH, don't expand it
        printf '%s' "$word"
        return
    fi
    
    # Handle special patterns like "file=@path" or "option=path"
    if [[ $word == *=@* ]]; then
        local prefix="${word%%=@*}"
        local suffix="${word#*=@}"
        if path_should_expand_as_path "$suffix"; then
            printf '%s=@%s' "$prefix" "$(path_expand_to_absolute "$suffix")"
            return
        fi
    elif [[ $word == *=* ]]; then
        local prefix="${word%%=*}"
        local suffix="${word#*=}"
        if path_should_expand_as_path "$suffix"; then
            printf '%s=%s' "$prefix" "$(path_expand_to_absolute "$suffix")"
            return
        fi
    fi
    
    # Check if word looks like a relative path
    if path_should_expand_as_path "$word"; then
        # Convert to absolute path
        path_expand_to_absolute "$word"
        return
    fi
    
    # Not a path, keep as-is
    printf '%s' "$word"
}

# Helper function to determine if a word should be expanded as a path
path_should_expand_as_path() {
    local word="$1"
    
    # Expand if contains / (subdirectory) or if file/directory exists
    [[ $word == */* ]] || [[ -e $word ]]
}

# Helper function to expand a path to absolute, with fallback for portability
path_expand_to_absolute() {
    local path="$1"
    
    if [[ -e "$path" ]]; then
        # File exists, use realpath
        realpath "$path"
    else
        # File doesn't exist, try realpath with --canonicalize-missing first
        if realpath --canonicalize-missing "$path" 2>/dev/null; then
            return 0
        elif readlink -f "$path" 2>/dev/null; then
            # Fallback to readlink -f if available
            return 0
        else
            # Neither available, construct manually
            printf '%s/%s' "$PWD" "$path"
        fi
    fi
}

# Check if a file or command exists
path_resource_exists() {
    local path="$1"
    
    # Check if it's a URL first (any protocol followed by ://)
    if [[ "$path" == *://* ]]; then
        printf "Yes (URL)"
        return 0
    fi
    
    # Check if it's a file
    if [[ -f "$path" ]]; then
        printf "Yes (file)"
        return 0
    fi
    
    # Check if it's a command (first word)
    local first_word
    first_word=$(printf '%s' "$path" | awk '{print $1}')
    if command -v "$first_word" >/dev/null 2>&1; then
        printf "Yes (command)"
        return 0
    fi
    
    # Check if first word is a desktop application ID
    # Desktop IDs typically follow reverse domain notation: com.example.App, dev.zed.Zed, org.gnome.gedit
    if [[ "$first_word" =~ ^[a-zA-Z0-9._-]+$ ]] && [[ "$first_word" == *.*.* ]] && [[ "$first_word" != */* ]]; then
        # Use pls-open --dry-run to check if desktop application can be resolved
        if pls-open --dry-run "$first_word" >/dev/null 2>&1; then
            printf "Yes (desktop app)"
            return 0
        fi
    fi
    
    printf "No"
    return 1
}