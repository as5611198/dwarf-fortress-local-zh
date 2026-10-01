local native=reqscript('df-local-zh-core/native')
local context=...;if type(context)~='table' then context={} end
local search=reqscript('df-local-zh-search')
local gui=require('gui')
local json=require('json')
assert(dfhack.isMapLoaded() and df.global.pause_state)
local screen=dfhack.gui.getCurViewscreen()
local stocks=df.global.game.main_interface.stocks
stocks.entering_item_filter=false
if stocks.open then gui.simulateInput(screen,'_MOUSE_R') end
local unit
for _,candidate in ipairs(df.global.world.units.active) do
    if dfhack.units.isCitizen(candidate) then unit=candidate;break end
end
assert(unit,'Need an existing fortress citizen for temporary item fixtures')
local fixtures={}
local function cleanup()
    stocks.item_filter=''
    stocks.entering_item_filter=false
    if stocks.open then gui.simulateInput(screen,'_MOUSE_R') end
    for _,id in ipairs(context.fixture_ids or {}) do
        local item=df.item.find(id)
        if item then dfhack.items.remove(item) end
    end
    context.fixture_ids={}
end
context.cleanup=cleanup;context.fixture_ids={}
for _,definition in ipairs({{'INORGANIC:IRON',df.item_type.GOBLET},{'INORGANIC:GRANITE',df.item_type.BOULDER}}) do
    local material=assert(dfhack.matinfo.find(definition[1]))
    for _,item in ipairs(dfhack.items.createItem(unit,definition[2],-1,material.type,material.index)) do
        assert(dfhack.items.moveToGround(item,unit.pos))
        fixtures[#fixtures+1]=item
        context.fixture_ids[#context.fixture_ids+1]=item.id
        print('TEMP_ITEM '..item.id..' '..dfhack.items.getDescription(item,0,true))
    end
end
if not stocks.open then gui.simulateInput(screen,'D_STOCKS') end
assert(stocks.open,'Native Stocks panel must be open before injecting search input')
stocks.item_filter='';stocks.entering_item_filter=true
gui.simulateInput(screen,'STRING_A032');gui.simulateInput(screen,'STRING_A000')
search.sync()
local queries={'鐵','高腳杯','花崗岩','铁','高脚杯','花岗岩',
    'tie','gaojiaobei','gjb','huagangyan','hgy','gao1jiao3bei1','完全不存在的物品'}
local rows={}
local index=0
local before=native.search_metrics()
local function step()
    if context.cancelled then return end
    index=index+1
    if index>#queries then
        cleanup()
        local f=assert(io.open(context.log_path or dfhack.getDFPath()..'/_localization-work/text-audit/chinese-stocks-live.json','wb'))
        f:write(json.encode(rows));f:close()
        print('CHINESE_STOCKS_LIVE complete queries='..#rows)
        if context.completed then context.completed(rows) end
        return
    end
    native.search_push_key(97,0x00c0)
    assert(native.search_push_text(queries[index]))
    local started=dfhack.getTickCount()
    local function completed()
        if context.cancelled then return end
        if search.active_query()~=queries[index] then
            assert(dfhack.getTickCount()-started<3000,'SDL search commit timeout')
            dfhack.timeout(1,'frames',completed);return
        end
        local types={}
        for _,kind in ipairs(stocks.filtered_type_list) do types[#types+1]=df.item_type[kind] end
        local comparisons,matches=native.search_metrics()
        local row={query=queries[index],types=types,height=stocks.i_height,current_type=stocks.current_type,
            comparisons=comparisons-before,matches=matches,elapsed_ms=dfhack.getTickCount()-started,
            actual_query=search.active_query(),native_filter=stocks.item_filter}
        row.fixture_ids={}
        for _,item in ipairs(stocks.current_type_i_list) do
            for _,fixture in ipairs(fixtures) do
                if item.id==fixture.id then row.fixture_ids[#row.fixture_ids+1]=item.id end
            end
        end
        local expected
        if queries[index]=='完全不存在的物品' then
            expected=nil
        elseif queries[index]=='花崗岩' or queries[index]=='花岗岩' or
                queries[index]=='huagangyan' or queries[index]=='hgy' then
            expected='BOULDER'
        else expected='GOBLET' end
        row.passed=expected==nil and #types==0
        for _,kind in ipairs(types) do if kind==expected then row.passed=true end end
        if index==2 or index==3 then row.passed=row.passed and #row.fixture_ids==1 end
        rows[#rows+1]=row
        print('LIVE_QUERY '..json.encode(row))
        dfhack.timeout(1,'frames',step)
    end
    dfhack.timeout(1,'frames',completed)
end
step()
