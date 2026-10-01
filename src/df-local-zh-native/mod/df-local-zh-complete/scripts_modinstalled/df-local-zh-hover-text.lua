--@module=true
local json=require('json')
local paths=reqscript('df-local-zh-paths')
local dictionary,owned,active_world,active_language
local next_poll=0

local function restore()
    if not owned then return end
    pcall(function()
        for index,key in ipairs(owned.keys) do
            local row=owned.box.text[index-1]
            if row and row.value==key then row.value=owned.original[index] end
        end
    end)
    owned=nil
end

local function valid_owned(box)
    if not owned or owned.box~=box or #box.text~=#owned.keys then return false end
    for index,key in ipairs(owned.keys) do
        if box.text[index-1].value~=key then return false end
    end
    return true
end

function poll(runtime,main,focus)
    local world=dfhack.isWorldLoaded() and dfhack.getSavePath() or nil
    local language=runtime.language and runtime.language() or 'zh-Hant'
    if world~=active_world or language~=active_language then restore();active_world=world;active_language=language end
    local hovered=world and dfhack.isMapLoaded() and focus:find('dwarfmode/',1,true) and
        main.hover_instructions_on and main.current_hover>=0
    local box=hovered and main.hover_instruction[main.current_hover] or nil
    if not box or (owned and not valid_owned(box)) then restore() end
    if not box or owned then return end
    local now=dfhack.getTickCount()
    if now<next_poll then return end
    next_poll=now+250
    if not dictionary then
        local file=io.open(paths.broker_source()..'/data/fortress-hover.json','rb')
        if not file then return end
        local data=json.decode(file:read('*a'));file:close()
        assert(data.version==1 and type(data.translations)=='table','Invalid hover dictionary')
        dictionary=data.translations
    end
    if #box.text==0 or #box.text>20 then return end
    local original,width={},0
    for i=0,#box.text-1 do
        local value=box.text[i].value
        if type(value)~='string' then return end
        original[#original+1]=value;width=math.max(width,#value)
    end
    local source=dfhack.df2utf(table.concat(original))
    local translated=dictionary[source]
    if not translated or translated:match('[A-Za-z{}%[%]]') then return end
    local glyphs=utf8.len(translated)
    local capacity=math.floor(width/2)
    if not glyphs or capacity<4 or glyphs>capacity*#original then return end
    local keys={}
    for index=1,#original do
        local first=(index-1)*capacity+1
        if first>glyphs then keys[index]=''
        else
            local begin=utf8.offset(translated,first)
            local ending=utf8.offset(translated,math.min(first+capacity,glyphs+1)) or #translated+1
            local fragment=translated:sub(begin,ending-1)
            -- Curses rows have no palette field; native drawing retains the caller's pen.
            local key=runtime.literal_key(fragment)
            if not key or #key>width or not runtime.native_ready(key,fragment) then return end
            keys[index]=key
        end
    end
    if not runtime.publish_native({{text=source,translation=translated}}) then return end
    for index,key in ipairs(keys) do box.text[index-1].value=key end
    owned={box=box,original=original,keys=keys,source=source,translation=translated}
end

function start(runtime)
    require('repeat-util').scheduleUnlessAlreadyScheduled('df-local-zh-hover-text',20,'frames',function()
        local main=df.global.game.main_interface
        local focus=table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()),'|')
        local ok,err=pcall(poll,runtime,main,focus)
        if not ok then restore();dfhack.printerr('df-local-zh-hover-text: '..tostring(err)) end
    end)
end

function stop()
    require('repeat-util').cancel('df-local-zh-hover-text')
    restore()
end
