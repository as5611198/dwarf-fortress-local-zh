local json=require('json')
local files,dictionary={},{}
local active_world='fixture/region1'
local directory='fixture/_localization-work/broker/data/'
local writes=0
local warnings={}
local retry_generation='fixture'
local env=setmetatable({
    dfhack={getDFPath=function() return 'fixture' end,isWorldLoaded=function() return true end,
        getSavePath=function() return active_world end,
        printerr=function(message) warnings[#warnings+1]=message end},
    os={time=function() return 100 end},
    io={open=function(path,mode)
        if mode=='rb' and not files[path] then return end
        local offset=0
        if mode=='wb' then files[path]='' end
        return {
            seek=function(_,kind,position)
                if kind=='end' then offset=#files[path] else offset=position end
                return offset
            end,
            lines=function() return ((files[path] or '')..'\n'):gmatch('(.-)\n') end,read=function() return files[path]:sub(offset+1) end,
            write=function(_,...) files[path]=(files[path] or '')..table.concat({...}); writes=writes+1; return true end,
            close=function() return true end,
        }
    end},
    reqscript=function(name)
        if name=='df-local-zh-status' then return {broker=function()
            return {runtime={retryGeneration=retry_generation}}
        end} end
        if name=='df-local-zh-offline-narrative' then
            local helper=setmetatable({},{__index=_G})
            assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-offline-narrative.lua','t',helper))()
            return helper
        end
        if name=='df-local-zh-paths' then return {
            broker_data=function() return directory:sub(1, -2) end,
            broker_source=function() return 'fixture/_localization-work/broker' end,
            source=function() return 'fixture/_localization-work' end,
            state=function() return 'fixture/_localization-work/broker' end,
        } end
        if name=='df-local-zh-core/mod' then return {
            sync_translate=function(key) return dictionary[key] end,
            async_translate=function() error('Rich prose must bypass native translations') end,
        } end
        assert(name=='df-local-zh-core/native')
        return {local_lookup=function(s) return dictionary[s] end,load_simple_dict=function(_,path)
            for key,text in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionary[key]=text end
        end}
    end,
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-runtime.lua','t',env))()
local source='{{DFL0}} arrived in 12.'
local links={{type=0,id=20,text='Vadane'}}
assert(not env.paragraph_lookup(source,links,20))
local request=json.decode(files[directory..'runtime-requests.jsonl'])
assert(request.kind=='legends-paragraph' and request.subjectId==20 and request.links[1].id==20)
local first_writes=writes
for _=1,10 do assert(not env.paragraph_lookup(source,links,20)) end
assert(writes==first_writes, 'Pending rich paragraphs must not duplicate queued requests')
local key='DFLIVE_'..string.rep('0',64)
files[directory..'runtime-responses.jsonl']=json.encode({world=active_world,text=source,
    translation='瓦丹於12年抵達。',key=key},{pretty=false})..'\n'
env.poll()
assert(not env.paragraph_lookup(source,links,20), 'A generic legacy response must not satisfy rich prose')
local boundary=env.reqscript('df-local-zh-offline-narrative')
assert(boundary.valid_result(source,links,
    {translation='{{DFL0}}於12年抵達。',links={{translation='荒霧瓦丹'}}}),
    'The boundary must accept a complete valid rich paragraph')
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world=active_world,text=source,translation='{{DFL0}}於12年抵達。',
        key=key,kind='legends-paragraph',subjectId=20,requestLinks=links,namePolicy='native-v2',
        links={{translation='荒霧瓦丹'}}},{pretty=false})..'\n'
env.poll()
local result=assert(env.paragraph_lookup(source,links,20))
assert(result.links[1].translation=='荒霧瓦丹')
local corrupt={
    '{{DFT0}}抵達。', '{{DFL1}}抵達。', '{{DFL0}}{{DFL0}}抵達。',
    '{{DFL00}}抵達。', '抵達。', '{{DFL0}}抵達。[C:evil]',
}
for _,translation in ipairs(corrupt) do
    files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
        json.encode({world=active_world,text=source,translation=translation,key=key,
            kind='legends-paragraph',subjectId=20,requestLinks=links,namePolicy='native-v2',
            links={{translation='壞回應'}}},{pretty=false})..'\n'
    env.poll()
    local retained=assert(env.paragraph_lookup(source,links,20))
    assert(retained.translation=='{{DFL0}}於12年抵達。' and retained.links[1].translation=='荒霧瓦丹',
        'Malformed rich slots must not replace a valid paragraph or reach the renderer: '..translation)
end
for _,label in ipairs({'{{DFT0}}','bad[C:evil]','bad\0label',string.rep('名',2001)}) do
    files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
        json.encode({world=active_world,text=source,translation='{{DFL0}}於12年抵達。',key=key,
            kind='legends-paragraph',subjectId=20,requestLinks=links,namePolicy='native-v2',
            links={{translation=label}}},{pretty=false})..'\n'
    env.poll()
    assert(env.paragraph_lookup(source,links,20).links[1].translation=='荒霧瓦丹',
        'Invalid rich link labels must not enter rendering')
end
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world=active_world,text=source,translation='12年，{{DFL0}}抵達。',key=key,
        kind='legends-paragraph',subjectId=20,requestLinks=links,namePolicy='native-v2',
        links={{translation='新譯名𠮷'}}},{pretty=false})..'\n'
env.poll()
assert(env.paragraph_lookup(source,links,20).links[1].translation=='新譯名𠮷',
    'Valid rows following rejected rich records must still advance and restore')
