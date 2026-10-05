local source=...
local env=setmetatable({dfhack_flags={module=true}},{__index=_G})
local fn=loadfile(source..'/df-local-zh-nickname-display.lua','t',env)
assert(fn,'Chinese nickname header adapter is missing')
fn()
local s={nickname='測試𠮷 A1',native="`測試𠮷 A1' Amemdakost",english="`測試𠮷 A1' Curlfloor",
    base='Feb Amemdakost',native_surname='Amemdakost',english_surname='Curlfloor',profession='Mason'}
local translations={['Feb Amemdakost']='費布 阿門達科斯特',Mason='石匠'}
local queries={}
local function lookup(text) queries[#queries+1]=text;return translations[text] end
local function mapping(rows) local result={};for _,row in ipairs(rows) do result[row.source]=row.translation end;return result end
local rows=mapping(env.prepare(s,lookup,'費布'))
assert(rows[s.native]=="`測試𠮷 A1' 阿門達科斯特",'Keep nickname verbatim and use the established surname')
assert(rows[s.native..', Mason']=="`測試𠮷 A1' 阿門達科斯特, 石匠",'Translate profession after the nickname')
assert(rows['"'..s.english..'"']=='"`測試𠮷 A1\' 阿門達科斯特"','Both displayed surname forms must agree')
for _,query in ipairs(queries) do assert(not query:find(s.nickname,1,true),'Never send player nickname to translation') end
assert(#env.prepare(s,lookup,'錯誤名字')==0,'Do not guess a surname from an unmatched first-name prefix')
translations.Amemdakost='阿門達科斯特'
assert(#env.prepare(s,lookup,nil)>0,'Missing first-name glossary may translate the native surname separately')
translations.Mason=nil
rows=mapping(env.prepare(s,lookup,'費布'))
assert(rows[s.native] and not rows[s.native..', Mason'],'An unknown profession must not publish a partial header')
s.native="`different' Amemdakost"
assert(#env.prepare(s,lookup,'費布')==0,'Reject mismatched nickname boundaries')
s.native="`測試𠮷 A1'";s.english=s.native;s.native_surname='';s.english_surname='';s.profession='Mason'
translations.Mason='石匠'
rows=mapping(env.prepare(s,lookup,'費布'))
assert(rows[s.native..', Mason']=="`測試𠮷 A1', 石匠",'A nickname without a surname still needs its profession translated')
local ordinary={nickname='',native='Feb Amemdakost',english='Feb Curlfloor',base='Feb Amemdakost',profession='Mason'}
rows=mapping(env.prepare(ordinary,lookup,nil))
assert(rows[ordinary.native..', Mason']=='費布 阿門達科斯特, 石匠')
translations[ordinary.base]=nil
rows=mapping(env.prepare(ordinary,lookup,nil))
assert(rows[ordinary.native..', Mason']=='Feb Amemdakost, 石匠','Unknown canonical names must not block known professions')
assert(rows[ordinary.english..', Mason']=='Feb Curlfloor, 石匠','Keep each verified literal spelling')
translations.Mason=nil
assert(#env.prepare(ordinary,lookup,nil)==0,'Unknown names and professions must not create bindings')
local list_source={nickname='',native='Other Surname',english='Other Floor',profession='expedition leader'}
translations['Expedition leader']='遠征隊領隊'
rows=mapping(env.prepare_list(list_source,lookup))
assert(rows['Other Surname, expedition leader']=='Other Surname, 遠征隊領隊','Native candidate roles can use canonical title-case terms')
assert(rows['Other Floor, expedition leader']=='Other Floor, 遠征隊領隊','Preserve both literal candidate names')
list_source.native="`鐵𠮷 A1' Surname";list_source.nickname='鐵𠮷 A1'
rows=mapping(env.prepare_list(list_source,lookup))
assert(rows[list_source.native..', expedition leader']==list_source.native..', 遠征隊領隊','Candidate nicknames remain literal')
list_source.profession='Unknown role'
assert(#env.prepare_list(list_source,lookup)==0,'Unknown candidate roles fall back atomically')
print('NICKNAME_DISPLAY PASS: canonical surname, profession, literal names, quotes, missing translations, no nickname dispatch')
