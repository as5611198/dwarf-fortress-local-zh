--@module=true
-- Bind ephemeral journal titles by their public string addresses. Save and UI
-- strings stay untouched; only prose whose identities match actual IDs is used.
local function safe(value,limit)
    return type(value)=='string' and #value>0 and #value<=limit and utf8.len(value)
        and not value:find('[{}%[%]\0-\31\127]')
end
local function translate_title(source,figure,site,suffix,lookup)
    if not safe(figure,512) or not safe(site,512) or
        source~=figure..suffix..site then return nil end
    local template='{JOURNAL_FIGURE}'..suffix..'{JOURNAL_SITE}'
    local translated=lookup(template)
    if type(translated)~='string' or #translated>2048 or not utf8.len(translated) then return nil end
    local remainder,a=translated:gsub('{JOURNAL_FIGURE}','')
    local b;remainder,b=remainder:gsub('{JOURNAL_SITE}','')
    if a~=1 or b~=1 or not safe(remainder,1024) or remainder:find('[A-Za-z]') then return nil end
    return (translated:gsub('{JOURNAL_FIGURE}',function() return figure end)
        :gsub('{JOURNAL_SITE}',function() return site end))
end
function translate_presence(source,figure,site,lookup)
    return translate_title(source,figure,site,"'s presence in ",lookup)
end

local function identities(entry)
    if entry.type~=1 or not entry.rumor then return end
    local actor,site_id,suffix
    if entry.rumor.type==4 then
        local beast=entry.rumor.data.beast
        if not beast or beast.region_id~=-1 or beast.histfig_id<0 or beast.site_id<0 then return end
        actor=df.historical_figure.find(beast.histfig_id)
        site_id=beast.site_id;suffix="'s presence in "
    elseif entry.rumor.type==5 or entry.rumor.type==6 then
        local rumor=entry.rumor.type==5 and entry.rumor.data.group or entry.rumor.data.harass
        if not rumor or rumor.entity_id<0 or rumor.site_id<0 then return end
        actor=df.historical_entity.find(rumor.entity_id)
        site_id=rumor.site_id
        suffix=entry.rumor.type==5 and "'s presence in " or "'s harassment of "
    else return end
    local site=df.world_site.find(site_id)
    if not actor or not site then return end
    return dfhack.df2utf(dfhack.translation.translateName(actor.name,true)),
        dfhack.df2utf(dfhack.translation.translateName(site.name,true)),suffix
end

