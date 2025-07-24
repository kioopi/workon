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
    
    # Source the utilities and validate modules
    source "$PROJECT_ROOT/lib/commands/utils.sh"
    source "$PROJECT_ROOT/lib/commands/validate.sh"
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# ─── validate_syntax tests ─────────────────────────────────────────────────

@test "validate_syntax shows success for valid YAML" {
    create_minimal_manifest
    
    run validate_syntax "workon.yaml"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🔍 YAML syntax: ✅ Valid" ]]
}

@test "validate_syntax shows error for invalid YAML" {
    create_invalid_yaml
    
    run validate_syntax "workon.yaml"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🔍 YAML syntax: ❌ YAML syntax error" ]]
}

@test "validate_syntax handles missing file" {
    run validate_syntax "nonexistent.yaml"
    
    [ "$status" -eq 1 ]
}

# ─── validate_structure tests ──────────────────────────────────────────────

@test "validate_structure shows success for valid structure" {
    local manifest_json='{"resources":{"test":"echo hello"}}'
    
    run validate_structure "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🏗️  Structure: ✅ Valid" ]]
}

@test "validate_structure shows error for missing resources section" {
    local manifest_json='{"layouts":{}}'
    
    run validate_structure "$manifest_json"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🏗️  Structure: ❌ Invalid - missing 'resources' section" ]]
}

@test "validate_structure shows error for empty resources" {
    local manifest_json='{"resources":{}}'
    
    run validate_structure "$manifest_json"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🏗️  Structure: ❌ Invalid - No resources defined" ]]
}

@test "validate_structure shows error for null resources" {
    local manifest_json='{"resources":null}'
    
    run validate_structure "$manifest_json"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "🏗️  Structure: ❌ Invalid - No resources defined" ]]
}

# ─── validate_show_resources tests ──────────────────────────────────────────

@test "validate_show_resources displays resource count" {
    local manifest_json='{"resources":{"test":"echo hello","ide":"code ."}}'
    
    run validate_show_resources "$manifest_json" "2"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📦 Resources: 2 found" ]]
}

@test "validate_show_resources lists all resources" {
    local manifest_json='{"resources":{"test":"echo hello","ide":"code ."}}'
    
    run validate_show_resources "$manifest_json" "2"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "• test: echo hello" ]]
    [[ "$output" =~ "• ide: code ." ]]
}

@test "validate_show_resources handles empty resources" {
    local manifest_json='{"resources":{}}'
    
    run validate_show_resources "$manifest_json" "0"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📦 Resources: 0 found" ]]
}

# ─── validate_show_templates tests ──────────────────────────────────────────

@test "validate_show_templates shows no templates when none exist" {
    local manifest_json='{"resources":{"test":"echo hello"}}'
    
    run validate_show_templates "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🔧 Template variables: None found" ]]
}

@test "validate_show_templates shows template variables when they exist" {
    local manifest_json='{"resources":{"test":"echo {{HOME}}","web":"{{URL:-https://example.com}}"}}'
    
    run validate_show_templates "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🔧 Template variables: Found" ]]
}

# ─── validate_manifest tests ───────────────────────────────────────────────

@test "validate_manifest shows header" {
    create_minimal_manifest
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WorkOn Manifest Validation" ]]
    [[ "$output" =~ "=========================" ]]
}

@test "validate_manifest shows success for valid manifest" {
    create_minimal_manifest
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📁 Manifest file:" ]]
    [[ "$output" =~ "✅ Valid manifest - ready to use!" ]]
}

@test "validate_manifest shows error when no manifest found" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "❌ No workon.yaml found" ]]
}

@test "validate_manifest shows error for invalid YAML syntax" {
    create_invalid_yaml
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ YAML syntax error" ]]
}

@test "validate_manifest shows error for invalid structure" {
    create_empty_resources_manifest
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ Invalid - No resources defined" ]]
}

@test "validate_manifest uses current directory when no path provided" {
    create_minimal_manifest
    
    run validate_manifest
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Valid manifest - ready to use!" ]]
}

@test "validate_manifest shows all validation steps" {
    create_minimal_manifest
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📁 Manifest file:" ]]
    [[ "$output" =~ "🔍 YAML syntax:" ]]
    [[ "$output" =~ "🏗️  Structure:" ]]
    [[ "$output" =~ "📦 Resources:" ]]
    [[ "$output" =~ "🔧 Template variables:" ]]
}

@test "validate_manifest handles complex manifest with templates" {
    cat > workon.yaml << EOF
resources:
  ide: code .
  terminal: alacritty
  web: "{{DEMO_URL:-https://example.com}}"
  notes: "{{HOME}}/documents/notes.md"
EOF
    
    run validate_manifest "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📦 Resources: 4 found" ]]
    [[ "$output" =~ "🔧 Template variables: Found" ]]
}