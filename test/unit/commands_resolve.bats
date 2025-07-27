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
    
    # Source the resolve module
    source "$PROJECT_ROOT/lib/commands/utils.sh"
    source "$PROJECT_ROOT/lib/commands/resolve.sh"
}

teardown() {
    # Clean up test directory
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

# ─── resolve_get_command tests ──────────────────────────────────────────────

@test "resolve_get_command returns command for existing resource" {
    local manifest_json='{"resources":{"test":"echo hello","ide":"code ."}}'
    
    run resolve_get_command "test" "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ "$output" == "echo hello" ]]
}

@test "resolve_get_command returns empty for non-existent resource" {
    local manifest_json='{"resources":{"test":"echo hello"}}'
    
    run resolve_get_command "nonexistent" "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ -z "$output" ]]
}

@test "resolve_get_command handles complex resource names" {
    local manifest_json='{"resources":{"my-app":"code project/","web_browser":"firefox"}}'
    
    run resolve_get_command "my-app" "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == "code project/" ]]
    
    run resolve_get_command "web_browser" "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == "firefox" ]]
}

# ─── resolve_show_info tests ────────────────────────────────────────────────

@test "resolve_show_info displays resource info when found" {
    local manifest_json='{"resources":{"test":"echo hello","ide":"code ."}}'
    
    run resolve_show_info "test" "echo hello" "$manifest_json"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "🎯 Resource: test" ]]
    [[ "$output" =~ "📝 Raw command: echo hello" ]]
}

@test "resolve_show_info shows error and available resources when not found" {
    local manifest_json='{"resources":{"test":"echo hello","ide":"code ."}}'
    
    run resolve_show_info "nonexistent" "" "$manifest_json"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ Resource 'nonexistent' not found" ]]
    [[ "$output" =~ "Available resources:" ]]
    [[ "$output" =~ "• test" ]]
    [[ "$output" =~ "• ide" ]]
}

@test "resolve_show_info handles empty manifest" {
    local manifest_json='{"resources":{}}'
    
    run resolve_show_info "test" "" "$manifest_json"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ Resource 'test' not found" ]]
    [[ "$output" =~ "Available resources:" ]]
}

# ─── resolve_show_results tests ──────────────────────────────────────────────

@test "resolve_show_results shows template analysis and resolved command" {
    export TEST_VAR="hello world"
    
    run resolve_show_results "echo {{TEST_VAR}}"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Resolved command: pls-open echo hello world" ]]
    [[ "$output" =~ "📋 File/Command exists:" ]]
}

@test "resolve_show_results handles commands without templates" {
    run resolve_show_results "echo hello"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Resolved command: pls-open echo hello" ]]
    [[ "$output" =~ "📋 File/Command exists:" ]]
}

@test "resolve_show_results handles template variables with defaults" {
    unset TEST_VAR
    
    run resolve_show_results "echo {{TEST_VAR:-default}}"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Resolved command: pls-open echo default" ]]
}

@test "resolve_show_results shows file existence check" {
    # Create a test file
    touch test_file.txt
    
    run resolve_show_results "test_file.txt"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📋 File/Command exists: Yes" ]]
}

# ─── resolve_resource tests ──────────────────────────────────────────────────

@test "resolve_resource shows header and manifest path" {
    create_minimal_manifest
    
    run resolve_resource "test" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "WorkOn Resource Resolution" ]]
    [[ "$output" =~ "=========================" ]]
    [[ "$output" =~ "📁 Manifest:" ]]
}

@test "resolve_resource shows error when no manifest found" {
    # Ensure no manifest exists
    rm -f workon.yaml
    
    run resolve_resource "test" "$TEST_DIR"
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "❌ No workon.yaml found" ]]
}

@test "resolve_resource shows error for missing resource name" {
    run resolve_resource "" "$TEST_DIR"
    
    [ "$status" -eq 2 ]
    [[ "$output" =~ "Usage: workon resolve <resource> [project_path]" ]]
}

@test "resolve_resource shows error for invalid YAML" {
    create_invalid_yaml
    
    run resolve_resource "test" "$TEST_DIR"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ Failed to parse manifest (YAML syntax error)" ]]
}

@test "resolve_resource shows error for non-existent resource" {
    create_minimal_manifest
    
    run resolve_resource "nonexistent" "$TEST_DIR"
    
    [ "$status" -eq 1 ]
    [[ "$output" =~ "❌ Resource 'nonexistent' not found" ]]
}

