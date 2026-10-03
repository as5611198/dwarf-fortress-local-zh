-- Observe actual drawing calls without a screenshot or recording input text.
local gui=require('gui')
local widgets=require('gui.widgets')
local native=reqscript('df-local-zh-core/native')
assert(require('json').decode(native.search_ime_candidates()).active,'Open real Windows candidates first')
local rows={}
local sr,wr,qs,draw=gui.Screen.onRender,widgets.Window.onRenderFrame,native.search_set_query,native.dfhack_addstr_flag
local candidate_handle
gui.Screen.onRender=function(self,...)
    rows[#rows+1]='screen begin'
    sr(self,...)
    rows[#rows+1]='screen end'
end
widgets.Window.onRenderFrame=function(self,...)
    rows[#rows+1]='window background'
    return wr(self,...)
end
native.search_set_query=function(slot,...)
    local handle=qs(slot,...)
    if slot==122 then candidate_handle=handle end
    return handle
end
native.dfhack_addstr_flag=function(x,y,fg,bg,bold,handle,...)
    if candidate_handle and handle==candidate_handle then rows[#rows+1]='candidate text' end
    return draw(x,y,fg,bg,bold,handle,...)
end
_G.df_ime_render_result='running'
dfhack.timeout(3,'frames',function()
    gui.Screen.onRender=sr
    widgets.Window.onRenderFrame=wr
    native.search_set_query=qs
    native.dfhack_addstr_flag=draw
    local last_window,last_candidate=0,0
    for index,value in ipairs(rows) do
        if value=='window background' then last_window=index end
        if value=='candidate text' then last_candidate=index end
    end
    _G.df_ime_render_result={passed=last_window>0 and last_candidate>last_window,order=table.concat(rows,' / ')}
end)
