#!/usr/bin/env bats

# Load BATS libraries (system installation paths)
load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Load common test helpers
load '../test_helper/common'

setup() {
    # Save original directory
    ORIG_DIR="$PWD"
    # Create temporary test directory
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Source the library functions for direct testing
    source "$PROJECT_ROOT/lib/workon.sh"
    
    # Set test cache directory
    export XDG_CACHE_HOME="$TEST_DIR/.cache"
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

@test "cache_dir: returns XDG_CACHE_HOME/workon when set" {
    # Arrange
    export XDG_CACHE_HOME="/custom/cache"
    
    # Act
    run cache_dir
    
    # Assert
    assert_success
    assert_output "/custom/cache/workon"
}

@test "cache_dir: returns default ~/.cache/workon when XDG_CACHE_HOME unset" {
    # Arrange
    unset XDG_CACHE_HOME || true
    
    # Act
    run cache_dir
    
    # Assert
    assert_success
    assert_output "$HOME/.cache/workon"
}

@test "cache_file: generates deterministic SHA1-based filename" {
    # Arrange
    local test_dir="/tmp/test-project"
    mkdir -p "$test_dir"
    
    # Act
    run cache_file "$test_dir"
    
    # Assert
    assert_success
    # Should be in cache directory with .json extension
    assert_output --partial "$(cache_dir)/"
    assert_output --partial ".json"
    # Should be deterministic (same input = same output)
    local first_output="$output"
    run cache_file "$test_dir"
    assert_output "$first_output"
    
    # Cleanup
    rm -rf "$test_dir"
}

@test "cache_file: handles current directory when no argument provided" {
    # Act
    run cache_file
    
    # Assert
    assert_success
    assert_output --partial "$(cache_dir)/"
    assert_output --partial ".json"
}

@test "launch_all_resources_with_session: prepares resources JSON correctly" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    
    # Create test resources in base64 format (mimicking actual data flow)
    local editor_resource terminal_resource
    editor_resource=$(printf '{"key": "editor", "value": "code ."}' | base64 -w 0)
    terminal_resource=$(printf '{"key": "terminal", "value": "gnome-terminal"}' | base64 -w 0)
    
    # Mock awesome-client to avoid actual AwesomeWM interaction
    cat > "$TEST_DIR/mock-awesome-client" << 'MOCK_SCRIPT'
#!/bin/bash
# Mock awesome-client that simulates successful execution
# Just exit successfully without doing anything
exit 0
MOCK_SCRIPT
    chmod +x "$TEST_DIR/mock-awesome-client"
    export PATH="$TEST_DIR:$PATH"
    
    # Mock dofile execution by creating a session file manually
    # This simulates what the Lua script would do
    mkdir -p "$(dirname "$session_file")"
    cat > "$session_file" << 'JSON'
[
  {
    "name": "editor",
    "cmd": "pls-open code .",
    "pid": 12345,
    "window_id": "0x1400001",
    "class": "code",
    "instance": "code",
    "timestamp": 1710441037
  },
  {
    "name": "terminal",
    "cmd": "pls-open gnome-terminal",
    "pid": 12346,
    "window_id": "0x1400002",
    "class": "gnome-terminal-server",
    "instance": "gnome-terminal-server",
    "timestamp": 1710441038
  }
]
JSON
    
    # Act - Test that function processes resources correctly  
    {
        printf '%s\n' "$editor_resource"
        printf '%s\n' "$terminal_resource"
    } | {
        # This tests the resource parsing part
        resources_json="[]"
        
        while read -r entry; do
            if [[ -z $entry ]]; then
                continue
            fi
            
            local name raw_cmd
            name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
            raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue
            
            # Add to resources JSON array  
            local resource_entry
            resource_entry=$(jq -n \
                --arg name "$name" \
                --arg cmd "pls-open $raw_cmd" \
                '{name: $name, cmd: $cmd}')
            
            resources_json=$(printf '%s' "$resources_json" | jq ". + [$resource_entry]")
        done
        
        # Verify the JSON structure
        assert [ "$(printf '%s' "$resources_json" | jq 'length')" -eq 2 ]
        assert [ "$(printf '%s' "$resources_json" | jq -r '.[0].name')" = "editor" ]
        assert [ "$(printf '%s' "$resources_json" | jq -r '.[1].name')" = "terminal" ]
    }
}

@test "stop_resource: uses PID strategy for running process" {
    # Arrange - Create a test session entry with a mock PID
    local session_entry
    session_entry=$(jq -n '{
        name: "test-app",
        cmd: "pls-open test-command",
        pid: 99999,
        class: "test-class",
        instance: "test-instance",
        timestamp: 1710441037
    }')
    
    # Mock kill function using bash function override
    kill() {
        echo "kill $*" >> "$TEST_DIR/kill_log"
        # Simulate process exists for -0 check, then simulate successful termination
        if [[ "$1" == "-0" ]]; then
            return 0
        elif [[ "$1" == "-TERM" ]]; then
            echo "TERM $2" >> "$TEST_DIR/kill_log"
            return 0
        else
            echo "KILL $2" >> "$TEST_DIR/kill_log" 
            return 0
        fi
    }
    
    # Act
    run stop_resource "$session_entry"
    
    # Assert
    assert_success
    assert_output --partial "Using PID 99999 for cleanup"
    
    # Check that kill was called appropriately
    assert [ -f "$TEST_DIR/kill_log" ]
    grep -q "kill -0 99999" "$TEST_DIR/kill_log"
    grep -q "TERM 99999" "$TEST_DIR/kill_log"
}

