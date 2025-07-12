# WorkOn — Phase 0 Implementation Guide (Bootstrap / v0.0)

> **Goal of Phase 0**  Lay a clean, test‑ready foundation so that later phases can iterate quickly.  By the end of this phase you should have:
>
> - A Git repository with predictable directory layout
> - Basic licensing & documentation
> - The `` entry‑point script stub in `bin/`
> - `` available in the repo for callers who do not have it system‑wide
> - Continuous Shell lint via GitHub Actions
>
> No functionality yet—just infrastructure.

---

## 1. Recommended directory layout

```text
workon/                  # git root
├── bin/                 # all CLI scripts (added to PATH during install)
│   ├── workon           # empty stub for now
│   └── pls-open         # current snapshot (symlink or copy)
├── docs/                # design docs, roadmap, guides
│   ├── ROADMAP.md       # already created
│   └── PHASE0_IMPLEMENTATION.md   # this file
├── examples/            # toy projects for manual testing later
├── .github/
│   └── workflows/
│       ├── lint.yml     # shellcheck CI
│       └── bats.yml     # test runner
├── LICENSE              # MIT
└── README.md            # high‑level description
```

*Why this layout?*  `bin/` can be added to `$PATH` via `make install` or a package later; docs live alongside code; CI configs isolated in `.github/`.

---

## 2. Initialise the repository

```bash
mkdir workon && cd workon
git init -b main
printf 'MIT\n' >LICENSE   # or use github web form
cat >README.md <<'EOF'
# WorkOn — project workspace bootstrapper
[short paragraph]
EOF
mkdir -p bin docs examples .github/workflows
```

> **Tip:** keep commits atomic. One commit = one of the tasks below.

---

## 3. Add `pls-open`

Phase 1 and later rely on this helper but your early testers may not have it pre‑installed.

We will for now just have a copy of the `pls-open` script in `bin/`. 
Later, we can replace it with a bin-stub that calls the system-installed `pls-open` if available, 
or give the user instructions to install it.

Document in README.

---

## 4. Stub the `workon` CLI

Create ``:

```bash
#!/usr/bin/env bash
set -euo pipefail

VERSION="0.0.0"

case ${1:-} in
  --version|-v)
        echo "workon $VERSION"; exit 0;;
  --help|-h|*)
        cat <<EOF
workon — no features yet (Phase 0)
Usage: workon [--version] [--help]
EOF
        exit 0;;
esac
```

`chmod +x bin/workon`

*Why a stub?*  Lets tooling (shellcheck, test harness) attach now, ensures packaging scripts know the file exists.

---

## 5. Continuous Shell lint

Add ``:

```yaml
name: lint
on: [push, pull_request]
jobs:
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: run shellcheck
        run: shellcheck bin/*
```

*Best practice:* fail PR if any warning appears (`-e SC` not yet necessary).

---

## 6. Test harness with bats

Bats is installed on the system. 
Document in README that it is required for development and testing.

Scaffold directory:

```bash
mkdir -p test/unit
cat > test/unit/version.bats <<'EOF'
#!/usr/bin/env bats
@test "workon --version exits 0" {
  run ./bin/workon --version
  [ "$status" -eq 0 ]
}
EOF
```

Extend `lint.yml`.

This gives the CI green ticks even before real features appear.

---

## 7. Verify Phase 0 locally

```bash
./bin/workon --help        # prints stub help
./bin/pls-open -n nvim README.md   # dry‑run still works
shellcheck bin/*           # 0 warnings
```

If using Bats:

```bash
./test/bats/bin/bats test/unit
```

Commit everything:

```bash
git add .t
git commit -m "Phase 0 – repo bootstrap"
```

---

## 8. Useful links & docs

- ShellCheck — [https://www.shellcheck.net](https://www.shellcheck.net)
- GitHub Actions shellcheck action — [https://github.com/marketplace/actions/shellcheck-linter](https://github.com/marketplace/actions/shellcheck-linter)
- Bats-core — [https://github.com/bats-core/bats-core](https://github.com/bats-core/bats-core)
- XDG Base Dir Spec — [https://specifications.freedesktop.org/basedir-spec/latest/](https://specifications.freedesktop.org/basedir-spec/latest/)

