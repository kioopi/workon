#!/usr/bin/env bats
# Tests for lib/session.sh - Session management functions

setup() {
    # Create a temporary directory for testing
    TEST_DIR=$(mktemp -d)
    export WORKON_CACHE_DIR="$TEST_DIR/cache"
    
    # Source the session module (once it exists)
    # For now, we'll prepare the test structure
    mkdir -p "$WORKON_CACHE_DIR"
    
    # Mock config_die function for testing
    config_die() {
        printf 'workon: %s\n' "$*" >&2
        exit 2
    }
    export -f config_die
}

teardown() {
    # Clean up test directory
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ── session_read() Tests ────────────────────────────────────────────────────

@test "session_read: returns 1 for non-existent file" {
    source lib/session.sh
    
    run session_read "$TEST_DIR/nonexistent.json"
    [[ $status -eq 1 ]]
}

@test "session_read: validates JSON format and returns valid data" {
    source lib/session.sh
    
    # Create valid session file
    local session_file="$TEST_DIR/valid.json"
    cat > "$session_file" << 'EOF'
[
    {
        "pid": 1234,
        "class": "TestApp",
        "instance": "test-instance",
        "name": "Test Application"
    }
]
EOF
    
    run session_read "$session_file"
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Test Application" ]]
}

@test "session_read: removes corrupted session file and returns 1" {
    source lib/session.sh
    
    # Create invalid JSON file
    local session_file="$TEST_DIR/corrupted.json"
    echo "invalid json content" > "$session_file"
    
    run session_read "$session_file"
    [[ $status -eq 1 ]]
    [[ ! -f "$session_file" ]]
    [[ "${lines[0]}" =~ "Corrupted session file" ]]
}

@test "session_read: handles empty array correctly" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/empty.json"
    echo '[]' > "$session_file"
    
    run session_read "$session_file"
    [[ $status -eq 0 ]]
    [[ "$output" == "[]" ]]
}

# ── session_write_atomic() Tests ────────────────────────────────────────────

@test "session_write_atomic: writes data atomically" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/atomic.json"
    local test_data='[{"pid": 1234, "name": "test"}]'
    
    run session_write_atomic "$session_file" "$test_data"
    [[ $status -eq 0 ]]
    [[ -f "$session_file" ]]
    
    # Verify content
    local content
    content=$(cat "$session_file")
    [[ "$content" == "$test_data" ]]
}

@test "session_write_atomic: creates parent directory if needed" {
    source lib/session.sh
    
    local nested_file="$TEST_DIR/nested/deep/session.json"
    local test_data='[]'
    
    run session_write_atomic "$nested_file" "$test_data"
    [[ $status -eq 0 ]]
    [[ -f "$nested_file" ]]
}

@test "session_write_atomic: fails gracefully on write error" {
    source lib/session.sh
    
    # Try to write to read-only directory
    local readonly_dir="$TEST_DIR/readonly"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir"
    
    run session_write_atomic "$readonly_dir/session.json" '[]'
    [[ $status -eq 1 ]]
    # Should contain an error message about writing
    [[ "$output" =~ "Cannot write session file" ]]
    
    # Cleanup
    chmod 755 "$readonly_dir"
}

# ── session_with_lock() Tests ───────────────────────────────────────────────

@test "session_with_lock: executes command with file lock" {
    source lib/session.sh
    
    local lock_file="$TEST_DIR/test.lock"
    local output_file="$TEST_DIR/output.txt"
    
    run session_with_lock "$lock_file" sh -c "echo 'locked command' > '$output_file'"
    [[ $status -eq 0 ]]
    [[ -f "$output_file" ]]
    [[ "$(cat "$output_file")" == "locked command" ]]
}

@test "session_with_lock: creates cache directory if needed" {
    source lib/session.sh
    
    local deep_lock="$TEST_DIR/deep/nested/test.lock"
    
    run session_with_lock "$deep_lock" true
    [[ $status -eq 0 ]]
    [[ -d "$(dirname "$deep_lock")" ]]
}

@test "session_with_lock: propagates command exit code" {
    source lib/session.sh
    
    local lock_file="$TEST_DIR/test.lock"
    
    run session_with_lock "$lock_file" sh -c "exit 42"
    [[ $status -eq 42 ]]
}

@test "session_with_lock: prevents concurrent access" {
    source lib/session.sh
    
    local lock_file="$TEST_DIR/concurrent.lock"
    local output_file="$TEST_DIR/concurrent.txt"
    
    # Test that flock prevents concurrent execution by running second command
    # only after first one completes
    {
        session_with_lock "$lock_file" sh -c "echo 'first' >> '$output_file'; sleep 0.1"
        session_with_lock "$lock_file" sh -c "echo 'second' >> '$output_file'"
    }
    
    # Verify sequential execution order
    local content
    content=$(cat "$output_file")
    [[ "$content" == $'first\nsecond' ]]
}

# ── session_get_valid_data() Tests ──────────────────────────────────────────

@test "session_get_valid_data: returns 1 for non-existent file" {
    source lib/session.sh
    
    run session_get_valid_data "$TEST_DIR/nonexistent.json"
    [[ $status -eq 1 ]]
}

@test "session_get_valid_data: returns valid session data" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/valid.json"
    echo '[{"pid": 1234, "name": "test"}]' > "$session_file"
    
    run session_get_valid_data "$session_file"
    [[ $status -eq 0 ]]
    [[ "$output" =~ "test" ]]
}

@test "session_get_valid_data: handles corrupted files" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/corrupted.json"
    echo "invalid json" > "$session_file"
    
    run session_get_valid_data "$session_file"
    [[ $status -eq 1 ]]
}

# ── Integration Tests ───────────────────────────────────────────────────────

@test "session module: complete write-read cycle" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/cycle.json"
    local test_data='[{"pid": 1234, "name": "test", "class": "TestApp"}]'
    
    # Write data
    run session_write_atomic "$session_file" "$test_data"
    [[ $status -eq 0 ]]
    
    # Read it back
    run session_read "$session_file"
    [[ $status -eq 0 ]]
    [[ "$output" == "$test_data" ]]
}

@test "session module: atomic operations with concurrent access" {
    source lib/session.sh
    
    local session_file="$TEST_DIR/atomic.json"
    local lock_file="$TEST_DIR/atomic.lock"
    
    # Simulate concurrent writes
    session_with_lock "$lock_file" session_write_atomic "$session_file" '[{"id": 1}]' &
    session_with_lock "$lock_file" session_write_atomic "$session_file" '[{"id": 2}]' &
    
    wait
    
    # File should exist and contain valid JSON
    [[ -f "$session_file" ]]
    run jq -e 'type == "array"' "$session_file"
    [[ $status -eq 0 ]]
}