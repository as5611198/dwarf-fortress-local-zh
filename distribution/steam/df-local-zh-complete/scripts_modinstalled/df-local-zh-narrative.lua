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

function capture(words, links, subject_id)
    local paragraphs = {}
    local paragraph, source, last_link
    local function finish()
        if paragraph then
            paragraph.source = table.concat(source, ' ')
            paragraphs[#paragraphs+1] = paragraph
        end
        paragraph, source, last_link = nil, nil, nil
    end
    for index=0,#words-1 do
        local word = words[index]
        local value = dfhack.df2utf(word.str)
        if value == '' then
            finish()
        else
            if not paragraph then
                paragraph = {subject_id=subject_id, links={}, request_links={}, native_y=word.py}
                source = {}
            end
            if word.link_index >= 0 and links[word.link_index] then
                if last_link ~= word.link_index then
                    local native = links[word.link_index]
                    local link = {id=native.id, type=native.type, px=word.px, py=word.py,
                        native_index=word.link_index, color=link_colors[native.type] or color(word)}
                    paragraph.links[#paragraph.links+1] = link
                    paragraph.request_links[#paragraph.request_links+1] = {
                        id=native.id, type=native.type, text=value}
                    source[#source+1] = '{{DFL'..(#paragraph.links-1)..'}}'
                else
                    local request = paragraph.request_links[#paragraph.request_links]
                    request.text = request.text .. ' ' .. value
                end
                last_link = word.link_index
            else
                source[#source+1] = value
                last_link = nil
            end
        end
    end
    finish()
    return paragraphs
end

function parts(paragraph, result)
    local output, offset = {}, 1
    while true do
        local first,last,index = result.translation:find('{{DFL(%d+)}}', offset)
        local stop = first and first-1 or #result.translation
        if stop >= offset then
            output[#output+1] = {text=result.translation:sub(offset,stop),color=7}
        end
        if not first then break end
        index = tonumber(index)+1
        local link = assert(paragraph.links[index], 'Invalid translated narrative link')
        output[#output+1] = {text=assert(result.links[index].translation),color=link.color,link=link}
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

local function active_state()
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if world ~= current_world then current_world, states, state = world, {}, nil end
    if not world then state=nil; return end
    local vs = dfhack.gui.getCurViewscreen()
    if not df.viewscreen_legendsst:is_instance(vs) then restore(state); state=nil; return end
    local page = vs.page[vs.active_page_index]
    if state and state.page ~= page then restore(state); state=nil end
    if not page or page.index < 0 then restore(state); state=nil; return end
    local width,height = dfhack.screen.getWindowSize()
    if width < 40 or height < 15 then restore(state); state=nil; return end
    local key = tostring(page)
    state = states[key]
    if not state or state.word_count ~= #page.text_box.word or
            state.mode ~= page.mode or state.index ~= page.index then
        restore(state)
        local subject = page.mode == df.legends_mode_type.HFS and vs.histfigs[page.index] or nil
        state = {page=page, mode=page.mode,index=page.index,word_count=#page.text_box.word,
            paragraphs=capture(page.text_box.word,page.text_box.link,subject),scroll=0,dirty=true}
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
    if not active_state() then
        if runtime.set_visible then runtime.set_visible({}) end
        return false
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
    for _,paragraph in ipairs(state.paragraphs) do
        if paragraph.last_y >= state.scroll and paragraph.y <= state.scroll+state.height-1 and
                not paragraph.parts then
            local result=runtime.paragraph_lookup(paragraph.source,paragraph.request_links,paragraph.subject_id)
            if result then paragraph.parts=parts(paragraph,result); state.dirty=true end
            attempted=attempted+1
            if attempted >= 4 then break end
        end
    end
    relayout(runtime)
    return true
end

function view(runtime)
    if not active_state() then return end
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
