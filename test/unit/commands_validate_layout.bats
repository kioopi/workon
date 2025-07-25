#!/usr/bin/env bats

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Source the validate module
    source "$PROJECT_ROOT/lib/commands/validate.sh"
    source "$PROJECT_ROOT/lib/manifest.sh"
}

teardown() {
    # Clean up temporary files
    cd "$BATS_TEST_TMPDIR"
    rm -rf "$TEST_PROJECT_DIR"
}

# Test: validate_show_layouts with no layouts
@test "validate_show_layouts: displays none defined message when no layouts exist" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        }
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Layouts: None defined (using sequential spawning)"* ]]
}

# Test: validate_show_layouts with valid layouts
@test "validate_show_layouts: displays layout information correctly" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty",
            "web": "firefox"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal", "web"]],
            "minimal": [["ide", "terminal"]]
        },
        "default_layout": "desktop"
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Layouts: 2 defined"* ]]
    [[ "$output" == *"• desktop: 2 tags ✅"* ]]
    [[ "$output" == *"• minimal: 1 tag ✅"* ]]
    [[ "$output" == *"Default Layout: desktop ✅"* ]]
}

# Test: validate_show_layouts with invalid layout reference
@test "validate_show_layouts: shows errors for invalid layout references" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "broken": [["ide"], ["nonexistent"]]
        },
        "default_layout": "broken"
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Layouts: 1 defined"* ]]
    [[ "$output" == *"• broken: 2 tags ❌"* ]]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"undefined resource"* ]]
}

# Test: validate_show_layouts with invalid default_layout
@test "validate_show_layouts: shows error for invalid default_layout" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        },
        "layouts": {
            "desktop": [["ide"]]
        },
        "default_layout": "nonexistent"
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Default Layout: nonexistent ❌ (layout not found)"* ]]
}

# Test: validate_show_layouts with no default_layout
@test "validate_show_layouts: handles missing default_layout" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        },
        "layouts": {
            "desktop": [["ide"]]
        }
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Default Layout: None specified"* ]]
}

# Test: validate_show_layouts with too many tags
@test "validate_show_layouts: shows error for too many tags" {
    local manifest_json='{
        "resources": {
            "r1": "cmd1", "r2": "cmd2", "r3": "cmd3", "r4": "cmd4", "r5": "cmd5",
            "r6": "cmd6", "r7": "cmd7", "r8": "cmd8", "r9": "cmd9", "r10": "cmd10"
        },
        "layouts": {
            "too_many": [["r1"], ["r2"], ["r3"], ["r4"], ["r5"], ["r6"], ["r7"], ["r8"], ["r9"], ["r10"]]
        }
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"• too_many: 10 tags ❌"* ]]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"maximum is 9"* ]]
}

# Test: validate_show_layouts with singular tag label
@test "validate_show_layouts: uses correct singular/plural for tag count" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        },
        "layouts": {
            "single": [["ide"]],
            "multiple": [["ide"], ["ide"]]
        }
    }'
    
    run validate_show_layouts "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"• single: 1 tag ✅"* ]]
    [[ "$output" == *"• multiple: 2 tags ✅"* ]]
}

# Test: Integration with validate_manifest function
@test "validate_manifest: includes layout validation in output" {
    # Create a test manifest with layouts
    cat > workon.yaml <<EOF
resources:
  ide: code .
  terminal: alacritty

layouts:
  desktop:
    - [ide]
    - [terminal]

default_layout: desktop
EOF
    
    run validate_manifest
    [ "$status" -eq 0 ]
    [[ "$output" == *"Layouts: 1 defined"* ]]
    [[ "$output" == *"• desktop: 2 tags ✅"* ]]
    [[ "$output" == *"Default Layout: desktop ✅"* ]]
}

# Test: Integration with validate_manifest for no layouts
@test "validate_manifest: handles manifests without layouts" {
    # Create a test manifest without layouts
    cat > workon.yaml <<EOF
resources:
  ide: code .
  terminal: alacritty
EOF
    
    run validate_manifest
    [ "$status" -eq 0 ]
    [[ "$output" == *"Layouts: None defined (using sequential spawning)"* ]]
}

# Test: Integration with validate_manifest for broken layouts
@test "validate_manifest: shows layout errors in full validation" {
    # Create a test manifest with broken layouts
    cat > workon.yaml <<EOF
resources:
  ide: code .

layouts:
  broken:
    - [ide, nonexistent]

default_layout: broken
EOF
    
    run validate_manifest
    [ "$status" -eq 0 ]
    [[ "$output" == *"• broken: 1 tag ❌"* ]]
    [[ "$output" == *"Error:"* ]]
    [[ "$output" == *"undefined resource"* ]]
}