--@ module=true

local json = require('json')
local native = reqscript('df-local-zh-core/native')
local mod = reqscript('df-local-zh-core/mod')
local modules={}
local function module(name)
    if not modules[name] then modules[name]=reqscript(name) end
    return modules[name]
end

local paths = reqscript('df-local-zh-paths')
local directory = paths.broker_data() .. '/'
local requests_path = directory .. 'runtime-requests.jsonl'
local responses_path = directory .. 'runtime-responses.jsonl'
local visibility_path = directory .. 'runtime-visible.json'
local one_row_path = directory .. 'runtime-one.csv'
local response_error
local JOURNAL_READ_BUDGET, JOURNAL_RECORD_LIMIT = 262144, 8*1024*1024
local function journal_state() return {offset=0,chunks={},bytes=0,discarding=false} end
local response_state, failure_state = journal_state(), journal_state()
local response_batch
local journal_errors, journal_warnings = {}, {}
-- DFHack's JSON decoder concatenates every decoded character, making long
-- strings quadratic. Decode strings in runs and substitute interned tokens;
-- keep the established decoder for JSON structure/numbers/booleans/null.
-- Equal decoded strings share a token so duplicate object keys still use the
-- decoder's last-value semantics, including differently escaped equal keys.
local function decode_journal(line)
    assert(utf8.len(line) and not line:find('\237[\160-\191][\128-\191]'),'invalid journal UTF-8')
    local strings, tokens, pieces = {}, {}, {}
    local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    local at,count=1,0
    while at<=#line do
        local opening=line:find('"',at,true)
        if not opening then pieces[#pieces+1]=line:sub(at);break end
        pieces[#pieces+1]=line:sub(at,opening-1)
        local chunks,cursor={},opening+1
        while true do
            local special=line:find('["\\%z\1-\31]',cursor)
            assert(special,'unterminated journal string')
            chunks[#chunks+1]=line:sub(cursor,special-1)
            local byte=line:byte(special)
            if byte==34 then
                local value=table.concat(chunks)
                local token=tokens[value]
                if not token then count=count+1;token='J'..count;tokens[value]=token;strings[token]=value end
                pieces[#pieces+1]='"'..token..'"'
                at=special+1;break
            end
            assert(byte==92,'unescaped journal control character')
            local escaped=line:sub(special+1,special+1)
            if escapes[escaped] then
                chunks[#chunks+1]=escapes[escaped];cursor=special+2
            else
                assert(escaped=='u','invalid journal escape')
                local hex=line:sub(special+2,special+5)
                assert(#hex==4 and hex:match('^%x%x%x%x$'),'invalid journal Unicode escape')
                local codepoint=tonumber(hex,16)
                cursor=special+6
                if codepoint>=0xD800 and codepoint<=0xDBFF then
                    local low=line:sub(cursor+2,cursor+5)
                    assert(line:sub(cursor,cursor+1)=='\\u' and #low==4 and low:match('^%x%x%x%x$'),'missing low surrogate')
                    low=tonumber(low,16)
                    assert(low>=0xDC00 and low<=0xDFFF,'invalid low surrogate')
                    codepoint=0x10000+(codepoint-0xD800)*0x400+low-0xDC00;cursor=cursor+6
                else
                    assert(codepoint<0xDC00 or codepoint>0xDFFF,'unpaired low surrogate')
                end
                chunks[#chunks+1]=utf8.char(codepoint)
            end
        end
    end
    local function restore(value,depth)
        assert(depth<=128,'journal nesting limit')
        if type(value)=='string' then return assert(strings[value],'unknown journal string token') end
        if type(value)~='table' then return value end
        local restored={}
        for key,entry in pairs(value) do restored[restore(key,depth+1)]=restore(entry,depth+1) end
        return setmetatable(restored,getmetatable(value))
    end
    return restore(json.decode(table.concat(pieces)),0)
end
local function journal_error(path,err)
    err=err and tostring(err) or nil
    if err and journal_errors[path]~=err then
        dfhack.printerr('df-local-zh-runtime journal '..path..': '..err)
    end
    journal_errors[path]=err
end
local function journal_warning(path,count)
    local warning=journal_warnings[path] or {count=0}
    warning.count=warning.count+count
    local now=os.time()
    if warning.count>0 and (not warning.at or now-warning.at>=5) then
        dfhack.printerr('df-local-zh-runtime journal '..path..': skipped '..warning.count..' invalid or oversized rows')
        warning.count,warning.at=0,now
    end
    journal_warnings[path]=warning
end

-- Stage each bounded read. The caller commits the state only after its rows
-- have been consumed, so native import failures never discard completed work.
local function read_journal(path,state)
    local opened,file,err,code=pcall(io.open,path,'rb')
    if not opened then journal_error(path,file);return end
    if not file then
        if code==2 or err==nil then
            journal_error(path,nil)
            return {rows={},state=journal_state(),reset=state.offset>0,missing=true}
        end
        journal_error(path,err);return
    end
    local read_ok,data,start,reset=pcall(function()
        local size,seek_err=file:seek('end')
        assert(size,seek_err or 'journal size unavailable')
        local restart=size<state.offset
        local offset=restart and 0 or state.offset
        local position,position_err=file:seek('set',offset)
        assert(position==offset,position_err or 'journal seek failed')
        local content,read_err=file:read(JOURNAL_READ_BUDGET)
        assert(content~=nil or (read_err==nil and offset==size),read_err or 'journal truncated during read')
        return content or '',offset,restart
    end)
    local close_ok,closed,close_err=pcall(file.close,file)
    if not read_ok then journal_error(path,data);return end
    if not close_ok or not closed then journal_error(path,close_err or closed or 'journal close failed');return end
    journal_error(path,nil)
    local next_state=journal_state()
    next_state.offset=start+#data
    if not reset then
        next_state.bytes,next_state.discarding=state.bytes,state.discarding
        for i,chunk in ipairs(state.chunks) do next_state.chunks[i]=chunk end
    end
    local rows,rejected,at={},0,1
    while at<=#data do
        -- Plain forward search is linear even if a large chunk has no newline.
        local boundary=data:find('\n',at,true)
        local last=boundary and boundary-1 or #data
        if next_state.discarding then
            if boundary then next_state.discarding=false end
        elseif next_state.bytes+last-at+1>JOURNAL_RECORD_LIMIT then
            next_state.chunks,next_state.bytes={},0
            next_state.discarding=not boundary
            rejected=rejected+1
        else
            next_state.chunks[#next_state.chunks+1]=data:sub(at,last)
            next_state.bytes=next_state.bytes+last-at+1
            if boundary then
                local line=table.concat(next_state.chunks)
                next_state.chunks,next_state.bytes={},0
                if line:find('%S') then
                    local ok,row=pcall(decode_journal,line)
                    if ok then rows[#rows+1]=row else rejected=rejected+1 end
                end
            end
        end
        if not boundary then break end
        at=boundary+1
    end
    journal_warning(path,rejected)
    return {rows=rows,state=next_state,reset=reset}
end
-- FIFO windows only hold reconstructible display state. Persisted responses
-- and native dictionaries remain the source of truth after an eviction.
local function cache(capacity)
    capacity=capacity or 4096
    local values,slots,positions,cursor={},{},{},1
    return setmetatable({}, {
        __index=values,
        __newindex=function(_,key,value)
            if value==nil then
                if positions[key] then slots[positions[key]]=nil;positions[key]=nil end
                values[key]=nil;return
            end
            if not positions[key] then
                local old=slots[cursor]
                if old then values[old]=nil;positions[old]=nil end
                slots[cursor]=key;positions[key]=cursor;cursor=cursor%capacity+1
            end
            values[key]=value
        end,
        __pairs=function() return next,values,nil end,
    })
end
local failures,failure_generation=cache(),nil
local ready = cache()
local ready_text = cache()
local pending = cache()
local pending_priority = cache()
local native_probe = cache()
local prefetch_published = cache()
local short_ready = cache()
local short_staged = cache()
local paragraph_ready = cache()
local literal_ready = cache()
local colored_ready = cache()
local colored_staged = cache()
local alias_text = cache()
local display_sources, display_names, display_fragments, display_saved = cache(), cache(), cache(), cache(16384)
local display_native = cache()
local announcement_staged,announcement_ready = cache(),cache()
local display_path = directory .. 'unit-display-cache.jsonl'
local restore_display
local display_initialized = false
local short_counter = 0
local alias_reserved = 0
local alias_initialized = false
local alias_counter_path = directory .. 'runtime-alias-counter.txt'
local pending_loaded = false
local pending_render_ready = false
local current_world
local current_language='zh-Hant'
local color_persistence=true
local api_enabled,background_enabled=true,true
local function localize(text)
    return native.localize_text and native.localize_text(text) or text
end

function language() return current_language end
function narrative_mode() return current_language..':'..tostring(api_enabled) end
function localize_text(text) return localize(text) end
function display_rows(rows)
    return native.native_display_rows_set(json.encode(rows,{pretty=false}))
end
function configure(value)
    api_enabled=value.apiEnabled~=false
    background_enabled=value.backgroundTranslation~=false
end
function set_language(value,color_enabled)
    assert(value=='zh-Hant' or value=='zh-Hans')
    color_persistence=color_enabled~=false
    if current_language==value then return end
    current_language=value
    display_initialized=false;pending_loaded=false;pending_render_ready=false
    poll()
end
local translation_watchers = {}
local visible_serialized
local visible_ids={}
local started = false
local short_alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
local pending_short_key = 'P_____'

local function identity(source, figure_id, entity_kind)
    if entity_kind then return source .. '\0' .. entity_kind .. ':' .. tostring(figure_id) end
    return figure_id ~= nil and source .. '\0figure:' .. tostring(figure_id) or source
end

local function paragraph_identity(source, links, subject_id)
    local parts = {source, '\0paragraph:', tostring(subject_id or '')}
    for _, link in ipairs(links) do
        parts[#parts+1] = '\0' .. link.type .. ':' .. link.id .. ':' .. #link.text .. ':' .. link.text
    end
    return table.concat(parts)
end

local world

function visibility_id(source,entity_id,entity_kind)
    return identity(source,entity_id,entity_kind)
end

function paragraph_visibility_id(source,links,subject_id)
    return paragraph_identity(source,links,subject_id)
end

function set_visible(ids)
    if world() ~= current_world then poll() end
    if type(ids)~='table' or #ids>256 then return false end
    local next_ids={}
    for _,id in ipairs(ids) do
        if type(id)~='string' or #id>8000 then return false end
        next_ids[id]=true
    end
    local serialized=json.encode({world=current_world,language=current_language,ids=ids},{pretty=false})
    if serialized==visible_serialized then return true end
    local file=io.open(visibility_path,'wb')
    if not file then return false end
    local ok,written=pcall(file.write,file,serialized)
    local closed,result=pcall(file.close,file)
    if not ok or not written or not closed or not result then return false end
    for id in pairs(visible_ids) do
        if not next_ids[id] then pending[id]=nil end
    end
    visible_ids=next_ids
    visible_serialized=serialized
    return true
end

world = function()
    return dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
end

local function csv_field(value)
    return '"' .. value:gsub('"', '""') .. '"'
end

local function color_tag(color)
    local byte=color:byte()
    return ('[C:%d:%d:%d]'):format(byte%8,math.floor(byte/8)%8,math.floor(byte/64)%2)
end

local function load_rows(rows, path)
    if #rows == 0 then return end
    local lines = {'text,translation,tags\n'}
    for _, row in ipairs(rows) do
        lines[#lines+1] = csv_field(row.text) .. ',' .. csv_field(localize(row.translation)) .. ',\n'
    end
    local file = assert(io.open(path, 'wb'))
    local write_ok,written,write_err=pcall(file.write,file,table.concat(lines))
    local close_ok,closed,close_err=pcall(file.close,file)
    assert(write_ok and written,write_err or written or 'Response CSV write failed')
    assert(close_ok and closed,close_err or closed or 'Response CSV close failed')
    local loaded,err=native.load_simple_dict(current_language, path)
    if loaded==false then error(err or 'Native dictionary rejected response rows') end
end

local function display_record(kind, source, translated, color, key)
    if type(translated) ~= 'string' or translated == '' or #translated > 24000 then return end
    if kind == 'native' then
        if not current_world or type(source) ~= 'string' or source == '' or #source > 8000 or
                not utf8.len(translated) then return end
        local plain=translated:gsub('%[C:[0-7]:[0-7]:[01]%]',''):gsub('%[[BPR]%]','')
        if plain:match('[A-Za-z{}%[%]]') or not plain:match('[\128-\255]') then return end
        local function tokens(text)
            local found={}
            for token in text:gmatch('%[[^%[%]]+%]') do found[#found+1]=token end
            table.sort(found);return table.concat(found,'\0')
        end
        if tokens(source)~=tokens(translated) then return end
        return {version=1,world=current_world,language=current_language,kind=kind,text=source,translation=translated}
    end
    if kind=='fragment' then
        local clean=translated:gsub('%[C:[0-7]:[0-7]:[01]%]',''):gsub('%[[BPR]%]','')
        if not utf8.len(translated) or clean:match('[A-Za-z{}%[%]]') or type(color)~='number' or
                color<0 or color>127 or color~=math.floor(color) then return end
        if key~=nil and (type(key)~='string' or not key:match('^L[%w][%w][%w][%w][%w][%w]_*$')) then return end
        return {version=1,world=current_world or false,language=current_language,kind=kind,translation=translated,color=color,key=key}
    end
    local clean = translated:gsub('{DWARF_NAME}', '')
    if clean:match('[A-Za-z{}%[%]]') then return end
    if not current_world or (kind ~= 'source' and kind ~= 'name') or
            type(source) ~= 'string' or source == '' or #source > 8000 then return end
    if translated ~= clean and (kind ~= 'source' or source:sub(1,19) ~= '{DWARF_NAME} likes ' or
            select(2, translated:gsub('{DWARF_NAME}', '')) ~= 1) then return end
    return {version=1, world=current_world, language=current_language, kind=kind, text=source, translation=translated}
end

local function retain_display(row)
    local id = row.kind .. '\0' .. (row.kind == 'fragment' and string.char(row.color) .. row.translation or row.text)
    if row.kind == 'source' then display_sources[row.text] = row.translation
    elseif row.kind == 'name' then display_names[row.text] = row.translation
    elseif row.kind == 'native' then display_native[row.text] = row.translation
    else display_fragments[string.char(row.color) .. row.translation] = row end
    return id
end

local function save_display(rows)
    if #rows == 0 then return true end
    local lines = {'\n'}
    for _, row in ipairs(rows) do lines[#lines+1] = json.encode(row, {pretty=false}) .. '\n' end
    local file = io.open(display_path, 'ab')
    if not file then return false end
    local ok, written = pcall(file.write, file, table.concat(lines))
    local closed, result = pcall(file.close, file)
    if ok and written and closed and result then
        for _, row in ipairs(rows) do display_saved[retain_display(row)] = row.key or row.translation end
        return true
    end
    return false
end

local function remember_display(kind, source, translated, color, key)
    if kind=='fragment' and not color_persistence then return end
    local row = display_record(kind, source, translated, color, key)
    if not row then return end
    local id = retain_display(row)
    if display_saved[id] ~= (key or translated) then
        save_display({row})
    end
end

local function load_display()
    display_sources, display_names, display_fragments, display_saved = cache(), cache(), cache(), cache(16384)
    display_native = cache()
    local file = io.open(display_path, 'rb')
    if file then
        -- The history is append-only; stream it so old worlds do not allocate
        -- a second copy of the entire journal during a save transition.
        for line in file:lines() do
            local ok, value = pcall(json.decode, line)
            if ok and type(value) == 'table' and value.version == 1 and
                    value.world == (current_world or false) and (value.language or 'zh-Hant')==current_language and
                    (value.kind~='fragment' or color_persistence) then
                local row = display_record(value.kind, value.text, value.translation, value.color,value.key)
                if row then display_saved[retain_display(row)] = row.key or row.translation end
            end
        end
        file:close()
    end
    -- Only aliases and viewed prose need Lua restoration. Bulk rows belong to the DLL.
    local function read_export(filename)
        local handle=io.open(directory..filename,'rb')
        if not handle then return end
        local content=handle:read('*a');handle:close()
        local ok,data=pcall(json.decode,content)
        if ok and type(data)=='table' and data.version==1 and data.world==current_world and
                (data.language or 'zh-Hant')==current_language then return data end
    end
    local data=read_export(current_language=='zh-Hant' and 'native-prewarm-unit.json' or 'native-prewarm-unit-zh-Hans.json')
    -- Compatibility with older Broker exports until their first refreshed snapshot.
    if not data then
        data=read_export(current_language=='zh-Hant' and 'native-prewarm.json' or 'native-prewarm-zh-Hans.json')
    end
    if not data then return end
    for _,value in ipairs(type(data.rows)=='table' and data.rows or {}) do
        if type(value)=='table' then
            local row=display_record('native',value.text,value.translation)
            if row and not ready_text[row.text] then
                ready[row.text],ready_text[row.text]=row.text,row.translation
            end
        end
    end
    local unit=type(data.unit)=='table' and data.unit or {}
    local changed = {}
    for field, kind in pairs({sources='source', names='name', fragments='fragment'}) do
        for _, value in ipairs(type(unit[field]) == 'table' and unit[field] or {}) do
            if type(value) == 'table' then
                local row = display_record(kind, value.text, value.translation, value.color,value.key)
                if row then
                    if kind=='fragment' then
                        local old=display_fragments[string.char(row.color)..row.translation]
                        row.key=old and old.key or row.key
                    end
                    local id = retain_display(row)
                    if display_saved[id] ~= (row.key or row.translation) then changed[#changed+1] = row end
                end
            end
        end
    end
    save_display(changed)
end

local function load_translation(key, translation, alignment, color)
    translation=localize(translation)
    local file = assert(io.open(one_row_path, 'wb'))
    file:write('text,translation,tags\n', csv_field(key), ',',
        csv_field(translation), ',', alignment == 'CENTER' and '[ALIGNMENT:CENTER]' or '', '\n')
    if color then
        local tag=color_tag(color)
        file:write(csv_field(tag..key),',',csv_field(tag..translation),',\n')
    end
    -- Legends truncates tab captions before submitting them to the renderer.
    if alignment == 'CENTER' then
        for length = 7, #key - 1 do
            local count = math.floor(length / 2)
            local stop = utf8.offset(translation, count + 1)
            local caption = stop and translation:sub(1, stop - 1) .. '...' or translation
            file:write(csv_field(key:sub(1, length) .. '...'), ',',
                csv_field(caption), ',[ALIGNMENT:CENTER]\n')
        end
    end
    file:close()
    native.load_simple_dict(current_language, one_row_path)
    return mod.sync_translate(key) == translation and
        (not color or mod.sync_translate(color_tag(color)..key)==color_tag(color)..translation)
end

local function reserve_alias()
    if not alias_initialized then
        local file = io.open(alias_counter_path, 'rb')
        if file then
            local value = file:read('*a')
            file:close()
            short_counter = assert(tonumber(value), 'Invalid runtime alias counter')
            assert(short_counter >= 0 and short_counter == math.floor(short_counter),
                'Invalid runtime alias counter')
        end
        alias_reserved = short_counter
        alias_initialized = true
    end
    if short_counter >= alias_reserved then
        alias_reserved = short_counter + 1024
        local file = assert(io.open(alias_counter_path, 'wb'))
        assert(file:write(tostring(alias_reserved)))
        assert(file:close())
    end
end

function on_translation(source, callback)
    assert(type(source) == 'string' and source ~= '' and type(callback) == 'function')
    if world() ~= current_world then poll() end
    local saved=ready_text[source] or display_sources[source] or display_native[source]
    if saved then
        callback(saved)
        return function() end
    end
    local watchers = translation_watchers[source] or {}
    translation_watchers[source] = watchers
    local entry = {callback=callback}
    watchers[#watchers+1] = entry
    return function()
        entry.callback=nil
        for i=#watchers,1,-1 do if not watchers[i].callback then table.remove(watchers,i) end end
        if #watchers==0 and translation_watchers[source]==watchers then translation_watchers[source]=nil end
    end
end

local function notify_translation(source, translated)
    local watchers = translation_watchers[source]
    translation_watchers[source] = nil
    for _, entry in ipairs(watchers or {}) do
        if entry.callback then
            local ok, err = pcall(entry.callback, translated)
            if not ok then dfhack.printerr('df-local-zh-runtime callback: ' .. tostring(err)) end
        end
    end
end

function poll()
    local active_world = world()
    if not display_initialized or active_world ~= current_world then
        display_initialized = false
        current_world = active_world
        ready = cache()
        ready_text = cache()
        translation_watchers = {}
        pending = cache()
        pending_priority = cache()
        visible_serialized = nil
        visible_ids = {}
        native_probe = cache()
        prefetch_published = cache()
        short_ready = cache()
        short_staged = cache()
        paragraph_ready = cache()
        literal_ready = cache()
        colored_ready = cache()
        colored_staged = cache()
        announcement_staged,announcement_ready = cache(),cache()
        alias_text = cache()
        response_state,failure_state=journal_state(),journal_state()
        response_batch,response_error=nil,nil
        failures,failure_generation=cache(),nil
        load_display()
        restore_display()
        display_initialized = true
    end
    if not active_world then return end

    local failure_batch=read_journal(directory..'runtime-failures.jsonl',failure_state)
    local generation=failure_generation
    if failure_batch and not failure_batch.missing then
        local status=module('df-local-zh-status').broker()
        generation=status and status.runtime and status.runtime.retryGeneration
        if generation~=failure_generation then
            failure_state,failures,failure_generation=journal_state(),cache(),generation
            failure_batch=read_journal(directory..'runtime-failures.jsonl',failure_state)
        end
    end
    if failure_batch then
        if failure_batch.reset then failures=cache() end
        for _,row in ipairs(failure_batch.rows) do
            if type(row)=='table' and row.world==active_world and (row.language or 'zh-Hant')==current_language and
                    row.retryGeneration==generation and type(row.text)=='string' then
                local id=row.visibilityId or row.text
                failures[id]=row.terminal and row.reason or nil
            end
        end
        failure_state=failure_batch.state
    end

    response_batch=response_batch or read_journal(responses_path,response_state)
    if not response_batch then return end
    local restored, translations, paragraphs, restored_indices = {}, {}, {}, {}
    for _,row in ipairs(response_batch.rows) do
        if type(row) == 'table' and row.world == active_world and (row.language or 'zh-Hant')==current_language and
                type(row.text) == 'string' and type(row.translation) == 'string' and
                type(row.key) == 'string' and #row.key == 71 and
                row.key:match('^DFLIVE_[0-9a-f]+$') and
                ((row.kind == 'legends-name' and row.namePolicy == 'native-v2' and
                    type(row.entityKind) == 'string' and row.entityKind:match('^[a-z_]+$') and
                    type(row.entityId) == 'number' and row.entityId >= 0 and
                    row.entityId == math.floor(row.entityId) and row.figureId == nil) or
                    (row.kind ~= 'legends-name' and
                    ((row.figureId == nil and row.kind ~= 'legends-paragraph') or
                    row.namePolicy == 'native-v2'))) and
                (row.figureId == nil or (type(row.figureId) == 'number' and
                row.figureId >= 0 and row.figureId == math.floor(row.figureId))) then
            if row.kind == 'legends-paragraph' and type(row.requestLinks) == 'table' and
                    type(row.links) == 'table' and #row.links == #row.requestLinks then
                local valid=module('df-local-zh-offline-narrative').valid_result(row.text,row.requestLinks,row)
                if valid then paragraphs[#paragraphs+1]=row else journal_warning(responses_path,1) end
            elseif row.kind == nil or row.kind == 'legends-name' then
                -- The native dictionary keeps the latest value for each key.
                -- Verifying an older revision would otherwise retry forever.
                local index=restored_indices[row.key] or #restored+1
                restored_indices[row.key]=index
                restored[index] = row
                translations[index] = {text=row.key, translation=row.translation}
            end
        end
    end
    if #translations > 0 then
        local loaded,err = pcall(function()
            load_rows(translations, directory .. 'runtime-restored.csv')
            for _,row in ipairs(restored) do
                assert(mod.sync_translate(row.key)==row.translation,'dictionary verification failed')
            end
        end)
        if not loaded then
            if response_error~=tostring(err) then
                response_error=tostring(err)
                dfhack.printerr('df-local-zh-runtime response import: '..response_error)
            end
            return false -- Retain this complete batch, including its partial tail.
        end
        for _, row in ipairs(restored) do
            local id = identity(row.text,
                row.kind == 'legends-name' and row.entityId or row.figureId,
                row.kind == 'legends-name' and row.entityKind or nil)
            if ready[id]~=row.key or ready_text[id]~=row.translation then
                short_ready[id],short_staged[id]=nil,nil
            end
            ready[id] = row.key
            ready_text[id] = row.translation
            pending[id] = nil
            if row.kind == nil and row.figureId == nil then
                notify_translation(row.text, row.translation)
            end
        end
    end
    for _,row in ipairs(paragraphs) do
        local id=paragraph_identity(row.text,row.requestLinks,row.subjectId)
        paragraph_ready[id]={translation=row.translation,links=row.links}
        pending[id]=nil
    end
    response_error=nil
    response_state=response_batch.state
    response_batch=nil
end

local function append_request(row)
    local encoded = json.encode(row, {pretty=false})
    local file, err = io.open(requests_path, 'ab')
    if not file then return false, err end
    -- Start a fresh line so an interrupted append cannot swallow the retry.
    local write_ok, written, write_err = pcall(file.write, file, '\n' .. encoded .. '\n')
    local close_ok, closed, close_err = pcall(file.close, file)
    if not write_ok then return false, written end
    if not written then return false, write_err end
    if not close_ok then return false, closed end
    if not closed then return false, close_err end
    return true
end

function paragraph_lookup(source, links, subject_id, local_source, literals)
    local offline=module('df-local-zh-offline-narrative')
    if not offline.valid(source,links) then return nil,'invalid' end
    local active_world = world()
    if not active_world then return nil, 'invalid' end
    if active_world ~= current_world then poll() end
    local id = paragraph_identity(source, links, subject_id)
    -- Local paragraphs bypass batching and keep native clickable identities.
    local immediate
    if local_source and offline.literal_source(local_source,literals)==source then
        immediate=offline.translate_literal(local_source,links,literals,native.local_lookup)
    end
    immediate=immediate or offline.translate(source,links,native.local_lookup)
    if immediate then return immediate,'ready' end
    if paragraph_ready[id] then return paragraph_ready[id], 'ready' end
    if not api_enabled then
        local original={translation=source,links={},native_fallback=true}
        for i,link in ipairs(links) do original.links[i]={translation=link.text} end
        return original,'ready'
    end
    if failures[id] then
        pending[id]=nil
        return nil,'failed',failures[id]
    end
    local now = os.time()
    if pending[id] and now - pending[id] < 20 then return nil, 'pending' end
    if #source > 8000 or #links > 64 then return nil, 'invalid' end
    local ok, err = append_request({world=active_world, language=current_language, text=source, kind='legends-paragraph',
        links=links, subjectId=subject_id,namePolicy='native-v2',priority='foreground',
        visibilityId=id})
    if not ok then return nil, 'failed', err end
    pending[id] = now
    return nil, 'queued'
end

function request(source, figure_id, entity_kind, priority)
    local active_world = world()
    if not active_world or type(source) ~= 'string' or #source == 0 or #source > 8000 or
            source:match('%f[%w]L%w%w%w%w%w%w_+') or source:find('DFLIVE_',1,true) then
        return nil, 'invalid'
    end
    if active_world ~= current_world then poll() end
    local id = identity(source, figure_id, entity_kind)
    if ready[id] then return ready[id], 'ready' end
    if failures[id] then return nil,'failed',failures[id] end
    if figure_id==nil then
        local saved=display_sources[source] or display_native[source]
        if saved then
            ready[id],ready_text[id]=source,saved
            pending[id]=nil
            notify_translation(source,saved)
            return source,'ready'
        end
    end
    priority=priority or 'foreground'
    if priority~='foreground' and priority~='recent' and priority~='background' then return nil,'invalid' end
    local now = os.time()
    local waiting=pending[id] and now-pending[id]<20
    local promote=waiting and priority=='foreground' and pending_priority[id]~='foreground'
    local existing=figure_id==nil and native.cache_lookup and native.cache_lookup(source) or nil
    -- A cold native "async" probe also starts rule work. Long prose uses the
    -- Broker; persisted unit prose has already been checked by unit_translation.
    if not existing and #source<=160 and figure_id==nil and priority=='foreground' and
            (not waiting or native_probe[id]~=now) then
        native_probe[id]=now
        existing=mod.async_translate(source)
    end
    if type(existing) == 'string' and existing ~= '' and
            not existing:match('[A-Za-z]') then
        ready[id] = source
        ready_text[id] = existing
        pending[id] = nil
        notify_translation(source,existing)
        return source, 'ready'
    end
    if not api_enabled or priority=='background' and not background_enabled then return nil,'disabled' end
    if waiting and not promote then return nil, 'pending' end

    local row={world=active_world, language=current_language, text=source,
        namePolicy=figure_id~=nil and 'native-v2' or nil,priority=priority}
    if figure_id~=nil then row.visibilityId=id end
    if entity_kind then
        row.kind='legends-name';row.entityKind=entity_kind;row.entityId=figure_id
    else row.figureId=figure_id end
    local ok, err = append_request(row)
    if not ok then return nil, 'failed', err end
    pending[id] = now
    pending_priority[id]=priority
    return nil, 'queued'
end

function prefetch(source,priority)
    if world() ~= current_world then poll() end
    if not current_world then return false end
    local function display_ready()
        local shown=mod.async_translate(source)
        local plain=type(shown)=='string' and shown:gsub('%[C:%d+:%d+:%d+%]','')
            :gsub('%[[BPR]%]','') or nil
        return plain and shown~=source and plain:match('[\128-\255]') and
            not plain:match('[A-Za-z{}]') or false
    end
    if #source<=160 and not (ready_text[source] or display_sources[source] or display_native[source]) and
            display_ready() then return true end
    local key,state,reason=request(source,nil,nil,priority or 'background')
    if not key then return false,state,reason end
    local translated=ready_text[source] or mod.sync_translate(key)
    if type(translated)=='string' and source:find('{DWARF_NAME}',1,true) then
        local remainder,tokens=translated:gsub('{DWARF_NAME}','')
        return tokens==1 and not remainder:match('[A-Za-z]')
    end
    local plain=type(translated)=='string' and translated:gsub('%[C:%d+:%d+:%d+%]','')
        :gsub('%[[BPR]%]','') or nil
    if not plain or plain:match('[A-Za-z{}]') or not plain:match('[\128-\255]') then return false end
    local id=current_world..'\0'..source
    if prefetch_published[id]~=translated then
        if not publish_batch({{text=source,translation=translated}}) then
            return display_ready()
        end
        prefetch_published[id]=translated
    end
    return display_ready()
end

function invalidate_native_cache()
    display_initialized = false
    pending_loaded = false
    pending_render_ready = false
    poll()
end

function lookup(source, figure_id, entity_kind)
    if world() ~= current_world then poll() end
    local key=ready[identity(source, figure_id, entity_kind)]
    if key then return key,'ready' end
    return request(source, figure_id, entity_kind)
end

function translation(source)
    if world() ~= current_world then poll() end
    local installed=native.local_lookup and native.local_lookup(source)
    if installed then return installed end
    local preferred=native.official_library_lookup and native.official_library_lookup(source)
    if preferred then return preferred end
    local fixed=module('df-local-zh-reviewed-text').translation(source,current_language)
    if fixed then return fixed end
    local saved=ready_text[source] or display_sources[source] or display_native[source]
    if saved then return saved end
    local key=lookup(source)
    if not key then return nil end
    local text=ready_text[source] or mod.sync_translate(key)
    if text then ready_text[source]=text end
    return text
end

function background_translation(source)
    local key=request(source,nil,nil,'background')
    if not key then return nil end
    return ready_text[source] or mod.sync_translate(key)
end

function unit_translation(source)
    if world() ~= current_world then poll() end
    local installed=native.local_lookup and native.local_lookup(source)
    if installed then return installed end
    local preferred=native.official_library_lookup and native.official_library_lookup(source)
    if preferred then return localize(preferred) end
    local fixed=module('df-local-zh-reviewed-text').translation(source,current_language)
    local prewarm=module('df-local-zh-unit-prewarm')
    prewarm.remember(source)
    local text = fixed or prewarm.fixed_translation(source) or ready_text[source] or display_sources[source] or translation(source)
    if text then text=localize(text);remember_display('source', source, text) end
    return text
end

function unit_name_translation(source)
    if world() ~= current_world then poll() end
    -- Static species labels are global; personal names retain world-scoped routing.
    local fixed=module('df-local-zh-creature-names').translation(source,current_language)
    local synchronous=fixed and mod.sync_translate(source)
    -- Homonyms such as pike mean a fish here, but a weapon in equipment UI.
    local text = fixed and (synchronous==fixed and synchronous or fixed) or
        display_names[source] or mod.async_translate(source)
    if text then remember_display('name', source, text) end
    return text
end

function publish(source, translated)
    return load_translation(source, translated)
end

function publish_batch(rows)
    if type(rows)~='table' or #rows==0 or #rows>8 then return false end
    local lines={'text,translation,tags\n'}
    for _,row in ipairs(rows) do
        if type(row.text)~='string' or type(row.translation)~='string' then return false end
        local alignment=row.alignment=='center' and '[ALIGNMENT:CENTER]' or
            row.alignment=='right' and '[ALIGNMENT:RIGHT]' or ''
        lines[#lines+1]=csv_field(row.text)..','..csv_field(localize(row.translation))..','..alignment..'\n'
    end
    local path=directory..'native-prewarm-batch.csv'
    local file=assert(io.open(path,'wb'))
    assert(file:write(table.concat(lines)));assert(file:close())
    native.load_simple_dict(current_language,path)
    for _,row in ipairs(rows) do
        if mod.sync_translate(row.text)~=localize(row.translation) then return false end
    end
    return true
end

function publish_native(rows)
    if not display_initialized or world() ~= current_world then poll() end
    if not current_world or type(rows)~='table' or #rows==0 or #rows>8 then return false end
    local changed={}
    for _,row in ipairs(rows) do
        local record=display_record('native',row.text,row.translation)
        if not record then return false end
        if display_saved['native\0'..row.text]~=row.translation then changed[#changed+1]=record end
    end
    if not publish_batch(rows) then return false end
    return save_display(changed)
end

function native_ready(source,translated)
    return mod.async_translate(source)==localize(translated)
end

function pending_key(status)
    if not api_enabled or (status~='queued' and status~='pending') then return nil end
    if not pending_loaded then
        local ok, loaded = pcall(load_translation, pending_short_key, '翻譯中')
        if not ok or not loaded then return nil end
        pending_loaded = true
    end
    if not pending_render_ready then
        if mod.async_translate(pending_short_key)~=localize('翻譯中') then return nil end
        pending_render_ready=true
    end
    return pending_short_key
end

local function next_alias(width)
    local base = #short_alphabet
    reserve_alias()
    if short_counter >= base ^ 6 then return end
    local value = short_counter
    short_counter = short_counter + 1
    local suffix = ''
    for _ = 1, 6 do
        local digit = value % base + 1
        suffix = short_alphabet:sub(digit, digit) .. suffix
        value = math.floor(value / base)
    end
    return 'L' .. suffix .. string.rep('_', width - 7)
end

-- Fresh keys bypass native misses cached before the Broker response arrived.
function announcement_key(translated,color)
    translated=localize(translated)
    if not display_initialized or world() ~= current_world then poll() end
    if type(translated)~='string' or type(color)~='string' or #color~=1 or color:byte()>127 then return end
    local plain=translated:gsub('%[C:[0-7]:[0-7]:[01]%]',''):gsub('%[[BPR]%]','')
    local length=utf8.len(plain)
    if not length or length==0 or #translated>24000 or plain:match('[A-Za-z{}%[%]]') or
            not plain:match('[\128-\255]') then return end
    local id=color..translated
    if announcement_ready[id] then
        remember_display('fragment',nil,translated,color:byte(),announcement_ready[id])
        return announcement_ready[id]
    end
    local key=announcement_staged[id]
    if not key then
        key=next_alias(math.max(7,length*2))
        if not key or not load_translation(key,translated,nil,color) then return end
        announcement_staged[id]=key
    end
    local tag=color_tag(color)
    if not native_ready(key,translated) or not native_ready(tag..key,tag..translated) then return end
    announcement_ready[id]=key;announcement_staged[id]=nil
    remember_display('fragment',nil,translated,color:byte(),key)
    return key
end

restore_display = function()
    local rows, aliases = {}, {}
    for text,translated in pairs(display_native) do
        rows[#rows+1]={text=text,translation=translated}
    end
    for text,translated in pairs(display_sources) do
        rows[#rows+1]={text=text,translation=translated}
    end
    for text,translated in pairs(display_names) do
        rows[#rows+1]={text=text,translation=translated}
    end
    for id, row in pairs(display_fragments) do
        local plain=row.translation:gsub('%[C:[0-7]:[0-7]:[01]%]',''):gsub('%[[BPR]%]','')
        local glyphs = utf8.len(plain)
        if glyphs then
            local key = row.key or next_alias(math.max(7, glyphs * 2))
            if key then
                local tag = color_tag(string.char(row.color))
                rows[#rows+1] = {text=key, translation=row.translation}
                rows[#rows+1] = {text=tag..key, translation=tag..row.translation}
                aliases[#aliases+1] = {id=id, key=key, source=tag..key, translation=tag..row.translation,
                    plain=row.translation,markup=plain~=row.translation}
            end
        end
    end
    load_rows(rows, directory .. 'unit-display-restored.csv')
    for _, row in ipairs(aliases) do
        announcement_staged[row.id]=row.key
        if not row.markup then colored_staged[row.id] = row.key end
    end
end

local function make_alias(translation, expand, alignment, max_width, source_length, color, literal)
    if type(translation) ~= 'string' or translation == '' or
            not literal and translation:match('[A-Za-z]') then return nil end
    local glyphs = utf8.len(translation)
    if not glyphs then return nil end
    local width = math.max(7, glyphs * 2)
    if max_width and width > max_width then
        if max_width < 8 then return nil end
        local count = math.floor((max_width - 6) / 2)
        local stop = utf8.offset(translation, count + 1)
        translation = translation:sub(1, stop - 1) .. '...'
        width = math.max(7, (count + 3) * 2)
    end
    if not expand and width > source_length then return false end

    local alias = next_alias(width)
    if alias then
        local ok, loaded = pcall(load_translation, alias, translation, alignment, color)
        if ok and loaded then
            if not color then alias_text[alias] = translation end
            return alias
        end
        return nil
    end
    return nil
end

function literal_key(translation)
    if type(translation)~='string' or translation:match('{{DF[LNE]%d+}}') or translation:find('{DWARF_NAME}',1,true) then return nil end
    translation=localize(translation)
    if not display_initialized or world() ~= current_world then poll() end
    if literal_ready[translation] then return literal_ready[translation] end
    local key = make_alias(translation, true, nil, nil, nil, nil, true)
    if key then literal_ready[translation] = key end
    return key
end

local function color_alias(translation, color, literal)
    if type(color)~='string' or #color~=1 or color:byte()>127 then return nil end
    local id=(literal and 'literal:' or '')..color..translation
    if colored_ready[id] then
        if not literal then remember_display('fragment',nil,translation,color:byte(),colored_ready[id]) end
        return colored_ready[id]
    end
    local key=colored_staged[id]
    if not key then
        key=make_alias(translation,true,nil,nil,nil,color,literal)
        if not key then return nil end
        colored_staged[id]=key
    end
    local tag=color_tag(color)
    if mod.async_translate(tag..key)~=tag..translation then return nil end
    colored_staged[id]=nil
    colored_ready[id]=key
    if not literal then remember_display('fragment', nil, translation, color:byte(),key) end
    return key
end

function colored_key(translation, color)
    translation=localize(translation)
    if not display_initialized or world() ~= current_world then poll() end
    return color_alias(translation, color)
end

-- Only callers that already validated literal identity slots may use this.
-- These transient aliases are bounded and never persisted as prose fragments.
function literal_colored_key(translation,color)
    if type(translation)~='string' or #translation>24000 or translation:find('[{}%[%]]') then return nil end
    translation=localize(translation)
    if not display_initialized or world()~=current_world then poll() end
    return color_alias(translation,color,true)
end

function draw_key(x,y,color,background,key,flag)
    if not display_initialized or world() ~= current_world then poll() end
    local translated=alias_text[key]
    background=background or 0
    if translated and type(color)=='number' and color>=0 and color<=15 and
            color==math.floor(color) and type(background)=='number' and background>=0 and
            background<=7 and background==math.floor(background) then
        local byte=color%8+(background or 0)*8+(color>=8 and 64 or 0)
        key=color_alias(translated,string.char(byte)) or key
    end
    return native.dfhack_addstr_flag(x,y,color%8,background or 0,color>=8 and 1 or 0,key,flag or 0)
end

function short_lookup(source, expand, alignment, max_width, figure_id, entity_kind)
    if world() ~= current_world then poll() end
    local mode = (expand and 'expanded' or 'fixed') .. ':' .. (alignment or 'LEFT') ..
        ':' .. tostring(max_width or '')
    local id = identity(source, figure_id, entity_kind)
    local cached = short_ready[id] and short_ready[id][mode]
    if cached ~= nil then return cached or nil,cached and 'ready' or 'unavailable' end
    local staged=short_staged[id] and short_staged[id][mode]
    if staged then
        if mod.async_translate(staged.key)~=staged.translation then return nil,'rendering' end
        short_ready[id]=short_ready[id] or {};short_ready[id][mode]=staged.key
        short_staged[id][mode]=nil
        return staged.key,'ready'
    end
    local key,status,reason = lookup(source, figure_id, entity_kind)
    if not key then return nil,status,reason end
    local alias = make_alias(ready_text[id] or mod.sync_translate(key), expand, alignment, max_width, #source)
    short_ready[id] = short_ready[id] or {}
    if alias then
        local text=mod.sync_translate(alias)
        if mod.async_translate(alias)~=text then
            short_staged[id]=short_staged[id] or {}
            short_staged[id][mode]={key=alias,translation=text}
            return nil,'rendering'
        end
    end
    short_ready[id][mode] = alias
    return alias or nil,alias and 'ready' or 'unavailable'
end

function restore_legends(page)
    return module('df-local-zh-legends').restore_native(page)
end

function adopt_running()
    started=true
end

function start()
    if started then return end
    started = true
    local legends = reqscript('df-local-zh-legends')
    local unit_text = reqscript('df-local-zh-unit-text')
    reqscript('df-local-zh-hover-text').start(_ENV)
    local unit_bridge = {translation=unit_translation,colored_key=colored_key,literal_colored_key=literal_colored_key,announcement_key=announcement_key,
        publish=publish,display_rows=display_rows,
        name_translation=unit_name_translation,observe=reqscript('df-local-zh-prefetch').observe}
    reqscript('df-local-zh-unit-prewarm').start({translation=background_translation,colored_key=colored_key})
    reqscript('df-local-zh-native-prewarm').start()
    reqscript('df-local-zh-prefetch').start({prefetch=prefetch})
    local bridge = {short_lookup = short_lookup, pending_key = pending_key,
        paragraph_lookup=paragraph_lookup, literal_key=literal_key,narrative_mode=narrative_mode,
        restore_legends=restore_legends,
        set_visible=set_visible,visibility_id=visibility_id,
        paragraph_visibility_id=paragraph_visibility_id}
    local function tick()
        local ok, err = pcall(poll)
        if not ok then dfhack.printerr('df-local-zh-runtime: ' .. tostring(err)) end
        local sheet_ok, sheet_err = pcall(unit_text.start, unit_bridge)
        if not sheet_ok then dfhack.printerr('df-local-zh-unit-text: ' .. tostring(sheet_err)) end
        dfhack.timeout(4, 'frames', tick)
    end
    local function legends_tick()
        local ok, err = pcall(legends.poll, bridge)
        if not ok then dfhack.printerr('df-local-zh-legends: ' .. tostring(err)) end
        -- Legends pages do not need a per-render-frame scan; keep the reader
        -- responsive without competing with the game's render loop.
        dfhack.timeout(4, 'frames', legends_tick)
    end
    tick()
    legends_tick()
end
