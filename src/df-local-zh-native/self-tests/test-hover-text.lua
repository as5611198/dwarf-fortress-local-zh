local source='Change to standard dig mode.'
local translated='切換至一般挖掘模式。'
local rows={[0]={value='Change to standard dig '},[1]={value='mode.'}}
local box={text=setmetatable(rows,{__len=function() return 2 end})}
local main={hover_instructions_on=true,current_hover=1,hover_instruction={[1]=box}}
local now,world=0,'fixture'
local dictionary,keys={},{}
local ready=false
local publications=0
local env=setmetatable({
    require=function(name)
        if name=='json' then return {decode=function() return {version=1,translations={[source]=translated}} end} end
        if name=='repeat-util' then return {cancel=function() end} end
        return require(name)
    end,
    reqscript=function() return {broker_source=function() return 'fixture' end} end,
    io={open=function() return {read=function() return '{}' end,close=function() end} end},
    dfhack={isWorldLoaded=function() return world~=nil end,isMapLoaded=function() return true end,
        getSavePath=function() return world end,getTickCount=function() return now end,df2utf=function(s) return s end},
},{__index=_G})
assert(loadfile(dfhack.getDFPath()..'/hack/scripts/df-local-zh-hover-text.lua','t',env))()
local runtime={
    literal_key=function(text)
        if not keys[text] then
            keys[text]='L'..string.format('%06d',#dictionary+1)..string.rep('_',math.max(0,utf8.len(text)*2-7))
            dictionary[#dictionary+1]={text=text,key=keys[text]}
        end
        return keys[text]
    end,
    native_ready=function() return ready end,
    publish_native=function(rows)
        assert(rows[1].text==source and rows[1].translation==translated)
        publications=publications+1;return true
    end,
}
env.poll(runtime,main,'dwarfmode/Default')
assert(rows[0].value=='Change to standard dig ','Unready native aliases must leave original rows intact')
ready=true;now=250;env.poll(runtime,main,'dwarfmode/Default')
assert(rows[0].value==keys[translated] and rows[1].value=='','Whole tooltip prose must span existing rows')
assert(publications==1,'The complete tooltip source must be durably journaled')
now=500;env.poll(runtime,main,'dwarfmode/Default')
assert(publications==1,'Ready frames must reuse their display aliases')
main.hover_instructions_on=false;env.poll(runtime,main,'dwarfmode/Default')
assert(rows[0].value=='Change to standard dig ' and rows[1].value=='mode.','Leaving a tooltip must restore source rows')
main.hover_instructions_on=true;now=750;env.poll(runtime,main,'dwarfmode/Default')
rows[0].value='A game-owned replacement';main.hover_instructions_on=false
env.poll(runtime,main,'dwarfmode/Default')
assert(rows[0].value=='A game-owned replacement','Restoration must preserve a new value written by the game')
assert(rows[1].value=='mode.','Remaining owned aliases must still restore')
main.hover_instructions_on=true;rows[0].value='Change to standard dig ';now=1000
env.poll(runtime,main,'dwarfmode/Default');world=nil
env.poll(runtime,main,'dwarfmode/Default')
assert(rows[0].value=='Change to standard dig ','World changes must restore owned rows')
print('PASS hover paragraph reconstruction, native readiness, durable source, bounds and safe restoration')
