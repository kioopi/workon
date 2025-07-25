#!/usr/bin/env bats

load "../test_helper/common"

setup() {
    # Create a temporary directory for test files
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$TEST_PROJECT_DIR"
    cd "$TEST_PROJECT_DIR"
    
    # Source the manifest module
    source "$PROJECT_ROOT/lib/manifest.sh"
}

teardown() {
    # Clean up temporary files
    cd "$BATS_TEST_TMPDIR"
    rm -rf "$TEST_PROJECT_DIR"
}

# Test: manifest_extract_layout with no layouts section (backward compatibility)
@test "manifest_extract_layout: returns empty when no layouts section exists" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        }
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Test: manifest_extract_layout with no default_layout (backward compatibility)
@test "manifest_extract_layout: returns empty when layouts exist but no default_layout" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal"]]
        }
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# Test: manifest_extract_layout with valid default_layout
@test "manifest_extract_layout: extracts default_layout when specified" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal"]]
        },
        "default_layout": "desktop"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = '[["ide"],["terminal"]]' ]
}

# Test: manifest_extract_layout with specific layout name
@test "manifest_extract_layout: extracts specific layout when name provided" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty",
            "web": "firefox"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal"]],
            "full": [["ide", "terminal"], ["web"]]
        },
        "default_layout": "desktop"
    }'
    
    run manifest_extract_layout "$manifest_json" "full"
    [ "$status" -eq 0 ]
    [ "$output" = '[["ide","terminal"],["web"]]' ]
}

# Test: manifest_extract_layout with nonexistent layout
@test "manifest_extract_layout: fails when requested layout does not exist" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "desktop": [["ide"], ["terminal"]]
        },
        "default_layout": "desktop"
    }'
    
    run manifest_extract_layout "$manifest_json" "nonexistent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Layout 'nonexistent' not found in manifest"* ]]
}

# Test: manifest_extract_layout with layout referencing undefined resource
@test "manifest_extract_layout: fails when layout references undefined resource" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty"
        },
        "layouts": {
            "desktop": [["ide"], ["undefined_resource"]]
        },
        "default_layout": "desktop"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Layout 'desktop' references undefined resource: 'undefined_resource'"* ]]
}

# Test: manifest_extract_layout with too many rows (>9 tags)
@test "manifest_extract_layout: fails when layout has more than 9 rows" {
    local manifest_json='{
        "resources": {
            "r1": "cmd1", "r2": "cmd2", "r3": "cmd3", "r4": "cmd4", "r5": "cmd5",
            "r6": "cmd6", "r7": "cmd7", "r8": "cmd8", "r9": "cmd9", "r10": "cmd10"
        },
        "layouts": {
            "too_many": [["r1"], ["r2"], ["r3"], ["r4"], ["r5"], ["r6"], ["r7"], ["r8"], ["r9"], ["r10"]]
        },
        "default_layout": "too_many"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Layout 'too_many' has 10 rows, but maximum is 9"* ]]
}

# Test: manifest_extract_layout with layout that is not an array
@test "manifest_extract_layout: fails when layout is not an array" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        },
        "layouts": {
            "invalid": "not an array"
        },
        "default_layout": "invalid"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Layout 'invalid' must be an array of resource groups"* ]]
}

# Test: manifest_extract_layout with complex valid layout
@test "manifest_extract_layout: handles complex multi-row layout correctly" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty",
            "web": "firefox",
            "docs": "evince README.pdf",
            "notes": "vim notes.md"
        },
        "layouts": {
            "development": [
                ["ide"],
                ["terminal", "web"],
                ["docs", "notes"]
            ]
        },
        "default_layout": "development"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = '[["ide"],["terminal","web"],["docs","notes"]]' ]
}

# Test: manifest_extract_layout with empty layout array
@test "manifest_extract_layout: handles empty layout array" {
    local manifest_json='{
        "resources": {
            "ide": "code ."
        },
        "layouts": {
            "empty": []
        },
        "default_layout": "empty"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = '[]' ]
}

# Test: manifest_extract_layout with mixed resource types
@test "manifest_extract_layout: handles layout with various resource types" {
    local manifest_json='{
        "resources": {
            "ide": "code .",
            "terminal": "alacritty",
            "web_local": "http://localhost:3000",
            "web_remote": "https://example.com",
            "file": "/path/to/file.txt"
        },
        "layouts": {
            "mixed": [
                ["ide"],
                ["terminal", "web_local"],
                ["web_remote", "file"]
            ]
        },
        "default_layout": "mixed"
    }'
    
    run manifest_extract_layout "$manifest_json"
    [ "$status" -eq 0 ]
    [ "$output" = '[["ide"],["terminal","web_local"],["web_remote","file"]]' ]
}