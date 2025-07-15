#!/bin/bash
# Test script for Lua spawn architecture
# Runs all tests related to the new Lua spawning functionality

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=== Testing Lua Spawn Architecture ==="
echo

echo "1. Testing JSON module functionality..."
bats test/unit/lua_spawn.bats --filter "json module"
echo

echo "2. Testing session module functionality..."
bats test/unit/lua_spawn.bats --filter "session module" 
echo

echo "3. Testing integration components..."
bats test/unit/phase2.bats --filter "launch_all_resources_with_session"
echo

echo "4. Testing critical integration paths..."
bats test/unit/lua_spawn.bats --filter "integration"
echo

echo "=== All Lua Spawn Tests Passed! ==="
echo "The Lua spawn architecture is properly tested and protected against regressions."