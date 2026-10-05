--@module=true
local json=require('json')
local unicode=reqscript('df-local-zh-unicode')
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')
local first_names,last_signature,last_rows
local list_active=false

local function chinese(text)
    return type(text)=='string' and text~='' and not text:find('[A-Za-z]') and utf8.len(text)~=nil
end

-- Unit identities come from native list records. Resolve only their profession;
-- names and player nicknames are never submitted to a translator by this poll.
function prepare_list(s,lookup,name_lookup)
    local profession=lookup(s.profession)
    if not chinese(profession) then
        profession=lookup(s.profession:gsub('^%l',string.upper))
    end
    if not chinese(profession) then return {} end
    local rows,seen={},{}
    for _,source in ipairs{s.native,s.english} do
        if not seen[source] then
            local name=s.nickname=='' and name_lookup and name_lookup(source) or nil
            rows[#rows+1]={source=source..', '..s.profession,
                translation=(chinese(name) and name or source)..', '..profession}
            seen[source]=true
        end
    end
    return rows
end

-- Only compose verified native nickname boundaries. Never translate user text.
function prepare(s,lookup,first_translation)
    if s.nickname=='' then
        local name=lookup(s.base)
        local profession=s.profession~='' and lookup(s.profession) or ''
        local rows,seen={},{}
        for _,source in ipairs{s.native,s.english} do
            local translated=chinese(name) and name or source
            local function add(key,value)
                if not seen[key] then rows[#rows+1]={source=key,translation=value};seen[key]=true end
            end
            if translated~=source then add(source,translated);add('"'..source..'"','"'..translated..'"') end
            if chinese(profession) then add(source..', '..s.profession,translated..', '..profession) end
        end
        return rows
    end
    local prefix='`'..s.nickname.."'"
    local function named(surname) return prefix..(surname~='' and ' '..surname or '') end
    if s.nickname=='' or s.native~=named(s.native_surname) or s.english~=named(s.english_surname) then return {} end
    local surname=s.native_surname=='' and '' or nil
    local full=surname~=nil and '' or lookup(s.base)
    if chinese(full) then
        if s.first=='' then surname=full
        elseif first_translation and full:sub(1,#first_translation+1)==first_translation..' ' then
            surname=full:sub(#first_translation+2)
        end
    end
    if surname~='' and not chinese(surname) then surname=lookup(s.native_surname) end
    if surname~='' and not chinese(surname) then return {} end
    local translated=named(surname)
    local profession=s.profession~='' and lookup(s.profession) or ''
    local rows,seen={},{}
    local function add(source,text)
        if not seen[source] then rows[#rows+1]={source=source,translation=text};seen[source]=true end
    end
    for _,source in ipairs{s.native,s.english} do
        add(source,translated)
        add('"'..source..'"','"'..translated..'"')
        if chinese(profession) then add(source..', '..s.profession,translated..', '..profession) end
    end
    return rows
end

local function glossary()
    if first_names then return first_names end
    local file=assert(io.open(paths.broker_source()..'/name-dictionary.json','rb'))
    local content=file:read('*a');file:close()
    first_names=json.decode(content)
    return first_names
end

function snapshot(unit)
    local name=dfhack.units.getVisibleName(unit)
    local s={nickname=unicode.decode(name.nickname),first=unicode.decode(name.first_name),
        native=unicode.decode(dfhack.translation.translateName(name,false)),
        english=unicode.decode(dfhack.translation.translateName(name,true)),
        profession=unicode.decode(dfhack.units.getProfessionName(unit))}
    local copy=df.language_name:new()
    local ok,err=xpcall(function()
        copy:assign(name);copy.nickname=''
        s.base=unicode.decode(dfhack.translation.translateName(copy,false))
        copy.first_name=''
        s.native_surname=unicode.decode(dfhack.translation.translateName(copy,false))
        s.english_surname=unicode.decode(dfhack.translation.translateName(copy,true))
    end,debug.traceback)
    copy:delete()
    assert(ok,err)
    return s
end

local function visible(w)
    return w and w.flag.VISIBILITY_ACTIVE and w.flag.VISIBILITY_VISIBLE
end

local function clear_list()
    if list_active then
        assert(native.native_unit_list_rows_set('[]'),'Resident display cleanup rejected')
        list_active=false
    end
end

local function poll_residents(focus)
    if not native.native_unit_list_rows_set then return end
    if not dfhack.isMapLoaded() then clear_list();return end
    if focus:find('dwarfmode/Info/ADMINISTRATORS',1,true) then
        local admins=df.global.game.main_interface.info.administrators
        local candidates=admins.choosing_candidate
        local list=candidates and admins.candidate or admins.noblelist
        local first=math.max(0,candidates and admins.scroll_position_candidate or admins.scroll_position_noblelist)
        local bindings,seen={},{}
        -- Legacy administrator lists expose native unit records, not the resident
        -- widgets. Bound to the current scroll window and discard pointers here.
        for i=first,math.min(#list-1,first+31) do
            local unit=list[i].un
            if unit and unit.custom_profession=='' then
                for _,row in ipairs(prepare_list(snapshot(unit),native.local_lookup,native.cache_lookup)) do
                    if not seen[row.source] then bindings[#bindings+1]=row;seen[row.source]=true end
                end
            end
        end
        if #bindings==0 then clear_list();return end
        assert(native.native_unit_list_rows_set(json.encode(bindings)),'Administrator display bindings rejected')
        list_active=true
        return
    end
    local scroll
    if focus:find('dwarfmode/Info/LABOR/WORK_DETAILS',1,true) then
        local labor=df.global.game.main_interface.info.labor
        local tabs=dfhack.gui.getWidget(labor,'Tabs')
        local details=tabs and dfhack.gui.getWidget(tabs,'Work Details')
        local right=details and dfhack.gui.getWidget(details,'Right panel')
        local panel=right and dfhack.gui.getWidget(right,0)
        local list=panel and dfhack.gui.getWidget(panel,3)
        -- The native labor tab owns a separate unit list. Check each ancestor:
        -- inactive tabs can leave descendants with their own visible flags set.
        if not visible(labor) or not visible(tabs) or not visible(details)
            or not visible(right) or not visible(panel) or not visible(list) then clear_list();return end
        scroll=dfhack.gui.getWidget(list,'Unit List',1)
    elseif focus:find('dwarfmode/Info/CREATURES',1,true) then
        local creatures=df.global.game.main_interface.info.creatures
        if creatures.current_mode~=df.unit_list_mode_type.CITIZEN then clear_list();return end
        local tabs=dfhack.gui.getWidget(creatures,'Tabs')
        local residents=tabs and dfhack.gui.getWidget(tabs,'Residents')
        if not visible(creatures) or not visible(tabs) or not visible(residents) then clear_list();return end
        scroll=dfhack.gui.getWidget(residents,0,'Unit List',1)
    else
        clear_list();return
    end
    if not df.widget_scroll_rows:is_instance(scroll) or not visible(scroll) or scroll.num_visible<=0 then clear_list();return end
    local bindings,seen={},{}
    -- Index only the native visible window, including a possible partial row.
    -- Never materialize all children or retain widget/unit pointers between polls.
    local first=math.max(0,scroll.scroll)
    local count=math.min(32,math.max(0,scroll.num_visible)+1)
    for i=first,math.min(#scroll.children-1,first+count-1) do
        local row=dfhack.gui.getWidget(scroll,i)
        local name=visible(row) and dfhack.gui.getWidget(row,'Name')
        if df.widget_unit_name:is_instance(name) and visible(name) and name.show_profession and name.u
            and name.u.custom_profession=='' then
            for _,row in ipairs(prepare_list(snapshot(name.u),native.local_lookup,native.cache_lookup)) do
                if not seen[row.source] then
                    bindings[#bindings+1]=row;seen[row.source]=true
                end
            end
        end
    end
    if #bindings==0 then clear_list();return end
    assert(native.native_unit_list_rows_set(json.encode(bindings)),'Resident display bindings rejected')
    list_active=true
end

function poll(runtime)
    if not native.native_nickname_rows_set then return end
    local sheet=df.global.game.main_interface.view_sheets
    local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen()),'/')
    local ok,err=pcall(poll_residents,focus)
    if not ok then clear_list();error(err) end
    local unit=dfhack.isMapLoaded() and sheet.open and focus:find('ViewSheets/UNIT/',1,true) and df.unit.find(sheet.active_id)
    if not unit then
        if last_signature then native.native_nickname_rows_set('[]');last_signature,last_rows=nil,nil end
        return
    end
    local s=snapshot(unit)
    local signature=json.encode({world=dfhack.getSavePath(),language=native.localize_text('繁體'),unit=unit.id,name=s})
    if signature~=last_signature or not last_rows then
        local dictionary=s.nickname~='' and glossary() or {}
        local first=dictionary[s.first] or dictionary[s.first:gsub('^%l',string.upper)]
        if first then first=native.localize_text(first) end
        local function lookup(text)
            return text==s.profession and runtime.translation(text) or runtime.name_translation(text)
        end
        local rows=prepare(s,lookup,first)
        local encoded=json.encode(rows)
        -- Retry incomplete translations at the existing 20-frame adapter cadence.
        local complete=#rows>0 and (s.profession=='' or chinese(lookup(s.profession))) and
            (s.nickname~='' or chinese(lookup(s.base)))
        last_signature,last_rows=signature,complete and encoded or nil
        assert(native.native_nickname_rows_set(encoded),'Nickname display bindings rejected')
    else
        assert(native.native_nickname_rows_set(last_rows),'Nickname display renewal rejected')
    end
end