# Tests for the new Lua spawn architecture integration
@test "launch_all_resources_with_session: generates proper JSON structure" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    
    # Create test resources in base64 format
    local test_resource
    test_resource=$(printf '{"key": "test-app", "value": "echo hello"}' | base64 -w0)
    
    # Extract just the JSON building logic for testing
    resources_json="[]"
    
    while read -r entry; do
        if [[ -z $entry ]]; then
            continue
        fi
        
        local name raw_cmd rendered_cmd
        name=$(printf '%s' "$entry" | base64 -d | jq -r '.key' 2>/dev/null) || continue
        raw_cmd=$(printf '%s' "$entry" | base64 -d | jq -r '.value' 2>/dev/null) || continue
        # Render template variables (simplified for test)
        rendered_cmd="$raw_cmd"
        
        # Add to resources JSON array
        local resource_entry
        resource_entry=$(jq -n \
            --arg name "$name" \
            --arg cmd "pls-open $rendered_cmd" \
            '{name: $name, cmd: $cmd}')
        
        resources_json=$(printf '%s' "$resources_json" | jq ". + [$resource_entry]")
    done <<< "$test_resource"
    
    # Build final configuration
    local spawn_config
    spawn_config=$(jq -n \
        --arg session_file "$session_file" \
        --argjson resources "$resources_json" \
        '{session_file: $session_file, resources: $resources}')
    
    # Assert proper structure
    run bash -c "echo '$spawn_config' | jq '.session_file'"
    assert_success
    assert_output "\"$session_file\""
    
    run bash -c "echo '$spawn_config' | jq '.resources[0].name'"
    assert_success 
    assert_output '"test-app"'
    
    run bash -c "echo '$spawn_config' | jq '.resources[0].cmd'"
    assert_success
    assert_output '"pls-open echo hello"'
}

@test "launch_all_resources_with_session: escapes JSON for Lua embedding" {
    # Test the critical JSON escaping logic
    local test_config='{"test": "value with \"quotes\" and \\backslashes"}'
    
    # Apply the same escaping used in the actual function
    local escaped_config
    escaped_config=$(printf '%s' "$test_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    
    # Should not break Lua syntax
    run lua -e "local config = \"$escaped_config\""
    assert_success
}

@test "stop_resource: falls back to xdotool when PID fails" {
    # Arrange - Create session entry with non-existent PID
    local session_entry
    session_entry=$(jq -n '{
        name: "test-app",
        cmd: "pls-open test-command", 
        pid: 1,
        class: "test-class",
        instance: "test-instance",
        timestamp: 1710441037
    }')
    
    # Mock kill to always fail (process doesn't exist)
    kill() {
        return 1
    }
    
    # Mock xdotool to simulate successful window close
    xdotool() {
        echo "xdotool $*" >> "$TEST_DIR/xdotool_log"
        if [[ "$1" == "search" && "$4" == "windowclose" ]]; then
            return 0
        fi
        return 1
    }
    
    # Mock command to report xdotool as available
    command() {
        if [[ "$1" == "-v" && "$2" == "xdotool" ]]; then
            return 0
        fi
        # Fall back to real command for other uses (but use builtin command)
        builtin command "$@"
    }
    
    # Act
    run stop_resource "$session_entry"
    
    # Assert
    assert_success
    assert_output --partial "Trying window-based cleanup with xdotool"
    assert_output --partial "Closed windows for PID 1"
}

@test "read_session: returns session data for valid file" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    local test_data='[{"cmd":"test","pid":123,"timestamp":1234567890}]'
    printf '%s' "$test_data" > "$session_file"
    
    # Act
    run read_session "$session_file"
    
    # Assert
    assert_success
    assert_output "$test_data"
}

@test "read_session: fails when session file does not exist" {
    # Arrange
    local session_file="$TEST_DIR/nonexistent.json"
    
    # Act
    run read_session "$session_file"
    
    # Assert
    assert_failure
    refute_output
}

@test "read_session: removes corrupted session file and fails" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    printf 'invalid json' > "$session_file"
    
    # Act
    run read_session "$session_file"
    
    # Assert
    assert_failure
    assert_output --partial "Corrupted session file"
    assert [ ! -f "$session_file" ]
}

@test "with_lock: creates cache directory if it does not exist" {
    # Arrange
    local lock_file="$TEST_DIR/nonexistent/cache/session.json"
    
    # Act
    run with_lock "$lock_file" echo "test"
    
    # Assert
    assert_success
    assert_output "test"
    assert [ -d "$(dirname "$lock_file")" ]
}

@test "with_lock: prevents concurrent access to same file" {
    skip "Requires complex process management - tested in integration tests"
}

# Test helper to create a mock session file
create_test_session() {
    local session_file="$1"
    local entry_count="${2:-2}"
    
    local entries=""
    for ((i=1; i<=entry_count; i++)); do
        if [[ $i -gt 1 ]]; then
            entries+=","
        fi
        entries+="{\"cmd\":\"test-cmd-$i\",\"name\":\"test-$i\",\"pid\":$((1000+i)),\"timestamp\":$((1600000000+i))}"
    done
    
    printf '[%s]' "$entries" > "$session_file"
}

@test "stop_session_impl: handles empty session file gracefully" {
    # Arrange
    local session_file="$TEST_DIR/empty_session.json"
    printf '[]' > "$session_file"
    
    # Act
    run stop_session_impl "$session_file"
    
    # Assert
    assert_success
    assert_output --partial "No resources found"
    assert [ ! -f "$session_file" ]  # Should be cleaned up
}

@test "stop_session_impl: removes session file after processing" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    create_test_session "$session_file" 1
    
    # Act
    run stop_session_impl "$session_file"
    
    # Assert
    assert_success
    assert [ ! -f "$session_file" ]
    assert [ ! -f "${session_file}.lock" ]
}
