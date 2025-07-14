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

@test "json_append: creates new session file with first entry" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    
    # Create JSON entry using jq to ensure proper formatting
    local json_entry
    json_entry=$(jq -n '{cmd: "test", pid: 123, timestamp: 1234567890}')
    
    # Act
    run json_append "$session_file" "$json_entry"
    
    # Assert
    assert_success
    assert [ -f "$session_file" ]
    
    # Verify JSON structure
    run jq -e 'type == "array" and length == 1' "$session_file"
    assert_success
    
    run jq -r '.[0].cmd' "$session_file"
    assert_output "test"
}

@test "json_append: appends to existing session file" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    printf '[{"cmd":"first","pid":100,"timestamp":1000}]' > "$session_file"
    
    # Create JSON entry using jq to ensure proper formatting
    local json_entry
    json_entry=$(jq -n '{cmd: "second", pid: 200, timestamp: 2000}')
    
    # Act
    run json_append "$session_file" "$json_entry"
    
    # Assert
    assert_success
    
    # Verify JSON structure
    run jq -e 'type == "array" and length == 2' "$session_file"
    assert_success
    
    run jq -r '.[1].cmd' "$session_file"
    assert_output "second"
}

@test "json_append: fails with invalid JSON entry" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    local invalid_json='not valid json'
    
    # Act
    run json_append "$session_file" "$invalid_json"
    
    # Assert
    assert_failure
    assert_output --partial "Invalid JSON entry"
}

@test "json_append: recovers from corrupted session file" {
    # Arrange
    local session_file="$TEST_DIR/test_session.json"
    printf 'corrupted json data' > "$session_file"
    
    # Create JSON entry using jq to ensure proper formatting
    local json_entry
    json_entry=$(jq -n '{cmd: "test", pid: 123, timestamp: 1234567890}')
    
    # Act
    run json_append "$session_file" "$json_entry"
    
    # Assert
    assert_success
    
    # Should have reset to valid array with one entry
    run jq -e 'type == "array" and length == 1' "$session_file"
    assert_success
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
    assert_output --partial "No processes found"
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