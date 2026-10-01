local native=reqscript('df-local-zh-core/native')
local runtime=reqscript('df-local-zh-runtime')
local paths=reqscript('df-local-zh-paths')
local json=require('json')
local file=assert(io.open(paths.source()..'/self-tests/arena-corrections.json','rb'))
local fixtures=json.decode(file:read('*a'));file:close()
local original=runtime.language()
local result={languages={}}
local ok,err=xpcall(function()
    for _,language in ipairs({'zh-Hant','zh-Hans'}) do
        native.set_lang_tag(language)
        native.load_simple_dict(language,paths.source()..'/dfi18n-data/simple/'..language..'/zzzzzzz-creature-names.csv')
        native.load_simple_dict(language,paths.source()..'/dfi18n-data/simple/'..language..'/zzzzzzzz-arena-corrections.csv')
        local _,_,before=native.core_cache_metrics()
        local count=0
        local function check(source,expected)
            assert(native.cache_lookup(source)==expected,language..': lookup '..source)
            assert(native.async_translate(source)==expected,language..': first repaint '..source)
            count=count+1
        end
        for _,row in ipairs(fixtures[language]) do check(row.text,row.translation) end
        local hant=language=='zh-Hant'
        check('[C:6:0:1].Needs setting',hant and '[C:6:0:1].需要復位' or '[C:6:0:1].需要复位')
        check('Aardvark Man 1','土豚人 1')
        check('Alligator Man 1',hant and '短吻鱷人 1' or '短吻鳄人 1')
        check('Grizzly Bear Man 2','灰熊人 2')
        check('Dragon 1',hant and '巨龍 1' or '巨龙 1')
        for _,source in ipairs({'{copper mace}','{silver war hammer}','☼{silver war hammer}☼','XX{copper mace}XX'}) do
            local plain=source:find('copper',1,true) and 'copper mace' or 'silver war hammer'
            local expected=assert(native.cache_lookup(plain),'Equipment noun '..plain)
            local first,last=assert(source:find(plain,1,true))
            check(source,source:sub(1,first-1)..expected..source:sub(last+1))
        end
        local _,_,after=native.core_cache_metrics()
        assert(before==after,'Static corrections submitted model workers')
        result.languages[language]={checks=count,worker_submissions_added=after-before}
    end
    native.set_lang_tag(original)
    for _,source in ipairs({'Aardvark Man 1','Alligator Man 1','Grizzly Bear Man 2','Dragon 1'}) do
        assert(runtime.unit_name_translation(source)==reqscript('df-local-zh-creature-names').translation(source,original))
    end
end,debug.traceback)
native.set_lang_tag(original)
result.pass=ok;result.error=not ok and tostring(err) or nil
file=assert(io.open(paths.broker_data()..'/arena-corrections-live.json','wb'))
file:write(json.encode(result,{pretty=true}));file:close()
print('ARENA_CORRECTIONS '..json.encode(result,{pretty=false}))
assert(ok,err)
