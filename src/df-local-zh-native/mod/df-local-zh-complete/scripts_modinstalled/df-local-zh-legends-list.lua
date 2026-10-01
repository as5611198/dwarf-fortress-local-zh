--@module=true

local gui = require('gui')
local current_world
local captions = {}
local rows = {}
local capture_failed = false

local groups = {
    HFS={values='histfigs',filtered='histfigs_filtered',kind='figure'},
    SITES={values='sites',filtered='sites_filtered',kind='site',class='world_site'},
    ARTIFACTS={values='artifacts',filtered='artifacts_filtered',kind='artifact',class='artifact_record'},
    BOOKS={values='codices',filtered='codices_filtered',kind='written_content',
        class='written_content',field='title'},
    SUBREGIONS={values='regions',filtered='regions_filtered',kind='region',class='world_region'},
    ENTITIES={values='entities',filtered='entities_filtered',kind='entity',class='historical_entity'},
    FEATURE_LAYERS={values='layers',filtered='layers_filtered',kind='layer',
        class='world_underground_region'},
}

local function group_for(mode)
    for name,group in pairs(groups) do
        if df.legends_mode_type[name] == mode then return group end
    end
end

local function native_name(group,id)
    local ok,object=pcall(function() return df[group.class].find(id) end)
    if not ok or not object then return end
    local named,value=pcall(function() return object[group.field or 'name'] end)
    if not named or not value then return end
    if group.field == 'title' then
        local title=dfhack.df2utf(value)
        return title,utf8.len(title)
    end
    local translated,name=pcall(dfhack.translation.translateName,value,false)
    if translated and name then
        name=dfhack.df2utf(name)
        local original=name
        local ok,english=pcall(dfhack.translation.translateName,value,true)
        if ok and english and english~='' then
            original=name..', "'..dfhack.df2utf(english)..'"'
        end
        return name,utf8.len(original)
    end
end

local function load_captions(world)
    local ok,paths=pcall(reqscript,'df-local-zh-paths')
    if not ok then return end
    local json=require('json')
    for _,name in ipairs({'runtime-requests.jsonl','runtime-responses.jsonl'}) do
        local file=io.open(paths.broker_data()..'/'..name,'rb')
        if file then
            local content=file:read('*a');file:close()
            for line in content:gmatch('(.-)\n') do
                local decoded,row=pcall(json.decode,line)
                if decoded and type(row)=='table' and row.world==world and type(row.figureId)=='number' and
                        type(row.text)=='string' and #row.text<=8000 and row.text:match('^.+, ".+", .+$') then
                    captions[row.figureId]=row.text
                end
            end
        end
    end
end

local function list_page(vs)
    if not vs or not df.viewscreen_legendsst:is_instance(vs) then return end
    local page = vs.page[vs.active_page_index]
    if page and page.index == -1 and group_for(page.mode) then return page,group_for(page.mode) end
end

function visible_rows()
    if not dfhack.isWorldLoaded() or dfhack.getSavePath() ~= current_world or
            not list_page(dfhack.gui.getCurViewscreen()) then return {} end
    return rows
end

local function capture(vs, row)
    local gps = df.global.gps
    local mouse_x, mouse_y = gps.mouse_x, gps.mouse_y
    local original_page = vs.active_page_index
    local original_count = #vs.page
    local source
    local ok, err = pcall(function()
        gps.mouse_x, gps.mouse_y = 10, row.y
        gui.simulateInput(vs, '_MOUSE_L')
        local detail = vs.page[vs.active_page_index]
        if #vs.page == original_count + 1 and detail and detail.index == row.index then
            source = dfhack.df2utf(detail.header)
        end
        if #vs.page == original_count + 1 then
            gps.mouse_x, gps.mouse_y = 118, 5
            gui.simulateInput(vs, '_MOUSE_L')
        end
        assert(vs.active_page_index == original_page and #vs.page == original_count,
            'Could not restore Legends list after caption capture')
    end)
    gps.mouse_x, gps.mouse_y = mouse_x, mouse_y
    if not ok then capture_failed = true; error(err) end
    return source
end

function poll(runtime)
    local world = dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if world ~= current_world then
        current_world, captions, rows, capture_failed = world, {}, {}, false
        if world then load_captions(world) end
    end
    if not world then return end
    local vs = dfhack.gui.getCurViewscreen()
    local page,group = list_page(vs)
    if not page then
        if runtime.set_visible then runtime.set_visible({}) end
        return
    end
    local width, height = dfhack.screen.getWindowSize()
    rows = {}
    if width < 120 then
        if runtime.set_visible then runtime.set_visible({}) end
        return
    end
    local captured = false
    local values,filtered=vs[group.values],vs[group.filtered]
    for row_number=0, math.floor((height - 16) / 3) do
        local position = page.scroll_position_list + row_number
        if position >= #filtered then break end
        local index = filtered[position]
        local id = values[index]
        local row = {id=id, kind=group.kind,index=index,y=13+row_number*3,width=width-26}
        local source,columns
        if group.kind=='figure' then source=captions[id]
        else source,columns=native_name(group,id) end
        -- Capture one exact game caption per tick; never guess race/title formatting.
        if group.kind == 'figure' and not source and not captured and not capture_failed and #vs.page == 2 then
            source = capture(vs, row)
            captions[id] = source
            captured = true
        end
        row.source = source
        row.caption_columns=columns or (source and utf8.len(source))
        rows[#rows+1] = row
    end
    local visible={}
    if runtime.visibility_id then
        for _,row in ipairs(rows) do
            if row.source then
                visible[#visible+1]=runtime.visibility_id(row.source,row.id,
                    row.kind ~= 'figure' and row.kind or nil)
            end
        end
    end
    if runtime.set_visible then runtime.set_visible(visible) end
    for _,row in ipairs(rows) do
        row.key = row.source and runtime.short_lookup(row.source,true,nil,row.width,row.id,
            row.kind ~= 'figure' and row.kind or nil) or nil
        if not row.key then row.key = runtime.pending_key() end
    end
end
