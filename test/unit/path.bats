#!/usr/bin/env bats
# Tests for path.sh module
# These tests verify path manipulation, expansion, and validation functionality

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Create test files and directories
    mkdir -p subdir
    touch testfile.txt
    touch "file with spaces.txt"
    
    # Source the path module if it exists
    if [[ -f "$PROJECT_ROOT/lib/path.sh" ]]; then
        source "$PROJECT_ROOT/lib/path.sh"
    fi
}

teardown() {
    # Clean up
    cd /
    rm -rf "$TEST_PROJECT_DIR"
}

# Test path_expand_relative function
@test "path_expand_relative: preserves URLs" {
        
    run path_expand_relative "https://example.com/path"
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com/path" ]
}

@test "path_expand_relative: preserves absolute paths" {
        
    run path_expand_relative "/absolute/path"
    [ "$status" -eq 0 ]
    [ "$output" = "/absolute/path" ]
}

@test "path_expand_relative: expands relative file paths" {
        
    run path_expand_relative "testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/testfile.txt" ]
}

@test "path_expand_relative: expands relative paths with slashes" {
        
    run path_expand_relative "subdir/file"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/subdir/file" ]
}

@test "path_expand_relative: preserves current directory dot" {
        
    run path_expand_relative "."
    [ "$status" -eq 0 ]
    [ "$output" = "." ]
}

@test "path_expand_relative: preserves command flags" {
        
    run path_expand_relative "--flag"
    [ "$status" -eq 0 ]
    [ "$output" = "--flag" ]
}

@test "path_expand_relative: handles complex commands" {
        
    run path_expand_relative "code --new-window testfile.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"code --new-window"* ]]
    [[ "$output" == *"$TEST_PROJECT_DIR/testfile.txt"* ]]
}

@test "path_expand_relative: handles mixed arguments" {
        
    run path_expand_relative "command --flag subdir/file --other-flag"
    [ "$status" -eq 0 ]
    [[ "$output" == *"command --flag"* ]]
    [[ "$output" == *"$TEST_PROJECT_DIR/subdir/file"* ]]
    [[ "$output" == *"--other-flag"* ]]
}

@test "path_expand_relative: does not expand non-existent files without slash" {
        
    run path_expand_relative "nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "nonexistent" ]
}

@test "path_expand_relative: preserves commands without file arguments" {
        
    run path_expand_relative "ls -la"
    [ "$status" -eq 0 ]
    [ "$output" = "ls -la" ]
}

@test "path_expand_relative: handles various URL protocols" {
        
    run path_expand_relative "ftp://example.com/file"
    [ "$status" -eq 0 ]
    [ "$output" = "ftp://example.com/file" ]
}

@test "path_expand_relative: handles file protocol URLs" {
        
    run path_expand_relative "file:///path/to/file"
    [ "$status" -eq 0 ]
    [ "$output" = "file:///path/to/file" ]
}

@test "path_expand_relative: handles multiple relative paths" {
        
    run path_expand_relative "testfile.txt subdir/another"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$TEST_PROJECT_DIR/testfile.txt"* ]]
    [[ "$output" == *"$TEST_PROJECT_DIR/subdir/another"* ]]
}

# Test path_expand_word_if_path function
@test "path_expand_word_if_path: expands relative path" {
        
    run path_expand_word_if_path "testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/testfile.txt" ]
}

@test "path_expand_word_if_path: preserves command" {
        
    run path_expand_word_if_path "ls"
    [ "$status" -eq 0 ]
    [ "$output" = "ls" ]
}

@test "path_expand_word_if_path: preserves URL" {
        
    run path_expand_word_if_path "https://example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com" ]
}

@test "path_expand_word_if_path: handles special patterns file=@path" {
        
    run path_expand_word_if_path "file=@testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "file=@$TEST_PROJECT_DIR/testfile.txt" ]
}

@test "path_expand_word_if_path: handles option=path patterns" {
        
    run path_expand_word_if_path "config=testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "config=$TEST_PROJECT_DIR/testfile.txt" ]
}

