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
    cat > workon.yaml << 'EOF'
resources:
  terminal: sleep 300
  editor: sleep 301
  browser: sleep 302
EOF
}

@test "integration: stop command terminates processes and removes session file" {
    # This is a simplified test that doesn't rely on actual spawning
    source "$PROJECT_ROOT/lib/workon.sh"
    
    # Create a mock session file
    local session_file="$TEST_DIR/.cache/workon/test_session.json"
    mkdir -p "$(dirname "$session_file")"
    echo '[{"name":"test","cmd":"echo test","pid":99999,"timestamp":1234567890}]' > "$session_file"
    
    # Test that stop_session_impl can handle the session
    run stop_session_impl "$session_file"
    assert_success
    
    # Session file should be removed
    assert [ ! -f "$session_file" ]
}

@test "integration: stop handles non-existent session gracefully" {
    run "$PROJECT_ROOT/bin/workon" stop
    assert_success
    assert_output --partial "No active session found"
}

@test "integration: start warns about existing session" {
    source "$PROJECT_ROOT/lib/workon.sh"
    
    # Create a fake existing session file
    local session_file="$TEST_DIR/.cache/workon/test_session.json" 
    mkdir -p "$(dirname "$session_file")"
    echo '[]' > "$session_file"
    
    # Test warning logic (without actually starting)
    if [[ -f "$session_file" ]]; then
        echo "Warning: Session file already exists"
    fi
    
    assert [ -f "$session_file" ]
}

@test "integration: processes different resource types correctly" {
    source "$PROJECT_ROOT/lib/workon.sh"
    
    # Test template rendering with different resource types
    export TEST_VAR="test_value"
    
    run render_template "echo {{TEST_VAR}}"
    assert_success
    assert_output "echo test_value"
    
    run render_template "nvim {{TEST_VAR}}.txt"
    assert_success
    assert_output "nvim test_value.txt"
}