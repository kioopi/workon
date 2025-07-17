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
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# Issue 1: Quoted arguments and filenames with spaces
@test "expand_relative_paths: should preserve quoted arguments with spaces" {
    # Arrange
    echo "content" > "file with spaces.txt"
    
    # Act - this should properly handle filenames with spaces
    run expand_relative_paths "vim 'file with spaces.txt'"
    
    # Assert - should escape spaces properly (backslash or quotes are both valid)
    assert_success
    # Accept either quoting style as functionally equivalent
    [[ $output == "vim '$PWD/file with spaces.txt'" ]] || [[ $output == "vim $PWD/file\ with\ spaces.txt" ]]
}

@test "expand_relative_paths: should handle double-quoted filenames with spaces" {
    # Arrange
    echo "content" > "my file.txt"
    
    # Act
    run expand_relative_paths 'vim "my file.txt"'
    
    # Assert - should properly escape spaces in path
    assert_success
    assert_output "vim $PWD/my\\ file.txt"
}

@test "expand_relative_paths: should handle command with quoted options" {
    # Arrange
    echo "content" > config.json
    
    # Act
    run expand_relative_paths "vim --cmd 'set number' config.json"
    
    # Assert - should properly escape quoted options and expand file path
    assert_success
    assert_output "vim --cmd set\\ number $PWD/config.json"
}

@test "expand_relative_paths: should handle mixed quoted and unquoted arguments" {
    # Arrange
    echo "content" > "file1.txt"
    echo "content" > "file with spaces.txt"
    
    # Act
    run expand_relative_paths "diff file1.txt 'file with spaces.txt'"
    
    # Assert - should properly escape spaces in filenames
    assert_success
    assert_output "diff $PWD/file1.txt $PWD/file\\ with\\ spaces.txt"
}

# Issue 2: Overly broad *.* pattern matching
@test "expand_relative_paths: should not expand domain names with dots" {
    # Act - domain names like "example.com" should not be treated as file paths
    run expand_relative_paths "ping example.com"
    
    # Assert - should NOT expand example.com to /current/dir/example.com
    assert_success
    assert_output "ping example.com"
}

@test "expand_relative_paths: should not expand version numbers with dots" {
    # Act
    run expand_relative_paths "node --version 18.0.0"
    
    # Assert - should NOT expand version numbers
    assert_success
    assert_output "node --version 18.0.0"
}

@test "expand_relative_paths: should not expand IP addresses" {
    # Act
    run expand_relative_paths "curl 192.168.1.1"
    
    # Assert - should NOT expand IP addresses
    assert_success
    assert_output "curl 192.168.1.1"
}

@test "expand_relative_paths: should not expand floating point numbers" {
    # Act
    run expand_relative_paths "calculate 3.14159"
    
    # Assert - should NOT expand numbers with decimals
    assert_success
    assert_output "calculate 3.14159"
}

@test "expand_relative_paths: should still expand actual files with dots" {
    # Arrange
    echo "content" > "my.file.txt"
    
    # Act
    run expand_relative_paths "vim my.file.txt"
    
    # Assert - should expand actual files that exist
    assert_success
    assert_output "vim $PWD/my.file.txt"
}

@test "expand_relative_paths: should not expand non-existent files" {
    # With simplified logic, we only expand files that actually exist
    # Non-existent files are treated as regular arguments
    
    # Act
    run expand_relative_paths "vim nonexistent.txt"
    
    # Assert - should NOT expand non-existent files
    assert_success
    assert_output "vim nonexistent.txt"
}

# Issue 3: readlink -f portability
@test "expand_relative_paths: should work when readlink -f is not available" {
    # This test simulates the scenario where readlink -f is not available (like on macOS)
    # We need to test that the function still works
    
    # Arrange
    echo "content" > "testfile.txt"
    
    # Mock readlink to fail (simulating macOS behavior)
    readlink() {
        if [[ "$1" == "-f" ]]; then
            return 1  # Simulate readlink -f not supported
        fi
        command readlink "$@"
    }
    export -f readlink
    
    # Act
    run expand_relative_paths "vim testfile.txt"
    
    # Assert - should still work even without readlink -f
    assert_success
    assert_output "vim $PWD/testfile.txt"
}

@test "expand_relative_paths: should handle non-existent files gracefully" {
    # With simplified logic, non-existent files are simply not expanded
    # This test verifies the behavior is consistent
    
    # Act
    run expand_relative_paths "vim nonexistent.txt"
    
    # Assert - should NOT expand non-existent files (consistent with simplified logic)
    assert_success
    assert_output "vim nonexistent.txt"
}

# Combined issue test
@test "expand_relative_paths: should handle complex command with spaces and domains" {
    # Arrange
    echo "content" > "my config.json"
    
    # Act - complex command with quoted file, domain, and other args
    run expand_relative_paths "curl -X POST 'https://api.example.com/upload' -F 'file=@\"my config.json\"'"
    
    # Assert - should preserve URL and properly escape the filename
    assert_success
    assert_output "curl -X POST https://api.example.com/upload -F file=@\\\"my\\ config.json\\\""
}

@test "expand_relative_paths: should handle mixed quoting with separate arguments" {
    # Arrange
    echo "content" > "my config.json"
    
    # Act - similar command but with separate arguments
    run expand_relative_paths 'curl -X POST "https://api.example.com/upload" -F "file=@my config.json"'
    
    # Assert - should expand file path and properly escape
    assert_success
    assert_output "curl -X POST https://api.example.com/upload -F file=@$PWD/my\\ config.json"
}