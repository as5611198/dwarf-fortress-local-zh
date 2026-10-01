--@module=true
local json=require('json')
local paths=reqscript('df-local-zh-paths')
local unit_prewarm=reqscript('df-local-zh-unit-prewarm')
local visible=reqscript('df-local-zh-visible-text')
local active_world,groups,group_cursor,seen,queue,cursor,counts,errors
local unit_cursors={}
local function field(value,name)
    local ok,result=pcall(function() return value[name] end)
    return ok and result or nil
end
local function reset()
    groups,group_cursor,seen,queue,cursor,counts,errors={},1,{},{},1,{},{}
    unit_cursors={}
end
reset()

local function log(row)
    local f=io.open(paths.broker_data()..'/prefetch-sources.jsonl','ab')
    if f then f:write(json.encode(row,{pretty=false})..'\n');f:close() end
end

local function add(text,category,field_id)
    if type(text)~='string' or text=='' then return end
    text=dfhack.df2utf(text):gsub('%[C:%d+:%d+:%d+%]',''):gsub('%[P%]',''):gsub('%[R%]','')
    if unit_prewarm.fixed_translation(text) then return end
    if #text>8000 or not text:match('[A-Za-z]') or seen[text] or #queue>=128 then return end
    if text:match('^L[%w]+_*$') and text:find('%d') or text:find('DFLIVE_',1,true) then return end
    seen[text]=true;queue[#queue+1]={text=text,category=category,field_id=field_id}
    counts[category]=counts[category] or {collected=0,ready=0}
    counts[category].collected=counts[category].collected+1
    log({version=1,world=active_world,text=text,type=category,field_id=field_id})
end

local function strings(value,category,id)
    if type(value)=='string' then add(value,category,id);return end
    if not value then return end
    for index=0,math.min(#value,8)-1 do add(value[index],category,id) end
end

local function building(value,category)
    add(dfhack.buildings.getName(value),category,'buildings.name')
end

local function work(value,category)
    local title=field(value,'title')
    if title then add(title,category,'works.title')
    else
        local name=field(value,'name')
        if name then add(dfhack.translation.translateName(name,true),category,'works.name') end
    end
end

local function material(value,index)
    if not dfhack.matinfo or not dfhack.matinfo.decode then return end
    local info=dfhack.matinfo.decode(value,index)
    if info then strings(field(info.material,'state_name'),'raws','local_material.state_name') end
end

local function referenced_work(kind,id)
    if type(id)~='number' or id<0 then return end
    local object=kind and kind.find(id)
    if object then work(object,'works') end
end

local function item(value,category)
    add(dfhack.items.getReadableDescription(value),category,'items.readable_description')
    if dfhack.items.getDescription then add(dfhack.items.getDescription(value,0,true),category,'items.description') end
    material(value)
    local improvements=field(value,'improvements')
    for i=0,math.min(improvements and #improvements or 0,8)-1 do
        local improvement=improvements[i]
        if improvement._type==df.itemimprovement_pagesst or improvement._type==df.itemimprovement_writingst then
            for j=0,math.min(#improvement.contents,8)-1 do
                referenced_work(df.written_content,improvement.contents[j])
            end
        end
    end
    local refs=field(value,'general_refs')
    for i=0,math.min(refs and #refs or 0,8)-1 do
        if refs[i]._type==df.general_ref_is_artifactst then
            referenced_work(df.artifact_record,refs[i].artifact_id)
        end
    end
end

local function preference(pref)
    local kind=df.unitpref_type[pref.type]
    local types={LikePoeticForm={df.poetic_form,'poetic_form_id'},
        LikeMusicalForm={df.musical_form,'musical_form_id'},LikeDanceForm={df.dance_form,'dance_form_id'}}
    local form=types[kind]
    if form then referenced_work(form[1],pref[form[2]])
    elseif kind=='LikeMaterial' or kind=='LikeFood' then material(pref.mattype,pref.matindex)
    else
        local raws=df.global.world.raws
        local object
        if kind=='LikeColor' then object=raws.descriptors.colors[pref.color_id]
        elseif kind=='LikeShape' then object=raws.descriptors.shapes[pref.shape_id]
        elseif kind=='LikeCreature' or kind=='HateCreature' then object=raws.creatures.all[pref.creature_id]
        elseif kind=='LikePlant' or kind=='LikeTree' then object=raws.plants.all[pref.plant_id] end
        if object then
            strings(field(object,'name'),'raws','citizen_preference.name')
            strings(field(object,'prefstring'),'raws','citizen_preference.prefstring')
        end
    end
end

local function unit(value,category)
    if not dfhack.units.isCitizen(value) then return end
    add(dfhack.units.getProfessionName(value),category,'units.profession')
    if dfhack.units.getRaceReadableName then add(dfhack.units.getRaceReadableName(value),category,'units.race') end
    local status=field(value,'status')
    local soul=status and field(status,'current_soul')
    if not soul then return end
    local skills=field(soul,'performance_skills')
    local parts={{vector=field(soul,'preferences'),collect=preference}}
    for _,row in ipairs({{'poetic_forms',df.poetic_form},{'musical_forms',df.musical_form},{'dance_forms',df.dance_form}}) do
        parts[#parts+1]={vector=skills and field(skills,row[1]),kind=row[2]}
    end
    local state=unit_cursors[value.id] or {part=1,index=0}
    unit_cursors[value.id]=state
    local collected=0
    -- Read at most two actual references, including newly learned local works.
    for _=1,6 do
        local part=parts[state.part]
        if not part.vector or state.index>=#part.vector then
            state.part=state.part%#parts+1;state.index=0
        else
            local object=part.vector[state.index];state.index=state.index+1
            if part.collect then part.collect(object) else referenced_work(part.kind,object.id) end
            collected=collected+1
            if collected==2 then break end
        end
    end
end

local function initialize()
    local w=df.global.world
    local function group(category,vector,collect)
        if vector then groups[#groups+1]={category=category,vector=vector,collect=collect,index=0,passes=0} end
    end
    group('citizens',w.units.active,unit)
    local other=field(w.items,'other')
    group('items',other and field(other,'IN_PLAY'),item)
    group('buildings',w.buildings.all,building)
end

function observe(text,category,field_id)
    local current=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if not current or not dfhack.isMapLoaded() then return end
    if current~=active_world then active_world=current;reset();initialize() end
    add(text,category,field_id)
end

function poll(runtime)
    local current=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    if current~=active_world then
        active_world=current;reset()
        if current and dfhack.isMapLoaded() then initialize() end
    end
    if not current or not dfhack.isMapLoaded() then return end
    if #groups==0 then initialize() end
    visible.poll(runtime)
    local status=reqscript('df-local-zh-status')
    if not status.background_allowed() then return end
    if status.claim_background and not status.claim_background('sources') then return end
    local b=status.broker();local r=b and b.runtime or {}
    if (r.backgroundQueued or 0)+(b and b.backgroundQueued or 0)>24 then return end
    if #queue<128 then
        for _=1,3 do
            if #groups==0 then break end
            if group_cursor>#groups then group_cursor=1 end
            local g=groups[group_cursor];group_cursor=group_cursor+1
            if g.index>=#g.vector then g.index=0;g.passes=g.passes+1 end
            if #g.vector>0 then
                local ok,err=pcall(g.collect,g.vector[g.index],g.category)
                if not ok and not errors[g.category..tostring(err)] then
                    errors[g.category..tostring(err)]=true
                    log({world=active_world,type='capability',field_id=g.category,error=tostring(err)})
                end
                g.index=g.index+1
            end
        end
    end
    for _=1,2 do
        if #queue==0 then break end
        if cursor>#queue then cursor=1 end
        local row=queue[cursor];cursor=cursor+1
        if not row.ready and runtime.prefetch(row.text) then
            counts[row.category].ready=counts[row.category].ready+1
            log({version=1,world=active_world,text=row.text,type=row.category,
                field_id=row.field_id,status='ready'})
            table.remove(queue,cursor-1);cursor=cursor-1
        end
    end
end

function status()
    local result={world=active_world,collected=0,ready=0,categories=counts,errors=0,scope='local-observed'}
    for _,row in pairs(counts) do
        result.ready=result.ready+row.ready;result.collected=result.collected+row.collected
    end
    for _ in pairs(errors) do result.errors=result.errors+1 end
    result.pending=result.collected-result.ready
    result.visible=visible.status()
    return result
end

function start(runtime)
    runtime_bridge=runtime
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-prefetch',20,'frames',function()
        local ok,err=pcall(poll,runtime_bridge)
        if not ok then dfhack.printerr('df-local-zh-prefetch: '..tostring(err)) end
    end)
end

function stop() require('repeat-util').cancel('df-local-zh-prefetch') end
