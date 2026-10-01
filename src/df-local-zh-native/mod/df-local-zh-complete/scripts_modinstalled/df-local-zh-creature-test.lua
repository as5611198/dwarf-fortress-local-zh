local native=reqscript('df-local-zh-core/native')
local runtime=reqscript('df-local-zh-runtime')
local paths=reqscript('df-local-zh-paths')
local json=require('json')
local file=assert(io.open(paths.source()..'/self-tests/creature-dictionaries.json','rb'))
local fixtures=json.decode(file:read('*a'));file:close()
local original=runtime.language()
local result={languages={},errors={}}
local ok,err=xpcall(function()
    for _,language in ipairs({'zh-Hant','zh-Hans'}) do
        native.load_simple_dict(language,paths.source()..'/dfi18n-data/simple/'..language..'/zzzzzzz-creature-names.csv')
        native.set_lang_tag(language)
        local _,_,before=native.core_cache_metrics()
        for _,row in ipairs(fixtures[language]) do
            local actual=native.cache_lookup(row.text)
            local expected=row.translation
            if row.text:lower()=='pike' then expected=language=='zh-Hans' and '长枪' or '長槍' end
            assert(actual==expected,language..': dictionary '..row.text)
            assert(native.async_translate(row.text)==expected,language..': repaint '..row.text)
        end
        local _,_,after=native.core_cache_metrics()
        assert(after==before,'Known creatures dispatched workers')
        result.languages[language]={rows=#fixtures[language],worker_submissions_added=after-before}
    end
    native.set_lang_tag(original)
    local _,_,before=native.core_cache_metrics()
    result.samples={}
    for _,source in ipairs({'cat','cats','dog','dogs','cow','cows','giant cave spider','pike'}) do
        local translated=runtime.unit_name_translation(source)
        local expected=reqscript('df-local-zh-creature-names').translation(source,original)
        assert(translated==expected,'Runtime name: '..source)
        assert(translated,'Missing creature: '..source)
        result.samples[source]=translated
    end
    local _,_,after=native.core_cache_metrics()
    assert(after==before,'Runtime known names dispatched workers')
    result.runtime_submissions_added=after-before
end,debug.traceback)
native.set_lang_tag(original)
result.pass=ok;result.error=not ok and tostring(err) or nil
file=assert(io.open(paths.broker_data()..'/creature-dictionaries-live.json','wb'))
file:write(json.encode(result,{pretty=true}));file:close()
print('CREATURE_DICTIONARIES '..json.encode(result,{pretty=false}))
assert(ok,err)
