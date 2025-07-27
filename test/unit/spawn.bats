#!/usr/bin/env bats
# Tests for lib/spawn.sh - Resource spawning coordination functions

setup() {
    # Create a temporary directory for testing
    TEST_DIR=$(mktemp -d)
    export WORKON_CACHE_DIR="$TEST_DIR/cache"
    export WORKON_DIR="$PWD"
    
    # Create mock directories
    mkdir -p "$WORKON_CACHE_DIR"
    mkdir -p "$TEST_DIR/project"
    
    # Disable all logging output for clean testing
    export WORKON_DEBUG=0
    export WORKON_VERBOSE=0
    export WORKON_DRY_RUN=0
    
    # Mock config_die function for testing
    config_die() {
        printf 'workon: %s\n' "$*" >&2
        exit 2
    }
    export -f config_die
    
    # Mock pls-open for testing
    pls-open() {
        echo "pls-open called with: $*"
    }
    export -f pls-open
    
    # Global variable to store session file path for mock
    export MOCK_SESSION_FILE=""
    
    # Mock awesome-client for testing - creates session file at the path being tested
    awesome-client() {
        echo "awesome-client called with: $*" >&2
        # Use the session file path that was set by the test
        if [[ -n "$MOCK_SESSION_FILE" ]]; then
            mkdir -p "$(dirname "$MOCK_SESSION_FILE")"
            echo '[{"pid": 12345, "name": "test-resource", "class": "TestApp"}]' > "$MOCK_SESSION_FILE"
        fi
    }
    export -f awesome-client
}

teardown() {
    # Clean up test directory
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ── spawn_prepare_resources_json() Tests ───────────────────────────────────

@test "spawn_prepare_resources_json: processes single resource correctly" {
    source lib/spawn.sh
    
    # Create base64-encoded resource entry
    local resource_json='{"key": "editor", "value": "code ."}'
    local encoded_resource
    encoded_resource=$(printf '%s' "$resource_json" | base64)
    
    # Capture stdout only (logging is disabled by environment variables)
    output=$(spawn_prepare_resources_json "$encoded_resource" 2>/dev/null)
    [[ $? -eq 0 ]]
    
    # Verify JSON structure
    local result_count
    result_count=$(printf '%s' "$output" | jq 'length')
    [[ $result_count -eq 1 ]]
    
    # Verify resource name and command
    local name cmd
    name=$(printf '%s' "$output" | jq -r '.[0].name')
    cmd=$(printf '%s' "$output" | jq -r '.[0].cmd')
    
    [[ "$name" == "editor" ]]
    [[ "$cmd" =~ "pls-open" ]]
}

@test "spawn_prepare_resources_json: processes multiple resources" {
    source lib/spawn.sh
    
    # Create multiple resource entries
    local resource1 resource2 encoded_resources
    resource1=$(printf '{"key": "editor", "value": "code ."}' | base64)
    resource2=$(printf '{"key": "browser", "value": "firefox"}' | base64)
    encoded_resources="$resource1"$'\n'"$resource2"
    
    # Capture stdout only (logging disabled by environment)
    output=$(spawn_prepare_resources_json "$encoded_resources" 2>/dev/null)
    [[ $? -eq 0 ]]
    
    # Verify we have 2 resources
    local result_count
    result_count=$(printf '%s' "$output" | jq 'length')
    [[ $result_count -eq 2 ]]
}

@test "spawn_prepare_resources_json: handles empty input" {
    source lib/spawn.sh
    
    output=$(spawn_prepare_resources_json "" 2>/dev/null)
    [[ $? -eq 0 ]]
    [[ "$output" == "[]" ]]
}

@test "spawn_prepare_resources_json: expands template variables" {
    source lib/spawn.sh
    
    # Set environment variable for template
    export PROJECT_DIR="/home/user/project"
    
    local resource_json='{"key": "editor", "value": "code {{PROJECT_DIR}}"}'
    local encoded_resource
    encoded_resource=$(printf '%s' "$resource_json" | base64)
    
    # Capture stdout only (logging disabled by environment)
    output=$(spawn_prepare_resources_json "$encoded_resource" 2>/dev/null)
    [[ $? -eq 0 ]]
    
    # Verify template was expanded
    local cmd
    cmd=$(printf '%s' "$output" | jq -r '.[0].cmd')
    [[ "$cmd" =~ "/home/user/project" ]]
}

# ── spawn_execute_lua_script() Tests ────────────────────────────────────────

@test "spawn_execute_lua_script: executes awesome-client with config" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/test-session.json"
    local resources_json='[{"name": "test", "cmd": "pls-open echo test"}]'
    
    run spawn_execute_lua_script "$session_file" "$resources_json" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "awesome-client called" ]]
}

@test "spawn_execute_lua_script: creates proper Lua configuration" {
    source lib/spawn.sh
    
    # Override awesome-client to capture the config
    awesome-client() {
        # Extract the WORKON_SPAWN_CONFIG from the Lua script
        echo "$1" | grep "WORKON_SPAWN_CONFIG"
    }
    export -f awesome-client
    
    local session_file="$TEST_DIR/test.json"
    local resources_json='[{"name": "test", "cmd": "echo"}]'
    
    run spawn_execute_lua_script "$session_file" "$resources_json"
    [[ $status -eq 0 ]]
    [[ "$output" =~ "WORKON_SPAWN_CONFIG" ]]
}

