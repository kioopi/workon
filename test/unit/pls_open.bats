#!/usr/bin/env bats

# Load BATS libraries (system installation paths)
load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Load common test helpers
load '../test_helper/common'

# Test setup
setup() {
    # Create a temporary directory for test files
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Create a minimal test desktop file
    mkdir -p .local/share/applications
    cat > .local/share/applications/test-app.desktop <<EOF
[Desktop Entry]
Name=Test App
Comment=Test application
Exec=echo "test-app executed with: %f"
Icon=test-app
Terminal=false
Type=Application
Categories=Utility;
EOF
    
    # Create a terminal test desktop file
    cat > .local/share/applications/test-terminal.desktop <<EOF
[Desktop Entry]
Name=Test Terminal App
Comment=Test terminal application
Exec=echo "terminal-app executed with: %f"
Icon=test-terminal
Terminal=true
Type=Application
Categories=Utility;
EOF
    
    # Set XDG_DATA_HOME to our test directory
    export XDG_DATA_HOME="$TEST_DIR/.local/share"
    
    # Create a test file
    echo "test content" > test.txt
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

@test "pls-open --help: shows usage information" {
    run "$PROJECT_ROOT/bin/pls-open" --help
    
    assert_failure 1  # usage() exits with 1
    assert_output --partial "Usage:"
    assert_output --partial "pls-open [OPTIONS] <desktop-id|FILE|URL> [FILE]"
    assert_output --partial "Examples:"
}

@test "pls-open --version: shows version information" {
    run "$PROJECT_ROOT/bin/pls-open" --help
    
    assert_output --partial "pls-open 2.5"
}

@test "pls-open with no arguments: shows usage" {
    run "$PROJECT_ROOT/bin/pls-open"
    
    assert_failure 1
    assert_output --partial "Usage:"
}

@test "pls-open --dry-run: shows command without executing" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-app test.txt
    
    assert_success
    assert_output --partial "bash -c"
    assert_output --partial "echo"
    assert_output --partial "test-app\ executed\ with:\ test.txt"
}

@test "pls-open --dry-run with terminal app: shows terminal command" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-terminal test.txt
    
    assert_success
    assert_output --partial "alacritty -e bash -c"
    assert_output --partial "echo"
    assert_output --partial "terminal-app\ executed\ with:\ test.txt"
}

@test "pls-open --dry-run --keep-open with terminal app: shows persistent terminal" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run --keep-open test-terminal test.txt
    
    assert_success
    assert_output --partial "alacritty -e bash -c"
    assert_output --partial "exec\ bash"
}

@test "pls-open --keep-open with non-terminal app: warns and ignores flag" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run --keep-open test-app test.txt
    
    assert_success
    assert_line --partial "Note: --keep-open ignored because Terminal=false"
    refute_output --partial "exec\ bash"
}

@test "pls-open with explicit .desktop file: uses provided desktop file" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run .local/share/applications/test-app.desktop test.txt
    
    assert_success
    assert_output --partial "echo"
    assert_output --partial "test-app\ executed\ with:\ test.txt"
}

@test "pls-open with nonexistent desktop id: fails with error" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run nonexistent-app test.txt
    
    assert_failure 2
    assert_output --partial "Cannot locate desktop file for 'nonexistent-app.desktop'"
}

@test "pls-open with malformed desktop file: fails gracefully" {
    # Create a malformed desktop file
    cat > .local/share/applications/broken.desktop <<EOF
[Desktop Entry]
Name=Broken App
# Missing Exec line
Terminal=false
Type=Application
EOF
    
    run "$PROJECT_ROOT/bin/pls-open" --dry-run broken test.txt
    
    assert_failure 2
    assert_output --partial "No Exec entry"
}

@test "pls-open with unknown option: fails with error" {
    run "$PROJECT_ROOT/bin/pls-open" --unknown-option test-app
    
    assert_failure 2
    assert_output --partial "Unknown option: --unknown-option"
}

@test "pls-open placeholder substitution: replaces %f with filename" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-app test.txt
    
    assert_success
    assert_output --partial "echo"
    assert_output --partial "test-app\ executed\ with:\ test.txt"
}

@test "pls-open placeholder substitution: handles empty filename" {
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-app
    
    assert_success
    assert_output --partial "echo"
    assert_output --partial "test-app\ executed\ with:"
}

@test "pls-open with file that has URL scheme: delegates to xdg-open" {
    skip "Requires xdg-open and proper MIME handling - integration test"
}

@test "pls-open with existing file path: delegates to xdg-open" {
    skip "Requires xdg-open and proper MIME handling - integration test"
}

@test "pls-open respects TERMINAL environment variable" {
    export TERMINAL="custom-terminal"
    
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-terminal test.txt
    
    assert_success
    assert_output --partial "custom-terminal -e bash -c"
}

@test "pls-open falls back to default terminal when TERMINAL unset" {
    unset TERMINAL
    
    run "$PROJECT_ROOT/bin/pls-open" --dry-run test-terminal test.txt
    
    assert_success
    assert_output --partial "/usr/bin/alacritty -e bash -c"
}

@test "pls-open with desktop file containing placeholders: substitutes correctly" {
    # Create desktop file with simple placeholders
    cat > .local/share/applications/placeholder-test.desktop <<EOF
[Desktop Entry]
Name=Placeholder Test
Exec=echo %f %c
Terminal=false
Type=Application
EOF
    
    run "$PROJECT_ROOT/bin/pls-open" --dry-run placeholder-test test.txt
    
    assert_success
    assert_output --partial "echo\\ test.txt\\ placeholder-test"
}