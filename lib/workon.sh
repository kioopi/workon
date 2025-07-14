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

# Launch a resource and record it in the session file
launch_resource_with_session() {
    local session_file="$1"
    local name="$2"
    local command="$3"
    
    # Escape for awesome-client
    local escaped_cmd
    escaped_cmd=$(printf '%s' "pls-open $command" | sed 's/"/\\"/g; s/\\/\\\\/g')
    
    printf '  %s: %s\n' "$name" "$command" >&2

    awesome-client <<-LUA
    local awful = require("awful")
    awful.spawn("${escaped_cmd}", {
      callback = function(c) 
        os.execute("echo \"" .. c.pid .. "\" > /home/vt/tmp/pid.txt")
        if c.pid then
          os.execute("write_session_entry \"${session_file}\" \"${command}\" \"${name}\" \"" .. c.pid .. "\"")
        end
      end
    })
LUA
    # TODO: Find a way to check if the command was successfully launched 

    return 0
}

write_session_entry() {
    local session_file="$1"
    local cmd="$2"
    local name="$3"
    local pid="$4"

    # Validate inputs
    if [[ -z $session_file || -z $cmd || -z $name || -z $pid ]]; then
        die "Invalid parameters for write_session_entry"
    fi

    # Create JSON entry
    local json_entry
    json_entry=$(session_entry "$cmd" "$name" "$pid")
    
    # Append to session file with locking
    with_lock "$session_file" json_append "$session_file" "$json_entry"
}


session_entry() {
    local cmd="$1"
    local name="$2"
    local pid="$3"
    
    # Validate inputs
    if [[ -z $cmd || -z $name || -z $pid ]]; then
        die "Invalid session entry parameters"
    fi
    
    # Create JSON entry
    jq -n \
        --arg cmd "$cmd" \
        --arg name "$name" \
        --argjson pid "$pid" \
        --argjson timestamp "$(date +%s)" \
        '{cmd: $cmd, name: $name, pid: $pid, timestamp: $timestamp}'
}

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

# Atomically append JSON entry to session file
json_append() {
    local session_file="$1"
    local json_entry="$2"
    local tmp_file
    
    # Validate JSON entry format
    if ! jq -e . <<<"$json_entry" >/dev/null 2>&1; then
        die "Invalid JSON entry for session file"
    fi
    
    tmp_file=$(mktemp) || die "Cannot create temporary file"
    
    # Append to existing array or create new array
    if [[ -s $session_file ]]; then
        if ! jq -e type <<<"$(cat "$session_file")" >/dev/null 2>&1; then
            printf '[]' >"$session_file"  # Reset corrupted file
        fi
        jq ". + [$json_entry]" "$session_file" >"$tmp_file" 2>/dev/null || {
            rm -f "$tmp_file"
            die "Failed to append to session file"
        }
    else
        jq -n "[$json_entry]" >"$tmp_file" 2>/dev/null || {
            rm -f "$tmp_file"
            die "Failed to create session file"
        }
    fi
    
    # Atomically replace session file
    mv "$tmp_file" "$session_file" || {
        rm -f "$tmp_file"
        die "Failed to update session file"
    }
}

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

# Implementation for stopping a session (called with file lock)
stop_session_impl() {
    local session_file="$1"
    local session_data
    
    # Read and validate session file
    if ! session_data=$(read_session "$session_file"); then
        printf 'Warning: No valid session data found\n' >&2
        return 1
    fi
    
    # Extract PIDs and stop processes
    local pids
    mapfile -t pids < <(printf '%s' "$session_data" | jq -r '.[].pid // empty' 2>/dev/null)
    
    if [[ ${#pids[@]} -eq 0 ]]; then
        printf 'No processes found in session\n' >&2
    else
        printf 'Stopping %d processes...\n' "${#pids[@]}" >&2
        
        # First pass: send TERM signal
        local live_pids=()
        for pid in "${pids[@]}"; do
            if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
                printf '  Terminating PID %s\n' "$pid" >&2
                kill -TERM "$pid" 2>/dev/null || true
                live_pids+=("$pid")
            fi
        done
        
        # Give processes time to exit gracefully
        if [[ ${#live_pids[@]} -gt 0 ]]; then
            sleep 3
            
            # Second pass: send KILL signal to remaining processes
            for pid in "${live_pids[@]}"; do
                if kill -0 "$pid" 2>/dev/null; then
                    printf '  Force killing PID %s\n' "$pid" >&2
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            done
        fi
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
