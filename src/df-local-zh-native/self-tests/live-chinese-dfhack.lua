local gui=require('gui')
local context=...;if type(context)~='table' then context={} end
local widgets=require('gui.widgets')
local native=reqscript('df-local-zh-core/native')
local search=reqscript('df-local-zh-search')
local json=require('json')
local submitted=select(3,native.core_cache_metrics())
local choices={{text='iron goblet',id=101},{text='granite blocks',id=102},{text='wooden bucket',id=103}}
local TestScreen=defclass(TestScreen,gui.ZScreen)
TestScreen.ATTRS{focus_path='local-zh-search-test'}
function TestScreen:init()
    self:addviews{widgets.Window{frame={w=48,h=12},subviews={
        widgets.FilteredList{view_id='search',frame={l=1,t=0,r=1,b=0},choices=choices},
    }}}
end
local screen=TestScreen{}:show()
context.cleanup=function() if screen:isActive() then screen:dismiss() end end
local list=screen.subviews.search
list.edit:setFocus(true)
local rows={}
local cases={{'鐵',101},{'高腳杯',101},{'花崗岩',102},{'IRON',101},
    {'花崗岩',102},{'花崗',102},{'崗',102},{'鐵 高腳杯',101},
    {'铁',101},{'高脚杯',101},{'花岗岩',102},{'tie',101},{'gaojiaobei',101},{'gjb',101},
    {'huagangyan',102},{'hgy',102},{'gāojiǎobēi',101},{'不存在的物品',nil}}
local index=0
local function step()
    if context.cancelled then return end
    index=index+1
    if index>#cases then
        screen:dismiss()
        local after=select(3,native.core_cache_metrics())
        local matched_before=select(3,native.core_cache_metrics())
        local started=os.clock()
        for _=1,1000 do
            assert(native.search_matches('iron goblet','鐵 高腳杯'))
            assert(native.search_matches('granite blocks','花崗岩'))
            assert(not native.search_matches('wooden bucket','鐵'))
        end
        local result={cases=rows,render_submissions=after-submitted,
            matcher_calls=3000,matcher_ms=(os.clock()-started)*1000,
            matcher_submissions=select(3,native.core_cache_metrics())-matched_before}
        assert(result.matcher_submissions==0,'Synchronous matching must not submit translation work')
        local f=assert(io.open(context.log_path or dfhack.getDFPath()..'/_localization-work/text-audit/chinese-dfhack-live.json','wb'))
        f:write(json.encode(result));f:close()
        print('DFHACK_CHINESE_SEARCH completed')
        if context.completed then context.completed(result) end
        return
    end
    local started=dfhack.getTickCount()
    local function completed()
        if context.cancelled then return end
        if list.edit.text~=cases[index][1] then
            assert(dfhack.getTickCount()-started<3000,'DFHack text commit timeout')
            dfhack.timeout(1,'frames',completed);return
        end
        local visible=list:getVisibleChoices()
        local row={query=list.edit.text,count=#visible,id=visible[1] and visible[1].id,
            passed=cases[index][2] and #visible==1 and visible[1].id==cases[index][2]
                or not cases[index][2] and #visible==0}
        rows[#rows+1]=row
        if not context.completed then
            local f=assert(io.open(dfhack.getDFPath()..'/_localization-work/text-audit/chinese-dfhack-progress.json','wb'))
            f:write(json.encode(rows));f:close()
        end
        assert(row.passed,'DFHack native choice identity changed: '..json.encode(row))
        dfhack.timeout(1,'frames',step)
    end
    if index==5 then
        native.search_push_key(97,0x00c0);assert(native.search_push_composition('hua'))
        local function composition_ready()
            if context.cancelled then return end
            if search.active_composition()~='hua' then
                assert(dfhack.getTickCount()-started<3000,'IME composition timeout')
                dfhack.timeout(1,'frames',composition_ready);return
            end
            assert(list.edit.text=='IRON','IME preedit must not change the committed filter')
            assert(native.search_push_text(cases[index][1]))
            dfhack.timeout(1,'frames',completed)
        end
        dfhack.timeout(1,'frames',composition_ready)
    else
        if index==6 then native.search_push_key(8,0)
        elseif index==7 then native.search_push_key(1073741898,0);native.search_push_key(127,0)
        else native.search_push_key(97,0x00c0);assert(native.search_push_text(cases[index][1])) end
        dfhack.timeout(1,'frames',completed)
    end
end
dfhack.timeout(1,'frames',step)
