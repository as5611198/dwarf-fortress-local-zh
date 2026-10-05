-- Read-only, opt-in capture. Run `arm` before navigating to a selected page,
-- then `capture ROOT PAGE`. Pair the result with a separately captured screenshot.
-- selectedRows are hook selections, not proof of visibility or correct meaning.
local action, root, page = ...
local json = require('json')
local native = reqscript('df-local-zh-core/native')
local settings = reqscript('df-local-zh-settings').effective()
assert(settings.apiEnabled == false and settings.officialAutoDownload == false)
assert(settings.sharedContributions == false)
assert(native.core_trace_status, 'Requires trace schema 2')
if action == 'arm' then
    native.core_trace_enable(1)
    print('OFFLINE_RENDER_TRACE_ARMED')
    return
end
assert(action == 'capture' and type(root) == 'string')
assert(type(page) == 'string' and page:match('^[a-z0-9%-]+$'))
local status = json.decode(native.core_trace_status())
assert(status.enabled and status.schema == 2)
local result = {
    schema=2, page=page, traceStatus=status, rows=json.decode(native.core_trace_read()),
    world=dfhack.getSavePath(), focus=dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()),
    version=reqscript('df-local-zh-core/mod').DISPLAYED_VERSION,
    gameVersion=dfhack.getDFVersion(), tick=dfhack.getTickCount(),
    paused=df.global.pause_state, graphicsFps=df.global.enabler.calculated_gfps,
    apiEnabled=false, officialAutoDownload=false, sharedContributions=false,
    nativeRows=json.decode(native.native_display_rows_status()),
}
native.core_trace_enable(0)
-- Capture complete unit-sheet source buffers once, outside the render hook.
-- Hidden/stale buffers remain diagnostic only; the paired screenshot determines
-- visibility. The existing scanner bounds traversal and reports any scan limits.
if dfhack.isMapLoaded() and dfhack.world.isFortressMode() then
    result.sourceAudit = reqscript('df-local-zh-audit').scan()
end
local state=reqscript('df-local-zh-narrative').view(reqscript('df-local-zh-runtime'))
if state then
    result.narrative={mode=state.mode, index=state.index, scroll=state.scroll, height=state.height, paragraphs={}}
    for i,p in ipairs(state.paragraphs) do
        local parts={}
        for _,part in ipairs(p.parts or {}) do
            parts[#parts+1]={text=part.text, color=part.color, hasLink=part.link~=nil}
        end
        result.narrative.paragraphs[#result.narrative.paragraphs+1]={index=i,source=p.source,
            links=p.request_links,parts=parts,ready=p.parts~=nil,
            visible=p.y and p.last_y>=state.scroll and p.y<=state.scroll+state.height-1 or false}
    end
end
local file=assert(io.open(root..'/'..page..'-render.json','wb'))
assert(file:write(json.encode(result,{pretty=true})));assert(file:close())
print(('OFFLINE_RENDER_CAPTURE %s rows=%d incomplete=%s'):format(page,#result.rows,tostring(status.incomplete)))
