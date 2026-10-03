-- Run this fixture on the existing probe, after each actual Windows key step.
-- No synthetic SDL events and no private text are logged.
local stage=...
local n=reqscript('df-local-zh-core/native')
local search=reqscript('df-local-zh-search')
local json=require('json')
local status=json.decode(n.search_ime_status())
local candidates=json.decode(n.search_ime_candidates())
local query=search.active_query()
local composition=search.active_composition()
assert(query~=nil and composition~=nil,'Probe must retain search focus')
assert(status.tsf_registered and status.sdl_text_input_active,'IME bridge must be active')
if stage=='start' then
    assert(query=='' and composition=='','Start with an empty fixture')
    _G.df_ime_acceptance={begin=status.candidate_begin,checks={}}
elseif stage=='composition' then
    assert(query=='' and composition~='','Preedit must not change query')
elseif stage=='candidate' then
    assert(query=='' and composition~='','Opening candidates must preserve preedit')
    assert(candidates.active and #candidates.items>1,'Live Windows candidate page must remain available')
    _G.df_ime_acceptance.selection=candidates.selected
    _G.df_ime_acceptance.items=#candidates.items
elseif stage=='selection' then
    assert(candidates.active,'Candidate page must survive navigation')
    assert(candidates.selected~=_G.df_ime_acceptance.selection,'Windows selection must move')
    _G.df_ime_acceptance.selected=candidates.items[candidates.selected-candidates.first+1]
    assert(_G.df_ime_acceptance.selected,'Selected OS candidate must be on the current page')
elseif stage=='chosen' then
    assert((query=='' and composition~='') or (query==_G.df_ime_acceptance.selected and composition==''),
        'Enter must retain preedit or commit the selected candidate')
elseif stage=='commit' then
    assert(query==_G.df_ime_acceptance.selected,'Final commit must equal the selected Windows candidate')
    assert(composition=='' and not candidates.active,'Commit must close preedit and candidate page')
elseif stage=='cancel' then
    assert(query==_G.df_ime_acceptance.selected,'Cancellation must preserve committed query')
    assert(composition=='' and not candidates.active,'Cancellation must clear preedit and candidates')
else
    error('Unknown acceptance stage')
end
_G.df_ime_acceptance.checks[stage]=true
print('OS_IME stage='..stage..' PASS query_bytes='..#query..' composition_bytes='..#composition..' candidate_items='..#candidates.items..' selected='..candidates.selected)
