#!/usr/bin/env bats
# Tests for lib/cleanup.sh - Multi-strategy resource cleanup functions

setup() {
    # Create a temporary directory for testing
    TEST_DIR=$(mktemp -d)
    export WORKON_CACHE_DIR="$TEST_DIR/cache"
    
    # Create mock directories
    mkdir -p "$WORKON_CACHE_DIR"
    
    # Mock config_die function for testing
    config_die() {
        printf 'workon: %s\n' "$*" >&2
        exit 2
    }
    export -f config_die
    
    # Mock kill command for testing PID operations
    kill() {
        # Store the signal and PID for verification
        echo "kill $*" >> "$TEST_DIR/kill_log"
        
        # Simulate different behaviors based on test context
        if [[ "$*" == "-0 123" ]] || [[ "$*" == "-0 124" ]]; then
            return 0  # Process exists
        elif [[ "$*" == "-0 999" ]]; then
            return 1  # Process doesn't exist
        elif [[ "$*" == "-TERM 123" ]] || [[ "$*" == "-TERM 124" ]]; then
            return 0  # Successfully sent TERM signal
        elif [[ "$*" == "-KILL 123" ]] || [[ "$*" == "-KILL 124" ]]; then
            return 0  # Successfully sent KILL signal
        else
            return 1  # Default failure
        fi
    }
    export -f kill
    
    # Mock xdotool for testing window management
    xdotool() {
        echo "xdotool $*" >> "$TEST_DIR/xdotool_log"
        
        # Simulate successful window operations
        if [[ "$*" == "search --pid 123 windowclose" ]]; then
            echo "Found window for PID 123"
            return 0
        elif [[ "$*" == "search --pid 999 windowclose" ]]; then
            echo "Found window for PID 999"
            return 0
        elif [[ "$*" == "search --class TestApp windowclose" ]]; then
            echo "Found window for class TestApp"
            return 0
        elif [[ "$*" == "search --classname test-instance windowclose" ]]; then
            echo "Found window for instance test-instance"
            return 0
        else
            return 1  # No windows found
        fi
    }
    export -f xdotool
    
    # Mock wmctrl for fallback window management
    wmctrl() {
        echo "wmctrl $*" >> "$TEST_DIR/wmctrl_log"
        
        if [[ "$*" == "-c TestApp" ]]; then
            echo "Closed window with class TestApp"
            return 0
        else
            return 1
        fi
    }
    export -f wmctrl
    
    # Mock command to control tool availability
    command() {
        if [[ "$1" == "-v" ]]; then
            case "$2" in
                "xdotool") [[ "${MOCK_XDOTOOL_AVAILABLE:-true}" == "true" ]] ;;
                "wmctrl") [[ "${MOCK_WMCTRL_AVAILABLE:-true}" == "true" ]] ;;
                *) /usr/bin/command "$@" ;;
            esac
        else
            /usr/bin/command "$@"
        fi
    }
    export -f command
}

teardown() {
    # Clean up test directory
    [[ -n "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ── cleanup_stop_by_pid() Tests ─────────────────────────────────────────────

@test "cleanup_stop_by_pid: successfully terminates running process" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_pid "123" "test-app" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Using PID 123 for cleanup" ]]
    
    # Verify TERM signal was sent
    [[ -f "$TEST_DIR/kill_log" ]]
    grep -q "kill -TERM 123" "$TEST_DIR/kill_log"
}

@test "cleanup_stop_by_pid: force kills stubborn process" {
    source lib/cleanup.sh
    
    # Mock kill to simulate process that survives TERM signal
    kill() {
        echo "kill $*" >> "$TEST_DIR/kill_log"
        if [[ "$*" == "-0 124" ]]; then
            return 0  # Process still exists after TERM
        elif [[ "$*" == "-TERM 124" ]]; then
            return 0  # TERM signal sent successfully
        elif [[ "$*" == "-KILL 124" ]]; then
            return 0  # KILL signal sent successfully
        fi
        return 1
    }
    export -f kill
    
    run cleanup_stop_by_pid "124" "stubborn-app" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Force killing PID 124" ]]
    
    # Verify both TERM and KILL signals were sent
    grep -q "kill -TERM 124" "$TEST_DIR/kill_log"
    grep -q "kill -KILL 124" "$TEST_DIR/kill_log"
}

@test "cleanup_stop_by_pid: fails for non-existent process" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_pid "999" "missing-app" 2>&1
    [[ $status -eq 1 ]]
    [[ ! "$output" =~ "Using PID" ]]
}

@test "cleanup_stop_by_pid: handles empty or zero PID" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_pid "" "empty-pid-app" 2>&1
    [[ $status -eq 1 ]]
    
    run cleanup_stop_by_pid "0" "zero-pid-app" 2>&1
    [[ $status -eq 1 ]]
}

