-- WorkOn Lua Spawn Script
-- Spawns all resources in a single AwesomeWM context and writes session file
-- This script is designed to work within AwesomeWM's Lua environment

-- WorkOn Lua Spawn Script Starting

-- Get WORKON_DIR from global variable (set by the workon script)
local workon_dir = WORKON_DIR or os.getenv("WORKON_DIR")
if not workon_dir then
    error("WORKON_DIR not available - this script must be called from the workon command")
end

-- Add module path
package.path = package.path .. ";" .. workon_dir .. "/lib/lua-workon/src/?.lua"

-- Load our modules
local json = require("json")
local session = require("session")
local awful = require("awful")

-- Check if we have a configuration (it could be set as a global variable)
local config = nil
local config_json = WORKON_SPAWN_CONFIG or os.getenv("WORKON_SPAWN_CONFIG")

if config_json then
    local success, parsed_config = pcall(json.decode, config_json)
    if success then
        config = parsed_config
    else
        error("Error parsing WORKON_SPAWN_CONFIG: " .. (parsed_config or "unknown error"))
    end
end

-- If still no config, error out
if not config then
    error("No configuration provided. Set WORKON_SPAWN_CONFIG environment variable or WORKON_SPAWN_CONFIG global variable.")
end

-- Validate configuration
if not config.session_file or not config.resources then
    io.stderr:write("Error: Invalid configuration - missing session_file or resources\n")
    return
end

-- Function to spawn a single resource on a specific tag
local function spawn_resource(resource, session_file, tag_index)
    local spawn_properties = {}
    
    -- If tag_index is specified, spawn on that tag
    if tag_index and tag_index > 0 then
        local screen = awful.screen.focused()
        if screen and screen.tags and screen.tags[tag_index] then
            spawn_properties.tag = screen.tags[tag_index]
            io.stderr:write("Spawning " .. resource.name .. " on tag " .. tag_index .. "\n")
        else
            io.stderr:write("Warning: Tag " .. tag_index .. " not available, spawning on current tag\n")
        end
    end
    
    -- Add callback for session tracking
    spawn_properties.callback = function(c)
        -- Create session entry with client data
        local entry = session.create_entry(resource.name, resource.cmd, c.pid, c)
        
        -- Append to session file
        local append_success, append_err = pcall(session.append_to_session, session_file, entry)
        if not append_success then
            io.stderr:write("Error updating session file: " .. (append_err or "unknown error") .. "\n")
        else
            io.stderr:write("Session updated: " .. resource.name .. " (PID: " .. (c.pid or "unknown") .. ")\n")
        end
    end
    
    local success, pid_or_err = pcall(function()
        return awful.spawn(resource.cmd, spawn_properties)
    end)
    
    if success then
        io.stderr:write("Spawned: " .. resource.name .. "\n")
        return true
    else
        io.stderr:write("Failed to spawn " .. resource.name .. ": " .. (pid_or_err or "unknown error") .. "\n")
        return false
    end
end

-- Spawn all resources based on layout or sequentially
local success_count = 0
local total_count = #config.resources

-- Check if layout is provided
if config.layout and type(config.layout) == "table" and #config.layout > 0 then
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
                        if spawn_resource(resource, config.session_file, tag_index) then
                            success_count = success_count + 1
                        end
                    end
                else
                    io.stderr:write("Warning: Layout references unknown resource: " .. resource_name .. "\n")
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
            if spawn_resource(resource, config.session_file) then
                success_count = success_count + 1
            end
        end
    end
end

io.stderr:write("Spawn complete: " .. success_count .. "/" .. total_count .. " resources started\n")
