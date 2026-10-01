--@module=true

-- The title screen's world list draws storage labels directly and bypasses
-- DFI18n's normal string lookup. Replace only those labels, leaving the
-- player-chosen folder name and all row hitboxes untouched.
local overlay = require('plugins.overlay')
local runtime = reqscript('df-local-zh-runtime')

local labels = {
    {source='Portable Folder:', translation='可攜式資料夾：    '},
    {source='Folder:', translation='資料夾：'},
}
local records = {}
local state_key

local function matches_at(x, y, source)
    for offset = 1, #source do
        local tile = dfhack.screen.readTile(x + offset - 1, y)
        if not tile or tile.ch ~= source:byte(offset) then return false end
    end
    return true
end

local function paint_label(x, y, label, color, suffix, suffix_color, suffix_background)
    local key = runtime.literal_key(label.translation)
    if not key then return end
    runtime.draw_key(x, y, color, 0, key)
    if suffix ~= '' then
        dfhack.screen.paintString({fg=suffix_color or color, bg=suffix_background or COLOR_BLACK},
            x + #label.source, y, suffix)
    end
end

local function read_suffix(x, y, width)
    local chars, color, background = {}, COLOR_WHITE, COLOR_BLACK
    for cursor = x, width - 1 do
        local tile = dfhack.screen.readTile(cursor, y)
        local ch = tile and tile.ch or 32
        chars[#chars + 1] = (ch >= 32 and ch <= 126) and string.char(ch) or ' '
        if #chars == 1 and tile then
            color, background = tile.fg or color, tile.bg or background
        end
    end
    return table.concat(chars):gsub('%s+$', ''), color, background
end

TitleOverlay = defclass(TitleOverlay, overlay.OverlayWidget)
TitleOverlay.ATTRS {
    desc='Traditional Chinese title-screen storage labels',
    default_enabled=true,
    viewscreens='title',
    full_interface=true,
    frame={l=0, t=0, r=0, b=0},
}

function TitleOverlay:onRenderBody()
    local screen = dfhack.gui.getCurViewscreen()
    if not screen or not df.viewscreen_titlest:is_instance(screen) or screen.mode ~= 1 then
        records, state_key = {}, nil
        return
    end
    local width, height = dfhack.screen.getWindowSize()
    local current_key = table.concat({tostring(screen), tostring(screen.selected),
        tostring(screen.selected_r), tostring(screen.scroll_position_world_choice)}, ':')
    if current_key ~= state_key then
        state_key, records = current_key, {}
        for y = 0, height - 1 do
            local x = 0
            while x < width do
                local found
                for _, label in ipairs(labels) do
                    if matches_at(x, y, label.source) then found = label; break end
                end
                if found then
                    local tile = dfhack.screen.readTile(x, y)
                    local suffix, suffix_color, suffix_background = read_suffix(x + #found.source, y, width)
                    records[#records + 1] = {
                        x=x, y=y, label=found, color=tile and tile.fg or COLOR_WHITE,
                        suffix=suffix, suffix_color=suffix_color, suffix_background=suffix_background,
                    }
                    x = x + #found.source
                else
                    x = x + 1
                end
            end
        end
    end
    for _, record in ipairs(records) do
        paint_label(record.x, record.y, record.label, record.color, record.suffix,
            record.suffix_color, record.suffix_background)
    end
end

OVERLAY_WIDGETS = {storage_labels=TitleOverlay}
