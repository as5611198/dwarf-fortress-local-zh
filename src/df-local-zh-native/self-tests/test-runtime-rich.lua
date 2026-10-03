local json=require('json')
local files,dictionary={},{}
local active_world='fixture/region1'
local directory='fixture/_localization-work/broker/data/'
local writes=0
local env=setmetatable({
    dfhack={getDFPath=function() return 'fixture' end,isWorldLoaded=function() return true end,
        getSavePath=function() return active_world end},
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
        return {load_simple_dict=function(_,path)
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
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world=active_world,text=source,translation='{{DFL0}}於12年抵達。',
        key=key,kind='legends-paragraph',subjectId=20,requestLinks=links,namePolicy='native-v2',
        links={{translation='荒霧瓦丹'}}},{pretty=false})..'\n'
env.poll()
local result=assert(env.paragraph_lookup(source,links,20))
assert(result.links[1].translation=='荒霧瓦丹')
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
active_world='fixture/region2'
assert(not env.paragraph_lookup(source,links,20), 'World changes must discard rich response identity')
print('Rich runtime queue, response identity, native bypass, and literal aliases verified')
