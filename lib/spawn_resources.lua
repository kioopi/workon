-- WorkOn Lua Spawn Script
-- Spawns all resources in a single AwesomeWM context and writes session file
-- This script is designed to work within AwesomeWM's Lua environment

-- WorkOn Lua Spawn Script Starting

-- Get WORKON_DIR from global variable (set by the workon script)
local workon_dir = WORKON_DIR or os.getenv("WORKON_DIR")
if not workon_dir then
    error("WORKON_DIR not available - this script must be called from the workon command")
end

-- Get WORKON_PROJECT_DIR from global variable (set by the workon script)
local project_dir = WORKON_PROJECT_DIR or os.getenv("WORKON_PROJECT_DIR") or workon_dir

-- Add module path
package.path = package.path .. ";" .. workon_dir .. "/lib/lua-workon/src/?.lua"

-- Load our modules
local json = require("json")
local session = require("session")
local awful = require("awful")

-- Set up debug logging to file
local debug_file = "/tmp/workon-lua-debug.log"
local function debug_log(message)
    local file = io.open(debug_file, "a")
    if file then
        file:write(os.date("%H:%M:%S") .. " " .. tostring(message) .. "\n")
        file:close()
    end
end

-- Clear previous debug log
local file = io.open(debug_file, "w")
if file then file:close() end

debug_log("=== WorkOn Lua Script Starting ===")
debug_log("WORKON_DIR = " .. (workon_dir or "nil"))
debug_log("WORKON_PROJECT_DIR = " .. (project_dir or "nil"))

-- Check if we have a configuration (it could be set as a global variable)
local config = nil
local config_json = WORKON_SPAWN_CONFIG or os.getenv("WORKON_SPAWN_CONFIG")

debug_log("Config JSON length: " .. (config_json and string.len(config_json) or "nil"))

if config_json then
    debug_log("Attempting to decode JSON config")
    local success, parsed_config = pcall(json.decode, config_json)
    if success then
        config = parsed_config
        debug_log("JSON config decoded successfully")
    else
        debug_log("JSON decode failed: " .. (parsed_config or "unknown error"))
        error("Error parsing WORKON_SPAWN_CONFIG: " .. (parsed_config or "unknown error"))
    end
end

-- If still no config, error out
if not config then
    debug_log("No configuration provided")
    error("No configuration provided. Set WORKON_SPAWN_CONFIG environment variable or WORKON_SPAWN_CONFIG global variable.")
end

debug_log("Configuration validated, proceeding with spawn")

-- Validate configuration
if not config.session_file or not config.resources then
    io.stderr:write("Error: Invalid configuration - missing session_file or resources\n")
    return
end

