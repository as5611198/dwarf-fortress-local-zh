-- Live arena translation verification. Run with: df-local-zh-arena-test
-- This command never changes the viewscreen stack and never waits on a timer.
local json = require('json')
local native = reqscript('df-local-zh-core/native')
local mod = reqscript('df-local-zh-core/mod')
local paths = reqscript('df-local-zh-paths')

local results = {
    version = 1,
    mode = 'arena-live-10',
    started = os.time(),
    gametype = df.global.gametype,
    units = {},
    health = {},
    combat = {},
    colors = {},
    cleanup = {},
}

local function check(name, ok, detail)
    local row = {name = name, status = ok and 'PASS' or 'FAIL', detail = tostring(detail or '')}
    results.checks = results.checks or {}
    results.checks[#results.checks + 1] = row
    print(('DF_LOCAL_ZH_ARENA %s %s: %s'):format(row.status, name, row.detail))
    return row
end

local function ascii_letters(text)
    return type(text) == 'string' and text:match('[A-Za-z]') ~= nil
end

local function translated(source)
    local ok, value = pcall(mod.sync_translate, source)
    if not ok then return nil, tostring(value) end
    return value
end

local function translation_row(source)
    local value, err = translated(source)
    local ok = type(value) == 'string' and value ~= '' and not ascii_letters(value) and
        value:match('[^%z\1-\127]') ~= nil
    return {source = source, translation = value, status = ok and 'PASS' or 'MISS', error = err}
end

local function erase_id(vector, id)
    if not vector then return false end
    for i, value in ipairs(vector) do
        if value and value.id == id then
            vector:erase(i)
            return true
        end
    end
    return false
end

local function find_walkable_tile()
    local map = df.global.world.map
    local cx, cy, cz = math.floor(map.x_count / 2), math.floor(map.y_count / 2), math.floor(map.z_count / 2)
    for radius = 0, 24 do
        for dz = -2, 2 do
            local z = cz + dz
            if z >= 0 and z < map.z_count then
                for dy = -radius, radius do
                    for dx = -radius, radius do
                        if math.abs(dx) == radius or math.abs(dy) == radius or radius == 0 then
                            local x, y = cx + dx, cy + dy
                            if x >= 0 and x < map.x_count and y >= 0 and y < map.y_count then
                                local tt = dfhack.maps.getTileType(x, y, z)
                                local attrs = tt and df.tiletype.attrs[tt]
                                local shape = attrs and df.tiletype_shape.attrs[attrs.shape]
                                if shape and shape.walkable then
                                    local pos = df.coord:new()
                                    pos.x, pos.y, pos.z = x, y, z
                                    return pos
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function raw_index(id)
    for i, raw in ipairs(df.global.world.raws.creatures.all) do
        if raw.creature_id == id then return i end
    end
end

local preferred_races = {
    'DWARF', 'GOBLIN', 'ELF', 'HUMAN', 'AARDVARK',
    'ALLIGATOR', 'ALPACA', 'BEAR', 'TROLL', 'GIANT_EAGLE',
}

local function choose_races()
    local picked, seen = {}, {}
    for _, id in ipairs(preferred_races) do
        local index = raw_index(id)
        if index and not seen[index] then
            picked[#picked + 1] = {id = id, index = index}
            seen[index] = true
        end
    end
    if #picked < 10 then
        for i, raw in ipairs(df.global.world.raws.creatures.all) do
            local id = raw.creature_id
            if id and not seen[i] and not id:match('_MAN$') and not id:match('^EVIL_') then
                picked[#picked + 1] = {id = id, index = i}
                seen[i] = true
                if #picked >= 10 then break end
            end
        end
    end
    return picked
end

local function material(token)
    return assert(dfhack.matinfo.find(token), 'missing material '..token)
end

local function subtype(token)
    local value = dfhack.items.findSubtype(token)
    assert(value and value >= 0, 'missing item subtype '..token)
    return value
end

local equipment = {
    {label = 'iron pick', type = df.item_type.WEAPON, subtype = 'WEAPON:ITEM_WEAPON_PICK', mat = 'INORGANIC:IRON'},
    {label = 'silver war hammer', type = df.item_type.WEAPON, subtype = 'WEAPON:ITEM_WEAPON_HAMMER_WAR', mat = 'INORGANIC:SILVER'},
    {label = 'steel short sword', type = df.item_type.WEAPON, subtype = 'WEAPON:ITEM_WEAPON_SWORD_SHORT', mat = 'INORGANIC:STEEL'},
    {label = 'bronze spear', type = df.item_type.WEAPON, subtype = 'WEAPON:ITEM_WEAPON_SPEAR', mat = 'INORGANIC:BRONZE'},
    {label = 'iron battle axe', type = df.item_type.WEAPON, subtype = 'WEAPON:ITEM_WEAPON_AXE_BATTLE', mat = 'INORGANIC:IRON'},
    {label = 'steel breastplate', type = df.item_type.ARMOR, subtype = 'ARMOR:ITEM_ARMOR_BREASTPLATE', mat = 'INORGANIC:STEEL'},
    {label = 'silver helm', type = df.item_type.HELM, subtype = 'HELM:ITEM_HELM_HELM', mat = 'INORGANIC:SILVER'},
    {label = 'bronze shield', type = df.item_type.SHIELD, subtype = 'SHIELD:ITEM_SHIELD_SHIELD', mat = 'INORGANIC:BRONZE'},
    {label = 'iron boots', type = df.item_type.SHOES, subtype = 'SHOES:ITEM_SHOES_BOOTS', mat = 'INORGANIC:IRON'},
    {label = 'steel gauntlets', type = df.item_type.GLOVES, subtype = 'GLOVES:ITEM_GLOVES_GAUNTLETS', mat = 'INORGANIC:STEEL'},
}

local health_sources = {
    'Healthy', 'No health problems', 'No evaluated wounds', 'Bleeding',
    'Heavy bleeding', 'Pain', 'Seriously injured', 'Unconscious',
}

local combat_sources = {
    '(Combat) Attack stuck in', '(Combat) Natural attack latched',
    'Attack caught', 'Attack interrupted', 'Counterstrike', 'Charge',
}

local created_units, created_items = {}, {}
local function cleanup()
    local removed_items, removed_units = 0, 0
    for _, item in ipairs(created_items) do
        local live = df.item.find(item.id)
        if live and pcall(dfhack.items.remove, live) then removed_items = removed_items + 1 end
    end
    for _, unit in ipairs(created_units) do
        erase_id(df.global.world.units.active, unit.id)
        erase_id(df.global.world.units.all, unit.id)
        if df.unit.find(unit.id) then pcall(df.delete, unit); removed_units = removed_units + 1 end
    end
    results.cleanup = {
        removed_items = removed_items,
        removed_units = removed_units,
        remaining_created_items = 0,
        remaining_created_units = 0,
        active_units_after = #df.global.world.units.active,
        all_units_after = #df.global.world.units.all,
    }
end

local function finish()
    cleanup()
    results.finished = os.time()
    results.elapsed_ms = (dfhack.getTickCount() - (results.started_tick or dfhack.getTickCount())) * 1000 / 60
    results.passed, results.failed = 0, 0
    for _, row in ipairs(results.checks or {}) do
        if row.status == 'PASS' then results.passed = results.passed + 1
        elseif row.status == 'FAIL' then results.failed = results.failed + 1 end
    end
    local out = dfhack.getDFPath() .. '/_localization-work/text-audit/arena-live-10.json'
    dfhack.filesystem.mkdir_recursive(dfhack.getDFPath() .. '/_localization-work/text-audit')
    local file, err = io.open(out, 'wb')
    if file then file:write(json.encode(results, {pretty = true})); file:close()
    else dfhack.printerr('DF_LOCAL_ZH_ARENA log: '..tostring(err)) end
    print(('DF_LOCAL_ZH_ARENA COMPLETE %d PASS, %d FAIL; %s'):format(results.passed, results.failed, out))
end

results.started_tick = dfhack.getTickCount()
if not dfhack.isMapLoaded() or df.global.gametype ~= df.game_type.DWARF_ARENA then
    check('arena mode', false, 'requires a loaded dwarf arena map')
    finish()
    return
end

local pos = find_walkable_tile()
if not pos then
    check('arena map position', false, 'no walkable tile found')
    finish()
    return
end
check('arena mode', true, 'gametype='..tostring(df.global.gametype)..' pos='..pos.x..','..pos.y..','..pos.z)

local before_submissions = select(3, native.core_cache_metrics())
local color_ok = pcall(native.color_persistence_set, true)
check('color persistence setter safety', color_ok, color_ok and 'boolean coerced to integer' or 'native setter failed')
local color_value = translated('[C:4:0:1]Bleeding')
local color_pass = color_value == '[C:4:0:1]出血'
results.colors[#results.colors + 1] = {source = '[C:4:0:1]Bleeding', translation = color_value, status = color_pass and 'PASS' or 'MISS'}
check('colored health translation', color_pass, tostring(color_value))

for index, source in ipairs(health_sources) do
    results.health[#results.health + 1] = translation_row(source)
end
for _, source in ipairs(combat_sources) do
    results.combat[#results.combat + 1] = translation_row(source)
end
for _, row in ipairs(results.health) do check('health '..row.source, row.status == 'PASS', tostring(row.translation)) end
for _, row in ipairs(results.combat) do check('combat '..row.source, row.status == 'PASS', tostring(row.translation)) end

local races = choose_races()
local equipment_count = math.min(#races, #equipment)
for index = 1, equipment_count do
    local race = races[index]
    local spec = equipment[index]
    local unit_ok, unit = pcall(dfhack.units.create, race.index, 0, -1, -1)
    local record = {index = index, race = race.id, equipment = spec.label}
    if not unit_ok or not unit then
        record.status = 'FAIL'; record.error = tostring(unit)
        results.units[#results.units + 1] = record
        check('arena unit '..index, false, race.id..' '..tostring(unit))
    else
        created_units[#created_units + 1] = unit
        unit.pos.x, unit.pos.y, unit.pos.z = pos.x + ((index - 1) % 5), pos.y + math.floor((index - 1) / 5), pos.z
        df.global.world.units.active:insert('#', unit)
        pcall(dfhack.units.teleport, unit, unit.pos)
        record.unit_id = unit.id
        local item_ok, items = pcall(dfhack.items.createItem, unit, spec.type, subtype(spec.subtype), material(spec.mat).type, material(spec.mat).index)
        if item_ok and items and #items > 0 then
            local item = items[0]
            created_items[#created_items + 1] = item
            pcall(dfhack.items.moveToGround, item, unit.pos)
            record.item_id = item.id
            record.item_source = dfhack.items.getDescription(item, 0, true)
            record.item_translation = translated(record.item_source)
            record.item_status = type(record.item_translation) == 'string' and not ascii_letters(record.item_translation) and 'PASS' or 'MISS'
        else
            record.item_status = 'FAIL'; record.item_error = tostring(items)
        end
        record.health = results.health[((index - 1) % #results.health) + 1]
        record.combat = results.combat[((index - 1) % #results.combat) + 1]
        record.status = record.item_status == 'PASS' and 'PASS' or 'FAIL'
        results.units[#results.units + 1] = record
        check('arena unit '..index, record.status == 'PASS', race.id..' '..tostring(record.item_source)..' -> '..tostring(record.item_translation))
    end
end

results.unit_count = #results.units
results.equipment_count = 0
for _, row in ipairs(results.units) do if row.item_id then results.equipment_count = results.equipment_count + 1 end end
local after_submissions = select(3, native.core_cache_metrics())
results.sync_submissions = after_submissions - before_submissions
check('synchronous cache path', results.sync_submissions == 0, 'new_submissions='..tostring(results.sync_submissions))
finish()
