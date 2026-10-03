--@module=true

local dlg=require('gui.dialogs')
local overlay=require('plugins.overlay')
local widgets=require('gui.widgets')
local core=reqscript('df-local-zh-legends-filter-core')
local runtime=reqscript('df-local-zh-runtime')

local choices,race_to_label,cur_race,previous_search
local function reset()
    choices={}; race_to_label={[-1]='全部'}; cur_race=-1; previous_search=''
end
reset()

local function current_page(screen)
    screen=screen or dfhack.gui.getDFViewscreen(true)
    return screen and screen.page[screen.active_page_index]
end

local function is_list(screen)
    local page=current_page(screen)
    return page and page.mode==df.legends_mode_type.HFS and page.index==-1
end

ZhRaceFilterOverlay=defclass(ZhRaceFilterOverlay,overlay.OverlayWidget)
ZhRaceFilterOverlay.ATTRS{
    desc='繁體中文歷史人物種族篩選',
    default_pos={x=56,y=11}, default_enabled=true, viewscreens='legends', frame={w=54,h=1},
}

function ZhRaceFilterOverlay:init()
    self:addviews{widgets.BannerPanel{subviews={widgets.Label{frame={l=1},text=' '}}}}
end

function ZhRaceFilterOverlay:set_race(_,choice)
    if cur_race==choice.race then return end
    cur_race=choice.race; self.dirty=true
end

function ZhRaceFilterOverlay:choose_race()
    if #choices==0 then
        for race=0,#df.global.world.raws.creatures.all-1 do
            local creature=df.global.world.raws.creatures.all[race]
            local label=core.label(creature.creature_id,race)
            race_to_label[race]=label
            choices[#choices+1]={text=runtime.literal_key(label) or ('RACE_' .. tostring(race)),race=race}
        end
        table.sort(choices,function(a,b)return a.text<b.text end)
        table.insert(choices,1,{text=runtime.literal_key('全部') or 'ALL',race=-1})
    end
    local title=runtime.literal_key('種族篩選') or 'RACE_FILTER'
    local prompt=runtime.literal_key('選擇要顯示的種族') or 'CHOOSE_RACE'
    dlg.showListPrompt(title,prompt,COLOR_WHITE,choices,self:callback('set_race'),nil,30,true)
end

function ZhRaceFilterOverlay:render(dc)
    local screen=dfhack.gui.getDFViewscreen(true)
    if not is_list(screen) then self.dirty=true; return end
    local page=current_page(screen)
    if self.dirty or previous_search~=page.filter_str then
        local figures={}
        for i=0,#screen.histfigs-1 do
            local id=screen.histfigs[i]; local hf=df.historical_figure.find(id)
            figures[i]={race=hf and hf.race or -1,name=hf and dfhack.toSearchNormalized(
                ('%s %s'):format(dfhack.translation.translateName(hf.name,false),
                    dfhack.translation.translateName(hf.name,true))) or ''}
        end
        local filtered=core.filter(figures,cur_race,page.filter_str)
        screen.histfigs_filtered:resize(#filtered)
        for i,id in ipairs(filtered) do screen.histfigs_filtered[i-1]=id end
        previous_search=page.filter_str; self.dirty=false
    end
    ZhRaceFilterOverlay.super.render(self,dc)
    local label=runtime.literal_key('Ctrl+E 種族：')
    local value=runtime.literal_key(race_to_label[cur_race] or '全部')
    if label then runtime.draw_key(57,11,COLOR_WHITE,0,label) end
    if value then runtime.draw_key(80,11,COLOR_YELLOW,0,value) end
end

function ZhRaceFilterOverlay:onInput(keys)
    if not is_list() then return end
    if keys.CUSTOM_CTRL_E then self:choose_race(); return true end
    return ZhRaceFilterOverlay.super.onInput(self,keys)
end

OVERLAY_WIDGETS={racefilter=ZhRaceFilterOverlay}
