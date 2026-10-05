local root=dfhack.getDFPath()..'/hack/scripts'
local env=setmetatable({dfhack={df2utf=function(s)return s end}},{__index=_G})
assert(loadfile(root..'/df-local-zh-narrative.lua','t',env))()
local function words(rows)
    local out=setmetatable({},{__len=function()return #rows end})
    for i,r in ipairs(rows)do out[i-1]=r end
    return out
end
local rows={
    {str='In 41,',py=0,px=0,link_index=-1},
    {str='The Civilization',py=0,px=7,link_index=0},
    {str='held a recital of The Poem',py=0,px=24,link_index=-1},
    {str='𠮷',py=1,px=0,link_index=-1,red=0,green=128,blue=255},
    {str='in',py=1,px=3,link_index=-1},
    {str='The Town',py=1,px=6,link_index=1},
    {str='as part of The Festival.',py=1,px=15,link_index=-1},
}
local ws=words(rows)
local links={[0]={type=6,id=35},[1]={type=1,id=9}}
local names={'The Festival','The Poem 𠮷'}
local p=env.capture(ws,links,nil,nil,names)[1]
assert(p.local_source=='In 41, {{DFL0}} held a recital of {{DFT0}} in {{DFL1}} as part of {{DFT1}}.',
    'Verified native occasion/form names must become local slots while the complete grammar remains visible')
assert(p.source=='In 41, {{DFL0}} held a recital of The Poem 𠮷 in {{DFL1}} as part of The Festival.')
assert(#p.literals==2 and p.literals[1].text=='The Poem 𠮷' and p.literals[2].text=='The Festival')
local output=env.parts(p,{translation='41年，{{DFL0}}在{{DFL1}}舉行了{{DFT0}}的朗誦，作為{{DFT1}}的一部分。',
    links={{translation='The Civilization'},{translation='The Town'}},
    literals={{translation='The Poem 𠮷'},{translation='The Festival'}}})
local matched=0
for _,part in ipairs(output)do
    if part.text=='The Poem' then matched=matched+1;assert(part.color==7 and not part.link)end
    if part.text==' 𠮷' then matched=matched+1;assert(part.color==9 and not part.link)end
end
assert(matched==2,'An unlinked Unicode name must preserve every original color boundary without gaining a target')
assert(ws[3].str=='𠮷' and ws[1].link_index==0 and #p.links==2 and #p.request_links==2)
for _,bad in ipairs({'The Poem {bad}',string.char(255)})do
    local q=env.capture(ws,links,nil,nil,{bad})[1]
    assert(not q.local_source,'Partial or invalid names must not certify literal slots')
end
for _,short in ipairs({'The Poem','Poem 𠮷'})do
    local q=env.capture(ws,links,nil,nil,{short})[1]
    local restored=q.local_source
    for i,l in ipairs(q.literals)do restored=restored:gsub('{{DFT'..(i-1)..'}}',function()return l.text end)end
    assert(restored==q.source,'Unmatched title words must remain explicit prose, never be hidden inside slots')
end
local unknown=env.capture(ws,links,nil,nil,{'The Town','The Civilization'})[1]
assert(not unknown.local_source,'A context name must never consume a native clickable span')
local repeated=words({{str='The Poem 𠮷 and The Poem 𠮷',px=0,py=0,link_index=-1}})
local twice=env.capture(repeated,{},nil,nil,names)[1]
assert(twice.local_source=='{{DFT0}} and {{DFT1}}' and #twice.literals==2,
    'Repeated native identities need separate occurrence slots')
local too_many=words({{str=string.rep('The Festival and ',8)..'The Festival',px=0,py=0,link_index=-1}})
assert(not env.capture(too_many,{},nil,nil,names)[1].local_source,
    'Over-budget protection must fall back atomically instead of hiding only some names')
local reads={entity=0,poem=0,site=0}
env.df={legends_mode_type={ENTITIES=6,HFS=1},
    global={world={world_data={name='The Realm'}}},
    occasion_schedule_type={[0]='POETRY_RECITAL',[1]='PROCESSION',[2]='CEREMONY'},
    occasion_schedule_feature={[0]='POETRY_RECITAL'},
    historical_entity={find=function(id)
        assert(id==35);reads.entity=reads.entity+1
        return {occasion_info={occasions={{name='The Festival',site=9,schedule={
            {type=0,reference=13,features={}},
            {type=2,reference=-1,features={{feature=0,reference=13}}},
            {type=1,reference=4,reference2=4,features={}},
        }}}}}
    end},poetic_form={find=function(id)
        assert(id==13);reads.poem=reads.poem+1;return {name='The Poem 𠮷'}
    end},world_site={find=function(id)
        assert(id==9);reads.site=reads.site+1;return {buildings={{id=4,name='The Hall'}}}
    end}}
env.dfhack.translation={translateName=function(name,english)assert(english);return name end}
local context=assert(env.context_names({mode=6,index=0},{entities={[0]=35}}))
local found={};for _,n in ipairs(context)do found[n]=true end
assert(#context==5 and found['The Realm'] and found['the Realm'] and found['The Festival'] and
    found['The Poem 𠮷'] and found['The Hall'])
assert(reads.entity==1 and reads.poem==1 and reads.site==1,
    'Repeated native form/building references must be resolved once per page capture')
assert(env.context_names({mode=1,index=0},{})==nil and reads.entity==1,
    'Other page modes must not scan entity occasions')
local intro=env.capture(words({{str='The Civilization',px=0,py=0,link_index=0},
    {str='was a human civilization of the Realm.',px=20,py=0,link_index=-1}}),links,nil,nil,context)[1]
assert(intro.local_source=='{{DFL0}} was a human civilization of {{DFT0}}.' and intro.literals[1].text=='the Realm')
local event_reads=0
env.df.entity_occasion_purpose_type={[1]='COMMEMORATE_EVENT'}
env.df.histfig_entity_link_type={[0]='POSITION'}
env.df.history_event_add_hf_entity_linkst={is_instance=function(_,e)return e.position==true end}
env.df.history_event={find=function(id)
    assert(id==471);event_reads=event_reads+1;return {position=true,histfig=103,civ=35,link_type=0}
end}
env.df.historical_figure={find=function(id)assert(id==103);return {name='Urist 𠮷'}end}
env.df.historical_entity.find=function(id)
    assert(id==35);return {id=35,name='The Civilization',occasion_info={occasions={
        {name='The Festival',purpose=1,purpose_id=471,schedule={}},
        {name='The Festival',purpose=1,purpose_id=471,schedule={}},
    }}}
end
local commemorative=assert(env.context_names({mode=6,index=0},{entities={[0]=35}}))
local story=env.capture(words({{str='The Civilization',px=0,py=0,link_index=0},
    {str='held the story of the ascension of the human Urist 𠮷 to the position of law-giver of The Civilization in 70 in',px=20,py=0,link_index=-1},
    {str='The Town',px=0,py=1,link_index=1},
    {str='as part of The Festival.',px=20,py=1,link_index=-1}}),links,nil,nil,commemorative)[1]
assert(story.local_source=='{{DFL0}} held the story of the ascension of the human {{DFT0}} to the position of law-giver of {{DFT1}} in 70 in {{DFL1}} as part of {{DFT2}}.' and event_reads==1,
    'A native commemorated POSITION event must certify its figure and entity exactly once')
-- Closing a tab must release its cached capture. Reusing the same native page
-- address and word count must read the new text instead of resurrecting prose.
local queries=0
env.context_names=function()queries=queries+1;return nil end
local a={mode=8,index=1,text_box={word=words({{str='Old source',px=0,py=0,link_index=-1}}),link={},max_y=10},scroll_position_text=0}
local b={mode=8,index=2,text_box={word=words({{str='Other source',px=0,py=0,link_index=-1}}),link={},max_y=10},scroll_position_text=0}
local pages=setmetatable({[0]=a},{__len=function()return 1 end})
local vs={page=pages,active_page_index=0}
env.df.viewscreen_legendsst={is_instance=function(_,v)return v==vs end}
env.df.global.enabler={renderer={dispx=8,dispy=12}}
env.dfhack.isWorldLoaded=function()return true end
env.dfhack.getSavePath=function()return 'fixture' end
env.dfhack.gui={getCurViewscreen=function()return vs end}
env.dfhack.screen={getWindowSize=function()return 100,60 end}
env.dfhack.printerr=function(s)error(s)end
assert(env.view({}).paragraphs[1].source=='Old source')
env.view({});assert(queries==1,'Native name context must not be polled each frame')
pages[0]=b;assert(env.view({}).paragraphs[1].source=='Other source')
pages[0]=a;a.text_box.word[0].str='New source'
assert(env.view({}).paragraphs[1].source=='New source' and queries==3,
    'A closed native tab must not retain stale text or dead page pointers')
print('LEGENDS_OCCASION_NAMES PASS')
