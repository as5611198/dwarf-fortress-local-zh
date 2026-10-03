--@module=true
local native=reqscript('df-local-zh-core/native')
local editor=reqscript('df-local-zh-search-editor')
local unicode=reqscript('df-local-zh-unicode')
local gui=require('gui')
local widgets=require('gui.widgets')
local utils=require('utils')
local json=require('json')
local overlay=require('plugins.overlay')
local records=setmetatable({}, {__mode='k'})
local focused
local slots=setmetatable({}, {__mode='v'})
local last_focus
local syncing=false
local pinyin_enabled=true
local custom_drawn,custom_screen
local render_ime
local rename_adapter
-- Explicit adapters share the native input bridge without becoming filters.
function track(view,options)
    view._df_local_zh_ime=true
    if not view.focus then return end
    custom_drawn,custom_screen=view,dfhack.gui.getCurViewscreen()
    local value=options.get()
    local result=records[view]
    local cursor=options.cursor and options.cursor() or #value+1
    if not result or result.state.text~=value then
        result={key=view,literal=true,state=editor.new(value,editor.clamp(value,cursor),options)}
        records[view]=result
    else
        result.state.cursor=editor.clamp(value,cursor)
    end
    result.get=options.get;result.set=options.set;result.rect=options.rect
    result.anchor=options.anchor
    result.set_cursor=options.set_cursor
    result.state.selected=view.selected or nil
    sync()
end
function configure(value) pinyin_enabled=value.pinyin~=false end
local function allocate()
    for candidate=0,119 do
        if not slots[candidate] then native.search_set_query(candidate,'');return candidate end
    end
    error('Chinese search has reached its active-field limit')
end

local fields={
    {'stocks','item_filter','entering_item_filter'},
    {'assign_trade','item_filter','entering_item_filter'},
    {'assign_display_item','item_filter','entering_item_filter'},
    {'construction','item_filter','entering_item_filter',nil,'building'},
    {'trade','item_filter','entering_item_filter',0},
    {'trade','item_filter','entering_item_filter',1},
    {'job_details','material_filter','material_doing_filter'},
    {'job_details','clothing_size_race_filter','clothing_size_race_doing_filter'},
    {'job_details','dye_object_filter','dye_object_doing_filter'},
    {'job_details','mix_dye_filter','mix_dye_doing_filter'},
    {'job_details','plant_filter','plant_doing_filter'},
    {'image_creator','filter','doing_filter'},
    {'custom_stockpile','spec_filter','entering_spec_filter'},
    {'view_sheets','building_job_filter_str','entering_building_job_filter'},
    {'create_work_order','job_filter','entering_job_filter'},
    {'info.justice','counterintelligence_filter_str','entering_counterintelligence_filter'},
    {'arena_unit','filter','editing_filter'},
    {'arena_tree','filter','editing_filter'},
}

local function field_get(object,key,index)
    local ok,value=pcall(function() return index and object[key][index] or object[key] end)
    return ok and value or nil
end
local function field_set(object,key,index,value)
    if index then object[key][index]=value else object[key]=value end
end

local function record(key,get,set,notify,rect,exit)
    local value=get()
    local result=records[key]
    if not result or value~=result.handle then
        local slot=result and result.slot or allocate()
        if result then native.search_set_query(slot,'') end
        result={key=key,slot=slot,handle=value or '',state=editor.new(unicode.decode(value or '')),get=get,set=set,notify=notify,rect=rect,exit=exit}
        records[key]=result;slots[slot]=result
    end
    result.get,result.set,result.notify,result.rect,result.exit=get,set,notify,rect,exit
    return result
end

local function legacy_field(object,field,key)
    return record(key,function() return field_get(object,field[2],field[4]) end,
        function(value) field_set(object,field[2],field[4],value) end,
        function()
            gui.simulateInput(dfhack.gui.getCurViewscreen(),'STRING_A032')
            gui.simulateInput(dfhack.gui.getCurViewscreen(),'STRING_A000')
        end,nil,function() field_set(object,field[3],field[4],false) end)
end

