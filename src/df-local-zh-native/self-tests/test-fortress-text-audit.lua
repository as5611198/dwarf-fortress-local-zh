local audit = reqscript('df-local-zh-audit')
assert(audit.classify('123 !') == 'nonlinguistic')
assert(audit.classify('English') == 'latin_residual')
assert(audit.classify(utf8.char(0x4E2D, 0x6587)) == 'cjk_only')
assert(audit.classify(utf8.char(0x4E2D) .. ' HP') == 'latin_residual')
assert(audit.classify('L123abc___') == 'runtime_alias_unverified')
assert(audit.classify('P_____') == 'pending_translation')
assert(audit.classify('Laborer') == 'latin_residual', 'Ordinary words must not be hidden as runtime aliases')
assert(audit.classify('Lithium') == 'latin_residual')
assert(audit.classify('L000008') == 'runtime_alias_unverified')
assert(audit.classify('Love') == 'latin_residual', 'Legacy aliases require an underscore suffix')
assert(audit.classify('L0009Ss_____ L0009Su_____') == 'runtime_alias_unverified',
    'Joined display aliases are not untranslated game prose')
assert(audit.classify('[C:7:0:1]L0009St_____ [C:7:0:1]L0009Su_____') == 'runtime_alias_unverified')
assert(audit.classify('He sees L000123.') == 'latin_residual',
    'An alias must not hide real untranslated words in the same line')
assert(audit.classify('[C:7:0:1]'..utf8.char(0x4E2D,0x6587)) == 'cjk_only',
    'Color markup is metadata, not residual English')
assert(audit.classify('[C:7:0:1]P_____') == 'pending_translation')
assert(audit.classify(utf8.char(0x7FFB,0x8B6F,0x4E2D)) == 'pending_translation',
    'A Chinese pending label is not a completed translation')
local stats = audit.summarize({
    {classification='latin_residual', text='English'},
    {classification='cjk_only', text=utf8.char(0x4E2D)},
    {classification='pending_translation', text='P_____'},
    {classification='runtime_alias_unverified', text='L123abc___'},
    {classification='internal_identifier', text='Meals'},
    {classification='nonlinguistic', text='123'},
})
assert(stats.assessable == 3 and stats.cjk_only == 1)
assert(math.abs(stats.memory_cjk_only_pct - 100/3) < 0.001)
assert(stats.latin_residual == 1 and stats.unverified_aliases == 1)
assert(audit.summarize({}).memory_cjk_only_pct == nil)
print('PASS fortress text audit classification, denominator, aliases, empty samples')

-- A fixture verifies pointer-backed thought prose and enum metadata without
-- writing to live reports, units, screens, or saves.
local real_df, real_dfhack = audit.df, audit.dfhack
local function typed(name, values)
    return setmetatable(values or {},{__index={_type=name}})
end
local report=typed('report',{id=42,text='Combat report',flags={announcement=false}})
local emotion=typed('personality_moodst',{type=1,thought=2,subthought=3,year=250,year_tick=7})
local sheets=typed('view_sheets_interfacest',{
    raw_thought_str=typed('vector<string*>',{
        typed('string',{value='He felt satisfied at work.'})}),
    raw_current_thought=utf8.char(0x4E2D,0x6587),
    unit_knowledge_type=setmetatable({[0]=14},{__len=function() return 1 end}),
    unit_knowledge_id=setmetatable({[0]=7},{__len=function() return 1 end})})
audit.df={global={game={main_interface=typed('main_interface',{view_sheets=sheets})},
    world={status={reports={report}},units={active={{id=11,
        status={current_soul={personality={emotions={emotion}}}}}}}}},
    emotion_type={[1]='Satisfaction'},unit_thought_type={[2]='Work'},
    view_sheet_unit_knowledge_type={[14]='POETIC_FORM'},
    poetic_form={find=function(id) assert(id==7); return typed('poetic_form',{id=7,name='The Fuchsia Silkinesses'}) end}}
audit.dfhack={
    getTickCount=function() return 100 end,
    gui={getCurViewscreen=function() return typed('viewscreen_dwarfmodest',{
            arena_choice=typed('vector<string*>',{typed('string',{value='region2-test-folder'})})}) end,
        getFocusStrings=function() return {'dwarfmode'} end},
    isWorldLoaded=function() return true end,isMapLoaded=function() return true end,
    world={isFortressMode=function() return true end},
    units={isCitizen=function() return true end},
    getSavePath=function() return 'fixture-world' end,
    getDFVersion=function() return 'fixture' end,getDFHackVersion=function() return 'fixture' end,
    df2utf=function(text) return text end,
    translation={translateName=function(name) return name end},
}
local ok, err=pcall(function()
    local result=audit.scan()
    assert(result.summary.fortress_loaded and result.summary.thought_objects==1)
    assert(result.summary.metrics.latin_residual==3 and result.summary.metrics.cjk_only==1)
    assert(result.summary.scan_issues==0)
    assert(result.summary.by_category.thought_prose.assessable==2)
    assert(result.summary.report_objects==1 and result.summary.citizen_objects==1)
    assert(result.objects[1].thought_type=='Work' and not result.objects[1].prose_available)
    local found={}
    for _,row in ipairs(result.strings) do found[row.field_id]=row end
    assert(found['world.status.reports[1].text'].object_id==42)
    assert(found['world.poetic_forms[id=7].name'].object_id==7 and
        found['world.poetic_forms[id=7].name'].category=='knowledge_title',
        'Knowledge titles must be logged with their actual work type and ID')
    assert(found['game.main_interface.view_sheets.raw_thought_str[1].value'].text==
        'He felt satisfied at work.')
    assert(found['viewscreen.arena_choice[1].value'].classification=='internal_identifier',
        'Save folder identifiers must not be counted as untranslated prose')
end)
audit.df, audit.dfhack=real_df, real_dfhack
assert(ok,err)
print('PASS fortress text audit report IDs, pointer strings, thought enums, UTF-8')
