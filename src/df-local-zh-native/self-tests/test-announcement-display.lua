local root=dfhack.getDFPath()
local source='The workers have completed 17 stairways.'
local translated='工人們已完成 17 座樓梯。'
local widget={str=source,fg=6,bright=true,children={}}
local date={str='Date: 18th Granite, 250',fg=7,children={}}
local labels={'General','Death'}
local stack={tab_labels=labels,children={widget,date}}
local alert={value='[C:6:0:1]'..source}
local reports={[0]={id=1,text=source,color=6,bright=true}}
local events={onReport={},eventType={REPORT=1},enableEvent=function() end}
local world,ready='display-world',false
local colors={}
local main={announcements={stack=stack},announcement_alert={
    alert_text={text=setmetatable({[0]=alert},{__len=function() return 1 end})},uac_text={text={}}}}
local env=setmetatable({
    df={global={world={status={reports=reports}},game={main_interface=main}},
        report={find=function() return reports[0] end}},
    dfhack={isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,df2utf=function(value) return value end,
        timeout=function() end,printerr=error},
    require=function(name) assert(name=='plugins.eventful');return events end,
    reqscript=function(name)
        if name=='df-local-zh-core/mod' then return {async_translate=function() return nil end} end
        assert(name=='df-local-zh-runtime')
        return {prefetch=function() return false end,publish_native=function() return true end,
            native_ready=function() return false end,
            on_translation=function(_,fn) fn(translated);return function() end end,
            announcement_key=function(text,color)
                colors[#colors+1]=color:byte()
                if not ready then return nil end
                if text=='[C:6:0:1]'..translated then return 'COLORED_ALERT_ALIAS' end
                assert(text==translated);return 'ANNOUNCEMENT_ALIAS'
            end}
    end,
},{__index=_G})
assert(loadfile(root..'/hack/scripts/df-local-zh-reports.lua','t',env))()
events.onReport.df_local_zh_reports(1)
env.refresh_display()
assert(widget.str==source,'A native alias must be ready before replacing the widget')
ready=true;env.refresh_display()
assert(widget.str=='ANNOUNCEMENT_ALIAS','Cached native misses need a fresh display alias')
assert(alert.value=='COLORED_ALERT_ALIAS','Alert markup must use the same report translation')
assert(widget.fg==6 and widget.bright,'Widget colors must remain unchanged')
assert(reports[0].text==source,'Display preparation must never mutate saved report text')
assert(date.str=='Date: 18th Granite, 250' and labels[1]=='General',
    'Unrelated widgets and tab sources must remain intact')
env.refresh_display();assert(widget.str=='ANNOUNCEMENT_ALIAS','Existing aliases must remain stable')
world='another-world';env.refresh_display()
assert(widget.str==source and alert.value=='[C:6:0:1]'..source,
    'World changes must restore UI aliases and discard previous report translations')
events.onReport.df_local_zh_reports(1);env.refresh_display()
widget.str='A new unrelated widget value.';env.refresh_display()
assert(widget.str=='A new unrelated widget value.','A rebuilt widget must not reuse stale prose')
env.stop()
assert(alert.value=='[C:6:0:1]'..source,'Stopping must restore only owned UI aliases')
assert(widget.str=='A new unrelated widget value.','Restore must preserve subsequent game updates')
local many={}
for i=1,600 do many[i]={str=source,fg=6,bright=true,children={}} end
stack.children=many
local late={value='[C:6:0:1]'..source}
main.announcement_alert.alert_text.text=setmetatable({[99]=late},{__len=function() return 100 end})
main.announcement_alert.scroll_position_alert=99
env.start();events.onReport.df_local_zh_reports(1)
for _=1,4 do env.refresh_display() end
for _,row in ipairs(many) do assert(row.str=='ANNOUNCEMENT_ALIAS',
    'Bounded widget traversal must rotate through later announcement rows') end
assert(late.value=='COLORED_ALERT_ALIAS','Alert preparation must follow the current scroll position')
env.stop()
for _,row in ipairs(many) do assert(row.str==source,'Stop must restore all owned rows beyond the per-frame budget') end
assert(late.value=='[C:6:0:1]'..source,'Stop must restore previously scrolled alert rows')
print('PASS announcement widgets and alert aliases, native misses, readiness, colors and source restoration')
