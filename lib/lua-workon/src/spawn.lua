-- workon.spawn - Resource spawning utilities for WorkOn
-- Provides AwesomeWM integration for spawning resources and managing sessions

local json = require("json")
local session = require("session")
local awful = require("awful")

local M = {}

-- Spawn a single resource with session tracking
function M.spawn_resource(resource, session_file)
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

-- Spawn all resources from configuration
function M.spawn_all(config)
    if not config or not config.session_file or not config.resources then
        error("Invalid configuration: missing session_file or resources")
    end
    
    local success_count = 0
    local total_count = #config.resources
    
    -- Spawn each resource
    for i, resource in ipairs(config.resources) do
        if not resource.name or not resource.cmd then
            io.stderr:write("Warning: Resource " .. i .. " missing name or cmd\n")
        else
            if M.spawn_resource(resource, config.session_file) then
                success_count = success_count + 1
            end
        end
    end
    
    io.stderr:write("Spawn complete: " .. success_count .. "/" .. total_count .. " resources started\n")
    return success_count
end

-- Main entry point for spawn script
function M.main()
    -- Read configuration from environment
    local config_json = os.getenv("WORKON_SPAWN_CONFIG")
    if not config_json then
        io.stderr:write("Error: WORKON_SPAWN_CONFIG environment variable not set\n")
        return 1
    end
    
    local config, decode_err = pcall(json.decode, config_json)
    if not config then
        io.stderr:write("Error: Invalid JSON in WORKON_SPAWN_CONFIG: " .. (decode_err or "unknown error") .. "\n")
        return 1
    end
    
    local spawn_success, spawn_err = pcall(M.spawn_all, config)
    if not spawn_success then
        io.stderr:write("Error: Spawn failed: " .. (spawn_err or "unknown error") .. "\n")
        return 1
    end
    
    return 0
end

return M