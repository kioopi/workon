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
    awesome-client "awful.spawn(\"$escaped_cmd\")" >/dev/null 2>&1 &
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

# Check dependencies are available
check_dependencies() {
    local missing=()
    
    command -v yq >/dev/null || missing+=(yq)
    command -v jq >/dev/null || missing+=(jq)
    command -v awesome-client >/dev/null || missing+=(awesome-client)
    command -v realpath >/dev/null || missing+=(realpath)
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required dependencies: ${missing[*]}"
    fi
}