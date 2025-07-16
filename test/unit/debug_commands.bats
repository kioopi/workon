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
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

@test "workon info shows basic system information" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WorkOn" ]]
    [[ "$output" =~ "Version:" ]]
    [[ "$output" =~ "Cache directory:" ]]
    [[ "$output" =~ "Installation directory:" ]]
    [[ "$output" =~ "Working directory:" ]]
}

@test "workon info shows cache directory path" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Cache directory: $TEST_DIR/.cache/workon" ]]
}

@test "workon info shows dependency status" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Dependencies:" ]]
    [[ "$output" =~ "yq:" ]]
    [[ "$output" =~ "jq:" ]]
    [[ "$output" =~ "awesome-client:" ]]
}

@test "workon info shows manifest status when manifest exists" {
    # Create a test manifest
    create_minimal_manifest
    
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manifest: Found" ]]
    [[ "$output" =~ "workon.yaml" ]]
}

@test "workon info shows manifest status when manifest missing" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manifest: Not found" ]]
}

@test "workon info shows version information" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Version: 0.1.0" ]]
}

@test "workon info shows installation directory" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Installation directory:" ]]
    [[ "$output" =~ "/workon" ]]
}

@test "workon info shows working directory" {
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Working directory: $TEST_DIR" ]]
}

@test "workon info handles custom XDG_CACHE_HOME" {
    export XDG_CACHE_HOME="$TEST_DIR/custom_cache"
    
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Cache directory: $TEST_DIR/custom_cache/workon" ]]
}

@test "workon info shows dependency status correctly" {
    # This test depends on the actual environment, but we can check the format
    run_workon info
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Dependencies:" ]]
    # Should show either "✓ available" or "✗ missing" for each dependency
    [[ "$output" =~ "yq:" ]]
    [[ "$output" =~ "jq:" ]]
    [[ "$output" =~ "awesome-client:" ]]
}

# Test for info subcommands structure (will be implemented later)
@test "workon info with unknown subcommand shows error" {
    run_workon info unknown_subcommand
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Unknown info subcommand" ]]
}

@test "workon info sessions shows no sessions when cache empty" {
    run_workon info sessions
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No active sessions found" || "$output" =~ "No cache directory found" ]]
}

@test "workon info session shows no session when none exists" {
    run_workon info session
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No active session found" ]]
}

# ─── workon validate tests ──────────────────────────────────────────────────

@test "workon validate shows success for valid manifest" {
    create_minimal_manifest
    
    run_workon validate
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid manifest" ]]
    [[ "$output" =~ "workon.yaml" ]]
}

@test "workon validate shows success for valid manifest with specific path" {
    mkdir -p subdir
    cd subdir
    create_minimal_manifest
    cd ..
    
    run_workon validate subdir
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Valid manifest" ]]
    [[ "$output" =~ "subdir/workon.yaml" ]]
}

@test "workon validate shows error for invalid YAML syntax" {
    create_invalid_yaml
    
    run_workon validate
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "YAML syntax error" ]]
}

@test "workon validate shows error for missing resources section" {
    create_manifest_without_resources
    
    run_workon validate
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "missing 'resources' section" ]]
}

@test "workon validate shows error for empty resources" {
    create_empty_resources_manifest
    
    run_workon validate
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "No resources defined" ]]
}

@test "workon validate shows error when no manifest found" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run_workon validate
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "No workon.yaml found" ]]
}

@test "workon validate shows detailed validation info" {
    create_minimal_manifest
    
    run_workon validate
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Manifest file:" ]]
    [[ "$output" =~ "YAML syntax:" ]]
    [[ "$output" =~ "Structure:" ]]
    [[ "$output" =~ "Resources:" ]]
}

@test "workon validate with complex manifest shows all resources" {
    cat > workon.yaml << EOF
resources:
  ide: code .
  terminal: alacritty
  browser: firefox
  notes: nvim README.md
EOF
    
    run_workon validate
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "ide:" ]]
    [[ "$output" =~ "terminal:" ]]
    [[ "$output" =~ "browser:" ]]
    [[ "$output" =~ "notes:" ]]
}

@test "workon validate shows template variables" {
    cat > workon.yaml << EOF
resources:
  web: "{{DEMO_URL:-https://example.com}}"
  env_var: "{{HOME}}/documents"
EOF
    
    run_workon validate
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Template variables: Found" ]]
    [[ "$output" =~ "DEMO_URL" ]]
    [[ "$output" =~ "HOME" ]]
}

# ─── workon resolve tests ───────────────────────────────────────────────────

@test "workon resolve shows resolved command for existing resource" {
    create_minimal_manifest
    
    run_workon resolve test
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Resource: test" ]]
    [[ "$output" =~ "Raw command: echo hello" ]]
    [[ "$output" =~ "Resolved command: pls-open echo hello" ]]
}

@test "workon resolve shows error for non-existent resource" {
    create_minimal_manifest
    
    run_workon resolve nonexistent
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Resource 'nonexistent' not found" ]]
}

@test "workon resolve shows error when no manifest found" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run_workon resolve test
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "No workon.yaml found" ]]
}

@test "workon resolve handles template variables" {
    export TEST_VAR="hello world"
    cat > workon.yaml << EOF
resources:
  test: echo "{{TEST_VAR}}"
EOF
    
    run_workon resolve test
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Raw command: echo \"{{TEST_VAR}}\"" ]]
    [[ "$output" =~ "Template variables: {{TEST_VAR}}" ]]
    [[ "$output" =~ "Resolved command: pls-open echo hello world" ]]
}

@test "workon resolve handles template variables with defaults" {
    unset TEST_VAR
    cat > workon.yaml << EOF
resources:
  test: echo "{{TEST_VAR:-default value}}"
EOF
    
    run_workon resolve test
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Raw command: echo \"{{TEST_VAR:-default value}}\"" ]]
    [[ "$output" =~ "Template variables: {{TEST_VAR:-default value}}" ]]
    [[ "$output" =~ "Resolved command: pls-open echo default value" ]]
}

@test "workon resolve shows file existence for file resources" {
    create_minimal_manifest
    
    # Create a test file
    touch test_file.txt
    
    cat > workon.yaml << EOF
resources:
  file: test_file.txt
  missing_file: nonexistent_file.txt
EOF
    
    run_workon resolve file
    [ "$status" -eq 0 ]
    [[ "$output" =~ "File/Command exists: Yes" ]]
    
    run_workon resolve missing_file
    [ "$status" -eq 0 ]
    [[ "$output" =~ "File/Command exists: No" ]]
}

@test "workon resolve shows environment variable values" {
    export TEST_ENV="environment_value"
    cat > workon.yaml << EOF
resources:
  test: echo "{{TEST_ENV}}"
EOF
    
    run_workon resolve test
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Environment variables:" ]]
    [[ "$output" =~ "TEST_ENV=environment_value" ]]
}