# ── spawn_wait_for_session_update() Tests ──────────────────────────────────

@test "spawn_wait_for_session_update: succeeds when session file updated" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/wait-test.json"
    
    # Start background process to create session file after delay
    (
        sleep 0.2
        echo '[{"pid": 123, "name": "test"}]' > "$session_file"
    ) &
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_wait_for_session_update "$session_file" 0 5 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Session file updated" ]]
}

@test "spawn_wait_for_session_update: times out if no update" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/timeout-test.json"
    
    # Enable verbose logging for this test  
    WORKON_VERBOSE=1 run spawn_wait_for_session_update "$session_file" 0 1 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Session file not updated within timeout" ]]
}

@test "spawn_wait_for_session_update: detects increased resource count" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/count-test.json"
    
    # Create initial session with 1 resource
    echo '[{"pid": 123, "name": "first"}]' > "$session_file"
    
    # Start background process to add second resource
    (
        sleep 0.2
        echo '[{"pid": 123, "name": "first"}, {"pid": 456, "name": "second"}]' > "$session_file"
    ) &
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_wait_for_session_update "$session_file" 1 5 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "updated with 2 entries" ]]
}

# ── spawn_launch_all_resources() Tests ──────────────────────────────────────

@test "spawn_launch_all_resources: orchestrates complete spawn process" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/launch-test.json"
    export MOCK_SESSION_FILE="$session_file"
    local resource_json='{"key": "editor", "value": "code ."}'
    local encoded_resource
    encoded_resource=$(printf '%s' "$resource_json" | base64)
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_launch_all_resources "$session_file" "$encoded_resource" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Preparing resources for sequential spawning" ]]
    [[ "$output" =~ "awesome-client called" ]]
}

@test "spawn_launch_all_resources: fails with no resources" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/empty-test.json"
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_launch_all_resources "$session_file" "" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "No resources to spawn" ]]
}

@test "spawn_launch_all_resources: handles timeout gracefully" {
    source lib/spawn.sh
    
    # Mock awesome-client to not create session file
    awesome-client() {
        echo "awesome-client called but no session file created" >&2
    }
    export -f awesome-client
    
    local session_file="$TEST_DIR/timeout-test.json" 
    local resource_json='{"key": "test", "value": "echo"}'
    local encoded_resource
    encoded_resource=$(printf '%s' "$resource_json" | base64)
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_launch_all_resources "$session_file" "$encoded_resource" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Session file not updated within timeout" ]]
}

# ── Integration Tests ───────────────────────────────────────────────────────

@test "spawn module: complete workflow from resources to session" {
    source lib/spawn.sh
    
    local session_file="$TEST_DIR/workflow-test.json"
    export MOCK_SESSION_FILE="$session_file"
    
    # Create multiple test resources
    local editor_res browser_res terminal_res
    editor_res=$(printf '{"key": "editor", "value": "code ."}' | base64)
    browser_res=$(printf '{"key": "browser", "value": "firefox"}' | base64)
    terminal_res=$(printf '{"key": "terminal", "value": "gnome-terminal"}' | base64)
    
    local all_resources="$editor_res"$'\n'"$browser_res"$'\n'"$terminal_res"
    
    run spawn_launch_all_resources "$session_file" "$all_resources" 2>/dev/null
    [[ $status -eq 0 ]]
    
    # Verify session file was created
    [[ -f "$session_file" ]]
    
    # Verify session contains expected data
    local entry_count
    entry_count=$(jq 'length' "$session_file")
    [[ $entry_count -eq 1 ]]  # Our mock creates 1 entry
}

@test "spawn module: handles relative path expansion" {
    source lib/spawn.sh
    
    # Create a test file for path expansion
    mkdir -p "$TEST_DIR/project"
    touch "$TEST_DIR/project/test.txt"
    cd "$TEST_DIR/project"
    
    local session_file="$TEST_DIR/path-test.json"
    export MOCK_SESSION_FILE="$session_file"
    local resource_json='{"key": "editor", "value": "code test.txt"}'
    local encoded_resource
    encoded_resource=$(printf '%s' "$resource_json" | base64)
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_launch_all_resources "$session_file" "$encoded_resource" 2>&1
    [[ $status -eq 0 ]]
    
    # The output should show the expanded absolute path
    [[ "$output" =~ "$TEST_DIR/project/test.txt" ]]
}

@test "spawn module: error handling for malformed resource data" {
    source lib/spawn.sh
    
    # Create invalid base64 data
    local invalid_resource="invalid-base64-data"
    local session_file="$TEST_DIR/error-test.json"
    
    # Enable verbose logging for this test
    WORKON_VERBOSE=1 run spawn_launch_all_resources "$session_file" "$invalid_resource" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "No resources to spawn" ]]
}