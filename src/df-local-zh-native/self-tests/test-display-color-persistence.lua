local json=require('json')
local root=dfhack.getDFPath()
local runtime_path=(...) or dfhack.findScript('df-local-zh-runtime')
local directory='fixture/color-cache/'
local journal=directory..'unit-display-cache.jsonl'
local files={}
local world='fixture/fortress'
local dictionary={}
local drawn={}
local color_ready=true
local loads=0
local world_reads=0
local fail_journal=false

local function open(path,mode)
    if path==journal and mode=='ab' and fail_journal then return nil end
    if mode=='rb' and files[path]==nil then return nil end
    if mode=='wb' then files[path]='' end
    local offset=0
    return {
        seek=function(_,kind,position)
            offset=kind=='end' and #(files[path] or '') or position
            return offset
        end,
        read=function() return (files[path] or ''):sub(offset+1) end,
        write=function(_,...)
            files[path]=(files[path] or '')..table.concat({...})
            return true
        end,
        close=function() return true end,
    }
end

local function restart()
    dictionary={}
    local env=setmetatable({
        dfhack={isWorldLoaded=function() return world~=nil end,
            getSavePath=function() world_reads=world_reads+1;return world end},
        io={open=open},
        reqscript=function(module)
            if module=='df-local-zh-reviewed-text' then return {translation=function() return nil end} end
            if module=='df-local-zh-paths' then
                return {broker_data=function() return directory:sub(1,-2) end}
            end
            if module=='df-local-zh-core/mod' then return {
                sync_translate=function(key) return dictionary[key] end,
                async_translate=function(key)
                    if key:match('^%[C:') and not color_ready then return nil end
                    return dictionary[key]
                end,
            } end
            assert(module=='df-local-zh-core/native',module)
            return {
                load_simple_dict=function(_,path)
                    loads=loads+1
                    for key,value in files[path]:gmatch('\n"([^"]+)","([^"]+)"') do
                        dictionary[key]=value
                    end
                end,
                dfhack_addstr_flag=function(_,_,fg,bg,bold,key)
                    drawn[#drawn+1]={fg=fg,bg=bg,bold=bold,key=key}
                    return true
                end,
            }
        end,
    },{__index=_G})
    assert(loadfile(runtime_path,'t',env))()
    return env
end

local function rows()
    local result={}
    for line in (files[journal] or ''):gmatch('(.-)\n') do
        local ok,row=pcall(json.decode,line)
        if ok and type(row)=='table' then result[#result+1]=row end
    end
    return result
end

local function count(scope,color)
    local n=0
    for _,row in ipairs(rows()) do
        if row.kind=='fragment' and row.world==scope and row.color==color then n=n+1 end
    end
    return n
end

local runtime=restart()
local plain=assert(runtime.literal_key('同一段翻譯'))
color_ready=false
runtime.draw_key(1,2,7,0,plain)
assert(drawn[#drawn].key==plain,'An unready color alias must not reach native rendering')
assert(count(world,7)==0,'An unready color alias must not be saved')
color_ready=true
runtime.draw_key(1,2,7,0,plain)
local white=drawn[#drawn].key
assert(white~=plain and dictionary['[C:7:0:0]'..white]=='[C:7:0:0]同一段翻譯',
    'Visible overlay text must use a verified native color alias')
runtime.draw_key(1,3,14,0,plain)
local yellow=drawn[#drawn].key
assert(yellow~=plain and yellow~=white and
    dictionary['[C:6:0:1]'..yellow]=='[C:6:0:1]同一段翻譯',
    'A second palette must get its own bright color alias')
assert(count(world,7)==1 and count(world,70)==1,'Both observed colors must be journaled')
local saved_loads=loads
world_reads=0
for _=1,20 do runtime.draw_key(1,2,7,0,plain) end
assert(loads==saved_loads and count(world,7)==1,'Repeated frames must reuse the same alias and journal row')
assert(world_reads==20,'Each resolved draw must check the current world only once')
runtime.draw_key(1,2,7,0,'P_____')
assert(drawn[#drawn].key=='P_____','Untracked pending text must pass through unchanged')
dictionary['The outer gate']='外門'
local short=assert(runtime.short_lookup('The outer gate',true))
runtime.draw_key(1,4,11,0,short)
assert(drawn[#drawn].key~=short and
    dictionary['[C:3:0:1]'..drawn[#drawn].key]=='[C:3:0:1]外門',
    'Broker-backed short aliases must use the same persistent color path')
assert(count(world,67)==1,'The short alias color must be journaled')

runtime=restart()
runtime.poll()
local fresh=assert(runtime.literal_key('同一段翻譯'))
saved_loads=loads
runtime.draw_key(1,2,7,0,fresh)
assert(drawn[#drawn].key~=fresh and loads==saved_loads,
    'Restart must reuse the restored color alias without loading another dictionary row')
runtime.draw_key(1,3,14,0,fresh)
assert(drawn[#drawn].key~=fresh and count(world,70)==1,
    'Restart must retain the second color without another journal row')

dictionary={}
assert(runtime.invalidate_native_cache,'A native dictionary reload needs to invalidate cached display aliases')
runtime.invalidate_native_cache()
local refreshed=assert(runtime.literal_key('同一段翻譯'))
runtime.draw_key(1,2,7,0,refreshed)
assert(dictionary['[C:7:0:0]'..drawn[#drawn].key]=='[C:7:0:0]同一段翻譯',
    'Native reload must rebuild the observed color aliases in the same world')

local report_source='A fortress announcement.'
local report_text='要塞公告。'
assert(runtime.publish_native,'Original report palette bindings need durable publication')
local markup='[C:2:0:1]公告[B]第二段[C:7:0:0]'
color_ready=false
assert(not runtime.announcement_key(markup,string.char(70)),
    'Announcement aliases must wait for native palette readiness')
color_ready=true
local announcement_alias=assert(runtime.announcement_key(markup,string.char(70)))
assert(dictionary[announcement_alias]==markup and
    dictionary['[C:6:0:1]'..announcement_alias]=='[C:6:0:1]'..markup,
    'Fresh announcement aliases must preserve every embedded color and break token')
local alias_loads=loads
assert(runtime.announcement_key(markup,string.char(70))==announcement_alias and loads==alias_loads,
    'Repeated announcement frames must reuse the prepared alias')
assert(count(world,70)==2,'A colored markup alias must persist its own full formatting and palette')
assert(not runtime.announcement_key('English',string.char(7)) and
    not runtime.announcement_key('[UNKNOWN]公告',string.char(7)),
    'Untranslated or unsupported markup cannot reach announcement rendering')
assert(runtime.publish_native({{text=report_source,translation=report_text},
    {text='[C:6:0:1]'..report_source,translation='[C:6:0:1]'..report_text},
    {text='[C:4:0:0]'..report_source,translation='[C:4:0:0]'..report_text}}))
local before_native_journal=#rows()
assert(runtime.publish_native({{text='[C:6:0:1]'..report_source,translation='[C:6:0:1]'..report_text}}))
assert(#rows()==before_native_journal,'Repeated native report bindings must not duplicate journal entries')
assert(not runtime.publish_native({{text='An invalid announcement',translation='[C:7:0:1]English'}}),
    'Persisted native bindings must reject mixed English')
assert(not runtime.publish_native({{text='[C:6:0:1]'..report_source,translation='[C:4:0:0]'..report_text}}),
    'Persisted report bindings must reject changed palette tokens')
runtime=restart();runtime.poll()
local restore_loads=loads
local restored_announcement=assert(runtime.announcement_key(markup,string.char(70)))
assert(restored_announcement==announcement_alias and loads==restore_loads and
    dictionary['[C:6:0:1]'..restored_announcement]=='[C:6:0:1]'..markup,
    'Restart must reuse the saved ready announcement alias without republishing its markup')
assert(dictionary[report_source]==report_text and
    dictionary['[C:6:0:1]'..report_source]=='[C:6:0:1]'..report_text and
    dictionary['[C:4:0:0]'..report_source]=='[C:4:0:0]'..report_text,
    'Restart must restore exact announcement sources and both observed palettes')

fail_journal=true
local retry_alias=assert(runtime.colored_key('快取重試',string.char(71)))
local function retry_rows()
    local n=0
    for _,row in ipairs(rows()) do if row.translation=='快取重試' then n=n+1 end end
    return n
end
assert(retry_rows()==0,'A failed journal write must not be considered persisted')
fail_journal=false
assert(runtime.colored_key('快取重試',string.char(71))==retry_alias and retry_rows()==1,
    'A cached color alias must retry a failed journal write on the next use')

local every_color=assert(runtime.literal_key('全部顏色'))
for bold=0,1 do for bg=0,7 do for fg=0,7 do
    runtime.draw_key(1,1,fg+bold*8,bg,every_color)
    local last=drawn[#drawn]
    local tag=('[C:%d:%d:%d]'):format(fg,bg,bold)
    assert(last.fg==fg and last.bg==bg and last.bold==bold and
        dictionary[tag..last.key]==tag..'全部顏色',
        'Every foreground, background and brightness combination needs its exact palette key')
end end end
local palettes={}
for _,row in ipairs(rows()) do
    if row.world==world and row.kind=='fragment' and row.translation=='全部顏色' then palettes[row.color]=true end
end
local palette_count=0;for _ in pairs(palettes) do palette_count=palette_count+1 end
assert(palette_count==128,'All 128 observed palettes must be persisted independently')
runtime=restart();runtime.poll();restore_loads=loads
local all_restored=assert(runtime.literal_key('全部顏色'))
restore_loads=loads
for bold=0,1 do for bg=0,7 do for fg=0,7 do
    runtime.draw_key(1,1,fg+bold*8,bg,all_restored)
    local tag=('[C:%d:%d:%d]'):format(fg,bg,bold)
    assert(dictionary[tag..drawn[#drawn].key]==tag..'全部顏色','Restart must restore every observed palette')
end end end
assert(loads==restore_loads,'Restored palettes must not need another dictionary publication')

world='fixture/other-fortress'
runtime=restart()
runtime.poll()
assert(not dictionary[report_source] and not dictionary['[C:6:0:1]'..report_source],
    'Another world must not restore this world\'s original report bindings')
local other=assert(runtime.literal_key('同一段翻譯'))
runtime.draw_key(1,2,7,0,other)
assert(count(world,7)==1,'A different world must create its own observed color row')

world=nil
runtime.poll()
local title=assert(runtime.literal_key('資料夾：'))
runtime.draw_key(1,2,9,0,title)
assert(count(false,65)==1,'The title screen must save its color in a global scope')
runtime=restart()
local restored_title=assert(runtime.literal_key('資料夾：'))
saved_loads=loads
runtime.draw_key(1,2,9,0,restored_title)
assert(drawn[#drawn].key~=restored_title and loads==saved_loads,
    'A no-world title color must survive process restart')
print('PASS overlay color persistence, native readiness, palette isolation, world scope and title restart')
