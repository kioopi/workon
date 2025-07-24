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
    
    # Source the info module (use PROJECT_ROOT from common.bash)
    source "$PROJECT_ROOT/lib/commands/info.sh"
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# ─── info_show_basic tests ───────────────────────────────────────────────

@test "info_show_basic displays WorkOn header" {
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WorkOn - one-shot project workspace bootstrapper" ]]
}

@test "info_show_basic displays version information" {
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Version:" ]]
}

@test "info_show_basic displays directory information" {
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Installation directory:" ]]
    [[ "$output" =~ "Working directory:" ]]
    [[ "$output" =~ "Cache directory:" ]]
}

@test "info_show_basic displays manifest status when found" {
    # Create a test manifest
    create_minimal_manifest
    
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manifest: Found" ]]
    [[ "$output" =~ "workon.yaml" ]]
}

@test "info_show_basic displays manifest status when not found" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manifest: Not found" ]]
}

@test "info_show_basic displays dependency status" {
    run info_show_basic
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Dependencies:" ]]
    [[ "$output" =~ "yq:" ]]
    [[ "$output" =~ "jq:" ]]
    [[ "$output" =~ "awesome-client:" ]]
}

# ─── info_show_sessions_list tests ────────────────────────────────────────

@test "info_show_sessions_list displays header" {
    run info_show_sessions_list
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Active WorkOn Sessions" ]]
    [[ "$output" =~ "=====================" ]]
}

@test "info_show_sessions_list shows no sessions when cache empty" {
    run info_show_sessions_list
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No cache directory found" || "$output" =~ "No active sessions found" ]]
}

@test "info_show_sessions_list shows session count when sessions exist" {
    # Create mock session files
    mkdir -p "$TEST_DIR/.cache/workon"
    echo '[]' > "$TEST_DIR/.cache/workon/project1.json"
    echo '[]' > "$TEST_DIR/.cache/workon/project2.json"
    
    run info_show_sessions_list
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Found 2 active session(s)" ]]
}

# ─── info_show_session_details tests ───────────────────────────────────────

@test "info_show_session_details displays header and project info" {
    run info_show_session_details "$TEST_DIR"
    
    [[ "$output" =~ "WorkOn Session Details" ]]
    [[ "$output" =~ "======================" ]]
    [[ "$output" =~ "📁 Project: $TEST_DIR" ]]
    [[ "$output" =~ "📄 Session file:" ]]
}

@test "info_show_session_details shows error when no session exists" {
    run info_show_session_details "$TEST_DIR"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ No active session found" ]]
}

@test "info_show_session_details shows session info when session exists" {
    # Create mock session file using the correct cache file function
    local session_file
    session_file=$(config_cache_file "$TEST_DIR")
    mkdir -p "$(dirname "$session_file")"
    cat > "$session_file" << 'EOF'
[
    {
        "name": "test_resource",
        "pid": "12345",
        "cmd": "echo hello",
        "class": "Terminal",
        "instance": "test",
        "spawn_time": "2023-01-01T12:00:00Z"
    }
]
EOF
    
    run info_show_session_details "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📦 Resources: 1" ]]
}

# ─── info_route_commands tests ─────────────────────────────────────────────

@test "info_route_commands calls info_show_basic with no arguments" {
    run info_route_commands
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WorkOn - one-shot project workspace bootstrapper" ]]
}

@test "info_route_commands calls info_show_sessions_list with 'sessions' argument" {
    run info_route_commands sessions
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Active WorkOn Sessions" ]]
}

@test "info_route_commands calls info_show_session_details with 'session' argument" {
    run info_route_commands session
    
    [[ "$output" =~ "WorkOn Session Details" ]]
}

@test "info_route_commands shows error for unknown subcommand" {
    run info_route_commands unknown_subcommand
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown info subcommand: unknown_subcommand" ]]
}

@test "info_route_commands passes additional arguments to session details" {
    run info_route_commands session "/some/path"
    
    [[ "$output" =~ "📁 Project: /some/path" ]]
}