@test "resolve_resource shows complete resolution for valid resource" {
    create_minimal_manifest
    
    run resolve_resource "test" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📁 Manifest:" ]]
    [[ "$output" =~ "🎯 Resource: test" ]]
    [[ "$output" =~ "📝 Raw command: echo hello" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open echo hello" ]]
}

@test "resolve_resource uses current directory when no path provided" {
    create_minimal_manifest
    
    run resolve_resource "test"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Resolved command: pls-open echo hello" ]]
}

@test "resolve_resource handles template variables" {
    export TEST_ENV="template_value"
    cat > workon.yaml << EOF
resources:
  templated: echo "{{TEST_ENV}}"
EOF
    
    run resolve_resource "templated" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📝 Raw command: echo \"{{TEST_ENV}}\"" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open echo template_value" ]]
}

@test "resolve_resource handles relative paths" {
    mkdir -p subdir
    cat > workon.yaml << EOF
resources:
  file: subdir/file.txt
EOF
    
    run resolve_resource "file" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "✅ Resolved command: pls-open $TEST_DIR/subdir/file.txt" ]]
}

@test "resolve_resource handles https URLs correctly" {
    cat > workon.yaml << EOF
resources:
  docs: https://awesomewm.org/apidoc/documentation/05-awesomerc.md.html
EOF
    
    run resolve_resource "docs" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📝 Raw command: https://awesomewm.org/apidoc/documentation/05-awesomerc.md.html" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open https://awesomewm.org/apidoc/documentation/05-awesomerc.md.html" ]]
    [[ "$output" =~ "📋 File/Command exists: Yes (URL)" ]]
}

@test "resolve_resource handles http URLs correctly" {
    cat > workon.yaml << EOF
resources:
  local: http://localhost:3000
EOF
    
    run resolve_resource "local" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📝 Raw command: http://localhost:3000" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open http://localhost:3000" ]]
    [[ "$output" =~ "📋 File/Command exists: Yes (URL)" ]]
}

@test "resolve_check_existence shows correct output for URLs without duplication" {
    run resolve_check_existence "https://example.com"
    
    [ "$status" -eq 0 ]
    [ "$output" = "Yes (URL)" ]
}

# ─── Desktop Application Resolution Tests (TDD) ──────────────────────────────

@test "resolve_check_existence should detect desktop applications" {
    # This test will initially FAIL - demonstrating the bug
    run resolve_check_existence "dev.zed.Zed"
    
    [ "$status" -eq 0 ]
    # Currently returns "No" but should return "Yes (desktop app)" or similar
    [[ "$output" =~ ^Yes ]]
}

@test "resolve_check_existence should handle desktop app with arguments" {
    # This test will initially FAIL - demonstrating the bug  
    run resolve_check_existence "dev.zed.Zed index.html"
    
    [ "$status" -eq 0 ]
    # Currently returns "No" but should return "Yes (desktop app)" or similar
    [[ "$output" =~ ^Yes ]]
}

@test "resolve_resource should work with desktop applications" {
    # Create manifest with desktop application
    cat > workon.yaml << EOF
resources:
  ide: dev.zed.Zed index.html
EOF
    
    # This test will initially FAIL - demonstrating the bug
    run resolve_resource "ide" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📝 Raw command: dev.zed.Zed index.html" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open dev.zed.Zed index.html" ]]
    # This is the key assertion that currently fails:
    [[ "$output" =~ "📋 File/Command exists: Yes" ]]
}

@test "resolve_resource should detect common desktop applications" {
    # Test with firefox (more likely to be installed)
    cat > workon.yaml << EOF
resources:
  browser: firefox https://example.com
EOF
    
    # This test will initially FAIL if firefox.desktop exists
    run resolve_resource "browser" "$TEST_DIR"
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📝 Raw command: firefox https://example.com" ]]
    [[ "$output" =~ "✅ Resolved command: pls-open firefox https://example.com" ]]
    # This should pass if firefox is a command in PATH, but might fail for desktop ID resolution
    [[ "$output" =~ "📋 File/Command exists: Yes" ]]
}

@test "resolve_resource should differentiate desktop IDs from regular commands" {
    # Create manifest with both types
    cat > workon.yaml << EOF
resources:
  command: echo hello
  desktop: dev.zed.Zed README.md
EOF
    
    # Test regular command (should work)
    run resolve_resource "command" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📋 File/Command exists: Yes (command)" ]]
    
    # Test desktop application (should now work)
    run resolve_resource "desktop" "$TEST_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "📋 File/Command exists: Yes" ]]
}