#!/usr/bin/env bats
# Tests for config.sh module
# These tests verify configuration management functionality

load "../test_helper/common"

setup() {
    # Source the config module
    source "$PROJECT_ROOT/lib/config.sh"
    # Save original environment
    ORIGINAL_WORKON_PROJECTS_PATH="${WORKON_PROJECTS_PATH:-}"
    ORIGINAL_XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"
    ORIGINAL_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-}"
    
    # Clean environment for tests
    unset WORKON_PROJECTS_PATH
    unset XDG_CACHE_HOME
    unset XDG_CONFIG_HOME
}

teardown() {
    # Restore original environment
    if [[ -n "$ORIGINAL_WORKON_PROJECTS_PATH" ]]; then
        export WORKON_PROJECTS_PATH="$ORIGINAL_WORKON_PROJECTS_PATH"
    fi
    if [[ -n "$ORIGINAL_XDG_CACHE_HOME" ]]; then
        export XDG_CACHE_HOME="$ORIGINAL_XDG_CACHE_HOME"
    fi
    if [[ -n "$ORIGINAL_XDG_CONFIG_HOME" ]]; then
        export XDG_CONFIG_HOME="$ORIGINAL_XDG_CONFIG_HOME"
    fi
}

# Test config_load_project_dirs function
@test "config_load_project_dirs: returns WORKON_PROJECTS_PATH when set" {
    export WORKON_PROJECTS_PATH="$HOME/projects:$HOME/workspace"
    
    run config_load_project_dirs
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$HOME/projects" ]
    [ "${lines[1]}" = "$HOME/workspace" ]
}

@test "config_load_project_dirs: returns empty when no config" {
    # Set XDG_CONFIG_HOME to a non-existent directory
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/no-config"
    
    run config_load_project_dirs
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "config_load_project_dirs: reads from config file when env var not set" {
    
    local config_dir="$BATS_TEST_TMPDIR/config"
    local config_file="$config_dir/workon/config.yaml"
    
    mkdir -p "$(dirname "$config_file")"
    cat > "$config_file" <<EOF
projects_path:
  - ~/dev
  - ~/work
EOF
    
    export XDG_CONFIG_HOME="$config_dir"
    
    run config_load_project_dirs
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "~/dev" ]
    [ "${lines[1]}" = "~/work" ]
}

# Test config_cache_dir function
@test "config_cache_dir: returns default cache directory" {
        
    run config_cache_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.cache/workon" ]
}

@test "config_cache_dir: respects XDG_CACHE_HOME" {
        
    export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/custom-cache"
    
    run config_cache_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$BATS_TEST_TMPDIR/custom-cache/workon" ]
}

# Test config_cache_file function
@test "config_cache_file: generates session file path from project directory" {
        
    local test_project="$BATS_TEST_TMPDIR/test-project"
    mkdir -p "$test_project"
    
    run config_cache_file "$test_project"
    [ "$status" -eq 0 ]
    
    # Should contain cache directory and SHA1 hash
    [[ "$output" == *"/.cache/workon/"* ]]
    [[ "$output" == *".json" ]]
}

# Test config_check_dependencies function
@test "config_check_dependencies: passes when all deps available" {
        
    run config_check_dependencies
    [ "$status" -eq 0 ]
}

@test "config_check_dependencies: fails when dep missing" {
    # Temporarily override the command builtin to simulate missing yq
    PATH="/nonexistent:$PATH" run bash -c "
        source '$PROJECT_ROOT/lib/config.sh'
        command() {
            if [[ \$1 == '-v' && \$2 == 'yq' ]]; then
                return 1
            fi
            builtin command \"\$@\"
        }
        config_check_dependencies
    "
    [ "$status" -eq 2 ]
    [[ "$output" == *"Missing required dependencies"* ]]
}

# Test config_die function
@test "config_die: exits with error code 2" {
        
    run config_die "test error message"
    [ "$status" -eq 2 ]
    [[ "$output" == *"workon: test error message"* ]]
}