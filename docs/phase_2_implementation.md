# WorkOn — Phase 2 Implementation Guide (Session Cache & `workon stop` / v0.1)

> **Scope**  Phase 2 adds life‑cycle management: every resource spawned by `workon start` is written to a *session file*, and `workon stop` tears that session back down.  We still run everything on the **current tag** (Phase 1 behaviour); layout logic comes in Phase 3.  No PID‑robust callback yet (that’s Phase 6).
>
> **Deliverables**
>
> 1. `workon start` now writes `~/.cache/workon/<sha1>.json` (one file per live session).
> 2. `workon stop` kills all processes recorded in that file (TERM → KILL) and removes it.
> 3. CI unit tests verify file structure and stop logic with stubs.

---

## 0. Pre‑requisites

- Phase 1 merged (`workon start` opening resources on current tag).
- `jq` ≥ 1.6 available in the environment.
- ShellCheck & Bats already wired in CI.

---

## 1. Design decisions

| Choice                                | Rationale                                                           |
| ------------------------------------- | ------------------------------------------------------------------- |
| **One session file per project‑root** | Keeps multi‑repo workflows separate; avoids global locks.           |
| **Location** `$XDG_CACHE_HOME/workon` | Follows XDG spec; defaults to `~/.cache/workon` when env var unset. |
| **Filename** `sha1(<project‑root>)`   | Collision‑free yet deterministic; symlink‑safe (`realpath`).        |
| **JSON array** of objects             | Easy to append with `jq`, easy to parse later.                      |
| **Fields** `cmd`, `pid`, `timestamp`  | Minimal info; timestamp helps stale‑session detection later.        |
| **Flock per session file**            | Prevents concurrent `workon start` races in split panes.            |

Session entry example:

```json
{
  "cmd": "pls-open nvim README.md",
  "pid": 4242,
  "timestamp": 1710441037
}
```

---

## 2. Implementation steps

### 2.1 Utility functions (add to `bin/workon`)

```bash
# ─── Cache helpers ────────────────────────────────────────────────────────
cache_dir()   { printf '%s/workon' "${XDG_CACHE_HOME:-$HOME/.cache}"; }
cache_file()  { sha1=$(printf '%s' "$project_root" | sha1sum | cut -d' ' -f1); printf '%s/%s.json' "$(cache_dir)" "$sha1"; }

with_lock() {   # with_lock <file> <command...>
    local lock="$1"; shift
    mkdir -p "$(dirname "$lock")"
    exec 200>"$lock.lock"
    flock -n 200 || { echo "Session file busy" >&2; exit 2; }
    "$@"
}

json_append() { # json_append <json object>
    local tmp
    tmp=$(mktemp)
    if [[ -s $session_file ]]; then
        jq '. + [env.NEW]' --argjson NEW "$1" "$session_file" >"$tmp"
    else
        jq -n --argjson NEW "$1" '[ $NEW ]' >"$tmp"
    fi
    mv "$tmp" "$session_file"
}
```

### 2.2 Modify **spawn loop** in `workon start`

Right after the `awesome-client` call (Phase 1):

```bash
pid=$!     # PID of awesome-client; we want the spawned shell’s PID.
wait $pid 2>/dev/null &   # detach; we only need $pid value now
entry=$(jq -n --arg cmd "$cmd" --argjson pid $pid --argjson ts $(date +%s) \
        '{cmd:$cmd,pid:$pid,timestamp:$ts}')
with_lock "$session_file" json_append "$entry"
```

### 2.3 Implement ``

Hook into CLI parser:

```bash
case ${1:-} in
  stop)
       action=stop; shift;;
  start|"" )
       action=start;;
  *) die "unknown action: $1";;
esac
```

Implementation:

```bash
stop_session() {
    [[ -f $session_file ]] || { echo "No live session for $project_root"; exit 0; }
    with_lock "$session_file" _stop_impl
}

_stop_impl() {
    mapfile -t pids < <(jq -r '.[].pid' "$session_file")
    for p in "${pids[@]}"; do
        if kill -0 "$p" 2>/dev/null; then
            kill "$p" && sleep 3
            kill -9 "$p" 2>/dev/null || true
        fi
    done
    rm -f "$session_file" "$session_file.lock"
}
```

Call `stop_session` when `action=stop`.

---

## 3. Testing strategy

### 3.1 Unit tests (Bats‑core)

| Test file                        | Focus                                                          |
| -------------------------------- | -------------------------------------------------------------- |
| `test/unit/cache_path.bats`      | Correct SHA1 filename for given project path.                  |
| `test/unit/json_append.bats`     | Append into empty and non‑empty session file; JSON validity.   |
| `test/unit/stop_kills_pids.bats` | Stub `kill` command to record signals instead of sending them. |

> **Hint:** Place mock binaries earlier in `$PATH` inside test, e.g.:
>
> ```bash
> test/stubs/kill() { echo "kill $*" >>"$TMP/kill_log"; }
> PATH="$(pwd)/test/stubs:$PATH"
> ```

### 3.2 Integration (manual / Xephyr)

1. Run `workon` inside demo project.
2. `ls ~/.cache/workon/*.json` → file exists and lists PIDs.
3. `workon stop` → windows close, file removed.
4. Re‑run `workon stop` again → prints “No live session…”.

### 3.3 CI wiring

Add a Bats job in `ci.yml`:

```yaml
- name: unit tests
  run: test/bats/bin/bats test/unit
```

---

## 4. Tool quick‑links

| Tool / cmd  | Purpose                            | Docs / manpage                                                                                           |
| ----------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **jq**      | read/append JSON arrays            | [https://stedolan.github.io/jq/manual/](https://stedolan.github.io/jq/manual/)                           |
| **flock**   | simple file locks (`man 1 flock`)  | [https://man7.org/linux/man-pages/man1/flock.1.html](https://man7.org/linux/man-pages/man1/flock.1.html) |
| **kill**    | send signals (TERM, KILL)          | `man 1 kill`                                                                                             |
| **sha1sum** | deterministic session filename     | `man 1 sha1sum`                                                                                          |
| **mktemp**  | atomic file swap during JSON write | `man 1 mktemp`                                                                                           |

---

## 5. Common pitfalls & fixes

| Pitfall                             | Symptom                                    | Fix / Advice                                         |
| ----------------------------------- | ------------------------------------------ | ---------------------------------------------------- |
| JSON "null" when `jq` appends       | Session file grows but entries become null | Ensure `--argjson` receives *valid* JSON (integers). |
| Stale session file after crash      | `workon start` refuses – file busy         | Provide `--force` later; for now instruct `rm`.      |
| Race when two terminals run `start` | One loses lock, prints "busy"              | OK by design; user decides which session is active.  |
| PIDs reused after reboot            | `stop` kills wrong processes               | Future Phase 8 stale‑cache detection will fix.       |

---

## 6. Documentation updates

- **README** – add new *Session Handling* section.
- **ROADMAP.md** – mark Phase 2 tasks **✅ Done** once merged.
- **man page skeleton** – note `start`, `stop` sub‑commands.

---

## 7. Merge checklist

-

> **Unix philosophy in action:** WorkOn keeps session state in plain JSON, manipulated by existing CLI workhorses (`jq`, `flock`, `kill`).  No daemons, no bespoke binary formats, no lockfiles beyond what the kernel already provides.

---

*Phase 3 will extend the spawn loop to multi‑tag layouts—get Phase 2 merged first so stop/kill remains stable during that refactor.*

