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

@test "find_manifest: locates workon.yaml in current directory" {
    # Arrange
    create_minimal_manifest
    
    # Act
    run find_manifest "$PWD"
    
    # Assert
    assert_success
    assert_output "$PWD/workon.yaml"
}

@test "find_manifest: locates workon.yaml in parent directory" {
    # Arrange
    create_minimal_manifest
    mkdir subdir
    cd subdir
    
    # Act
    run find_manifest "$PWD"
    
    # Assert
    assert_success
    assert_output "$(dirname "$PWD")/workon.yaml"
}

@test "find_manifest: fails when no workon.yaml exists" {
    # Act
    run find_manifest "$PWD"
    
    # Assert
    assert_failure
    refute_output
}

@test "render_template: performs basic variable substitution" {
    # Arrange
    export TEST_VAR="test_value"
    
    # Act
    run render_template "Hello {{TEST_VAR}}"
    
    # Assert
    assert_success
    assert_output "Hello test_value"
}

@test "render_template: leaves templates without variables unchanged" {
    # Act
    run render_template "Just a plain string"
    
    # Assert
    assert_success
    assert_output "Just a plain string"
}

@test "render_template: handles multiple variables in single template" {
    # Arrange
    export VAR1="first"
    export VAR2="second"
    
    # Act
    run render_template "{{VAR1}} and {{VAR2}}"
    
    # Assert
    assert_success
    assert_output "first and second"
}

@test "render_template: leaves undefined variables as empty strings" {
    # Arrange
    unset UNDEFINED_VAR || true
    
    # Act
    run render_template "Hello {{UNDEFINED_VAR}}"
    
    # Assert
    assert_success
    assert_output "Hello "
}

@test "render_template: uses default value when variable undefined" {
    # Arrange
    unset DEFAULT_TEST_VAR || true
    
    # Act
    run render_template "Hello {{DEFAULT_TEST_VAR:-world}}"
    
    # Assert
    assert_success
    assert_output "Hello world"
}

@test "render_template: variable overrides default value when defined" {
    # Arrange
    export DEFAULT_TEST_VAR="custom"
    
    # Act
    run render_template "Hello {{DEFAULT_TEST_VAR:-world}}"
    
    # Assert
    assert_success
    assert_output "Hello custom"
}

@test "render_template: handles complex default values with special characters" {
    # Arrange
    unset URL_VAR || true
    
    # Act
    run render_template "URL: {{URL_VAR:-https://example.com/path?param=value}}"
    
    # Assert
    assert_success
    assert_output "URL: https://example.com/path?param=value"
}

@test "render_template: processes mixed variables with and without defaults" {
    # Arrange
    export DEFINED_VAR="defined"
    unset UNDEFINED_VAR || true
    unset PLAIN_VAR || true
    
    # Act
    run render_template "{{DEFINED_VAR}} and {{UNDEFINED_VAR:-default}} and {{PLAIN_VAR}}"
    
    # Assert
    assert_success
    assert_output "defined and default and "
}

@test "render_template: leave imput unchanged if no variables" {
    # Act
    run render_template "nvim ."
    
    # Assert
    assert_success
    assert_output "nvim ."
}

@test "workon --version: displays current version information" {
    # Act
    run_workon --version
    
    # Assert
    assert_success
    assert_output "workon 0.1.0-alpha"
}

@test "workon --help: displays usage information and options" {
    # Act
    run_workon --help
    
    # Assert
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "PROJECT_PATH"
}

@test "workon: fails with helpful error when no manifest found" {
    # Act
    run_workon
    
    # Assert
    assert_failure 2
    assert_output --partial "No workon.yaml found"
}

@test "workon: fails gracefully with invalid YAML syntax" {
    # Arrange
    create_invalid_yaml
    
    # Act
    run_workon
    
    # Assert
    assert_failure 2
    assert_output --partial "Failed to parse"
}

@test "workon: fails when manifest missing required resources section" {
    # Arrange
    create_manifest_without_resources
    
    # Act
    run_workon
    
    # Assert
    assert_failure 2
    assert_output --partial "missing 'resources' section"
}

@test "workon: fails when resources section is empty" {
    # Arrange
    create_empty_resources_manifest
    
    # Act
    run_workon
    
    # Assert
    assert_failure 2
    assert_output --partial "No resources defined"
}
