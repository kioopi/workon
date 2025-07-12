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

### Phase 0 (Current) - Bootstrap v0.0
**Goal**: Infrastructure foundation with no functionality
- ✅ Git repo with proper structure
- ✅ Documentation and licensing
- ⏳ CLI stub (`bin/workon`)
- ⏳ Dependency validation (`bin/check-deps`)
- ⏳ CI/CD with shellcheck + bats
- ⏳ Pre-commit hooks

### Phase 1 (Next) - Minimal Start-only v0.1-alpha
- Locate `workon.yaml` (walk upward from current dir)
- Parse YAML → JSON with `yq`
- Expand `{{VAR}}` templates
- Spawn all resources via `pls-open` on current tag
- CLI: `workon [path]`

### Phase 2+ - Session tracking, layouts, multiple layouts, etc.

## File Structure
```
workon/
├── bin/
│   ├── workon           # Main CLI script
│   ├── pls-open         # Universal launcher (vendored)
│   └── check-deps       # Dependency validator
├── docs/                # Design docs and implementation guides
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

## Current Status (Phase 0)

The project is in bootstrap phase focusing on infrastructure:
- Repository structure established
- Documentation and roadmap complete
- Testing and CI framework being implemented
- No functional features yet - just tooling foundation

Next step is implementing the basic functionality in Phase 1.