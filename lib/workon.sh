#!/usr/bin/env bash
# WorkOn Library Functions
# Shared functions for workon CLI tool

# Print error message and exit
die() {
    printf 'workon: %s\n' "$*" >&2
    exit 2
}

# Find workon.yaml by walking up directory tree
find_manifest() {
    local dir
    dir=$(realpath "${1:-$PWD}")
    
    while [[ $dir != / ]]; do
        if [[ -f $dir/workon.yaml ]]; then
            printf '%s/workon.yaml' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    
    return 1
}

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
        
        printf '  %s: %s\n' "$name" "$rendered_cmd" >&2
        
        # Add to resources JSON array
        local resource_entry
        resource_entry=$(jq -n \
            --arg name "$name" \
            --arg cmd "pls-open $rendered_cmd" \
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

# Parse and validate manifest JSON
parse_manifest() {
    local manifest="$1"
    local manifest_json
    
    # Parse YAML to JSON
    if ! manifest_json=$(yq eval -o=json '.' "$manifest" 2>/dev/null); then
        die "Failed to parse $manifest (check YAML syntax)"
    fi
    
    # Validate structure
    if ! jq -e '.resources' <<<"$manifest_json" >/dev/null 2>&1; then
        die "Invalid manifest: missing 'resources' section"
    fi
    
    # Check if resources is empty
    local resource_count
    resource_count=$(jq -r '.resources | length' <<<"$manifest_json" 2>/dev/null)
    if [[ "$resource_count" == "0" ]] || [[ "$resource_count" == "null" ]]; then
        die "No resources defined in manifest"
    fi
    
    printf '%s' "$manifest_json"
}

# Extract resources from manifest JSON
extract_resources() {
    local manifest_json="$1"
    
    if ! jq -r '.resources | to_entries[] | @base64' <<<"$manifest_json" 2>/dev/null; then
        die "Failed to extract resources from manifest"
    fi
}

# ─── Session Management Functions ───────────────────────────────────────────

# Get the cache directory following XDG spec
cache_dir() {
    printf '%s/workon' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# Generate session file path for a project directory
cache_file() {
    local project_root
    project_root=$(realpath "${1:-$PWD}")
    local sha1
    sha1=$(printf '%s' "$project_root" | sha1sum | cut -d' ' -f1)
    printf '%s/%s.json' "$(cache_dir)" "$sha1"
}

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
    
    # Strategy 1: Direct PID kill (most reliable)
    if [[ -n $pid && $pid != "0" ]] && kill -0 "$pid" 2>/dev/null; then
        printf '  Using PID %s for cleanup\n' "$pid" >&2
        if kill -TERM "$pid" 2>/dev/null; then
            sleep 3
            if kill -0 "$pid" 2>/dev/null; then
                printf '  Force killing PID %s\n' "$pid" >&2
                kill -KILL "$pid" 2>/dev/null || true
            fi
            return 0
        fi
    fi
    
    # Strategy 2: Window-based cleanup with xdotool (if available)
    if command -v xdotool >/dev/null 2>&1; then
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
    fi
    
    # Strategy 3: wmctrl fallback (if available)
    if command -v wmctrl >/dev/null 2>&1; then
        printf '  Trying wmctrl fallback\n' >&2
        
        # Try to close windows by class name
        if [[ -n $class ]]; then
            if wmctrl -c "$class" 2>/dev/null; then
                printf '  Closed window with wmctrl (class: %s)\n' "$class" >&2
                return 0
            fi
        fi
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

# Check dependencies are available
check_dependencies() {
    local missing=()
    
    command -v yq >/dev/null || missing+=(yq)
    command -v jq >/dev/null || missing+=(jq)
    command -v awesome-client >/dev/null || missing+=(awesome-client)
    command -v realpath >/dev/null || missing+=(realpath)
    command -v sha1sum >/dev/null || missing+=(sha1sum)
    command -v flock >/dev/null || missing+=(flock)
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}
