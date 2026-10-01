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
        header = {source = current_header}
        headers[page_id] = header
    end
    if source_needs_translation(header.source) then
        local figure_id = detail.mode == df.legends_mode_type.HFS and
            vs.histfigs[detail.index] or nil
        local key = runtime.short_lookup(header.source, true, 'CENTER', nil, figure_id)
        if key then detail.header = key; header.key = key end
    end
    if runtime.paragraph_lookup then
        local narrative=reqscript('df-local-zh-narrative')
        if require('plugins.overlay').isOverlayEnabled('df-local-zh-narrative-overlay.narratives') then
            if narrative.poll(runtime) then return end
        else narrative.suspend() end
    end
    if runtime.set_visible then runtime.set_visible({}) end
    local page = pages[page_id]
    local previous_groups = page and page.groups
    if page and (#page.groups == 0 or page.word_count ~= #words or
            (page.applied and page.groups[1] and
            page.groups[1].last > page.groups[1].first and
            #words[page.groups[1].last].str > 0)) then
        page = nil
    end
    if not page then
        local groups = collect(words, previous_groups)
        if #groups == 0 then return end
        page = {word_count = #words, groups = groups, applied = false}
        pages[page_id] = page
    end

    frame = frame + 1
    if page.applied and frame % 20 ~= 0 then return end
    local row_end = {}
    local columns = dfhack.screen.getWindowSize()
    for _, group in ipairs(page.groups) do
        local key = runtime.short_lookup(group.source, true)
        local px = math.max(group.px, row_end[group.py] or 0)
        if not key or px + #key > columns - 4 then key = runtime.pending_key() end
        if key then
            words[group.first].px = px
            row_end[group.py] = px + #key + 1
        end
        if key and dfhack.df2utf(words[group.first].str) ~= key then
            words[group.first].str = key
            for index = group.first + 1, group.last do words[index].str = '' end
        end
    end
    page.applied = true
end
