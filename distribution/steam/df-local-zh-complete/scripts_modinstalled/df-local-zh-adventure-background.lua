--@module=true
-- Complete creation prose with identities verified against the selected world data.
local hearth='You are a newly-minted hearthperson of the great {ADV_LEADER} in {ADV_SITE}, a {ADV_SITE_KIND}.  Destiny is calling!'
local regular='You are a {ADV_JOB} in {ADV_SITE}, a {ADV_SITE_KIND}, and you have never strayed far from home.'
local function safe(s,limit)
    return type(s)=='string' and #s>0 and #s<=limit and utf8.len(s) and not s:find('[{}%[%]\0-\31\127]')
end
local function pattern(s) return (s:gsub('(%W)','%%%1')) end
local function chinese(s)
    return safe(s,4096) and not s:find('[A-Za-z]')
end
function translate(source,site,leaders,lookup)
    if not safe(source,4096) or not safe(site,512) or type(leaders)~='table' or #leaders>64 then return nil end
    local key,values,kind
    for _,leader in ipairs(leaders) do
        if safe(leader,512) then
            kind=source:match('^You are a newly%-minted hearthperson of the great '..pattern(leader)..' in '..pattern(site)..', a (.-)%.  Destiny is calling!$')
            if kind then key=hearth;values={ADV_LEADER=leader,ADV_SITE=site};break end
        end
    end
    if not key then
        local job
        job,kind=source:match('^You are an? (.-) in '..pattern(site)..', a (.-), and you have never strayed far from home%.$')
        if not job then return nil end
        local translated_job=lookup(job)
        if not chinese(translated_job) then return nil end
        key=regular;values={ADV_JOB=translated_job,ADV_SITE=site}
    end
    local site_kind=lookup(kind)
    if not chinese(site_kind) then return nil end
    values.ADV_SITE_KIND=site_kind
    local translated=lookup(key)
    if type(translated)~='string' or #translated>4096 or not utf8.len(translated) then return nil end
    local remaining=translated
    for slot in pairs(values) do
        local count;remaining,count=remaining:gsub('{'..slot..'}','')
        if count~=1 then return nil end
    end
    if not chinese(remaining) then return nil end
    return (translated:gsub('{(ADV_%u+_?%u*)}',function(slot) return values[slot] end))
end

-- At most 64 site links / 256 position records on a changed background. All
-- cached values are copied text; no native object survives between polls.
function identities(sheet)
    local site=df.world_site.find(sheet.start_site_id)
    if not site then return nil,{} end
    local name=dfhack.df2utf(dfhack.translation.translateName(site.name,true))
    local leaders,seen={},{}
    local position=sheet.background_start_squad_epp_id
    if position<0 then return name,leaders end
    local examined=0
    for i=0,math.min(#site.entity_links,64)-1 do
        local entity=df.historical_entity.find(site.entity_links[i].entity_id)
        if entity then
            local assignments=entity.positions.assignments
            for j=0,#assignments-1 do
                examined=examined+1;if examined>256 then return name,leaders end
                local assignment=assignments[j]
                if assignment.id==position then
                    local figure=df.historical_figure.find(assignment.histfig)
                    if figure then
                        local value=dfhack.df2utf(dfhack.translation.translateName(figure.name,true))
                        if not seen[value] then leaders[#leaders+1]=value;seen[value]=true end
                    end
                    break
                end
            end
        end
    end
    return name,leaders
end
