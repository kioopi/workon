#!/usr/bin/env bats

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Source the layout module
    source "$PROJECT_ROOT/lib/layout.sh"
}

teardown() {
    # Clean up temporary files
    cd "$BATS_TEST_TMPDIR"
    rm -rf "$TEST_PROJECT_DIR"
}

# Test: layout_exists with layouts present
@test "layout_exists: returns true when layouts section exists" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {"desktop": [["ide"]]}
    }'
    
    run layout_exists "$manifest_json"
    [ "$status" -eq 0 ]
}

# Test: layout_exists with no layouts
@test "layout_exists: returns false when no layouts section" {
    local manifest_json='{
        "resources": {"ide": "code ."}
    }'
    
    run layout_exists "$manifest_json"
    [ "$status" -ne 0 ]
}

# Test: layout_get_default with valid default
@test "layout_get_default: returns default layout name" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {"desktop": [["ide"]]},
        "default_layout": "desktop"
    }'
    
    run layout_get_default "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = "desktop" ]
}

# Test: layout_get_default with no default
@test "layout_get_default: fails when no default_layout specified" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {"desktop": [["ide"]]}
    }'
    
    run layout_get_default "$manifest_json"
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

# Test: layout_validate_exists with existing layout
@test "layout_validate_exists: succeeds for existing layout" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {"desktop": [["ide"]], "minimal": [["ide"]]}
    }'
    
    run layout_validate_exists "$manifest_json" "desktop"
    [ "$status" -eq 0 ]
}

# Test: layout_validate_exists with non-existing layout
@test "layout_validate_exists: fails for non-existing layout" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {"desktop": [["ide"]]}
    }'
    
    run layout_validate_exists "$manifest_json" "nonexistent"
    [ "$status" -ne 0 ]
}

# Test: layout_get_tag_limit returns constant
@test "layout_get_tag_limit: returns maximum tag count" {
    run layout_get_tag_limit
    [ "$status" -eq 0 ]
    [ "$output" = "9" ]
}

# Test: layout_has_valid_structure with array
@test "layout_has_valid_structure: succeeds for array layout" {
    local layout_json='[["ide"], ["terminal"]]'
    
    run layout_has_valid_structure "$layout_json"
    [ "$status" -eq 0 ]
}

# Test: layout_has_valid_structure with non-array
@test "layout_has_valid_structure: fails for non-array layout" {
    local layout_json='"not an array"'
    
    run layout_has_valid_structure "$layout_json"
    [ "$status" -ne 0 ]
}

# Test: layout_get_row_count
@test "layout_get_row_count: returns correct count" {
    local layout_json='[["ide"], ["terminal", "web"]]'
    
    run layout_get_row_count "$layout_json"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

# Test: layout_extract_by_name
@test "layout_extract_by_name: extracts correct layout" {
    local manifest_json='{
        "resources": {"ide": "code .", "terminal": "alacritty"},
        "layouts": {
            "desktop": [["ide"], ["terminal"]],
            "minimal": [["ide"]]
        }
    }'
    
    run layout_extract_by_name "$manifest_json" "minimal"
    [ "$status" -eq 0 ]
    [ "$output" = '[["ide"]]' ]
}

# Test: layout_get_all_names
@test "layout_get_all_names: returns all layout names" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {
            "desktop": [["ide"]],
            "minimal": [["ide"]],
            "full": [["ide"]]
        }
    }'
    
    run layout_get_all_names "$manifest_json"
    [ "$status" -eq 0 ]
    [[ "$output" == *"desktop"* ]]
    [[ "$output" == *"minimal"* ]]
    [[ "$output" == *"full"* ]]
}

# Test: layout_get_count
@test "layout_get_count: returns correct layout count" {
    local manifest_json='{
        "resources": {"ide": "code ."},
        "layouts": {
            "desktop": [["ide"]],
            "minimal": [["ide"]]
        }
    }'
    
    run layout_get_count "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

# Test: layout_get_count with no layouts
@test "layout_get_count: returns 0 when no layouts" {
    local manifest_json='{
        "resources": {"ide": "code ."}
    }'
    
    run layout_get_count "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# Test: layout_validate_resource_references with valid references
@test "layout_validate_resource_references: succeeds with valid resources" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        }
    }'
    local layout_json='[["ide"], ["terminal"]]'
    
    run layout_validate_resource_references "$manifest_json" "$layout_json" "test_layout"
    [ "$status" -eq 0 ]
}

# Test: layout_validate_resource_references with invalid reference
@test "layout_validate_resource_references: fails with invalid resource" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        }
    }'
    local layout_json='[["ide"], ["nonexistent"]]'
    
    run layout_validate_resource_references "$manifest_json" "$layout_json" "test_layout"
    [ "$status" -ne 0 ]
    [[ "$output" == *"references undefined resource: 'nonexistent'"* ]]
}

# Test: layout_validate_comprehensive with valid layout
@test "layout_validate_comprehensive: succeeds for completely valid layout" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal"]]
        }
    }'
    
    run layout_validate_comprehensive "$manifest_json" "desktop"
    [ "$status" -eq 0 ]
}

# Test: layout_validate_comprehensive with too many rows
@test "layout_validate_comprehensive: fails when too many rows" {
    local manifest_json='{
        "resources": {
            "r1": "cmd1", "r2": "cmd2", "r3": "cmd3", "r4": "cmd4", "r5": "cmd5",
            "r6": "cmd6", "r7": "cmd7", "r8": "cmd8", "r9": "cmd9", "r10": "cmd10"
        },
        "layouts": {
            "too_many": [["r1"], ["r2"], ["r3"], ["r4"], ["r5"], ["r6"], ["r7"], ["r8"], ["r9"], ["r10"]]
        }
    }'
    
    run layout_validate_comprehensive "$manifest_json" "too_many"
    [ "$status" -ne 0 ]
    [[ "$output" == *"maximum is 9"* ]]
}