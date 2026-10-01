local calls = 0
local blocking_misses = 0
local writes = 0
local now = 100
local active_world = 'fixture/region2'
local dictionary = {['The Fixed Title'] = '固定標題', ['(enemy)'] = '固定標題'}
dictionary['Long Caption'] = string.rep('固定標題', 20)
local written = ''
local files = {}
local drawn = {}
local env = setmetatable({
    dfhack = {
        getDFPath = function() return 'fixture' end,
        isWorldLoaded = function() return true end,
        getSavePath = function() return active_world end,
    },
    os = {time = function() return now end},
    io = {open = function(path, mode)
        if mode == 'rb' then
            if not files[path] then return nil end
            return {read=function() return files[path] end, close=function() end}
        end
        local content = ''
        return {
            write = function(_, ...)
                for _, part in ipairs({...}) do content = content .. part end
                written = content
                files[path] = content
                writes = writes + 1
                return true
            end,
            close = function() return true end,
        }
    end},
    reqscript = function(name)
        if name=='df-local-zh-reviewed-text' then return {translation=function() return nil end} end
        if name == 'df-local-zh-paths' then
            return {
                broker_data = function() return 'fixture/broker/data' end,
                broker_source = function() return 'fixture/broker' end,
                source = function() return 'fixture' end,
                state = function() return 'fixture/broker' end,
            }
        end
        if name == 'df-local-zh-core/mod' then
            return {sync_translate = function(source)
                calls = calls + 1
                if not dictionary[source] then blocking_misses = blocking_misses + 1 end
                return dictionary[source]
            end, async_translate = function(source)
                calls = calls + 1
                return dictionary[source]
            end}
        end
        if name == 'df-local-zh-core/native' then
            return {dfhack_addstr_flag=function(x,y,fg,bg,bold,key,flag)
                drawn={fg=fg,bold=bold}
            end, load_simple_dict = function()
                assert(written:match('\n"([^"]+)"'))
                for key, translation in written:gmatch('\n"([^"]+)","([^"]+)"') do
                    dictionary[key] = translation
                end
            end}
        end
        error('Unexpected module: ' .. name)
    end,
}, {__index = _G})
local runtime_path=(...) or dfhack.findScript('df-local-zh-runtime')
assert(loadfile(runtime_path, 't', env))()

assert(not env.request('An unresolved narrative'))
local first_calls, first_writes = calls, writes
for _ = 1, 100 do assert(not env.request('An unresolved narrative')) end
assert(calls == first_calls, 'Pending requests must not synchronously translate every poll')
assert(writes == first_writes, 'Pending requests must not append duplicate requests')
dictionary['An unresolved narrative']='新到的本機翻譯'
now=101
assert(env.translation('An unresolved narrative')=='新到的本機翻譯',
    'A newly completed native translation must be usable before the 20-second provider retry')
assert(writes==first_writes,'Native readiness checks must not duplicate provider requests')
now = 121
assert(env.request('An unresolved narrative')=='An unresolved narrative')

local key = assert(env.short_lookup('The Fixed Title'))
local ready_calls = calls
for _ = 1, 100 do assert(env.short_lookup('The Fixed Title') == key) end
assert(calls == ready_calls, 'Resolved short keys must not invoke native translation each poll')
assert(env.translation('The Fixed Title')=='固定標題')
local translated_calls=calls
for _=1,100 do assert(env.translation('The Fixed Title')=='固定標題') end
assert(calls==translated_calls,'Cached display text must not query the native dictionary every poll')

assert(not env.short_lookup('(enemy)'), 'Fixed-width mode must reject overflow')
local expanded = assert(env.short_lookup('(enemy)', true),
    'An expandable Legends field must allow a wider Chinese translation')
