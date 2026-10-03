-- Runs against installed production modules without modifying settings or saves.
local history=reqscript('df-local-zh-history')
local adventure=reqscript('df-local-zh-adventure')
local diagnostics=reqscript('df-local-zh-local-diagnostics')
local rename=reqscript('df-local-zh-rename')
local native=reqscript('df-local-zh-core/native')
local json=require('json')
local event=df.history_event_hist_figure_diedst:new()
event.id=12;event.year=250;event.victim_hf=10;event.slayer_hf=-1;event.site=-1
local row=history.structured(event,function(_,id) return id==10 and 'Urist「𠮷」' or '' end)
assert(row.kind=='HIST_FIGURE_DIED')
local rendered=native.history_event_render(json.encode(row))
assert(rendered:find('Urist「𠮷」',1,true) and not rendered:find('殺害者',1,true))
event:delete()
local rows=adventure.collect({adventure_log_event={{summary='An actual journal summary',list_name='ignored'}},
    site_entry={{list_name='鐵城𠮷'}},histfig_entry={{simple_list_name='Urist'}}})
assert(#rows==3 and rows[1].source=='An actual journal summary' and rows[2].source=='鐵城𠮷')
assert(#adventure.collect({unknown=1})==0)
local sample={summary={world='fixture',screen_type='journal',focus={'adventure_log'}},strings={
    {field_id='summary',text='Unknown source',classification='latin_residual'},
    {field_id='summary',text='Unknown source',classification='latin_residual'},
    {field_id='summary',text='中文',classification='cjk_only'}}}
local seen={};assert(#diagnostics.select_rows(sample,seen,10)==1)
assert(#diagnostics.select_rows(sample,seen,10)==0)
sample.summary.world='second';assert(#diagnostics.select_rows(sample,seen,10)==1)
assert(#diagnostics.select_rows(sample,{},0)==0)
assert(rename.valid('鐵匠𠮷 A1') and not rename.valid('bad\nname') and not rename.valid(string.rep('字',65)))
local unit=df.unit:new();unit.name.nickname='fixture'
local screen=rename.show(unit)
screen.subviews.name_edit:setText('未套用𠮷');screen:dismiss()
assert(unit.name.nickname=='fixture','Cancel must not write nickname');unit:delete()
local settings=reqscript('df-local-zh-settings-ui')
local prompt=settings.PromptScreen{value='fixture prompt',default_text='',on_accept=function() error('Cancel must not accept') end}:show()
prompt.subviews.prompt_text:setText('未保存草稿\n𠮷');prompt:dismiss()
local secret=settings.SecretField{value='fixture-key'}
secret:setValue('中文');assert(secret.value=='fixture-key')
assert(native.glyph_font_index('zh-Hant',0x9435)>=0,'Primary must cover 鐵')
assert(native.glyph_font_index('zh-Hant',0x20bb7)>=0,'Font chain must cover 𠮷 on this Windows host')
assert(native.glyph_font_index('zh-Hant',0x20000)>0,'Windows fallback must cover a character missing from the primary')
assert(native.glyph_font_index('zh-Hant',0x10ffff)==-1,'Missing codepoint must not claim coverage')
print('EXTENDED_ADAPTERS passed')
