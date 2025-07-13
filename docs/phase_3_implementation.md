# WorkOn — Phase 3 Implementation Guide (Default Layout / v0.2)

> **Scope of Phase 3**  Extend `workon start` so each **layout row** is spawned on a **distinct AwesomeWM tag** (workspace).  We keep the “current screen” assumption and simple ascending tag indices `1, 2, 3…`.  No named‑tag, multi‑monitor or `workon stop` logic yet.
>
> By the end of this phase:
>
> - `workon` reads `default_layout` (or `--layout <name>` CLI flag – *optional for Phase 3*).
> - Resources in the first row appear on tag 1, second row on tag 2, etc.
> - Error if layout references an undefined resource or tag index exceeds number of rows.
> - Session‑file writing from Phase 2 continues unchanged.

---

## 0. Pre‑requisites

- Phase 2 delivered: `` with session file.
- Repo passes ShellCheck & Bats CI.
- You have at least AwesomeWM 4.3 installed locally or inside Xephyr.

---

## 1. YAML additions & validation

```yaml
# workon.yaml (excerpt)
layouts:
  desktop:
    - [ide]
    - [web, admin]
    - [terminal, readme, notes, process]

default_layout: desktop
```

**Validation rules (Phase 3):**

1. `default_layout` must exist in `.layouts` map.
2. Each entry inside a layout row **must exist** in `.resources`.
3. No empty row arrays (warn & skip).
4. Hard‑cap: we only support as many rows as target screen has tags (usually 9). Return error if row > 9.

### Implementation hint

Use **jq** to yield a flat JSON array of rows with resources already expanded:

```bash
layout_json=$(jq -r --arg lay "$layout" '
  .layouts[$lay][] | map(.)' "$manifest_json" )
```

Where `$layout_json` will look like:

```json
[ ["ide"], ["web","admin"], … ]
```

---

## 2. Tag‑aware spawn loop

Add helper in `bin/workon`:

```bash
spawn_on_tag() {
    local cmd="$1" tag_num="$2"
    awesome-client "awful.spawn(\"$cmd\", { tag = screen[1].tags[$tag_num] })" >&2
}
```

(*screen[1]* is current screen).  For each **row index** `i` (starting at 1):

```bash
idx=1
for row in $(jq -c '.[]' <<<"$layout_json"); do
  for res in $(jq -r '.[]' <<<"$row"); do
     cmd=$(resolve_resource "$res")   # existing phase‑1 function
     spawn_on_tag "pls-open $cmd" "$idx"
  done
  idx=$((idx+1))
done
```

### Quoting tip

Pass `cmd` through `printf %q` when composing Lua to survive spaces:

```bash
lua_cmd=$(printf %q "$cmd")
awesome-client "awful.spawn(\"$lua_cmd\",{tag=screen[1].tags[$idx]})"
```

---

## 3. Handling missing resources or tag overflow

```bash
validate_layout() {
   local ok=true row_idx=0
   while read -r row; do
       ((row_idx++))
       if (( row_idx > 9 )); then
           echo "layout uses more than 9 rows (tag $row_idx)" >&2
           ok=false
       fi
       for res in $(jq -r '.[]' <<<"$row"); do
           jq -e --arg r "$res" '.resources[$r]' <<<"$manifest_json" >/dev/null || {
              echo "layout references undefined resource: $res" >&2; ok=false; }
       done
   done <<<"$(jq -c '.[]' <<<"$layout_json")"
   $ok || exit 2
}
```

Call `validate_layout` before spawn loop.

---

## 4. Testing strategy

### 4.1 Unit tests (Bats)

- `` – feed good & bad manifests; expect status 0/2.
- `` – monkey‑patch `awesome-client` using shell stub that records arguments ( `export PATH="$(pwd)/test/stubs:$PATH"`).  Ensure tag numbers line up with row order.

### 4.2 Integration (manual / Xephyr)

1. Start Xephyr as in Phase 1.
2. Create manifest with 3‑row layout.
3. Run `workon` and press `Mod+1`, `Mod+2`, `Mod+3` inside Xephyr: windows should be grouped by row.
4. Observational test: row > 9 triggers error.

---

## 5. Toolchain refresher

| Tool               | New flag / concept                                                                    | Doc link                                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **jq**             | `-c` compact output for row iteration                                                 | [https://stedolan.github.io/jq/manual/](https://stedolan.github.io/jq/manual/)                           |
| **awesome-client** | Access tags via `screen[1].tags[idx]`                                                 | [https://awesomewm.org/doc/api/classes/tag.html](https://awesomewm.org/doc/api/classes/tag.html)         |
| **shellcheck**     | Watch for `SC2086` (double‑quote to prevent globbing) when building Lua command lines | [https://github.com/koalaman/shellcheck/wiki/SC2086](https://github.com/koalaman/shellcheck/wiki/SC2086) |

---

## 6. Common pitfalls & fixes

| Pitfall                                       | Symptom                            | Fix                                                                     |
| --------------------------------------------- | ---------------------------------- | ----------------------------------------------------------------------- |
| Tag array nil (less than 9 tags configured)   | Lua error in awesome log           | Check `#screen[1].tags` and error if layout rows > tags count.          |
| Resource names vs bash arrays                 | `cmd` contains newline → Lua fails | `printf %q` quoting mentioned above.                                    |
| Users with >1 monitor want per‑screen mapping | Windows may land on wrong screen   | Multi‑monitor will be addressed Phase 10; declare limitation in README. |

---

## 7. Documentation updates

- Update **README** “How it works” diagram to show tag‑based grouping.
- Amend **PHASE1\_IMPLEMENTATION.md** “Next steps” section to point to Phase 3.

---

## 8. Merge checklist

-

> **Unix ethos:** no internal X bindings, no custom window manipulation library—every mutation goes through Awesome’s own `awful.spawn` and tag API.  Keep the shell small; delegate everything else.

---

*On to Phase 4 — multiple layout choice & CLI flag!*

