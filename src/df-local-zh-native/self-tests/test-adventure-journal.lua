-- Native event headings must translate verified prose without touching journal or save fields.
local env=setmetatable({},{__index=_G})
local unit_script=dfhack.findScript('df-local-zh-unit-text')
assert(loadfile(dfhack.findScript('df-local-zh-adventure-journal'),'t',env))()
local key="{JOURNAL_FIGURE}'s presence in {JOURNAL_SITE}"
local requested={}
local target='{JOURNAL_FIGURE}出現在{JOURNAL_SITE}'
local function lookup(source)
    requested[#requested+1]=source
    assert(source==key,'Only the reviewed template reaches the translation lookup')
    return target
end
assert(env.translate_presence("Hero's presence in Test Cave",'Hero','Test Cave',lookup)=='Hero出現在Test Cave')
assert(env.translate_presence("Hero's presence in Test Cave",'Other Hero','Test Cave',lookup)==nil)
assert(env.translate_presence("Hero's presence in Test Cave",'Hero','Other Cave',lookup)==nil)
assert(env.translate_presence("Hero's presence in Test Cave. Extra",'Hero','Test Cave',lookup)==nil)
assert(env.translate_presence("𠮷's presence in 測試洞穴",'𠮷','測試洞穴',lookup)=='𠮷出現在測試洞穴')
target='Partly English {JOURNAL_FIGURE}{JOURNAL_SITE}'
assert(env.translate_presence("Hero's presence in Test Cave",'Hero','Test Cave',lookup)==nil)
target='{JOURNAL_FIGURE}出現在{JOURNAL_SITE}{JOURNAL_SITE}'
assert(env.translate_presence("Hero's presence in Test Cave",'Hero','Test Cave',lookup)==nil)
target='{JOURNAL_FIGURE}出現在{JOURNAL_SITE}'
assert(env.translate_presence("Hero\t's presence in Test Cave",'Hero\t','Test Cave',lookup)==nil)
local function vector(rows)
    local result={}
    for i,row in ipairs(rows) do result[i-1]=row end
    return setmetatable(result,{__len=function() return #rows end})
end
local function event(figure_id,site_id,source,lines,address)
    local e={type=1,rumor={type=4,data={beast={histfig_id=figure_id,site_id=site_id,region_id=-1}}},
        summary=source,p_list_name=source,p_list_box={text=vector(lines)}}
    function e:_field(name) assert(name=='p_list_name');return {address=address} end
    return e
end
env.df={historical_figure={find=function(id) return id==1 and {name='Hero'} end},
    world_site={find=function(id) return id==2 and {name='Test Cave'} end}}
env.dfhack={df2utf=function(s) return s end,
    sizeof=nil,translation={translateName=function(name) return name end}}
env.df.sizeof=function(ref) return 32,ref.address end
local first=event(1,2,"Hero's presence in Test Cave",{
    {value="Hero's presence in ",address=100},{value='Test Cave',address=101}},200)
local second=event(1,2,"Hero's presence in Test Cave",{},201)
local missing=event(999,2,"Unknown's presence in Test Cave",{},202)
local unrelated=event(1,2,"Hero's presence in Other Cave",{},203)
local union=event(1,2,"Hero's presence in Test Cave",{},204);union.rumor.type=5
local screen={mode=0,adventure_log_event=vector{first,second,missing,unrelated,union},scroll_position_events=0}
local rows=env.bindings(screen,lookup)
assert(#rows==3,'Both wrapped and single-field native paths bind; unknown identities and union variants fall back')
assert(rows[1].address==100 and rows[1].source=="Hero's presence in " and rows[1].translation=='Hero出現在Test Cave' and rows[1].width==19)
assert(rows[2].address==101 and rows[2].translation=='','Unused native continuation is suppressed')
assert(rows[3].address==201 and rows[3].translation=='Hero出現在Test Cave')
for _,row in ipairs(rows) do assert(row.verified_name_literals==true) end
assert(first.summary=="Hero's presence in Test Cave" and first.p_list_box.text[0].value=="Hero's presence in ",'No native strings or persistent fields are changed')
first.p_list_box.text[0].value='unrelated visible text'
assert(#env.bindings(screen,lookup)==1,'Reject rows that do not reconstruct the proven complete summary')
first.p_list_box.text[0].value='';first.p_list_box.text[1].value=first.summary
assert(#env.bindings(screen,lookup)==1,'Never assign the title to an empty native row that the renderer skips')
screen.scroll_position_events=4
assert(#env.bindings(screen,lookup)==0,'Honor the current viewport instead of translating the first entries forever')
-- Actual group and army-rumor variants use entity IDs, never figure IDs or text guesses.
env.df.historical_entity={find=function(id) return id==3 and {name='The Test Crew'} end}
local group=event(1,2,"The Test Crew's presence in Test Cave",{},401)
group.rumor={type=5,data={group={entity_id=3,site_id=2}}}
local harass=event(1,2,"The Test Crew's harassment of Test Cave",{},402)
harass.rumor={type=6,data={harass={entity_id=3,site_id=2,army_leader_hf_id=1}}}
local missing_group=event(1,2,"The Test Crew's presence in Test Cave",{},403)
missing_group.rumor={type=5,data={group={entity_id=999,site_id=2}}}
local wrong_group=event(1,2,"Another Crew's presence in Test Cave",{},404)
wrong_group.rumor=group.rumor
local wrong_site=event(1,2,"The Test Crew's harassment of Unknown Cave",{},405)
wrong_site.rumor=harass.rumor
local extra_clause=event(1,2,"The Test Crew's harassment of Test Cave. Extra",{},406)
extra_clause.rumor=harass.rumor
local invalid_site=event(1,2,"The Test Crew's harassment of Test Cave",{},407)
invalid_site.rumor={type=6,data={harass={entity_id=3,site_id=-1,army_leader_hf_id=1}}}
local harass_key="{JOURNAL_FIGURE}'s harassment of {JOURNAL_SITE}"
local harass_target='{JOURNAL_FIGURE}騷擾{JOURNAL_SITE}'
local function rumor_lookup(source)
    requested[#requested+1]=source
    if source==key then return '{JOURNAL_FIGURE}出現在{JOURNAL_SITE}' end
    assert(source==harass_key,'Only reviewed generic templates reach lookup; world names remain local literals')
    return harass_target
end
screen={mode=0,adventure_log_event=vector{group,harass,missing_group,wrong_group,wrong_site,extra_clause,invalid_site},scroll_position_events=0}
rows=env.bindings(screen,rumor_lookup)
assert(#rows==2,'Supported group presence and harassment bind; incorrect or missing IDs and extra clauses fall back')
assert(rows[1].address==401 and rows[1].translation=='The Test Crew出現在Test Cave')
assert(rows[2].address==402 and rows[2].translation=='The Test Crew騷擾Test Cave')
assert(group.summary=="The Test Crew's presence in Test Cave" and harass.summary=="The Test Crew's harassment of Test Cave",'Generated source and save text stay English')
harass_target='{JOURNAL_FIGURE}English{JOURNAL_SITE}'
assert(#env.bindings(screen,rumor_lookup)==1,'Reject a partial-English harassment template')
harass_target='{JOURNAL_FIGURE}騷擾{JOURNAL_SITE}{JOURNAL_SITE}'
assert(#env.bindings(screen,rumor_lookup)==1,'Reject duplicated identity placeholders')
group.type=0;harass.rumor.type=99
assert(#env.bindings(screen,rumor_lookup)==0,'Never read a different rumor union or incident as a supported event')
env.df.historical_figure.find=function(id) return id==1 and {name='𠮷'} end
env.df.world_site.find=function(id) return id==2 and {name='測試洞穴'} end
target='{JOURNAL_FIGURE}被發現在{JOURNAL_SITE}'
local wide=event(1,2,"𠮷's presence in 測試洞穴",{
    {value="𠮷's presence ",address=301},{value='in 測試洞穴',address=302}},303)
screen={mode=0,adventure_log_event=vector{wide},scroll_position_events=0}
rows=env.bindings(screen,lookup)
assert(#rows==2 and rows[1].translation=='𠮷被發現在測試洞' and rows[2].translation=='穴','Wrap extension-plane glyphs only at complete UTF-8 boundaries')
wide.p_list_box.text[0].value="𠮷's ";wide.p_list_box.text[1].value='presence in 測試洞穴'
rows=env.bindings(screen,lookup)
assert(#rows==2 and rows[1].translation=='𠮷被發現在測試洞穴')
env.df.historical_figure.find=function(id) return id==1 and {name='Hero'} end
env.df.world_site.find=function(id) return id==2 and {name='Test Cave'} end
target='{JOURNAL_FIGURE}出現在{JOURNAL_SITE}'
local many={}
for i=1,600 do many[i]=event(1,2,"Hero's presence in Test Cave",{},1000+i) end
screen={mode=0,adventure_log_event=vector(many),scroll_position_events=300}
rows=env.bindings(screen,lookup)
assert(#rows==64 and rows[1].address==1301 and rows[64].address==1364,'Bound work around the actual viewport in a large journal')
local kind={}
screen._type=kind
env.df.viewscreen_adventure_logst=kind
env.df.global={game={main_interface={view_sheets={}}}}
env.dfhack.isWorldLoaded=function() return true end
env.dfhack.isMapLoaded=function() return true end
env.dfhack.getSavePath=function() return 'journal-test-world' end
env.dfhack.gui={getCurViewscreen=function() return screen end,
    getFocusStrings=function() return {'dungeonmode'} end}
local loads=0
env.reqscript=function(name)
    assert(name=='df-local-zh-adventure-journal')
    loads=loads+1;return env
end
local unit=setmetatable({},{__index=env})
assert(loadfile(unit_script,'t',unit))()
local published
local bridge={translation=lookup,display_rows=function(value) published=value end}
unit.poll(bridge)
assert(#published==64,'The sole display publisher must not erase the journal rows afterward')
unit.poll(bridge)
assert(loads==1,'Cache the script lookup across polls')
screen.mode=2
unit.poll(bridge)
assert(#published==0,'Switching away from Events must remove event bindings even while its native vector remains populated')
screen={}
unit.poll(bridge)
assert(#published==0,'Leaving the journal clears bindings before another screen can reuse its positions')
print('PASS adventure journal verified identities, complete title bindings, Unicode and native fallback')
