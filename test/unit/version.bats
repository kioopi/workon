#!/usr/bin/env bats

# Load BATS libraries (system installation paths)
load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

# Load common test helpers
load '../test_helper/common'

@test "workon --version: exits successfully and shows version" {
    run ./bin/workon --version
    
    assert_success
    assert_output --partial "workon 0.1.0"
}

@test "workon --help: exits successfully and shows usage" {
    run ./bin/workon --help
    
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "PROJECT_PATH"
}

@test "check-deps script: exists and is executable" {
    # Using manual [ -x ] check since assert_file_executable is not available in standard bats-assert
    [ -x "./bin/check-deps" ]
}

@test "pls-open script: exists and is executable" {
    # Using manual [ -x ] check since assert_file_executable is not available in standard bats-assert
    [ -x "./bin/pls-open" ]
}

@test "lint script: exists and is executable" {
    # Using manual [ -x ] check since assert_file_executable is not available in standard bats-assert
    [ -x "./bin/lint" ]
}

@test "lint script: runs successfully without errors" {
    run ./bin/lint --quiet
    
    assert_success
    refute_output
}