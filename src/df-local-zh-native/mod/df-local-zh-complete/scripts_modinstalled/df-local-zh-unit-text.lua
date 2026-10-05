--@module=true

local world, page, boxes, cursor, title_cursor, published, prepared, source_cache, title_delay
local plain_boxes={}
local plain_layouts={}
local health_layouts={}
local nickname_display
local preferences
local adventure_background, background_names, adventure_journal
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
    health_layouts={}
    background_names=nil
end
reset()

local function plain(value)
    return dfhack.df2utf(type(value)=='string' and value or value.value)
        :gsub('%[C:%d+:%d+:%d+%]', ''):gsub('%[P%]', ''):gsub('%[R%]', '')
end

local function color_spans(value,is_utf8,initial_color)
    local text=(is_utf8 and value or dfhack.df2utf(value)):gsub('^%[P%]','')
    local spans,colors={},{}
    local color,tag=string.char(7),'[C:7:0:0]'
    if initial_color and initial_color>=0 and initial_color<128 then
        color=string.char(initial_color)
        tag=('[C:%d:%d:%d]'):format(initial_color%8,math.floor(initial_color/8)%8,math.floor(initial_color/64))
    end
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

local function restore_health(box)
    local id=tostring(box)
    local layout=health_layouts[id]
    if not layout then return end
    for _,part in ipairs(layout.parts) do
        local old=boxes[part.id]
        if old then
            for j=part.first,math.min(part.last,#box.line-1) do
                local k=j-part.first+1
                if box.line[j].text==old.keys[k] then
                    box.line[j].text=old.lines[k].text
                    box.line[j].color=old.lines[k].color
                end
            end
            boxes[part.id]=nil
        end
    end
    health_layouts[id]=nil
end

local function restore(sheets)
    local vectors={'personality_box','thought_box','thoughts_memory_box','unit_health_box',
        'skill_description_box','kill_description_box'}
    for _,name in ipairs(vectors) do
      local vector=sheets[name]
      for i=0,(vector and #vector or 0)-1 do
        local box=vector[i]
        if name=='unit_health_box' then restore_health(box) end
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

local function prepare_plain(box,source,width,runtime,field_id,native_rows,prepared_translation,identity)
    if not box or not source or source=='' or not source:match('[A-Za-z]') or #box.text==0 then return end
    local id=identity or tostring(box)
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
    if not prepared_translation and runtime.observe then runtime.observe(plain(source),'display',field_id) end
    local translated=prepared_translation or runtime.translation(plain(source))
    if not translated or (not prepared_translation and translated:match('[A-Za-z]')) then return end
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
                translation=fragment,width=width,
                verified_name_literals=prepared_translation~=nil and field_id=='setupadventure.background_text'}
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

local function prepare_hover(interface,runtime,native_rows)
    -- Only the currently displayed tooltip is meaningful. The fixed native
    -- array also contains hundreds of hidden/stale instructions.
    if not runtime.display_rows or not interface.hover_instructions_on then return end
    local index=interface.current_hover
    local vector=interface.hover_instruction
    if type(index)~='number' or index%1~=0 or not vector or index<0 or index>=#vector or
        interface.last_displayed_hover_inst~=index then return end
    local box=vector[index]
    if not box or #box.text==0 or #box.text>32 or #native_rows+#box.text>256 then return end
    local parts,width,size={},0,0
    for i=0,#box.text-1 do
        local value=box.text[i].value
        -- Preserve row-ending spaces when rebuilding the complete source.
        -- Unsupported key/color markup keeps DF's original display path.
        if type(value)~='string' or #value>256 or value:find('[^ -~]') or
            value:find('[%[%]{}]') then return end
        size=size+#value;if size>4096 then return end
        parts[#parts+1]=value;width=math.max(width,#value)
    end
    -- One scalar layout slot bounds cache growth as the hover changes. Never
    -- retain DF userdata or string addresses beyond this publication batch.
    local before=#native_rows
    prepare_plain(box,table.concat(parts),width,runtime,'main_interface.hover_instruction',
        native_rows,nil,'visible_hover_instruction')
    if #native_rows==before then return end
    local chunks={}
    for i=before+1,#native_rows do chunks[#chunks+1]=native_rows[i].translation end
    local characters={}
    for _,cp in utf8.codes(table.concat(chunks)) do characters[#characters+1]=utf8.char(cp) end
    local capacity=math.floor(width/2)
    local first,wrapped=1,{}
    local closing='，。！？；：、）》」』】〉〕〗〙〛…,.!?;:)]}'
    local opening='（《「『【〈〔〖〘〚([{'
    for i=1,#chunks do
        local last=math.min(first+capacity-1,#characters)
        while last>=first and last<#characters and
            (closing:find(characters[last+1],1,true) or opening:find(characters[last],1,true)) do
            last=last-1
        end
        if last<first and first<=#characters then break end
        wrapped[i]=table.concat(characters,'',first,last)
        first=last+1
    end
    if first<=#characters or #wrapped~=#chunks then
        -- A punctuation run can exhaust the conservative native row capacity.
        -- Remove only this tooltip, preserving any item/other paragraph batch.
        for i=#native_rows,before+1,-1 do native_rows[i]=nil end
        return
    end
    for i,text in ipairs(wrapped) do native_rows[before+i].translation=text end
end

local function preference_subject(source,sheets,runtime)
    local unit=sheets.active_id and df.unit.find(sheets.active_id)
    if not unit then return source end
    if preferences and preferences.mask_need and (source:find(' after being unable to pray to ',1,true) or source:find(' after communing with ',1,true)) then
        local names={}
        local soul=unit.status.current_soul
        for i,need in ipairs(soul and soul.personality and soul.personality.needs or {}) do
            if i>=64 then break end
            local deity=need.deity_id>=0 and df.historical_figure.find(need.deity_id)
            if deity then
                -- Unit sheets can use either the native or translated surname.
                -- Bind both from the same historical figure, never arbitrary text.
                for _,english in ipairs({false,true}) do
                    names[#names+1]=dfhack.df2utf(dfhack.translation.translateName(deity.name,english))
                end
            end
        end
        local request,bindings=preferences.mask_need(source,names)
        if request then return request,{id=unit.id or sheets.active_id,bindings=bindings} end
    end
    local name=dfhack.df2utf(dfhack.translation.translateName(dfhack.units.getVisibleName(unit),false))
    if source:sub(1,#name+7)~=name..' likes ' then return source end
    if not preferences then return nil end
    local forms={}
    local soul=unit.status.current_soul
    local types={LikePoeticForm={df.poetic_form,'poetic_form_id'},
        LikeMusicalForm={df.musical_form,'musical_form_id'},LikeDanceForm={df.dance_form,'dance_form_id'}}
    for _,pref in ipairs(soul and soul.preferences or {}) do
        local kind=types[df.unitpref_type[pref.type]]
        local form=kind and kind[1].find(pref[kind[2]])
        if form then forms[#forms+1]=dfhack.df2utf(dfhack.translation.translateName(form.name,true)) end
    end
    local request,bindings=preferences.mask(source,name,forms)
    return request,bindings and {id=unit.id or sheets.active_id,bindings=bindings}
end

local function prepare_colored_rows(spans,box,runtime,source)
    if not runtime.announcement_key then return end
    local capacity=math.floor(box.width/2)
    if capacity<4 then return end
    local translated,complete={},true
    -- Thoughts split a single sentence across semantic colors. Translate it as
    -- a whole, then lay out the returned colors without re-decoding UTF-8.
    local full=source and runtime.translation(source)
    local ready=type(full)=='string' and utf8.len(full) and color_spans(full,true,spans[1].color:byte(1))
    if ready then
        for _,span in ipairs(ready) do if span.source:find('[A-Za-z{}]') then ready=nil;break end end
    end
    if ready then spans=ready end
    for i,span in ipairs(spans) do
        if not ready and runtime.observe then runtime.observe(span.source,'display','view_sheets.personality_color_span') end
        local text=ready and span.source or (span.source:match('[A-Za-z]') and runtime.translation(span.source) or span.source)
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

local function prepare_box(box, source, runtime, sheets, prepared_translation, spans, identity)
    local id=identity or tostring(box)
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
        local keys,colors=prepare_colored_rows(spans,box,runtime,source)
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
        if sheets.active_id~=subject.id then return end
        translation=preferences.restore(translation,subject.bindings,runtime.name_translation or runtime.translation)
    end
    if type(translation)~='string' or (not subject and translation:match('[A-Za-z]')) then return end
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
            local render_key=subject and runtime.literal_colored_key or runtime.colored_key
            if not render_key then return end
            local key=render_key(translation:sub(begin,ending-1),color)
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

-- A health box combines independently meaningful paragraphs using [B]. Keep
-- native row ranges, rather than flattening an unknown appearance paragraph
-- into an otherwise supported physical-ability sentence. Cache only scalars;
-- DF may rebuild its vectors between polls, so no line pointers are retained.
local function prepare_health_box(box,value,runtime,sheets)
    if not box or #value>8192 or #box.line>512 then return end
    local id=tostring(box)
    local layout=health_layouts[id]
    if layout and (layout.raw~=value or layout.width~=box.width or layout.count~=#box.line) then
        restore_health(box);layout=nil
    end
    if layout then
        local rebuilt=false
        for _,part in ipairs(layout.parts) do
            local old=boxes[part.id]
            for j=part.first,part.last do
                local k=j-part.first+1
                local expected=old and old.keys[k] or part.rows[k]
                if box.line[j].text~=expected then rebuilt=true;break end
            end
            if rebuilt then break end
        end
        if rebuilt then restore_health(box);layout=nil end
    end
    if not layout then
        local function normalize(s) return s:gsub('%s+',' '):match('^%s*(.-)%s*$') end
        local parts,offset={},1
        local text=dfhack.df2utf(value)
        while true do
            local at=text:find('[B]',offset,true)
            local fragment=text:sub(offset,at and at-1 or #text):match('^%s*(.-)%s*$')
            -- fragment is already UTF-8: remove only supported markup here.
            local clean=fragment:gsub('%[C:[0-7]:[0-7]:[01]%]',''):gsub('^%[P%]','')
            if clean:find('[',1,true) or clean:find(']',1,true) then return end
            -- Adventure can omit the ability paragraph while retaining [B][B].
            -- Keep native blank rows, but do not ask the translator for empty prose.
            if normalize(clean)~='' then
                parts[#parts+1]={source=fragment,plain=clean,id=id..':health:'..(#parts+1)}
                if #parts>32 then return end
            end
            if not at then break end
            offset=at+3
        end
        if #parts==0 then return end
        local line=0
        for _,part in ipairs(parts) do
            while line<#box.line and box.line[line].text:match('^%s*$') do line=line+1 end
            part.first=line
            local rows={}
            while line<#box.line and not box.line[line].text:match('^%s*$') do
                rows[#rows+1]=dfhack.df2utf(box.line[line].text);line=line+1
            end
            part.last=line-1
            if #rows==0 or normalize(table.concat(rows,' '))~=normalize(part.plain) then return end
            part.rows={}
            for j=part.first,part.last do part.rows[j-part.first+1]=box.line[j].text end
            part.spans=color_spans(part.source,true,box.line[part.first].color:byte(1))
            if not part.spans then part.source=part.plain:match('^%s*(.-)%s*$') end
        end
        while line<#box.line and box.line[line].text:match('^%s*$') do line=line+1 end
        if line~=#box.line then return end
        layout={raw=value,width=box.width,count=#box.line,parts=parts};health_layouts[id]=layout
    end
    for _,part in ipairs(layout.parts) do
        local rows={}
        for j=part.first,part.last do
            rows[j-part.first]={text=box.line[j].text,color=box.line[j].color}
        end
        local count=part.last-part.first+1
        local proxy={width=box.width,line=setmetatable(rows,{__len=function() return count end})}
        local commit=prepare_box(proxy,part.source,runtime,sheets,nil,part.spans,part.id)
        if commit then
            commit()
            for j=part.first,part.last do
                local row=rows[j-part.first]
                box.line[j].text=row.text;box.line[j].color=row.color
            end
        end
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
    if active_world and runtime.display_rows then
        local screen=dfhack.gui.getCurViewscreen()
        if df.viewscreen_adventure_logst and screen and screen._type==df.viewscreen_adventure_logst then
            if page~='adventure_log:'..tostring(screen) then
                if dfhack.isMapLoaded() then restore(sheets) end
                reset();page='adventure_log:'..tostring(screen)
            end
            adventure_journal=adventure_journal or reqscript('df-local-zh-adventure-journal')
            runtime.display_rows(adventure_journal.bindings(screen,runtime.translation))
            return
        end
    end
    if active_world and not dfhack.isMapLoaded() and runtime.display_rows then
        local screen=dfhack.gui.getCurViewscreen()
        if df.viewscreen_setupadventurest and screen and screen._type==df.viewscreen_setupadventurest and (screen.mode==0 or screen.mode==5) then
            local sheet=screen.mode==5 and screen.active_sheet_index>=0 and screen.active_sheet_index<#screen.csheet and screen.csheet[screen.active_sheet_index] or nil
            local context='setupadventure:'..tostring(screen)..':'..screen.mode..':'..tostring(screen.active_sheet_index)..':'..tostring(sheet and sheet.sub_mode)
            if page~=context then reset();page=context end
            local native_rows={}
            local function setup_box(box,field,translate)
                if not box or #box.text==0 or #box.text>32 then return end
                local source,width,size={},0,0
                for i=0,#box.text-1 do
                    local text=box.text[i].value
                    -- Fixed explanations are ASCII; background identities may be
                    -- CP437. Decode once after joining, never split UTF-8 bytes.
                    if type(text)~='string' or #text>256 or text:find('[\0-\31\127]') or (not translate and text:find('[^ -~]')) then return end
                    size=size+#text;if size>4096 then return end
                    source[#source+1]=text;width=math.max(width,#text)
                end
                -- The longest native row is a conservative lower bound on the
                -- box width. prepare_plain checks that all Chinese fits; native
                -- drawing retains its foreground/background and string storage.
                if translate then
                    local full=table.concat(source)
                    local translated=translate(dfhack.df2utf(full))
                    if not translated then return end
                    prepare_plain(box,full,width,runtime,field,native_rows,translated)
                else
                    -- Preserve real paragraph separators and their native colors.
                    -- A missing paragraph must not block a separate known one.
                    local first=0
                    while first<#box.text do
                        if source[first+1]:match('^ *$') then first=first+1
                        else
                            local last=first
                            local lines,parts,part_width={},{},0
                            while last<#box.text and not source[last+1]:match('^ *$') do
                                lines[last-first]=box.text[last]
                                parts[#parts+1]=source[last+1];part_width=math.max(part_width,#source[last+1])
                                last=last+1
                            end
                            local count=last-first
                            setmetatable(lines,{__len=function() return count end})
                            prepare_plain({text=lines},table.concat(parts),part_width,runtime,field,native_rows,nil,tostring(box)..':'..first)
                            first=last
                        end
                    end
                end
            end
            if screen.mode==0 then
                for i=0,2 do setup_box(screen.destiny_desc[i],'setupadventure.destiny_desc.'..i) end
                setup_box(screen.difficulty_desc,'setupadventure.difficulty_desc')
            elseif sheet then
                if sheet.sub_mode==9 then
                    adventure_background=adventure_background or reqscript('df-local-zh-adventure-background')
                    setup_box(sheet.background_text,'setupadventure.background_text',function(source)
                        if not background_names or background_names.source~=source or background_names.site~=sheet.start_site_id or background_names.position~=sheet.background_start_squad_epp_id then
                            local site,leaders=adventure_background.identities(sheet)
                            background_names={source=source,site=sheet.start_site_id,position=sheet.background_start_squad_epp_id,name=site,leaders=leaders}
                        end
                        return adventure_background.translate(source,background_names.name,background_names.leaders,runtime.translation)
                    end)
                elseif sheet.sub_mode==7 then
                    setup_box(sheet.appearance_text,'setupadventure.appearance_text')
                elseif sheet.sub_mode==8 then
                    setup_box(sheet.personal_values_text,'setupadventure.personal_values_text')
                    setup_box(sheet.personality_text,'setupadventure.personality_text')
                    setup_box(sheet.civ_values_text,'setupadventure.civ_values_text')
                end
            end
            runtime.display_rows(native_rows)
            return
        end
    end
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
    prepare_hover(df.global.game.main_interface,runtime,native_rows)
    if runtime.display_rows then runtime.display_rows(native_rows) end
    if focus:find('ViewSheets/UNIT/',1,true) then
        for _,pair in ipairs(pairs_to_translate) do
            if focus:find(pair[3],1,true) then
                local raw,display=sheets[pair[1]],sheets[pair[2]]
                local count=math.min(raw and #raw or 0,display and #display or 0)
                local start=count>0 and cursor%count or 0
                for offset=0,math.min(count,8)-1 do
                    local index=(start+offset)%count
                    local value=type(raw[index])=='string' and raw[index] or raw[index].value
                    if pair[3]=='/Health' then
                        prepare_health_box(display[index],value,runtime,sheets)
                    else
                    local spans=pair[3]=='/Thoughts' and color_spans(value) or nil
                    local source=spans and dfhack.df2utf(value) or plain(value)
                    if source:match('[A-Za-z]') then
                        if runtime.observe then runtime.observe(source,'display','view_sheets.'..pair[1]) end
                        local commit=prepare_box(display[index],source,runtime,sheets,nil,spans)
                        if commit then commit() end
                    end
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
                    -- Each paragraph keeps atomic text/palette readiness. An unknown
                    -- deity or one slow model request must not hold the whole page.
                    local commit=prepare_box(sheets.personality_box[cursor],source,runtime,sheets)
                    if commit then commit() end
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
    preferences=preferences or reqscript('df-local-zh-preferences')
    nickname_display=nickname_display or reqscript('df-local-zh-nickname-display')
    -- Unit sheets can contain many rolling rows. Twenty-frame polling keeps
    -- the display translation available without competing with the render
    -- loop in large worlds. A later poll still observes changed pages.
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-unit-text',20,'frames',function()
        local ok,err=pcall(poll,runtime)
        if not ok then
            if runtime.display_rows then runtime.display_rows({}) end
            dfhack.printerr('df-local-zh-unit-text: '..tostring(err))
        end
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
    start({colored_key=runtime.colored_key,literal_colored_key=runtime.literal_colored_key,announcement_key=runtime.announcement_key,
        name_translation=runtime.unit_name_translation,display_rows=runtime.display_rows,
        translation=runtime.unit_translation,publish=runtime.publish,
        observe=reqscript('df-local-zh-prefetch').observe})
end
