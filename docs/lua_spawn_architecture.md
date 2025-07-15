# WorkOn Lua Spawn Architecture

> **Problem Statement**: The current awesome-client PID-based approach is fundamentally flawed because awesome-client PIDs are useless for window management. This document describes the architectural solution using a single Lua script for spawning.

## Current Problems

### 1. Useless PID Collection
```bash
# Current broken approach
awesome-client "awful.spawn('$cmd')" &
spawn_pid=$!  # PID of awesome-client process, NOT the spawned app!
```

The `spawn_pid` variable contains the PID of the `awesome-client` process, which immediately exits after sending the Lua command. This PID has no relationship to the actual spawned application.

### 2. Multiple Round-Trips
```bash
# Each resource requires separate awesome-client call
for resource in "${resources[@]}"; do
    awesome-client "awful.spawn('$resource')" &
    # Lose all context between calls
done
```

Each spawn operation loses context from previous operations, making session management fragmented and unreliable.

### 3. Complex Callback System
```lua
-- Overly complex callback with shell injection risks
awful.spawn("${escaped_cmd}", {
  callback = function(c) 
    os.execute("write_session_entry \"${session_file}\" \"${command}\" \"${name}\" \"" .. c.pid .. "\"")
  end
})
```

This approach:
- Creates security vulnerabilities through shell injection
- Has no error handling if the external script fails
- Cannot synchronize with the main bash process
- Makes testing extremely difficult

## Proposed Solution: Single Lua Script

### Architecture Overview

```
Bash (prepare) → JSON → Lua Script (spawn all) → Session File → Bash (continue)
```

### Data Flow

1. **Bash Preparation**: Parse YAML, render templates, create resources JSON
2. **Single Lua Execution**: Spawn all resources, collect metadata, write session
3. **Bash Continuation**: Read session file and report status

### JSON Interface

**Input to Lua** (via environment variable):
```json
{
  "session_file": "/home/user/.cache/workon/abc123.json",
  "resources": [
    {"name": "editor", "cmd": "code ."},
    {"name": "terminal", "cmd": "gnome-terminal"},
    {"name": "browser", "cmd": "firefox"}
  ]
}
```

**Output Session File**:
```json
[
  {
    "name": "editor",
    "cmd": "code .",
    "pid": 12345,
    "window_id": "0x1400001",
    "class": "code",
    "instance": "code",
    "timestamp": 1710441037
  }
]
```

## Implementation Components

### 1. Lua Spawn Script (`lib/spawn_resources.lua`)

```lua
local json = require("json")  -- or cjson/dkjson
local awful = require("awful")

-- Read configuration from environment
local config = json.decode(os.getenv("WORKON_SPAWN_CONFIG"))
local session_data = {}

-- Spawn each resource
for _, resource in ipairs(config.resources) do
    local success, pid = pcall(function()
        return awful.spawn(resource.cmd, {
            callback = function(c)
                -- Collect comprehensive window metadata
                table.insert(session_data, {
                    name = resource.name,
                    cmd = resource.cmd,
                    pid = c.pid,
                    window_id = tostring(c.window),
                    class = c.class or "",
                    instance = c.instance or "",
                    timestamp = os.time()
                })
                
                -- Write session file atomically
                write_session_atomic(config.session_file, session_data)
            end
        })
    end)
    
    if not success then
        -- Log error but continue with other resources
        io.stderr:write("Failed to spawn " .. resource.name .. ": " .. tostring(pid) .. "\n")
    end
end

-- Helper function for atomic session file writing
function write_session_atomic(filepath, data)
    local tmp_file = filepath .. ".tmp"
    local file = io.open(tmp_file, "w")
    if file then
        file:write(json.encode(data))
        file:close()
        os.rename(tmp_file, filepath)
    end
end
```

### 2. Bash Integration (`lib/workon.sh`)

```bash
launch_all_resources() {
    local session_file="$1"
    local resources_json="$2"
    
    # Prepare configuration for Lua script
    local spawn_config
    spawn_config=$(jq -n \
        --arg session_file "$session_file" \
        --argjson resources "$resources_json" \
        '{session_file: $session_file, resources: $resources}')
    
    # Execute single Lua script with all spawning
    WORKON_SPAWN_CONFIG="$spawn_config" awesome-client "$(cat "$WORKON_DIR/lib/spawn_resources.lua")"
    
    # Wait for session file to be written
    local timeout=10
    while [[ ! -f "$session_file" && $timeout -gt 0 ]]; do
        sleep 0.1
        timeout=$((timeout - 1))
    done
    
    if [[ -f "$session_file" ]]; then
        local count
        count=$(jq 'length' "$session_file" 2>/dev/null || echo 0)
        printf 'Started %d resources\n' "$count" >&2
        return 0
    else
        printf 'Warning: Session file not created within timeout\n' >&2
        return 1
    fi
}
```

