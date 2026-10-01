-- Event-driven real UI checks. Run from a loaded, paused fortress.
local paths=reqscript('df-local-zh-paths')
local native=reqscript('df-local-zh-core/native')
local search=reqscript('df-local-zh-search')
local gui=require('gui')
local json=require('json')
assert(dfhack.isMapLoaded() and df.global.pause_state,'Search tests require a loaded, paused fortress')
assert(df.viewscreen_dwarfmodest:is_instance(dfhack.gui.getCurViewscreen()),'Close any DFHack dialog before starting')
local root=paths.source()..'/self-tests/'
local prefix=paths.broker_data()..'/chinese-search-'..os.time()..'-'..dfhack.getTickCount()
local results={started=os.time(),world=dfhack.getSavePath(),checks={}}
local active,timer,finished

local function finish(error)
    if finished then return end
    finished=true
    if timer then dfhack.timeout_active(timer,nil) end
    if active then active.cancelled=true end
    if active and active.cleanup then pcall(active.cleanup) end
    if error then results.error=tostring(error) end
    local attempts=0
    local function restored()
        local screen=dfhack.gui.getCurViewscreen()
        if not dfhack.gui.matchFocusString('dwarfmode/Default',screen) and attempts<8 then
            attempts=attempts+1
            if df.viewscreen_dwarfmodest:is_instance(screen) then
                gui.simulateInput(screen,'LEAVESCREEN')
                gui.simulateInput(screen,'_MOUSE_R')
            end
            dfhack.timeout(1,'frames',restored);return
        end
        search.sync()
        results.restored_focus=dfhack.gui.getFocusStrings(screen)
        results.paused=df.global.pause_state
        if not dfhack.gui.matchFocusString('dwarfmode/Default',screen) then
            results.error=results.error or 'Could not restore the default fortress view'
        end
        results.finished=os.time();results.passed=not results.error
        local file=assert(io.open(prefix..'.json','wb'));file:write(json.encode(results));file:close()
        print('df-local-zh-search-test COMPLETE '..(results.passed and 'PASS' or 'FAIL')..'; '..prefix..'.json')
        if results.error then dfhack.printerr(results.error) end
    end
    -- DFHack screen dismissal is applied on the next frame.
    dfhack.timeout(1,'frames',restored)
end

local function checked(callback,...)
    if finished then return end
    local args=table.pack(...)
    local ok,error=xpcall(function() callback(table.unpack(args,1,args.n)) end,debug.traceback)
    if not ok then finish(error) end
end

local function helper(name,callback)
    if timer then dfhack.timeout_active(timer,nil) end
    local context={log_path=prefix..'-'..name..'.json'}
    active=context
    context.completed=function(result)
        if finished or active~=context then return end
        if timer then dfhack.timeout_active(timer,nil);timer=nil end
        checked(callback,result)
    end
    timer=dfhack.timeout(180,'frames',function() finish(name..' did not complete within the frame deadline') end)
    checked(function() assert(loadfile(root..name..'.lua'))(context) end)
end

local function dfhack_list()
    helper('live-chinese-dfhack',function(result)
        for _,row in ipairs(result.cases) do assert(row.passed,'DFHack query failed: '..row.query) end
        assert(result.matcher_submissions==0,'Matcher dispatched translation work')
        results.checks.dfhack=result
        finish()
    end)
end

local function widget()
    local screen=dfhack.gui.getCurViewscreen()
    gui.simulateInput(screen,'LEAVESCREEN');gui.simulateInput(screen,'D_UNITLIST')
    local started=dfhack.getTickCount()
    local function ready()
        checked(function()
            local creatures=df.global.game.main_interface.info.creatures
            if #dfhack.gui.getWidgetChildren(creatures)==0 then
                assert(dfhack.getTickCount()-started<3000,'Native widget did not initialize')
                dfhack.timeout(1,'frames',ready);return
            end
            helper('live-chinese-widget',function(result)
                assert(result.passed and result.comparisons>0,'Native unit-list filter failed')
                results.checks.widget=result
                dfhack.timeout(1,'frames',dfhack_list)
            end)
        end)
    end
    dfhack.timeout(1,'frames',ready)
end

helper('live-chinese-stocks',function(rows)
    for _,row in ipairs(rows) do assert(row.passed,'Stocks query failed: '..row.query) end
    results.checks.stocks=rows
    dfhack.timeout(1,'frames',widget)
end)
