-- workon.session - Session management utilities for WorkOn
-- Provides atomic file operations and session data management

local json = require("json")

local M = {}

-- Create a session entry for a spawned resource
function M.create_entry(resource_name, command, pid, client_data)
    local entry = {
        name = resource_name,
        cmd = command,
        pid = pid or 0,
        timestamp = os.time()
    }
    
    -- Add client data if available
    if client_data then
        entry.window_id = client_data.window and tostring(client_data.window) or ""
        entry.class = client_data.class or ""
        entry.instance = client_data.instance or ""
        entry.name_prop = client_data.name or ""
    else
        entry.window_id = ""
        entry.class = ""
        entry.instance = ""
        entry.name_prop = ""
    end
    
    return entry
end

-- Write session data to file atomically
function M.write_session_atomic(filepath, session_data)
    local tmp_file = filepath .. ".tmp"
    
    -- Encode session data to JSON
    local json_content = json.encode(session_data)
    
    -- Write to temporary file
    local file, err = io.open(tmp_file, "w")
    if not file then
        error("Cannot create temporary file " .. tmp_file .. ": " .. (err or "unknown error"))
    end
    
    file:write(json_content)
    file:close()
    
    -- Atomic move
    local success, move_err = os.rename(tmp_file, filepath)
    if not success then
        os.remove(tmp_file)
        error("Cannot move temporary file to " .. filepath .. ": " .. (move_err or "unknown error"))
    end
    
    return true
end

-- Read session data from file
function M.read_session(filepath)
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Cannot open session file: " .. (err or "unknown error")
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        return {}, nil
    end
    
    local success, session_data = pcall(json.decode, content)
    if not success then
        return nil, "Invalid JSON in session file: " .. (session_data or "unknown error")
    end
    
    return session_data, nil
end

-- Append entry to existing session (used for incremental updates)
function M.append_to_session(filepath, entry)
    local session_data, err = M.read_session(filepath)
    if err or not session_data then
        -- If file doesn't exist or read failed, create new session
        session_data = {}
    end
    
    -- Check for duplicates based on name and pid to prevent multiple entries for same resource
    for i, existing_entry in ipairs(session_data) do
        if existing_entry.name == entry.name and existing_entry.pid == entry.pid then
            -- Update existing entry with new data (callback adds window info to immediate_pid entry)
            -- But preserve the original tracking method
            local original_tracking_method = existing_entry.tracking_method
            for key, value in pairs(entry) do
                existing_entry[key] = value
            end
            -- Restore original tracking method (immediate_pid is more important than missing)
            if original_tracking_method then
                existing_entry.tracking_method = original_tracking_method
            end
            M.write_session_atomic(filepath, session_data)
            return true
        end
    end
    
    table.insert(session_data, entry)
    M.write_session_atomic(filepath, session_data)
    
    return true
end

return M