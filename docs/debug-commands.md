# Debug Commands

This document describes the debug and introspection commands available in WorkOn to help users troubleshoot issues and understand the tool's behavior.

## Commands Overview

### `workon info`
Displays general system information about the WorkOn installation and environment.

**Usage:**
```bash
workon info
```

**Output:**
- Cache directory path
- WorkOn version and installation directory
- Dependency status (which required tools are available)
- Current working directory
- Manifest status (found/not found in current directory)

### `workon info sessions`
Lists all active session files in the cache directory.

**Usage:**
```bash
workon info sessions
```

**Output:**
- List of session files with metadata:
  - Session file name (SHA1 hash)
  - Associated project directory
  - Creation time
  - Number of resources tracked
  - File size

### `workon info session [<project_dir>]`
Shows detailed information about a specific session.

**Usage:**
```bash
workon info session                    # Current directory
workon info session ~/my-project       # Specific project
```

**Output:**
- Session file path
- Project directory
- List of all resources in the session:
  - Resource name
  - PID (with status: running/stopped)
  - Process command
  - Window class/instance (if available)
  - Spawn time

### `workon validate [<project_dir>]`
Validates the `workon.yaml` file in the specified directory.

**Usage:**
```bash
workon validate                        # Current directory
workon validate ~/my-project          # Specific project
```

**Output:**
- Manifest file path
- YAML syntax validation results
- Structure validation (required fields)
- Resource validation (each resource entry)
- Template variable validation
- Success/error summary

**Exit Codes:**
- 0: Valid manifest
- 1: Invalid manifest (with detailed error messages)
- 2: No manifest found

### `workon resolve <resource>`
Shows the resolved command that would be executed for a given resource.

**Usage:**
```bash
workon resolve ide
workon resolve "nvim config.lua"
workon resolve README.md
```

**Output:**
- Resource name
- Raw command from manifest
- Template variables found
- Environment variable values
- Final resolved command
- Whether the command/file exists

**Exit Codes:**
- 0: Resource found and resolved
- 1: Resource not found in manifest
- 2: No manifest found

## Implementation Details

### Code Organization
All debug commands are implemented as functions in `lib/workon.sh`:
- `workon_info()` - Main info command with subcommand handling
- `workon_validate()` - Manifest validation
- `workon_resolve()` - Resource resolution

### Code Reuse
The debug commands leverage existing library functions:
- `find_manifest()` - Locate workon.yaml files
- `parse_manifest()` - Parse and validate YAML
- `cache_dir()` / `cache_file()` - Session file management
- `read_session()` - Session data access
- `render_template()` - Template variable expansion

### Error Handling
Debug commands follow the existing error handling patterns:
- Use `die()` for fatal errors that should exit
- Print warnings to stderr for non-fatal issues
- Return appropriate exit codes for scripting

### Testing Strategy
Each command has comprehensive test coverage:
- Unit tests for individual functions
- Integration tests for command-line interface
- Edge case testing (missing files, corrupted data)
- Mock testing for external dependencies

## Development Phases

### Phase 1: Foundation (`workon info`)
- Basic system information display
- Dependency checking
- Environment status

### Phase 2: Validation (`workon validate`)
- YAML syntax validation
- Manifest structure validation
- Detailed error reporting

### Phase 3: Session Management (`workon info sessions/session`)
- Session file listing
- Session detail inspection
- PID status checking

### Phase 4: Resource Resolution (`workon resolve`)
- Resource lookup from manifest
- Template expansion
- Command resolution and validation

## Usage Examples

### Troubleshooting Workflow
1. Check system status: `workon info`
2. Validate manifest: `workon validate`
3. Check active sessions: `workon info sessions`
4. Inspect specific session: `workon info session`
5. Test resource resolution: `workon resolve <resource>`

### Common Use Cases
- **Setup verification**: `workon info` to check dependencies
- **YAML debugging**: `workon validate` to find syntax errors
- **Session cleanup**: `workon info sessions` to see what's running
- **Resource testing**: `workon resolve` to test commands before running
- **Troubleshooting**: `workon info session` to see what failed to start

## Security Considerations
- Session file access respects file permissions
- Template expansion uses safe environment variable handling
- No execution of resolved commands (read-only operations)
- Proper handling of special characters in file paths

## Future Enhancements
- JSON output format for scripting (`--json` flag)
- Filtering options for session listing
- Resource dependency visualization
- Performance metrics and timing information