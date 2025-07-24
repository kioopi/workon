#!/usr/bin/env bash
# WorkOn Library Functions
# Shared functions for workon CLI tool

# Source modular components
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=lib/config.sh disable=SC1091
source "$SCRIPT_DIR/config.sh"
# shellcheck source=lib/manifest.sh disable=SC1091
source "$SCRIPT_DIR/manifest.sh"
# shellcheck source=lib/template.sh disable=SC1091
source "$SCRIPT_DIR/template.sh"
# shellcheck source=lib/path.sh disable=SC1091
source "$SCRIPT_DIR/path.sh"
# shellcheck source=lib/session.sh disable=SC1091
source "$SCRIPT_DIR/session.sh"
# shellcheck source=lib/spawn.sh disable=SC1091
source "$SCRIPT_DIR/spawn.sh"
# shellcheck source=lib/cleanup.sh disable=SC1091
source "$SCRIPT_DIR/cleanup.sh"

# Source command modules
# shellcheck source=lib/commands/utils.sh disable=SC1091
source "$SCRIPT_DIR/commands/utils.sh"
# shellcheck source=lib/commands/info.sh disable=SC1091
source "$SCRIPT_DIR/commands/info.sh"
# shellcheck source=lib/commands/validate.sh disable=SC1091
source "$SCRIPT_DIR/commands/validate.sh"
# shellcheck source=lib/commands/resolve.sh disable=SC1091
source "$SCRIPT_DIR/commands/resolve.sh"

# Backward compatibility aliases for config functions
die() { config_die "$@"; }

load_project_dirs() { config_load_project_dirs "$@"; }
find_manifest() { manifest_find "$@"; }
render_template() { template_render "$@"; }
expand_relative_paths() { path_expand_relative "$@"; }
expand_word_if_path() { path_expand_word_if_path "$@"; }
should_expand_as_path() { path_should_expand_as_path "$@"; }
expand_to_absolute_path() { path_expand_to_absolute "$@"; }
resource_exists() { path_resource_exists "$@"; }

# Launch a resource via awesome-client with proper escaping
# Spawn functions moved to lib/spawn.sh

# Legacy functions removed - session entries are now created by Lua script

parse_manifest() { manifest_parse "$@"; }

extract_resources() { manifest_extract_resources "$@"; }

# ─── Session Management Functions ───────────────────────────────────────────

cache_dir() { config_cache_dir; }
cache_file() { config_cache_file "$@"; }

# Session functions moved to lib/session.sh

# Cleanup functions moved to lib/cleanup.sh

check_dependencies() { config_check_dependencies "$@"; }

# ─── Utility Functions ──────────────────────────────────────────────────────

# Check if a single dependency is available
# Session functions moved to lib/session.sh

# ─── Path Expansion Utilities ──────────────────────────────────────────────
# Functions moved to lib/path.sh

# ─── Template Processing Utilities ─────────────────────────────────────────

process_template_variables() { template_process_variables "$@"; }

show_template_analysis() { template_analyze "$@"; }

# ─── Debug Command Functions ────────────────────────────────────────────────
# Command functions moved to lib/commands/ modules


# Route workon info commands to the info module
workon_info() {
    info_route_commands "$@"
}

extract_template_variables() { template_extract_variables "$@"; }

# Legacy function aliases (will be removed after full refactoring)
check_single_dependency() { utils_check_dependency "$@"; }
parse_yaml_to_json() { utils_parse_yaml "$@"; }
parse_resource_entry() { utils_parse_resource "$@"; }
show_basic_info() { info_show_basic "$@"; }
show_sessions_list() { info_show_sessions_list "$@"; }
show_session_details() { info_show_session_details "$@"; }

# Validate YAML syntax and print status
# Route workon validate commands to the validate module
workon_validate() {
    validate_manifest "$@"
}

# Route workon resolve commands to the resolve module
workon_resolve() {
    resolve_resource "$@"
}
