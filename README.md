## **WorkOn — One-shot project workspace bootstrapper**

### 1. Problem we solve

Modern projects often require **several tools and documents** open at once—
an IDE, a terminal running a process manager, the project’s README, a browser with a couple of URLs, maybe a log viewer.
Manually restoring that constellation each day is error-prone and time-consuming, and closing every window again is equally tedious.

**WorkOn** lets you codify that constellation in a single `workon.yaml` file checked into the project.
Running

```bash
workon            # inside the repo
# or
workon ~/path/to/project
```

brings up every required resource on the correct AwesomeWM tag(s) in one shot.
`workon stop` cleans the slate just as easily.

### 2. Core concepts

| Concept               | What it is                                                                                         | Example                                                                  |
| --------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| **Resource**          | A *logical name* mapped to a launch command, file path, or URL.                                    | `ide: code .`  •  `readme: README.md`                                    |
| **Layout**            | An ordered list of resource groups. Each row is assigned to a tag (workspace).                     | `desktop: <br>  - [ide] <br>  - [web, admin] <br>  - [terminal, readme]` |
| **Template variable** | `{{VAR}}` placeholder expanded from the shell environment or `.env`.                               | `web: "{{ NEXT_PUBLIC_SERVER_URL }}"`                                    |
| **Session file**      | JSON record of every PID / window spawned, stored under `~/.cache/workon/`. Enables `workon stop`. |                                                                          |
| **Backend tools**     | Existing utilities WorkOn orchestrates rather than re-implements.                                  | `pls-open`, `awesome-client`, `yq`, `jq`                            |

### 3. High-level architecture

```
           ┌────────────────────┐
           │ workon (bash)      │  CLI front-end
           └─────────┬──────────┘
                     │
    ┌────────────────▼──────────────────┐
    │ Parse workon.yaml (yq → jq)       │
    └────────────────┬──────────────────┘
                     │ resources + layout
           ┌─────────▼──────────┐
           │ Template expander  │  envsubst / bash
           └─────────┬──────────┘
                     │ rendered commands
    ┌────────────────▼──────────────────┐
    │ Spawn via awesome-client          │
    │   awful.spawn(\"pls-open …\")│
    └────────────────┬──────────────────┘
                     │ c.pid + tag
           ┌─────────▼──────────┐
           │ Session writer     │ → ~/.cache/workon/<hash>.json
           └────────────────────┘
```

* **Start pathway**

  1. **Locate project root** (walk up for `workon.yaml`).
  2. **Load environment** (`direnv` or `.env`).
  3. **Parse YAML → JSON** with `yq`; pick requested layout (`default_layout` if none).
  4. Expand templates; convert each resource to an **`pls-open`** or `xdg-open` command.
  5. For every tag row call **`awesome-client`** to run `awful.spawn()` on that tag.
  6. In the Lua *client callback* capture the final window’s **PID** and append to the session file.

* **Stop pathway**

  1. Load session file.
  2. For each entry: `kill -TERM pid`, escalate to `-KILL` if necessary.
  3. If PID is gone but windows linger, use `awesome-client` to find and `c:kill()` them.
  4. Remove session file.

### 4. Key design decisions

* **Everything is declarative** in YAML; no code inside manifests.
* **Reuse existing tools** instead of re-implementing parsers or window management.
* **PID-plus-window fallback** makes cleanup reliable even for forking GUI apps.
* **No Awesome-specific markup in YAML** — resources are portable to other tiling WMs if you swap the spawn adapter.

### 5. Minimal viable feature set

1. `workon start` — open all resources on current tag.
2. `workon stop` — graceful teardown via stored PIDs.
3. Layout rows → tag indices.
4. Variable expansion from environment.

Everything else (named tags, multiple monitors, resource flags, safety switches) layers on top without breaking the base flow.

---

With those pieces WorkOn gives any contributor a **single command** to recreate and later dismiss the exact working environment the project expects, boosting onboarding speed and day-to-day productivity while staying just a thin wrapper around time-tested Unix utilities.

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
shellcheck bin/workon bin/check-deps bin/src/pls-open
```

### Pre-commit hooks

Pre-commit hooks automatically run shellcheck on every commit. If you need to skip them:

```bash
git commit --no-verify
```

### Included Tools

This repository includes a vendored copy of `pls-open` in `bin/src/pls-open` for convenience. This ensures the tool is available even if not installed system-wide during early development phases.

