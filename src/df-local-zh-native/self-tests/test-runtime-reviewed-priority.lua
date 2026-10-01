local fixed=false
local correct='這是肉盔菇菌種袋。'
local wrong='這是矮人菇孢子袋。'
local env=setmetatable({dfhack={isWorldLoaded=function() return false end},reqscript=function(name)
    if name=='df-local-zh-core/native' then return {} end
    if name=='df-local-zh-core/mod' then return {sync_translate=function() return wrong end} end
    if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture-unused' end} end
    if name=='df-local-zh-reviewed-text' then return {translation=function() return fixed and correct or nil end} end
    if name=='df-local-zh-unit-prewarm' then return {remember=function() end,fixed_translation=function() return nil end} end
    error(name)
end},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/_localization-work/df-local-zh-native/mod/df-local-zh-complete/scripts_modinstalled/df-local-zh-runtime.lua','t',env))()
env.lookup=function() return 'old-alias' end
local source='This is a plump helmet spawn Bag.'
assert(env.translation(source)==wrong,'Fixture must first cache the bad model response')
fixed=true
assert(env.translation(source)==correct,'Reviewed item text must supersede already cached display prose')
assert(env.unit_translation(source)==correct,'The item-sheet bridge must also supersede cached display prose')
print('PASS reviewed prose overrides cached Lua display response')