assert(#expanded >= 8, 'Expanded keys must reserve the translated width')
assert(not env.short_lookup('(enemy)'), 'Expanded mode must not change fixed-width mode')
local centered = assert(env.short_lookup('The Fixed Title', true, 'CENTER'))
assert(dictionary[centered:sub(1, 7) .. '...'] == '固定標...',
    'A game-truncated tab key must still resolve to a fitted Chinese caption')
local full_caption = assert(env.short_lookup('Long Caption', true))
local fitted_caption = assert(env.short_lookup('Long Caption', true, nil, 30))
assert(#fitted_caption <= 30 and dictionary[fitted_caption]:sub(-3)=='...',
    'A long list caption must fit beside its date column and remain an abbreviation')
assert(env.short_lookup('Long Caption', true)==full_caption,
    'Fitting a list row must not shorten the full detail caption')

active_world = 'fixture/region1'
local other_key = assert(env.short_lookup('The Fixed Title'))
assert(other_key ~= key, 'World switches must discard the previous short-key cache')
dictionary = {['The Fixed Title'] = '固定標題'}
assert(loadfile(runtime_path, 't', env))()
local restarted_key = assert(env.short_lookup('The Fixed Title'))
assert(restarted_key ~= key and restarted_key ~= other_key,
    'A restarted native dictionary must not reuse aliases retained by the render cache')
assert(blocking_misses == 0,
    'Unknown sources and reserved aliases must never use a blocking native lookup')
dictionary['Misleading figure caption'] = '瓦達內，「瓦丹」，雌性大鵬'
assert(env.request('Misleading figure caption') == 'Misleading figure caption')
assert(not env.request('Misleading figure caption', 20),
    'A Chinese native result must not bypass authoritative figure identity')
assert(require('json').decode(written).figureId == 20,
    'Caption requests must retain the actual figure ID')
env.draw_key(0,0,9,0,'KEY')
assert(drawn.fg==1 and drawn.bold==1, 'Bright link colors must not be brightened twice')
env.draw_key(0,0,7,0,'KEY')
assert(drawn.fg==7 and drawn.bold==0, 'Ordinary text must retain its normal palette entry')
local colored=assert(env.colored_key('彩色段落',string.char(71)))
assert(dictionary['[C:7:0:1]'..colored]=='[C:7:0:1]彩色段落',
    'Colored aliases must translate in the actual addcoloredst markup path')
assert(env.colored_key('彩色段落',string.char(71))==colored,'Colored keys must remain stable')
local batch_writes=writes
assert(env.publish_batch({{text='Rice plants, rice leaves',translation='稻米植株，稻米葉'},
    {text='Macadamia tree Sapling',translation='奶油果樹樹苗'}}))
assert(writes==batch_writes+1,'Native source preparation must publish one CSV batch rather than one file per source')
assert(env.native_ready('Rice plants, rice leaves','稻米植株，稻米葉'))
assert(not env.native_ready('Rice plants, rice leaves','其他譯文'),'Readiness must check the expected translation')
local another=assert(env.colored_key('彩色段落',string.char(4)))
assert(another~=colored and dictionary['[C:4:0:0]'..another]=='[C:4:0:0]彩色段落',
    'A new palette must not reuse a stale markup alias')
local native_ready=false
local native_mod=env.reqscript('df-local-zh-core/mod')
local old_reqscript=env.reqscript
env.reqscript=function(name)
    if name=='df-local-zh-core/mod' then
        return {sync_translate=native_mod.sync_translate,async_translate=function(source)
            if (source:match('^%[C:') or source:match('^L[%w]+_*$')) and not native_ready then return nil end
            return dictionary[source]
        end}
    end
    return old_reqscript(name)
end
assert(loadfile(runtime_path,'t',env))()
assert(not env.colored_key('等待彩色渲染',string.char(71)),
    'A synchronous dictionary hit must not expose an alias before asynchronous markup readiness')
local staged_writes=writes
assert(not env.colored_key('等待彩色渲染',string.char(71)))
assert(writes==staged_writes,'Polling a staged color alias must not regenerate dictionary files')
native_ready=true
assert(env.colored_key('等待彩色渲染',string.char(71)),
    'The staged alias must become available when its full color markup resolves')
native_ready=false
assert(not env.short_lookup('The Fixed Title',true),
    'List captions must not expose short aliases before native rendering readiness')
staged_writes=writes
for _=1,20 do assert(not env.short_lookup('The Fixed Title',true)) end
assert(writes==staged_writes,'Waiting list aliases must be reused without repeated CSV loads')
native_ready=true
assert(env.short_lookup('The Fixed Title',true))
local ready_calls=calls
assert(env.short_lookup('The Fixed Title',true))
assert(calls==ready_calls,'Renderable list aliases must stop native readiness polling')
print('Runtime poll cost verified: pending and ready lookups avoid repeated native calls')
