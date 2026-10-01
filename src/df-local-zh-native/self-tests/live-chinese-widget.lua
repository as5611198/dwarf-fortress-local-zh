local native=reqscript('df-local-zh-core/native')
local context=...;if type(context)~='table' then context={} end
local search=reqscript('df-local-zh-search')
local gui=require('gui')
local json=require('json')
assert(dfhack.isMapLoaded() and df.global.pause_state)
local screen=dfhack.gui.getCurViewscreen()
local function child(widget,index) return assert(dfhack.gui.getWidgetChildren(widget)[index]) end
local list=child(child(child(df.global.game.main_interface.info.creatures,1),1),1)
local box=child(list,2)
assert(df.widget_textbox:is_instance(box))
print('FILTER_RECT '..box.rect.x1..','..box.rect.y1..','..box.rect.x2..','..box.rect.y2)
for key,value in pairs(list) do if key=='filter_str' or key=='entry_list' then print('LIST '..key..' '..tostring(value)) end end
local table_widget=child(list,1)
for key,value in pairs(table_widget) do print('TABLE '..key..' '..tostring(value)) end
local enabler,gps=df.global.enabler,df.global.gps
local old=enabler.mouse_focus;enabler.mouse_focus=true
gps.mouse_x,gps.mouse_y=box.rect.x1+1,box.rect.y1
gui.simulateInput(screen,'_MOUSE_L');enabler.mouse_focus=old
assert(df.global.gview.cur_textbox==box,'Automated click must activate the native text box')
search.sync()
local before=native.search_metrics()
assert(native.search_push_text('礦工'))
local started=dfhack.getTickCount()
local function completed()
    if context.cancelled then return end
    local comparisons,matches=native.search_metrics()
    if search.active_query()~='礦工' or comparisons==before then
        assert(dfhack.getTickCount()-started<3000,'Widget filter completion timeout')
        dfhack.timeout(1,'frames',completed);return
    end
    local rows=child(table_widget,2)
    local ids={}
    for _,row_widget in ipairs(dfhack.gui.getWidgetChildren(rows)) do
        local portrait=child(row_widget,1)
        if df.widget_unit_portrait:is_instance(portrait) then ids[#ids+1]=portrait.u.id end
    end
    local row={query=search.active_query(),filter=list.filter_str,comparisons=comparisons-before,matches=matches,
        entries=#list.entry_list,visible=#dfhack.gui.getWidgetChildren(rows),unit_ids=ids,passed=#ids>0}
    local f=assert(io.open(context.log_path or dfhack.getDFPath()..'/_localization-work/text-audit/chinese-widget-live.json','wb'))
    f:write(json.encode(row));f:close()
    print('NATIVE_WIDGET '..json.encode(row))
    if context.completed then context.completed(row) end
end
dfhack.timeout(1,'frames',completed)
