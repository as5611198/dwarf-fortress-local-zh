--@module=true
local json=require('json')
local paths=reqscript('df-local-zh-paths')
local unit_prewarm=reqscript('df-local-zh-unit-prewarm')
local active_world,observed,slots,next_slot,next_poll,cursor,log_rows,log_errors
local total,ready,active,pending,errors,evicted=0,0,0,0,0,0

local function reset(current)
    active_world=current
    observed,slots={},{}
    log_rows,log_errors={},0
    next_slot,next_poll,cursor,total,ready,active,pending,errors,evicted=1,0,1,0,0,0,0,0,0
end
reset()

local function field(value,name)
    local ok,result=pcall(function() return value[name] end)
    return ok and result or nil
end

local function log(row)
    row.version=1;row.world=active_world
    log_rows[#log_rows+1]=json.encode(row,{pretty=false})..'\n'
end

local function flush_log()
    if #log_rows==0 then return end
    local f=io.open(paths.broker_data()..'/visible-fortress-sources.jsonl','ab')
    if not f then log_errors=log_errors+1
    else
        local ok,written=pcall(f.write,f,table.concat(log_rows))
        local closed,result=pcall(f.close,f)
        if not ok or not written or not closed or not result then log_errors=log_errors+1 end
    end
    log_rows={}
end

local function has_alias(source)
    for word in source:gmatch('[%w_]+') do
        if word=='P_____' or word:match('^L%w%w%w_+$') or
                word:match('^L%w%w%w%w%w%w_+$') or
                (#word==7 and word:match('^L%w+$') and word:find('%d')) or
                word:match('^DFLIVE_') then return true end
    end
    return false
end

local function track(row,pinned)
    local state=observed[row.text]
    if state then return state end
    -- Retain a bounded recent window; even rows beyond 4096 keep completion state.
    while slots[next_slot] and pinned[slots[next_slot]] do next_slot=next_slot%4096+1 end
    local old=slots[next_slot]
    if old then
        local removed=observed[old]
        if removed.ready then ready=ready-1 end
        if removed.error then errors=errors-1 end
        observed[old]=nil;evicted=evicted+1
    else total=total+1 end
    state={next_try=0,delay=250}
    slots[next_slot]=row.text;next_slot=next_slot%4096+1
    observed[row.text]=state;log(row)
    return state
end

function collect(main,focus)
    local rows,seen={},{}
    local function add(source,id,kind)
        if type(source)~='string' or #rows>=32 then return end
        source=dfhack.df2utf(source)
        local clean=source:gsub('%[C:%d+:%d+:%d+%]',''):gsub('%[P%]',''):gsub('%[R%]','')
        if not clean:match('[A-Za-z]') or #source>8000 or seen[source] or
                has_alias(clean) or
                unit_prewarm.fixed_translation(clean) then return end
        seen[source]=true;rows[#rows+1]={text=source,field_id=id,type=kind or 'visible'}
    end
    local function box(value,id,start,kind)
        local text=value and field(value,'text')
        if not text then return end
        local first=math.max(0,math.min(start or 0,#text))
        for i=first,math.min(#text-1,first+31) do
            local row=text[i]
            add(type(row)=='string' and row or field(row,'value'),id..'.text['..i..'].value',kind)
        end
    end
    if focus=='dwarfmode/Default' then
        local mouse=dfhack.gui.getMousePos and dfhack.gui.getMousePos()
        local looks=mouse and field(df.global,'ui_look_list')
        for i=0,math.min(looks and #looks or 0,32)-1 do
            local row=looks[i]
            local pos=field(row,'pos')
            local kind=df.look_info_type and field(df.look_info_type,field(row,'type'))
            -- Unit names keep the typed name path; only read the tile under the mouse.
            if type(kind)=='string' and kind~='Unit' and pos and
                    pos.x==mouse.x and pos.y==mouse.y and pos.z==mouse.z then
                add(field(row,'display_str'),'ui_look_list['..i..'].display_str','map-hover:'..kind)
            end
        end
    end
    local hover=field(main,'current_hover')
    if field(main,'hover_instructions_on') and type(hover)=='number' and hover>=0 then
        box(field(field(main,'hover_instruction'),hover),'main_interface.hover_instruction['..hover..']',nil,'hover')
        local enum=df.main_hover_instruction
        local name=enum and field(enum,hover)
        if type(name)=='string' and name:find('ANNOUNCEMENT',1,true) then
            box(field(main,'hover_announcement_alert_text'),'main_interface.hover_announcement_alert_text',nil,'announcement')
            box(field(main,'hover_announcement_alert_button_text'),'main_interface.hover_announcement_alert_button_text',nil,'announcement')
        end
    end
    local building=field(main,'building')
    if building and (field(building,'current_tool_tip_address') or 0)~=0 then
        box(field(building,'current_tool_tip'),'main_interface.building.current_tool_tip',nil,'tooltip')
    end
    if (field(main,'hover_compass_stid') or -1)>=0 then
        box(field(main,'hover_compass_text'),'main_interface.hover_compass_text',nil,'compass')
    end
    local alert=field(main,'announcement_alert')
    if alert and field(alert,'open') then
        box(field(alert,'alert_text'),'announcement_alert.alert_text',field(alert,'scroll_position_alert'),'announcement')
        box(field(alert,'uac_text'),'announcement_alert.uac_text',field(alert,'scroll_position_uac'),'announcement')
    end
    local trade=field(main,'trade')
    if trade and field(trade,'open') then
        add(field(trade,'title'),'trade.title','trade')
        box(field(trade,'big_announce'),'trade.big_announce',field(trade,'scroll_position_big_announce'),'trade')
    end
    local options=field(main,'options')
    if options and field(options,'open') then
        add(field(options,'header'),'options.header','options')
        box(field(options,'text'),'options.text',field(options,'scroll_position_popup'),'options')
    end
    local help=field(main,'help')
    if help and field(help,'open') then add(field(help,'header'),'help.header','help') end
    local image=field(main,'image_creator')
    if image and field(image,'open') then
        add(field(image,'header'),'image_creator.header','art')
        box(field(image,'art_box'),'image_creator.art_box',field(image,'scroll_position_art_box'),'art')
        if (field(image,'last_selected_index') or -1)>=0 then
            box(field(image,'selected_box'),'image_creator.selected_box',nil,'art')
        end
    end
    local sheets=field(main,'view_sheets')
    if sheets and field(sheets,'open') then
        if focus:find('/ViewSheets/ITEM',1,true) then
            local use=field(sheets,'item_use')
            local first=math.max(0,field(sheets,'scroll_position_item') or 0)
            for i=first,math.min(use and #use-1 or -1,first+31) do
                local value=use[i]
                add(type(value)=='string' and value or field(value,'value'),'view_sheets.item_use['..i..'].value','item-action')
            end
        end
        if focus:find('/ViewSheets/ENGRAVING',1,true) then
            add(field(sheets,'engraving_title'),'view_sheets.engraving_title','engraving')
        end
        if focus:find('/ViewSheets/VERMIN',1,true) then box(field(sheets,'vermin_text'),'view_sheets.vermin_text',nil,'vermin') end
        if focus:find('/ViewSheets/UNIT/Overview',1,true) then box(field(sheets,'guest_text'),'view_sheets.guest_text',nil,'guest') end
    end
    local info=field(main,'info')
    if info and field(info,'open') then
        if focus:find('/Info/ADMINISTRATORS',1,true) then
            box(field(field(info,'administrators'),'desc_hover_text'),'info.administrators.desc_hover_text',nil,'administration')
        end
        if focus:find('/Info/JUSTICE',1,true) then
            local justice=field(info,'justice')
            if field(justice,'viewing_interrogation_report') then
                box(field(justice,'interrogation_report_box'),'info.justice.interrogation_report_box',
                    field(justice,'scroll_position_interrogation_report'),'justice')
            end
        end
    end
    return rows
end

function poll(runtime)
    local current=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if current~=active_world then reset(current) end
    if not current or not dfhack.isMapLoaded() then active,pending=0,0;return end
    local now=dfhack.getTickCount()
    if now<next_poll then return end
    next_poll=now+250
    local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()),'|')
    if not focus:find('dwarfmode/',1,true) then active,pending=0,0;return end
    local rows=collect(df.global.game.main_interface,focus)
    active,pending=#rows,0
    local pinned={}
    for _,row in ipairs(rows) do pinned[row.text]=true end
    for _,row in ipairs(rows) do
        if not track(row,pinned).ready then pending=pending+1 end
    end
    local attempted=0
    for _=1,#rows do
        if cursor>#rows then cursor=1 end
        local row=rows[cursor];cursor=cursor+1
        local state=observed[row.text]
        if not state.ready and now>=state.next_try then
            attempted=attempted+1
            local ok,result=pcall(runtime.prefetch,row.text,'foreground')
            if not ok then
                if not state.error then
                    state.error=true;errors=errors+1
                    log({text=row.text,field_id=row.field_id,type=row.type,error=tostring(result)})
                end
                state.next_try=now+5000
            elseif result then
                state.ready=true;ready=ready+1
                if state.error then state.error=nil;errors=errors-1 end
                pending=math.max(0,pending-1)
                log({text=row.text,field_id=row.field_id,type=row.type,status='native-ready'})
            else
                state.next_try=now+state.delay;state.delay=math.min(1000,state.delay*2)
            end
            if attempted>=2 then break end
        end
    end
    flush_log()
end

function status()
    return {world=active_world,collected=total,tracked=total,ready=ready,active=active,
        pending=pending,errors=errors,evicted=evicted,log_errors=log_errors,scope='recent-visible'}
end
