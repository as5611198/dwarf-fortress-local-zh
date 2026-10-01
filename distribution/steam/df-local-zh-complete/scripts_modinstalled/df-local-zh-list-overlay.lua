--@module=true

local overlay = require('plugins.overlay')
local captions = reqscript('df-local-zh-legends-list')

CaptionOverlay = defclass(CaptionOverlay, overlay.OverlayWidget)
CaptionOverlay.ATTRS {
    desc='Traditional Chinese Legends list captions',
    default_enabled=true,
    viewscreens='legends',
    full_interface=true,
    frame={l=0,t=0,r=0,b=0},
}

function CaptionOverlay:onRenderBody()
    local runtime = reqscript('df-local-zh-runtime')
    local mouse_x, mouse_y = dfhack.screen.getMousePos()
    for _, row in ipairs(captions.visible_rows()) do
        if row.key then
            local x=3
            local hovered = mouse_x and mouse_y and mouse_x >= x and
                mouse_x < row.width+x and math.abs(mouse_y-row.y) <= 1
            -- Transparent occupied cells hide the complete native caption without
            -- painting over its frame or the separate item-type column.
            local columns=math.min(row.width,row.caption_columns or 0)
            if columns>0 then runtime.draw_key(x,row.y,7,0,string.rep(' ',columns)) end
            runtime.draw_key(x, row.y, hovered and 14 or 7, 0, row.key)
        end
    end
end

OVERLAY_WIDGETS = {captions=CaptionOverlay}
