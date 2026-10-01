local root=dfhack.getDFPath()
local editor=setmetatable({},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-search-editor.lua','t',editor))()
local stocks={open=true,item_filter='',entering_item_filter=true}
local actions={}
local json=require('json')
local screen={}
local native={search_set_query=function(_,query) return query~='' and 'LZHS000___' or '' end,
    search_input_focus=function() end,search_input_drain=function()
        local result=json.encode(actions);actions={};return result
    end}
local env=setmetatable({reqscript=function(name)
    return name=='df-local-zh-search-editor' and editor or native
end,require=function(name)
    if name=='gui' then return {simulateInput=function() end} end
    if name=='gui.widgets' then return {EditField={setCursor=function() end}} end
    if name=='gui.widgets.text_area.text_area_content' then return {} end
    if name=='utils' then return {search_text=function() return false end} end
    if name=='plugins.overlay' then return {OverlayWidget=nil} end
    return require(name)
end,dfhack={onStateChange={},isMapLoaded=function() return false end,gui={
    getCurViewscreen=function() return screen end,getDFViewscreen=function() return screen end,
    getFocusStrings=function() return {'dwarfmode/Stocks'} end}},
df={global={gview={},gps={mouse_x=0,mouse_y=0},game={main_interface={stocks=stocks}}},
    viewscreen_legendsst={is_instance=function() return false end},
    viewscreen_setupdwarfgamest={is_instance=function() return false end},
    viewscreen_dwarfmodest={is_instance=function() return true end}},
defclass=function() return {ATTRS=function() end} end,
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-search.lua','t',env))()
actions={{kind='text',text='gaojiaobei'}};env.sync()
assert(stocks.item_filter=='LZHS000___','ASCII Pinyin must reach the native localized matcher')
assert(env.active_query()=='gaojiaobei')
env.configure{pinyin=false};env.sync()
assert(stocks.item_filter=='gaojiaobei','disabling Pinyin must restore native English search')
actions={{kind='select_all'},{kind='text',text='铁'}};env.sync()
assert(stocks.item_filter=='LZHS000___','Chinese search must stay active when Pinyin is disabled')
print('PINYIN_ROUTING PASS native ASCII handles and immediate setting changes')