## Enhanced Session Management

### Session Data Structure

Each session entry contains:
- **name**: Resource identifier from YAML
- **cmd**: Actual command executed
- **pid**: Real application PID from `awful.spawn()`
- **window_id**: X11 window identifier
- **class**: Window class for pattern matching
- **instance**: Window instance for precise identification
- **timestamp**: Creation time for stale session detection

### Multi-Strategy Cleanup

```bash
stop_resource() {
    local entry="$1"
    local pid class instance name
    
    pid=$(echo "$entry" | jq -r '.pid')
    class=$(echo "$entry" | jq -r '.class')
    instance=$(echo "$entry" | jq -r '.instance')
    name=$(echo "$entry" | jq -r '.name')
    
    printf 'Stopping %s (PID: %s)\n' "$name" "$pid" >&2
    
    # Strategy 1: Direct PID kill
    if kill -0 "$pid" 2>/dev/null; then
        if kill -TERM "$pid" 2>/dev/null; then
            sleep 3
            kill -KILL "$pid" 2>/dev/null || true
            return 0
        fi
    fi
    
    # Strategy 2: Window-based cleanup with xdotool
    if command -v xdotool >/dev/null; then
        if xdotool search --pid "$pid" windowclose 2>/dev/null; then
            return 0
        fi
        
        # Strategy 3: Class-based pattern matching
        if [[ -n "$class" ]] && xdotool search --class "$class" windowclose 2>/dev/null; then
            return 0
        fi
    fi
    
    printf 'Warning: Could not stop %s\n' "$name" >&2
    return 1
}
```

## Benefits of New Architecture

### 1. Real Application PIDs
- `awful.spawn()` returns actual application PIDs
- No confusion with awesome-client process PIDs
- Reliable process lifecycle management

### 2. Reduced Complexity
- Single point of spawning eliminates race conditions
- No bash/Lua round-trip synchronization issues
- Simplified error handling and debugging

### 3. Enhanced Metadata
- Window properties enable robust cleanup fallbacks
- Session files contain comprehensive application state
- Future-proof for advanced AwesomeWM features

### 4. Security Improvements
- Eliminates shell injection vulnerabilities
- Controlled data flow through JSON interface
- No external script dependencies

### 5. Better Testing
- Mock Lua script easily for unit tests
- Single execution path reduces test complexity
- JSON interface enables precise test validation

## Migration Strategy

### Phase 1: Implement Core Components
1. Create `lib/spawn_resources.lua`
2. Update `launch_resource_with_session()` function
3. Test with simple resources

### Phase 2: Enhanced Session Management
1. Update session data structure
2. Implement multi-strategy cleanup
3. Add comprehensive error handling

### Phase 3: Cleanup and Optimization
1. Remove legacy callback system
2. Delete external script dependencies
3. Update tests and documentation

## Error Handling

### Lua Script Errors
- Graceful degradation if JSON parsing fails
- Continue spawning other resources if one fails
- Log errors to stderr for debugging

### Session File Issues
- Atomic writes prevent corruption
- Timeout handling for session file creation
- Recovery strategies for missing/corrupted sessions

### Window Management Failures
- Multiple cleanup strategies ensure reliability
- Clear user feedback about partial failures
- Graceful handling of missing dependencies

## Dependencies

### Required
- **AwesomeWM**: `awful.spawn()` API
- **jq**: JSON processing in bash
- **Lua JSON library**: Choose from `cjson`, `dkjson`, or `lua-json`

### Optional
- **xdotool**: Enhanced window management for cleanup fallbacks

## Testing Strategy

### Unit Tests
- Mock Lua script execution
- Test JSON interface validation
- Verify session file format

### Integration Tests
- Real AwesomeWM spawn behavior
- Multi-resource session management
- Cleanup strategy validation

This architecture transforms WorkOn from a fragile bash script into a robust workspace manager that properly leverages AwesomeWM's capabilities while maintaining simplicity and reliability.