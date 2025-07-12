# WorkOn — Phase 0 Implementation Guide (Bootstrap / v0.0)

> **Goal of Phase 0**  Lay a clean, test‑ready foundation so that later phases can iterate quickly.  By the end of this phase you should have:
>
> - A Git repository with predictable directory layout
> - Basic licensing & documentation with proper `.gitignore`
> - The `workon` entry‑point script stub in `bin/`
> - `pls-open` available in the repo for callers who do not have it system‑wide
> - Continuous Shell lint via GitHub Actions with bats testing
> - Pre-commit hooks for automated quality checks
> - Dependency validation script
>
> No functionality yet—just infrastructure.

---

## 1. Recommended directory layout

```text
workon/                  # git root
├── bin/                 # all CLI scripts (added to PATH during install)
│   ├── workon           # empty stub for now
│   ├── pls-open         # current snapshot (executable)
│   └── check-deps       # dependency validation script
├── docs/                # design docs, roadmap, guides
│   ├── ROADMAP.md       # already created
│   └── PHASE0_IMPLEMENTATION.md   # this file
├── examples/            # toy projects for manual testing later
├── test/                # test infrastructure
│   └── unit/            # unit tests with bats
│       └── version.bats # basic version test
├── .github/
│   └── workflows/
│       └── ci.yml       # shellcheck + bats CI
├── .git/
│   └── hooks/
│       └── pre-commit   # automated linting
├── .gitignore           # shell development patterns
├── LICENSE              # MIT with proper copyright
└── README.md            # high‑level description
```

*Why this layout?*  `bin/` can be added to `$PATH` via `make install` or a package later; docs live alongside code; CI configs isolated in `.github/`; testing infrastructure ready from start.

---

## 2. Initialize the repository

```bash
mkdir workon && cd workon
git init -b main
mkdir -p bin docs examples test/unit .github/workflows
```

> **Tip:** keep commits atomic. One commit = one of the tasks below.

---

## 3. Create essential files

### 3.1. Add proper `.gitignore`

Create `.gitignore` with shell development patterns:

```bash
cat >.gitignore <<'EOF'
# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Editor files
*~
*.swp
*.swo
.vscode/
.idea/

# Shell development
*.log
*.tmp

# WorkOn specific
.env
.env.local
workon.yaml
EOF
```

### 3.2. Create proper MIT LICENSE

```bash
cat >LICENSE <<'EOF'
MIT License

Copyright (c) $(date +%Y) WorkOn Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

### 3.3. Make `pls-open` executable

Phase 1 and later rely on this helper but your early testers may not have it pre‑installed.

```bash
chmod +x bin/src/pls-open
ln -sf src/pls-open bin/pls-open  # or copy if symlink not preferred
```

Document in README that `pls-open` is vendored for convenience.

---

## 4. Create dependency validation script

Create `bin/check-deps` to validate required tools:

```bash
cat >bin/check-deps <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# check-deps — validate WorkOn development dependencies

VERSION="0.0.0"
ERRORS=0

