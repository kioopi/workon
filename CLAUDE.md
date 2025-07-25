# WorkOn Project Context for AI Assistants

## Project Overview

**WorkOn** is a one-shot project workspace bootstrapper for AwesomeWM that lets developers codify their entire working environment in a single `workon.yaml` file. Running `workon` opens all required resources (IDE, terminals, browsers, documents) on the correct AwesomeWM tags in one command. `workon stop` cleans everything up just as easily.

## Core Architecture

### Key Components
1. **workon** (bash CLI) - Main entry point script
2. **pls-open** - Universal launcher that respects `.desktop` Terminal property
3. **YAML parser** - Uses `yq` to convert YAML → JSON
4. **Template expander** - Uses `envsubst` for `{{VAR}}` expansion
5. **AwesomeWM integration** - Uses `awesome-client` to spawn on specific tags
6. **Session tracking** - JSON files in `~/.cache/workon/` track PIDs for cleanup
7. **Dependency validator** - `bin/check-deps` validates required tools

### Data Flow
```
workon.yaml → yq → JSON → template expansion → pls-open commands → awesome-client → session file
```

### Key Concepts
- **Resources**: Logical names mapped to commands/files/URLs (`ide: code .`)
- **Layouts**: Ordered lists of resource groups assigned to tags
- **Template variables**: `{{VAR}}` placeholders from environment
- **Session files**: JSON records of spawned PIDs for cleanup

## Development Phases

### Phase 0 - Bootstrap v0.0 ✅
**Goal**: Infrastructure foundation with no functionality
- ✅ Git repo with proper structure
- ✅ Documentation and licensing
- ✅ CLI stub (`bin/workon`)
- ✅ Dependency validation (`bin/check-deps`)
- ✅ CI/CD with shellcheck + bats
- ✅ Pre-commit hooks

### Phase 1 - Minimal Start-only v0.1-alpha ✅
- ✅ Locate `workon.yaml` (walk upward from current dir)
- ✅ Parse YAML → JSON with `yq`
- ✅ Expand `{{VAR}}` templates
- ✅ Spawn all resources via `pls-open` on current tag
- ✅ CLI: `workon [path]`

### Phase 2 - Session tracking and stop v0.1.0 ✅ 
**Major Architectural Achievement**: Single Lua Script Architecture
- ✅ Real PID tracking via `awful.spawn()` instead of useless awesome-client PIDs
- ✅ Single `lib/spawn_resources.lua` eliminates bash/AwesomeWM round-trip complexity
- ✅ Enhanced session metadata with window properties for robust cleanup
- ✅ Multi-strategy stop: PID → xdotool → wmctrl fallback hierarchy
- ✅ Security improvements (eliminated shell injection vulnerabilities)
- ✅ Comprehensive test coverage: 59 tests across 6 files (see [docs/test-coverage.md](docs/test-coverage.md))

### Phase 3+ - Layouts, multiple layouts, etc.

## File Structure
```
workon/
├── bin/
│   ├── workon           # Main CLI script
│   ├── pls-open         # Universal launcher (vendored)
│   └── check-deps       # Dependency validator
├── lib/
│   ├── workon.sh        # Core bash library functions
│   └── spawn_resources.lua # AwesomeWM Lua spawn script (Phase 2+)
├── docs/                # Design docs and implementation guides
│   ├── lua_spawn_architecture.md # Architecture documentation
│   ├── roadmap.md       # Development roadmap
│   └── test-coverage.md # Comprehensive test coverage analysis
├── test/unit/           # Bats test files
├── examples/            # Sample workon.yaml files
└── .github/workflows/   # CI configuration
```

## Dependencies

### Runtime
- `bash` 4.0+
- `yq` v4+ (YAML processor)
- `jq` (JSON processor)
- `awesome-client` (AwesomeWM)
- `envsubst` (template expansion)

### Development
- `shellcheck` (linting)
- `bats` (testing)

Use `./bin/check-deps` to validate dependencies.

## Key Design Decisions

1. **Everything declarative in YAML** - No code in manifests
2. **Reuse existing tools** - No custom parsers or window management
3. **PID-plus-window fallback** - Reliable cleanup for forking GUI apps
4. **No Awesome-specific markup in YAML** - Portable to other WMs
5. **Vendor pls-open** - Ensures availability for early testers

## Testing Strategy

- **Unit tests**: bats framework for CLI behavior
- **Linting**: shellcheck for all shell scripts
- **CI**: GitHub Actions with dependency validation
- **Pre-commit hooks**: Automated quality checks
- **Manual testing**: Examples directory with sample projects

## Common Patterns

### Version Management
All scripts use semantic versioning starting with "0.0.0" in Phase 0.

### Error Handling
All bash scripts use `set -euo pipefail` for strict error handling.

### Command Structure
- `workon` - Main command
- `workon --version` - Version info
- `workon --help` - Usage help
- `workon [path]` - Start workspace (Phase 1+)
- `workon stop` - Stop workspace (Phase 2+)

### File Conventions
- Executable scripts in `bin/`
- Tests in `test/unit/*.bats`
- Documentation in `docs/`
- Examples in `examples/`

## Security Considerations

- Template expansion from environment variables
- Execution of commands from YAML files
- Trust model for workon.yaml files in projects
- Session file permissions in `~/.cache/workon/`

## Integration Points

### AwesomeWM
- Uses `awesome-client` for Lua script execution
- Spawns applications on specific tags via `awful.spawn`
- Captures PIDs through client callbacks
- Manages windows and tags

### XDG Standards
- Follows XDG Base Directory specification
- Uses XDG cache directory for session files
- Integrates with desktop entry system via `pls-open`

## Current Status (Phase 3 Complete)

**WorkOn now supports complete layout-based workspace management!**

### ✅ **Completed Phases:**
- **Phase 0**: Bootstrap infrastructure, documentation, CI/CD
- **Phase 1**: Basic start-only functionality with YAML parsing and resource spawning
- **Phase 2**: Complete session tracking and stop functionality with robust PID management
- **Phase 3**: Layout support with tag-based resource distribution and comprehensive validation

### 🚀 **Enhanced Capabilities:**
- Start workspaces from `workon.yaml` manifests with layout support
- Template expansion with `{{VAR}}` syntax
- Session tracking with real PID capture
- Robust stop functionality with multi-strategy cleanup
- **Layout-based spawning**: Resources distributed across AwesomeWM tags per layout configuration
- **Multiple layout support**: Named layouts with `default_layout` fallback
- **Comprehensive validation**: Layout references, resource existence, and tag limits
- **Backward compatibility**: Projects without layouts work unchanged
- **Enhanced testing**: 70+ automated tests with comprehensive coverage

### 🎯 **Next Step: Phase 4** - Multiple Layout Choice
- CLI flag `--layout <name>` for selecting specific layouts
- Interactive layout picker (future enhancement)