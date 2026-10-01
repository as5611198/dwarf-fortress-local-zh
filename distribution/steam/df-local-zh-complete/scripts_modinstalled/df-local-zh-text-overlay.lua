--@module=true

-- Text viewers are rendered from mutable screen rows and bypass some of the
-- normal DFI18n lookup paths. Capture the native rows once per page/scroll
-- state, then paint validated Chinese aliases over the original cells.
local overlay = require('plugins.overlay')
local runtime = reqscript('df-local-zh-runtime')

local state

local function safe_field(screen, name)
    local ok, value = pcall(function() return screen[name] end)
    return ok and tostring(value or '') or ''
end

local function focus_name(screen)
    local ok, value = pcall(dfhack.gui.getFocusString, screen)
    return ok and value or ''
end

local function is_text_viewer(focus)
    return focus == 'textviewer' or focus:find('/textviewer', 1, true) ~= nil
end

local function row_segments(y, width)
    local chars, colors, backgrounds = {}, {}, {}
    for x = 0, width - 1 do
        local tile = dfhack.screen.readTile(x, y)
        local ch = tile and tile.ch or 0
        local ok, value = pcall(string.char, ch)
        chars[x + 1] = ok and value or ' '
        colors[x + 1] = tile and tile.fg or COLOR_WHITE
        backgrounds[x + 1] = tile and tile.bg or COLOR_BLACK
    end
    local raw = table.concat(chars)
    local result, start, x = {}, 1, 1
    local function append(stop)
        while start <= stop and raw:sub(start, start) == ' ' do start = start + 1 end
        while stop >= start and raw:sub(stop, stop) == ' ' do stop = stop - 1 end
        if stop < start then return end
        local text = raw:sub(start, stop)
        if not text:match('[A-Za-z]') or #text < 2 then return end
        result[#result + 1] = {
            x = start - 1, y = y, width = stop - start + 1, text = dfhack.df2utf(text),
            color = colors[start] or COLOR_WHITE, background = backgrounds[start] or COLOR_BLACK,
        }
    end
    -- Three or more spaces are treated as a column separator; one or two
    -- spaces stay inside a sentence and are sent to the provider together.
    while x <= width do
        if raw:sub(x, x) == ' ' then
            local stop = x
            while stop <= width and raw:sub(stop, stop) == ' ' do stop = stop + 1 end
            if stop - x >= 3 then append(x - 1); start = stop end
            x = stop
        else
            x = x + 1
        end
    end
    append(width)
    return result
end

local function capture(screen, focus, width, height)
    local rows = {}
    local key = table.concat({tostring(screen), focus, tostring(width), tostring(height),
        safe_field(screen, 'scroll'), safe_field(screen, 'scroll_position'),
        safe_field(screen, 'top_line'), safe_field(screen, 'cursor_pos'),
        safe_field(screen, 'selected'), safe_field(screen, 'sel_idx')}, ':')
    for y = 0, height - 1 do
        for _, segment in ipairs(row_segments(y, width)) do rows[#rows + 1] = segment end
    end
    return {key = key, rows = rows}
end

TextOverlay = defclass(TextOverlay, overlay.OverlayWidget)
TextOverlay.ATTRS {
    desc = 'Traditional Chinese text viewer fallback',
    default_enabled = true,
    viewscreens = 'all',
    full_interface = true,
    fullscreen = true,
    frame = {l = 0, t = 0, r = 0, b = 0},
}

function TextOverlay:onRenderBody()
    local screen = dfhack.gui.getCurViewscreen()
    local focus = focus_name(screen)
    if not screen or not is_text_viewer(focus) then state = nil; return end
    local width, height = dfhack.screen.getWindowSize()
    local current_key = table.concat({tostring(screen), focus, tostring(width), tostring(height),
        safe_field(screen, 'scroll'), safe_field(screen, 'scroll_position'),
        safe_field(screen, 'top_line'), safe_field(screen, 'cursor_pos'),
        safe_field(screen, 'selected'), safe_field(screen, 'sel_idx')}, ':')
    if not state or state.key ~= current_key then state = capture(screen, focus, width, height) end
    for _, segment in ipairs(state.rows) do
        if segment.width >= 7 then
            local key = runtime.short_lookup(segment.text, true, nil, segment.width) or runtime.pending_key()
            if key then
                dfhack.screen.fillRect({ch = 32, fg = COLOR_WHITE, bg = segment.background},
                    segment.x, segment.y, segment.x + segment.width - 1, segment.y)
                runtime.draw_key(segment.x, segment.y, segment.color, segment.background, key)
            end
        end
    end
end

OVERLAY_WIDGETS = {text = TextOverlay}