# ── cleanup_stop_by_xdotool() Tests ─────────────────────────────────────────

@test "cleanup_stop_by_xdotool: closes window by PID" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_xdotool "123" "TestApp" "test-instance" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Trying window-based cleanup with xdotool" ]]
    [[ "$output" =~ "Closed windows for PID 123" ]]
    
    # Verify xdotool was called correctly
    [[ -f "$TEST_DIR/xdotool_log" ]]
    grep -q "xdotool search --pid 123 windowclose" "$TEST_DIR/xdotool_log"
}

@test "cleanup_stop_by_xdotool: falls back to window class" {
    source lib/cleanup.sh
    
    # Mock xdotool to fail on PID but succeed on class
    xdotool() {
        echo "xdotool $*" >> "$TEST_DIR/xdotool_log"
        if [[ "$*" == "search --pid 456 windowclose" ]]; then
            return 1  # PID search fails
        elif [[ "$*" == "search --class TestApp windowclose" ]]; then
            echo "Found window for class TestApp"
            return 0  # Class search succeeds
        fi
        return 1
    }
    export -f xdotool
    
    run cleanup_stop_by_xdotool "456" "TestApp" "test-instance" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Closed windows with class \"TestApp\"" ]]
}

@test "cleanup_stop_by_xdotool: falls back to window instance" {
    source lib/cleanup.sh
    
    # Mock xdotool to fail on PID and class but succeed on instance
    xdotool() {
        echo "xdotool $*" >> "$TEST_DIR/xdotool_log"
        if [[ "$*" == "search --classname test-instance windowclose" ]]; then
            echo "Found window for instance test-instance"
            return 0
        fi
        return 1
    }
    export -f xdotool
    
    run cleanup_stop_by_xdotool "789" "FailClass" "test-instance" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Closed windows with instance \"test-instance\"" ]]
}

@test "cleanup_stop_by_xdotool: fails when xdotool not available" {
    source lib/cleanup.sh
    
    export MOCK_XDOTOOL_AVAILABLE="false"
    
    run cleanup_stop_by_xdotool "123" "TestApp" "test-instance" 2>&1
    [[ $status -eq 1 ]]
    [[ ! "$output" =~ "xdotool" ]]
}

@test "cleanup_stop_by_xdotool: fails when no windows found" {
    source lib/cleanup.sh
    
    # Mock xdotool to always fail
    xdotool() {
        echo "xdotool $*" >> "$TEST_DIR/xdotool_log"
        return 1
    }
    export -f xdotool
    
    run cleanup_stop_by_xdotool "999" "NonExistentApp" "missing-instance" 2>&1
    [[ $status -eq 1 ]]
}

# ── cleanup_stop_by_wmctrl() Tests ──────────────────────────────────────────

@test "cleanup_stop_by_wmctrl: closes window by class name" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_wmctrl "TestApp" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Trying wmctrl fallback" ]]
    [[ "$output" =~ "Closed window with wmctrl (class: TestApp)" ]]
    
    # Verify wmctrl was called correctly
    [[ -f "$TEST_DIR/wmctrl_log" ]]
    grep -q "wmctrl -c TestApp" "$TEST_DIR/wmctrl_log"
}

