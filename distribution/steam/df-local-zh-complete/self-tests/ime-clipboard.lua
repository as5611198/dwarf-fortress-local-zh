-- Run seed/copy/cut/paste/verify in separate frames on the dedicated probe.
-- Tests actual system clipboard encoding; only fixture text is used.
local stage=...
local n=reqscript('df-local-zh-core/native')
local search=reqscript('df-local-zh-search')
local fixture=utf8.char(0x597d,0x90dd,0x20bb7)..'gjsok184'
if stage=='seed' then
    assert(df_ime_probe,'Open the dedicated IME probe first')
    df_ime_probe.subviews.search.edit:setText(fixture)
    search.sync()
elseif stage=='copy' or stage=='cut' then
    assert(search.active_query()==fixture,'Fixture must be in the focused search editor')
    assert(n.search_push_key(97,0x40))
    assert(n.search_push_key(stage=='copy' and 99 or 120,0x40))
elseif stage=='copied' then
    assert(search.active_query()==fixture,'Copy must preserve the query')
elseif stage=='cut_empty' then
    assert(search.active_query()=='','Successful cut must clear selected text')
elseif stage=='paste' then
    assert(n.search_push_key(97,0x40))
    assert(n.search_push_key(118,0x40))
elseif stage=='verify' then
    assert(search.active_query()==fixture,'In-game copy/paste must preserve Chinese and supplementary Unicode exactly')
    assert(search.active_composition()=='','Clipboard must not leave stale composition')
else
    error('Unknown clipboard acceptance stage')
end
print('IME_CLIPBOARD '..stage..' PASS')
