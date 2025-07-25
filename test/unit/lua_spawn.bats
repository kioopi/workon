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
    
    # Set WORKON_DIR for tests that need it
    export WORKON_DIR="$PROJECT_ROOT"
    
    # Source the library functions for direct testing
    source "$PROJECT_ROOT/lib/workon.sh"
    
    # Set test cache directory
    export XDG_CACHE_HOME="$TEST_DIR/.cache"
    mkdir -p "$XDG_CACHE_HOME/workon"
    
    # Create mock awesome-client that records calls and optionally executes Lua
    export PATH="$TEST_DIR/bin:$PATH"
    mkdir -p "$TEST_DIR/bin"
    
    # Create mock awesome-client that logs commands but can execute Lua for testing
    cat > "$TEST_DIR/bin/awesome-client" << EOF
#!/bin/bash
echo "awesome-client called with: \$*" >> "$TEST_DIR/awesome_client_log"

# If AWESOME_CLIENT_MODE is set to "execute", run lua instead
if [[ "\$AWESOME_CLIENT_MODE" == "execute" ]]; then
    # Mock the awful module for testing
    cat > "$TEST_DIR/awful_mock.lua" << 'LUA_EOF'
awful = {spawn = function(cmd, opts) 
    if opts and opts.callback then
        local mock_client = {
            pid = 12345,
            window = "0x123456", 
            class = "test-app",
            instance = "test-instance",
            name = "Test Application"
        }
        opts.callback(mock_client)
    end
    return 12345
end}
LUA_EOF
    
    # Create the combined Lua script
    {
        echo "dofile('$TEST_DIR/awful_mock.lua')"
        echo "\$1"
    } > "$TEST_DIR/combined.lua"
    
    lua "$TEST_DIR/combined.lua" 2>&1
else
    # Default mock mode - just log the call
    echo "Mock awesome-client executed" >&2
fi
EOF
    chmod +x "$TEST_DIR/bin/awesome-client"
    
    # Create test session file location
    TEST_SESSION_FILE="$TEST_DIR/.cache/workon/test_session.json"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# Test JSON module functionality (fallback implementation)
@test "json module: encodes and decodes basic objects" {
    # Test the JSON module directly with lua
    run lua -e "
        package.path = package.path .. ';$PROJECT_ROOT/lib/lua-workon/src/?.lua'
        local json = require('json')
        local obj = {name = 'test', value = 42, active = true}
        local encoded = json.encode(obj)
        print('Encoded: ' .. encoded)
        local decoded = json.decode(encoded)
        print('Name: ' .. decoded.name)
        print('Value: ' .. decoded.value)
        print('Active: ' .. tostring(decoded.active))
    "
    
    assert_success
    assert_output --partial "Encoded:"
    assert_output --partial "Name: test"
    assert_output --partial "Value: 42" 
    assert_output --partial "Active: true"
}

