#!/usr/bin/env bats
# Tests for manifest.sh module
# These tests verify manifest discovery, parsing, and validation functionality

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Source the manifest module if it exists
    if [[ -f "$PROJECT_ROOT/lib/manifest.sh" ]]; then
        source "$PROJECT_ROOT/lib/manifest.sh"
    fi
}

teardown() {
    # Clean up
    cd /
    rm -rf "$TEST_PROJECT_DIR"
}

# Test manifest_find function
@test "manifest_find: locates workon.yaml in current directory" {
        
    create_minimal_manifest
    
    run manifest_find
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/workon.yaml" ]
}

@test "manifest_find: locates workon.yaml in parent directory" {
        
    create_minimal_manifest
    mkdir subdir
    cd subdir
    
    run manifest_find
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_PROJECT_DIR/workon.yaml" ]
}

@test "manifest_find: fails when no workon.yaml exists" {
        
    run manifest_find
    [ "$status" -eq 1 ]
}

@test "manifest_find: finds project by name when configured" {
        
    # Setup config with project path
    local config_dir="$BATS_TEST_TMPDIR/config"
    local config_file="$config_dir/workon/config.yaml"
    mkdir -p "$(dirname "$config_file")"
    
    # Create a project in the configured path
    local projects_dir="$BATS_TEST_TMPDIR/projects"
    mkdir -p "$projects_dir/test-project"
    create_minimal_manifest > "$projects_dir/test-project/workon.yaml"
    
    cat > "$config_file" <<EOF
projects_path:
  - $projects_dir
EOF
    
    export XDG_CONFIG_HOME="$config_dir"
    
    run manifest_find "test-project"
    [ "$status" -eq 0 ]
    [ "$output" = "$projects_dir/test-project/workon.yaml" ]
}

# Test manifest_parse function
@test "manifest_parse: converts YAML to JSON successfully" {
        
    create_minimal_manifest
    
    run manifest_parse "$TEST_PROJECT_DIR/workon.yaml"
    [ "$status" -eq 0 ]
    
    # Verify it's valid JSON
    echo "$output" | jq . >/dev/null
}

@test "manifest_parse: fails with invalid YAML syntax" {
        
    create_invalid_yaml
    
    run manifest_parse "$TEST_PROJECT_DIR/workon.yaml"
    [ "$status" -ne 0 ]
    [[ "$output" == *"check YAML syntax"* ]]
}

# Test manifest_validate_syntax function
@test "manifest_validate_syntax: passes with valid YAML" {
        
    create_minimal_manifest
    
    run manifest_validate_syntax "$TEST_PROJECT_DIR/workon.yaml"
    [ "$status" -eq 0 ]
}

@test "manifest_validate_syntax: fails with invalid YAML" {
        
    create_invalid_yaml
    
    run manifest_validate_syntax "$TEST_PROJECT_DIR/workon.yaml"
    [ "$status" -eq 1 ]
}

# Test manifest_validate_structure function
@test "manifest_validate_structure: passes with valid structure" {
        
    local manifest_json='{"resources":{"test":"echo hello"}}'
    
    run manifest_validate_structure "$manifest_json"
    [ "$status" -eq 0 ]
}

@test "manifest_validate_structure: fails without resources section" {
        
    local manifest_json='{"layouts":{"desktop":[]}}'
    
    run manifest_validate_structure "$manifest_json"
    [ "$status" -eq 1 ]
}

@test "manifest_validate_structure: fails with empty resources" {
        
    local manifest_json='{"resources":{}}'
    
    run manifest_validate_structure "$manifest_json"
    [ "$status" -eq 1 ]
}

# Test manifest_extract_resources function
@test "manifest_extract_resources: extracts resources as base64 entries" {
        
    local manifest_json='{"resources":{"ide":"code .","terminal":"gnome-terminal"}}'
    
    run manifest_extract_resources "$manifest_json"
    [ "$status" -eq 0 ]
    
    # Should return 2 base64-encoded entries
    [ "${#lines[@]}" -eq 2 ]
    
    # Decode first entry and verify structure
    local first_entry=$(echo "${lines[0]}" | base64 -d)
    echo "$first_entry" | jq -e '.key' >/dev/null
    echo "$first_entry" | jq -e '.value' >/dev/null
}