assert(#warnings>0 and warnings[1]:find('invalid or oversized rows',1,true),
    'Rejected rich records must use the throttled journal diagnostic')
local local_source='In 125, {{DFL0}} was created by {{DFL1}}'
dictionary[local_source]='125年，{{DFL1}}創造了{{DFL0}}。'
local local_links={{type=3,id=7,text='The Gate'},{type=0,id=20,text='Urist.'}}
local before_local=writes
env.configure({apiEnabled=false})
local immediate,status=env.paragraph_lookup(local_source,local_links,20)
assert(status=='ready' and immediate.translation==dictionary[local_source])
assert(immediate.links[1].translation=='The Gate' and immediate.links[2].translation=='Urist')
assert(writes==before_local,'Cold local narrative must not queue or write files')
local unknown='{{DFL0}} performed an unknown ritual.'
local fallback,fallback_status=env.paragraph_lookup(unknown,links,20)
assert(fallback_status=='ready' and fallback.translation==unknown and fallback.links[1].translation=='Vadane',
    'With AI disabled, unknown prose must retain readable original text instead of pending forever')
assert(fallback.native_fallback==true,
    'Original fallback must be identified so the reader retains native span colors')
assert(writes==before_local,'AI-disabled fallback must not create a background request')
local literal_template='{{DFT0}}, only daughter, b. 95'
dictionary[literal_template]='{{DFT0}}：獨生女，生於95年。'
local literal_ready,literal_status=env.paragraph_lookup('Urist 𠮷, only daughter, b. 95',{},20,
    literal_template,{{text='Urist 𠮷',color=9}})
assert(literal_status=='ready' and not literal_ready.native_fallback and
    literal_ready.translation==dictionary[literal_template] and
    literal_ready.literals[1].translation=='Urist 𠮷',
    'A literal native name must translate locally with zero fabricated request links')
assert(writes==before_local,'Local text slots must never write a provider request')
assert(select(2,env.paragraph_lookup(literal_template,{},20))=='invalid',
    'Internal text slots cannot enter the rich request protocol')
env.configure({apiEnabled=true})
local other={{type=0,id=21,text='Vadane'}}
assert(not env.paragraph_lookup(source,other,20), 'Same text with another link ID must use a separate result')
local site_source='Kacufensast Nedorsiga'
assert(not env.request(site_source,1,'site'))
local site_request
for line in files[directory..'runtime-requests.jsonl']:gmatch('([^\n]+)\n') do
    local ok,row=pcall(json.decode,line)
    if ok and row.kind=='legends-name' then site_request=row end
end
assert(site_request and site_request.entityKind=='site' and site_request.entityId==1 and
    site_request.namePolicy=='native-v2')
local visible_id=env.visibility_id(site_source,1,'site')
assert(site_request.visibilityId==visible_id)
assert(env.set_visible({visible_id}))
local visible=json.decode(files[directory..'runtime-visible.json'])
assert(visible.world==active_world and visible.ids[1]==visible_id)
local stable_writes=writes
assert(env.set_visible({visible_id}) and writes==stable_writes,
    'An unchanged viewport must not rewrite visibility state')
local another='Other Native'
local other_id=env.visibility_id(another,2,'site')
assert(env.set_visible({visible_id,other_id}))
local _,status=env.request(another,2,'site')
assert(status=='queued')
assert(env.set_visible({visible_id}))
assert(env.set_visible({visible_id,other_id}))
_,status=env.request(another,2,'site')
assert(status=='queued','Returning to a dropped row should enqueue immediately')
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world=active_world,text=site_source,translation='卡庫芬薩斯特 涅多爾西加',
        key=key,kind='legends-name',entityKind='site',entityId=1,namePolicy='native-v2'},
        {pretty=false})..'\n'
env.poll()
assert(env.lookup(site_source,1,'site')==key,'Typed site response must restore under site identity')
assert(not env.lookup(site_source,1),'Site translation cannot satisfy figure identity')
local alias=assert(env.literal_key('荒霧瓦丹'))
assert(dictionary[alias]=='荒霧瓦丹' and env.literal_key('荒霧瓦丹')==alias)
assert(not env.literal_key('{{DFL0}}'), 'Unresolved tokens must never become visible text')
local rejected_source='{{DFL0}} performed a forbidden ritual.'
assert(select(2,env.paragraph_lookup(rejected_source,links,20))=='queued')
local rejected_id=env.paragraph_visibility_id(rejected_source,links,20)
files[directory..'runtime-failures.jsonl']=json.encode({world=active_world,text=rejected_source,
    kind='legends-paragraph',visibilityId=rejected_id,terminal=true,reason='format token mismatch',
    retryGeneration=retry_generation},{pretty=false})..'\n'
env.poll()
local writes_at_failure=writes
local rejected,status,reason=env.paragraph_lookup(rejected_source,links,20)
assert(not rejected and status=='failed' and reason=='format token mismatch',
    'A terminal rich failure must reveal original text instead of staying pending')
assert(writes==writes_at_failure,'Terminal rich failure must not append duplicate requests')
retry_generation='new-profile'
env.poll()
assert(select(2,env.paragraph_lookup(rejected_source,links,20))=='queued',
    'A changed provider generation must permit an immediate retry after terminal rejection')
active_world='fixture/region2'
assert(not env.paragraph_lookup(source,links,20), 'World changes must discard rich response identity')
print('Rich runtime queue, response identity, native bypass, and literal aliases verified')
