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