local function native_field()
    local screen=dfhack.gui.getCurViewscreen()
    if screen~=dfhack.gui.getDFViewscreen() then return end
    local textbox=field_get(df.global.gview,'cur_textbox')
    if textbox and field_get(textbox,'textbox_type')==0 then
        return record('widget:'..tostring(textbox),function() return textbox.str end,
            function(value) textbox.str=value end,
            function()
                local _,widget_address=df.sizeof(textbox)
                local _,callback_address=df.sizeof(textbox:_field('callback'))
                assert(native.search_widget_notify(widget_address,callback_address),'Missing native search callback')
            end,textbox.rect)
    end
    if df.viewscreen_legendsst:is_instance(screen) then
        local page=screen.page[screen.active_page_index]
        if page and page.entering_filter then
            return legacy_field(page,{'legends','filter_str','entering_filter'},'legends.filter')
        end
    elseif df.viewscreen_setupdwarfgamest:is_instance(screen) and screen.entering_item_filter then
        return legacy_field(screen,{'embark','item_filter','entering_item_filter'},'embark.filter')
    end
    if not df.viewscreen_dwarfmodest:is_instance(screen) then return end
    local interface=df.global.game.main_interface
    local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()),'/'):lower():gsub('_','')
    if focus=='dwarfmode/default' then return end
    for _,field in ipairs(fields) do
        local object=interface
        for component in field[1]:gmatch('[^.]+') do object=object and field_get(object,component) end
        local field_focus=(field[5] or field[1]):gsub('[^%w]','')
        if object and field_get(object,field[3],field[4])==true and
                (field_get(object,'open')==true or focus:gsub('/',''):find(field_focus,1,true)) then
            local key=field[1]..'.'..field[2]..tostring(field[4] or '')
            return legacy_field(object,field,key)
        end
    end
end

local function is_search_edit(view)
    local parent=view.parent_view
    return view._df_local_zh_ime or (parent and parent.edit==view and parent.list and type(parent.getFilter)=='function')
        or (view.view_id or ''):lower():find('filter') or (view.view_id or ''):lower():find('search')
end
local function hack_field()
    local screen=dfhack.gui.getCurViewscreen()
    local edit=search_drawn_screen==screen and search_drawn_edit or nil
    if not edit or not edit.focus then return end
    local owner=edit
    while owner.parent_view do owner=owner.parent_view end
    if owner._native and (owner._native~=screen or not owner:isActive()) then return end
    local result=records[edit]
    if not result then
        result={slot=allocate(),state=editor.new(edit.text,editor.clamp(edit.text,edit.cursor)),edit=edit}
        records[edit]=result;slots[result.slot]=result
    elseif result.state.text~=edit.text then result.state=editor.new(edit.text,editor.clamp(edit.text,edit.cursor)) end
    return result
end
local function custom_field()
    if custom_screen~=dfhack.gui.getCurViewscreen() or not custom_drawn or not custom_drawn.focus then return end
    local parent=custom_drawn
    while parent do
        if utils.getval(parent.visible)==false then return end
        parent=parent.parent_view
    end
    return records[custom_drawn]
end

local function sync_field()
    local screen=dfhack.gui.getCurViewscreen()
    local focus=tostring(screen)..':'..table.concat(dfhack.gui.getFocusStrings(screen),'/')
    if focus~=last_focus then
        local live={}
        local count=0
        local function visit(widget)
            if not widget or not df.widget:is_instance(widget) or count>=8192 then return end
            local key='widget:'..tostring(widget)
            if live[key] then return end
            live[key]=true;count=count+1
            if df.widget_container:is_instance(widget) then
                for _,child in ipairs(dfhack.gui.getWidgetChildren(widget)) do visit(child) end
            end
        end
        if dfhack.isMapLoaded() then
            local mi=df.global.game.main_interface
            for _,object in pairs(mi) do if type(object)=='userdata' then visit(object) end end
            for _,object in pairs(mi.info) do if type(object)=='userdata' then visit(object) end end
        end
        visit(field_get(df.global.gview,'cur_textbox'))
        for key,result in pairs(records) do
            if type(key)=='string' and key:sub(1,7)=='widget:' and not live[key] then
                native.search_set_query(result.slot,'');slots[result.slot]=nil;records[key]=nil
            end
        end
        if search_drawn_screen~=screen then search_drawn_edit,search_drawn_screen=nil,nil end
        last_focus=focus
    end
    local current=custom_field() or hack_field() or native_field()
    if current~=focused then
        if focused then editor.apply(focused.state,{kind='cancel'}) end
        if focused and focused.exit and (not current or current.key~=focused.key) then focused.exit() end
        native.search_input_focus(0,0,0,0,0)
        focused=current
    end
    if not current then return end
    local rect=current.rect or current.edit and current.edit.text_area.frame_body
    local anchor=rect and rect.x1 or df.global.gps.mouse_x or 0
    if rect and not current.anchor then
        local before=current.state.text:sub(1,current.state.cursor-1)
        local width=rect.x2-rect.x1
        local start=1
        if current.edit or current.literal then
            while start<#before+1 and native.search_columns(before:sub(start))>=math.max(1,width) do
                start=utf8.offset(before,2,start) or #before+1
            end
        end
        anchor=anchor+math.min(native.search_columns(before:sub(start)),math.max(0,width))
    end
    native.search_input_focus(1,anchor,
        rect and rect.y1 or df.global.gps.mouse_y or 0,
        1,1)
    local changed=false
    for _,action in ipairs(json.decode(native.search_input_drain())) do
        if action.kind=='copy' or action.kind=='cut' then
            local content=current.edit and current.edit.text_area.text_area
            local text,from,to=editor.clipboard_range(current.state,content and content.sel_end)
            if text and native.search_clipboard_write(text) and action.kind=='cut' then
                changed=editor.cut_range(current.state,from,to) or changed
                if content then content.sel_end=nil end
            end
        else
            changed=editor.apply(current.state,action) or changed
        end
    end
    if current.literal then
        if changed then current.set(current.state.text) end
        if current.set_cursor then current.set_cursor(current.state.cursor,current.state.selected) end
    elseif current.edit then
        if changed then current.edit:setText(current.state.text,current.state.cursor)
        else current.edit:setCursor(current.state.cursor) end
    elseif changed or current.handle_mode~=pinyin_enabled then
        if current.state.text:find('[\128-\255]') or pinyin_enabled and current.state.text:find('[A-Za-z]') then
            current.handle=native.search_set_query(current.slot,current.state.text)
        else
            native.search_set_query(current.slot,'')
            current.handle=current.state.text
        end
        current.set(current.handle)
        current.handle_mode=pinyin_enabled
        current.notify()
    end
