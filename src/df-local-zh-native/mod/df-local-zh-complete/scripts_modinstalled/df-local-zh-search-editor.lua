--@module=true

function new(text,cursor)
    return {text=text or '',cursor=cursor or #(text or '')+1,composition=''}
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
    local old=state.text
    local kind=action.kind
    if kind=='composition' then state.composition=action.text or '';return false end
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
        local text=(action.text or ''):gsub('[%z\1-\31]',' ')
        if utf8.len(text) and #state.text+#text<=512 then
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
