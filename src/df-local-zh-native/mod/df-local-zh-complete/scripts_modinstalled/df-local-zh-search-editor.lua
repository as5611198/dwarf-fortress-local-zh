--@module=true

function new(text,cursor,options)
    options=options or {}
    text=type(text)=='string' and utf8.len(text) and text or ''
    return {text=text,cursor=clamp(text,cursor),composition='',max_bytes=options.max_bytes or 512,max_chars=options.max_chars,multiline=options.multiline,secret=options.secret}
end

local function previous(text,cursor)
    if cursor<=1 then return 1 end
    return utf8.offset(text,-1,cursor) or 1
end
local function following(text,cursor)
    if cursor>#text then return #text+1 end
    return utf8.offset(text,2,cursor) or #text+1
end

function apply(state,action)
    if not utf8.len(state.text) then return false end
    state.cursor=clamp(state.text,state.cursor)
    local old=state.text
    local kind=action.kind
    if kind=='composition' then
        if type(action.text)~='string' or #action.text>4096 or not utf8.len(action.text) then return false end
        state.composition=action.text or ''
        state.composition_start=action.start or 0
        state.composition_length=action.length or 0
        return false
    end
    if kind=='cancel' then
        state.composition='';state.composition_start=0;state.composition_length=0
        return false
    end
    -- Preedit/candidate navigation belongs to Windows, never to the query.
    if state.composition~='' and kind~='text' then return false end
    if kind=='text' then
        local text=action.text or ''
        if state.multiline then text=text:gsub('\r\n?','\n') end
        text=text:gsub(state.multiline and '[%z\1-\8\11\12\14-\31\127]' or '[%z\1-\31\127]',' ')
        action={kind=kind,text=text}
        local size=state.selected and 0 or #state.text
        if not utf8.len(text) or size+#text>state.max_bytes or state.secret and text:find('[\127-\255]') then return false end
        if state.max_chars and (state.selected and 0 or utf8.len(state.text))+utf8.len(text)>state.max_chars then return false end
    end
    if kind=='select_all' then state.selected=true;return false end
    if kind=='home' then state.cursor=1;state.selected=nil;return false end
    if kind=='end' then state.cursor=#state.text+1;state.selected=nil;return false end
    if kind=='left' then state.cursor=previous(state.text,state.cursor);state.selected=nil;return false end
    if kind=='right' then state.cursor=following(state.text,state.cursor);state.selected=nil;return false end
    if state.selected and (kind=='text' or kind=='backspace' or kind=='delete') then
        state.text='';state.cursor=1;state.selected=nil
    elseif kind=='backspace' then
        local from=previous(state.text,state.cursor)
        state.text=state.text:sub(1,from-1)..state.text:sub(state.cursor);state.cursor=from
    elseif kind=='delete' then
        state.text=state.text:sub(1,state.cursor-1)..state.text:sub(following(state.text,state.cursor))
    end
    if kind=='text' then
        local text=(action.text or ''):gsub(state.multiline and '[%z\1-\8\11\12\14-\31]' or '[%z\1-\31]',' ')
        if utf8.len(text) and #state.text+#text<=state.max_bytes then
            state.text=state.text:sub(1,state.cursor-1)..text..state.text:sub(state.cursor)
            state.cursor=state.cursor+#text
        end
        state.composition=''
    end
    return old~=state.text
end

function clamp(text,cursor)
    cursor=math.max(1,math.min(cursor or #text+1,#text+1))
    while cursor<=#text and text:byte(cursor)>=128 and text:byte(cursor)<192 do cursor=cursor-1 end
    return cursor
end

-- Return an exclusive byte range on Unicode boundaries. DFHack mouse
-- selection endpoints are inclusive; Ctrl+A is owned by this editor.
function clipboard_range(state,selection_end)
    if state.secret or state.composition~='' or not utf8.len(state.text) then return nil end
    if state.selected then return state.text,1,#state.text+1 end
    if selection_end then
        local from,to=state.cursor,selection_end
        if from>to then from,to=to,from end
        from=clamp(state.text,from)
        to=clamp(state.text,to)
        to=to<=#state.text and (utf8.offset(state.text,2,to) or #state.text+1) or #state.text+1
        return state.text:sub(from,to-1),from,to
    end
    if not state.multiline then return state.text,1,#state.text+1 end
    local from=state.text:sub(1,state.cursor-1):match('.*\n()') or 1
    local newline=state.text:find('\n',state.cursor,true)
    local to=newline and newline+1 or #state.text+1
    local text=state.text:sub(from,to-1)
    if not newline then text=text..'\n' end
    return text,from,to
end

function cut_range(state,from,to)
    if not from or state.secret or state.composition~='' then return false end
    if not utf8.len(state.text) then return false end
    from,to=clamp(state.text,from),clamp(state.text,to)
    if to<from then from,to=to,from end
    local old=state.text
    state.text=old:sub(1,from-1)..old:sub(to)
    state.cursor=from;state.selected=nil
    return old~=state.text
end

function candidate_line(candidates)
    if not candidates or not candidates.active or type(candidates.items)~='table' or #candidates.items==0 then return nil end
    local labels={}
    for index,item in ipairs(candidates.items) do
        local selected=(candidates.first+index-1)==candidates.selected and '>' or ' '
        labels[#labels+1]=selected..tostring(index)..':'..tostring(item)
    end
    return '候選 '..table.concat(labels,' ')
end

-- Presentation only. Windows owns the page, selection, and navigation keys.
function candidate_box(candidates,width,height,anchor_x,anchor_y,columns)
    local line=candidate_line(candidates)
    if not line or width<8 or height<3 then return nil end
    local available=width-2
    if columns(line)>available or #line>512 then
        local selected=math.max(1,math.min(#candidates.items,candidates.selected-candidates.first+1))
        local first,last=selected,selected
        local function range_line(from,to)
            local rows={}
            for index=from,to do
                rows[#rows+1]=(index==selected and '>' or ' ')..index..':'..tostring(candidates.items[index])
            end
            return '候選 '..table.concat(rows,' ')
        end
        line=range_line(first,last)
        for _=1,#candidates.items do
            local from,to=math.max(1,first-1),math.min(#candidates.items,last+1)
            if from==first and to==last then break end
            local expanded=range_line(from,to)
            if columns(expanded)>available or #expanded>512 then break end
            first,last,line=from,to,expanded
        end
        while #line>0 and (columns(line)>available or #line>512) do
            line=line:sub(1,(utf8.offset(line,-1) or 1)-1)
        end
    end
    local box_width=math.min(width,columns(line)+2)
    local x=math.max(0,math.min(anchor_x,width-box_width))
    local y=anchor_y+1
    if y+3>height then y=anchor_y-3 end
    return {line=line,width=box_width,x=x,y=math.max(0,math.min(y,height-3))}
end