end

function sync()
    -- Native filter notifications can redraw overlays before the update returns.
    if syncing then return end
    syncing=true
    local ok,err=xpcall(sync_field,debug.traceback)
    syncing=false
    if not ok then error(err) end
end

function active_query() return focused and not focused.state.secret and focused.state.text or nil end
function active_composition() return focused and not focused.state.secret and focused.state.composition or nil end
function clear()
    native.search_input_focus(0,0,0,0,0)
    focused=nil;records=setmetatable({}, {__mode='k'});slots=setmetatable({}, {__mode='v'});native.search_clear()
    last_focus=nil
    search_drawn_edit,search_drawn_screen=nil,nil
    custom_drawn,custom_screen=nil,nil
end

function start()
    if started then return end
    local original=utils.search_text
    utils.search_text=function(text,tokens)
        local query=type(tokens)=='table' and table.concat(tokens,' ') or tokens
        if query and utf8.len(query) then
            if original(text,tokens) then return true end
            if not utf8.len(text) then text=dfhack.df2utf(text) end
            return native.search_matches(text,query)
        end
        return original(text,tokens)
    end
    -- Keep all UTF-8 cursor positions on character boundaries, including clicks.
    local set_cursor=widgets.EditField.setCursor
    widgets.EditField.setCursor=function(self,cursor)
        if utf8.len(self.text) then cursor=editor.clamp(self.text,cursor) end
        return set_cursor(self,cursor)
    end
    local render=widgets.EditField.onRenderBody
    widgets.EditField.onRenderBody=function(self,dc)
        if is_search_edit(self) and self.focus then
            search_drawn_edit,search_drawn_screen=self,dfhack.gui.getCurViewscreen()
            sync()
        end
        if render then return render(self,dc) end
    end
    local content=require('gui.widgets.text_area.text_area_content')
    local render_content=content.onRenderBody
    content.onRenderBody=function(self,dc)
        local area=self.parent_view
        local edit=area and area.parent_view
        local preedit=edit and focused and (focused.edit==edit or focused.key==edit) and focused.state.composition or ''
        if not edit or not is_search_edit(edit) or not utf8.len(self.text) then
            return render_content(self,dc)
        end
        -- Search values are literal user input even when entirely ASCII:
        -- e.g. pinyin "tie" must not be translated as the English word "tie".
        local pen=self.main_pen
        dc:pen(pen):fill(0,0,dc.width-1,0,{ch=32})
        local cursor=editor.clamp(self.text,self.cursor)
        local start=1
        while start<cursor and native.search_columns(self.text:sub(start,cursor-1))>=dc.width-1 do
            start=utf8.offset(self.text,2,start) or cursor
        end
        local ending=start
        while ending<=#self.text do
            local next_offset=utf8.offset(self.text,2,ending) or #self.text+1
            if native.search_columns(self.text:sub(start,next_offset-1))>dc.width-1 then break end
            ending=next_offset
        end
        local visible=self.text:sub(start,ending-1)
        local handle=native.search_set_query(120,visible)
        native.dfhack_addstr_flag(dc.x1,dc.y1,pen.fg,pen.bg,pen.bold and 1 or 0,handle,0x80000000)
        if preedit~='' then
            local x=native.search_columns(self.text:sub(start,cursor-1))
            local preview=''
            for _,code in utf8.codes(preedit) do
                local next_preview=preview..utf8.char(code)
                if x+native.search_columns(next_preview)>dc.width then break end
                preview=next_preview
            end
            local preedit_handle=native.search_set_query(121,preview)
            -- A contrasting preedit is display-only and never updates the filter.
            native.dfhack_addstr_flag(dc.x1+x,dc.y1,COLOR_YELLOW,pen.bg,1,preedit_handle,0x80000000)
            return
        end
        if edit.focus and gui.blink_visible(530) then
            dc:seek(native.search_columns(self.text:sub(start,cursor-1)),0):char('_')
        end
    end
    -- ZScreen renders its native parent (including native overlays) before
    -- painting its own Window background. Draw IME feedback after all views
    -- on the current DFHack screen, so that background cannot cover it.
    local screen_render=gui.Screen.onRender
    gui.Screen.onRender=function(self,...)
        screen_render(self,...)
        if self._native==dfhack.gui.getCurViewscreen() then
            sync()
            render_ime()
        end
    end
    dfhack.onStateChange.df_local_zh_search=function(code)
        if code==SC_WORLD_UNLOADED then clear() end
    end
    started=true
