# WorkOn — Development Road‑Map

> **Purpose**  A living guide that shows where we are heading and in what order we will ship features.  Each phase produces a usable artifact; later phases layer new capability without refactors.  Keep this file under version control and update it when reality diverges.

---

## Legend

| Symbol         | Meaning                                    |
| -------------- | ------------------------------------------ |
| **✅ Done**     | Feature is implemented on *main*           |
| **🚧 WIP**     | Feature under active development (open PR) |
| **✅ Next**    | Immediately upcoming after current WIP     |
| **🗓 Planned** | Future milestone, no work yet              |
| **⚠️ Gotcha**  | Edge‑case or risk to watch                 |

---

## Milestones

### Phase 0 — Bootstrap   `(tag: v0.0)`  ✅ 


**✅ COMPLETED** (commit c0e92e3) — All infrastructure tasks finished.
| Task                                  | Notes / Resources                                              |
| ------------------------------------- | -------------------------------------------------------------- |
| Initialise Git repo, `bin/`, `README` | `git init`, add MIT LICENSE.                                   |
| Vendor or symlink `` into `bin/`      | For now copy master script; later make it a system dependency. |
| Continuous Shell‑lint                 | Add GitHub Action using ShellCheck.                            |
| Dir structure                         | `bin/` for CLI, `docs/`, `examples/`, `.github/`.              |

### Phase 1 — **Minimal Start‑only**   `(tag: v0.1.0-alpha)` ✅


**✅ COMPLETED** (commit 05e9e63, v0.1.0-alpha) — Full start-only functionality with comprehensive testing.

**Additional work completed:**
- Comprehensive test suite (20+ tests in `test/unit/phase1.bats`)
- Centralized linting with `bin/lint` script for consistent shellcheck execution
- Functional demo project in `examples/demo/` with working `workon.yaml`
- Enhanced error handling and user feedback
| Task                                   | Implementation hints                                        | Gotchas                               |

| -------------------------------------- | ----------------------------------------------------------- | ------------------------------------- |
| **Locate** `workon.yaml` (walk upward) | `while [[ $d != / ]]; do … done`                            | Symlinks / bind‑mounts.               |
| **Parse** YAML → JSON                  | [`yq eval -o=json`](https://mikefarah.gitbook.io/yq/)       | Require yq v4; flags differ in v3.    |
| Expand `{{VAR}}`                       | `envsubst`‑style: `sed -E 's/\{\{([A-Z0-9_]+)\}\}/${\1}/g'` | Missing env‑var → warn not blank‑out. |
| Loop resources, spawn with ``          | No layout logic yet; all on current tag.                    | GUI forks lose PID (tolerated now).   |
| CLI: `workon [path]`                   | Default path = `$PWD`.                                      | Handle spaces in path.                |

### Phase 2 — **Session File & Stop**   `(tag: v0.1)` 🔜

| Task                                 | Resources                                                                  | Tips / Gotchas             |
| ------------------------------------ | -------------------------------------------------------------------------- | -------------------------- |
| Create cache dir `~/.cache/workon`   | Use `${XDG_CACHE_HOME:-$HOME/.cache}`.                                     | Ensure mkdir ‑p.           |
| After spawn: append `{cmd,pid}` JSON | `jq -n --arg cmd "$cmd" --argjson pid $pid '{cmd:$cmd,pid:$pid}' >> $file` | Concurrency — use `flock`. |
| `workon stop`                        | Read file, `kill -TERM`, then `-KILL` after timeout.                       | Stale PIDs → ignore.       |
| Remove session file                  |                                                                            |                            |

### Phase 3 — **Default Layout (tags 1…N)**  `(tag: v0.2)` 🗓

| Task                            | Reference                                             | Gotchas                                         |
| ------------------------------- | ----------------------------------------------------- | ----------------------------------------------- |
| Read `default_layout` row‑array | Already in YAML.                                      | Validate index continuity.                      |
| Spawn per row → tag index       | `awesome-client 'awful.spawn("cmd",{tag=tags[IDX]})'` | Multi‑monitor order differs per user; document. |

### Phase 4 — **Multiple Layout Choice**  `(tag: v0.3)` 🗓

- CLI flag `--layout <name>`
- Interactive picker later (fzf).

### Phase 5 — **Environment Sources**  `(tag: v0.4)` 🗓

- First respect `direnv export bash`; fallback source `.env`.
- Document security note (untrusted repos).

### Phase 6 — **Robust PID capture (client callback)**  `(tag: v0.5)` 🗓

- Use Awesome’s Lua:
  ```lua
  awful.spawn(cmd, { tag = t }, function(c) io.write(c.pid.."\n") end)
  ```
- Pipe that to session writer.
- ⚠️  Needs `< /dev/null` with awesome-client.

### Phase 7 — **Window fallback stop**  `(tag: v0.6)` 🗓

- Lua iterate `client.get()`; match on `pid` or partial `cmd`.
- Careful with RegExp escaping.

### Phase 8 — **Safety & QoL**  `(tag: v0.7)` 🗓

- `--dry-run` prints spawn plan.
- `--unique` aborts if live session exists.
- Stale‑cache warning (>48h).

### Phase 9 — **Per‑resource flags**  `(tag: v0.8)` 🗓

- YAML schema extension:
  ```yaml
  readme:
    cmd: README.md
    persist: true
    tag: docs
  ```
- Need YAML → JSON transformation update.

### Phase 10 — **Multi‑monitor / named tags**  `(tag: v1.0‑rc)` 🗓

- Accept `screen:tag` or literal tag names.
- Use `awful.tag.find_by_name` + `awful.screen`.

### Phase 11 — **Packaging & docs**  `(tag: v1.0)` 🗓

- Debian: `fpm -s dir -t deb -n workon`.
- Homebrew `brew tap org/workon`.
- Man page via Pandoc.

---

## General tips & gotchas

- **Shell quoting** — always build arrays (`cmd=(… )`) before `awesome-client` to avoid double‑quotes hell.
- **YQ 3 vs 4** — v3 uses different CLI; pin `>= 4.2`.
- **Awesome‑client blocking** — It exits only when Lua chunk finishes; printing PID then `io.flush()` is mandatory.
- **Wayland** — *Not officially supported*; X11 PID ↔ window mapping assumed.
- **Testing** — Use Xephyr + nested Awesome for CI.

---

## Useful links

- AwesomeWM awful.spawn docs — [https://awesomewm.org/doc/api/libraries/awful.spawn.html](https://awesomewm.org/doc/api/libraries/awful.spawn.html)
- XDG Base Dir spec — [https://specifications.freedesktop.org/basedir-spec/latest/](https://specifications.freedesktop.org/basedir-spec/latest/)
- yq documentation — [https://mikefarah.gitbook.io/yq/](https://mikefarah.gitbook.io/yq/)
- jq manual — [https://stedolan.github.io/jq/manual/](https://stedolan.github.io/jq/manual/)
- direnv — [https://direnv.net/](https://direnv.net/)
- xdg‑open specification — [https://freedesktop.org/wiki/Specifications/desktop-entry-spec/](https://freedesktop.org/wiki/Specifications/desktop-entry-spec/)

---

> *Keep this file in sync with reality.  Outdated road‑maps are worse than none.*

