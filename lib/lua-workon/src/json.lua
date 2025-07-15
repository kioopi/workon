-- workon.json - JSON utilities for WorkOn
-- Provides a clean interface to JSON operations with fallback implementation

local M = {}

-- Try to load dkjson, fall back to simple JSON implementation
local dkjson = nil
local has_dkjson = pcall(function()
    dkjson = require("dkjson")
end)

-- Simple JSON encoder fallback (basic implementation)
local function simple_encode(obj)
    local t = type(obj)
    if t == "string" then
        return '"' .. obj:gsub('"', '\\"') .. '"'
    elseif t == "number" then
        return tostring(obj)
    elseif t == "boolean" then
        return tostring(obj)
    elseif t == "nil" then
        return "null"
    elseif t == "table" then
        local result = {}
        local is_array = true
        local max_index = 0
        
        -- Check if it's an array
        for k, v in pairs(obj) do
            if type(k) ~= "number" then
                is_array = false
                break
            end
            max_index = math.max(max_index, k)
        end
        
        if is_array then
            result[1] = "["
            for i = 1, max_index do
                if i > 1 then result[#result + 1] = "," end
                result[#result + 1] = simple_encode(obj[i])
            end
            result[#result + 1] = "]"
        else
            result[1] = "{"
            local first = true
            for k, v in pairs(obj) do
                if not first then result[#result + 1] = "," end
                first = false
                result[#result + 1] = simple_encode(tostring(k))
                result[#result + 1] = ":"
                result[#result + 1] = simple_encode(v)
            end
            result[#result + 1] = "}"
        end
        
        return table.concat(result)
    else
        error("Cannot encode type: " .. t)
    end
end

-- Simple JSON decoder fallback (basic but functional implementation)
local function simple_decode(json_str)
    local pos = 1
    local len = #json_str
    
    local function skip_whitespace()
        while pos <= len and json_str:sub(pos, pos):match("%s") do
            pos = pos + 1
        end
    end
    
    local function parse_value()
        skip_whitespace()
        if pos > len then return nil end
        
        local char = json_str:sub(pos, pos)
        
        if char == '"' then
            -- Parse string
            pos = pos + 1
            local start = pos
            while pos <= len and json_str:sub(pos, pos) ~= '"' do
                if json_str:sub(pos, pos) == "\\" then
                    pos = pos + 1 -- Skip escaped character
                end
                pos = pos + 1
            end
            if pos > len then error("Unterminated string") end
            local str = json_str:sub(start, pos - 1)
            pos = pos + 1
            return str:gsub('\\"', '"')
        elseif char == '{' then
            -- Parse object
            pos = pos + 1
            local obj = {}
            skip_whitespace()
            
            if pos <= len and json_str:sub(pos, pos) == '}' then
                pos = pos + 1
                return obj
            end
            
            while pos <= len do
                local key = parse_value()
                skip_whitespace()
                if pos > len or json_str:sub(pos, pos) ~= ':' then
                    error("Expected ':' after object key")
                end
                pos = pos + 1
                local value = parse_value()
                obj[key] = value
                
                skip_whitespace()
                if pos > len then break end
                
                if json_str:sub(pos, pos) == '}' then
                    pos = pos + 1
                    return obj
                elseif json_str:sub(pos, pos) == ',' then
                    pos = pos + 1
                    skip_whitespace()
                else
                    error("Expected ',' or '}' in object")
                end
            end
            
            return obj
        elseif char == '[' then
            -- Parse array
            pos = pos + 1
            local arr = {}
            skip_whitespace()
            
            if pos <= len and json_str:sub(pos, pos) == ']' then
                pos = pos + 1
                return arr
            end
            
            while pos <= len do
                arr[#arr + 1] = parse_value()
                skip_whitespace()
                if pos > len then break end
                
                if json_str:sub(pos, pos) == ']' then
                    pos = pos + 1
                    return arr
                elseif json_str:sub(pos, pos) == ',' then
                    pos = pos + 1
                    skip_whitespace()
                else
                    error("Expected ',' or ']' in array")
                end
            end
            
            return arr
        elseif char:match("%d") or char == "-" then
            -- Parse number
            local start = pos
            if char == "-" then pos = pos + 1 end
            while pos <= len and json_str:sub(pos, pos):match("%d") do
                pos = pos + 1
            end
            if pos <= len and json_str:sub(pos, pos) == "." then
                pos = pos + 1
                while pos <= len and json_str:sub(pos, pos):match("%d") do
                    pos = pos + 1
                end
            end
            return tonumber(json_str:sub(start, pos - 1))
        elseif json_str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif json_str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif json_str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        else
            error("Unexpected character: " .. char)
        end
    end
    
    return parse_value()
end

-- Encode a Lua table to JSON string
function M.encode(obj)
    if has_dkjson then
        local json_str, err = dkjson.encode(obj)
        if not json_str then
            error("JSON encode error: " .. (err or "unknown error"))
        end
        return json_str
    else
        return simple_encode(obj)
    end
end

-- Decode a JSON string to Lua table
function M.decode(json_str)
    if has_dkjson then
        local obj, pos, err = dkjson.decode(json_str, 1, nil)
        if not obj then
            error("JSON decode error: " .. (err or "unknown error"))
        end
        return obj
    else
        return simple_decode(json_str)
    end
end

-- Pretty-print JSON with indentation
function M.pretty_encode(obj)
    if has_dkjson then
        local json_str, err = dkjson.encode(obj, { indent = true })
        if not json_str then
            error("JSON pretty encode error: " .. (err or "unknown error"))
        end
        return json_str
    else
        -- Simple pretty printing with basic indentation
        local json_str = simple_encode(obj)
        return json_str -- Basic implementation, no pretty formatting
    end
end

return M