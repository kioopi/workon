#!/usr/bin/env bats

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

# Helper function to test find_manifest
test_find_manifest() {
    local search_dir="$1"
    bash -c "
        set -euo pipefail
        find_manifest() {
            local dir
            dir=\$(realpath \"\${1:-\$PWD}\")
            
            while [[ \$dir != / ]]; do
                if [[ -f \$dir/workon.yaml ]]; then
                    printf '%s/workon.yaml' \"\$dir\"
                    return 0
                fi
                dir=\$(dirname \"\$dir\")
            done
            
            return 1
        }
        find_manifest '$search_dir'
    "
}

@test "find_manifest: finds workon.yaml in current directory" {
    echo "resources: {}" > workon.yaml
    
    run test_find_manifest "$PWD"
    [ "$status" -eq 0 ]
    [[ "$output" == "$PWD/workon.yaml" ]]
}

@test "find_manifest: finds workon.yaml in parent directory" {
    echo "resources: {}" > workon.yaml
    mkdir subdir
    cd subdir
    
    run test_find_manifest "$PWD"
    [ "$status" -eq 0 ]
    [[ "$output" == "$(dirname "$PWD")/workon.yaml" ]]
}

@test "find_manifest: fails when no workon.yaml found" {
    run test_find_manifest "$PWD"
    [ "$status" -eq 1 ]
}

# Helper function to test render_template
test_render_template() {
    local input="$1"
    bash -c "
        set -euo pipefail
        render_template() {
            local input=\"\$1\"
            local converted
            converted=\$(printf '%s' \"\$input\" | sed -E 's/\{\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}\}/\${\1\2}/g')
            (set +u; eval \"printf '%s' \\\"\$converted\\\"\")
        }
        render_template '$input'
    "
}

@test "render_template: basic variable substitution" {
    export TEST_VAR="test_value"
    
    run test_render_template "Hello {{TEST_VAR}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "Hello test_value" ]]
}

@test "render_template: multiple variables" {
    export VAR1="first"
    export VAR2="second"
    
    run test_render_template "{{VAR1}} and {{VAR2}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "first and second" ]]
}

@test "render_template: undefined variable stays as empty" {
    run test_render_template "Hello {{UNDEFINED_VAR}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "Hello " ]]
}

@test "render_template: default value when variable undefined" {
    unset DEFAULT_TEST_VAR || true
    
    run test_render_template "Hello {{DEFAULT_TEST_VAR:-world}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "Hello world" ]]
}

@test "render_template: variable overrides default value" {
    export DEFAULT_TEST_VAR="custom"
    
    run test_render_template "Hello {{DEFAULT_TEST_VAR:-world}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "Hello custom" ]]
}

@test "render_template: complex default values" {
    unset URL_VAR || true
    
    run test_render_template "URL: {{URL_VAR:-https://example.com/path?param=value}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "URL: https://example.com/path?param=value" ]]
}

@test "render_template: mixed variables with and without defaults" {
    export DEFINED_VAR="defined"
    unset UNDEFINED_VAR || true
    
    run test_render_template "{{DEFINED_VAR}} and {{UNDEFINED_VAR:-default}} and {{PLAIN_VAR}}"
    [ "$status" -eq 0 ]
    [[ "$output" == "defined and default and " ]]
}

@test "workon --version shows correct version" {
    run "$ORIG_DIR/bin/workon" --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ "workon 0.1.0-alpha" ]]
}

@test "workon --help shows usage" {
    run "$ORIG_DIR/bin/workon" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "PROJECT_PATH" ]]
}

@test "workon fails with no manifest" {
    run "$ORIG_DIR/bin/workon"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "No workon.yaml found" ]]
}

@test "workon fails with invalid YAML" {
    cat > workon.yaml <<EOF
invalid: yaml: syntax [
EOF
    
    run "$ORIG_DIR/bin/workon"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Failed to parse" ]]
}

@test "workon fails with missing resources section" {
    cat > workon.yaml <<EOF
layouts:
  desktop: []
EOF
    
    run "$ORIG_DIR/bin/workon"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "missing 'resources' section" ]]
}

@test "workon fails with empty resources" {
    cat > workon.yaml <<EOF
resources: {}
EOF
    
    run "$ORIG_DIR/bin/workon"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "No resources defined" ]]
}
