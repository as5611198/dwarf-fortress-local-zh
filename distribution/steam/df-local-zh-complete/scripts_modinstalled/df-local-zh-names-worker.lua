--@module=true

-- Exporting every historical figure synchronously can block DF's main thread
-- for large worlds. This worker keeps the same registry format but advances a
-- bounded number of records per frame.
local json = require('json')

local state
local completed_world
local BUDGET = 64

-- DF can resize history and world vectors while a save finishes loading. Read
-- through a guarded, size-checked accessor so a boundary change only ends the
-- current phase instead of aborting the worker.
local function vector_at(vector, index)
    if not vector or index < 0 then return nil end
    local ok_size, size = pcall(function() return #vector end)
    if not ok_size or index >= size then return nil end
    local ok_value, value = pcall(function() return vector[index] end)
    if not ok_value then return nil end
    return value
end

local function text(value)
    if value == nil then return '' end
    return dfhack.df2utf(tostring(value))
end

local function add_row(s, kind, id, aliases, preferred, short_aliases)
    local key = kind .. ':' .. tostring(id)
    if s.by_id[key] or preferred == '' then return end
    local unique, clean = {}, {}
    for _, alias in ipairs(aliases) do
        if alias ~= '' and not unique[alias] then
            unique[alias] = true
            clean[#clean + 1] = alias
        end
    end
    if #clean == 0 then return end
    local row = {id=key, aliases=clean, preferred=preferred}
    if short_aliases and #short_aliases > 0 then row.shortAliases = short_aliases end
    s.entities[#s.entities + 1] = row
    s.by_id[key] = row
end

local function add_name(s, kind, id, value)
    local ok_native, native_value = pcall(dfhack.translation.translateName, value, false)
    local ok_english, english_value = pcall(dfhack.translation.translateName, value, true)
    if not ok_native or not ok_english then return end
    local native, english = text(native_value), text(english_value)
    local short_aliases
    local ok_first, first_name = pcall(function() return value.first_name end)
    if kind == 'figure' and ok_first and first_name ~= '' then
        local short = native:match('^(%S+)')
        if short and short ~= '' then short_aliases = {short} end
    end
    add_row(s, kind, id, {native, english}, english, short_aliases)
    if s.by_id[kind..':'..tostring(id)] then
        s.by_id[kind..':'..tostring(id)].nativeName=native
    end
    if kind == 'figure' and native ~= '' then
        local first = native:match('^(%S+)')
        if first and ok_first and first_name ~= '' and not s.seen[first] then
            s.seen[first] = true
            s.names[#s.names + 1] = first
            s.entities[#s.entities + 1] = {
                id='first:' .. first, kind='first', aliases={first}, preferred=first,
            }
        end
    end
end

local function add_text(s, kind, id, value)
    local value_text = text(value)
    if value_text ~= '' then add_row(s, kind, id, {value_text}, value_text) end
end

local function initialize()
    if not dfhack.isWorldLoaded() then qerror('Load a world before exporting names.') end
    if #df.global.world.history.figures == 0 then
        qerror('Wait for historical figures to finish loading before exporting names.')
    end
    local world_data = df.global.world.world_data
    state = {
        world=dfhack.getSavePath(), names={}, seen={}, entities={}, by_id={},
        phase='figures', index=0, groups={
            {kind='site', vector=world_data.sites},
            {kind='entity', vector=df.global.world.entities.all},
            {kind='artifact', vector=df.global.world.artifacts.all},
            {kind='poetic_form', vector=df.global.world.poetic_forms.all},
            {kind='musical_form', vector=df.global.world.musical_forms.all},
            {kind='dance_form', vector=df.global.world.dance_forms.all},
            {kind='written_content', vector=df.global.world.written_contents.all},
            {kind='region', vector=world_data.regions},
            {kind='layer', vector=world_data.underground_regions},
            {kind='layer', vector=world_data.landmasses},
            {kind='layer', vector=world_data.mountain_peaks},
            {kind='layer', vector=world_data.rivers},
            {kind='layer', vector=world_data.constructions and world_data.constructions.list},
        }, group_index=1, display_aliases=0,
    }
    add_name(state, 'world', 0, world_data.name)
end

local function process_group(s, group)
    local value = vector_at(group.vector, s.index)
    if not value then return false end
    if group.kind == 'written_content' then
        add_text(s, group.kind, value.id, value.title)
    elseif group.kind == 'artifact' then
        add_name(s, group.kind, value.id, value.name)
        local ok_title, title = pcall(dfhack.items.getBookTitle, value.item)
        if ok_title and title and title ~= '' then add_text(s, 'book', value.id, title) end
    else
        local ok_name, name = pcall(function() return value.name end)
        local ok_id, id = pcall(function() return value.id end)
        if not ok_id or id == nil then
            ok_id, id = pcall(function() return value.index end)
        end
        if ok_name and name and ok_id and id ~= nil then
            add_name(s, group.kind, id, name)
        end
    end
    s.index = s.index + 1
    return true
end

local function finish(s)
    local paths = reqscript('df-local-zh-paths')
    local directory = paths.broker_data()
    local captured = io.open(directory .. '/captured-legends.jsonl', 'r')
    if captured then
        for line in captured:lines() do
            local ok, item = pcall(json.decode, line)
            local row = ok and type(item) == 'table' and item.world == s.world
                and type(item.id) == 'number' and s.by_id['figure:' .. item.id] or nil
            if row and type(item.text) == 'string' then
                local prefix = row.aliases[1] .. ', "'
                if item.text:sub(1, #prefix) == prefix then
                    local display = item.text:sub(#prefix + 1):match('^(.-)",')
                    if display and display ~= '' then
                        local known = false
                        for _, alias in ipairs(row.aliases) do
                            if alias == display then known = true; break end
                        end
                        if not known then row.aliases[#row.aliases + 1] = display; s.display_aliases = s.display_aliases + 1 end
                    end
                end
            end
        end
        captured:close()
    end
    table.sort(s.names)
    local file = assert(io.open(directory .. '/active-firstnames.json', 'w'))
    file:write(json.encode(s.names)); file:close()
    local registry = assert(io.open(directory .. '/world-names.json', 'w'))
    registry:write(json.encode({world=s.world, entities=s.entities})); registry:close()
    completed_world = s.world
    print(('Exported %d distinct first names.'):format(#s.names))
    print(('Exported %d named entities and aliases.'):format(#s.entities))
    print(('Added %d Legends display aliases.'):format(s.display_aliases))
    state = nil
end

local function step()
    local s = state
    if not s then return end
    if not dfhack.isWorldLoaded() or dfhack.getSavePath() ~= s.world then state = nil; return end
    local budget = BUDGET
    while budget > 0 do
        if s.phase == 'figures' then
            local value = vector_at(df.global.world.history.figures, s.index)
            if not value then s.phase, s.index = 'groups', 0
            else add_name(s, 'figure', value.id, value.name); s.index = s.index + 1; budget = budget - 1 end
        elseif s.phase == 'groups' then
            local group = s.groups[s.group_index]
            if not group then finish(s); return end
            if not process_group(s, group) then s.group_index, s.index = s.group_index + 1, 0 end
            budget = budget - 1
        end
    end
    dfhack.timeout(1, 'frames', step)
end

function start()
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if not world then qerror('Load a world before exporting names.') end
    if completed_world == world or (state and state.world == world) then return true end
    initialize()
    dfhack.timeout(1, 'frames', step)
    return true
end

function reset()
    state = nil
    completed_world = nil
end

