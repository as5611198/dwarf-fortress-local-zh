--@module=true

local world, page, boxes, cursor, title_cursor, published, prepared, source_cache, title_delay
local plain_boxes={}
local plain_layouts={}
local nickname_display
local pairs_to_translate={
    {'raw_thought_str','thought_box','/Thoughts'},
    {'thoughts_raw_memory_str','thoughts_memory_box','/Thoughts'},
    {'unit_health_raw_str','unit_health_box','/Health'},
    {'skill_description_raw_str','skill_description_box','/Skills'},
    {'kill_description_raw_str','kill_description_box','/Military'},
}
local function reset()
    boxes, cursor, title_cursor, published, prepared = {}, 0, 0, {}, {}
    source_cache,title_delay={},0
    plain_boxes={}
    plain_layouts={}
end
reset()

local function plain(value)
    return dfhack.df2utf(type(value)=='string' and value or value.value)
        :gsub('%[C:%d+:%d+:%d+%]', ''):gsub('%[P%]', ''):gsub('%[R%]', '')
end

local function color_spans(value)
    local text=dfhack.df2utf(value):gsub('^%[P%]','')
    local spans,colors={},{}
    local color,tag=string.char(7),'[C:7:0:0]'
    local offset=1
    local function append(fragment)
        if fragment=='' then return end
        local last=spans[#spans]
        if last and last.color==color then last.source=last.source..fragment
        else spans[#spans+1]={source=fragment,color=color,tag=tag} end
    end
    while offset<=#text do
        local first,last,fg,bg,bright=text:find('%[C:([0-7]):([0-7]):([01])%]',offset)
        if not first then append(text:sub(offset));break end
        append(text:sub(offset,first-1))
        tag=text:sub(first,last)
        color=string.char(tonumber(fg)+tonumber(bg)*8+tonumber(bright)*64)
        offset=last+1
    end
    local cleaned={}
    for _,span in ipairs(spans) do
        span.source=span.source:match('^%s*(.-)%s*$')
        -- Unsupported markup keeps the native path; never flatten it silently.
        if span.source:find('[',1,true) or span.source:find(']',1,true) then return nil end
        if span.source~='' then cleaned[#cleaned+1]=span;colors[span.color]=true end
    end
    local count=0;for _ in pairs(colors) do count=count+1 end
    return count>1 and cleaned or nil
end

local function source_at(sheets,index)
    local raw=sheets.personality_raw_str[index]
    local value=type(raw)=='string' and raw or raw.value
    local cached=source_cache[index]
    if cached and cached.value==value then return cached.source,cached.spans end
    local source=plain(value)
    local spans=color_spans(value)
    if spans then source=dfhack.df2utf(value) end
    source_cache[index]={value=value,source=source,spans=spans}
    return source,spans
end

local function restore(sheets)
    local vectors={'personality_box','thought_box','thoughts_memory_box','unit_health_box',
        'skill_description_box','kill_description_box'}
    for _,name in ipairs(vectors) do
      local vector=sheets[name]
      for i=0,(vector and #vector or 0)-1 do
        local box=vector[i]
        local old=boxes[tostring(box)]
        if old and #box.line==#old.lines then
            for j=0,#box.line-1 do
                if box.line[j].text==old.keys[j+1] then
                    box.line[j].text=old.lines[j+1].text
                    box.line[j].color=old.lines[j+1].color
                end
            end
        end
      end
    end
    for _,name in ipairs({'description','current_thought'}) do
        local box=sheets[name]
        local old=box and plain_boxes[tostring(box)]
        if old and #box.text==#old.lines then
            for i=0,#box.text-1 do
                if box.text[i].value==old.keys[i+1] then box.text[i].value=old.lines[i+1] end
            end
        end
    end
    plain_boxes={}
    boxes={}
end

function language_changed()
    if dfhack.isMapLoaded() then restore(df.global.game.main_interface.view_sheets) end
    page=nil;reset()
end

local function prepare_plain(box,source,width,runtime,field_id,native_rows)
    if not box or not source or source=='' or not source:match('[A-Za-z]') or #box.text==0 then return end
    local id=tostring(box)
    if runtime.display_rows and (width or 0)<8 then
        local layout=plain_layouts[id]
        if not layout or layout.source~=source or #layout.lines~=#box.text then return end
        for i=0,#box.text-1 do
            if box.text[i].value~=layout.lines[i+1] then return end
        end
        -- DF temporarily zeros this field while rebuilding the same text.
        -- Only reuse a width proven against this exact paragraph and layout.
        width=layout.width
    end
    local old=plain_boxes[id]
    if old and old.source==source and old.width==width and #box.text==#old.lines then
        local same=true
        for i=0,#box.text-1 do if box.text[i].value~=old.keys[i+1] then same=false;break end end
        if same then return end
    end
    if old then
        for i=0,math.min(#box.text,#old.lines)-1 do
            if box.text[i].value==old.keys[i+1] then box.text[i].value=old.lines[i+1] end
        end
    end
    plain_boxes[id]=nil
    if runtime.observe then runtime.observe(plain(source),'display',field_id) end
    local translated=runtime.translation(plain(source))
    if not translated or translated:match('[A-Za-z]') then return end
    local capacity=math.floor((width or 0)/2)
    local length=utf8.len(translated)
    if capacity<4 or not length or length>capacity*#box.text then return end
    if runtime.display_rows then
        -- Bind original C++ string addresses for native drawing. The game may
        -- rebuild these rows every frame; never compete by writing aliases.
        local lines={}
        for i=0,#box.text-1 do
            lines[i+1]=box.text[i].value
            local _,address=df.sizeof(box.text[i])
            local first=i*capacity+1
            local fragment=''
            if first<=length then
                local begin=utf8.offset(translated,first)
                local ending=utf8.offset(translated,math.min(first+capacity,length+1)) or #translated+1
                fragment=translated:sub(begin,ending-1)
            end
            native_rows[#native_rows+1]={address=address,source=dfhack.df2utf(box.text[i].value),
                translation=fragment,width=width}
        end
        plain_layouts[id]={source=source,width=width,lines=lines}
        return
    end
    local keys,lines={},{}
    for i=0,#box.text-1 do
        lines[i+1]=box.text[i].value
        local first=i*capacity+1
        if first>length then keys[i+1]=''
        else
            local begin=utf8.offset(translated,first)
            local ending=utf8.offset(translated,math.min(first+capacity,length+1)) or #translated+1
            keys[i+1]=runtime.colored_key(translated:sub(begin,ending-1),string.char(7))
            if not keys[i+1] or #keys[i+1]>width then return end
        end
    end
    for i=0,#box.text-1 do box.text[i].value=keys[i+1] end
    plain_boxes[id]={source=source,width=width,lines=lines,keys=keys}
end

local function preference_subject(source,sheets,runtime)
    local unit=sheets.active_id and df.unit.find(sheets.active_id)
    if not unit then return source end
    local name=dfhack.df2utf(dfhack.translation.translateName(dfhack.units.getVisibleName(unit),false))
    if source:sub(1,#name+7)~=name..' likes ' then return source end
    if source:find('{DWARF_NAME}',1,true) then return nil end
    return '{DWARF_NAME}'..source:sub(#name+1),{id=unit.id or sheets.active_id,name=name}
end

local function prepare_colored_rows(spans,box,runtime)
    if not runtime.announcement_key then return end
    local capacity=math.floor(box.width/2)
    if capacity<4 then return end
    local translated,complete={},true
    for i,span in ipairs(spans) do
        if runtime.observe then runtime.observe(span.source,'display','view_sheets.personality_color_span') end
        local text=span.source:match('[A-Za-z]') and runtime.translation(span.source) or span.source
        if type(text)~='string' or text=='' or not utf8.len(text) or text:match('[A-Za-z{}%[%]]') then
            complete=false
        else translated[i]=text end
    end
    if not complete then return end
    local rows,row,used={},nil,0
    for i,span in ipairs(spans) do
        for _,codepoint in utf8.codes(translated[i]) do
            if not row or used>=capacity then
                row={text='',color=span.color,tag=nil};rows[#rows+1]=row;used=0
                if #rows>#box.line then return end
            end
            if row.tag~=span.tag then row.text=row.text..span.tag;row.tag=span.tag end
            row.text=row.text..utf8.char(codepoint);used=used+1
        end
    end
    local keys,colors={},{}
    for j=0,#box.line-1 do
        local row=rows[j+1]
        local key=''
        if row then key=runtime.announcement_key(row.text,row.color) end
        if not key or #key>box.width then return end
        keys[j+1]=key
        colors[j+1]=string.rep(row and row.color or string.char(7),#key)
    end
    return keys,colors
end

local function prepare_box(box, source, runtime, sheets, prepared_translation, spans)
    local id=tostring(box)
    local old=boxes[id]
    if old and (box.width~=old.width or old.source~=source or #box.line~=#old.lines) then
        for j=0,math.min(#box.line,#old.lines)-1 do
            if box.line[j].text==old.keys[j+1] then
                box.line[j].text=old.lines[j+1].text
                box.line[j].color=old.lines[j+1].color
            end
        end
        boxes[id]=nil; old=nil
    end
    if old and (old.source~=source or #box.line~=#old.lines) then boxes[id]=nil; old=nil end
    if old then
        for j=0,#box.line-1 do
            if box.line[j].text~=old.keys[j+1] then boxes[id]=nil; old=nil; break end
        end
    end
    if old then return function() end end
    if spans then
        local keys,colors=prepare_colored_rows(spans,box,runtime)
        if not keys then return end
        local lines={}
        for j=0,#box.line-1 do lines[j+1]={text=box.line[j].text,color=box.line[j].color} end
        return function()
            for j=0,#box.line-1 do box.line[j].text=keys[j+1];box.line[j].color=colors[j+1] end
            boxes[id]={source=source,lines=lines,keys=keys,width=box.width}
        end
    end
    local request,subject=preference_subject(source,sheets,runtime)
    if not request then return end
    local translation=prepared_translation or runtime.translation(request)
    if subject and translation then
        local _,tokens=translation:gsub('{DWARF_NAME}','')
        if tokens~=1 or sheets.active_id~=subject.id then return end
        local name=(runtime.name_translation or runtime.translation)(subject.name)
        if not name or name:match('[A-Za-z]') then return end
        translation=translation:gsub('{DWARF_NAME}',function() return name end)
    end
    if type(translation)~='string' or translation:match('[A-Za-z]') then return end
    local length=utf8.len(translation)
    local capacity=math.floor(box.width/2)
    if not length or capacity<4 or length>capacity*#box.line then return end
    local lines, keys={},{}
    for j=0,#box.line-1 do
        lines[j+1]={text=box.line[j].text,color=box.line[j].color}
        local first=j*capacity+1
        if first>length then keys[j+1]=''
        else
            local begin=utf8.offset(translation,first)
            local ending=utf8.offset(translation,math.min(first+capacity,length+1)) or #translation+1
            local color=lines[j+1].color:sub(1,1)
            if color=='' then color=string.char(7) end
            local key=runtime.colored_key(translation:sub(begin,ending-1),color)
            if not key or #key>box.width then return end
            keys[j+1]=key
        end
    end
    return function()
        for j=0,#box.line-1 do
            local color=lines[j+1].color:sub(1,1)
            box.line[j].text=keys[j+1]
            box.line[j].color=string.rep(color~='' and color or string.char(7),#keys[j+1])
        end
        boxes[id]={source=source,lines=lines,keys=keys,width=box.width}
    end
end

function knowledge_title(kind, id)
    local name=df.view_sheet_unit_knowledge_type[kind]
    if name=='WRITTEN_CONTENT' then
        local item=df.written_content.find(id)
        return item and dfhack.df2utf(item.title)
    end
    local types={POETIC_FORM=df.poetic_form,MUSICAL_FORM=df.musical_form,DANCE_FORM=df.dance_form}
    local item=types[name] and types[name].find(id)
    return item and dfhack.df2utf(dfhack.translation.translateName(item.name,true))
end

function poll(runtime)
    local active_world=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    local sheets=df.global.game.main_interface.view_sheets
    if world~=active_world then world=active_world; page=nil; reset() end
    if not active_world or not dfhack.isMapLoaded() then
        if runtime.display_rows then runtime.display_rows({}) end
        return
    end
    local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()),'|')
    local context=focus..':'..tostring(sheets.active_id)
    if context~=page then
        restore(sheets); reset(); page=context
        -- DF carries the corpse's scroll offset into the next item, including
        -- one-row equipment descriptions. Reset only on entering another sheet;
        -- subsequent polling must preserve scrolling within the same item.
        if focus:find('ViewSheets/ITEM',1,true) then
            sheets.scroll_position_description=0
        end
    end
    local native_rows={}
    if focus:find('ViewSheets/',1,true) then
        prepare_plain(sheets.description,sheets.raw_description,sheets.description_width,runtime,'view_sheets.raw_description',native_rows)
        prepare_plain(sheets.current_thought,sheets.raw_current_thought,sheets.current_thought_width,runtime,'view_sheets.raw_current_thought',native_rows)
    end
    if runtime.display_rows then runtime.display_rows(native_rows) end
    if focus:find('ViewSheets/UNIT/',1,true) then
        for _,pair in ipairs(pairs_to_translate) do
            if focus:find(pair[3],1,true) then
                local raw,display=sheets[pair[1]],sheets[pair[2]]
                local count=math.min(raw and #raw or 0,display and #display or 0)
                local start=count>0 and cursor%count or 0
                for offset=0,math.min(count,8)-1 do
                    local index=(start+offset)%count
                    local source=plain(raw[index])
                    if source:match('[A-Za-z]') then
                        if runtime.observe then runtime.observe(source,'display','view_sheets.'..pair[1]) end
                        local commit=prepare_box(display[index],source,runtime,sheets)
                        if commit then commit() end
                    end
                end
                if count>0 then cursor=(start+8)%count end
            end
        end
    end
    if focus:find('ViewSheets/UNIT/Personality/',1,true) then
        local count=math.min(#sheets.personality_raw_str,#sheets.personality_box)
        if count==0 then return end
        local needs=focus:find('/Personality/Needs',1,true)
        local processed=0
        for _=1,count do
            if cursor>=count then cursor=0 end
            local source,spans=source_at(sheets,cursor)
            if source:match('[A-Za-z]') then
                if runtime.observe and not spans then
                    local masked=preference_subject(source,sheets,runtime)
                    if masked then runtime.observe(masked,'display','view_sheets.personality_raw_str') end
                end
                processed=processed+1
                if spans then
                    local commit=prepare_box(sheets.personality_box[cursor],source,runtime,sheets,nil,spans)
                    if commit then commit() end
                elseif needs then
                    if not prepared[source] then
                        local translated=runtime.translation(source)
                        if translated and not translated:match('[A-Za-z]') then prepared[source]=translated end
                    end
                    -- Each paragraph keeps atomic text/palette readiness. An unknown
                    -- deity or one slow model request must not hold the whole page.
                    if prepared[source] then
                        local commit=prepare_box(sheets.personality_box[cursor],source,runtime,sheets,prepared[source])
                        if commit then commit() end
                    end
                else
                    local commit=prepare_box(sheets.personality_box[cursor],source,runtime,sheets)
                    if commit then commit() end
                end
            end
            cursor=cursor+1
            if processed>=8 then break end
        end
    end
    if focus:find('ViewSheets/UNIT/',1,true) then
        if title_delay>0 then title_delay=title_delay-1; return end
        title_delay=19
        local count=math.min(#sheets.unit_knowledge_type,#sheets.unit_knowledge_id)
        if count==0 then return end
        if title_cursor>=count then title_cursor=0 end
        local start=math.max(0,math.min(sheets.scroll_position_unit_skill,count-1))
        for offset=0,math.min(3,count-1) do
            local index=(start+title_cursor+offset)%count
            local source=knowledge_title(sheets.unit_knowledge_type[index],sheets.unit_knowledge_id[index])
            if source and source:match('[A-Za-z]') and not published[source] then
                local translation=runtime.translation(source)
                if translation and not translation:match('[A-Za-z]') and runtime.publish(source,translation) then
                    published[source]=true
                end
            end
        end
        title_cursor=title_cursor+4
    end
end

function start(runtime)
    nickname_display=nickname_display or reqscript('df-local-zh-nickname-display')
    -- Unit sheets can contain many rolling rows. Twenty-frame polling keeps
    -- the display translation available without competing with the render
    -- loop in large worlds. A later poll still observes changed pages.
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-unit-text',20,'frames',function()
        local ok,err=pcall(poll,runtime)
        if not ok then dfhack.printerr('df-local-zh-unit-text: '..tostring(err)) end
        local name_ok,name_err=pcall(nickname_display.poll,runtime)
        if not name_ok then dfhack.printerr('df-local-zh-nickname-display: '..tostring(name_err)) end
    end)
end

function stop()
    require('repeat-util').cancel('df-local-zh-unit-text')
    restore(df.global.game.main_interface.view_sheets)
    reset()
    page=nil
    local ok,native=pcall(reqscript,'df-local-zh-core/native')
    if ok and native.native_display_rows_set then native.native_display_rows_set('[]') end
end

function start_cached()
    local script=dfhack.internal.scripts[dfhack.findScript('df-local-zh-runtime')]
    assert(script and script.env,'Translation runtime must already be loaded')
    local runtime=script.env
    start({colored_key=runtime.colored_key,announcement_key=runtime.announcement_key,
        name_translation=runtime.unit_name_translation,display_rows=runtime.display_rows,
        translation=runtime.unit_translation,publish=runtime.publish,
        observe=reqscript('df-local-zh-prefetch').observe})
end
