#!/usr/bin/env bash
# WorkOn Library Functions
# Shared functions for workon CLI tool

# Source modular components
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/config.sh disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib/manifest.sh disable=SC1091
source "$SCRIPT_DIR/manifest.sh"

# Backward compatibility aliases for config functions
die() { config_die "$@"; }

load_project_dirs() { config_load_project_dirs "$@"; }
find_manifest() { manifest_find "$@"; }

# Expand {{VAR}} and {{VAR:-default}} templates using environment variables
render_template() {
    local input="$1"
    # Convert {{VAR}} and {{VAR:-default}} to ${VAR} and ${VAR:-default} format
    local converted
    converted=$(printf '%s' "$input" | sed -E 's/\{\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}\}/${\1\2}/g')
    # Use bash parameter expansion (temporarily disable -u for undefined vars)
    (set +u; eval "printf '%s' \"$converted\"")
}

# Launch a resource via awesome-client with proper escaping
launch_resource() {
    local name="$1"
    local command="$2"
    
    # Escape for awesome-client
    local escaped_cmd
    escaped_cmd=$(printf '%s' "pls-open $command" | sed 's/"/\\"/g; s/\\/\\\\/g')
    
    printf '  %s: %s\n' "$name" "$command" >&2

    # Spawn via awesome-client
    awesome-client "require(\"awful.spawn\").spawn(\"$escaped_cmd\")" >/dev/null 2>&1 &
    local spawn_pid=$!
    
    # Give the process a moment to start
    sleep 0.1
    
    # Check if the process is still running
    if ! kill -0 "$spawn_pid" 2>/dev/null; then
        printf 'Warning: Failed to spawn %s\n' "$name" >&2
        return 1
    fi
    
    return 0
}

