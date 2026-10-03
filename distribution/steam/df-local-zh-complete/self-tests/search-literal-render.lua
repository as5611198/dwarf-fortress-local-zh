-- Exercise the installed renderer with real DFHack widgets, without touching
-- the player's screen, input, clipboard, or taking screenshots.
local widgets=require('gui.widgets')
local native=reqscript('df-local-zh-core/native')
reqscript('df-local-zh-search').start()
local set_query,draw=native.search_set_query,native.dfhack_addstr_flag
local queries,draws,ordinary={},{},{}
local dc={width=40,height=1,x1=0,y1=0}
for _,method in ipairs{'pen','fill','seek','char','newline'} do
    dc[method]=function(self) return self end
end
dc.string=function(self,value) ordinary[#ordinary+1]=value;return self end
native.search_set_query=function(slot,value)
    local handle=set_query(slot,value)
    queries[#queries+1]={slot=slot,value=value,handle=handle}
    return handle
end
native.dfhack_addstr_flag=function(x,y,fg,bg,bold,handle,flags)
    draws[#draws+1]={handle=handle,flags=flags}
end
local ok,err=xpcall(function()
    local function render(edit,value,width)
        queries,draws,ordinary={},{},{}
        dc.width=width or 40
        edit:setText(value)
        local content=edit.text_area.text_area
        content.wrapped_text:update(value)
        content:onRenderBody(dc)
        assert(edit.text==value,'Rendering must not modify input')
    end
    local function literal(edit,value,width,visible)
        render(edit,value,width)
        assert(#queries==1 and queries[1].slot==120,
            'Search input must use literal rendering, including ASCII')
        assert(queries[1].value==(visible or value),'Visible text must preserve exact input')
        assert(#draws==1 and draws[1].handle==queries[1].handle and
            draws[1].flags==0x80000000,'Literal handle must reach the single-line draw API')
        assert(#ordinary==0,'Search input must bypass translatable string drawing')
    end
    local list=widgets.FilteredList{choices={'iron goblet','granite blocks'}}
    list.edit.focus=false
    for _,value in ipairs{'tie','huagangyan','tie184','',utf8.char(0x597d)..'gjsok184'} do
        literal(list.edit,value)
    end
    literal(list.edit,'huagangyan',6,'gyan')
    local named=widgets.EditField{view_id='search_fixture'}
    named.focus=false
    literal(named,'tie')
    local unrelated=widgets.EditField{view_id='unrelated_fixture'}
    unrelated.focus=false
    render(unrelated,'tie')
    assert(#queries==0 and #ordinary>0,'Unrelated DFHack text keeps its original renderer')
    render(list.edit,string.char(255))
    assert(#queries==0 and #ordinary>0,'Invalid UTF-8 keeps the legacy renderer')
    assert(native.search_matches('iron goblet','tie'),'Iron pinyin matching must survive')
    assert(native.search_matches('granite blocks','huagangyan'),'Granite pinyin matching must survive')
end,debug.traceback)
native.search_set_query,native.dfhack_addstr_flag=set_query,draw
if not ok then error(err) end
print('SEARCH_LITERAL_RENDER passed')
