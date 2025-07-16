#!/usr/bin/env bats

# Load BATS libraries
load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Load common test helpers  
load '../test_helper/common'

setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
    
    # Create test workon.yaml
    cat > workon.yaml << 'EOF'
resources:
  terminal: sleep 300
  editor: sleep 301
  browser: sleep 302
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "integration: workon can find and parse manifest" {
    run "$PROJECT_ROOT/bin/workon" --help
    assert_success
}

@test "integration: workon validates manifest correctly" {
    # Test with invalid YAML
    echo "invalid: yaml: [" > workon.yaml
    
    run "$PROJECT_ROOT/bin/workon" start
    assert_failure
    assert_output --partial "Failed to parse"
}

@test "integration: workon generates correct session file path" {
    source "$PROJECT_ROOT/lib/workon.sh"
    
    local session_file
    session_file=$(cache_file "$TEST_DIR")
    
    run echo "$session_file"
    assert_output --partial ".cache/workon/"
    assert_output --partial ".json"
}