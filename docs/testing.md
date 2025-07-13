# Testing Guide

This document describes the testing strategy and practices for the WorkOn project.

## Overview

WorkOn uses the [BATS (Bash Automated Testing System)](https://bats-core.readthedocs.io/) framework for testing all shell scripts and CLI functionality. BATS provides a structured way to write tests for bash scripts with proper assertions, setup/teardown, and clear output.

## Test Organization

### Directory Structure

```
test/
├── bats/              # BATS framework (git submodule)
├── test_helper/       # Shared test utilities
│   ├── bats-support/  # BATS support library (git submodule)
│   ├── bats-assert/   # BATS assertion library (git submodule)
│   └── common.bash    # Project-specific test helpers
└── unit/              # Unit test files
    ├── version.bats   # Basic CLI functionality tests
    ├── phase1.bats    # Phase 1 feature tests
    └── *.bats         # Additional test files
```

### Test Files

- **`version.bats`** - Tests basic CLI functionality (--version, --help, script existence)
- **`phase1.bats`** - Tests Phase 1 features (manifest discovery, template expansion, resource spawning)
- Future phases will have dedicated test files

## Testing Strategy

### Unit Tests
- Test individual functions in isolation
- Test CLI interface behavior
- Test error handling and edge cases
- Test template expansion and YAML parsing

### Integration Tests
- Test complete workflows with real YAML files
- Test interaction between components
- Test error propagation through the system

### Smoke Tests  
- Basic functionality verification
- Dependency validation
- Script execution and exit codes

## Writing Tests

### Basic Test Structure

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    load 'test_helper/common'
    
    # Test-specific setup
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
}

teardown() {
    # Cleanup
    rm -rf "$TEST_DIR"
}

@test "descriptive test name" {
    # Arrange
    echo "resources: {test: echo hello}" > workon.yaml
    
    # Act
    run workon --version
    
    # Assert
    assert_success
    assert_output --partial "workon 0.1.0-alpha"
}
```

### Assertion Patterns

#### Status Assertions
```bash
# Success/failure
assert_success
assert_failure

# Specific exit codes
assert_equal "$status" 2
```

#### Output Assertions
```bash
# Exact output match
assert_output "expected output"

# Partial output match
assert_output --partial "substring"

# Regular expression match
assert_output --regexp "pattern.*"

# Empty output
refute_output

# Specific line assertions
assert_line "expected line"
assert_line -n 0 "first line"
assert_line --partial "substring in line"
```

#### File Assertions
```bash
# File existence
assert_file_exists "path/to/file"
assert_file_not_exists "path/to/file"

# File permissions
assert_file_executable "script"
```

### Best Practices

1. **Use descriptive test names** that explain what is being tested
   ```bash
   @test "find_manifest: locates workon.yaml in parent directory"
   ```

2. **Follow Arrange-Act-Assert pattern**
   ```bash
   @test "template expansion: handles undefined variables gracefully" {
       # Arrange
       unset UNDEFINED_VAR || true
       
       # Act  
       run render_template "Hello {{UNDEFINED_VAR}}"
       
       # Assert
       assert_success
       assert_output "Hello "
   }
   ```

3. **Use proper setup/teardown** for test isolation
   ```bash
   setup() {
       TEST_DIR=$(mktemp -d)
       cd "$TEST_DIR"
   }
   
   teardown() {
       cd "$ORIG_DIR"
       rm -rf "$TEST_DIR"
   }
   ```

4. **Test both success and failure cases**
   ```bash
   @test "workon: succeeds with valid manifest"
   @test "workon: fails with missing manifest"
   @test "workon: fails with invalid YAML syntax"
   ```

5. **Use helper functions** for complex setup or repeated logic
   ```bash
   create_test_manifest() {
       local resources="$1"
       cat > workon.yaml <<EOF
   resources:
     $resources
   EOF
   }
   ```

## Test Categories

### Core Function Tests
- `find_manifest()` - Manifest discovery logic
- `render_template()` - Template variable expansion
- `workon_start()` - Main application logic

### CLI Interface Tests
- Argument parsing (`--version`, `--help`)
- Error handling and exit codes
- Output formatting and messages

### Integration Tests
- End-to-end workflows
- YAML parsing and validation
- Resource spawning (mocked in CI)

### Error Handling Tests
- Invalid YAML files
- Missing dependencies
- File permission issues
- Network connectivity (future)

## Running Tests

### Local Development
```bash
# Run all tests
bats test/unit/

# Run specific test file
bats test/unit/phase1.bats

# Run with verbose output
bats --verbose-run test/unit/

# Run specific test
bats test/unit/phase1.bats --filter "find_manifest"
```

### Continuous Integration
Tests run automatically on every push and pull request via GitHub Actions:

```yaml
- name: Run tests
  run: bats test/unit/
```

## Test Data and Fixtures

### Temporary Test Data
Tests use temporary directories created in `setup()` for isolation:

```bash
setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
}
```

### Test Manifests
Create minimal YAML files for testing:

```bash
# Valid minimal manifest
echo "resources: {test: echo hello}" > workon.yaml

# Invalid manifest
cat > workon.yaml <<EOF
invalid: yaml: syntax [
EOF
```

### Environment Variables
Set and unset variables as needed for template testing:

```bash
export TEST_VAR="value"
unset UNDEFINED_VAR || true
```

## Debugging Tests

### Verbose Output
```bash
# Show command output during test runs
bats --verbose-run test/unit/phase1.bats
```

### Debug Specific Tests
```bash
# Add debug output to tests (prints to stderr)
@test "debug example" {
    echo "Debug info" >&3
    run some_command
    echo "Status: $status" >&3
    echo "Output: $output" >&3
    assert_success
}
```

### Test Isolation Issues
- Ensure `setup()`/`teardown()` properly isolates tests
- Check for environment variable pollution
- Verify temporary directory cleanup

## Coverage Goals

- **Core functions**: 100% coverage of all public functions
- **CLI interface**: All command-line options and arguments
- **Error paths**: All error conditions and edge cases
- **Integration**: Key workflows and user scenarios

## Future Testing Enhancements

### Phase 2+
- Session file management tests
- PID tracking and cleanup verification
- Multi-tag layout testing

### Integration Testing
- Real AwesomeWM integration (using Xvfb)
- Network resource testing
- File system permission testing

### Performance Testing
- Large YAML file handling
- Template expansion performance
- Startup time benchmarks

## Maintenance

### Adding New Tests
1. Create test file following naming convention
2. Follow established patterns and use shared helpers
3. Add to CI workflow if needed
4. Update this documentation

### Refactoring Tests
1. Maintain backward compatibility where possible
2. Update shared helpers rather than individual tests
3. Run full test suite after changes
4. Update documentation as needed

### Dependencies
- Keep BATS libraries updated via git submodules
- Monitor for breaking changes in BATS ecosystem
- Test with multiple bash versions when possible