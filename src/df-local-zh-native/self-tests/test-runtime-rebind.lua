local bind=assert(loadfile(dfhack.getDFPath()..'/_localization-work/runtime-rebind.lua'))()
local function module(new)
    local state={count=0}
    local record
    if new then record=function() state.count=state.count+10;return state end
    else record=function() state.count=state.count+1;return state end end
    local render=function() return record() end
    return {render=render,draw=function() return record() end}
end
local old,fresh=module(false),module(true)
local captured=old.render
local state=old.render()
assert(state.count==1)
assert(bind(old,fresh,{'record'},{'draw'})==2)
assert(captured()==state and state.count==11,'Captured bridge must use new code with the original state')
assert(old.draw()==state and state.count==21,'Export must share the running state')
local ok=pcall(bind,old,{draw=function() return 0 end},{'missing'},{'draw'})
assert(not ok and old.draw()==state and state.count==31,'Failed validation must leave running closures intact')
print('PASS runtime rebinding, captured bridges, preserved state and atomic validation')
