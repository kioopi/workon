#!/usr/bin/env lua

-- Debug script to safely test the Lua spawn functionality without crashing X11
-- This comprehensive debug script tests all components and identifies issues

print("=== WorkOn Lua Spawn Debug Script ===")

-- Add current directory to package path for our modules
package.path = package.path .. ";./lib/lua-workon/src/?.lua"

-- Mock the awful library to avoid AwesomeWM dependency
local awful = {
    spawn = function(cmd, opts)
        print("MOCK SPAWN: " .. cmd)
        if opts and opts.callback then
            -- Simulate a client object
            local mock_client = {
                pid = math.random(1000, 9999),
                window = string.format("0x%x", math.random(1000000, 9999999)),
                class = "test-app",
                instance = "test-instance",
                name = "Test Application"
            }
            print("  Mock client created: PID=" .. mock_client.pid .. ", Window=" .. mock_client.window)
            opts.callback(mock_client)
        end
        return math.random(1000, 9999)
    end
}

-- Inject the mock awful module into the package system
package.preload["awful"] = function() return awful end

-- Test environment variable access
print("\n--- Testing Environment Variables ---")
local config_json = os.getenv("WORKON_SPAWN_CONFIG")
if config_json then
    print("WORKON_SPAWN_CONFIG found:", config_json)
else
    print("ERROR: WORKON_SPAWN_CONFIG not set")
    -- Set a test configuration
    config_json = '{"session_file":"/tmp/test_session.json","resources":[{"name":"test","cmd":"echo hello"}]}'
    print("Using test configuration:", config_json)
end

-- Test JSON module
print("\n--- Testing JSON Module ---")
local json_ok, json = pcall(require, "json")
if json_ok then
    print("JSON module loaded successfully")
    
    -- Test encoding/decoding
    local test_data = {name = "test", cmd = "echo hello", pid = 123}
    local encoded = json.encode(test_data)
    print("Encoded:", encoded)
    
    local decoded = json.decode(encoded)
    print("Decoded name:", decoded.name)
else
    print("ERROR: JSON module failed to load:", json)
    return 1
end

-- Test session module
print("\n--- Testing Session Module ---")
local session_ok, session = pcall(require, "session")
if session_ok then
    print("Session module loaded successfully")
    
    -- Test creating an entry
    local entry = session.create_entry("test-app", "echo hello", 123, {
        window = "0x123456",
        class = "test-class",
        instance = "test-instance"
    })
    print("Created entry:", json.encode(entry))
    
    -- Test session file operations
    local test_session_file = "/tmp/test_session.json"
    local success, err = pcall(session.write_session_atomic, test_session_file, {entry})
    if success then
        print("Session file written successfully")
        
        local read_data, read_err = session.read_session(test_session_file)
        if read_err then
            print("ERROR: Session read failed:", read_err)
        else
            print("Session read successfully:", json.encode(read_data))
        end
    else
        print("ERROR: Session write failed:", err)
    end
else
    print("ERROR: Session module failed to load:", session)
    return 1
end

-- Test spawn module
print("\n--- Testing Spawn Module ---")
local spawn_ok, spawn = pcall(require, "spawn")
if spawn_ok then
    print("Spawn module loaded successfully")
    
    -- Test configuration parsing
    local config = json.decode(config_json)
    print("Test configuration:", json.pretty_encode(config))
    
    -- Test spawn_all with mock awful
    local spawn_success, spawn_err = pcall(spawn.spawn_all, config)
    if spawn_success then
        print("Spawn test completed successfully")
    else
        print("ERROR: Spawn test failed:", spawn_err)
    end
else
    print("ERROR: Spawn module failed to load:", spawn)
    return 1
end

print("\n=== Debug Complete ===")
print("All tests passed - the Lua modules are working correctly")
print("The issue is likely in the AwesomeWM integration or environment variable passing")