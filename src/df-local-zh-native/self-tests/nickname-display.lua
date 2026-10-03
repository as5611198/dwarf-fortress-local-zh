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
print('NICKNAME_DISPLAY PASS: canonical surname, profession, literal nickname, quotes, missing translations, no nickname dispatch')