@test "cleanup_stop_by_wmctrl: fails when wmctrl not available" {
    source lib/cleanup.sh
    
    export MOCK_WMCTRL_AVAILABLE="false"
    
    run cleanup_stop_by_wmctrl "TestApp" 2>&1
    [[ $status -eq 1 ]]
    [[ ! "$output" =~ "wmctrl" ]]
}

@test "cleanup_stop_by_wmctrl: fails when no window found" {
    source lib/cleanup.sh
    
    # Mock wmctrl to fail
    wmctrl() {
        echo "wmctrl $*" >> "$TEST_DIR/wmctrl_log"
        return 1
    }
    export -f wmctrl
    
    run cleanup_stop_by_wmctrl "NonExistentApp" 2>&1
    [[ $status -eq 1 ]]
}

@test "cleanup_stop_by_wmctrl: handles empty class name" {
    source lib/cleanup.sh
    
    run cleanup_stop_by_wmctrl "" 2>&1
    [[ $status -eq 1 ]]
}

# ── cleanup_stop_resource() Tests ───────────────────────────────────────────

@test "cleanup_stop_resource: stops resource using PID strategy" {
    source lib/cleanup.sh
    
    local resource_entry='{"pid": 123, "class": "TestApp", "instance": "test-instance", "name": "Test Application"}'
    
    run cleanup_stop_resource "$resource_entry" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Stopping Test Application (PID: 123)" ]]
    [[ "$output" =~ "Using PID 123 for cleanup" ]]
}

@test "cleanup_stop_resource: falls back to xdotool when PID fails" {
    source lib/cleanup.sh
    
    # Mock kill to always fail (process doesn't exist)
    kill() {
        echo "kill $*" >> "$TEST_DIR/kill_log"
        return 1
    }
    export -f kill
    
    local resource_entry='{"pid": 999, "class": "TestApp", "instance": "test-instance", "name": "Test Application"}'
    
    run cleanup_stop_resource "$resource_entry" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Trying window-based cleanup with xdotool" ]]
    [[ "$output" =~ "Closed windows for PID 999" ]]
}

@test "cleanup_stop_resource: falls back to wmctrl when xdotool fails" {
    source lib/cleanup.sh
    
    # Mock kill and xdotool to fail
    kill() {
        return 1
    }
    export -f kill
    
    xdotool() {
        return 1
    }
    export -f xdotool
    
    local resource_entry='{"pid": 999, "class": "TestApp", "instance": "test-instance", "name": "Test Application"}'
    
    run cleanup_stop_resource "$resource_entry" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Trying wmctrl fallback" ]]
    [[ "$output" =~ "Closed window with wmctrl (class: TestApp)" ]]
}

@test "cleanup_stop_resource: fails when all strategies fail" {
    source lib/cleanup.sh
    
    # Mock all cleanup methods to fail
    kill() { return 1; }
    xdotool() { return 1; }
    wmctrl() { return 1; }
    export -f kill xdotool wmctrl
    
    local resource_entry='{"pid": 999, "class": "FailApp", "instance": "fail-instance", "name": "Failing Application"}'
    
    run cleanup_stop_resource "$resource_entry" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Warning: Could not stop Failing Application" ]]
}

@test "cleanup_stop_resource: handles malformed JSON gracefully" {
    source lib/cleanup.sh
    
    local invalid_entry='invalid json'
    
    run cleanup_stop_resource "$invalid_entry" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Stopping unknown (PID: unknown)" ]]
}

# ── cleanup_stop_session() Tests ────────────────────────────────────────────