check_command() {
    local cmd="$1" desc="$2" install_hint="$3"
    if command -v "$cmd" >/dev/null 2>&1; then
        printf "✓ %s (%s)\n" "$cmd" "$desc"
    else
        printf "✗ %s missing — %s\n" "$cmd" "$desc"
        printf "  Install: %s\n" "$install_hint"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "WorkOn dependency check v$VERSION"
echo

# Core shell tools
check_command "bash" "Shell interpreter" "system package manager"
check_command "shellcheck" "Shell linting" "apt install shellcheck / brew install shellcheck"

# Testing (development only)
if [[ ${1:-} != "--runtime-only" ]]; then
    check_command "bats" "Test framework" "npm install -g bats / brew install bats-core"
fi

# Future dependencies (commented for now)
# check_command "yq" "YAML processor" "brew install yq / snap install yq"
# check_command "jq" "JSON processor" "apt install jq / brew install jq"
# check_command "awesome-client" "AwesomeWM client" "apt install awesome"

echo
if [[ $ERRORS -eq 0 ]]; then
    echo "All dependencies satisfied ✓"
    exit 0
else
    echo "$ERRORS missing dependencies ✗"
    exit 1
fi
EOF

chmod +x bin/check-deps
```

---

## 5. Stub the `workon` CLI

Create `bin/workon`:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.0.0"

case ${1:-} in
  --version|-v)
        echo "workon $VERSION"; exit 0;;
  --help|-h|*)
        cat <<EOF
workon — no features yet (Phase 0)
Usage: workon [--version] [--help]
EOF
        exit 0;;
esac
```

`chmod +x bin/workon`

*Why a stub?*  Lets tooling (shellcheck, test harness) attach now, ensures packaging scripts know the file exists.

---

## 6. Set up pre-commit hook

Create automated linting on every commit:

```bash
cat >.git/hooks/pre-commit <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Pre-commit hook for WorkOn
echo "Running pre-commit checks..."

# Check dependencies first
if ! ./bin/check-deps --runtime-only >/dev/null 2>&1; then
    echo "⚠️  Warning: Some dependencies missing (run ./bin/check-deps for details)"
fi

# Run shellcheck on all shell scripts
if command -v shellcheck >/dev/null 2>&1; then
    echo "Running shellcheck..."
    if ! shellcheck bin/workon bin/check-deps 2>/dev/null; then
        echo "❌ ShellCheck failed. Fix the issues above."
        exit 1
    fi
    echo "✓ ShellCheck passed"
else
    echo "⚠️  ShellCheck not available, skipping..."
fi

echo "✓ Pre-commit checks passed"
EOF

chmod +x .git/hooks/pre-commit
```

---

## 7. Continuous Integration

Add `.github/workflows/ci.yml`:

```yaml
name: CI
on: [push, pull_request]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y shellcheck
          npm install -g bats
      - name: Check dependencies
        run: ./bin/check-deps
      - name: Run shellcheck
        run: shellcheck bin/workon bin/check-deps
      - name: Run tests
        run: bats test/unit/
```

*Best practice:* fail PR if any warning appears. Includes both linting and testing.

---

## 8. Test harness with bats

Create comprehensive test structure:

```bash
cat >test/unit/version.bats <<'EOF'
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
EOF
```

This gives comprehensive CI validation even before real features appear.

---

## 9. Update README with development info

Update `README.md` to include development requirements:

```bash
cat >>README.md <<'EOF'

## Development

### Requirements

- `bash` 4.0+
- `shellcheck` (for linting)
- `bats` (for testing)

Run `./bin/check-deps` to verify all dependencies.

### Testing

```bash
# Run all tests
bats test/unit/

# Run linting
shellcheck bin/*
```

### Pre-commit hooks

Pre-commit hooks automatically run shellcheck on every commit. If you need to skip them:

```bash
git commit --no-verify
```
EOF
```

---

## 10. Verify Phase 0 locally

```bash
# Test basic functionality
./bin/workon --help              # prints stub help
./bin/pls-open -n nvim README.md # dry‑run still works
./bin/check-deps                 # validates dependencies

# Run quality checks
shellcheck bin/*                 # 0 warnings
bats test/unit/                  # all tests pass

# Test pre-commit hook
git add . && git commit -m "test commit" # should run pre-commit checks
```

Commit everything:

```bash
git add .
git commit -m "Phase 0 — repository bootstrap with full infrastructure"
```

---

## 11. Useful links & docs

- ShellCheck — [https://www.shellcheck.net](https://www.shellcheck.net)
- GitHub Actions shellcheck action — [https://github.com/marketplace/actions/shellcheck-linter](https://github.com/marketplace/actions/shellcheck-linter)
- Bats-core — [https://github.com/bats-core/bats-core](https://github.com/bats-core/bats-core)
- XDG Base Dir Spec — [https://specifications.freedesktop.org/basedir-spec/latest/](https://specifications.freedesktop.org/basedir-spec/latest/)
- Pre-commit hooks — [https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks](https://git-scm.com/book/en/v2/Customizing-Git-Git-Hooks)
