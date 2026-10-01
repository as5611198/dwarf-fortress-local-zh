--@module = true

-- Resolve public mod assets separately from per-player runtime state. The
-- development checkout predates the Workshop package, so keep its fallback.
local scriptmanager = require('script-manager')

MOD_ID = 'df-local-zh-complete'
local cached_source,cached_state,cached_data

local function absolute(relative)
    if not relative or relative == '' then return nil end
    if relative:match('^[A-Za-z]:[\\/]') or relative:match('^[/\\][/\\]') then
        local normalized = relative:gsub('\\', '/'):gsub('/+$', '')
        return normalized
    end
    return dfhack.getDFPath() .. '/' .. relative:gsub('\\', '/'):gsub('/+$', '')
end

local function exists(path)
    local file = path and io.open(path, 'rb')
    if file then file:close(); return true end
    return false
end

function source()
    if cached_source then return cached_source end
    local ok, mod_path = pcall(scriptmanager.getModSourcePath, MOD_ID)
    local path = ok and absolute(mod_path) or nil
    cached_source=path and exists(path .. '/broker/config.json') and path or dfhack.getDFPath() .. '/_localization-work'
    return cached_source
end

function state()
    if cached_state then return cached_state end
    local root = source()
    if root ~= dfhack.getDFPath() .. '/_localization-work' then
        local ok, path = pcall(scriptmanager.getModStatePath, MOD_ID)
        if not ok or not path then
            path = dfhack.getConfigPath() .. '/mods/' .. MOD_ID
            if not dfhack.filesystem.mkdir_recursive(path) then
                error('failed to create mod state directory: ' .. path)
            end
        end
        cached_state=absolute(path)
        return cached_state
    end
    cached_state=root .. '/broker'
    return cached_state
end

function broker_source()
    return source() .. '/broker'
end

function broker_data()
    if cached_data then return cached_data end
    local path = state() .. '/data'
    if not dfhack.filesystem.mkdir_recursive(path) then
        error('failed to create broker data directory: ' .. path)
    end
    cached_data=path
    return cached_data
end
