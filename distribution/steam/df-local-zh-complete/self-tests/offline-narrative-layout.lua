local env = setmetatable({dfhack={df2utf=function(value) return value end}}, {__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-narrative.lua','t',env))()
local rows = {
    {str='Vadane',px=0,py=0,link_index=-1},
    {str='met',px=7,py=0,link_index=-1},
    {str='Vadane',px=11,py=0,link_index=0,red=0,green=128,blue=255},
    {str='Other',px=18,py=0,link_index=0},
    {str='in',px=24,py=0,link_index=-1},
    {str='12.',px=27,py=0,link_index=-1},
    {str='',px=-1,py=-1,link_index=-1},
    {str='Next',px=0,py=2,link_index=-1},
}
local words = setmetatable({}, {__len=function() return #rows end})
for i,row in ipairs(rows) do words[i-1]=row end
local paragraphs = env.capture(words, {[0]={type=0,id=21}}, 20)
assert(#paragraphs==2 and paragraphs[1].source=='Vadane met {{DFL0}} in 12.',
    'A paragraph must keep prose context while protecting exact linked spans')
assert(paragraphs[1].request_links[1].text=='Vadane Other' and
    paragraphs[1].request_links[1].id==21 and paragraphs[1].links[1].px==11,
    'Target identity and original click coordinates must survive capture')
assert(words[2].str=='Vadane' and words[2].px==11, 'Capture must not alter native words')
-- Only a verified native subject name may protect a biography prefix. Its
-- original colors survive; a substring, linked name, or later paragraph cannot.
local biography_rows={
    {str='Urist',px=0,py=0,link_index=-1,red=0,green=128,blue=255},
    {str='𠮷',px=6,py=0,link_index=-1},
    {str='was a human born in 55. He was the third eldest son of',px=10,py=0,link_index=-1},
    {str='Parent One',px=0,py=1,link_index=0},
    {str='and',px=11,py=1,link_index=-1},
    {str='Parent Two',px=15,py=1,link_index=1},
    {str='',px=-1,py=-1,link_index=-1},
    {str='Urist 𠮷 was a human',px=0,py=3,link_index=-1},
}
local biography_words=setmetatable({},{__len=function() return #biography_rows end})
for i,row in ipairs(biography_rows) do biography_words[i-1]=row end
local parents={[0]={type=0,id=11},[1]={type=0,id=12}}
local biography=env.capture(biography_words,parents,20,'Urist 𠮷')
assert(biography[1].local_source=='{{DFT0}} was a human born in 55. He was the third eldest son of {{DFL0}} and {{DFL1}}',
    'A verified complete subject prefix must protect the whole Unicode identity')
assert(biography[1].source=='Urist 𠮷 was a human born in 55. He was the third eldest son of {{DFL0}} and {{DFL1}}')
local biography_parts=env.parts(biography[1],{translation='{{DFT0}}是人類，生於55年。他是{{DFL0}}與{{DFL1}}的第三子。',
    literals={{translation='Urist 𠮷'}},links={{translation='Parent One'},{translation='Parent Two'}}})
assert(biography_parts[1].text=='Urist' and biography_parts[1].color==9 and biography_parts[1].link==nil)
assert(biography_parts[2].text==' 𠮷' and biography_parts[2].color==7 and biography_parts[2].link==nil,
    'Name color boundaries and supplementary characters must stay intact')
assert(biography[2].local_source==nil,'Later unlinked names are not certified biography subjects')
for _,wrong in ipairs({'Urist','Urist 𠮷 was','Different 𠮷','Urist {evil}',string.char(255)}) do
    assert(env.capture(biography_words,parents,20,wrong)[1].local_source==nil,
        'Only a complete, literal, exact native subject-name prefix may be protected')
end
biography_rows[1].link_index=0
assert(env.capture(biography_words,parents,20,'Urist 𠮷')[1].local_source==nil,
    'A local subject slot must not consume any native clickable span')
biography_rows[1].link_index=-1
assert(biography_words[1].str=='𠮷' and biography_words[1].px==6)
-- Native Legends uses type -1 for non-clickable related figures (including
-- newly born children). Their label is literal text, never a fabricated link.
local sentinel_rows={
    {str='Urist',px=0,py=0,link_index=0,red=0,green=128,blue=255},
    {str='𠮷,',px=6,py=0,link_index=0,red=0,green=128,blue=255},
    {str='only daughter, b. 95',px=10,py=0,link_index=-1},
}
local sentinel_words=setmetatable({},{__len=function() return #sentinel_rows end})
for i,row in ipairs(sentinel_rows) do sentinel_words[i-1]=row end
local sentinel=env.capture(sentinel_words,{[0]={type=-1,id=2854}},20)[1]
assert(#sentinel.links==0 and #sentinel.request_links==0,
    'An unclickable native sentinel must not enter the translation link protocol')
assert(sentinel.source=='Urist 𠮷, only daughter, b. 95',
    'Unclickable labels must remain complete literal Unicode source text')
assert(sentinel.local_source=='{{DFT0}}, only daughter, b. 95' and
    #sentinel.literals==1 and sentinel.literals[1].text=='Urist 𠮷' and
    sentinel.literals[1].color==9,
    'Native non-clickable labels need separate local text slots, with punctuation outside their identity')
local literal_parts=env.parts(sentinel,{translation='{{DFT0}}：獨生女，生於95年。',links={},
    literals={{translation='Urist 𠮷'}}})
assert(literal_parts[1].text=='Urist 𠮷' and literal_parts[1].color==9 and
    literal_parts[1].link==nil and literal_parts[2].text=='：獨生女，生於95年。',
    'Translated literal names must keep their palette and never receive a click target')
assert(sentinel_words[1].str=='𠮷,' and sentinel_words[1].link_index==0,
    'Capture must leave the original native words and sentinel identity untouched')
for _,invalid in ipairs({{type=12,id=2854},{type=0,id=-1}}) do
    local p=env.capture(sentinel_words,{[0]=invalid},20)[1]
    assert(#p.request_links==0 and p.source==sentinel.source,
        'Unsupported native records must remain literal instead of clickable')
    assert(p.local_source==nil,'Unknown link types and invalid targets cannot certify a local name span')
end
local parts = env.parts(paragraphs[1], {translation='瓦丹於12年遇見{{DFL0}}。',
    links={{translation='另一位瓦丹'}}})
assert(parts[2].text=='另一位瓦丹' and parts[2].link.id==21,
    'Translated token position must retain its target even after word order changes')
paragraphs[1].parts=parts
paragraphs[2].parts={{text='下一段中文',color=7}}
local chunks, height = env.layout(paragraphs, 12)
local link_chunks=0
for _,chunk in ipairs(chunks) do
    assert(chunk.x>=0 and chunk.x+chunk.width<=12, 'Wrapped Chinese text must fit the viewport')
    if chunk.link then link_chunks=link_chunks+1; assert(chunk.link.id==21) end
end
assert(link_chunks>=1 and height>=4, 'Wrapping must retain link identity on each drawn piece')
assert(paragraphs[2].y>paragraphs[1].y, 'A following paragraph must not overlap expanded text')
assert(parts[2].color==9, 'Figure links must retain their native blue category')

local gps={mouse_x=100,mouse_y=30}
local page={mode=1,index=20,text_box={word=words,link={[0]={type=0,id=21}},max_y=100},scroll_position_text=5}
local pages={[0]=page}
setmetatable(pages,{__len=function() return 1 end})
local vs={page=pages,active_page_index=0,histfigs={[20]=20}}
env.df={global={gps=gps,enabler={renderer={dispx=8,dispy=12}}},
    legends_mode_type={HFS=1},viewscreen_legendsst={is_instance=function(_,value) return value==vs end}}
env.dfhack.isWorldLoaded=function() return true end
env.dfhack.getSavePath=function() return 'fixture' end
env.dfhack.getTickCount=function() return 0 end
env.dfhack.gui={getCurViewscreen=function() return vs end}
env.dfhack.screen={getWindowSize=function() return 182,68 end}
local subject_reads=0
env.df.historical_figure={find=function(id)
    assert(id==20);subject_reads=subject_reads+1;return {name='Verified Name'}
end}
env.dfhack.translation={translateName=function(name,english)
    assert(english);return name
end}
env.require=function(name)
    assert(name=='gui')
    return {simulateInput=function(screen,key)
        assert(screen==vs and key=='_MOUSE_L')
        assert(env.dispatching(), 'Native dispatch must bypass the translated overlay input handler')
        assert(gps.mouse_x==13 and gps.mouse_y==9,
            'A translated link must dispatch to the original native word coordinates')
        assert(page.scroll_position_text==0)
    end}
end
local runtime={paragraph_lookup=function() return nil end}
local initial=assert(env.view(runtime), 'A detail view must be available before its first translation')
assert(subject_reads==1)
env.view(runtime)
assert(subject_reads==1,'The authoritative subject-name query must run once per capture, never per frame')
assert(initial.hidden and page.scroll_position_text>page.text_box.max_y,
    'Native rendering must be hidden before the first async translation response')
assert(env.poll(runtime))
assert(page.scroll_position_text>page.text_box.max_y, 'Native rendering must be hidden without editing words')
assert(env.click(paragraphs[1].links[1]))
assert(gps.mouse_x==100 and gps.mouse_y==30, 'Native click dispatch must restore the mouse')
words[2].px,words[2].py=3,30
env.require=function(name)
    assert(name=='gui')
    return {simulateInput=function()
        assert(env.dispatching(), 'Native dispatch must bypass the translated overlay input handler')
        assert(gps.mouse_x==5 and gps.mouse_y==9 and page.scroll_position_text==30,
            'Resized native text must use current target coordinates instead of captured positions')
    end}
end
assert(env.click(paragraphs[1].links[1]))
page.text_box.link[0].id=22
assert(not env.click(paragraphs[1].links[1]), 'A stale target must never dispatch to a different entity')
page.text_box.link[0].id=21
env.dfhack.screen.getWindowSize=function() return 30,12 end
assert(not env.poll(runtime))
assert(page.scroll_position_text==5, 'Unsupported viewport must restore native text immediately')
env.dfhack.screen.getWindowSize=function() return 182,68 end
assert(env.poll(runtime))
rows[#rows+1]={str='Extra',px=0,py=4,link_index=-1}
words[#rows-1]=rows[#rows]
assert(env.poll(runtime))
local visible
runtime.paragraph_visibility_id=function(source) return source end
runtime.set_visible=function(ids) visible=ids end
for index=1,40 do
    rows[#rows+1]={str='',px=-1,py=-1,link_index=-1}
    words[#rows-1]=rows[#rows]
    rows[#rows+1]={str='Paragraph '..index,px=0,py=index*2+4,link_index=-1}
    words[#rows-1]=rows[#rows]
end
assert(env.poll(runtime))
assert(visible and #visible>0 and #visible<40,
    'Only visible paragraphs should be marked for translation')
local first_visible=visible[1]
assert(env.scroll(100))
assert(env.poll(runtime))
assert(visible[1]~=first_visible,'Scrolling must replace the visible paragraph set')
local selected_mode='繁'
runtime.narrative_mode=function() return selected_mode end
runtime.paragraph_lookup=function(source,links)
    local translated={translation=selected_mode..source,links={}}
    for i,link in ipairs(links) do translated.links[i]={translation=link.text} end
    return translated
end
env.scroll(-10000)
assert(env.poll(runtime))
assert(env.view(runtime).paragraphs[1].parts[1].text:sub(1,#selected_mode)==selected_mode)
selected_mode='简'
assert(env.poll(runtime))
assert(env.view(runtime).paragraphs[1].parts[1].text:sub(1,#selected_mode)==selected_mode,
    'Changing translation mode must invalidate cached original or translated paragraphs')
-- A terminal rejection reveals native text. An I/O failure remains retryable
-- with backoff instead of appending to disk on every render poll.
selected_mode='native-original'
runtime.paragraph_lookup=function(source,links)
    local result={translation=source,links={},native_fallback=true}
    for i,link in ipairs(links) do result.links[i]={translation=link.text} end
    return result,'ready'
end
env.poll(runtime)
local retained=env.view(runtime).paragraphs[1]
assert(retained.parts==retained.original_parts,
    'Original fallback must use native spans instead of recoloring them as translated prose')
local clock=1000
env.dfhack.getTickCount=function() return clock end
local attempts=0
selected_mode='invalid'
runtime.paragraph_lookup=function()
    attempts=attempts+1
    return nil,'invalid'
end
assert(env.poll(runtime))
local rejected=env.view(runtime).paragraphs[1]
local original={}
for _,part in ipairs(rejected.parts or {}) do original[#original+1]=part.text end
assert(table.concat(original)=='Vadane met Vadane Other in 12.',
    'A rejected paragraph must show native source without DFL tokens or pending text')
local original_link
for _,part in ipairs(rejected.parts) do if part.link then original_link=part.link end end
assert(original_link and original_link.id==21 and original_link.type==0,
    'Readable fallback must preserve valid native click identities')
assert(sentinel.original_parts and sentinel.original_parts[1].color==9 and
    sentinel.original_parts[1].link==nil,
    'Sentinel fallback must preserve its Unicode palette without inventing a target')
-- Finish all visible invalid paragraphs, then ensure they stop consuming work.
for _=1,20 do env.poll(runtime) end
local terminal_attempts=attempts
env.poll(runtime)
assert(attempts==terminal_attempts, 'Terminal paragraphs must release the per-poll work budget')
selected_mode='failed'
runtime.paragraph_lookup=function() attempts=attempts+1;return nil,'failed','fixture write error' end
env.poll(runtime)
local failed=env.view(runtime).paragraphs[1]
assert(failed.parts and failed.retry_at>clock,
    'A transient write failure must display source and schedule a retry')
local delayed=failed.retry_at
clock=delayed-1
env.poll(runtime)
assert(failed.retry_at==delayed, 'Failed paragraphs must back off before retrying')
runtime.paragraph_lookup=function(source,links)
    local translated={translation='重試'..source,links={}}
    for i,link in ipairs(links) do translated.links[i]={translation=link.text} end
    return translated,'ready'
end
clock=delayed
env.poll(runtime)
assert(failed.parts[1].text:sub(1,#'重試')=='重試' and not failed.retry_at,
    'Recovered I/O must replace fallback with its completed translation')

env.suspend()
assert(page.scroll_position_text==5, 'Disabling translated rendering must restore native scrolling')
print('Narrative capture, structural links, word-order restoration, and Chinese wrapping verified')
