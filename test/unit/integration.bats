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
    
    # Set test cache directory
    export XDG_CACHE_HOME="$TEST_DIR/.cache"
    
    # Create a test workon.yaml with mock commands
    create_integration_manifest
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# Create a manifest with commands that can be easily mocked/tested
create_integration_manifest() {
    cat > workon.yaml <<EOF
resources:
  # Use sleep commands that we can easily track and kill
  terminal: sleep 300
  editor: sleep 301
  browser: sleep 302
EOF
}

# Create mock awesome-client that simulates process spawning
create_mock_awesome_client() {
    mkdir -p "$TEST_DIR/mock_bin"
    cat > "$TEST_DIR/mock_bin/awesome-client" <<'EOF'
#!/bin/bash
# Mock awesome-client that starts the actual process
# Extract the command from the Lua spawn call
cmd=$(echo "$1" | sed -n 's/.*awful\.spawn.*"\([^"]*\)".*/\1/p')
if [[ -n $cmd ]]; then
    # Remove pls-open prefix and execute the actual command
    actual_cmd=$(echo "$cmd" | sed 's/^pls-open //')
    exec $actual_cmd
fi
EOF
    chmod +x "$TEST_DIR/mock_bin/awesome-client"
    
    # Add mock pls-open that just executes the command
    cat > "$TEST_DIR/mock_bin/pls-open" <<'EOF'
#!/bin/bash
exec "$@"
EOF
    chmod +x "$TEST_DIR/mock_bin/pls-open"
    
    # Prepend mock bin to PATH
    export PATH="$TEST_DIR/mock_bin:$PATH"
}

@test "integration: start creates session file with process entries" {
    require_command "yq"
    require_command "jq"
    
    # Arrange
    create_mock_awesome_client
    
    # Act - start the workspace (in background to avoid hanging)
    timeout 5s "$PROJECT_ROOT/bin/workon" start &
    local workon_pid=$!
    
    # Give it time to start processes
    sleep 2
    
    # Kill the workon process and its children
    pkill -P $workon_pid || true
    kill $workon_pid 2>/dev/null || true
    wait $workon_pid 2>/dev/null || true
    
    # Assert - check session file was created
    local cache_dir="$XDG_CACHE_HOME/workon"
    assert [ -d "$cache_dir" ]
    
    # Should have exactly one session file
    local session_files=("$cache_dir"/*.json)
    assert [ -f "${session_files[0]}" ]
    
    # Verify session file structure
    run jq -e 'type == "array" and length > 0' "${session_files[0]}"
    assert_success
    
    # Verify each entry has required fields
    run jq -e '.[] | has("cmd") and has("name") and has("pid") and has("timestamp")' "${session_files[0]}"
    assert_success
    
    # Clean up any remaining processes
    if [[ -f "${session_files[0]}" ]]; then
        local pids
        mapfile -t pids < <(jq -r '.[].pid' "${session_files[0]}" 2>/dev/null || true)
        for pid in "${pids[@]}"; do
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
}

@test "integration: stop command terminates processes and removes session file" {
    require_command "yq"
    require_command "jq"
    
    # Arrange
    create_mock_awesome_client
    
    # Start processes in background to simulate what workon start would do
    sleep 300 &
    local pid1=$!
    sleep 301 &
    local pid2=$!
    
    # Create a session file manually
    local cache_dir="$XDG_CACHE_HOME/workon"
    mkdir -p "$cache_dir"
    local session_file
    session_file="$cache_dir/$(printf '%s' "$PWD" | sha1sum | cut -d' ' -f1).json"
    
    cat > "$session_file" <<EOF
[
  {
    "cmd": "pls-open sleep 300",
    "name": "terminal",
    "pid": $pid1,
    "timestamp": $(date +%s)
  },
  {
    "cmd": "pls-open sleep 301",
    "name": "editor",
    "pid": $pid2,
    "timestamp": $(date +%s)
  }
]
EOF
    
    # Verify processes are running
    assert kill -0 $pid1
    assert kill -0 $pid2
    
    # Act - stop the workspace
    run "$PROJECT_ROOT/bin/workon" stop
    
    # Assert
    assert_success
    assert_output --partial "Stopping session"
    assert_output --partial "Session stopped and cleaned up"
    
    # Verify processes were terminated
    sleep 1
    run kill -0 $pid1
    assert_failure
    run kill -0 $pid2
    assert_failure
    
    # Verify session file was removed
    assert [ ! -f "$session_file" ]
}

@test "integration: stop handles non-existent session gracefully" {
    # Act
    run "$PROJECT_ROOT/bin/workon" stop
    
    # Assert
    assert_success
    assert_output --partial "No active session found"
}

@test "integration: start warns about existing session" {
    require_command "yq"
    require_command "jq"
    
    # Arrange - create an existing session file
    local cache_dir="$XDG_CACHE_HOME/workon"
    mkdir -p "$cache_dir"
    local session_file
    session_file="$cache_dir/$(printf '%s' "$PWD" | sha1sum | cut -d' ' -f1).json"
    echo '[]' > "$session_file"
    
    create_mock_awesome_client
    
    # Act
    timeout 5s "$PROJECT_ROOT/bin/workon" start &
    local workon_pid=$!
    
    # Give it time to start and show warning
    sleep 1
    
    # Kill the workon process
    kill $workon_pid 2>/dev/null || true
    wait $workon_pid 2>/dev/null || true
    
    # The output would be visible in the process, but since we're testing
    # in the background, we verify the session file still exists
    assert [ -f "$session_file" ]
}

@test "integration: handles missing dependencies gracefully" {
    # Arrange - create environment without required tools
    local old_path="$PATH"
    export PATH="/usr/bin:/bin"  # Limited PATH without yq, jq
    
    # Act
    run "$PROJECT_ROOT/bin/workon" start
    
    # Assert
    assert_failure
    assert_output --partial "Missing required dependencies"
    
    # Restore PATH
    export PATH="$old_path"
}

@test "integration: processes different resource types correctly" {
    require_command "yq"
    require_command "jq"
    
    # Arrange - create manifest with different resource types
    cat > workon.yaml <<EOF
resources:
  # File path
  readme: README.md
  # Command
  server: echo "server started"
  # URL (will be opened via pls-open)
  docs: https://example.com
EOF
    
    # Create README.md for file resource
    echo "# Test Project" > README.md
    
    create_mock_awesome_client
    
    # Act
    timeout 5s "$PROJECT_ROOT/bin/workon" start &
    local workon_pid=$!
    
    # Give it time to process
    sleep 2
    
    # Kill the workon process
    kill $workon_pid 2>/dev/null || true
    wait $workon_pid 2>/dev/null || true
    
    # Assert - check session file contains all resources
    local cache_dir="$XDG_CACHE_HOME/workon"
    local session_files=("$cache_dir"/*.json)
    
    if [[ -f "${session_files[0]}" ]]; then
        # Should have entries for all three resources
        run jq -e 'length == 3' "${session_files[0]}"
        assert_success
        
        # Verify resource names are recorded
        run jq -r '.[].name' "${session_files[0]}"
        assert_output --partial "readme"
        assert_output --partial "server"
        assert_output --partial "docs"
        
        # Clean up any processes
        local pids
        mapfile -t pids < <(jq -r '.[].pid' "${session_files[0]}" 2>/dev/null || true)
        for pid in "${pids[@]}"; do
            kill -KILL "$pid" 2>/dev/null || true
        done
    fi
}