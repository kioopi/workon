# Common test helpers for WorkOn project

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Helper function to test find_manifest functionality
test_find_manifest() {
    local search_dir="$1"
    bash -c "
        set -euo pipefail
        find_manifest() {
            local dir
            dir=\$(realpath \"\${1:-\$PWD}\")
            
            while [[ \$dir != / ]]; do
                if [[ -f \$dir/workon.yaml ]]; then
                    printf '%s/workon.yaml' \"\$dir\"
                    return 0
                fi
                dir=\$(dirname \"\$dir\")
            done
            
            return 1
        }
        find_manifest '$search_dir'
    "
}

# Helper function to test render_template functionality
test_render_template() {
    local input="$1"
    bash -c "
        set -euo pipefail
        render_template() {
            local input=\"\$1\"
            local converted
            converted=\$(printf '%s' \"\$input\" | sed -E 's/\{\{([A-Za-z_][A-Za-z0-9_]*)(:-[^}]*)?\}\}/\${\1\2}/g')
            (set +u; eval \"printf '%s' \\\"\$converted\\\"\")
        }
        render_template '$input'
    "
}

# Helper function to create a minimal valid workon.yaml
create_minimal_manifest() {
    local resources="${1:-test: echo hello}"
    cat > workon.yaml <<EOF
resources:
  $resources
EOF
}

# Helper function to create invalid YAML for testing
create_invalid_yaml() {
    cat > workon.yaml <<EOF
invalid: yaml: syntax [
EOF
}

# Helper function to create manifest with missing resources section
create_manifest_without_resources() {
    cat > workon.yaml <<EOF
layouts:
  desktop: []
EOF
}

# Helper function to create manifest with empty resources
create_empty_resources_manifest() {
    cat > workon.yaml <<EOF
resources: {}
EOF
}

# Helper function to run workon command with proper path
run_workon() {
    run "$PROJECT_ROOT/bin/workon" "$@"
}

# Helper function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper function to skip test if dependency is missing
require_command() {
    local cmd="$1"
    local message="${2:-$cmd is required for this test}"
    
    if ! command_exists "$cmd"; then
        skip "$message"
    fi
}