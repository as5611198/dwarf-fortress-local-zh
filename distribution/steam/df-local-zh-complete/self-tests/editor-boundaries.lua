local root=assert((...),'scripts directory required')
local e=setmetatable({},{__index=_G})
assert(loadfile(root..'/df-local-zh-search-editor.lua','t',e))()
local source='甲𠮷乙'
for cursor=1,#source+1 do
    local state=e.new(source,cursor)
    local ok=pcall(e.apply,state,{kind='backspace'})
    assert(ok and utf8.len(state.text),'Mid-codepoint initial cursor must not split text or crash')
end
local state=e.new(source)
assert(not e.apply(state,{kind='composition',text=string.char(255)}))
assert(utf8.len(state.composition),'Malformed preedit must not reach rendering')
state=e.new(source)
e.cut_range(state,2,6)
assert(utf8.len(state.text),'Cut endpoints must snap to Unicode boundaries')
print('EDITOR_BOUNDARIES PASS')
