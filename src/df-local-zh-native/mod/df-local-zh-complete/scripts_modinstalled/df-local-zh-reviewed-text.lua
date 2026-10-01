--@module=true
local keys
function translation(source,language)
    if not keys then
        local path=reqscript('df-local-zh-paths').broker_source()..'/data/reviewed-text-keys.json'
        local file=assert(io.open(path,'rb'))
        keys=require('json').decode(file:read('*a'));file:close()
    end
    local row=keys[source]
    return row and row[language]
end
