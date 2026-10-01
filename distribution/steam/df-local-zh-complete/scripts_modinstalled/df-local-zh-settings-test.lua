local settings=reqscript('df-local-zh-settings')
local ui=reqscript('df-local-zh-settings-ui')
local runtime=reqscript('df-local-zh-runtime')
local native=reqscript('df-local-zh-core/native')
local paths=reqscript('df-local-zh-paths')
local gui=require('gui')
local json=require('json')
local mode=({...})[1] or (dfhack.isMapLoaded() and 'fortress' or 'title')
assert((mode=='fortress')==dfhack.isMapLoaded(),'Settings test mode must match the current game screen')
assert(dfhack.gui.getCurViewscreen()==dfhack.gui.getDFViewscreen(),'Close the previous test dialog before starting')
settings.reload()
local before=require('utils').clone(settings.get_snapshot().document,true)
local scope=mode=='fortress' and 'save' or 'global'
local original=settings.effective(scope)
local controls={
    colorPersistence=not original.colorPersistence,
    backgroundTranslation=not original.backgroundTranslation,
    concurrency=original.concurrency==1 and 2 or 1,
    timeoutMs=original.timeoutMs==26000 and 27000 or 26000,
    maxRetries=original.maxRetries==3 and 2 or 3,
    retryBaseMs=original.retryBaseMs==1100 and 1200 or 1100,
}
local result={version=1,mode=mode,started=os.time(),checks={},original_settings=before}
local path=paths.broker_data()..'/settings-'..mode..'-live.json'
local finished=false
local screen
local function finish(error)
    if finished then return end;finished=true
    if screen and screen:isActive() then screen:dismiss() end
    native.core_trace_enable(0)
    df.global.game.main_interface.settings.open=false
    if mode=='fortress' and df.global.game.main_interface.options.open then
        gui.simulateInput(dfhack.gui.getCurViewscreen(),'LEAVESCREEN')
    end
    local function record()
        if mode=='fortress' then
            result.checks.options_closed=not df.global.game.main_interface.options.open and
                dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen())[1]=='dwarfmode/Default'
            if not result.checks.options_closed and not error then error='Options did not close after the test' end
        end
        result.error=error and tostring(error) or nil
        result.pass=not result.error;result.finished=os.time()
        local file=assert(io.open(path..'.tmp','wb'));file:write(json.encode(result,{pretty=true}));file:close()
        os.remove(path);assert(os.rename(path..'.tmp',path))
        print('SETTINGS_'..mode..' COMPLETE '..(result.pass and 'PASS' or 'FAIL')..'; '..path)
    end
    if mode=='fortress' then dfhack.timeout(1,'frames',record) else record() end
end
local function checked(callback,...)
    if finished then return end
    local args=table.pack(...)
    local ok,error=xpcall(function() callback(table.unpack(args,1,args.n)) end,debug.traceback)
    if not ok then finish(error) end
end
local function restore(final_error)
    if screen and screen:isActive() then screen:dismiss() end
    local request={action='save',scope=scope,reset=scope=='save'}
    if scope=='global' then request.settings=before.defaults end
    assert(settings.submit(request,function(reply)
        checked(function()
            assert(reply.ok,'Restoring original settings failed')
            local saved=before.saves[settings.world_key(settings.world())]
            if scope=='save' and saved then
                assert(settings.submit({action='save',scope=scope,settings=saved},function(row)
                    checked(function() assert(row.ok);result.checks.restored=true;finish(final_error) end)
                end))
            else result.checks.restored=true;finish(final_error) end
        end)
    end))
