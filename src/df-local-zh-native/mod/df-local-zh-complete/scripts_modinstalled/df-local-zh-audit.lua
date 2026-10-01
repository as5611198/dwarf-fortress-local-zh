--@module = true

local json = require('json')
local repeatutil = require('repeat-util')
local watch_name = 'df-local-zh-audit'
local log_root = dfhack.getDFPath() .. '/_localization-work/text-audit'

function classify(text)
    text=text:gsub('%[C:%d+:%d+:%d+%]',''):gsub('%[P%]',''):gsub('%[R%]','')
    local trimmed=text:match('^%s*(.-)%s*$')
    if trimmed=='P_____' or trimmed==utf8.char(0x7FFB,0x8B6F,0x4E2D) then
        return 'pending_translation'
    end
    -- Bare letter-only keys can also be real English words. Keep them in the
    -- residual list until a renderer or alias registry proves their identity.
    local aliases,pending=false,false
    local remaining=text:gsub('[%w_]+',function(word)
        if word=='P_____' then pending=true;return '' end
        if (#word==7 and word:match('^L%w+$') and word:find('%d')) or
                word:match('^DFLIVE_[0-9a-f]+$') or word:match('^L%w%w%w%w%w%w_+$') or
                word:match('^L%w%w%w_+$') then aliases=true;return '' end
        return word
    end)
    if remaining:match('[A-Za-z]') then return 'latin_residual' end
    if aliases then return 'runtime_alias_unverified' end
    if pending then return 'pending_translation' end
    local found = false
    local valid = pcall(function()
        for _, code in utf8.codes(text) do
            if (code >= 0x3400 and code <= 0x9FFF) or
                    (code >= 0xF900 and code <= 0xFAFF) or
                    (code >= 0x20000 and code <= 0x323AF) then found = true end
        end
    end)
    if not valid then return 'encoding_unverified' end
    return found and 'cjk_only' or 'nonlinguistic'
end

function summarize(rows)
    local s = {strings=0, assessable=0, cjk_only=0, latin_residual=0,
        pending=0, unverified_aliases=0, encoding_unverified=0, unique_latin_strings=0}
    local unique = {}
    for _, row in ipairs(rows) do
        s.strings = s.strings + 1
        local c = row.classification
        if c == 'cjk_only' or c == 'latin_residual' or c == 'pending_translation' then
            s.assessable = s.assessable + 1
        end
        if c == 'cjk_only' then s.cjk_only = s.cjk_only + 1
        elseif c == 'latin_residual' then
            s.latin_residual = s.latin_residual + 1
            if not unique[row.text] then
                unique[row.text] = true
                s.unique_latin_strings = s.unique_latin_strings + 1
            end
        elseif c == 'pending_translation' then s.pending = s.pending + 1
        elseif c == 'runtime_alias_unverified' then s.unverified_aliases = s.unverified_aliases + 1
        elseif c == 'encoding_unverified' then s.encoding_unverified = s.encoding_unverified + 1 end
    end
    if s.assessable > 0 then s.memory_cjk_only_pct = 100 * s.cjk_only / s.assessable end
    return s
end

local function field(object, key)
    local ok, value = pcall(function() return object[key] end)
    return ok and value or nil
end

local function type_name(object)
    return tostring(field(object, '_type') or type(object))
end

local function decode(value)
    -- DF fields are CP437; retain valid UTF-8 CJK supplied by adapters as UTF-8.
    local ok, length = pcall(utf8.len, value)
    if ok and length and classify(value) == 'cjk_only' then return value, 'utf8' end
    if ok and length and value:find('[\228-\233]') then return value, 'utf8' end
    local converted, text = pcall(dfhack.df2utf, value)
    return converted and text or value, converted and 'df2utf' or 'unverified'
end

function scan()
    local started = dfhack.getTickCount()
    local screen = dfhack.gui.getCurViewscreen(true)
    local world_loaded, map_loaded = dfhack.isWorldLoaded(), dfhack.isMapLoaded()
    local fortress = map_loaded and dfhack.world.isFortressMode()
    local rows, objects, issues, visited = {}, {}, {}, {}
    local report_objects, citizen_objects = 0, 0
    local nodes, max_nodes, max_depth = 0, 20000, 12
    local function issue(path, reason)
        issues[#issues+1] = {field_id=path, reason=reason}
    end
    local function add(value, path, owner, category, object_id, internal)
        if type(value) ~= 'string' or value == '' then return end
        local text, encoding = decode(value)
        if category=='fortress_interface' then
            if path:find('raw_thought',1,true) or path:find('current_thought',1,true) or
                    path:find('.thought_box',1,true) then category='thought_prose'
            elseif path:find('thoughts_memory',1,true) or path:find('thoughts_raw_memory',1,true) then
                category='memory_prose'
            elseif path:find('personality_',1,true) then category='personality_prose'
            elseif path:find('unit_health_',1,true) then category='medical_prose'
            elseif path:find('kill_description',1,true) then category='kill_prose'
            elseif path:find('.raw_description',1,true) or path:find('.description.',1,true) then
                category='description_prose'
            end
        end
        rows[#rows+1] = {category=category, field_id=path, object_id=object_id or field(owner,'id'),
            object_address=tostring(owner),
            object_type=type_name(owner), field_type='string', text=text,
            classification=internal and 'internal_identifier' or classify(text), encoding=encoding}
    end
    local skipped = {parent=true, child=true, next=true, prev=true,
        children_by_name=true, custom_feed=true, custom_logic=true,
        custom_render=true, custom_activated=true}
    local function text_container(value)
        local t = type_name(value):lower()
        return t:find('text',1,true) or t:find('string',1,true) or
            t:find('widget',1,true) or t:find('interface',1,true) or
            t:find('view_sheets',1,true)
    end
    local walk
    walk = function(object, path, category, depth, object_id)
        if not object then return end
        if type(object) == 'string' then add(object,path,object,category,object_id); return end
        if type(object) ~= 'userdata' and type(object) ~= 'table' then return end
        if visited[object] then return end
        if depth > max_depth or nodes >= max_nodes then issue(path,'scan_limit'); return end
        visited[object], nodes = true, nodes + 1
        local owner_type = type_name(object):lower()
        local ok, err = pcall(function()
            for key, value in pairs(object) do
                local name = tostring(key)
                local next_path = type(key)=='number' and path .. '['..key..']' or path..'.'..name
                if not skipped[name] then
                    if type(value)=='string' then
                        local internal = (name=='name' and owner_type:find('widget',1,true)) or
                            name=='search_string' or name=='folder_name' or
                            name=='directory' or name=='filename' or
                            next_path:find('.arena_choice[',1,true)~=nil
                        add(value,next_path,object,category,object_id,internal)
                    elseif text_container(value) then
                        walk(value,next_path,category,depth+1,object_id)
                    end
                end
            end
        end)
        if not ok then issue(path,tostring(err)) end
    end
    walk(screen,'viewscreen','screen_structure',0)
    if fortress then
        walk(df.global.game.main_interface,'game.main_interface','fortress_interface',0)
        -- Knowledge lists retain work IDs instead of storing their displayed
        -- titles in the sheet. Resolve those IDs without modifying world names.
        local sheets=df.global.game.main_interface.view_sheets
        local kinds,ids=field(sheets,'unit_knowledge_type'),field(sheets,'unit_knowledge_id')
        local work_types={POETIC_FORM={type=df.poetic_form,path='poetic_forms'},
            MUSICAL_FORM={type=df.musical_form,path='musical_forms'},
            DANCE_FORM={type=df.dance_form,path='dance_forms'},
            WRITTEN_CONTENT={type=df.written_content,path='written_contents'}}
        if kinds and ids and df.view_sheet_unit_knowledge_type then
            for index=0,math.min(#kinds,#ids,256)-1 do
                local work=work_types[df.view_sheet_unit_knowledge_type[kinds[index]]]
                if work and work.type then
                    local ok,err=pcall(function()
                        local object=work.type.find(ids[index])
                        if not object then return end
                        local name=work.path=='written_contents' and 'title' or 'name'
                        local value=name=='title' and object.title or
                            dfhack.translation.translateName(object.name,true)
                        add(value,'world.'..work.path..'[id='..ids[index]..'].'..name,
                            object,'knowledge_title',ids[index])
                    end)
                    if not ok then issue('view_sheets.unit_knowledge_id['..index..']',tostring(err)) end
                end
            end
            if math.min(#kinds,#ids)>256 then issue('view_sheets.unit_knowledge_id','scan_limit') end
        end
        local reports = df.global.world.status.reports
        report_objects = #reports
        for index, report in ipairs(reports) do
            local category = report.flags.announcement and 'announcement' or 'combat_report'
            add(report.text,'world.status.reports['..index..'].text',report,category,report.id)
        end
        -- Emotions contain enum IDs, not stored narrative prose. Log their
        -- identity without treating English enum symbols as untranslated text.
        for _, unit in ipairs(df.global.world.units.active) do
            if dfhack.units.isCitizen(unit) then
                citizen_objects = citizen_objects + 1
                local soul = unit.status.current_soul
                if soul then
                    for index, emotion in ipairs(soul.personality.emotions) do
                        local path = 'unit['..unit.id..'].status.current_soul.personality.emotions['..index..']'
                        objects[#objects+1] = {category='thought_object',field_id=path,
                            object_type=type_name(emotion),object_id=unit.id,unit_id=unit.id,
                            emotion_id=emotion.type,emotion_type=df.emotion_type[emotion.type],
                            thought_id=emotion.thought,thought_type=df.unit_thought_type[emotion.thought],
                            subthought=emotion.subthought,year=emotion.year,year_tick=emotion.year_tick,
                            prose_available=false}
                        walk(emotion,path,'thought_object_strings',0,unit.id)
                    end
                end
            end
        end
    end
    local by_category, groups = {}, {}
    for _, row in ipairs(rows) do
        groups[row.category] = groups[row.category] or {}
        table.insert(groups[row.category],row)
    end
    for category, values in pairs(groups) do by_category[category]=summarize(values) end
    local summary = {timestamp=os.date('!%Y-%m-%dT%H:%M:%SZ'),
        df_version=dfhack.getDFVersion(),dfhack_version=dfhack.getDFHackVersion(),
        screen_type=type_name(screen),focus=dfhack.gui.getFocusStrings(screen),
        world=world_loaded and dfhack.getSavePath() or '',map_loaded=map_loaded,
        fortress_loaded=fortress,status=fortress and 'sampled' or 'fortress_not_loaded',
        metrics=summarize(rows),by_category=by_category,thought_objects=#objects,
        report_objects=report_objects,citizen_objects=citizen_objects,
        scan_nodes=nodes,scan_issues=#issues,elapsed_ms=dfhack.getTickCount()-started,
        rendered_coverage_verified=false,
        limitations={'Source-memory statistics only; native render hooks can keep English source strings.',
            'Hidden UI buffers may be present; empty fields and unvisited screens are not coverage.',
            'Runtime aliases are unverified; thought enum names are metadata, not prose.',
            'Latin residuals include proper names and shortcuts; review the local log.',
            'Thought prose is collected only when the game has generated its view_sheets buffers.'}}
    return {summary=summary,strings=rows,objects=objects,issues=issues}
end

local function write_json(path, value)
    local file = assert(io.open(path,'wb'))
    assert(file:write(json.encode(value,{pretty=true}), '\n'))
    assert(file:close())
end

function run(result)
    assert(dfhack.filesystem.mkdir_recursive(log_root),'Cannot create audit directory')
    result = result or scan()
    local stamp = os.date('!%Y%m%dT%H%M%SZ') .. '-' .. tostring(dfhack.getTickCount())
    local prefix = log_root..'/'..stamp
    local all = assert(io.open(prefix..'.jsonl','wb'))
    local residual = assert(io.open(prefix..'-english.log','wb'))
    for _, row in ipairs(result.strings) do
        local line = json.encode(row,{pretty=false}) .. '\n'
        assert(all:write(line))
        if row.classification=='latin_residual' or row.classification=='pending_translation' or
                row.classification=='runtime_alias_unverified' or row.classification=='encoding_unverified' then
            assert(residual:write(line))
        end
    end
    for _, row in ipairs(result.objects) do assert(all:write(json.encode(row,{pretty=false}),'\n')) end
    for _, row in ipairs(result.issues) do assert(all:write(json.encode(row,{pretty=false}),'\n')) end
    assert(all:close()); assert(residual:close())
    result.summary.full_log=prefix..'.jsonl'
    result.summary.english_log=prefix..'-english.log'
    write_json(prefix..'-summary.json',result.summary)
    write_json(log_root..'/latest-summary.json',result.summary)
    local m = result.summary.metrics
    print(('TEXT_AUDIT status=%s strings=%d latin=%d cjk=%d thoughts=%d issues=%d memory_cjk_pct=%s'):format(
        result.summary.status,m.strings,m.latin_residual,m.cjk_only,
        result.summary.thought_objects,result.summary.scan_issues,
        m.memory_cjk_only_pct and ('%.2f'):format(m.memory_cjk_only_pct) or 'N/A'))
    print('TEXT_AUDIT_LOG '..result.summary.english_log)
    return result.summary
end

if not dfhack_flags.module then
    local command = ({...})[1] or 'once'
    if command=='once' then run()
    elseif command=='watch' then
        local last_sample
        repeatutil.scheduleEvery(watch_name,600,'frames',function()
            if dfhack.isMapLoaded() and dfhack.world.isFortressMode() then
                local ok, err = pcall(function()
                    local result=scan()
                    local fingerprint=json.encode({world=result.summary.world,
                        screen=result.summary.screen_type,focus=result.summary.focus,
                        strings=result.strings,objects=result.objects,issues=result.issues},{pretty=false})
                    if fingerprint~=last_sample then
                        run(result)
                        last_sample=fingerprint
                    end
                end)
                if not ok then dfhack.printerr('TEXT_AUDIT_ERROR '..tostring(err)) end
            end
        end)
        print('TEXT_AUDIT_WATCH every 600 UI frames, fortress only; stop: df-local-zh-audit stop')
    elseif command=='stop' then repeatutil.cancel(watch_name); print('TEXT_AUDIT_WATCH stopped')
    else qerror('Usage: df-local-zh-audit [once|watch|stop]') end
end
