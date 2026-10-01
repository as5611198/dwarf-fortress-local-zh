-- Verify both language dictionaries without drawing UI or dispatching translation work.
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')
local json=require('json')
local file=assert(io.open(paths.source()..'/self-tests/workbook-dictionaries.json','rb'))
local fixture=json.decode(file:read('*a'));file:close()
local result={version=1,started=os.time(),languages={},errors={},restored_language='zh-Hant'}
local ok,err=xpcall(function()
    for _,language in ipairs({'zh-Hant','zh-Hans'}) do
        native.set_lang_tag(language)
        local _,_,before=native.core_cache_metrics()
        local started=dfhack.getTickCount()
        local rows=fixture[language]
        for _,row in ipairs(rows) do
            local actual=native.cache_lookup(row.text)
            if actual~=row.translation then
                result.errors[#result.errors+1]={language=language,source=row.text,
                    expected=row.translation,actual=actual}
            else
                local repainted=native.async_translate(row.text)
                if repainted~=row.translation then
                    result.errors[#result.errors+1]={language=language,source=row.text,
                        expected=row.translation,actual=repainted}
                end
            end
        end
        local _,pending,after=native.core_cache_metrics()
        result.languages[language]={rows=#rows,lookups=#rows*2,
            elapsed_ms=dfhack.getTickCount()-started,pending=pending,
            worker_submissions_added=after-before}
        assert(after==before,'Static workbook hits dispatched translation workers')
    end
end,debug.traceback)
native.set_lang_tag('zh-Hant')
result.error=not ok and tostring(err) or nil
result.pass=ok and #result.errors==0
local path=paths.broker_data()..'/workbook-dictionaries-live.json'
file=assert(io.open(path,'wb'));file:write(json.encode(result,{pretty=true}));file:close()
print(('WORKBOOK_DICTIONARIES pass=%s errors=%d language_restored=zh-Hant; %s'):format(
    tostring(result.pass),#result.errors,path))
for _,language in ipairs({'zh-Hant','zh-Hans'}) do
    local row=result.languages[language]
    if row then print(('%s rows=%d lookups=%d elapsed_ms=%d submissions=%d'):format(
        language,row.rows,row.lookups,row.elapsed_ms,row.worker_submissions_added)) end
end
if not result.pass then error('Workbook dictionary verification failed; see '..path) end
