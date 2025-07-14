# Common test helpers for WorkOn project

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Source the real workon library functions
source "$PROJECT_ROOT/lib/workon.sh"


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