# Test path_should_expand_as_path function
@test "path_should_expand_as_path: returns true for existing file" {
        
    run path_should_expand_as_path "testfile.txt"
    [ "$status" -eq 0 ]
}

@test "path_should_expand_as_path: returns true for path with slash" {
        
    run path_should_expand_as_path "subdir/file"
    [ "$status" -eq 0 ]
}

@test "path_should_expand_as_path: returns false for command" {
        
    run path_should_expand_as_path "ls"
    [ "$status" -eq 1 ]
}

# Test path_expand_to_absolute function
@test "path_expand_to_absolute: expands existing file" {
        
    run path_expand_to_absolute "testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/testfile.txt" ]
}

@test "path_expand_to_absolute: expands non-existing file with fallback" {
        
    run path_expand_to_absolute "nonexistent.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == "$TEST_PROJECT_DIR/nonexistent.txt"* ]]
}

# Test path_resource_exists function
@test "path_resource_exists: returns Yes (file) for existing file" {
        
    run path_resource_exists "testfile.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (file)" ]
}

@test "path_resource_exists: returns Yes (command) for command in PATH" {
        
    run path_resource_exists "ls"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (command)" ]
}

@test "path_resource_exists: returns No for non-existent resource" {
        
    run path_resource_exists "nonexistent"
    [ "$status" -eq 1 ]
    [ "$output" = "No" ]
}

@test "path_resource_exists: returns Yes (URL) for https URL" {
        
    run path_resource_exists "https://example.com"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (URL)" ]
}

@test "path_resource_exists: returns Yes (URL) for http URL" {
        
    run path_resource_exists "http://localhost:3000"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (URL)" ]
}

@test "path_resource_exists: returns Yes (URL) for ftp URL" {
        
    run path_resource_exists "ftp://ftp.example.com/file.txt"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (URL)" ]
}

@test "path_resource_exists: returns Yes (URL) for file URL" {
        
    run path_resource_exists "file:///path/to/file.html"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (URL)" ]
}

# ─── Desktop Application Tests (TDD) ────────────────────────────────────────

@test "path_resource_exists: should detect desktop application IDs (FAILING)" {
    # This test INTENTIONALLY FAILS to demonstrate the bug
    # Desktop ID format: reverse domain notation with dots
    run path_resource_exists "dev.zed.Zed"
    
    [ "$status" -eq 0 ]
    # Currently returns "No" but should detect desktop applications
    [[ "$output" =~ ^Yes ]]
}

@test "path_resource_exists: should detect desktop apps with arguments (FAILING)" {
    # This test INTENTIONALLY FAILS to demonstrate the bug
    run path_resource_exists "dev.zed.Zed index.html"
    
    [ "$status" -eq 0 ]
    # Currently returns "No" but should detect desktop applications
    [[ "$output" =~ ^Yes ]]
}

@test "path_resource_exists: should detect available desktop applications" {
    # Test with dev.zed.Zed (confirmed to exist on this system)
    run path_resource_exists "dev.zed.Zed"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Yes ]]
}

@test "path_resource_exists: should differentiate desktop IDs from files" {
    # Create a test file with similar name
    touch "fake.desktop.app"
    
    # Test file (should work)
    run path_resource_exists "fake.desktop.app"
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (file)" ]
    
    # Test non-existent desktop ID (should return No)
    run path_resource_exists "org.example.NonExistent"
    [ "$status" -eq 1 ]
    [ "$output" = "No" ]
    
    # Test existing desktop ID (should work)
    run path_resource_exists "dev.zed.Zed"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^Yes ]]
}

@test "path_resource_exists: should handle mixed desktop ID and file arguments (FAILING)" {
    # Create a test file
    touch "test.txt"
    
    # Desktop app with file argument (common pattern)
    run path_resource_exists "dev.zed.Zed test.txt"
    
    [ "$status" -eq 0 ]
    # Should detect the desktop app, not just check if whole string is a file
    [[ "$output" =~ ^Yes ]]
}