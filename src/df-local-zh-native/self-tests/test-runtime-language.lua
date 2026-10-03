local json=require('json')
local root=dfhack.getDFPath()
local language='zh-Hant'
local dictionaries={['zh-Hant']={},['zh-Hans']={}}
local files={}
local directory='fixture/language/'
local function localize(text)
    return language=='zh-Hans' and text:gsub('鐵','铁'):gsub('製','制'):gsub('腳','脚'):gsub('譯','译') or text
end
local env=setmetatable({
    dfhack={isWorldLoaded=function() return true end,getSavePath=function() return 'fixture/world' end},
    reqscript=function(name)
        if name=='df-local-zh-reviewed-text' then return {translation=function() return nil end} end
        if name=='df-local-zh-paths' then return {broker_data=function() return directory:sub(1,-2) end} end
        if name=='df-local-zh-core/mod' then return {
            sync_translate=function(key) return dictionaries[language][key] end,
            async_translate=function(key) return dictionaries[language][key] end,
        } end
        assert(name=='df-local-zh-core/native')
        return {localize_text=localize,load_simple_dict=function(lang,path)
            for key,value in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do dictionaries[lang][key]=value end
        end}
    end,
    io={open=function(path,mode)
        if mode=='rb' and not files[path] then return nil end
        local offset=0;if mode=='wb' then files[path]='' end
        return {seek=function(_,kind,position) offset=kind=='end' and #files[path] or position;return offset end,
            lines=function() return ((files[path] or '')..'\n'):gmatch('(.-)\n') end,read=function() return files[path]:sub(offset+1) end,
            write=function(_,...) files[path]=(files[path] or '')..table.concat({...});return true end,
            close=function() return true end}
    end},
},{__index=_G})
local path=(...) or dfhack.findScript('df-local-zh-runtime')
assert(loadfile(path,'t',env))()
assert(type(env.set_language)=='function','runtime language context is required')
local source='An iron goblet.'
files[directory..'unit-display-cache.jsonl']=json.encode({version=1,world='fixture/world',
    kind='source',text=source,translation='鐵製高腳杯。'},{pretty=false})..'\n'
env.poll();assert(env.translation(source)=='鐵製高腳杯。','legacy Hant journal must remain usable')
language='zh-Hans';env.set_language(language,true)
assert(env.translation(source)==nil,'Hant ready data must not enter Hans')
local called=0;env.on_translation(source,function(text) assert(text=='铁制高脚杯。');called=called+1 end)
files[directory..'runtime-responses.jsonl']=json.encode({world='fixture/world',text=source,
    language='zh-Hant',translation='鐵製高腳杯。',key='DFLIVE_'..string.rep('0',64)},{pretty=false})..'\n'
env.poll();assert(called==0,'completion from the previous language must be ignored')
files[directory..'runtime-responses.jsonl']=files[directory..'runtime-responses.jsonl']..
    json.encode({world='fixture/world',language='zh-Hans',text=source,translation='铁制高脚杯。',
        key='DFLIVE_'..string.rep('1',64)},{pretty=false})..'\n'
env.poll();assert(called==1 and env.translation(source)=='铁制高脚杯。')
local key=assert(env.colored_key('鐵製高腳杯',string.char(70)))
assert(dictionaries['zh-Hans']['[C:6:0:1]'..key]=='[C:6:0:1]铁制高脚杯')
assert(files[directory..'unit-display-cache.jsonl']:find('zh-Hans',1,true))
language='zh-Hant';env.set_language(language,true)
assert(env.translation(source)=='鐵製高腳杯。','switching back must restore persisted Hant immediately')
print('PASS runtime language isolation, legacy Hant reuse, captured callback and colored Hans aliases')
