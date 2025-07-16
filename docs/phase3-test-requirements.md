# Phase 3 Test Requirements: Layout Support

> **Phase 3 Goal**: Default Layout (tags 1…N) - `(tag: v0.2)` ⭐  
> **Current Status**: Phase 2 Complete, Phase 3 Next  
> **Test Coverage**: 0 tests (needs 8-10 new tests)

## Overview

Phase 3 introduces layout support, allowing resources to be spawned on specific AwesomeWM tags instead of all on the current tag. This requires parsing a `default_layout` array from YAML and mapping resources to tag indices.

## Core Functionality to Test

### 1. **YAML Layout Parsing** (3-4 tests needed)

**Function**: Parse `default_layout` from `workon.yaml`

**Test Requirements:**
```bash
# Test file: test/unit/phase3.bats

@test "parse_layout: reads default_layout array from YAML"
@test "parse_layout: validates tag indices are continuous" 
@test "parse_layout: handles missing default_layout gracefully"
@test "parse_layout: rejects invalid layout structures"
```

**Example YAML Structure:**
```yaml
resources:
  terminal: alacritty
  editor: nvim
  browser: firefox

default_layout:
  - [terminal, editor]    # Tag 1: terminal + editor
  - [browser]             # Tag 2: browser only
  - []                    # Tag 3: empty (reserved)
```

**Edge Cases to Test:**
- Missing `default_layout` (fallback to current tag behavior)
- Empty layout array
- Invalid resource names in layout
- Non-continuous tag indices
- Resources not mentioned in layout

### 2. **Tag Assignment Logic** (3-4 tests needed)

**Function**: Map resources to AwesomeWM tag indices

**Test Requirements:**
```bash
@test "assign_tags: maps resources to correct tag indices"
@test "assign_tags: handles resources not in layout (fallback to tag 1)"
@test "assign_tags: generates correct AwesomeWM spawn commands"
@test "assign_tags: validates tag indices within AwesomeWM limits"
```

**Expected Output:**
```lua
-- Instead of: awful.spawn("pls-open alacritty")
-- Generate: awful.spawn("pls-open alacritty", {tag = tags[1]})
-- And: awful.spawn("pls-open firefox", {tag = tags[2]})
```

**Edge Cases to Test:**
- Tag index out of bounds (> 9 typically)
- Multiple resources on same tag
- Empty tag assignments
- Mixed layout + non-layout resources

### 3. **Layout Integration** (2-3 tests needed)

**Function**: End-to-end layout workflow

**Test Requirements:**
```bash
@test "integration: layout spawns resources on correct tags"
@test "integration: session tracking works with tag assignments" 
@test "integration: stop functionality handles multi-tag sessions"
```

**Integration Points:**
- YAML parsing → layout extraction → tag assignment → spawn commands
- Session file includes tag information for cleanup
- Stop functionality works across multiple tags

## Implementation Strategy

### **New Functions Needed:**

1. **`parse_layout_from_yaml()`**
   - Extract `default_layout` array from parsed YAML
   - Validate structure and resource references
   - Return tag-to-resources mapping

2. **`assign_resources_to_tags()`**
   - Take resources and layout mapping
   - Generate tag assignments for each resource
   - Handle fallbacks for unmapped resources

3. **`build_spawn_command_with_tag()`**
   - Modify existing spawn command building
   - Add `{tag = tags[INDEX]}` to AwesomeWM spawn calls
   - Maintain backward compatibility

### **Modified Functions:**

1. **`launch_all_resources_with_session()`**
   - Add layout parsing step
   - Pass tag assignments to spawn commands
   - Update session metadata with tag info

2. **Lua spawn script updates**
   - Handle tag assignment in `awful.spawn()` calls
   - Include tag metadata in session entries
   - Validate tag indices before spawning

## Test File Structure

```bash
# New test file
test/unit/phase3.bats

# Test sections:
# 1. Layout parsing functions (4 tests)
# 2. Tag assignment logic (4 tests) 
# 3. Integration with existing workflow (2 tests)

# Total: ~10 new tests
```

## Mock Requirements

### **YAML Test Fixtures:**
```yaml
# Valid layout
resources:
  terminal: alacritty
  editor: nvim
  browser: firefox
default_layout:
  - [terminal, editor]
  - [browser]

# Invalid layouts for error testing
default_layout:
  - [nonexistent_resource]  # Reference error
  - [terminal, terminal]    # Duplicate resource
```

### **AwesomeWM Mock Updates:**
```bash
# Enhanced awesome-client mock needs to:
# 1. Parse tag assignments from Lua spawn calls
# 2. Validate tag indices (1-9 typically)
# 3. Include tag info in mock session entries
```

## Success Criteria

### **Functional Requirements:**
- ✅ Parse `default_layout` from YAML without breaking existing functionality
- ✅ Generate correct `awful.spawn("cmd", {tag = tags[N]})` commands  
- ✅ Maintain session tracking with tag metadata
- ✅ Preserve backward compatibility (no layout = current tag)

### **Test Coverage Goals:**
- ✅ **100% function coverage** for new layout functions
- ✅ **Error handling coverage** for invalid layouts
- ✅ **Integration coverage** for end-to-end layout workflow
- ✅ **Backward compatibility** - existing YAML still works

### **Quality Metrics:**
- All existing 59 tests continue to pass
- New layout tests are fast (< 1s each)
- Mock-based testing (no real AwesomeWM required)
- Clear test failure messages for debugging

## Phase 3 Implementation Order

1. **Start with unit tests** - Write failing tests first (TDD approach)
2. **Implement layout parsing** - Basic YAML → data structure conversion
3. **Add tag assignment logic** - Map resources to tag indices
4. **Update spawn commands** - Integrate with existing Lua spawn script
5. **Integration testing** - End-to-end workflow validation
6. **Error handling** - Graceful fallbacks and validation

---

**Next Steps:** Create `test/unit/phase3.bats` with skeleton test structure and begin TDD implementation of layout support.