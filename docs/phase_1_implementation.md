# WorkOn — Phase 1 Implementation Guide (v0.1‑alpha)

> **Scope:** Implements the first runnable slice of WorkOn: *starting* all resources listed in `workon.yaml` on the **current** AwesomeWM tag (no layout logic, no stop command yet). Deliverable is the `workon` CLI in `$PATH` plus a sample project showing it in action.

---

## 1. Directory & file scaffold

```text
workon/               # project repo
├── bin/
│   ├── workon        # phase‑1 wrapper script (bash)
│   └── pls-open # vendored helper (symlink or copy)
├── docs/
│   └── PHASE1_IMPLEMENTATION.md   # this file
├── examples/
│   └── demo/        # tiny sample project
│       ├── workon.yaml
│       └── README.md
└── .github/workflows/lint.yml      # ShellCheck CI (optional)
```

### Shell best‑practice

- Use `/usr/bin/env bash`, `set -euo pipefail`, `IFS=$'\n\t'` inside loops.
- Keep single‑purpose functions; unit‑test them with **Bats‑core** where feasible.

---

## 2. External tool quick‑refs

| Tool                | Why we need it                                         | Install                                                              | Docs                                                                           |
| ------------------- | ------------------------------------------------------ | -------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **yq v4**           | YAML → JSON conversion (`yq eval -o=json`)             | `sudo apt install yq`                                                | [https://mikefarah.gitbook.io/yq/](https://mikefarah.gitbook.io/yq/)           |
| **envsubst**        | Variable substitution `{{VAR}}` → `$VAR`               | `sudo apt install gettext-base`                                      | [https://www.gnu.org/software/gettext/](https://www.gnu.org/software/gettext/) |
| **awesome-client**  | Remote control of AwesomeWM (`awesome-client '<lua>'`) | part of `awesome` pkg                                                | [https://awesomewm.org/](https://awesomewm.org/)                               |
| **pls-open**   | Launch shim honoring `Terminal=true`                   | our script                                                           | see repo                                                                       |
| **ShellCheck**      | Lint bash in CI                                        | `apt install shellcheck`                                             | [https://www.shellcheck.net/](https://www.shellcheck.net/)                     |
| **Bats‑core** (opt) | Bash tests                                             | `git submodule add https://github.com/bats-core/bats-core test/bats` | [https://bats-core.readthedocs.io/](https://bats-core.readthedocs.io/)         |

---

## 3. CLI contract (Phase 1)

```text
workon [PROJECT_PATH]
    • PROJECT_PATH   directory containing (or nested under) a workon.yaml
                     default = $PWD
```

Exit codes:

| Code | Meaning                                                   |
| ---- | --------------------------------------------------------- |
| 0    | Successfully spawned all resources                        |
| 2    | fatal error (yaml not found, missing tools, invalid file) |

---

## 4. Algorithm

1. \*\*Locate \*\*\`\`
   ```bash
   find_manifest() {
       local dir=$(realpath "$1")
       while [[ $dir != / ]]; do
           [[ -f $dir/workon.yaml ]] && { echo "$dir/workon.yaml"; return; }
           dir=$(dirname "$dir")
       done
       return 1
   }
   ```
2. **Parse YAML → JSON**
   ```bash
   manifest_json=$(yq eval -o=json '.' "$manifest") || die "yq failed"
   resources=$(jq -r '.resources | to_entries[] | @base64' <<<"$manifest_json")
   ```
3. **Environment substitution** *Accept only **`{{VAR}}`** patterns.*
   ```bash
   render() { 
       local input="$1"
       # Convert {{VAR}} to ${VAR} format, allowing alphanumeric and underscore
       printf '%s' "$input" | sed -E 's/\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}/${\1}/g' | envsubst
   }
   ```
4. **Spawn each resource** (current tag)
   ```bash
   while read -r entry; do
       name=$(printf '%s' "$entry" | base64 -d | jq -r '.key')
       raw=$(printf '%s' "$entry" | base64 -d | jq -r '.value') 
       cmd=$(render "$raw")
       # Properly escape command for awesome-client
       escaped_cmd=$(printf '%s' "pls-open $cmd" | sed 's/"/\\"/g')
       awesome-client "awful.spawn(\"$escaped_cmd\")" &
   done <<<"$resources"
   wait  # ensure script exits only after all awful.spawn queued
   ```
5. **Done** – print summary.

---

## 5. Testing strategy

### 5.1 Unit tests (Bats)

- \`\` – feed various directory layouts; expect correct path or failure.
- \`\` – ensure missing env vars are warned, output unchanged.

Run locally:

```bash
bats test/*.bats
```

CI: call Bats inside GitHub Actions after ShellCheck.

### 5.2 Integration smoke test (manual)

1. Launch Xephyr nested X server:
   ```bash
   Xephyr :1 -screen 1280x800 &
   export DISPLAY=:1
   awesome &
   ```
2. From host terminal:
   ```bash
   cd examples/demo && ../../bin/workon
   ```
3. Verify IDE, README etc. open in Xephyr window.
4. Close Xephyr → observe script exits 0.

---

## 6. Example manifest (examples/demo/workon.yaml)

```yaml
resources:
  ide: code .
  readme: README.md
  docs: https://awesomewm.org/
  term: alacritty .
```

Place a dummy README.md next to it so the resource resolves.

---

## 7. Common pitfalls & fixes

| Problem                 | Symptom                             | Fix                                                  |
| ----------------------- | ----------------------------------- | ---------------------------------------------------- |
| yq v3 installed         | `unknown flag: -o`                  | `sudo snap remove yq`; reinstall v4 binary.          |
| env var not substituted | `web: "{{URL}}"` opens literally    | Export URL before running; or document `.env`.       |
| Awesome not running     | `awesome-client: unable to connect` | Run inside login Awesome session; for CI use Xephyr. |
| Invalid YAML structure  | `jq: error parsing`                  | Validate YAML has `resources:` key; check syntax.    |
| Command escaping issues | Spawn failures with special chars   | Use proper shell quoting in awesome-client calls.    |

---

## 8. Incremental upgrade path

- **Keep PID** capture out for now – Phase 1 doesn’t need stop.
- Function shells are already modular → Session writing will slot into spawn loop in Phase 2.

---
