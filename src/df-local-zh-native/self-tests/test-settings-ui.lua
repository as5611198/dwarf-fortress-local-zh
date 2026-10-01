local gui=require('gui')
local widgets=require('gui.widgets')
local json=require('json')
local root=dfhack.getDFPath()
local snapshot={profiles={legacy={label='DeepSeek',enabled=true,kind='DeepSeek',
    baseUrl='https://api.deepseek.com/v1',model='deepseek-chat',hasKey=true},
    other={label='Local API',enabled=false,kind='Custom_OpenAI',baseUrl='http://localhost:1234/v1',model='local'}},
    promptDefaults={translation='Dwarf Fortress fixture default.'},
    document={defaults={language='zh-Hant',pinyin=true,colorPersistence=true,apiEnabled=true,translationPrompt='',
        apiProfile='legacy',backgroundTranslation=true,concurrency=2,timeoutMs=25000,maxRetries=2,retryBaseMs=1000,officialAutoDownload=true,sharedContributions=false}}}
local requests={}
local painted={}
local aliases={}
local interception_bypassed=false
local bypass_events={}
local function literal_key(text)
    local key='L00000'..string.char(96+(#painted%26)+1)..'____'
    aliases[key]=text
    return key
end
local fake={reload=function() end,world=function() return '' end,get_snapshot=function() return snapshot end,
    effective=function() return require('utils').clone(snapshot.document.defaults,true) end,
    is_pending=function() return false end,submit=function(request,callback)
        requests[#requests+1]=request
        if request.action=='clipboard' then callback({ok=true,text='中文多行\n肉盔菇菌種'}) end
        return true
    end}
local env=setmetatable({dfhack_flags={module=true},
dfhack=setmetatable({internal=setmetatable({getClipboardTextCp437=function() return 'fixture-key' end},
    {__index=dfhack.internal}),screen=setmetatable({paintString=function(_,x,y,value)
    painted[#painted+1]={x=x,y=y,text=value,bypassed=interception_bypassed}
end},{__index=dfhack.screen})},{__index=dfhack}),
reqscript=function(name)
    if name=='df-local-zh-settings' then return fake end
    if name=='df-local-zh-runtime' then
        local runtime=reqscript(name)
        return setmetatable({language=function() return 'zh-Hant' end,
            publish=function(key,text) aliases[key]=text;return true end,
            localize_text=function(text) return text end,literal_key=literal_key,
            draw_key=function(x,y,color,background,key,flag)
                painted[#painted+1]={x=x,y=y,text=aliases[key] or key,flag=flag}
            end},{__index=runtime})
    end
    if name=='df-local-zh-core/mod' then
        return {async_translate=function(key) return aliases[key] end}
    end
    if name=='df-local-zh-core/native' then
        return {interception_bypass_enable=function() interception_bypassed=true;bypass_events[#bypass_events+1]='enable' end,
            interception_bypass_disable=function() interception_bypassed=false;bypass_events[#bypass_events+1]='disable' end}
    end
    return reqscript(name)
end},{__index=_G})
local source=(...) or reqscript('df-local-zh-paths').source()..'/scripts_modinstalled/df-local-zh-settings-ui.lua'
assert(loadfile(source,'t',env))()
local screen=env.SettingsScreen{}
screen.subviews.window.frame.h=28
screen:updateLayout(gui.ViewRect{rect={x1=0,y1=0,x2=79,y2=29}})
local function assert_native_text(widget,text)
    painted={}
    widget:onRenderBody({seek=function() return {string=function(_,value)
        assert(not value:match('^L[%w_]+$'),'Untranslated alias reached a DFHack text painter')
    end} end})
    for _,row in ipairs(painted) do
        if row.text==text then
            assert(row.flag==0x80000000,'Dense settings labels must not reserve the following row: '..text)
            return
        end
    end
    error('Native painter did not receive '..text)
end
local help_text={
    api_key_help='點金鑰欄輸入或 Ctrl+V 貼上，Ctrl+S 套用',
    backgroundHelp='閒置時補譯背景佇列，前景請求優先',
    concurrencyHelp='所有 API 合計的請求上限（1-32）',
    timeoutHelp='單次模型請求的等待上限（毫秒）',
    retriesHelp='請求失敗後再次嘗試的次數（0-5）',
    retryDelayHelp='每次重試前等待的時間（毫秒）',
}
local function assert_help(id)
    painted={}
    screen.subviews[id]:onRenderBody()
    table.sort(painted,function(a,b) return a.x<b.x end)
    local chunks={}
    for _,row in ipairs(painted) do chunks[#chunks+1]=row.text end
    assert(table.concat(chunks)==help_text[id],'Missing or clipped setting help: '..id)
end
screen.subviews.pages:setSelected(2)
assert_native_text(screen.subviews.tabs,'模型服務')
assert_native_text(screen.subviews.profile_select,'模型設定檔')
assert_native_text(screen.subviews.api_url,'服務網址')
assert_native_text(screen.subviews.api_key,'已保存的金鑰')
assert_native_text(screen.subviews.new_profile,'新增設定檔')
assert_help('api_key_help')
screen.subviews.pages:setSelected(3)
assert_native_text(screen.subviews.backgroundTranslation,'背景翻譯')
assert_native_text(screen.subviews.timeoutMs,'逾時毫秒')
for _,id in ipairs({'backgroundHelp','concurrencyHelp','timeoutHelp','retriesHelp','retryDelayHelp'}) do
    assert_help(id)
end
screen.subviews.pages:setSelected(2)
local tabs=screen.subviews.tabs
tabs.getMousePos=function() return 1,0 end
assert(tabs:onInput{_MOUSE_L=true} and screen.page==1,'First tab must be clickable')
tabs.getMousePos=function() return 20,0 end
assert(tabs:onInput{_MOUSE_L=true} and screen.page==2,'API tab must be clickable')
assert(tabs:onInput{CUSTOM_CTRL_T=true} and screen.page==3,'Keyboard tab cycling must work')
tabs:onInput{CUSTOM_CTRL_Y=true}
assert(screen.page==2,'Reverse keyboard tab cycling must work')
local pressed=0
assert(env.NativeButton.onInput({key='CUSTOM_A',on_activate=function() pressed=pressed+1 end,
    getMousePos=function() return 1,0 end},{_MOUSE_L=true}) and pressed==1,
    'Native settings buttons must remain clickable')
assert(screen.subviews.kind:getOptionValue()=='DeepSeek','existing provider kind must be displayed accurately')
screen.subviews.api_model:setText('edited-deepseek')
screen:select_profile('other')
assert(screen.draft.apiProfile=='legacy','Selecting the editor must not change active APIs')
assert(screen.subviews.apiParticipating:getOptionValue()==false,'An unselected API must not silently join the pool')
screen.subviews.apiParticipating.on_change(true)
screen.subviews.apiConcurrency:setText('4')
screen.subviews.api_model:setText('edited-local')
screen:select_profile('legacy')
assert(screen.subviews.apiParticipating:getOptionValue()==true,'Switching editors must retain previous participation')
screen.subviews.apiConcurrency:setText('3')
screen.subviews.apiEnabled.on_change(false)
assert(screen.profile.enabled==true,'Master API switch must not disable individual profiles')
screen.subviews.apiEnabled.on_change(true)
assert(screen.subviews.api_model.text=='edited-deepseek','switching API profiles must preserve unsaved edits')
screen:apply()
assert(#requests==1 and #requests[1].profiles==2,'Apply must save every edited profile')
assert(#requests[1].settings.apiProfiles==2,'Apply must retain both participating APIs')
for _,row in ipairs(requests[1].profiles) do
    assert(row.concurrency==(row.id=='legacy' and 3 or 4),'Each API must retain its own concurrency')
end
for _,row in ipairs(requests[1].profiles) do assert(row.key==nil,'unchanged keys must not be cleared or exposed') end
screen.subviews.api_key:setFocus(true)
assert(screen.subviews.api_key:onInput{CUSTOM_CTRL_V=true},'Focused key field must accept Ctrl+V')
assert(screen.profile.key=='fixture-key','Pasted key must be saved in the draft')
painted={}
screen.subviews.api_key:onRenderBody()
assert(painted[1] and painted[1].text==string.rep('*',#'fixture-key'),
    'Pasted key must remain masked on screen')
screen.subviews.api_key.selected=true
screen.subviews.api_key:onInput{CUSTOM_BACKSPACE=true}
assert(screen.subviews.api_key.value=='','Backspace must clear a selected key')
screen:onDismiss()
assert(screen.profile.key==nil and screen.subviews.api_key.value==nil,'dismiss must clear key drafts')
assert(#requests==1,'Cancel must not submit settings')
local save_screen=env.SettingsScreen{scope_override='save'}
assert(save_screen:apply(true),'Inherit Global must submit a reset')
assert(requests[2].scope=='save' and requests[2].reset==true and requests[2].settings==nil,
    'Inherit Global must omit empty settings instead of sending a JSON array')
assert(save_screen:apply(false),'An unchanged save draft must submit')
assert(requests[3].scope=='save' and requests[3].settings==nil,
    'An unchanged save draft must omit empty settings')
local pool_screen=env.SettingsScreen{}
pool_screen:set_participating(false)
assert(pool_screen.draft.apiPoolEnabled and #pool_screen.draft.apiProfiles==0,
    'Removing the last member must preserve an explicitly empty pool')
pool_screen:new_profile()
assert(pool_screen.draft.apiProfile=='legacy' and #pool_screen.draft.apiProfiles==1,
    'Adding a profile must join the pool without changing the legacy selection')
pool_screen.subviews.apiConcurrency:setText('')
assert(not pool_screen:apply(),'Empty per-API concurrency must be rejected before submitting')
for _,bounds in ipairs({{80,30},{64,30}}) do
    screen.subviews.window.frame.w=math.min(78,bounds[1]-2)
    screen:updateLayout(gui.ViewRect{rect={x1=0,y1=0,x2=bounds[1]-1,y2=bounds[2]-1}})
    local parent=screen.subviews.api.frame_body
    for _,id in ipairs({'kind','apiEnabled','apiParticipating','apiConcurrency','api_url','api_model','api_key','new_profile','delete_profile','test','clear_key'}) do
        local rect=assert(screen.subviews[id],'Missing API control: '..id).frame_body
        assert(rect.x1>=parent.x1 and rect.x2<=parent.x2 and rect.y1>=parent.y1 and rect.y2<=parent.y2,
            'API control outside its page at '..bounds[1]..' columns: '..id)
    end
    for _,id in ipairs({'api_label','api_url','api_model','concurrency','timeoutMs'}) do
        local field=screen.subviews[id]
        assert(field.text_area.frame_body.x1==field.frame_body.x1+24,
            'Native label must reserve the same edit width at '..bounds[1]..' columns: '..id)
    end
    local field=screen.subviews.api_label
    local text_draws={}
    local original_paint=dfhack.screen.paintString
    dfhack.screen.paintString=function(_,x,y,value)
        if value==field.text then text_draws[#text_draws+1]={x=x,y=y,bypassed=interception_bypassed} end
    end
    local rendered,render_error=pcall(function() field:render(gui.Painter.new()) end)
    dfhack.screen.paintString=original_paint
    assert(rendered,render_error)
    assert(#text_draws==1 and text_draws[1].x==field.text_area.frame_body.x1 and text_draws[1].bypassed==true,
        'Profile value must render once, inside its input field at '..bounds[1]..' columns: '..
        json.encode({expected=field.text_area.frame_body.x1,draws=text_draws}))
    assert(#bypass_events>0 and bypass_events[#bypass_events]=='disable' and not interception_bypassed,
        'Settings render must close its interception bypass scope')
    for id in pairs(help_text) do assert_help(id) end
    painted={}
    screen.subviews.tabs:onRenderBody({})
    local tabs=screen.subviews.tabs.frame_body
    local last_right=tabs.x1-1
    for _,row in ipairs(painted) do
        local right=row.x+utf8.len(row.text)*2-1
        assert(row.x>last_right and right<=tabs.x2,'Chinese tab text overlaps at '..bounds[1]..' columns')
        last_right=right
    end
end
assert(type(env.PromptScreen)=='table','Prompt editor is required')
local parent=env.SettingsScreen{scope_override='save'}
env.PromptScreen.show=function(self) return self end
env.PromptScreen.dismiss=function() end
local editor=parent:edit_prompt()
assert(editor.subviews.prompt_text:getText()=='Dwarf Fortress fixture default.')
editor.subviews.prompt_text:setText('請使用肉盔菇。\n健康描述保持精確。')
assert(parent.draft.translationPrompt=='','Editing must remain a separate draft until accepted')
editor:accept()
assert(parent.draft.translationPrompt=='請使用肉盔菇。\n健康描述保持精確。')
assert(parent:apply(false))
assert(requests[#requests].settings.translationPrompt=='請使用肉盔菇。\n健康描述保持精確。','Apply must transmit the accepted prompt')
editor.isActive=function() return true end
editor.subviews.prompt_text.selected=true
editor:paste()
assert(editor.subviews.prompt_text:getText()=='中文多行\n肉盔菇菌種','Paste must retain Chinese and newlines')
assert(not editor.subviews.prompt_text:setText(string.rep('x',8193)),'Oversized drafts must be rejected')
local cancelled=parent:edit_prompt()
cancelled.subviews.prompt_text:setText('discard this')
cancelled:dismiss()
assert(parent.draft.translationPrompt=='請使用肉盔菇。\n健康描述保持精確。','Cancel must retain the parent draft')
local reset_editor=parent:edit_prompt()
reset_editor:restore_default();reset_editor:accept()
assert(parent.draft.translationPrompt=='','Reset must request the shipped default, not a stale copy')
for _,width in ipairs({64,80}) do
  editor.subviews.window.frame.w=width-2
  editor:updateLayout(gui.ViewRect{rect={x1=0,y1=0,x2=width-1,y2=29}})
  local field=editor.subviews.prompt_text
  field:setText('中文測試\nsecond line');field:setFocus(true)
  field:onInput{CUSTOM_CTRL_A=true};field:onInput{_STRING=65}
  assert(field:getText()=='A','Select all must replace Unicode safely')
  field:setText('字');field.cursor=2
  field:onInput{CUSTOM_BACKSPACE=true}
  assert(field:getText()=='','Backspace must delete a full UTF-8 codepoint')
  local rect=field.frame_body;local window=editor.subviews.window.frame_body
  assert(rect.x1>=window.x1 and rect.x2<=window.x2 and rect.y2<editor.subviews.accept_prompt.frame_body.y1)
  field:setText('Prompt ASCII 中文 mixed');field.cursor=1;painted={}
  field:onRenderBody()
  local full=false
  for _,row in ipairs(painted) do if row.text=='Prompt ASCII 中文 mixed' and row.flag==0x80000000 then full=true end end
  assert(full,'Prompt rows must render as one literal native row, including Latin text')
  assert(painted[#painted].text=='P','Cursor must highlight the current character without hiding it')
  field.cursor=utf8.len(field.text)+1;painted={};field:onRenderBody()
  assert(painted[#painted].text=='_','Cursor must remain visible at the end of the prompt')
end
assert(parent:apply(false));assert((requests[#requests].settings or {}).translationPrompt==nil,
    'An unchanged default prompt must inherit global settings')
-- Cloud synchronization is an acknowledgement, never a settings reload.
snapshot.document.defaults.officialAutoDownload=true
local cloud=env.SettingsScreen{}
cloud.isActive=function() return true end
cloud.draft.translationPrompt='未套用提示詞'
cloud.profile.key='unapplied-fixture-key';cloud:profile_changed()
local cloud_submit=fake.submit
fake.submit=function(request,callback)
    requests[#requests+1]=request
    if request.action=='official-sync' then callback({ok=true}) end
    return true
end
cloud.subviews.officialAutoDownload:cycle()
assert(cloud.draft.officialAutoDownload==false and snapshot.document.defaults.officialAutoDownload==true)
assert(cloud:sync_official())
assert(requests[#requests].action=='official-sync' and requests[#requests].settings==nil)
assert(cloud.profile.key=='unapplied-fixture-key' and cloud.draft.translationPrompt=='未套用提示詞')
assert(cloud:apply() and requests[#requests].settings.officialAutoDownload==false)
for _,width in ipairs({64,80}) do
    cloud.subviews.window.frame.w=width-2;cloud.subviews.pages:setSelected(4)
    cloud:updateLayout(gui.ViewRect{rect={x1=0,y1=0,x2=width-1,y2=29}})
    for _,id in ipairs({'officialAutoDownload','official_sync','official_phase','official_entries','official_help','official_offline'}) do
        local rect=cloud.subviews[id].frame_body;local window=cloud.subviews.window.frame_body
        assert(rect.x1>=window.x1 and rect.x2<=window.x2 and rect.y2<cloud.subviews.apply.frame_body.y1,'Cloud page clips at '..width)
    end
end
fake.submit=cloud_submit
local sharing=env.SettingsScreen{}
sharing.isActive=function() return true end
sharing.profile.key='unapplied-share-fixture-key';sharing.draft.translationPrompt='共享頁未套用提示詞'
assert(sharing.draft.sharedContributions==false)
fake.submit=function(request,callback)
    requests[#requests+1]=request
    if request.action=='shared-clear' then callback({ok=true}) end
    return true
end
sharing.subviews.sharedContributions:cycle()
assert(sharing.draft.sharedContributions==true)
assert(sharing:clear_shared())
assert(requests[#requests].action=='shared-clear' and requests[#requests].settings==nil)
assert(sharing.profile.key=='unapplied-share-fixture-key' and sharing.draft.translationPrompt=='共享頁未套用提示詞')
for _,width in ipairs({64,80}) do
    sharing.subviews.window.frame.w=width-2;sharing.subviews.pages:setSelected(5)
    sharing:updateLayout(gui.ViewRect{rect={x1=0,y1=0,x2=width-1,y2=29}})
    for _,id in ipairs({'sharedContributions','shared_privacy','shared_phase','shared_clear'}) do
        local rect=sharing.subviews[id].frame_body;local window=sharing.subviews.window.frame_body
        assert(rect.x1>=window.x1 and rect.x2<=window.x2 and rect.y2<sharing.subviews.apply.frame_body.y1,'Share page clips at '..width)
    end
end
assert(sharing:apply())
assert(requests[#requests].settings.sharedContributions==true and requests[#requests].settings.translationPrompt=='共享頁未套用提示詞',
    'Apply must preserve sharing consent and the pending prompt draft together')
local shared_requests=#requests
sharing:onDismiss()
assert(#requests==shared_requests,'Closing the sharing page must not submit another request')
fake.submit=cloud_submit
-- Exercise save/refresh, not only the outgoing draft: a disabled API must stay
-- selected and visibly off while the other API and master switch stay enabled.
snapshot.document.defaults.apiPoolEnabled=true
snapshot.document.defaults.apiProfiles={'legacy','other'}
snapshot.profiles.other.enabled=true
local independent=env.SettingsScreen{}
independent.isActive=function() return true end
independent:select_profile('other')
independent.subviews.apiParticipating:cycle()
assert(not independent:profile_participating() and independent.draft.apiEnabled,
    'Disabling this API must leave the master switch enabled')
local original_submit=fake.submit
fake.submit=function(request,callback)
    assert(request.scope=='global' and request.settings.apiEnabled,
        'An individual toggle must not disable all model services')
    assert(#request.settings.apiProfiles==1 and request.settings.apiProfiles[1]=='legacy',
        'An individual toggle must preserve the other active API')
    for key,value in pairs(request.settings) do snapshot.document.defaults[key]=value end
    callback({ok=true,snapshot=snapshot})
    return true
end
assert(independent:apply())
assert(independent.profile_id=='other','Apply must keep the API being edited selected')
assert(independent.subviews.apiParticipating:getOptionValue()==false,
    'The disabled API must still display off after saving')
independent:select_profile('legacy')
assert(independent.subviews.apiParticipating:getOptionValue()==true,
    'The other API must remain independently enabled')
independent:select_profile('other')
independent:load_draft();independent:refresh_fields()
assert(independent.profile_id=='other' and not independent:profile_participating(),
    'Reloading a saved draft must retain the current API and its disabled state')
fake.submit=original_submit
assert_native_text(independent.subviews.apiEnabled,'所有模型服務')
assert_native_text(independent.subviews.apiParticipating,'啟用此')
snapshot.document.defaults.apiProfiles={'legacy','other'}
local deleting=env.SettingsScreen{}
deleting:select_profile('other')
local request_count=#requests
deleting:delete_profile()
assert(#requests==request_count and snapshot.profiles.other,
    'Deleting must remain a cancellable draft until Apply')
assert(deleting.profile_id=='legacy' and #deleting.active_profiles==1 and deleting.active_profiles[1]=='legacy')
for _,option in ipairs(deleting:profile_options()) do assert(option.value~='other') end
assert(deleting:apply())
local deletion_request=requests[#requests]
assert(#deletion_request.deleteProfiles==1 and deletion_request.deleteProfiles[1]=='other')
for _,update in ipairs(deletion_request.profiles) do assert(update.id~='other') end
assert_native_text(deleting.subviews.delete_profile,'刪除設定檔')
snapshot.profiles.other=nil
snapshot.document.defaults.apiProfiles={'legacy'}
local last=env.SettingsScreen{}
last:delete_profile()
assert(#last.active_profiles==0 and last.draft.apiPoolEnabled,
    'Deleting the last profile must retain an explicitly empty pool')
assert(last:apply(),'An empty profile list must still be saveable')
assert(requests[#requests].deleteProfiles[1]=='legacy')
snapshot.profiles.legacy=nil
snapshot.document.defaults.apiPoolEnabled=true
snapshot.document.defaults.apiProfiles={}
last:load_draft();last:refresh_fields()
assert(not last:has_profile(),'An empty list must show a placeholder without a real API')
assert(last:profile_options()[1].label=='尚無設定檔','The empty selector must show an explicit placeholder')
assert(not require('utils').getval(last.subviews.delete_profile.enabled),
    'The empty placeholder must not be deletable')
last:new_profile()
assert(last:has_profile() and last.profile_id=='profile-1' and #last.active_profiles==1,
    'A new profile must be addable after deleting the last one')
last:delete_profile()
assert(#last:deleted_profile_ids()==0,'An unsaved profile must be discarded without a server deletion')
print('SETTINGS_UI_FIXTURE PASS profile deletion, independent API toggles, saved editor selection, prompt drafts, reset, Unicode editing and 64/80-column bounds')
