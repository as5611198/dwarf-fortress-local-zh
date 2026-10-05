--@module=true
local function slots(text,count,literal_count)
    local seen,total,literal_total={},0,0
    local plain=text:gsub('{{DF([LT])(%d+)}}',function(kind,index)
        local n=tonumber(index)
        local limit=kind=='L' and count or (literal_count or 0)
        if tostring(n)~=index or n>=limit or seen[kind..index] then return '{invalid}' end
        seen[kind..index]=true
        if kind=='L' then total=total+1 else literal_total=literal_total+1 end
        return ''
    end)
    return total==count and literal_total==(literal_count or 0) and not plain:find('[{}%[%]]'),plain
end
function valid(source,links)
    if type(source)~='string' or #source>8000 or not utf8.len(source) or type(links)~='table' or #links>64 then return false end
    for _,link in ipairs(links) do
        if type(link)~='table' or type(link.id)~='number' or link.id<0 or link.id~=math.floor(link.id) or
            type(link.type)~='number' or link.type<0 or link.type>11 or link.type~=math.floor(link.type) or
            link.id>=math.huge or type(link.text)~='string' or #link.text==0 or #link.text>2000 or not utf8.len(link.text) or
            link.text:find('[{}%[%]%z\1-\31\127]') then return false end
    end
    return slots(source,#links)
end
function valid_result(source,links,result)
    if not valid(source,links) or type(result)~='table' or type(result.translation)~='string' or
            #result.translation==0 or #result.translation>16000 or not utf8.len(result.translation) or
            result.translation:find('[%z\1-\31\127]') or type(result.links)~='table' or #result.links~=#links then return false end
    if not slots(result.translation,#links) then return false end
    for _,link in ipairs(result.links) do
        if type(link)~='table' or type(link.translation)~='string' or #link.translation==0 or
                #link.translation>6000 or not utf8.len(link.translation) or
                link.translation:find('[{}%[%]%z\1-\31\127]') then return false end
    end
    return true
end
local function caption(text,kind,lookup)
    if kind~=0 or (text:sub(1,4)~='the ' and text:sub(1,4)~='The ') then return text end
    local body=text:sub(5)
    local stops={}
    for position in body:gmatch('() ') do
        stops[#stops+1]=position-1
        if #stops>=8 then break end
    end
    if #stops<8 then stops[#stops+1]=#body end
    for i=#stops,1,-1 do
        local stop=stops[i]
        local suffix=body:sub(stop+1)
        -- A lower-case suffix is still a race/caste descriptor, not a native
        -- proper name. Do not shorten an unknown "badger brute" to "badger".
        local name_boundary=suffix=='' or suffix:match('^ [A-Z]') or
            suffix:sub(1,1)==' ' and (suffix:byte(2) or 0)>=128
        local race=name_boundary and lookup('DFL_LEGENDS_RACE:'..body:sub(1,stop))
        if type(race)=='string' and #race>0 and #race<=512 and utf8.len(race) and
                not race:find('[A-Za-z{}%[%]%z\1-\31\127]') then
            return race..body:sub(stop+1)
        end
    end
    return text
end
local function translated(source,links,lookup,literals)
    if type(lookup)~='function' then return nil end
    local translated=lookup(source)
    if type(translated)~='string' or #translated>16000 or not utf8.len(translated) then return nil end
    local ok,plain=slots(translated,#links,literals and #literals)
    if not ok or plain:find('[A-Za-z]') then return nil end
    local results={}
    for i,link in ipairs(links) do
        -- Only a typed vanilla race label may alter a figure caption. The name
        -- suffix and all click identities stay literal; generic terms/caches
        -- cannot reinterpret a generated proper name.
        local text=link.text
        if source:sub(-#('{{DFL'..(i-1)..'}}'))=='{{DFL'..(i-1)..'}}' then text=text:gsub('%.$','') end
        results[i]={translation=caption(text,link.type,lookup)}
    end
    local result={translation=translated,links=results}
    if literals then
        result.literals={}
        for i,literal in ipairs(literals) do result.literals[i]={translation=literal.text} end
    end
    return result
end
function translate(source,links,lookup)
    if not valid(source,links) then return nil end
    return translated(source,links,lookup)
end
function literal_source(source,literals)
    if type(source)~='string' or #source>8000 or not utf8.len(source) or
            type(literals)~='table' or #literals<1 or #literals>8 then return nil end
    for _,literal in ipairs(literals) do
        if type(literal)~='table' or type(literal.text)~='string' or #literal.text==0 or
                #literal.text>2000 or not utf8.len(literal.text) or literal.text:find('[{}%[%]%z\1-\31\127]') then return nil end
    end
    return source:gsub('{{DFT(%d+)}}',function(index)
        local literal=literals[tonumber(index)+1]
        return literal and literal.text or '{invalid}'
    end)
end
function translate_literal(source,links,literals,lookup)
    local original=literal_source(source,literals)
    if not original or not valid(original,links) or not slots(source,#links,#literals) then return nil end
    return translated(source,links,lookup,literals)
end
