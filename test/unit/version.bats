#!/usr/bin/env bats

@test "workon --version exits 0" {
    run ./bin/workon --version
    [ "$status" -eq 0 ]
    [[ "$output" =~ workon\ 0\.0\.0 ]]
}

@test "workon --help exits 0" {
    run ./bin/workon --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "no features yet" ]]
}

@test "check-deps script exists and is executable" {
    [ -x "./bin/check-deps" ]
}

@test "pls-open is executable" {
    [ -x "./bin/pls-open" ]
}

@test "lint script exists and is executable" {
    [ -x "./bin/lint" ]
}

@test "lint script runs successfully" {
    run ./bin/lint --quiet
    [ "$status" -eq 0 ]
}