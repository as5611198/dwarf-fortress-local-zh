--@module = true
local keys
function translation(source,language)
    if not keys then
        local path=reqscript('df-local-zh-paths').broker_source()..'/data/creature-name-keys.json'
        local file=assert(io.open(path,'rb'))
        keys=require('json').decode(file:read('*a'));file:close()
    end
    if keys[source] then return keys[source][language] end
    local stem,number=source:match('^(.-) (%d+)$')
    local row=stem and (keys[stem] or keys[stem:lower()])
    return row and row[language]..' '..number
end