# Launch all resources using single Lua script execution
launch_all_resources_with_session() {
    local session_file="$1"
    local resources="$2"  # Base64-encoded resource entries
    
    # Prepare resources array for JSON
    local resources_json="[]"
    
    printf 'Preparing resources for spawning:\n' >&2
    
    while read -r entry; do
        if [[ -z $entry ]]; then
            continue
        fi
        
        local name raw_cmd rendered_cmd
        name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
        raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue

        # Render template variables
        rendered_cmd=$(render_template "$raw_cmd")
        
        # Expand relative paths to absolute paths
        expanded_cmd=$(expand_relative_paths "$rendered_cmd")
        
        printf '  %s: %s\n' "$name" "$expanded_cmd" >&2
        
        # Add to resources JSON array
        local resource_entry
        resource_entry=$(jq -n \
            --arg name "$name" \
            --arg cmd "pls-open $expanded_cmd" \
            '{name: $name, cmd: $cmd}')
        
        resources_json=$(printf '%s' "$resources_json" | jq ". + [$resource_entry]")
        
    done <<<"$resources"
    
    # Check if we have any resources to spawn
    local resource_count
    resource_count=$(printf '%s' "$resources_json" | jq 'length')
    
    if [[ $resource_count -eq 0 ]]; then
        printf 'No resources to spawn\n' >&2
        return 1
    fi
    
    printf 'Spawning %d resources via single Lua script...\n' "$resource_count" >&2
    
    # Prepare configuration for Lua script
    local spawn_config
    spawn_config=$(jq -n \
        --arg session_file "$session_file" \
        --argjson resources "$resources_json" \
        '{session_file: $session_file, resources: $resources}')
    
    # Execute the spawn script with configuration embedded directly in Lua
    # Set the environment variables as global Lua variables since env vars may not pass through
    printf 'Executing awesome-client with embedded configuration\n' >&2
    
    # Escape the JSON for Lua string literal
    local escaped_config
    escaped_config=$(printf '%s' "$spawn_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    
    awesome-client "
        WORKON_DIR = '$WORKON_DIR'
        WORKON_SPAWN_CONFIG = '$escaped_config'
        dofile('$WORKON_DIR/lib/spawn_resources.lua')
    "
    
    # Wait for session file to be created/updated
    local timeout=15
    local initial_count=0
    
    if [[ -f "$session_file" ]]; then
        initial_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
    fi
    
    while [[ $timeout -gt 0 ]]; do
        if [[ -f "$session_file" ]]; then
            local current_count
            current_count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
            
            # Check if we have new entries (allowing for partial success)
            if [[ $current_count -gt $initial_count ]]; then
                printf 'Session file updated with %d entries\n' "$current_count" >&2
                return 0
            fi
        fi
        
        sleep 0.5
        timeout=$((timeout - 1))
    done
    
    printf 'Warning: Session file not updated within timeout\n' >&2
    return 1
}

# Legacy functions removed - session entries are now created by Lua script

parse_manifest() { manifest_parse "$@"; }

extract_resources() { manifest_extract_resources "$@"; }

# ─── Session Management Functions ───────────────────────────────────────────

cache_dir() { config_cache_dir; }
cache_file() { config_cache_file "$@"; }

# Execute command with file lock protection
with_lock() {
    local lock_file="$1"
    shift
    local cache_dir_path
    cache_dir_path=$(dirname "$lock_file")

    # Ensure cache directory exists
    mkdir -p "$cache_dir_path" || die "Cannot create cache directory: $cache_dir_path"
    
    # Use flock with file descriptor 200
    {
        flock -n 200 || die "Session file busy (another workon process may be running)"
        "$@"
    } 200>"${lock_file}.lock"
}

# Legacy json_append function removed - session files are now written by Lua script

# Validate and read session file
read_session() {
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

# ─── Cleanup Strategy Functions ────────────────────────────────────────────

# Strategy 1: Stop by PID
stop_by_pid() {
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

# Strategy 2: Stop by xdotool
stop_by_xdotool() {
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

# Strategy 3: Stop by wmctrl
stop_by_wmctrl() {
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

# Stop a single resource using multiple cleanup strategies
stop_resource() {
    local entry="$1"
    local pid class instance name
    
    # Extract metadata from session entry
    pid=$(printf '%s' "$entry" | jq -r '.pid // empty' 2>/dev/null)
    class=$(printf '%s' "$entry" | jq -r '.class // empty' 2>/dev/null)
    instance=$(printf '%s' "$entry" | jq -r '.instance // empty' 2>/dev/null)
    name=$(printf '%s' "$entry" | jq -r '.name // empty' 2>/dev/null)
    
    printf 'Stopping %s (PID: %s)\n' "${name:-unknown}" "${pid:-unknown}" >&2
    
    # Try cleanup strategies in order
    if stop_by_pid "$pid" "$name"; then
        return 0
    fi
    
    if stop_by_xdotool "$pid" "$class" "$instance"; then
        return 0
    fi
    
    if stop_by_wmctrl "$class"; then
        return 0
    fi
    
    printf '  Warning: Could not stop %s (no reliable method found)\n' "${name:-unknown}" >&2
    return 1
}

# Implementation for stopping a session (called with file lock)
stop_session_impl() {
    local session_file="$1"
    local session_data
    
    # Read and validate session file
    if ! session_data=$(read_session "$session_file"); then
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
            if stop_resource "$entry"; then
                success_count=$((success_count + 1))
            fi
        done
        
        printf 'Successfully stopped %d/%d resources\n' "$success_count" "${#entries[@]}" >&2
    fi
    
    # Clean up session file and lock
    rm -f "$session_file" "${session_file}.lock"
    
    return 0
}

check_dependencies() { config_check_dependencies "$@"; }

# ─── Utility Functions ──────────────────────────────────────────────────────

# Check if a single dependency is available
check_single_dependency() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "✓ available"
    else
        printf "✗ missing"
    fi
}

# Parse YAML to JSON with error handling
parse_yaml_to_json() {
    local yaml_file="$1"
    
    local manifest_json
    if ! manifest_json=$(yq eval -o=json '.' "$yaml_file" 2>/dev/null); then
        return 1
    fi
    
    printf '%s' "$manifest_json"
}

# Parse a resource entry from JSON
parse_resource_entry() {
    local resource_entry="$1"
    local name cmd
    
    name=$(jq -r '.key' <<<"$resource_entry" 2>/dev/null)
    cmd=$(jq -r '.value' <<<"$resource_entry" 2>/dev/null)
    
    if [[ -z "$name" || -z "$cmd" ]]; then
        return 1
    fi
    
    printf '%s\t%s' "$name" "$cmd"
}

# Get valid session data with error handling
get_valid_session_data() {
    local session_file="$1"
    
    if [[ ! -f "$session_file" ]]; then
        return 1
    fi
    
    local session_data
    if ! session_data=$(read_session "$session_file"); then
        return 1
    fi
    
    printf '%s' "$session_data"
}

# Check if a file or command exists
resource_exists() {
    local path="$1"
    
    # Check if it's a file first
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
    
    printf "No"
    return 1
}

# ─── Path Expansion Utilities ──────────────────────────────────────────────

# Expand relative paths in a command to absolute paths
# This function identifies potential file paths and expands them to absolute paths
# - Preserves URLs (http://, https://, ftp://, etc.)
# - Preserves absolute paths (starting with /)
# - Expands relative paths to absolute paths based on current working directory
expand_relative_paths() {
    local cmd="$1"
    local -a words
    
    # Use eval to let bash handle quote parsing properly
    eval "words=($cmd)"
    
    local result=""
    for word in "${words[@]}"; do
        local expanded_word
        expanded_word=$(expand_word_if_path "$word")
        
        # Use printf %q to properly quote the result
        result+="$(printf '%q' "$expanded_word") "
    done
    
    # Remove trailing space and output
    printf '%s' "${result% }"
}

# Helper function to expand a word if it's a path
expand_word_if_path() {
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
        if should_expand_as_path "$suffix"; then
            printf '%s=@%s' "$prefix" "$(expand_to_absolute_path "$suffix")"
            return
        fi
    elif [[ $word == *=* ]]; then
        local prefix="${word%%=*}"
        local suffix="${word#*=}"
        if should_expand_as_path "$suffix"; then
            printf '%s=%s' "$prefix" "$(expand_to_absolute_path "$suffix")"
            return
        fi
    fi
    
    # Check if word looks like a relative path
    if should_expand_as_path "$word"; then
        # Convert to absolute path
        expand_to_absolute_path "$word"
        return
    fi
    
    # Not a path, keep as-is
    printf '%s' "$word"
}

# Helper function to determine if a word should be expanded as a path
should_expand_as_path() {
    local word="$1"
    
    # Expand if contains / (subdirectory) or if file/directory exists
    [[ $word == */* ]] || [[ -e $word ]]
}

# Helper function to expand a path to absolute, with fallback for portability
expand_to_absolute_path() {
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

# ─── Template Processing Utilities ─────────────────────────────────────────

# Process template variables and show analysis
process_template_variables() {
    local text="$1"
    local template_vars
    
    template_vars=$(extract_template_variables "$text")
    
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
show_template_analysis() {
    local text="$1"
    local template_vars
    
    template_vars=$(extract_template_variables "$text")
    
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

# ─── Debug Command Functions ────────────────────────────────────────────────

# Show basic system information
show_basic_info() {
    printf "WorkOn - one-shot project workspace bootstrapper\n\n"
    printf "Version: %s\n" "$VERSION"
    printf "Installation directory: %s\n" "$WORKON_DIR"
    printf "Working directory: %s\n" "$PWD"
    printf "Cache directory: %s\n" "$(cache_dir)"
    printf "\n"
    
    # Check manifest status
    local manifest
    if manifest=$(find_manifest "$PWD" 2>/dev/null); then
        printf "Manifest: Found (%s)\n" "$manifest"
    else
        printf "Manifest: Not found\n"
    fi
    printf "\n"
    
    # Show dependency status
    printf "Dependencies:\n"
    printf "  yq: %s\n" "$(check_single_dependency yq)"
    printf "  jq: %s\n" "$(check_single_dependency jq)"
    printf "  awesome-client: %s\n" "$(check_single_dependency awesome-client)"
    printf "  realpath: %s\n" "$(check_single_dependency realpath)"
    printf "  sha1sum: %s\n" "$(check_single_dependency sha1sum)"
    printf "  flock: %s\n" "$(check_single_dependency flock)"
}

# Show list of all active sessions
show_sessions_list() {
    printf "Active WorkOn Sessions\n"
    printf "=====================\n\n"
    
    local cache_path
    cache_path="$(cache_dir)"
    
    if [[ ! -d "$cache_path" ]]; then
        printf "No cache directory found (%s)\n" "$cache_path"
        return 0
    fi
    
    local session_files
    mapfile -t session_files < <(find "$cache_path" -name "*.json" -type f 2>/dev/null | sort)
    
    if [[ ${#session_files[@]} -eq 0 ]]; then
        printf "No active sessions found\n"
        return 0
    fi
    
    printf "Found %d active session(s):\n\n" "${#session_files[@]}"
    
    for session_file in "${session_files[@]}"; do
        local session_name
        session_name=$(basename "$session_file" .json)
        
        local session_data resource_count
        if session_data=$(get_valid_session_data "$session_file"); then
            resource_count=$(printf '%s' "$session_data" | jq 'length' 2>/dev/null || echo "0")
        else
            resource_count="0"
        fi
        
        local file_size created_time
        file_size=$(stat -c %s "$session_file" 2>/dev/null || echo "unknown")
        created_time=$(stat -c %Y "$session_file" 2>/dev/null | xargs -I {} date -d @{} '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        
        printf "📁 Session: %s\n" "$session_name"
        printf "   Resources: %s\n" "$resource_count"
        printf "   Created: %s\n" "$created_time"
        printf "   File size: %s bytes\n" "$file_size"
        printf "\n"
    done
}

# Show detailed information for a specific session
show_session_details() {
    local project_path="${1:-$PWD}"
    
    printf "WorkOn Session Details\n"
    printf "======================\n\n"
    
    local session_file
    session_file=$(cache_file "$project_path")
    
    printf "📁 Project: %s\n" "$project_path"
    printf "📄 Session file: %s\n" "$session_file"
    
    local session_data
    if ! session_data=$(get_valid_session_data "$session_file"); then
        printf "❌ No active session found\n"
        return 1
    fi
    
    local resource_count
    resource_count=$(printf '%s' "$session_data" | jq 'length' 2>/dev/null || echo "0")
    
    printf "📦 Resources: %s\n\n" "$resource_count"
    
    if [[ "$resource_count" -gt 0 ]]; then
        local entries
        mapfile -t entries < <(printf '%s' "$session_data" | jq -c '.[]' 2>/dev/null)
        
        for entry in "${entries[@]}"; do
            local name pid cmd class instance spawn_time
            name=$(jq -r '.name // "unknown"' <<<"$entry" 2>/dev/null)
            pid=$(jq -r '.pid // "unknown"' <<<"$entry" 2>/dev/null)
            cmd=$(jq -r '.cmd // "unknown"' <<<"$entry" 2>/dev/null)
            class=$(jq -r '.class // ""' <<<"$entry" 2>/dev/null)
            instance=$(jq -r '.instance // ""' <<<"$entry" 2>/dev/null)
            spawn_time=$(jq -r '.spawn_time // ""' <<<"$entry" 2>/dev/null)
            
            printf "🎯 %s\n" "$name"
            printf "   PID: %s" "$pid"
            
            # Check if process is still running
            if [[ "$pid" != "unknown" && "$pid" != "0" ]] && kill -0 "$pid" 2>/dev/null; then
                printf " (✅ running)\n"
            else
                printf " (❌ stopped)\n"
            fi
            
            printf "   Command: %s\n" "$cmd"
            
            if [[ -n "$class" ]]; then
                printf "   Window class: %s\n" "$class"
            fi
            
            if [[ -n "$instance" ]]; then
                printf "   Window instance: %s\n" "$instance"
            fi
            
            if [[ -n "$spawn_time" ]]; then
                printf "   Spawned: %s\n" "$spawn_time"
            fi
            
            printf "\n"
        done
    fi
}

# Route info commands to appropriate handlers
workon_info() {
    local subcommand="${1:-}"
    [[ $# -gt 0 ]] && shift
    
    case "$subcommand" in
        "")
            show_basic_info
            ;;
        sessions)
            show_sessions_list
            ;;
        session)
            show_session_details "$@"
            ;;
        *)
            printf "Unknown info subcommand: %s\n" "$subcommand" >&2
            return 2
            ;;
    esac
}

# Extract template variables from a string
extract_template_variables() {
    local input="$1"
    # Find all {{VAR}} and {{VAR:-default}} patterns
    printf '%s' "$input" | grep -oE '\{\{[A-Za-z_][A-Za-z0-9_]*(:[-][^}]*)?\}\}' | sort | uniq || true
}

# Validate YAML syntax and print status
validate_manifest_syntax() {
    local manifest="$1"
    
    printf "🔍 YAML syntax: "
    if parse_yaml_to_json "$manifest" >/dev/null; then
        printf "✅ Valid\n"
        return 0
    else
        printf "❌ YAML syntax error\n"
        yq eval -o=json '.' "$manifest" 2>&1 | head -5
        return 1
    fi
}

# Validate manifest structure and print status
validate_manifest_structure() {
    local manifest_json="$1"
    
    printf "🏗️  Structure: "
    if ! jq -e '.resources' <<<"$manifest_json" >/dev/null 2>&1; then
        printf "❌ Invalid - missing 'resources' section\n"
        return 1
    fi
    
    # Check if resources is empty
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    if [[ "$resource_count" == "0" ]] || [[ "$resource_count" == "null" ]]; then
        printf "❌ Invalid - No resources defined in manifest\n"
        return 1
    fi
    
    printf "✅ Valid\n"
    return 0
}

# Show manifest resources
show_manifest_resources() {
    local manifest_json="$1"
    local resource_count="$2"
    
    printf "📦 Resources: %s found\n" "$resource_count"
    
    # List each resource
    while IFS= read -r resource_entry; do
        local result
        if result=$(parse_resource_entry "$resource_entry"); then
            local name cmd
            IFS=$'\t' read -r name cmd <<<"$result"
            printf "  • %s: %s\n" "$name" "$cmd"
        fi
    done < <(jq -c '.resources | to_entries[]' <<<"$manifest_json" 2>/dev/null)
}

# Show template variables in manifest
show_manifest_template_variables() {
    local manifest_json="$1"
    
    printf "\n🔧 Template variables: "
    local all_commands
    all_commands=$(jq -r '.resources | to_entries[] | .value' <<<"$manifest_json" 2>/dev/null)
    
    process_template_variables "$all_commands" || true
}

# Validate workon.yaml manifest file
workon_validate() {
    local project_path="${1:-$PWD}"
    local manifest
    
    printf "WorkOn Manifest Validation\n"
    printf "=========================\n\n"
    
    # Find manifest file
    if ! manifest=$(find_manifest "$project_path"); then
        printf "❌ No workon.yaml found in %s or parent directories\n" "$project_path"
        return 2
    fi
    
    printf "📁 Manifest file: %s\n" "$manifest"
    
    # Validate syntax
    if ! validate_manifest_syntax "$manifest"; then
        return 1
    fi
    
    # Get JSON for further processing
    local manifest_json
    if ! manifest_json=$(parse_yaml_to_json "$manifest"); then
        printf "❌ Unexpected error parsing manifest\n"
        return 1
    fi
    
    # Validate structure
    if ! validate_manifest_structure "$manifest_json"; then
        return 1
    fi
    
    # Get resource count for display
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    
    # Show resources
    show_manifest_resources "$manifest_json" "$resource_count"
    
    # Show template variables
    show_manifest_template_variables "$manifest_json"
    
    printf "\n✅ Valid manifest - ready to use!\n"
    return 0
}


# Get resource command from manifest
get_resource_command() {
    local resource_name="$1"
    local manifest_json="$2"
    
    jq -r --arg resource "$resource_name" '.resources[$resource] // empty' <<<"$manifest_json" 2>/dev/null
}

# Show resource resolution info
show_resource_info() {
    local resource_name="$1"
    local raw_command="$2"
    local manifest_json="$3"
    
    if [[ -z $raw_command ]]; then
        printf "❌ Resource '%s' not found in manifest\n" "$resource_name"
        printf "\nAvailable resources:\n"
        jq -r '.resources | keys[] | "  • " + .' <<<"$manifest_json" 2>/dev/null
        return 1
    fi
    
    printf "🎯 Resource: %s\n" "$resource_name"
    printf "📝 Raw command: %s\n" "$raw_command"
    return 0
}

# Show resolution results with template analysis
show_resolution_results() {
    local raw_command="$1"
    
    # Show template analysis
    show_template_analysis "$raw_command" || true
    
    # Resolve template variables
    local resolved_command
    resolved_command=$(render_template "$raw_command")
    
    # Expand relative paths to absolute paths
    local expanded_command
    expanded_command=$(expand_relative_paths "$resolved_command")
    
    printf "✅ Resolved command: pls-open %s\n" "$expanded_command"
    
    # Check if file/command exists
    printf "📋 File/Command exists: %s\n" "$(resource_exists "$expanded_command")"
}

# Show resolved command for a specific resource
workon_resolve() {
    local resource_name="$1"
    local project_path="${2:-$PWD}"
    
    if [[ -z $resource_name ]]; then
        printf "Usage: workon resolve <resource> [project_path]\n" >&2
        return 2
    fi
    
    printf "WorkOn Resource Resolution\n"
    printf "==========================\n\n"
    
    # Find manifest file
    local manifest
    if ! manifest=$(find_manifest "$project_path"); then
        printf "❌ No workon.yaml found in %s or parent directories\n" "$project_path"
        return 2
    fi
    
    printf "📁 Manifest: %s\n" "$manifest"
    
    # Change to manifest directory for relative path resolution
    local manifest_dir
    manifest_dir=$(dirname "$manifest")
    local orig_pwd="$PWD"
    cd "$manifest_dir" || {
        printf "❌ Cannot change to manifest directory: %s\n" "$manifest_dir"
        return 1
    }
    
    # Parse manifest
    local manifest_json
    if ! manifest_json=$(parse_yaml_to_json "$manifest"); then
        cd "$orig_pwd" || return 1
        printf "❌ Failed to parse manifest (YAML syntax error)\n"
        return 1
    fi
    
    # Get the resource command
    local raw_command
    raw_command=$(get_resource_command "$resource_name" "$manifest_json")
    
    # Show resource info
    if ! show_resource_info "$resource_name" "$raw_command" "$manifest_json"; then
        cd "$orig_pwd" || return 1
        return 1
    fi
    
    # Show resolution results
    show_resolution_results "$raw_command"
    
    # Restore original directory
    cd "$orig_pwd" || return 1
    
    return 0
}