end

SearchOverlay=defclass(SearchOverlay,overlay.OverlayWidget)
SearchOverlay.ATTRS{
    desc='UTF-8 Chinese search input and synchronous local filtering',
    default_enabled=true,viewscreens={'all'},
    full_interface=true,hotspot=true,overlay_onupdate_max_freq_seconds=0,
    frame={l=0,t=0,r=0,b=0},
}
function SearchOverlay:overlay_onupdate()
    -- Load only when entering a nickname, then reuse the module. Opening a
    -- screen belongs to update, never to the native-parent render callback.
    local screen=dfhack.gui.getCurViewscreen()
    if screen==dfhack.gui.getDFViewscreen() and df.viewscreen_dwarfmodest:is_instance(screen)
            and df.global.game.main_interface.view_sheets.unit_overview_entering_nickname then
        rename_adapter=rename_adapter or reqscript('df-local-zh-rename')
        rename_adapter.poll_native()
    end
    sync()
end
render_ime=function()
    sync()
    if not focused or focused.state.secret then return end
    local rect=focused.rect or focused.edit and focused.edit.text_area.frame_body
    if not rect then return end
    local candidates=json.decode(native.search_ime_candidates())
    if focused.state.composition=='' and not candidates.active then return end
    local x=rect.x1+(focused.anchor and 0 or math.min(native.search_columns(focused.state.text:sub(1,focused.state.cursor-1)),rect.x2-rect.x1))
    if not focused.edit then
        local preview=''
        for _,code in utf8.codes(focused.state.composition) do
            local next_preview=preview..utf8.char(code)
            if x+native.search_columns(next_preview)>rect.x2+1 then break end
            preview=next_preview
        end
        if preview~='' then
            local handle=native.search_set_query(121,preview)
            native.dfhack_addstr_flag(x,rect.y1,COLOR_YELLOW,COLOR_BLACK,1,handle,0x80000000)
        end
    end
    local width,height=dfhack.screen.getWindowSize()
    local box=editor.candidate_box(candidates,width,height,x,rect.y1,native.search_columns)
    if box then
        local pen={fg=COLOR_LIGHTCYAN,bg=COLOR_BLACK}
        local edge='+'..string.rep('-',box.width-2)..'+'
        dfhack.screen.paintString(pen,box.x,box.y,edge)
        dfhack.screen.paintString(pen,box.x,box.y+1,'|'..string.rep(' ',box.width-2)..'|')
        dfhack.screen.paintString(pen,box.x,box.y+2,edge)
        local handle=native.search_set_query(122,box.line)
        if handle then
            native.dfhack_addstr_flag(box.x+1,box.y+1,COLOR_LIGHTCYAN,COLOR_BLACK,1,handle,0x80000000)
        end
    end
end
function SearchOverlay:onRenderBody() render_ime() end
OVERLAY_WIDGETS={search=SearchOverlay}
start()