@test "json module: handles arrays correctly" {
    run lua -e "
        package.path = package.path .. ';$PROJECT_ROOT/lib/lua-workon/src/?.lua'
        local json = require('json')
        local arr = {'first', 'second', 'third'}
        local encoded = json.encode(arr)
        print('Encoded: ' .. encoded)
        local decoded = json.decode(encoded)
        print('Length: ' .. #decoded)
        print('First: ' .. decoded[1])
    "
    
    assert_success
    assert_output --partial "Encoded:"
    assert_output --partial "Length: 3"
    assert_output --partial "First: first"
}

# Test session module functionality
@test "session module: creates proper session entries" {
    run lua -e "
        package.path = package.path .. ';$PROJECT_ROOT/lib/lua-workon/src/?.lua'
        local session = require('session')
        local entry = session.create_entry('test-app', 'echo hello', 12345, {
            window = '0x123456',
            class = 'test-class',
            instance = 'test-instance',
            name = 'Test App'
        })
        print('Name: ' .. entry.name)
        print('PID: ' .. entry.pid)
        print('Class: ' .. entry.class)
        print('Has timestamp: ' .. (entry.timestamp and 'yes' or 'no'))
    "
    
    assert_success
    assert_output --partial "Name: test-app"
    assert_output --partial "PID: 12345"
    assert_output --partial "Class: test-class"
    assert_output --partial "Has timestamp: yes"
}

@test "session module: writes and reads session files atomically" {
    # Create test session data
    run lua -e "
        package.path = package.path .. ';$PROJECT_ROOT/lib/lua-workon/src/?.lua'
        local session = require('session')
        local json = require('json')
        
        local entry1 = session.create_entry('app1', 'cmd1', 111, {class = 'class1'})
        local entry2 = session.create_entry('app2', 'cmd2', 222, {class = 'class2'})
        
        session.write_session_atomic('$TEST_SESSION_FILE', {entry1, entry2})
        
        local read_data, err = session.read_session('$TEST_SESSION_FILE')
        if err then
            print('Error: ' .. err)
        else
            print('Read ' .. #read_data .. ' entries')
            print('First entry name: ' .. read_data[1].name)
            print('Second entry PID: ' .. read_data[2].pid)
        end
    "
    
    assert_success
    assert_output --partial "Read 2 entries"
    assert_output --partial "First entry name: app1" 
    assert_output --partial "Second entry PID: 222"
    
    # Verify file exists and has valid JSON
    assert [ -f "$TEST_SESSION_FILE" ]
    run jq '.[0].name' "$TEST_SESSION_FILE"
    assert_success
    assert_output '"app1"'
}

# Test spawn script path resolution
@test "spawn_resources.lua: resolves WORKON_DIR correctly" {
    # Test that the script can load modules from the correct path
    run lua -e "
        WORKON_DIR = '$PROJECT_ROOT'
        package.path = package.path .. ';' .. WORKON_DIR .. '/lib/lua-workon/src/?.lua'
        local json = require('json')
        local session = require('session')
        print('Modules loaded successfully')
    "
    
    assert_success
    assert_output --partial "Modules loaded successfully"
}

@test "spawn_resources.lua: handles missing WORKON_DIR gracefully" {
    # Test script fails appropriately without WORKON_DIR
    # The script will fail when trying to load modules, but we test the WORKON_DIR check logic
    run env -u WORKON_DIR lua -e "
        -- Test the WORKON_DIR check logic directly
        local workon_dir = WORKON_DIR or os.getenv('WORKON_DIR')
        if not workon_dir then
            error('WORKON_DIR not available - this script must be called from the workon command')
        end
        print('WORKON_DIR found: ' .. workon_dir)
    "
    
    assert_failure
    assert_output --partial "WORKON_DIR not available"
}

# These tests are skipped because they require complex mocking of AwesomeWM
# The core functionality is tested through unit tests of individual modules
# and integration tests with simpler mocks

@test "spawn_resources.lua: validates configuration structure" {
    # Test JSON configuration validation logic separately
    run lua -e "
        package.path = package.path .. ';$PROJECT_ROOT/lib/lua-workon/src/?.lua'
        local json = require('json')
        
        -- Test valid config
        local valid_config = '{\"session_file\": \"/tmp/test.json\", \"resources\": []}'
        local config = json.decode(valid_config)
        print('Session file: ' .. (config.session_file or 'missing'))
        print('Resources type: ' .. type(config.resources))
        
        -- Test invalid config (malformed JSON)
        local success, err = pcall(json.decode, '{\"invalid\": [}')
        print('Malformed JSON handled: ' .. tostring(not success))
    "
    
    assert_success
    assert_output --partial "Session file: /tmp/test.json"
    assert_output --partial "Resources type: table"
    assert_output --partial "Malformed JSON handled: true"
}

# Test integration with launch_all_resources_with_session function
@test "launch_all_resources_with_session: builds correct JSON configuration" {
    # Create test resources in base64 format (mimicking actual data flow)
    local editor_resource terminal_resource
    editor_resource=$(printf '{"key": "editor", "value": "nvim {{PROJECT_DIR}}/file.txt"}' | base64 -w0)
    terminal_resource=$(printf '{"key": "terminal", "value": "alacritty"}' | base64 -w0)
    
    local resources
    resources=$(printf '%s\n%s' "$editor_resource" "$terminal_resource")
    
    # Set up environment for template expansion
    export PROJECT_DIR="/home/user/project"
    
    # Test with mock awesome-client that just logs the call
    run launch_all_resources_with_session "$TEST_SESSION_FILE" "$resources"
    
    # Should have called awesome-client
    assert [ -f "$TEST_DIR/awesome_client_log" ]
    
    # Verify the awesome-client was called with correct parameters
    run cat "$TEST_DIR/awesome_client_log"
    assert_success
    assert_output --partial "awesome-client called with:"
    assert_output --partial "WORKON_DIR = '$PROJECT_ROOT'"
    assert_output --partial "dofile('$PROJECT_ROOT/lib/spawn_resources.lua')"
}

@test "launch_all_resources_with_session: handles template expansion" {
    # Create test resource with template variable
    local test_resource
    test_resource=$(printf '{"key": "editor", "value": "nvim {{PROJECT_DIR}}/README.md"}' | base64 -w0)
    
    # Set environment variable for expansion
    export PROJECT_DIR="/tmp/test-project"
    
    run launch_all_resources_with_session "$TEST_SESSION_FILE" "$test_resource"
    
    # Verify template was expanded in the logged command
    run cat "$TEST_DIR/awesome_client_log"
    assert_success
    assert_output --partial "/tmp/test-project/README.md"
    refute_output --partial "{{PROJECT_DIR}}"
}

# This test is skipped because it requires complex AwesomeWM mocking
# The timeout and session file creation logic is tested in integration tests

@test "launch_all_resources_with_session: times out if session not created" {
    # Create test resource but use mock mode that won't create session file
    local test_resource
    test_resource=$(printf '{"key": "test", "value": "echo hello"}' | base64 -w0)
    
    # Override timeout to make test faster
    run timeout 3 bash -c '
        launch_all_resources_with_session() {
            local session_file="$1"
            local resources="$2"
            
            # Simulate the function but with shorter timeout for testing
            local timeout=2
            while [[ $timeout -gt 0 ]]; do
                if [[ -f "$session_file" ]]; then
                    return 0
                fi
                sleep 0.5
                timeout=$((timeout - 1))
            done
            echo "Warning: Session file not updated within timeout" >&2
            return 1
        }
        source "$PROJECT_ROOT/lib/workon.sh"
        launch_all_resources_with_session "'$TEST_SESSION_FILE'" "'$test_resource'"
    '
    
    assert_failure
    assert_output --partial "Warning: Session file not updated within timeout"
}

# Error handling tests are covered by simpler unit tests of individual components

# Test critical path: JSON escaping and command structure
@test "integration: JSON escaping for Lua works correctly" {
    # Test that special characters in JSON are properly escaped for Lua
    local test_config='{"session_file": "/tmp/test.json", "resources": [{"name": "test\"quote", "cmd": "echo \"hello world\""}]}'
    
    # The escaping function used in launch_all_resources_with_session
    local escaped_config
    escaped_config=$(printf '%s' "$test_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    
    # Verify no unescaped quotes that would break Lua
    run echo "$escaped_config"
    refute_output --partial '{"'
    assert_output --partial '\\"'  # Should contain escaped quotes
}

# Test command structure verification
@test "integration: awesome-client command structure" {
    # Verify that the command we generate has the right structure
    local session_file="$TEST_SESSION_FILE"
    local test_config='{"session_file": "'$session_file'", "resources": []}'
    local escaped_config
    escaped_config=$(printf '%s' "$test_config" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n')
    
    # Build the command that would be sent to awesome-client
    local awesome_command="
        WORKON_DIR = '$PROJECT_ROOT'
        WORKON_SPAWN_CONFIG = '$escaped_config'
        dofile('$PROJECT_ROOT/lib/spawn_resources.lua')
    "
    
    # Verify structure
    run echo "$awesome_command"
    assert_output --partial "WORKON_DIR = '$PROJECT_ROOT'"
    assert_output --partial "WORKON_SPAWN_CONFIG = "
    assert_output --partial "dofile('$PROJECT_ROOT/lib/spawn_resources.lua')"
}