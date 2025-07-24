#!/usr/bin/env bats
# Tests for template.sh module
# These tests verify template variable processing and environment expansion functionality

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Source the template module if it exists
    if [[ -f "$PROJECT_ROOT/lib/template.sh" ]]; then
        source "$PROJECT_ROOT/lib/template.sh"
    fi
    
    # Clean environment for consistent testing
    unset TEST_VAR
    unset ANOTHER_VAR
}

teardown() {
    # Clean up
    cd /
    rm -rf "$TEST_PROJECT_DIR"
    unset TEST_VAR
    unset ANOTHER_VAR
}

# Test template_render function
@test "template_render: performs basic variable substitution" {
        
    export TEST_VAR="hello world"
    
    run template_render "{{TEST_VAR}}"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "template_render: leaves templates without variables unchanged" {
        
    run template_render "no variables here"
    [ "$status" -eq 0 ]
    [ "$output" = "no variables here" ]
}

@test "template_render: handles multiple variables in single template" {
        
    export TEST_VAR="hello"
    export ANOTHER_VAR="world"
    
    run template_render "{{TEST_VAR}} {{ANOTHER_VAR}}"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "template_render: leaves undefined variables as empty strings" {
        
    run template_render "{{UNDEFINED_VAR}}"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "template_render: uses default value when variable undefined" {
        
    run template_render "{{UNDEFINED_VAR:-default_value}}"
    [ "$status" -eq 0 ]
    [ "$output" = "default_value" ]
}

@test "template_render: variable overrides default value when defined" {
        
    export TEST_VAR="actual_value"
    
    run template_render "{{TEST_VAR:-default_value}}"
    [ "$status" -eq 0 ]
    [ "$output" = "actual_value" ]
}

@test "template_render: handles complex default values with special characters" {
        
    run template_render "{{UNDEFINED_VAR:-/path/to/file.txt}}"
    [ "$status" -eq 0 ]
    [ "$output" = "/path/to/file.txt" ]
}

@test "template_render: processes mixed variables with and without defaults" {
        
    export DEFINED_VAR="hello"
    
    run template_render "{{DEFINED_VAR}} {{UNDEFINED_VAR:-world}}"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

# Test template_extract_variables function
@test "template_extract_variables: finds single variable" {
        
    run template_extract_variables "{{TEST_VAR}}"
    [ "$status" -eq 0 ]
    [ "$output" = "{{TEST_VAR}}" ]
}

@test "template_extract_variables: finds multiple variables" {
        
    run template_extract_variables "{{VAR1}} and {{VAR2}}"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "{{VAR1}}" ]
    [ "${lines[1]}" = "{{VAR2}}" ]
}

@test "template_extract_variables: finds variables with defaults" {
        
    run template_extract_variables "{{VAR:-default}}"
    [ "$status" -eq 0 ]
    [ "$output" = "{{VAR:-default}}" ]
}

@test "template_extract_variables: returns nothing for text without variables" {
        
    run template_extract_variables "no variables here"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "template_extract_variables: deduplicates identical variables" {
        
    run template_extract_variables "{{TEST_VAR}} and {{TEST_VAR}} again"
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "$output" = "{{TEST_VAR}}" ]
}

# Test template_analyze function (shows variables with environment values)
@test "template_analyze: shows template variables with environment values" {
        
    export TEST_VAR="test_value"
    
    run template_analyze "{{TEST_VAR}} {{UNDEFINED_VAR}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Template variables:"* ]]
    [[ "$output" == *"Environment variables:"* ]]
    [[ "$output" == *"TEST_VAR=test_value"* ]]
    [[ "$output" == *"UNDEFINED_VAR=<unset>"* ]]
}

@test "template_analyze: handles text with no variables" {
        
    run template_analyze "no variables here"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Template variables: None"* ]]
}

# Test template_process_variables function (simpler version for validation)
@test "template_process_variables: returns Found with variable list" {
        
    run template_process_variables "{{VAR1}} and {{VAR2}}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Found"* ]]
    [[ "$output" == *"VAR1"* ]]
    [[ "$output" == *"VAR2"* ]]
}

@test "template_process_variables: returns None for text without variables" {
        
    run template_process_variables "no variables here"
    [ "$status" -eq 1 ]
    [[ "$output" == *"None"* ]]
}