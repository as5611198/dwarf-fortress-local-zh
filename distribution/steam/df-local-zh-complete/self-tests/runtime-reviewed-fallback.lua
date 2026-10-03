-- Exercise the actual reviewed reader and runtime lookup with incomplete packages.
local root=assert((...), 'scripts_modinstalled directory required')
local json=require('json')
local source='An ordinary sentence.'
for _,case in ipairs({{name='missing'}, {name='invalid',content='{'},
    {name='valid',content=json.encode({[source]={['zh-Hant']='人工校訂文字。',['zh-Hans']='人工校订文字。'}})}}) do
    local reads=0
    local reviewed=setmetatable({
        reqscript=function(name)
            assert(name=='df-local-zh-paths')
            return {broker_source=function() return 'fixture' end}
        end,
        io={open=function()
            reads=reads+1
            if not case.content then return nil end
            return {read=function() return case.content end,close=function() end}
        end},
    },{__index=_G})
    assert(loadfile(root..'/df-local-zh-reviewed-text.lua','t',reviewed))()
    local runtime=setmetatable({dfhack={isWorldLoaded=function() return false end},reqscript=function(name)
        if name=='df-local-zh-core/native' then return {} end
        if name=='df-local-zh-core/mod' then return {sync_translate=function() return '模型譯文。' end} end
        if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
        if name=='df-local-zh-reviewed-text' then return reviewed end
        error(name)
    end},{__index=_G})
    assert(loadfile(root..'/df-local-zh-runtime.lua','t',runtime))()
    runtime.lookup=function() return 'fixture-key' end
    local expected=case.name=='valid' and '人工校訂文字。' or '模型譯文。'
    assert(runtime.translation(source)==expected,case.name..': runtime lookup must remain available')
    assert(runtime.translation(source)==expected)
    assert(reads==1,case.name..': repeated render lookups must not reread the file')
    if case.name=='valid' then assert(reviewed.translation(source,'zh-Hans')=='人工校订文字。') end
end
print('RUNTIME_REVIEWED_FALLBACK PASS: missing/invalid index preserves runtime translation; valid bilingual corrections win')
