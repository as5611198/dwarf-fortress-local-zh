--@module=true

local function text(word)
    return dfhack.df2utf(word.str)
end

local function is_runtime_key(source)
    local bare=source:match('^L(%w%w%w%w%w%w)%s*$')
    return source:match('^L[%w][%w][%w]_+%s*$') or
        source:match('^L%w%w%w%w%w%w_+%s*$') or
        (bare and bare:match('%d')) or
        source:match('^P_____%s*$')
end

local function source_needs_translation(source)
    return source:match('[A-Za-z]') and not is_runtime_key(source)
end

local function is_date_fragment(source)
    return source:match('^%a%.%s+%d+$') ~= nil
end

local function span(words, first, last)
    local parts = {}
    for index = first, last do parts[#parts + 1] = text(words[index]) end
    local final = words[last]
    return {
        first = first,
        last = last,
        px = words[first].px,
        py = words[first].py,
        link_index = words[first].link_index,
        source = table.concat(parts, ' '),
        width = final.px + #final.str - words[first].px,
    }
end

local function restore_source(group, previous)
    if not is_runtime_key(group.source) then return group end
    for _, old in ipairs(previous or {}) do
        if old.first == group.first and old.py == group.py and
                old.link_index == group.link_index then
            group.source = old.source
            group.width = old.width
            group.px = old.px
            break
        end
    end
    return group
end

function collect(words, previous)
    local groups = {}
    local covered = {}
    local index = 0
    while index < #words do
        local first = words[index]
        local preceding = index > 0 and words[index - 1] or nil
        if first.px == 0 and first.py >= 0 and first.link_index >= 0 and
                (not preceding or preceding.link_index ~= first.link_index) then
            local stop = index + 1
            while stop < #words and words[stop].py == first.py and
                    words[stop].link_index == first.link_index do
                stop = stop + 1
            end
            local link = restore_source(span(words, index, stop - 1), previous)
            if source_needs_translation(link.source) then
                groups[#groups + 1] = link
                covered[link.first] = true
            end
            index = stop

            if index < #words and words[index].py == first.py and
                    words[index].link_index < 0 then
                local role_start = index
                while index < #words and words[index].py == first.py and
                        words[index].link_index < 0 do
                    index = index + 1
                end
                local role = restore_source(span(words, role_start, index - 1), previous)
                if role.source:sub(1, 1) == '(' and role.source:sub(-1) == ')' then
                    groups[#groups + 1] = role
                    covered[role.first] = true
                end
            end
        else
            index = index + 1
        end
    end

    local related = false
    index = 0
    while index < #words do
        local first = words[index]
        if first.px < 0 or first.py < 0 then
            index = index + 1
        else
            local stop = index + 1
            while stop < #words and words[stop].py == first.py and
                    words[stop].link_index == first.link_index do
                stop = stop + 1
            end
            local group = restore_source(span(words, index, stop - 1), previous)
            if group.source == 'Related Entities' and first.px == 0 then related = true end
            if related and not covered[index] and source_needs_translation(group.source) and
                    not is_date_fragment(group.source) then
                groups[#groups + 1] = group
            end
            index = stop
        end
    end
    return groups
end

local current_world
local pages = {}
local frame = 0
local headers = {}

local function matches(words, group, saved)
    if not saved or group.last >= #words then return false end
    for index=group.first,group.last do
        local word,old=words[index],saved[index]
        if word.str~=old.str or word.px~=old.px or word.py~=old.py or
                word.link_index~=old.link_index then return false end
    end
    return true
end

local function snapshot(words,group)
    local saved={}
    for index=group.first,group.last do
        local word=words[index]
        saved[index]={str=word.str,px=word.px,py=word.py,link_index=word.link_index}
    end
    return saved
end

local function restore_group(words,group)
    if group.written and matches(words,group,group.written) then
        for index=group.first,group.last do
            words[index].str=group.original[index].str
            words[index].px=group.original[index].px
        end
    end
    group.written=nil
end

function restore_native(detail)
    if current_world~=(dfhack.isWorldLoaded() and dfhack.getSavePath() or nil) then return end
    local id=detail.mode..':'..detail.index
    local page=pages[id]
    if not page or page.detail~=detail then return end
    local words=detail.text_box.word
    if page.word_count==#words then
        for _,group in ipairs(page.groups) do restore_group(words,group) end
    end
    pages[id]=nil
end

function poll(runtime)
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if world ~= current_world then
        current_world = world
        pages = {}
        headers = {}
    end
    if not world then
        if runtime.set_visible then runtime.set_visible({}) end
        return
    end

    local vs = dfhack.gui.getCurViewscreen()
    if not df.viewscreen_legendsst:is_instance(vs) then
        if runtime.set_visible then runtime.set_visible({}) end
        return
    end
    local active = vs.page[vs.active_page_index]
    if active and active.index == -1 then
        reqscript('df-local-zh-legends-list').poll(runtime)
        return
    end
    if vs.active_page_index < 2 then
        if runtime.set_visible then runtime.set_visible({}) end
        return
    end

    local detail = vs.page[vs.active_page_index]
    local words = detail.text_box.word
    local page_id = detail.mode .. ':' .. detail.index
    local header = headers[page_id]
    local current_header = dfhack.df2utf(detail.header)
    if not header or (current_header ~= header.key and current_header ~= header.source) then
        header = {source = current_header,raw=detail.header}
        headers[page_id] = header
    end
    if source_needs_translation(header.source) then
        local figure_id = detail.mode == df.legends_mode_type.HFS and
            vs.histfigs[detail.index] or nil
        local key = runtime.short_lookup(header.source, true, 'CENTER', nil, figure_id)
        if key then detail.header = key; header.key = key
        elseif current_header==header.key then detail.header=header.raw;header.key=nil end
    end
    if runtime.paragraph_lookup then
        local narrative=reqscript('df-local-zh-narrative')
        if require('plugins.overlay').isOverlayEnabled('df-local-zh-narrative-overlay.narratives') then
            restore_native(detail)
            if narrative.poll(runtime) then return end
        else narrative.suspend() end
    end
    if runtime.set_visible then runtime.set_visible({}) end
    local page = pages[page_id]
    if page and (page.detail~=detail or page.word_count~=#words) then
        page = nil
    end
    frame=frame+1
    local columns=dfhack.screen.getWindowSize()
    local mode=runtime.narrative_mode and runtime.narrative_mode()
    if page and page.applied and page.mode==mode and page.columns==columns and frame%20~=0 then return end
    if page then
        for _,group in ipairs(page.groups) do
            if not matches(words,group,group.written or group.original) then
                restore_native(detail);page=nil;break
            end
        end
    end
    if not page then
        -- Retain snapshots only for open tabs, never for every entity visited.
        local live={}
        for index=0,#vs.page-1 do
            local tab=vs.page[index]
            live[tab.mode..':'..tab.index]=true
        end
        for id in pairs(pages) do if not live[id] then pages[id]=nil end end
        for id in pairs(headers) do if not live[id] then headers[id]=nil end end
        local groups = collect(words)
        if #groups == 0 then return end
        for _,group in ipairs(groups) do group.original=snapshot(words,group) end
        page = {detail=detail,word_count = #words, groups = groups, applied = false}
        pages[page_id] = page
    end

    local row_end = {}
    for _, group in ipairs(page.groups) do
        restore_group(words,group)
        local key = runtime.short_lookup(group.source, true)
        local px = math.max(group.px, row_end[group.py] or 0)
        if key and px + #key > columns - 4 then key=nil end
        if key then
            words[group.first].px = px
            row_end[group.py] = px + #key + 1
        else
            -- Preserve the full native span, including its clickable identity.
            for index=group.first,group.last do
                words[index].px=group.original[index].px+px-group.px
            end
            row_end[group.py]=px+group.width+1
        end
        if key and dfhack.df2utf(words[group.first].str) ~= key then
            words[group.first].str = key
            for index = group.first + 1, group.last do words[index].str = '' end
        end
        group.written=snapshot(words,group)
    end
    page.applied = true
    page.mode=mode;page.columns=columns
end
