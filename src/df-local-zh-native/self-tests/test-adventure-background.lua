local env=setmetatable({},{__index=_G})
assert(loadfile(dfhack.findScript('df-local-zh-adventure-background'),'t',env))()
local hearth='You are a newly-minted hearthperson of the great {ADV_LEADER} in {ADV_SITE}, a {ADV_SITE_KIND}.  Destiny is calling!'
local regular='You are a {ADV_JOB} in {ADV_SITE}, a {ADV_SITE_KIND}, and you have never strayed far from home.'
local dict={
    [hearth]='你剛成為偉大的{ADV_LEADER}的侍衛，居於{ADV_SITE}（{ADV_SITE_KIND}）。命運正在呼喚你！',
    [regular]='你是{ADV_SITE}（{ADV_SITE_KIND}）的{ADV_JOB}，從未遠離家鄉。',
    ['human hamlet']='人類村落',miner='礦工',['animal trainer']='馴獸師',
}
local requested={}
local function lookup(s) requested[#requested+1]=s;return dict[s] end
local site='Test𠮷 Home'
local leader='Example Leader'
local source='You are a newly-minted hearthperson of the great '..leader..' in '..site..', a human hamlet.  Destiny is calling!'
local result=env.translate(source,site,{leader},lookup)
assert(result=='你剛成為偉大的Example Leader的侍衛，居於Test𠮷 Home（人類村落）。命運正在呼喚你！','Translate full verified background while preserving identities')
assert(env.translate(source,site,{'Different Leader'},lookup)==nil,'Do not treat unverified English as a name')
assert(env.translate(source,'Different Site',{leader},lookup)==nil)
assert(env.translate(source..' Unknown continuation.',site,{leader},lookup)==nil,'Reject unknown tails atomically')
assert(env.translate('You are a miner in '..site..', a human hamlet, and you have never strayed far from home.',site,{},lookup)=='你是Test𠮷 Home（人類村落）的礦工，從未遠離家鄉。')
assert(env.translate('You are an animal trainer in '..site..', a human hamlet, and you have never strayed far from home.',site,{},lookup)=='你是Test𠮷 Home（人類村落）的馴獸師，從未遠離家鄉。')
assert(env.translate('You are a fake profession in '..site..', a human hamlet, and you have never strayed far from home.',site,{},lookup)==nil)
for _,request in ipairs(requested) do assert(not request:find(site,1,true) and not request:find(leader,1,true),'Do not send or cache save-specific prose') end
dict[hearth]=dict[hearth]..'{ADV_SITE}'
assert(env.translate(source,site,{leader},lookup)==nil,'Reject duplicate placeholders')
dict[hearth]='Partly English {ADV_LEADER}{ADV_SITE}{ADV_SITE_KIND}'
assert(env.translate(source,site,{leader},lookup)==nil,'Reject incomplete translations')
print('PASS verified adventure background identities, profession articles, complete output and unknown fallbacks')
