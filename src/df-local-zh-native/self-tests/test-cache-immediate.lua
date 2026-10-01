local json=require('json')
local root=dfhack.getDFPath()
local directory='fixture/immediate/'
local world='fixture/fortress'
local text='She enjoys company.'
local translated='她喜歡有人陪伴。'
local saved_key='L000123_________________'
local files={}
files[directory..'native-prewarm.json']=json.encode({version=1,world=world,
    rows={{text='Known static label',translation='已知靜態標籤',kind='plain'}},unit={}},
    {pretty=false})
files[directory..'unit-display-cache.jsonl']=json.encode({version=1,world=world,
    kind='source',text=text,translation=translated},{pretty=false})..'\n'..
    json.encode({version=1,world=world,kind='fragment',translation=translated,
        color=71,key=saved_key},{pretty=false})..'\n'
for i=1,1000 do
    files[directory..'unit-display-cache.jsonl']=files[directory..'unit-display-cache.jsonl']..
        json.encode({version=1,world=world,kind='fragment',translation='既有譯文'..i,
            color=7,key='L'..string.format('%06d',i+1000)..'_________'},{pretty=false})..'\n'
end
local dictionary,queued={},{}
local preferred={}
local requests=0
local ready={[saved_key]=translated,['[C:7:0:1]'..saved_key]='[C:7:0:1]'..translated}
local env=setmetatable({
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return world end},
    io={open=function(path,mode)
        if mode=='rb' and not files[path] then return end
        if mode=='wb' then files[path]='' end
        local offset=0
        return {seek=function(_,kind,value) offset=kind=='end' and #files[path] or value;return offset end,
            read=function() return files[path]:sub(offset+1) end,
            write=function(_,...)
                files[path]=(files[path] or '')..table.concat({...})
                if path==directory..'runtime-requests.jsonl' then requests=requests+1 end
                return true
            end,close=function() return true end}
    end},
    reqscript=function(name)
        if name=='df-local-zh-reviewed-text' then return {translation=function() return nil end} end
        if name=='df-local-zh-paths' then return {broker_data=function() return directory:sub(1,-2) end} end
        if name=='df-local-zh-core/mod' then return {
            sync_translate=function(key) return dictionary[key] end,
            async_translate=function(key) queued[key]=true;return ready[key] end}
        end
        assert(name=='df-local-zh-core/native',name)
        return {official_library_lookup=function(source) return preferred[source] end,load_simple_dict=function(_,path)
            for key,value in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionary[key]=value end
        end}
    end,
},{__index=_G})
assert(loadfile((...) or dfhack.findScript('df-local-zh-runtime'),'t',env))()
env.poll()
local n=0;for _ in pairs(queued) do n=n+1 end
assert(n<=8,'Restart must not flood native workers with unused saved display aliases: '..n)
assert(env.translation(text)==translated,'Shared lookup must use persisted prose immediately')
preferred[text]='官方優先譯文。'
assert(env.translation(text)==preferred[text] and env.unit_translation(text)==preferred[text],
    'Official/native pins must precede persisted Lua model/display prose')
preferred[text]=nil
assert(requests==0,'A persisted translation must not be queued for inference again')
local shortcut=assert(env.literal_key('r: '),'Owned literal shortcuts must permit Latin key names')
assert(dictionary[shortcut]=='r: ','Literal shortcut must preserve the actual key')
assert(requests==0,'Literal shortcuts must not enqueue an API request')
local completed=false
env.on_translation(text,function(value) completed=value==translated end)
assert(completed,'A completed saved translation must invoke its callback immediately')
local key=assert(env.colored_key(translated,string.char(71)),
    'A completed saved palette must be available on its first lookup')
assert(key==saved_key,'Restart must reuse the verified saved palette key')
local before=0;for _ in pairs(queued) do before=before+1 end
assert(env.translation('Known static label')=='已知靜態標籤',
    'A known static dictionary entry must return synchronously on its first lookup')
local key,status=env.request('Known static label',nil,nil,'background')
assert(key=='Known static label' and status=='ready')
local static_done=false
env.on_translation('Known static label',function(value) static_done=value=='已知靜態標籤' end)
assert(static_done,'Known static dictionary callbacks must complete immediately')
local after=0;for _ in pairs(queued) do after=after+1 end
assert(after==before and requests==0,
    'A static dictionary hit must not invoke native async lookup or append a Broker request')
world='fixture/other'
env.poll()
assert(not env.translation(text),'Persisted text must remain isolated to its world')
print('PASS immediate shared cache, first-lookup palette restoration and bounded restart work')

world='fixture/fortress'
files[directory..'native-prewarm-unit.json']=json.encode({version=1,world=world,language='zh-Hant',
    unit={sources={{text='He needs solitude.',translation='他需要獨處。'}},names={},fragments={}}})
local original_open=env.io.open
env.io.open=function(path,mode)
    assert(path~=directory..'native-prewarm.json','Compact restart must not decode the bulk manifest')
    return original_open(path,mode)
end
assert(loadfile((...) or dfhack.findScript('df-local-zh-runtime'),'t',env))()
env.poll()
assert(env.translation('He needs solitude.')=='他需要獨處。','Compact unit export must restore known prose')
print('PASS compact unit restart without bulk JSON parsing')
