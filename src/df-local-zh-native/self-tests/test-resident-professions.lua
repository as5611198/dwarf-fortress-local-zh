local json=require('json')
local writes,reads={},0
local native={native_unit_list_rows_set=function(s) writes[#writes+1]=json.decode(s);return true end,
    native_nickname_rows_set=function() return true end,
    local_lookup=function(s) return ({Miner='礦工',Mason='石匠'})[s] end,
    cache_lookup=function() return nil end}
local function widget(kind,children)
    return {kind=kind,children=children or {},flag={VISIBILITY_ACTIVE=true,VISIBILITY_VISIBLE=true}}
end
local rows=widget('scroll');rows.scroll=0;rows.num_visible=2
local huge=setmetatable({},{__len=function() return 10000 end})
rows.children=huge
local units={}
for i=0,70 do
    units[i]={id=i,custom_profession='',s={native='Native '..i,english='English '..i,profession=i%2==0 and 'Miner' or 'Mason'}}
    local row=widget('container');row.Name=widget('unit_name');row.Name.u=units[i];row.Name.show_profession=true
    huge[i]=row
end
local residents=widget('stack');local tabs=widget('tabs');local creatures=widget('creatures');creatures.current_mode=0
creatures.Tabs=tabs;tabs.Residents=residents;residents[0]=widget('unit_list')
residents[0]['Unit List']=widget('table');residents[0]['Unit List'][1]=rows
local labor=widget('labor');local laborTabs=widget('tabs');local details=widget('details')
local right=widget('stack');local panel=widget('container');local laborList=widget('unit_list')
labor.Tabs=laborTabs;laborTabs['Work Details']=details;details['Right panel']=right
right[0]=panel;panel[3]=laborList;laborList['Unit List']=widget('table');laborList['Unit List'][1]=rows
local focus='dwarfmode/Info/CREATURES'
local env=setmetatable({
    dfhack_flags={module=true},
    reqscript=function(n)
        if n=='df-local-zh-core/native' then return native end
        return {}
    end,
    df={global={game={main_interface={info={creatures=creatures,labor=labor},view_sheets={open=false}}}},
        unit_list_mode_type={CITIZEN=0},
        widget_scroll_rows={is_instance=function(_,w) return w and w.kind=='scroll' end},
        widget_unit_name={is_instance=function(_,w) return w and w.kind=='unit_name' end}},
    dfhack={isMapLoaded=function() return true end,gui={getDFViewscreen=function() return {} end,
        getFocusStrings=function() return {focus} end,
        getWidget=function(w,...)
            for _,k in ipairs{...} do
                if not w then return nil end
                if w.kind=='scroll' then reads=reads+1;w=w.children[k] else w=w[k] end
            end
            return w
        end}},
},{__index=_G})
assert(loadfile(dfhack.findScript('df-local-zh-nickname-display'),'t',env))()
env.snapshot=function(u) return u.s end
local function latest() local m={};for _,r in ipairs(writes[#writes] or {}) do m[r.source]=r.translation end;return m end
env.poll({})
assert(latest()['Native 0, Miner']=='Native 0, 礦工','Visible professions must work without a selected unit sheet')
assert(latest()['English 1, Mason']=='English 1, 石匠')
assert(reads<=3 and not latest()['Native 3, Mason'],'Do not scan the full 10000-row list')
rows.scroll=40;reads=0;env.poll({})
assert(latest()['Native 40, Miner']=='Native 40, 礦工' and not latest()['Native 0, Miner'],'Scrolling replaces old bindings')
assert(reads<=3)
rows.num_visible=0;reads=0;env.poll({});assert(reads==0 and #writes[#writes]==0,'Empty viewports do no work')
rows.num_visible=2
units[40].s.native="`測試𠮷, A1' Surname";units[40].s.english=units[40].s.native
env.poll({})
assert(latest()[units[40].s.native..', Miner']==units[40].s.native..', 礦工','Nickname and surname remain verbatim')
units[40].custom_profession='My custom Miner';env.poll({})
assert(not latest()[units[40].s.native..', Miner'],'Never reinterpret a custom profession')
huge[41].Name.flag.VISIBILITY_VISIBLE=false;env.poll({})
assert(not latest()['Native 41, Mason'],'Hidden rows are ignored')
rows.scroll=0;rows.num_visible=5000;reads=0;env.poll({})
assert(reads<=32 and #writes[#writes]<=64,'Visible work and native bindings have fixed caps')
focus='dwarfmode/Default';env.poll({});assert(#writes[#writes]==0,'Leaving the list clears all aliases')
local n=#writes;env.poll({});assert(#writes==n,'Inactive polling must not write repeatedly')
focus='dwarfmode/Info/CREATURES';residents.flag.VISIBILITY_VISIBLE=false;env.poll({})
assert(#writes==n,'An invisible Residents tab must not create aliases')
residents.flag.VISIBILITY_VISIBLE=true;creatures.current_mode=1;env.poll({});assert(#writes==n)
creatures.current_mode=0;env.poll({});assert(#writes[#writes]>0)

focus='dwarfmode/Info/LABOR/WORK_DETAILS/Default';rows.scroll=0;rows.num_visible=2;reads=0
huge[41].Name.flag.VISIBILITY_VISIBLE=true
env.poll({})
assert(latest()['Native 0, Miner']=='Native 0, 礦工','Work-details names need the same bounded profession adapter')
assert(reads<=3 and not latest()['Native 3, Mason'],'Work details must not scan all residents')
rows.scroll=40;reads=0;env.poll({})
assert(latest()['English 41, Mason']=='English 41, 石匠' and not latest()['Native 0, Miner'])
assert(reads<=3,'Labor scrolling keeps the visible cap')
for _,ancestor in ipairs{labor,laborTabs,details,right,panel,laborList} do
    ancestor.flag.VISIBILITY_VISIBLE=false;reads=0;env.poll({})
    assert(reads==0 and #writes[#writes]==0,'Hidden labor ancestors must clear bindings without scanning')
    ancestor.flag.VISIBILITY_VISIBLE=true;env.poll({})
end
focus='dwarfmode/Info/LABOR/KITCHEN';env.poll({})
assert(#writes[#writes]==0,'Other labor tabs must not retain work-detail aliases')
focus='dwarfmode/Info/LABOR/WORK_DETAILS/Default';env.poll({})
panel[3]=nil;reads=0;env.poll({})
assert(reads==0 and #writes[#writes]==0,'A missing or rebuilt labor list safely clears its bindings')
panel[3]=laborList;env.poll({})
env.snapshot=function() error('fixture rebuilt widget') end
local ok=pcall(env.poll,{})
assert(not ok and #writes[#writes]==0,'A failed scan clears aliases and propagates its error for logging')
print('RESIDENT_PROFESSIONS PASS: residents and labor, bounded visible rows, scroll, literal nicknames, custom jobs, exit/error cleanup')
