-- Reproduce the complete native bestiary paragraph split across string rows.
local env=setmetatable({},{__index=_G})
assert(loadfile(dfhack.findScript('df-local-zh-adventure-journal'),'t',env))()
local function vector(rows)
    local out={};for i,row in ipairs(rows) do out[i-1]=row end
    return setmetatable(out,{__len=function() return #rows end})
end
env.dfhack={df2utf=function(s) return s end}
env.df={sizeof=function(ref) return 32,ref.address end}
local first='An insect many times the size of its peers.  It is known '
local last='for its deafening buzz.'
local source=first..last
local target='一種體型是同類許多倍大的昆蟲。牠以震耳欲聾的嗡嗡聲聞名。'
local entry={p_list_name='Acorn fly, ♀',main_text_box={text=vector{
    {value=first,address=100},{value=last,address=101},{value='',address=102},
    {value='An unsupported extra paragraph.',address=103}}}}
function entry:_field(name) assert(name=='p_list_name');return {address=99} end
local screen={mode=6,bestiary_entry=vector{entry},scroll_position_bestiary=0}
local requested={}
local function lookup(s)
    requested[s]=true
    if s==source then return target end
    if s=='Acorn fly' then return '橡子蠅' end
end
local rows=env.bindings(screen,lookup)
assert(#rows==3,'Bestiary binds the complete species title and joined description, independently of an unknown later paragraph')
local by={};for _,r in ipairs(rows) do by[r.address]=r end
assert(by[99].source=='Acorn fly, ♀' and by[99].translation=='橡子蠅, ♀','Translate the species while preserving its native gender marker')
assert(by[100].translation==target and by[101].translation=='','The shorter Chinese paragraph fits the first row and suppresses its unused continuation')
assert(by[100].translation..by[101].translation==target and utf8.len(by[100].translation) and utf8.len(by[101].translation))
assert(not by[102] and not by[103],'Preserve blank separators and unknown paragraphs')
assert(requested[source] and not requested[first] and not requested[last],'Query complete paragraphs, never English fragments')
assert(entry.main_text_box.text[0].value==first and entry.p_list_name=='Acorn fly, ♀','All journal sources stay unchanged')
entry.p_list_name='Wiwaxia, ♀'
rows=env.bindings(screen,function(s) if s=='Wiwaxia' then return '威瓦克蟲' elseif s==source then return target end end)
assert(#rows==3 and rows[1].translation=='威瓦克蟲, ♀','A translated species title can be wider than its English name within the native panel')
entry.p_list_name='Wren, '..string.char(12)
env.dfhack.df2utf=function(s) return (s:gsub(string.char(12),'♀')) end
rows=env.bindings(screen,function(s) if s=='Wren' then return '鷦鷯' elseif s==source then return target end end)
assert(#rows==3 and rows[1].source=='Wren, ♀' and rows[1].translation=='鷦鷯, ♀','Short CP437 gender titles must not be rejected by an eight-byte source gate')
entry.p_list_name='Acorn fly, ♀'
rows=env.bindings(screen,function(s) if s==source then return 'Partly English 中文' end end)
assert(#rows==0,'Reject mixed English translations without verified name identities')
rows=env.bindings(screen,function(s) if s==source then return string.rep('字',100) end end)
assert(#rows==0,'If the complete paragraph cannot fit, preserve all its original rows')
entry.main_text_box.text[0].value='[UNKNOWN]'..first
assert(#env.bindings(screen,lookup)==1,'Unsupported markup must not be flattened into ordinary prose')
entry.main_text_box.text[0].value=first
entry.p_list_name='Acorn fly, UNKNOWN'
rows=env.bindings(screen,lookup)
assert(#rows==2,'Unknown title suffixes must retain the original title')
screen.mode=7
assert(#env.bindings(screen,lookup)==0,'Never bind hidden bestiary rows on the artifact page')
screen.mode=6;screen.scroll_position_bestiary=1
assert(#env.bindings(screen,lookup)==0,'Use the bestiary scroll index, not the hidden event index')
local narrow={p_list_name='Unknown',main_text_box={text=vector{
    {value='Complete unknown ',address=500},{value='paragraph.',address=501}}}}
function narrow:_field() return {address=499} end
screen.bestiary_entry=vector{narrow};screen.scroll_position_bestiary=0
rows=env.bindings(screen,function(s) if s=='Complete unknown paragraph.' then return '𠮷的描述必須完整保留。' end end)
assert(#rows==2 and rows[1].translation=='𠮷的描述必須完整' and rows[2].translation=='保留。','Supplementary Unicode wraps at scalar boundaries within the existing rows')
local many={}
entry.p_list_name='Acorn fly, ♀'
for i=1,700 do many[i]=entry end
screen.bestiary_entry=vector(many);screen.scroll_position_bestiary=350
rows=env.bindings(screen,lookup)
assert(#rows>0 and #rows<=256,'A large bestiary stays within the native row publication budget')
local people={main_text_box={text=vector{{value='You have known this person since his birth.',address=700}}}}
screen={mode=2,histfig_entry=vector{people},scroll_position_people=0}
rows=env.bindings(screen,function(s) if s=='You have known this person since his birth.' then return '自他出生起，你就認識他了。' end end)
assert(#rows==1 and rows[1].address==700,'Person-list prose uses its own complete paragraph bindings')
print('PASS journal bestiary complete paragraphs, gender, Unicode, bounds, native fallback and tab cleanup')
