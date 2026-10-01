local probes,mod_queries,state_queries,mkdirs=0,0,0,0
local env=setmetatable({
    require=function(name)
        if name=='script-manager' then return {
            getModSourcePath=function() mod_queries=mod_queries+1;return 'fixture/mod' end,
            getModStatePath=function() state_queries=state_queries+1;return 'fixture/state' end,
        } end
        return require(name)
    end,
    io={open=function() probes=probes+1;return {close=function() end} end},
    dfhack={getDFPath=function() return 'fixture' end,
        filesystem={mkdir_recursive=function() mkdirs=mkdirs+1;return true end}},
},{__index=_G})
assert(loadfile((...) or dfhack.getDFPath()..'/hack/scripts/df-local-zh-paths.lua','t',env))()
for _=1,1000 do
    assert(env.source()=='fixture/fixture/mod')
    assert(env.state()=='fixture/fixture/state')
    assert(env.broker_data()=='fixture/fixture/state/data')
end
assert(probes==1 and mod_queries==1 and state_queries==1 and mkdirs==1,
    'Repeated path access must not open config files, resolve mod paths or create directories')
print('PATHS_PERFORMANCE source/state/data cached; file probes=1, mkdirs=1')
