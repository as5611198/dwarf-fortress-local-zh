--@module=true
local json=require('json')
local unicode=reqscript('df-local-zh-unicode')
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')
local first_names,last_signature,last_rows

local function chinese(text)
    return type(text)=='string' and text~='' and not text:find('[A-Za-z]') and utf8.len(text)~=nil
end

-- Only compose verified native nickname boundaries. Never translate user text.
function prepare(s,lookup,first_translation)
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

function poll(runtime)
    if not native.native_nickname_rows_set then return end
    local sheet=df.global.game.main_interface.view_sheets
    local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getDFViewscreen()),'/')
    local unit=dfhack.isMapLoaded() and sheet.open and focus:find('ViewSheets/UNIT/',1,true) and df.unit.find(sheet.active_id)
    if not unit or dfhack.units.getVisibleName(unit).nickname=='' then
        if last_signature then native.native_nickname_rows_set('[]');last_signature,last_rows=nil,nil end
        return
    end
    local s=snapshot(unit)
    local signature=json.encode({world=dfhack.getSavePath(),language=native.localize_text('繁體'),unit=unit.id,name=s})
    if signature~=last_signature or not last_rows then
        local dictionary=glossary()
        local first=dictionary[s.first] or dictionary[s.first:gsub('^%l',string.upper)]
        if first then first=native.localize_text(first) end
        local function lookup(text)
            return text==s.profession and runtime.translation(text) or runtime.name_translation(text)
        end
        local rows=prepare(s,lookup,first)
        local encoded=json.encode(rows)
        -- Retry incomplete translations at the existing 20-frame adapter cadence.
        local complete=#rows>0 and (s.profession=='' or chinese(lookup(s.profession)))
        last_signature,last_rows=signature,complete and encoded or nil
        assert(native.native_nickname_rows_set(encoded),'Nickname display bindings rejected')
    else
        assert(native.native_nickname_rows_set(last_rows),'Nickname display renewal rejected')
    end
end