end
local function after_language(reply,new_screen)
    checked(function()
        assert(reply.ok,reply.error);screen=new_screen
        local target=original.language=='zh-Hant' and 'zh-Hans' or 'zh-Hant'
        assert(runtime.language()==target,'Applied language is not active')
        assert(native.cache_lookup('Fighting')==(target=='zh-Hans' and '战斗' or '戰鬥'))
        local effective=settings.effective(scope)
        for key,value in pairs(controls) do
            assert(effective[key]==value,'Applied '..key..' did not persist')
        end
        result.checks.controls_applied=true
        assert(not native.search_matches('iron goblet','gaojiaobei'),'Disabled Pinyin must take effect immediately')
        assert(native.search_matches('iron goblet','铁'),'Simplified input must remain usable')
        result.checks.language_applied=true;result.checks.pinyin_disabled=true
        for _,language in ipairs({'zh-Hant','zh-Hans'}) do
            native.set_lang_tag(language)
            local _,_,submitted=native.core_cache_metrics()
            local start=os.clock()
            for _=1,2000 do
                assert(native.cache_lookup('Fighting')==(language=='zh-Hans' and '战斗' or '戰鬥'))
                assert(native.search_matches('granite blocks','花岗岩'))
            end
            assert(select(3,native.core_cache_metrics())==submitted,'Known language hits dispatched translation work')
            result.checks[language]={lookups=4000,cpu_ms=(os.clock()-start)*1000,submissions=0}
        end
        native.set_lang_tag(target)
        screen.subviews.pinyin:setOption(true,true)
        assert(screen:apply(false,function(row,active)
            checked(function()
                assert(row.ok,row.error);screen=active
                assert(native.search_matches('iron goblet','gaojiaobei'))
                assert(native.search_matches('iron goblet','gjb'))
                assert(native.search_matches('granite blocks','hgy'))
                result.checks.pinyin_enabled=true
                assert(screen:test_connection(function(connection)
                    checked(function()
                        result.checks.connection={ok=connection.ok,error=connection.error}
                        local error
                        if not connection.ok then error='Connection test: '..tostring(connection.error) end
                        if mode=='fortress' then
                            assert(screen:apply(true,function(reset,active)
                                checked(function()
                                    screen=active
                                    result.checks.inherit_global=reset.ok
                                    if reset.ok then
                                        assert(settings.effective('save').language==settings.effective('global').language,
                                            'Inherit Global did not activate global language')
                                    elseif not error then error='Inherit Global: '..tostring(reset.error) end
                                    restore(error)
                                end)
                            end))
                        else restore(error) end
                    end)
                end))
            end)
        end))
    end)
end
local function test_panel()
    checked(function()
        assert(dfhack.gui.getCurFocus()[1]:find('df-local-zh/settings',1,true),
            'The Settings entry did not open the shared panel')
        screen=ui.show()
        assert(screen.scope==scope and screen.subviews.kind:getOptionValue()==screen.profile.kind)
        assert(screen.subviews.api_key.value==nil,'Stored keys must remain outside the UI draft')
        screen.subviews.language:setOption(original.language=='zh-Hant' and 'zh-Hans' or 'zh-Hant',true)
        local profile_before=settings.get_snapshot().profiles[screen.profile_id]
        local previous_url,previous_model,previous_key=profile_before.baseUrl,profile_before.model,profile_before.hasKey
        screen.subviews.api_url:setText('https://example.invalid/v1')
        screen.subviews.api_model:setText('fixture-model')
        screen.subviews.api_key:setValue('fixture-key')
        screen:dismiss()
        dfhack.timeout(1,'frames',function()
            checked(function()
                assert(settings.effective(scope).language==original.language,'Cancel saved a draft')
                local profile_after=settings.get_snapshot().profiles[screen.profile_id]
                assert(profile_after.baseUrl==previous_url and profile_after.model==previous_model and
                    profile_after.hasKey==previous_key,'Cancel saved the API draft')
                result.checks.cancel=true
                screen=ui.show()
                screen.subviews.language:setOption(original.language=='zh-Hant' and 'zh-Hans' or 'zh-Hant',true)
                screen.subviews.pinyin:setOption(false,true)
                for _,key in ipairs({'colorPersistence','backgroundTranslation'}) do
                    screen.subviews[key]:setOption(controls[key],true)
                end
                for _,key in ipairs({'concurrency','timeoutMs','maxRetries','retryBaseMs'}) do
                    screen.subviews[key]:setText(tostring(controls[key]))
                end
                assert(screen:apply(false,after_language))
            end)
        end)
    end)
end
native.core_trace_enable(1)
if mode=='fortress' then gui.simulateInput(dfhack.gui.getCurViewscreen(),'OPTIONS') end
local started=dfhack.getTickCount()
local clicked=false
local function find_entry()
    checked(function()
        local options=df.global.game.main_interface.settings
        if options.open then
            local state=require('plugins.overlay').get_state()
            local entry=assert(state.db['df-local-zh-settings-ui.settings']).widget
            assert(entry.visible(),'Settings entry must be visible in the actual Settings screen')
            local rect=entry.frame_body
            result.checks.entry={focus=dfhack.gui.getCurFocus(),x=rect.x1,y=rect.y1,width=rect.width,height=rect.height}
            gui.simulateInput(dfhack.gui.getCurViewscreen(),'CUSTOM_CTRL_M')
            dfhack.timeout(1,'frames',test_panel);return
        end
        for _,row in ipairs(json.decode(native.core_trace_read())) do
            if not clicked and row.text:lower():gsub('%s','')=='settings' then
                local old=df.global.enabler.mouse_focus;df.global.enabler.mouse_focus=true
                df.global.gps.mouse_x,df.global.gps.mouse_y=row.x+1,row.y
                gui.simulateInput(dfhack.gui.getCurViewscreen(),'_MOUSE_L')
                df.global.enabler.mouse_focus=old;clicked=true
            end
        end
        assert(dfhack.getTickCount()-started<4000,'Native Settings entry did not open')
        dfhack.timeout(1,'frames',find_entry)
    end)
end
dfhack.timeout(1,'frames',find_entry)