@test "cleanup_stop_session: stops all resources in session" {
    source lib/cleanup.sh
    
    # Create a test session file
    local session_file="$TEST_DIR/test-session.json"
    cat > "$session_file" << 'EOF'
[
    {"pid": 123, "class": "App1", "instance": "app1", "name": "Application 1"},
    {"pid": 124, "class": "App2", "instance": "app2", "name": "Application 2"}
]
EOF
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Stopping 2 resources" ]]
    [[ "$output" =~ "Successfully stopped 2/2 resources" ]]
    
    # Verify session file was removed
    [[ ! -f "$session_file" ]]
}

@test "cleanup_stop_session: handles empty session file" {
    source lib/cleanup.sh
    
    local session_file="$TEST_DIR/empty-session.json"
    echo '[]' > "$session_file"
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "No resources found in session" ]]
    
    # Verify session file was still removed
    [[ ! -f "$session_file" ]]
}

@test "cleanup_stop_session: handles non-existent session file" {
    source lib/cleanup.sh
    
    local session_file="$TEST_DIR/missing-session.json"
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Warning: No valid session data found" ]]
}

@test "cleanup_stop_session: handles corrupted session file" {
    source lib/cleanup.sh
    
    local session_file="$TEST_DIR/corrupted-session.json"
    echo "invalid json content" > "$session_file"
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 1 ]]
    [[ "$output" =~ "Warning: No valid session data found" ]]
}

@test "cleanup_stop_session: reports partial success when some resources fail" {
    source lib/cleanup.sh
    
    # Mock to make second resource fail
    kill() {
        echo "kill $*" >> "$TEST_DIR/kill_log"
        if [[ "$*" == *"123"* ]]; then
            return 0  # First resource succeeds
        else
            return 1  # Second resource fails
        fi
    }
    export -f kill
    
    # Mock other cleanup methods to fail
    xdotool() { return 1; }
    wmctrl() { return 1; }
    export -f xdotool wmctrl
    
    local session_file="$TEST_DIR/partial-session.json"
    cat > "$session_file" << 'EOF'
[
    {"pid": 123, "class": "App1", "name": "Application 1"},
    {"pid": 124, "class": "App2", "name": "Application 2"}
]
EOF
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Successfully stopped 1/2 resources" ]]
}

# ── Integration Tests ───────────────────────────────────────────────────────

@test "cleanup module: complete multi-strategy cleanup workflow" {
    source lib/cleanup.sh
    
    # Create a complex session with various resource types
    local session_file="$TEST_DIR/complex-session.json"
    cat > "$session_file" << 'EOF'
[
    {"pid": 123, "class": "Editor", "instance": "vscode", "name": "VS Code"},
    {"pid": 999, "class": "Browser", "instance": "firefox", "name": "Firefox"},
    {"pid": 0, "class": "Terminal", "instance": "gnome-terminal", "name": "Terminal"}
]
EOF
    
    # First resource should succeed via PID
    # Second resource should fail PID but succeed via xdotool
    # Third resource should fail PID and xdotool but succeed via wmctrl
    
    # Mock behaviors for different resources
    kill() {
        if [[ "$*" == *"123"* ]]; then
            return 0  # VS Code PID cleanup succeeds
        fi
        return 1  # Other PIDs fail
    }
    export -f kill
    
    xdotool() {
        if [[ "$*" == *"Browser"* ]]; then
            return 0  # Firefox window cleanup succeeds
        fi
        return 1  # Other window operations fail
    }
    export -f xdotool
    
    wmctrl() {
        if [[ "$*" == *"Terminal"* ]]; then
            return 0  # Terminal wmctrl cleanup succeeds
        fi
        return 1  # Other wmctrl operations fail
    }
    export -f wmctrl
    
    run cleanup_stop_session "$session_file" 2>&1
    [[ $status -eq 0 ]]
    [[ "$output" =~ "Successfully stopped 3/3 resources" ]]
    [[ "$output" =~ "Using PID 123 for cleanup" ]]
    [[ "$output" =~ "Trying window-based cleanup with xdotool" ]]
    [[ "$output" =~ "Trying wmctrl fallback" ]]
}