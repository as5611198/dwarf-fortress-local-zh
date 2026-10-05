local root,selection=...
assert(root,'scripts directory required')
local json=require('json')
local world='fixture/world'
local response_path='fixture/runtime-responses.jsonl'
local failure_path='fixture/runtime-failures.jsonl'
local budget=262144
local function row(source,key)
    return {world=world,text=source,translation='已完成。',key='DFLIVE_'..string.rep(key or 'a',64)}
end
local function encoded(value) return json.encode(value,{pretty=false})..'\n' end
local function fixture()
    local state={files={},dictionary={},errors={},closes=0,reads=0,generation='fixture',world=world}
    local env=setmetatable({
        dfhack={isWorldLoaded=function() return true end,getSavePath=function() return state.world end,
            printerr=function(err) state.errors[#state.errors+1]=err end},
        reqscript=function(name)
            if name=='df-local-zh-status' then return {broker=function() return {runtime={retryGeneration=state.generation}} end} end
            if name=='df-local-zh-paths' then return {broker_data=function() return 'fixture' end} end
            if name=='df-local-zh-offline-narrative' then return {valid=function() return true end,translate=function() end} end
            if name=='df-local-zh-core/mod' then return {sync_translate=function(key) return state.dictionary[key] end,
                async_translate=function(key) return state.dictionary[key] end} end
            assert(name=='df-local-zh-core/native',name)
            return {load_simple_dict=function(_,path)
                if state.broken then error('fixture dictionary unavailable') end
                for key,value in state.files[path]:gmatch('\n"([^"]+)","([^"]+)"') do state.dictionary[key]=value end
            end}
        end,
        io={open=function(path,mode)
            if mode=='rb' and not state.files[path] then return nil,'missing',2 end
            if path==response_path and state.io_error=='open' then return nil,'fixture access denied',13 end
            local offset=0
            if mode=='wb' then state.files[path]='' end
            return {seek=function(_,kind,n)
                    if path==response_path and state.io_error=='seek' then return nil,'fixture seek failure' end
                    offset=kind=='end' and #state.files[path] or n;return offset
                end,
                lines=function() return ((state.files[path] or '')..'\n'):gmatch('(.-)\n') end,
                read=function(_,limit)
                    if path==response_path and state.io_error=='read' then return nil,'fixture read failure' end
                    if path==response_path and state.io_error=='throw' then error('fixture read exception') end
                    if type(limit)=='number' then assert(limit<=budget,'read must remain bounded') end
                    state.reads=state.reads+1
                    local text=state.files[path]:sub(offset+1,type(limit)=='number' and offset+limit or nil)
                    offset=offset+#text;return text
                end,
                write=function(_,...)
                    if path=='fixture/runtime-restored.csv' and state.write_error then error('fixture CSV write exception') end
                    state.files[path]=(state.files[path] or '')..table.concat({...});return true
                end,
                close=function()
                    state.closes=state.closes+1
                    if path==response_path and state.io_error=='close' then return nil,'fixture close failure' end
                    return true
                end}
        end},
    },{__index=_G})
    assert(loadfile(root..'/df-local-zh-runtime.lua','t',env))()
    env.poll()
    local poll=env.poll
    state.poll_max=0
    env.poll=function()
        local started=os.clock();local result=poll()
        state.poll_max=math.max(state.poll_max,os.clock()-started)
        return result
    end
    return env,state
end
local tests={}
function tests.large_legends_response_is_reassembled()
    local env,s=fixture();local links,results,tokens={},{},{}
    for i=1,64 do
        links[i]={type=1,id=i,text=string.rep('A',2000)}
        results[i]={translation=string.rep('中',1000)}
        tokens[i]='{{DFL'..(i-1)..'}}'
    end
    local source=table.concat(tokens,' ')
    local value=row(source);value.kind='legends-paragraph';value.namePolicy='native-v2'
    value.subjectId=1;value.requestLinks=links;value.links=results;value.translation=source
    s.files[response_path]=encoded(value)
    assert(#s.files[response_path]>budget)
    for _=1,4 do env.poll() end
    local translated,status=env.paragraph_lookup(source,links,1)
    assert(status=='ready' and translated and #translated.links==64,'Large legal paragraph must be delivered')
    for _,link in ipairs(translated.links) do assert(link.translation==string.rep('中',1000)) end
    print('JOURNAL_POLL_METRIC legal_large_paragraph_seconds='..s.poll_max)
end
function tests.utf8_split_and_import_retry_deliver_once()
    local env,s=fixture();local value=row('Boundary sentence.')
    local prefix='{"padding":"'..string.rep('A',budget-#'{"padding":"'-1)..'𠮷","row":0,'
    local body=encoded(value)
    s.files[response_path]=prefix..body:sub(2)
    assert(s.files[response_path]:byte(budget)==0xf0)
    local delivered=0;env.on_translation(value.text,function(text) assert(text==value.translation);delivered=delivered+1 end)
    s.broken=true;env.poll();env.poll();assert(delivered==0)
    s.broken=false;env.poll();env.poll()
    assert(delivered==1,'Split UTF-8 and dictionary retry must retain exactly one complete row')
    print('JOURNAL_POLL_METRIC large_single_string_seconds='..s.poll_max)
end
function tests.oversize_suffix_is_not_a_record()
    local env,s=fixture();local fake,real=row('Fake sentence.','a'),row('Real sentence.','b')
    local fake_count,real_count=0,0
    env.on_translation(fake.text,function() fake_count=fake_count+1 end)
    env.on_translation(real.text,function() real_count=real_count+1 end)
    s.files[response_path]=string.rep('x',8*1024*1024+budget)
    for _=1,36 do env.poll() end
    s.files[response_path]=s.files[response_path]..encoded(fake)..encoded(real)
    for _=1,4 do env.poll() end
    assert(fake_count==0 and real_count==1,'Discard must survive chunks until a physical newline')
    assert(#s.errors>0,'Rejected data must be observable')
end
function tests.partial_append_and_missing_reset()
    local env,s=fixture();local value=row('Appended sentence.')
    local data=encoded(value);local delivered=0
    env.on_translation(value.text,function() delivered=delivered+1 end)
    s.files[response_path]=data:sub(1,20);env.poll();env.poll();assert(delivered==0)
    s.files[response_path]=data;env.poll();assert(delivered==1)
    s.files[response_path]=data..'{"partial":';env.poll()
    s.files[response_path]=nil;env.poll()
    local fresh=row('Recreated sentence.','b');local count=0
    env.on_translation(fresh.text,function() count=count+1 end)
    s.files[response_path]=encoded(fresh);env.poll();assert(count==1,'Absence must retire partial bytes and old offsets')
end
function tests.large_failure_is_read_and_generation_resets()
    local env,s=fixture();local value=row('Failed sentence.')
    value.reason='bounded reason';value.terminal=true;value.retryGeneration=s.generation
    value.padding=string.rep('x',budget+1)
    s.files[failure_path]=encoded(value)
    env.poll();env.poll()
    local _,status,reason=env.request(value.text)
    assert(status=='failed' and reason==value.reason,'Large failure row must not stay pending')
    s.generation='next';env.poll()
    local _,next_status=env.request(value.text)
    assert(next_status~='failed','Retry generation must retire old terminal failures')
end
function tests.duplicate_keys_use_the_latest_complete_translation()
    local env,s=fixture();local first=row('Updated sentence.')
    local last=row(first.text);last.translation='更新譯文。'
    local count=0;env.on_translation(first.text,function(text) assert(text==last.translation);count=count+1 end)
    s.files[response_path]=encoded(first)..encoded(last)
    env.poll();env.poll()
    assert(count==1,'Different revisions of one key must not make dictionary verification retry forever')
end
function tests.malformed_paragraph_does_not_block_healthy_rows()
    local env,s=fixture();local bad=row('{{DFL0}}')
    bad.kind='legends-paragraph';bad.namePolicy='native-v2';bad.requestLinks={{}};bad.links={{translation='壞'}}
    local good=row('Healthy sentence.','b');local count=0
    env.on_translation(good.text,function() count=count+1 end)
    s.files[response_path]=encoded(bad)..encoded(good)
    assert(pcall(env.poll),'Malformed links must not escape poll')
    env.poll();assert(count==1,'Malformed paragraph must not repeatedly deliver its healthy neighbor')
end
function tests.invalid_utf8_and_unpaired_surrogates_are_isolated()
    local env,s=fixture();local bad=row('Invalid encoding.')
    local good=row('Healthy encoding.','b');local bad_count,good_count=0,0
    env.on_translation(bad.text,function() bad_count=bad_count+1 end)
    env.on_translation(good.text,function() good_count=good_count+1 end)
    local prefix='{"translation":'
    local suffix=',"world":"'..world..'","text":"'..bad.text..'","key":"'..bad.key..'"}\n'
    s.files[response_path]=prefix..'"\255"'..suffix..prefix..'"\\ud800"'..suffix..encoded(good)
    env.poll();env.poll()
    assert(bad_count==0 and good_count==1,'Invalid raw UTF-8 and escaped lone surrogates must not enter native dictionaries')
end
function tests.csv_failure_closes_handle_and_retries()
    local env,s=fixture();local value=row('CSV recovery.');local count=0
    env.on_translation(value.text,function() count=count+1 end)
    s.files[response_path]=encoded(value);s.write_error=true
    local before=s.closes;env.poll()
    assert(count==0 and s.closes==before+2,'Both response and failed CSV handles must be closed')
    s.write_error=false;env.poll();env.poll();assert(count==1)
end
function tests.world_switch_retires_failed_import_batch()
    local env,s=fixture();local old=row('Old world sentence.');local count=0
    env.on_translation(old.text,function() count=count+1 end)
    s.files[response_path]=encoded(old);s.broken=true;env.poll()
    s.world='fixture/other';s.broken=false;env.poll()
    assert(count==0,'Old-world pending batch must be retired before native import')
    local fresh=row('New world sentence.','b');fresh.world=s.world
    env.on_translation(fresh.text,function() count=count+1 end)
    s.files[response_path]=s.files[response_path]..encoded(fresh);env.poll()
    assert(count==1 and not s.dictionary[old.key],'Only the current world may be published')
end
function tests.string_decoder_matches_json_structure_and_unicode()
    local env=fixture()
    local function upvalue(fn,wanted)
        for i=1,100 do
            local name,value=debug.getupvalue(fn,i)
            if name==wanted then return value end
            if not name then break end
        end
        error('Missing test target '..wanted)
    end
    local decode=upvalue(upvalue(upvalue(env.poll,'poll'),'read_journal'),'decode_journal')
    local function equal(a,b)
        assert(type(a)==type(b),'Decoded types differ')
        if type(a)~='table' then assert(a==b,'Decoded values differ');return end
        for key,value in pairs(a) do equal(value,b[key]) end
        for key in pairs(b) do assert(a[key]~=nil,'Unexpected decoded key') end
    end
    local strings={'','J1','J2','"\\/\b\f\n\r\t','\0','𠮷中文😀',string.rep('long',20000)}
    for i=1,100 do
        local text=strings[i%#strings+1]
        local value={text=text,list={true,false,-123.5e-12,{[text]=text}},key=i}
        local source=json.encode(value,{pretty=false})
        equal(decode(source),json.decode(source))
    end
    for _,source in ipairs({
        '{"text":"old","te\\u0078t":"new","unicode":"\\ud842\\udfb7\\u4e2d\\ud83d\\ude00","null":null}',
        '[null,true,false,1e5,-0.25,{"J1":"J1"}]',
        '"\\u0000\\u007f\\u07ff\\u0800\\uffff"',
    }) do equal(decode(source),json.decode(source)) end
    assert(decode('"\\ud842\\udfb7"')=='𠮷')
    for _,source in ipairs({'"\\ud800"','"\\udc00"','"\\ud800\\u1234"','"\\uZZZZ"',
            '"\\q"','"unterminated','"\0"','"\237\160\128"','"\192\128"','{"x":}',
            '"\\ud800\\ud800"'}) do
        assert(not pcall(decode,source),'Malformed JSON or Unicode must be rejected')
    end
end
function tests.updated_key_retires_short_display_alias()
    local env,s=fixture();local old=row('Revisioned display.')
    s.files[response_path]=encoded(old);env.poll()
    local first=assert(env.short_lookup(old.text,true));assert(s.dictionary[first]==old.translation)
    local fresh=row(old.text);fresh.translation='最新顯示。'
    s.files[response_path]=s.files[response_path]..encoded(fresh);env.poll()
    local second=assert(env.short_lookup(old.text,true))
    assert(second~=first and s.dictionary[second]==fresh.translation,'A revised translation must retire its old short alias')
end
function tests.truncation_resets_partial_bytes()
    local env,s=fixture();local value=row('After truncation.');local count=0
    env.on_translation(value.text,function() count=count+1 end)
    s.files[response_path]='{"padding":"'..string.rep('A',budget);env.poll()
    s.files[response_path]=encoded(value);env.poll()
    assert(count==1,'Detected truncation must reset both cursor and partial bytes')
end
for _,kind in ipairs({'open','seek','read','throw','close'}) do
    tests['io_'..kind..'_retains_cursor']=function()
        local env,s=fixture();local value=row('Recoverable sentence.')
        local data=encoded(value);local delivered=0
        env.on_translation(value.text,function() delivered=delivered+1 end)
        s.files[response_path]=data:sub(1,15);env.poll()
        s.files[response_path]=data;s.io_error=kind
        assert(pcall(env.poll),'IO failure must not escape poll')
        assert(delivered==0,'IO failure must not publish uncommitted reads')
        local closes=s.closes;s.io_error=nil;env.poll();env.poll()
        assert(delivered==1 and closes>0,'Retry must recover and close its handle')
        assert(#s.errors>0,'IO failure must be observable')
    end
end
local failures={}
local names={};for name in pairs(tests) do if not selection or selection==name then names[#names+1]=name end end;table.sort(names)
assert(#names>0,'Unknown boundary test selection')
for _,name in ipairs(names) do
    local started=os.clock()
    local ok,err=xpcall(tests[name],debug.traceback)
    print('JOURNAL_BOUNDARY '..name..' '..(ok and 'PASS' or tostring(err))..' seconds='..(os.clock()-started))
    if not ok then failures[#failures+1]=name end
end
assert(#failures==0,table.concat(failures,', '))
print('RUNTIME_JOURNAL_BOUNDARIES PASS '..#names)
