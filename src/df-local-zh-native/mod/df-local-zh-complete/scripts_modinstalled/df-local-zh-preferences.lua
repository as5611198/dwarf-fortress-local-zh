--@module=true
local function replace(text,from,to)
    return text:gsub(from:gsub('(%W)','%%%1'),function() return to end)
end
function mask(source,name,forms)
    if type(source)~='string' or #source>8192 or source:find('[{}]') or
        type(name)~='string' or name=='' or source:sub(1,#name+7)~=name..' likes ' then return nil end
    local bindings={{slot='{DWARF_NAME}',name=name,count=1}}
    local text='{DWARF_NAME}'..source:sub(#name+1)
    local names,seen={},{}
    for _,form in ipairs(forms or {}) do
        if type(form)=='string' and form~='' and not form:find('[{}]') and not seen[form] then
            names[#names+1]=form;seen[form]=true
        end
    end
    if #names>16 then return nil end
    table.sort(names,function(a,b) return #a>#b end)
    for _,form in ipairs(names) do
        local slot='{PREF_NAME_'..#bindings..'}'
        local count=0
        for _,prefix in ipairs({'the words of ','the sound of ','the sight of '}) do
            local n;text,n=replace(text,prefix..form,prefix..slot);count=count+n
        end
        if count>0 then bindings[#bindings+1]={slot=slot,name=form,count=count,quote=true} end
    end
    return text,bindings
end
function restore(text,bindings,lookup)
    if type(text)~='string' or #text>16384 or not utf8.len(text) or type(bindings)~='table' then return nil end
    local remaining=text
    for _,b in ipairs(bindings) do
        local n;remaining,n=replace(remaining,b.slot,'')
        if n~=b.count then return nil end
    end
    if remaining:find('[A-Za-z{}]') then return nil end
    for _,b in ipairs(bindings) do
        local name=lookup(b.name)
        if type(name)~='string' or name=='' or name:find('[A-Za-z{}]') or not utf8.len(name) then name=b.name end
        if b.quote then name='「'..name..'」' end
        text=replace(text,b.slot,name)
    end
    return text
end

-- Bind only names supplied by this unit's real deity references. An arbitrary
-- English suffix must never become an approved literal identity.
function mask_need(source,deities)
    if type(source)~='string' or #source>4096 or source:find('[{}%[%]]') then return nil end
    local subject=source:match('^(%a+) is ')
    if subject~='He' and subject~='She' and subject~='It' then return nil end
    for i,name in ipairs(deities or {}) do
        if i>128 then return nil end -- Two spellings for at most 64 real references.
        if type(name)=='string' and name~='' and #name<=512 and utf8.len(name) and not name:find('[{}%[%]\r\n]') then
            for _,prefix in ipairs({' after being unable to pray to ',' after communing with '}) do
                local tail=prefix..name..'.'
                if source:sub(-#tail)==tail then
                    return source:sub(1,#source-#name-1)..'{DEITY_NAME}.',{{slot='{DEITY_NAME}',name=name,count=1}}
                end
            end
        end
    end
end
