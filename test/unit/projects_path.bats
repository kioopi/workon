#!/usr/bin/env bats

# Load BATS libraries (system installation paths)
load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Load common test helpers
load '../test_helper/common'

setup() {
    ORIG_DIR="$PWD"
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"

    # Source library for direct function calls
    source "$PROJECT_ROOT/lib/workon.sh"
}

teardown() {
    cd "$ORIG_DIR"
    rm -rf "$TEST_DIR"
}

@test "find_manifest: searches WORKON_PROJECTS_PATH for project name" {
    mkdir -p "$TEST_DIR/projects/foo"
    create_minimal_manifest > "$TEST_DIR/projects/foo/workon.yaml"

    export WORKON_PROJECTS_PATH="$TEST_DIR/projects"

    run find_manifest foo

    assert_success
    assert_output "$TEST_DIR/projects/foo/workon.yaml"
}

@test "find_manifest: uses config file when environment unset" {
    mkdir -p "$TEST_DIR/glob/bar"
    create_minimal_manifest > "$TEST_DIR/glob/bar/workon.yaml"

    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - $TEST_DIR/glob
CFG

    unset WORKON_PROJECTS_PATH || true

    run find_manifest bar

    assert_success
    assert_output "$TEST_DIR/glob/bar/workon.yaml"
}

@test "find_manifest: fails when project not found in search paths" {
    export WORKON_PROJECTS_PATH="$TEST_DIR/none"

    run find_manifest missing

    assert_failure
    refute_output
}

# Security tests
@test "find_manifest: rejects project names with path traversal" {
    export WORKON_PROJECTS_PATH="$TEST_DIR/projects"

    # Test a path that definitely doesn't exist as a file or directory
    run find_manifest '../../../nonexistent/path'

    assert_failure
    assert_output --partial "Invalid project name"
}

@test "find_manifest: rejects project names with special characters" {
    export WORKON_PROJECTS_PATH="$TEST_DIR/projects"

    run find_manifest "proj@ct"

    assert_failure
    assert_output --partial "Invalid project name"
}

@test "find_manifest: accepts valid project names" {
    mkdir -p "$TEST_DIR/projects/valid-project_123"
    create_minimal_manifest > "$TEST_DIR/projects/valid-project_123/workon.yaml"

    export WORKON_PROJECTS_PATH="$TEST_DIR/projects"

    run find_manifest valid-project_123

    assert_success
    assert_output "$TEST_DIR/projects/valid-project_123/workon.yaml"
}

# Error handling tests
@test "load_project_dirs: fails with malformed YAML config" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - valid_path
invalid_yaml: [
CFG

    unset WORKON_PROJECTS_PATH || true

    run load_project_dirs

    assert_failure
    assert_output --partial "invalid YAML syntax"
}

@test "load_project_dirs: fails with invalid projects_path format" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path: "not_an_array"
CFG

    unset WORKON_PROJECTS_PATH || true

    run load_project_dirs

    assert_failure
    assert_output --partial "must be an array of strings"
}

@test "load_project_dirs: handles missing projects_path gracefully" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
other_config: value
CFG

    unset WORKON_PROJECTS_PATH || true

    run load_project_dirs

    assert_success
    refute_output
}

@test "load_project_dirs: fails with unreadable config file" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    echo "projects_path: []" > "$XDG_CONFIG_HOME/workon/config.yaml"
    chmod 000 "$XDG_CONFIG_HOME/workon/config.yaml"

    unset WORKON_PROJECTS_PATH || true

    run load_project_dirs

    assert_failure
    assert_output --partial "not readable"
}

@test "find_manifest: handles tilde expansion in config paths" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    mkdir -p "$TEST_DIR/home/projects/tilde-test"
    create_minimal_manifest > "$TEST_DIR/home/projects/tilde-test/workon.yaml"

    export HOME="$TEST_DIR/home"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - ~/projects
CFG

    unset WORKON_PROJECTS_PATH || true

    run find_manifest tilde-test

    assert_success
    assert_output "$TEST_DIR/home/projects/tilde-test/workon.yaml"
}

@test "find_manifest: skips non-existent directories in config" {
    mkdir -p "$TEST_DIR/real/myproject"
    create_minimal_manifest > "$TEST_DIR/real/myproject/workon.yaml"

    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - $TEST_DIR/nonexistent
  - $TEST_DIR/real
CFG

    unset WORKON_PROJECTS_PATH || true

    run find_manifest myproject

    assert_success
    assert_output "$TEST_DIR/real/myproject/workon.yaml"
}

# Cache functionality tests
@test "load_project_dirs: caches config file results" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - $TEST_DIR/path1
  - $TEST_DIR/path2
CFG

    unset WORKON_PROJECTS_PATH || true

    # First call should parse and cache
    run load_project_dirs
    assert_success
    local first_output="$output"

    # Second call should use cache (same output)
    run load_project_dirs
    assert_success
    assert_output "$first_output"
}

@test "load_project_dirs: invalidates cache when config file changes" {
    export XDG_CONFIG_HOME="$TEST_DIR/config"
    mkdir -p "$XDG_CONFIG_HOME/workon"
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - $TEST_DIR/original
CFG

    unset WORKON_PROJECTS_PATH || true

    # First call
    run load_project_dirs
    assert_success
    assert_output "$TEST_DIR/original"

    # Wait to ensure different mtime
    sleep 1
    
    # Modify config file
    cat > "$XDG_CONFIG_HOME/workon/config.yaml" <<CFG
projects_path:
  - $TEST_DIR/modified
CFG

    # Second call should detect change and reparse
    run load_project_dirs
    assert_success
    assert_output "$TEST_DIR/modified"
}
