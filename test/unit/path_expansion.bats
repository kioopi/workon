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

@test "relative paths should be expanded to absolute paths" {
    # Arrange
    mkdir -p project/subdir
    cd project
    
    # Create a test file that exists relatively
    echo "test content" > README.md
    echo "test notes" > notes.md
    
    # Create manifest with relative paths
    cat > workon.yaml <<EOF
resources:
  readme: README.md
  notes: vim notes.md
  editor: code .
EOF
    
    # Act - parse the manifest and extract resources
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    # Extract and render the readme resource
    local readme_entry
    readme_entry=$(echo "$resources" | head -1)
    local readme_cmd
    readme_cmd=$(echo "$readme_entry" | base64 -d | jq -r '.value')
    local rendered_readme
    rendered_readme=$(render_template "$readme_cmd")
    
    # Expand relative paths after template rendering
    local expanded_readme
    expanded_readme=$(expand_relative_paths "$rendered_readme")
    
    # Assert - the relative path should be expanded to absolute
    assert_equal "$expanded_readme" "$PWD/README.md"
}

@test "absolute paths should remain unchanged" {
    # Arrange
    mkdir -p project
    cd project
    
    cat > workon.yaml <<EOF
resources:
  editor: /usr/bin/vim
  browser: /usr/bin/firefox
EOF
    
    # Act
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    local editor_entry
    editor_entry=$(echo "$resources" | head -1)
    local editor_cmd
    editor_cmd=$(echo "$editor_entry" | base64 -d | jq -r '.value')
    local rendered_editor
    rendered_editor=$(render_template "$editor_cmd")
    
    # Expand relative paths after template rendering
    local expanded_editor
    expanded_editor=$(expand_relative_paths "$rendered_editor")
    
    # Assert - absolute paths should remain unchanged
    assert_equal "$expanded_editor" "/usr/bin/vim"
}

@test "URLs should remain unchanged" {
    # Arrange
    mkdir -p project
    cd project
    
    cat > workon.yaml <<EOF
resources:
  docs: https://example.com/docs
  local: http://localhost:3000
EOF
    
    # Act
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    local docs_entry
    docs_entry=$(echo "$resources" | head -1)
    local docs_cmd
    docs_cmd=$(echo "$docs_entry" | base64 -d | jq -r '.value')
    local rendered_docs
    rendered_docs=$(render_template "$docs_cmd")
    
    # Expand relative paths after template rendering
    local expanded_docs
    expanded_docs=$(expand_relative_paths "$rendered_docs")
    
    # Assert - URLs should remain unchanged
    assert_equal "$expanded_docs" "https://example.com/docs"
}

@test "commands with relative path arguments should expand paths" {
    # Arrange
    mkdir -p project
    cd project
    
    echo "test content" > config.json
    
    cat > workon.yaml <<EOF
resources:
  editor: vim config.json
  ide: code .
EOF
    
    # Act
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    local editor_entry
    editor_entry=$(echo "$resources" | head -1)
    local editor_cmd
    editor_cmd=$(echo "$editor_entry" | base64 -d | jq -r '.value')
    local rendered_editor
    rendered_editor=$(render_template "$editor_cmd")
    
    # Expand relative paths after template rendering
    local expanded_editor
    expanded_editor=$(expand_relative_paths "$rendered_editor")
    
    # Assert - relative paths in commands should be expanded
    assert_equal "$expanded_editor" "vim $PWD/config.json"
}

@test "mixed paths should be handled correctly" {
    # Arrange
    mkdir -p project
    cd project
    
    echo "test" > local.txt
    
    cat > workon.yaml <<EOF
resources:
  mixed: vim local.txt /etc/hosts https://example.com
EOF
    
    # Act
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    local mixed_entry
    mixed_entry=$(echo "$resources" | head -1)
    local mixed_cmd
    mixed_cmd=$(echo "$mixed_entry" | base64 -d | jq -r '.value')
    local rendered_mixed
    rendered_mixed=$(render_template "$mixed_cmd")
    
    # Expand relative paths after template rendering
    local expanded_mixed
    expanded_mixed=$(expand_relative_paths "$rendered_mixed")
    
    # Assert - should expand relative paths but preserve absolute paths and URLs
    assert_equal "$expanded_mixed" "vim $PWD/local.txt /etc/hosts https://example.com"
}

@test "relative paths with template variables should work" {
    # Arrange
    mkdir -p project
    cd project
    
    export TEST_FILE="test.txt"
    echo "content" > test.txt
    
    cat > workon.yaml <<EOF
resources:
  templated: vim {{TEST_FILE}}
EOF
    
    # Act
    local manifest_json
    manifest_json=$(parse_manifest "$PWD/workon.yaml")
    local resources
    resources=$(extract_resources "$manifest_json")
    
    local templated_entry
    templated_entry=$(echo "$resources" | head -1)
    local templated_cmd
    templated_cmd=$(echo "$templated_entry" | base64 -d | jq -r '.value')
    local rendered_templated
    rendered_templated=$(render_template "$templated_cmd")
    
    # Expand relative paths after template rendering
    local expanded_templated
    expanded_templated=$(expand_relative_paths "$rendered_templated")
    
    # Assert - template variables should be expanded, then paths expanded
    assert_equal "$expanded_templated" "vim $PWD/test.txt"
}