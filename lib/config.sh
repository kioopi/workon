#!/usr/bin/env bash
# WorkOn Configuration Management Module
# 
# This module handles all configuration-related functionality including:
# - Project directory discovery and caching
# - Environment variable processing  
# - Dependency validation
# - XDG Base Directory specification compliance
#
# Functions:
#   config_load_project_dirs() - Load project search paths from config or env
#   config_cache_dir() - Get XDG-compliant cache directory
#   config_cache_file() - Generate session file path for project
#   config_check_dependencies() - Validate required system dependencies
#   config_die() - Print error message and exit with code 2

# Print error message and exit with code 2
config_die() {
    printf 'workon: %s\n' "$*" >&2
    exit 2
}

# Config cache variables for performance
declare -g _WORKON_CONFIG_CACHE=""
declare -g _WORKON_CONFIG_MTIME=""

# Load project search directories from environment or config file
config_load_project_dirs() {
    # First check environment variable
    if [[ -n ${WORKON_PROJECTS_PATH:-} ]]; then
        printf '%s' "$WORKON_PROJECTS_PATH" | tr ':' '\n'
        return 0
    fi

    # Check config file
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}/workon/config.yaml"
    if [[ -f $cfg ]]; then
        # Check if config file is readable
        if [[ ! -r $cfg ]]; then
            config_die "Configuration file is not readable: $cfg"
        fi
        
        # Check cache validity
        local current_mtime
        current_mtime=$(stat -c %Y "$cfg" 2>/dev/null) || current_mtime=0
        
        if [[ -n $_WORKON_CONFIG_CACHE && $_WORKON_CONFIG_MTIME == "$current_mtime" ]]; then
            printf '%s' "$_WORKON_CONFIG_CACHE"
            return 0
        fi
        
        local yq_output
        if ! yq_output=$(yq eval -o=json '.projects_path' "$cfg" 2>&1); then
            config_die "Failed to parse configuration file: $cfg (invalid YAML syntax)"
        fi
        
        # Check if projects_path exists and is an array
        if [[ $yq_output == "null" ]]; then
            # No projects_path configured, cache empty result
            _WORKON_CONFIG_CACHE=""
            _WORKON_CONFIG_MTIME="$current_mtime"
            return 0
        fi
        
        local jq_output
        if ! jq_output=$(printf '%s' "$yq_output" | jq -r '.[]' 2>&1); then
            config_die "Invalid projects_path format in config file: $cfg (must be an array of strings)"
        fi
        
        # Cache the result
        _WORKON_CONFIG_CACHE="$jq_output"
        _WORKON_CONFIG_MTIME="$current_mtime"
        
        printf '%s' "$jq_output"
    fi
}

# Get the cache directory following XDG spec
config_cache_dir() {
    printf '%s/workon' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Generate session file path for a project directory
config_cache_file() {
    local project_root
    project_root=$(realpath "${1:-$PWD}")
    local sha1
    sha1=$(printf '%s' "$project_root" | sha1sum | cut -d' ' -f1)
    printf '%s/%s.json' "$(config_cache_dir)" "$sha1"
}

# Check dependencies are available
config_check_dependencies() {
    local missing=()
    
    command -v yq >/dev/null || missing+=(yq)
    command -v jq >/dev/null || missing+=(jq)
    command -v awesome-client >/dev/null || missing+=(awesome-client)
    command -v realpath >/dev/null || missing+=(realpath)
    command -v sha1sum >/dev/null || missing+=(sha1sum)
    command -v flock >/dev/null || missing+=(flock)
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        config_die "Missing required dependencies: ${missing[*]}"
    fi
}