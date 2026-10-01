--@module=true

-- The embark detail panel is rendered as dynamic screen text rather than a
-- DFI18n lookup. Read the native rows before painting and replace only rows
-- that contain Latin text, keeping the map and its input handling intact.
local overlay = require('plugins.overlay')
local runtime = reqscript('df-local-zh-runtime')

local fixed = {
    ['Moderate'] = '中等',
    ['Sparse'] = '稀疏',
    ['Scarce'] = '稀少',
    ['Woodland'] = '林地',
    ['Heavily Forested'] = '森林茂密',
    ['None'] = '無',
    ['Thick'] = '茂密',
    ['Calm'] = '平靜',
    ['Wilderness'] = '荒原',
    ['Untamed Wilds'] = '未馴荒野',
    ['Sinister'] = '陰森',
    ['Cold'] = '寒冷',
    ['Temperate'] = '溫和',
    ['Warm'] = '溫暖',
    ['Hot'] = '炎熱',
    ['Scorching'] = '酷熱',
    ['Dwarven hillocks'] = '矮人丘陵',
}

local composite_labels = {
    Temperature = '溫度：',
    Trees = '樹木：',
    ['Other Vegetation'] = '其他植被：',
    Surroundings = '周遭環境：',
    Stream = '溪流：',
    Brook = '溪流：',
    River = '河流：',
}

local races = { Humans='人類', Elves='精靈', Goblins='哥布林', Dwarves='矮人' }
local resources = {
    Iron='鐵', Gold='金色', Silver='銀色', Copper='銅色', Nickel='鎳', Zinc='鋅',
    Platinum='鉑', Tin='錫', Lead='鉛', Steel='鋼', Coal='煤', Flux='熔劑石層',
}

local amounts = {
    ['a few hundred'] = '幾百',
    ['a thousand'] = '一千',
    ['two thousand'] = '兩千',
    ['three thousand'] = '三千',
    ['four thousand'] = '四千',
    ['five thousand'] = '五千',
    ['hundred'] = '一百',
    ['hundreds'] = '數百',
}

local captured_selection
local native_lines
local capture_delay = 0

local function native_line(x1, x2, y)
    local chars, first, color = {}, nil, COLOR_WHITE
    for x = x1, x2 do
        local tile = dfhack.screen.readTile(x, y)
        local ch = tile and tile.ch or 0
        if ch and ch > 0 then
            chars[#chars + 1] = string.char(ch)
            if not first then first, color = #chars, tile.fg or COLOR_WHITE end
        else
            chars[#chars + 1] = ' '
        end
    end
    local raw = table.concat(chars):gsub('%s+$', '')
    if raw == '' then return nil end
    local leading = raw:match('^%s*') or ''
    local text = raw:sub(#leading + 1)
    return {text=dfhack.df2utf(text), indent=#leading, color=color}
end

local function static_translation(text)
    if fixed[text] then return fixed[text] end
    local label, value = text:match('^(.-):%s+(.+)$')
    if label and composite_labels[label] then
        local translated = fixed[value]
        if translated then return composite_labels[label] .. translated end
    end
    local amount = text:match('^Hostile, (.+)$')
    if amount and amounts[amount] then return '敵對，約有' .. amounts[amount] end
    local race, hostile_amount = text:match('^(%a+)%s+Hostile, (.+)$')
    if race and races[race] and amounts[hostile_amount] then
        return races[race] .. '　敵對，約有' .. amounts[hostile_amount]
    end
    return nil
end

local function keep_native_translation(text)
    if text:match('^(Humans|Elves|Dwarves)%s+') then return true end
    local words = 0
    for word in text:gmatch('%S+') do
        words = words + 1
        if not resources[word] then return false end
    end
    return words > 0
end

local function key_for(line, max_width)
    local translation = static_translation(line.text)
    if translation then return runtime.literal_key(translation) end
    -- Use the normal dynamic queue for generated region, site, civilization,
    -- and settlement names. The pending key masks the native English row while
    -- a provider result is being validated and loaded into DFI18n.
    return runtime.short_lookup(line.text, true, nil, max_width) or runtime.pending_key()
end

EmbarkOverlay = defclass(EmbarkOverlay, overlay.OverlayWidget)
EmbarkOverlay.ATTRS {
    desc='Traditional Chinese embark detail panel',
    default_enabled=true,
    viewscreens='choose_start_site',
    full_interface=true,
    frame={l=0,t=0,r=0,b=0},
}

function EmbarkOverlay:onRenderBody()
    local width, height = dfhack.screen.getWindowSize()
    -- The native embark panel is 39 columns wide at the supported interface
    -- sizes. Keep the replacement inside its gold border to avoid covering
    -- the map when the window is resized.
    local x1 = math.max(0, width - 39)
    local x2 = width - 2
    local screen = dfhack.gui.getCurViewscreen()
    if not screen or screen.zoomed_in then
        native_lines = nil
        captured_selection = nil
        return
    end
    local location = screen and screen.location
    local position = location and location.region_pos
    local selection = position and (tostring(position.x) .. ':' .. tostring(position.y)) or 'none'
    if selection ~= captured_selection then
        captured_selection = selection
        native_lines = nil
        capture_delay = 1
    end
    if capture_delay > 0 then
        capture_delay = capture_delay - 1
        return
    end
    if not native_lines then
        native_lines = {}
        for y = 1, math.min(height - 2, 46) do
            local line = native_line(x1, x2, y)
            if line and line.text:match('[A-Za-z]') then native_lines[y] = line end
        end
    end
    for y, line in pairs(native_lines) do
        local key = not keep_native_translation(line.text) and
            key_for(line, math.max(8, x2 - x1 - line.indent)) or nil
        if key then
            dfhack.screen.fillRect({ch=32,fg=COLOR_WHITE,bg=COLOR_BLACK},
                x1, y, x2, y)
            runtime.draw_key(x1 + line.indent, y, line.color, 0, key)
        end
    end
end

OVERLAY_WIDGETS = {embark=EmbarkOverlay}
