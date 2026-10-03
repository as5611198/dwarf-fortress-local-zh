-- Read-only fixtures for the binding-label adapter; no input or screenshots.
local json = require('json')
local source = (...) or (reqscript('df-local-zh-paths').source() ..
    '/scripts_modinstalled/df-local-zh-keybinding-labels.lua')
local submitted, scheduled, cancelled, timer
local env = setmetatable({
    df={settings_tab_type={KEYBINDINGS=3}, global={game={main_interface={}}},
        sizeof=function(label) return 32,label.address end},
    dfhack={onStateChange={},timeout=function(_,_,callback) timer=callback end},
    reqscript=function() return {native_literal_rows_set=function(data)
        submitted=json.decode(data);return true end} end,
    require=function(name)
        if name=='repeat-util' then return {
            scheduleUnlessAlreadyScheduled=function(_,_,_,callback)
                scheduled=callback;callback() end,
            cancel=function() cancelled=true end} end
        return require(name)
    end,
}, {__index=_G})
assert(loadfile(source,'t',env))()
local labels={}
for i=1,341 do labels[i]={value='Shift+Numpad Enter',address=100+i} end
labels[1].value='Home';labels[2].value='End';labels[3].value='Ctrl+Mwheel up'
labels[4].value='';labels[5].value='Enter\n';labels[6].value=string.char(255)
local s={open=true,current_mode=3,keybinding_selected_category=0,
    keybinding_binding_name={[0]=labels},keybinding_name={'Confirm'}}
env.df.global.game.main_interface.settings=s
local rows=env.collect(s)
assert(#rows==338,'Full category collected, empty/control/non-ASCII rejected')
assert(rows[1].source=='Home' and rows[1].translation=='Home' and rows[1].width==4)
assert(rows[1].address==101,'Must use public string address')
env.start();assert(#submitted==338)
s.keybinding_selected_category=1
s.keybinding_binding_name[1]={{value='z',address=999}}
scheduled();assert(#submitted==1 and submitted[1].source=='z','Custom/category update')
s.current_mode=0
scheduled();assert(#submitted==0,'Other settings tabs clear protected rows')
s.current_mode=3;s.open=false
assert(#env.collect(s)==0,'Closed settings must not protect unrelated text')
s.open=true;env.refresh();env.stop()
assert(cancelled and #submitted==0,'Stopping clears the batch')
env.dfhack.onStateChange.df_local_zh_keybinding_labels()
assert(timer,'Transitions schedule restart after repeat-util reset');timer()
assert(s.keybinding_name[1]=='Confirm' and labels[1].value=='Home','Never modify game fields')
print('KEYBINDING_LABELS fixtures passed')
