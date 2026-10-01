-- Verify the observed inventory correction without opening a game panel.
local paths=reqscript('df-local-zh-paths')
local native=reqscript('df-local-zh-core/native')
local mod=reqscript('df-local-zh-core/mod')
native.set_lang_tag('zh-Hant')
local ok,err=native.load_translation_rulesets('zh-Hant',
    paths.source()..'/dfi18n-data/rulesets/zh-Hant')
assert(ok,tostring(err))
local cases={
    {'Iron picks [3]','鐵十字鎬 [3]'},
    {'Steel pick','鋼十字鎬'},
    {'Copper great picks [2]','銅大十字鎬 [2]'},
    {'wooden carving knives [5]','木製切肉刀 [5]'},
}
for _,case in ipairs(cases) do
    local actual=mod.sync_translate(case[1])
    assert(actual==case[2],('equipment translation failed: %s => %s'):format(case[1],tostring(actual)))
    print(('df-local-zh-equipment-test PASS %s => %s'):format(case[1],actual))
end
