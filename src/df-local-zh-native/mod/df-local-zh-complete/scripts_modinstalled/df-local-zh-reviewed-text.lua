--@module=true
local keys
function translation(source,language)
    if not keys then
        -- Older/incomplete packages must still reach cached or AI prose.
        -- Cache an empty index too, so render lookups do not repeatedly hit disk.
        keys={}
        local path=reqscript('df-local-zh-paths').broker_source()..'/data/reviewed-text-keys.json'
        local file=io.open(path,'rb')
        if file then
            local content=file:read('*a');file:close()
            local ok,value=pcall(require('json').decode,content or '')
            if ok and type(value)=='table' then keys=value end
        end
    end
    local row=keys[source]
    return type(row)=='table' and type(row[language])=='string' and row[language] or nil
end