-- ASCII uses one cell, other codepoints conservatively use two. Split only at
-- complete UTF-8 scalar boundaries; if every row cannot fit, keep native prose.
local function split(value,width,count)
    local rows,parts,cells={},{},0
    for _,code in utf8.codes(value) do
        local n=code<128 and 1 or 2
        if n>width then return end
        if cells+n>width then
            rows[#rows+1]=table.concat(parts);parts={};cells=0
            if #rows>=count then return end
        end
        parts[#parts+1]=utf8.char(code);cells=cells+n
    end
    rows[#rows+1]=table.concat(parts)
    while #rows<count do rows[#rows+1]='' end
    return rows
end

local function append_rows(result,native,translated,width,literals)
    local rows=split(translated,width,#native)
    if not rows or #result+#native>256 then return end
    for i,row in ipairs(native) do
        row.translation=rows[i];row.width=width
        if literals then row.verified_name_literals=true end
        result[#result+1]=row
    end
end

local function prose(source,lookup)
    if not safe(source,4096) then return end
    local translated=lookup(source)
    if safe(translated,4096) and not translated:find('[A-Za-z]') then return translated end
end

local list_modes={
    [2]={'histfig_entry','scroll_position_people'},
    [3]={'site_entry','scroll_position_sites'},
    [4]={'entity_entry','scroll_position_entities'},
    [6]={'bestiary_entry','scroll_position_bestiary'},
}
local function list_bindings(screen,lookup,fields)
    local entries=screen[fields[1]]
    local start=screen[fields[2]]
    if not entries or type(start)~='number' or start<0 or start%1~=0 then return {} end
    local result={}
    for i=start,math.min(#entries-1,start+63) do
        local entry=entries[i]
        local box=entry.main_text_box
        if screen.mode==6 then
            local raw=entry.p_list_name
            local source=dfhack.df2utf(raw)
            local name,suffix=source:match('^(.-)(, .+)$')
            if suffix~=', ♀' and suffix~=', ♂' then name=nil;suffix=nil end
            name=name or source;suffix=suffix or ''
            local translated=prose(name,lookup)
            if translated and #raw>0 and #raw<=240 then
                -- The English name's byte count is not the panel's available
                -- width. Existing body rows provide a conservative lower bound;
                -- reserve both counter numbers, the slash and a separating cell.
                local width=#raw
                if box and #box.text<=128 then
                    local reserve=2*#tostring(#entries)+2
                    for j=0,#box.text-1 do
                        local size=#box.text[j].value
                        if size<=240 then width=math.max(width,size-reserve) end
                    end
                end
                if width>=8 and width<=240 then
                    local _,address=df.sizeof(entry:_field('p_list_name'))
                    append_rows(result,{{address=address,source=source}},translated..suffix,width)
                end
            end
        end
        if box and #box.text<=128 then
            local part,native,width={}, {},0
            local function flush()
                if #native>0 and #native<=16 and width>=8 and width<=240 then
                    local translated=prose(table.concat(part),lookup)
                    if translated then append_rows(result,native,translated,width) end
                end
                part,native,width={}, {},0
            end
            for j=0,#box.text-1 do
                local raw=box.text[j].value
                if raw:match('^%s*$') then flush()
                else
                    local _,address=df.sizeof(box.text[j])
                    local source=dfhack.df2utf(raw)
                    part[#part+1]=source;native[#native+1]={address=address,source=source}
                    width=math.max(width,#raw)
                end
            end
            flush()
        end
        if #result>=256 then break end
    end
    return result
end

function bindings(screen,lookup)
    local fields=list_modes[screen.mode]
    if fields then return list_bindings(screen,lookup,fields) end
    -- Event strings survive in the screen while another tab is visible.
    -- Never resolve their IDs or publish their old positions on another page.
    if screen.mode~=0 then return {} end
    local entries=screen.adventure_log_event
    if not entries then return {} end
    local start=screen.scroll_position_events or 0
    if type(start)~='number' or start%1~=0 then return {} end
    start=math.max(0,start)
    local result={}
    -- The displayed/filter-sorted vector and viewport bound work even when the
    -- world has thousands of rumors. No native objects are retained across polls.
    for i=start,math.min(#entries-1,start+63) do
        local entry=entries[i]
        local source=dfhack.df2utf(entry.summary)
        if source~='' then
            local figure,site,suffix=identities(entry)
            local translated=figure and translate_title(source,figure,site,suffix,lookup)
            if translated then
                local text=entry.p_list_box.text
                local native,width={},0
                if #text>0 and #text<=16 then
                    local joined={}
                    for j=0,#text-1 do
                        local raw=text[j].value
                        if #raw>240 or raw:match('^%s*$') then native={};break end
                        local _,address=df.sizeof(text[j])
                        joined[#joined+1]=dfhack.df2utf(raw)
                        native[#native+1]={address=address,source=dfhack.df2utf(raw)}
                        width=math.max(width,#raw)
                    end
                    if table.concat(joined)~=source then native={} end
                elseif #text==0 and dfhack.df2utf(entry.p_list_name)==source then
                    width=#entry.p_list_name
                    local _,address=df.sizeof(entry:_field('p_list_name'))
                    native={{address=address,source=source}}
                end
                if #native>0 and width>=8 and width<=240 then
                    append_rows(result,native,translated,width,true)
                end
            end
        end
    end
    return result
end