-- Function to spawn a single resource on a specific tag
local function spawn_resource(resource, session_file, tag_index, working_directory)
    local spawn_properties = {}
    
    -- Set working directory for spawned applications
    if working_directory then
        spawn_properties.cwd = working_directory
        debug_log(string.format("Setting working directory to %s for %s", working_directory, resource.name))
    end
    
    -- If tag_index is specified, spawn on that tag
    if tag_index and tag_index > 0 then
        local screen = awful.screen.focused()
        debug_log(string.format("Tag resolution for %s: tag_index=%d, screen=%s", resource.name, tag_index, screen and "found" or "nil"))
        
        -- Get screen tags (might be a function in some AwesomeWM versions)
        local screen_tags = screen.tags
        if type(screen_tags) == "function" then
            screen_tags = screen_tags()
        end
        
        if screen and screen_tags then
            debug_log(string.format("Screen has %d tags available", #screen_tags))
            
            -- Log all available tags for debugging
            for i, tag in ipairs(screen_tags) do
                debug_log(string.format("Available tag %d: name='%s', selected=%s", i, tag.name or "unnamed", tag.selected and "yes" or "no"))
            end
            
            -- Log currently selected tag
            local selected_tag = screen.selected_tag
            if selected_tag then
                debug_log(string.format("Currently selected tag: name='%s'", selected_tag.name or "unnamed"))
            else
                debug_log("No currently selected tag")
            end
            
            if screen_tags[tag_index] then
                spawn_properties.tag = screen_tags[tag_index]
                debug_log(string.format("Tag %d found: %s (selected: %s)", tag_index, screen_tags[tag_index].name or "unnamed", screen_tags[tag_index].selected and "yes" or "no"))
                debug_log(string.format("Setting spawn_properties.tag for %s to tag %d (%s)", resource.name, tag_index, screen_tags[tag_index].name or "unnamed"))
                
                -- Don't switch tags during spawn - let applications appear on correct tags without view changes
                debug_log(string.format("Tag assignment set, will spawn on tag %d without switching view", tag_index))
            else
                debug_log(string.format("Warning - Tag %d not available (only %d tags), spawning on current tag", tag_index, #screen_tags))
            end
        else
            debug_log(string.format("Warning - No screen.tags available, spawning on current tag"))
        end
    else
        debug_log(string.format("Spawning %s on current tag (no tag specified)", resource.name))
    end
    
    -- Add callback for session tracking and tag enforcement
    spawn_properties.callback = function(c)
        debug_log(string.format("Callback triggered for %s (PID: %s, class: %s, instance: %s)", resource.name, c.pid or "unknown", c.class or "unknown", c.instance or "unknown"))
        debug_log(string.format("Client window info: name='%s', window_id=%s", c.name or "unknown", c.window or "unknown"))
        
        -- If we have a target tag, ensure client appears on it
        if tag_index and tag_index > 0 then
            local screen = awful.screen.focused()
            local screen_tags = screen.tags
            if type(screen_tags) == "function" then
                screen_tags = screen_tags()
            end
            
            if screen and screen_tags and screen_tags[tag_index] then
                debug_log(string.format("Enforcing tag assignment: moving %s to tag %d", resource.name, tag_index))
                c:move_to_tag(screen_tags[tag_index])
                debug_log(string.format("Client %s moved to tag %d", resource.name, tag_index))
            end
        end
        
        -- Check which tag the client actually appeared on
        local client_tags = c.tags
        if type(client_tags) == "function" then
            client_tags = client_tags(c)
        end
        
        if client_tags and #client_tags > 0 then
            local tag_names = {}
            for _, tag in ipairs(client_tags) do
                table.insert(tag_names, tag.name or "unnamed")
            end
            debug_log(string.format("Client %s final tags: %s", resource.name, table.concat(tag_names, ", ")))
        else
            debug_log(string.format("Client %s has no tags assigned", resource.name))
        end
        
        -- Check if this resource already exists in session before adding callback data
        local session_data, err = session.read_session(session_file)
        local already_tracked = false
        if session_data and not err then
            for _, existing_entry in ipairs(session_data) do
                if existing_entry.name == resource.name and existing_entry.pid == c.pid then
                    already_tracked = true
                    debug_log(string.format("Resource %s (PID: %s) already tracked, updating in place", resource.name, c.pid or "unknown"))
                    -- Update the existing entry with window data
                    existing_entry.window_id = c.window and tostring(c.window) or ""
                    existing_entry.class = c.class or ""
                    existing_entry.instance = c.instance or ""
                    existing_entry.name_prop = c.name or ""
                    session.write_session_atomic(session_file, session_data)
                    debug_log(string.format("SUCCESS: Updated existing session entry for %s", resource.name))
                    break
                end
            end
        end
        
        -- Only create new entry if not already tracked
        if not already_tracked then
            local entry = session.create_entry(resource.name, resource.cmd, c.pid, c)
            local append_success, append_err = pcall(session.append_to_session, session_file, entry)
            if not append_success then
                debug_log(string.format("ERROR: Failed to update session file for %s: %s", resource.name, append_err or "unknown error"))
            else
                debug_log(string.format("SUCCESS: Session updated for %s (PID: %s)", resource.name, c.pid or "unknown"))
            end
        end
    end
    
    debug_log(string.format("About to spawn '%s' with properties: tag=%s, cwd=%s", 
        resource.cmd, 
        spawn_properties.tag and spawn_properties.tag.name or "current",
        spawn_properties.cwd or "nil"
    ))
    
    local success, pid_or_err = pcall(function()
        return awful.spawn(resource.cmd, spawn_properties)
    end)
    
    if success then
        debug_log(string.format("SUCCESS: Spawned %s (returned: %s)", resource.name, pid_or_err or "unknown"))
        
        -- Create immediate session entry with the returned PID
        -- This provides fallback tracking for apps that don't trigger callbacks
        if pid_or_err and type(pid_or_err) == "number" then
            local immediate_entry = {
                name = resource.name,
                cmd = resource.cmd,
                pid = pid_or_err,
                timestamp = os.time(),
                tracking_method = "immediate_pid"
            }
            
            local append_success, append_err = pcall(session.append_to_session, session_file, immediate_entry)
            if append_success then
                debug_log(string.format("SUCCESS: Immediate session tracking for %s (PID: %s)", resource.name, pid_or_err))
            else
                debug_log(string.format("ERROR: Failed immediate session tracking for %s: %s", resource.name, append_err or "unknown"))
            end
        end
        
        return true
    else
        debug_log(string.format("ERROR: Failed to spawn %s: %s", resource.name, pid_or_err or "unknown error"))
        return false
    end
end

-- Spawn all resources based on layout or sequentially
local success_count = 0
local total_count = #config.resources

-- Check if layout is provided
if config.layout and type(config.layout) == "table" and #config.layout > 0 then
    debug_log("Using layout-based spawning with " .. #config.layout .. " tags")
    io.stderr:write("Using layout-based spawning with " .. #config.layout .. " tags\n")
    
    -- Spawn resources by layout (tag-based)
    for tag_index, resource_group in ipairs(config.layout) do
        if type(resource_group) == "table" then
            for _, resource_name in ipairs(resource_group) do
                -- Find the resource by name
                local resource = nil
                for _, res in ipairs(config.resources) do
                    if res.name == resource_name then
                        resource = res
                        break
                    end
                end
                
                if resource then
                    if not resource.name or not resource.cmd then
                        io.stderr:write("Warning: Resource " .. resource_name .. " missing name or cmd\n")
                    else
                        if spawn_resource(resource, config.session_file, tag_index, project_dir) then
                            success_count = success_count + 1
                        end
                    end
                else
                    io.stderr:write(string.format("Warning: Layout references unknown resource: %s\n", resource_name))
                end
            end
        end
    end
    
    total_count = 0
    for _, group in ipairs(config.layout) do
        if type(group) == "table" then
            total_count = total_count + #group
        end
    end
else
    io.stderr:write("Using sequential spawning (no layout)\n")
    
    -- Spawn resources sequentially (backward compatibility)
    for i, resource in ipairs(config.resources) do
        if not resource.name or not resource.cmd then
            io.stderr:write("Warning: Resource " .. i .. " missing name or cmd\n")
        else
            if spawn_resource(resource, config.session_file, nil, project_dir) then
                success_count = success_count + 1
            end
        end
    end
end

io.stderr:write("Spawn complete: " .. success_count .. "/" .. total_count .. " resources started\n")
debug_log("=== Lua script completed successfully! ===")
