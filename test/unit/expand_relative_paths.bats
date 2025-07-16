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

@test "expand_relative_paths: preserves URLs" {
    # Act
    run expand_relative_paths "https://example.com/path"
    
    # Assert
    assert_success
    assert_output "https://example.com/path"
}

@test "expand_relative_paths: preserves absolute paths" {
    # Act
    run expand_relative_paths "/usr/bin/vim"
    
    # Assert
    assert_success
    assert_output "/usr/bin/vim"
}

@test "expand_relative_paths: expands relative file paths" {
    # Arrange
    echo "test content" > test.txt
    
    # Act
    run expand_relative_paths "test.txt"
    
    # Assert
    assert_success
    assert_output "$PWD/test.txt"
}

@test "expand_relative_paths: expands relative paths with extensions" {
    # Arrange
    echo "config" > config.json
    
    # Act
    run expand_relative_paths "config.json"
    
    # Assert
    assert_success
    assert_output "$PWD/config.json"
}

@test "expand_relative_paths: expands relative paths with slashes" {
    # Arrange
    mkdir -p subdir
    echo "content" > subdir/file.txt
    
    # Act
    run expand_relative_paths "subdir/file.txt"
    
    # Assert
    assert_success
    assert_output "$PWD/subdir/file.txt"
}

@test "expand_relative_paths: preserves current directory dot" {
    # Act
    run expand_relative_paths "."
    
    # Assert
    assert_success
    assert_output "."
}

@test "expand_relative_paths: preserves command flags" {
    # Act
    run expand_relative_paths "--help"
    
    # Assert
    assert_success
    assert_output "--help"
}

@test "expand_relative_paths: handles complex commands" {
    # Arrange
    echo "content" > README.md
    
    # Act
    run expand_relative_paths "vim README.md --readonly"
    
    # Assert
    assert_success
    assert_output "vim $PWD/README.md --readonly"
}

@test "expand_relative_paths: handles mixed arguments" {
    # Arrange
    echo "local" > local.txt
    
    # Act
    run expand_relative_paths "vim local.txt /etc/hosts https://example.com"
    
    # Assert
    assert_success
    assert_output "vim $PWD/local.txt /etc/hosts https://example.com"
}

@test "expand_relative_paths: handles non-existent files" {
    # Act
    run expand_relative_paths "nonexistent.txt"
    
    # Assert
    assert_success
    assert_output "$PWD/nonexistent.txt"
}

@test "expand_relative_paths: preserves commands without file arguments" {
    # Act
    run expand_relative_paths "alacritty"
    
    # Assert
    assert_success
    assert_output "alacritty"
}

@test "expand_relative_paths: handles various URL protocols" {
    # Act
    run expand_relative_paths "ftp://example.com/file"
    
    # Assert
    assert_success
    assert_output "ftp://example.com/file"
}

@test "expand_relative_paths: handles file protocol URLs" {
    # Act
    run expand_relative_paths "file:///path/to/file"
    
    # Assert
    assert_success
    assert_output "file:///path/to/file"
}

@test "expand_relative_paths: handles multiple relative paths" {
    # Arrange
    echo "content1" > file1.txt
    echo "content2" > file2.txt
    
    # Act
    run expand_relative_paths "diff file1.txt file2.txt"
    
    # Assert
    assert_success
    assert_output "diff $PWD/file1.txt $PWD/file2.txt"
}