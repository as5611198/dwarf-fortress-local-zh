--@module=true

local current_world
local states = {}
local state
local native_dispatch=false
local link_colors = {[0]=9,[1]=14,[2]=14,[3]=14,[4]=10,[5]=10,[6]=11,[7]=14,[8]=11}
local colors = {
    {0,0,0}, {0,0,128}, {0,128,0}, {0,128,128}, {128,0,0}, {128,0,128},
    {128,128,0}, {192,192,192}, {128,128,128}, {0,128,255}, {0,255,0},
    {0,255,255}, {255,0,0}, {255,0,255}, {255,255,0}, {255,255,255},
}

local function color(word)
    local best, distance = 7, math.huge
    for index,rgb in ipairs(colors) do
        local value = ((word.red or 192)-rgb[1])^2 + ((word.green or 192)-rgb[2])^2 +
            ((word.blue or 192)-rgb[3])^2
        if value < distance then best, distance = index-1, value end
    end
    return best
end

local function clickable(link)
    return link and type(link.type)=='number' and link.type>=0 and link.type<=11 and
        link.type==math.floor(link.type) and type(link.id)=='number' and
        link.id>=0 and link.id<math.huge and link.id==math.floor(link.id)
end

local function protect_subject(paragraph,name)
    if type(name)~='string' or #name==0 or #name>2000 or not utf8.len(name) or
            name:find('[{}%[%]%z\1-\31\127]') or #paragraph.literals>0 or
            paragraph.source:sub(1,#name+5)~=name..' was ' then return end
    local remaining,parts=#name,{}
    for _,part in ipairs(paragraph.original_parts) do
        if remaining==0 then break end
        if part.link then return end
        local value=part.text:sub(1,remaining)
        parts[#parts+1]={text=value,color=part.color}
        remaining=remaining-#value
    end
    if remaining~=0 then return end
    -- Source and native records stay unchanged. Only the local composer sees
    -- a certified name slot; the ordinary rich protocol still receives prose.
    paragraph.literals={{text=name,color=parts[1].color,parts=parts}}
    paragraph.local_source='{{DFT0}}'..paragraph.source:sub(#name+1)
end

local function safe_name(name)
    return type(name)=='string' and #name>0 and #name<=2000 and utf8.len(name) and
        not name:find('[{}%[%]%z\1-\31\127]')
end

local function protect_names(paragraph,names)
    if not names or #names>128 or #paragraph.literals>0 or #paragraph.source>4096 then return end
    local candidates,seen={},{}
    for _,name in ipairs(names) do
        if safe_name(name) and not seen[name] then
            candidates[#candidates+1]=name;seen[name]=true
        end
    end
    table.sort(candidates,function(a,b)if #a==#b then return a<b end return #a>#b end)
    -- Map normalized source bytes back to native palette spans. Never consume
    -- linked text, change original_parts, or infer a click target for a name.
    local slices,pieces,length,previous_link={}, {},0,nil
    local indices={}
    for i,link in ipairs(paragraph.links) do indices[link]=i-1 end
    for _,part in ipairs(paragraph.original_parts) do
        local value=part.text
        if part.link then
            if part.link~=previous_link then
                value=(length>0 and ' ' or '')..'{{DFL'..indices[part.link]..'}}'
            else value='' end
        else
            slices[#slices+1]={first=length+1,last=length+#value,color=part.color}
        end
        pieces[#pieces+1]=value;length=length+#value;previous_link=part.link
    end
    local source=table.concat(pieces)
    if source~=paragraph.source then return end
    local literals,output,offset={}, {},1
    local function boundary(c)return c=='' or c:match('[%s%.,;:!?()]')~=nil end
    while offset<=#source do
        local first,last,identity
        for _,name in ipairs(candidates) do
            local start=offset
            while true do
                local a,b=source:find(name,start,true)
                if not a then break end
                local palette,covered={},0
                for _,slice in ipairs(slices) do
                    local lo,hi=math.max(a,slice.first),math.min(b,slice.last)
                    if lo<=hi then
                        palette[#palette+1]={text=source:sub(lo,hi),color=slice.color}
                        covered=covered+hi-lo+1
                    end
                end
                if covered==#name and boundary(source:sub(a-1,a-1)) and boundary(source:sub(b+1,b+1)) then
                    if not first or a<first or a==first and b>last then
                        first,last,identity=a,b,{text=name,color=palette[1].color,parts=palette}
                    end
                    break
                end
                start=a+1
            end
        end
        if not first then output[#output+1]=source:sub(offset);break end
        if #literals+#paragraph.links>=8 then return end
        output[#output+1]=source:sub(offset,first-1)
        output[#output+1]='{{DFT'..#literals..'}}'
        literals[#literals+1]=identity;offset=last+1
    end
    if #literals>0 then paragraph.literals=literals;paragraph.local_source=table.concat(output) end
end

function context_names(page,vs)
    if page.mode~=df.legends_mode_type.ENTITIES then return end
    local names,seen={},{}
    local function add(name)
        if safe_name(name) and not seen[name] then
            if #names>=128 then error('Legends native-name budget exceeded') end
            names[#names+1]=name;seen[name]=true
        end
    end
    local function name(object)
        return object and dfhack.df2utf(dfhack.translation.translateName(object.name,true))
    end
    local function bounded(values,limit)
        if values and #values>limit then error('Legends occasion reference budget exceeded') end
        return values or {}
    end
    local world=df.global.world and df.global.world.world_data
    local world_name=name(world)
    add(world_name)
    -- Native introductory prose lowercases only the definite article.
    if world_name and world_name:sub(1,4)=='The ' then add('the '..world_name:sub(5)) end
    local entity=df.historical_entity.find(vs.entities[page.index])
    local info=entity and entity.occasion_info
    local forms,buildings,commemorated={},{},{}
    local function form(kind,id)
        local class=({POETRY_RECITAL=df.poetic_form,MUSICAL_PERFORMANCE=df.musical_form,
            DANCE_PERFORMANCE=df.dance_form})[kind]
        if not class or id<0 then return end
        local key=kind..':'..id
        if forms[key]==nil then forms[key]=name(class.find(id)) or false end
        add(forms[key])
    end
    local function building(site_id,id)
        if id<0 then return end
        if not buildings[site_id] then
            local site=df.world_site.find(site_id)
            local values={}
            for _,b in ipairs(bounded(site and site.buildings,4096)) do values[b.id]=name(b) end
            buildings[site_id]=values
        end
        add(buildings[site_id][id])
    end
    for _,occasion in ipairs(bounded(info and info.occasions,64)) do
        add(name(occasion))
        if df.entity_occasion_purpose_type and
                df.entity_occasion_purpose_type[occasion.purpose]=='COMMEMORATE_EVENT' and
                not commemorated[occasion.purpose_id] then
            commemorated[occasion.purpose_id]=true
            local event=df.history_event.find(occasion.purpose_id)
            if event and df.history_event_add_hf_entity_linkst:is_instance(event) and
                    df.histfig_entity_link_type[event.link_type]=='POSITION' then
                add(name(df.historical_figure.find(event.histfig)))
                add(name(event.civ==entity.id and entity or df.historical_entity.find(event.civ)))
            end
        end
        for _,schedule in ipairs(bounded(occasion.schedule,64)) do
            local kind=df.occasion_schedule_type[schedule.type]
            form(kind,schedule.reference)
            if kind=='PROCESSION' then
                building(occasion.site,schedule.reference);building(occasion.site,schedule.reference2)
            end
            for _,feature in ipairs(bounded(schedule.features,64)) do
                form(df.occasion_schedule_feature[feature.feature],feature.reference)
            end
        end
    end
    return names
end

function capture(words, links, subject_id, subject_name, known_names)
    local paragraphs = {}
    local paragraph, source, local_source, last_link, last_literal
    local function finish()
        if paragraph then
            paragraph.source = table.concat(source, ' ')
            if #paragraph.literals>0 and #paragraph.literals<=8 then
                paragraph.local_source=table.concat(local_source,' ')
                for i,literal in ipairs(paragraph.literals) do
                    if literal.text:sub(-1)==',' then
                        literal.text=literal.text:sub(1,-2)
                        local final=literal.parts[#literal.parts]
                        final.text=final.text:sub(1,-2)
                        local token='{{DFT'..(i-1)..'}}'
                        paragraph.local_source=paragraph.local_source:gsub(token,token..',')
                    end
                end
            end
            if #paragraphs==0 then protect_subject(paragraph,subject_name) end
            protect_names(paragraph,known_names)
            paragraphs[#paragraphs+1] = paragraph
        end
        paragraph, source, local_source, last_link, last_literal = nil, nil, nil, nil, nil
    end
    for index=0,#words-1 do
        local word = words[index]
        local value = dfhack.df2utf(word.str)
        if value == '' then
            finish()
        else
            if not paragraph then
                paragraph = {subject_id=subject_id, links={}, request_links={}, literals={}, original_parts={},native_y=word.py}
                source,local_source = {},{}
            end
            local original_link
            -- Native type -1 is a literal relationship label, not a click target.
            -- Keep unsupported records out of the translation link protocol.
            if word.link_index >= 0 and clickable(links[word.link_index]) then
                if last_link ~= word.link_index then
                    local native = links[word.link_index]
                    local link = {id=native.id, type=native.type, px=word.px, py=word.py,
                        native_index=word.link_index, color=link_colors[native.type] or color(word)}
                    paragraph.links[#paragraph.links+1] = link
                    paragraph.request_links[#paragraph.request_links+1] = {
                        id=native.id, type=native.type, text=value}
                    source[#source+1] = '{{DFL'..(#paragraph.links-1)..'}}'
                    local_source[#local_source+1]=source[#source]
                else
                    local request = paragraph.request_links[#paragraph.request_links]
                    request.text = request.text .. ' ' .. value
                end
                last_link = word.link_index
                last_literal=nil
                original_link=paragraph.links[#paragraph.links]
            else
                source[#source+1] = value
                last_link = nil
                local native=word.link_index>=0 and links[word.link_index] or nil
                if native and native.type==-1 then
                    local literal
                    if last_literal~=word.link_index then
                        literal={text=value,color=color(word),parts={}}
                        paragraph.literals[#paragraph.literals+1]=literal
                        local_source[#local_source+1]='{{DFT'..(#paragraph.literals-1)..'}}'
                    else
                        literal=paragraph.literals[#paragraph.literals]
                        literal.text=literal.text..' '..value
                    end
                    local palette=color(word)
                    local previous=literal.parts[#literal.parts]
                    if previous and previous.color==palette then
                        previous.text=previous.text..' '..value
                    else
                        literal.parts[#literal.parts+1]={text=(#literal.parts>0 and ' ' or '')..value,color=palette}
                    end
                    last_literal=word.link_index
                else
                    local_source[#local_source+1]=value
                    last_literal=nil
                end
            end
            local original=paragraph.original_parts
            local previous=original[#original]
            local palette=color(word)
            if previous and previous.color==palette and previous.link==original_link then
                previous.text=previous.text..' '..value
            else
                original[#original+1]={text=(#original>0 and ' ' or '')..value,
                    color=palette,link=original_link}
            end
        end
    end
    finish()
    return paragraphs
end

function parts(paragraph, result)
    local output, offset = {}, 1
    while true do
        local first,last,kind,index = result.translation:find('{{DF([LT])(%d+)}}', offset)
        local stop = first and first-1 or #result.translation
        if stop >= offset then
            output[#output+1] = {text=result.translation:sub(offset,stop),color=7}
        end
        if not first then break end
        index = tonumber(index)+1
        if kind=='L' then
            local link = assert(paragraph.links[index], 'Invalid translated narrative link')
            output[#output+1] = {text=assert(result.links[index].translation),color=link.color,link=link}
        else
            local literal=assert(paragraph.literals[index],'Invalid local narrative text slot')
            assert(result.literals[index].translation==literal.text,'Local name text must remain literal')
            for _,part in ipairs(literal.parts) do
                output[#output+1]={text=part.text,color=part.color}
            end
        end
        offset = last+1
    end
    return output
end

function layout(paragraphs, width, wide_cells)
    wide_cells = wide_cells or 2
    local chunks, y = {}, 0
    for _,paragraph in ipairs(paragraphs) do
        paragraph.y = y
        local x = 0
        for _,part in ipairs(paragraph.parts or {{text='翻譯中',color=7}}) do
            local text, cells, start = '', 0, x
            local function flush()
                if text ~= '' then
                    chunks[#chunks+1] = {x=start,y=y,text=text,width=cells,
                        color=part.color,link=part.link,paragraph=paragraph}
                end
                text, cells, start = '', 0, x
            end
            for _,code in utf8.codes(part.text) do
                local size = code < 256 and 1 or wide_cells
                if x+size > width then
                    flush()
                    y, x, start = y+1, 0, 0
                end
                if x > 0 or code ~= 32 then
                    text = text .. utf8.char(code)
                    x, cells = x+size, cells+size
                end
            end
            flush()
            x = math.ceil(x)
        end
        paragraph.last_y = y
        y = y+2
    end
    return chunks, math.max(0,y-1)
end

local function restore(active)
    if not active or not active.hidden then return end
    local vs=dfhack.gui.getCurViewscreen()
    if df.viewscreen_legendsst:is_instance(vs) then
        for index=0,#vs.page-1 do
            local page=vs.page[index]
            if page == active.page then page.scroll_position_text=active.native_scroll; break end
        end
    end
    active.hidden=false
end

local function hide(active)
    if active.hidden then return end
    active.native_scroll=active.page.scroll_position_text
    active.hidden=true
    active.page.scroll_position_text=active.page.text_box.max_y+active.height+1
end

function suspend()
    restore(state)
    state=nil
end

function dispatching()
    return native_dispatch
end

local function active_state(runtime)
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if world ~= current_world then current_world, states, state = world, {}, nil end
    if not world then state=nil; return end
    local vs = dfhack.gui.getCurViewscreen()
    if not df.viewscreen_legendsst:is_instance(vs) then restore(state); state=nil; states={}; return end
    local page = vs.page[vs.active_page_index]
    if state and state.page ~= page then restore(state); state=nil end
    if not state then
        -- Native tabs can be deleted and their address reused. Retain only
        -- still-open tab captures, with no per-frame scan on a stable page.
        local live={}
        for index=0,#vs.page-1 do live[tostring(vs.page[index])]=true end
        for key in pairs(states) do if not live[key] then states[key]=nil end end
    end
    if not page or page.index < 0 then restore(state); state=nil; return end
    local width,height = dfhack.screen.getWindowSize()
    if width < 40 or height < 15 then restore(state); state=nil; return end
    -- The legacy reader temporarily replaces native words with display aliases.
    -- Restore those exact words before the rich reader captures link spans.
    if runtime and runtime.restore_legends then runtime.restore_legends(page) end
    local key = tostring(page)
    state = states[key]
    if not state or state.word_count ~= #page.text_box.word or
            state.mode ~= page.mode or state.index ~= page.index then
        restore(state)
        local subject = page.mode == df.legends_mode_type.HFS and vs.histfigs[page.index] or nil
        local name
        if subject and df.historical_figure and df.historical_figure.find then
            -- Resolve the authoritative alias once per page capture, never per
            -- frame or paragraph lookup. A failed read leaves native prose.
            local ok,value=pcall(function()
                local figure=df.historical_figure.find(subject)
                return figure and dfhack.df2utf(dfhack.translation.translateName(figure.name,true))
            end)
            if ok then name=value
            else dfhack.printerr('df-local-zh: unable to read Legends subject name: '..tostring(value)) end
        end
        local known_names
        local ok,value=pcall(context_names,page,vs)
        if ok then known_names=value
        else dfhack.printerr('df-local-zh: unable to read Legends occasion names: '..tostring(value)) end
        state = {page=page, mode=page.mode,index=page.index,word_count=#page.text_box.word,
            paragraphs=capture(page.text_box.word,page.text_box.link,subject,name,known_names),scroll=0,dirty=true}
        states[key] = state
    end
    if state.width ~= width-7 then state.width=width-7; state.dirty=true end
    local renderer=df.global.enabler.renderer
    local wide_cells=renderer.dispy/renderer.dispx
    if state.wide_cells ~= wide_cells then state.wide_cells=wide_cells; state.dirty=true end
    state.height=height-11
    hide(state)
    return state,vs
end

local function relayout(runtime)
    if not state.dirty then return end
    local anchor, relative
    for _,paragraph in ipairs(state.paragraphs) do
        if paragraph.y and paragraph.y <= state.scroll then
            anchor, relative = paragraph, state.scroll-paragraph.y
        end
    end
    state.chunks,state.total=layout(state.paragraphs,state.width,state.wide_cells)
    if anchor then state.scroll=anchor.y+math.min(relative,anchor.last_y-anchor.y) end
    state.scroll=math.max(0,math.min(state.scroll,math.max(0,state.total-state.height)))
    state.dirty=false
end

function poll(runtime)
    if not active_state(runtime) then
        if runtime.set_visible then runtime.set_visible({}) end
        return false
    end
    local mode=runtime.narrative_mode and runtime.narrative_mode()
    if mode~=state.translation_mode then
        for _,paragraph in ipairs(state.paragraphs) do
            paragraph.parts,paragraph.retry_at=nil,nil
        end
        state.translation_mode=mode;state.dirty=true
    end
    relayout(runtime)
    local visible={}
    if runtime.paragraph_visibility_id then
        for _,paragraph in ipairs(state.paragraphs) do
            if paragraph.last_y >= state.scroll and
                    paragraph.y <= state.scroll+state.height-1 then
                visible[#visible+1]=runtime.paragraph_visibility_id(paragraph.source,
                    paragraph.request_links,paragraph.subject_id)
            end
        end
    end
    if runtime.set_visible then runtime.set_visible(visible) end
    local attempted=0
    local now=dfhack.getTickCount()
    for _,paragraph in ipairs(state.paragraphs) do
        if paragraph.last_y >= state.scroll and paragraph.y <= state.scroll+state.height-1 and
                (not paragraph.parts or paragraph.retry_at and now>=paragraph.retry_at) then
            local result,status=runtime.paragraph_lookup(paragraph.source,paragraph.request_links,paragraph.subject_id,
                paragraph.local_source,paragraph.literals)
            if result then
                paragraph.parts=result.native_fallback and paragraph.original_parts or parts(paragraph,result)
                paragraph.retry_at=nil
                state.dirty=true
            elseif status=='invalid' or status=='failed' then
                -- Protocol limits must never leave an unreadable pending page.
                -- Retry transient I/O, retaining real native spans and targets.
                paragraph.parts=paragraph.original_parts
                paragraph.retry_at=status=='failed' and now+1000 or nil
                state.dirty=true
            elseif paragraph.retry_at then
                paragraph.retry_at=now+1000
            end
            attempted=attempted+1
            if attempted >= 4 then break end
        end
    end
    relayout(runtime)
    return true
end

function view(runtime)
    if not active_state(runtime) then return end
    relayout(runtime)
    return state
end

function scroll(delta)
    if not active_state() then return false end
    state.scroll=math.max(0,math.min(state.scroll+delta,math.max(0,(state.total or 0)-state.height)))
    return true
end

function click(link)
    local active,vs=active_state()
    if not active then return false end
    local target=active.page.text_box.link[link.native_index]
    if not target or target.id~=link.id or target.type~=link.type then return false end
    local word
    for index=0,#active.page.text_box.word-1 do
        local candidate=active.page.text_box.word[index]
        if candidate.link_index==link.native_index then word=candidate; break end
    end
    if not word then return false end
    local gps=df.global.gps
    local x,y,old_scroll=gps.mouse_x,gps.mouse_y,active.page.scroll_position_text
    active.page.scroll_position_text=math.max(0,math.min(word.py, active.page.text_box.max_y))
    gps.mouse_x=word.px+2
    gps.mouse_y=9+word.py-active.page.scroll_position_text
    native_dispatch=true
    local ok,err=pcall(require('gui').simulateInput,vs,'_MOUSE_L')
    native_dispatch=false
    active.page.scroll_position_text=old_scroll
    gps.mouse_x,gps.mouse_y=x,y
    if not ok then error(err) end
    return true
end
