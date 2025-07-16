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

-- Function to spawn a single resource
local function spawn_resource(resource, session_file)
    local success, pid_or_err = pcall(function()
        return awful.spawn(resource.cmd, {
            callback = function(c)
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
        })
    end)
    
    if success then
        io.stderr:write("Spawned: " .. resource.name .. "\n")
        return true
    else
        io.stderr:write("Failed to spawn " .. resource.name .. ": " .. (pid_or_err or "unknown error") .. "\n")
        return false
    end
end

-- Spawn all resources
local success_count = 0
local total_count = #config.resources

for i, resource in ipairs(config.resources) do
    if not resource.name or not resource.cmd then
        io.stderr:write("Warning: Resource " .. i .. " missing name or cmd\n")
    else
        if spawn_resource(resource, config.session_file) then
            success_count = success_count + 1
        end
    end
end

io.stderr:write("Spawn complete: " .. success_count .. "/" .. total_count .. " resources started\n")
