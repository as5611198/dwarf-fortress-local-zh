--@module=true
local gui=require('gui')
local widgets=require('gui.widgets')
local overlay=require('plugins.overlay')
local settings=reqscript('df-local-zh-settings')
local runtime=reqscript('df-local-zh-runtime')
local mod=reqscript('df-local-zh-core/mod')
local native=reqscript('df-local-zh-core/native')

local function raw_paint(pen,x,y,text)
    native.interception_bypass_enable()
    local ok,err=xpcall(function() dfhack.screen.paintString(pen,x,y,text) end,debug.traceback)
    native.interception_bypass_disable()
    if not ok then error(err) end
end

local function clone(value) return require('utils').clone(value,true) end
local function paint(x,y,text,color,max_width)
    text=type(text)=='string' and text or ''
    local used,part,chinese=0,'',nil
    local function flush()
        if part=='' then return end
        if chinese then
            local key=runtime.literal_key(part)
            local expected=runtime.localize_text and runtime.localize_text(part) or part
            if key and mod.async_translate(key)==expected then
                runtime.draw_key(x+used,y,color or COLOR_WHITE,0,key,0x80000000)
            end
        else
            raw_paint(color or COLOR_WHITE,x+used,y,part)
        end
        used=used+(chinese and utf8.len(part)*2 or #part)
        part=''
    end
    for _,point in utf8.codes(text) do
        local is_chinese=point>127
        local width=is_chinese and 2 or 1
        if max_width and used+(chinese and utf8.len(part)*2 or #part)+width>max_width then break end
        if chinese~=nil and chinese~=is_chinese then flush() end
        chinese=is_chinese
        part=part..utf8.char(point)
    end
    flush()
end
local function enabled(widget)
    return widget.enabled==nil or require('utils').getval(widget.enabled)
end
local provider_urls={Google='https://generativelanguage.googleapis.com/v1beta',OpenAI='https://api.openai.com/v1',
    DeepSeek='https://api.deepseek.com/v1',Grok='https://api.x.ai/v1',OpenRouter='https://openrouter.ai/api/v1'}
local screen

NativeLabel=defclass(NativeLabel,widgets.Panel)
NativeLabel.ATTRS{text=DEFAULT_NIL,text_pen=COLOR_WHITE}
function NativeLabel:onRenderBody()
    local rect=self.frame_body
    paint(rect.x1,rect.y1,require('utils').getval(self.text),self.text_pen,rect.x2-rect.x1+1)
end

NativeCycle=defclass(NativeCycle,widgets.CycleHotkeyLabel)
function NativeCycle:onRenderBody()
    local rect=self.frame_body
    local label_width=self.label_width or 20
    paint(rect.x1,rect.y1,require('utils').getval(self.label),COLOR_WHITE,label_width)
    paint(rect.x1+label_width,rect.y1,self:getOptionLabel(),self:getOptionPen() or COLOR_LIGHTCYAN,
        rect.x2-rect.x1+1-label_width)
end

NativeEdit=defclass(NativeEdit,widgets.EditField)
NativeEdit.ATTRS{native_label=DEFAULT_NIL}
function NativeEdit:init()
    self.label.onRenderBody=function() end
    self.text_area.frame.l=24
    local content=self.text_area.text_area
    local render=content.onRenderBody
    content.onRenderBody=function(area,dc)
        native.interception_bypass_enable()
        local ok,err=xpcall(function() render(area,dc) end,debug.traceback)
        native.interception_bypass_disable()
        if not ok then error(err) end
    end
end
function NativeEdit:onRenderBody()
    local rect=self.frame_body
    local prefix=self.key and gui.getKeyDisplay(self.key)..': ' or ''
    if prefix~='' then raw_paint(COLOR_LIGHTGREEN,rect.x1,rect.y1,prefix) end
    paint(rect.x1+#prefix,rect.y1,self.native_label,COLOR_WHITE,23-#prefix)
end

NativeButton=defclass(NativeButton,widgets.Panel)
NativeButton.ATTRS{key=DEFAULT_NIL,caption=DEFAULT_NIL,on_activate=DEFAULT_NIL}
function NativeButton:onRenderBody()
    local rect=self.frame_body
    local prefix=gui.getKeyDisplay(self.key)..': '
    raw_paint(COLOR_LIGHTGREEN,rect.x1,rect.y1,prefix)
    paint(rect.x1+#prefix,rect.y1,require('utils').getval(self.caption),
        enabled(self) and COLOR_WHITE or COLOR_DARKGREY,rect.x2-rect.x1+1-#prefix)
end
function NativeButton:onInput(keys)
    if enabled(self) and (keys[self.key] or keys._MOUSE_L and self:getMousePos()) then
        self.on_activate();return true
    end
end

NativeTabs=defclass(NativeTabs,widgets.Panel)
NativeTabs.ATTRS{labels=DEFAULT_NIL,get_cur_page=DEFAULT_NIL,on_select=DEFAULT_NIL}
function NativeTabs:onRenderBody()
    local rect=self.frame_body
    local segment=math.floor((rect.x2-rect.x1+1)/#self.labels)
    for index,label in ipairs(self.labels) do
        paint(rect.x1+(index-1)*segment+1,rect.y1,label,
            self.get_cur_page()==index and COLOR_YELLOW or COLOR_WHITE,segment-2)
    end
end
function NativeTabs:onInput(keys)
    if keys._MOUSE_L then
        local x=self:getMousePos()
        if x then
            local segment=math.floor((self.frame_body.x2-self.frame_body.x1+1)/#self.labels)
            self.on_select(math.min(#self.labels,math.floor(x/segment)+1));return true
        end
    end
    if keys.CUSTOM_CTRL_T or keys.CUSTOM_CTRL_Y then
        local step=keys.CUSTOM_CTRL_T and 1 or -1
        self.on_select((self.get_cur_page()-1+step+#self.labels)%#self.labels+1);return true
    end
end

SecretField=defclass(SecretField,widgets.Panel)
SecretField.ATTRS{value=DEFAULT_NIL,has_key=false,on_change=DEFAULT_NIL}
function SecretField:onRenderBody()
    local text=self.value and string.rep('*',math.min(32,#self.value)) or
        (self.has_key and '已保存的金鑰' or '未設定')
    local rect=self.frame_body
    paint(rect.x1,rect.y1,text,self.focus and COLOR_YELLOW or COLOR_LIGHTCYAN,rect.x2-rect.x1+1)
end
function SecretField:setValue(value)
    if type(value)~='string' or #value>8192 or value:match('[%z\1-\31\127-\255]') then return end
    self.value=value;self.selected=false;if self.on_change then self.on_change(value) end
end
function SecretField:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then self:setFocus(true);return true end
    if not self.focus then return false end
    if keys.LEAVESCREEN or keys.SELECT then self:setFocus(false);return true end
    if keys.CUSTOM_CTRL_V then self:setValue(dfhack.internal.getClipboardTextCp437() or '');return true end
    if keys.CUSTOM_CTRL_A then self.selected=true;return true end
    if keys._STRING==0 or keys.CUSTOM_BACKSPACE then self:setValue(self.selected and '' or (self.value or ''):sub(1,-2));return true end
    if keys._STRING and keys._STRING>=32 and keys._STRING<127 then
        self:setValue((self.selected and '' or self.value or '')..string.char(keys._STRING));self.selected=false;return true
    end
    return false
end

-- Unicode editor: use native Chinese painting and codepoint-safe navigation.
PromptText=defclass(PromptText,widgets.Panel)
PromptText.ATTRS{text='',on_change=DEFAULT_NIL}
function PromptText:init()
    self.cursor=1;self.scroll=0;self.selected=false
    self.literal_keys={};self.literal_counter=0
    self.literal_prefix='DFPROMPT_'..tostring({}):gsub('[^%w]','')..'_'
end
function PromptText:paint_literal(x,y,text,color)
    if text=='' then return end
    local key=self.literal_keys[text]
    if not key then
        self.literal_counter=self.literal_counter+1
        key=self.literal_prefix..self.literal_counter
        if not runtime.publish(key,text) then return end
        self.literal_keys[text]=key
    end
    local expected=runtime.localize_text and runtime.localize_text(text) or text
    if mod.async_translate(key)==expected then runtime.draw_key(x,y,color,0,key,0x80000000) end
end
function PromptText:getText() return self.text end
function PromptText:setText(value)
    if type(value)~='string' or not utf8.len(value) or utf8.len(value)>8192 or value:find('[%z\1-\8\11\12\14-\31]') then return false end
    self.text=value:gsub('\r\n?','\n');self.cursor=math.min(self.cursor,utf8.len(self.text)+1)
    if self.on_change then self.on_change(self.text) end
    return true
end
function PromptText:replace(value,erase)
    local first=utf8.offset(self.text,self.cursor) or #self.text+1
    local last=erase and (utf8.offset(self.text,self.cursor+1) or #self.text+1) or first
    local text=self.selected and value or self.text:sub(1,first-1)..value..self.text:sub(last)
    if not self:setText(text) then return false end
    self.cursor=(self.selected and 1 or self.cursor)+(utf8.len(value) or 0);self.selected=false
    return true
end
function PromptText:onRenderBody()
    local rect=self.frame_body;local width=rect.width-1
    local lines,column,index={{text='',start=1}},0,1
    for _,point in utf8.codes(self.text) do
        local cells=point>127 and 2 or 1
        if point==10 then lines[#lines+1]={text='',start=index+1};column=0
        else
            if column+cells>width then lines[#lines+1]={text='',start=index};column=0 end
            lines[#lines].text=lines[#lines].text..utf8.char(point);column=column+cells
        end
        index=index+1
    end
    local cursor_line=1
    for i,line in ipairs(lines) do if line.start<=self.cursor then cursor_line=i end end
    self.scroll=math.max(0,math.min(self.scroll,cursor_line-1))
    if cursor_line>self.scroll+rect.height then self.scroll=cursor_line-rect.height end
    for i=1,rect.height do
        local line=lines[self.scroll+i]
        if line and line.text~='' then
            -- Native rows also protect Latin prompt text from occupied tiles
            -- left by the game underneath this modal; never translate input.
            self:paint_literal(rect.x1,rect.y1+i-1,line.text,self.selected and COLOR_YELLOW or COLOR_LIGHTCYAN)
        end
    end
    if self.focus then
        local line=lines[cursor_line];local offset=self.cursor-line.start
        local ending=utf8.offset(line.text,offset+1) or #line.text+1
        local before=line.text:sub(1,ending-1);local x=0
        for _,p in utf8.codes(before) do x=x+(p>127 and 2 or 1) end
        local following=utf8.offset(line.text,offset+2) or #line.text+1
        local character=line.text:sub(ending,following-1)
        self:paint_literal(rect.x1+math.min(x,width),rect.y1+cursor_line-self.scroll-1,character~='' and character or '_',COLOR_YELLOW)
    end
end
function PromptText:onInput(keys)
    if keys._MOUSE_L and self:getMousePos() then self:setFocus(true);return true end
    if not self.focus then return false end
    local length=utf8.len(self.text)
    if keys.CUSTOM_CTRL_A then self.selected=true;return true end
    if keys.CURSOR_LEFT then self.cursor=math.max(1,self.cursor-1);self.selected=false;return true end
    if keys.CURSOR_RIGHT then self.cursor=math.min(length+1,self.cursor+1);self.selected=false;return true end
    if keys.CURSOR_UP or keys.CURSOR_DOWN then
        self.cursor=math.max(1,math.min(length+1,self.cursor+(keys.CURSOR_UP and -1 or 1)*math.max(1,(self.frame_body and self.frame_body.width or 50)-1)))
        self.selected=false;return true
    end
    if keys.CUSTOM_HOME then self.cursor=1;self.selected=false;return true end
    if keys.CUSTOM_END then self.cursor=length+1;self.selected=false;return true end
    if keys.CUSTOM_BACKSPACE or keys._STRING==0 then
        if self.selected then self:replace('')
        elseif self.cursor>1 then self.cursor=self.cursor-1;self:replace('',true) end
        return true
    end
    if keys.CUSTOM_DELETE then self:replace('',true);return true end
    if keys.SELECT then self:replace('\n');return true end
    if keys._STRING and keys._STRING>=32 and keys._STRING<127 then self:replace(string.char(keys._STRING));return true end
    return false
end

PromptScreen=defclass(PromptScreen,gui.ZScreen)
PromptScreen.ATTRS{focus_path='df-local-zh/prompt',value='',default_text='',on_accept=DEFAULT_NIL}
function PromptScreen:init()
    local w,h=dfhack.screen.getWindowSize()
    self.default_mode=self.value=='';self.message=''
    self:addviews{widgets.Window{view_id='window',frame={w=math.min(78,w-2),h=math.min(33,h-2)},
        frame_title='Translation Prompt',resizable=false,draggable=false,subviews={
            NativeLabel{frame={l=1,t=0,r=1,h=1},text='翻譯指引：可編輯多行文字，中文可貼上'},
            PromptText{view_id='prompt_text',frame={l=1,t=2,r=1,b=6},
                text=self.default_mode and self.default_text or self.value,
                on_change=function() self.default_mode=false end},
            NativeLabel{frame={l=1,b=5,r=1,h=1},text='Ctrl+A 全選；方向鍵移動；Enter 換行'},
            NativeLabel{frame={l=1,b=4,r=1,h=1},text='術語、數字、格式與專名音譯仍依固定規則'},
            NativeLabel{frame={l=1,b=3,r=1,h=1},text=function() return self.message end,text_pen=COLOR_YELLOW},
            NativeButton{view_id='paste_prompt',frame={l=1,b=2,w=22,h=1},key='CUSTOM_CTRL_V',caption='貼上',
                on_activate=function() self:paste() end},
            NativeButton{view_id='default_prompt',frame={l=25,b=2,r=1,h=1},key='CUSTOM_CTRL_R',caption='恢復預設',
                on_activate=function() self:restore_default() end},
            NativeButton{view_id='accept_prompt',frame={l=1,b=0,w=25,h=1},key='CUSTOM_CTRL_S',caption='確認編輯',
                on_activate=function() self:accept() end},
            NativeButton{frame={l=28,b=0,r=1,h=1},key='LEAVESCREEN',caption='取消',on_activate=function() self:dismiss() end},
        }}}
    self.subviews.prompt_text:setFocus(true)
end
function PromptScreen:restore_default()
    self.subviews.prompt_text:setText(self.default_text)
    self.subviews.prompt_text.cursor=1;self.default_mode=true;self.message='已恢復預設；確認後回到設定套用'
end
function PromptScreen:accept()
    local value=self.default_mode and '' or self.subviews.prompt_text:getText()
    if self.on_accept then self.on_accept(value) end
    self:dismiss()
end
function PromptScreen:paste()
    self.message='讀取剪貼簿中'
    local ok,error=settings.submit({action='clipboard'},function(result)
        if not self:isActive() then return end
        local inserted=result.ok and self.subviews.prompt_text:replace(result.text)
        self.message=inserted and '已貼上' or '無法貼上或超過 8192 字元'
    end)
    if not ok then self.message=error end
end

SettingsScreen=defclass(SettingsScreen,gui.ZScreen)
SettingsScreen.ATTRS{focus_path='df-local-zh/settings',scope_override=DEFAULT_NIL}
function SettingsScreen:load_draft()
    self.draft=settings.effective(self.scope)
    if self.draft.officialAutoDownload==nil then self.draft.officialAutoDownload=true end
    if self.draft.sharedContributions==nil then self.draft.sharedContributions=false end
    self.active_profiles=clone(self.draft.apiPoolEnabled and self.draft.apiProfiles or {self.draft.apiProfile})
    local saved_profiles=settings.get_snapshot().profiles
    self.profile_id=saved_profiles[self.profile_id] and self.profile_id or self.draft.apiProfile
    self.profiles={};self.profile_dirty_ids={};self.deleted_profiles={}
    self.profile=clone(settings.get_snapshot().profiles[self.profile_id] or {enabled=false})
    if not self.draft.apiPoolEnabled then self.profile.concurrency=self.draft.concurrency end
    self.profiles[self.profile_id]=self.profile
    self.dirty=false
end
function SettingsScreen:profile_changed()
    if self.loading then return end
    self.profile_dirty_ids[self.profile_id]=true;self.dirty=true
end
function SettingsScreen:init()
    settings.reload()
    self.scope=self.scope_override or (settings.world()~='' and 'save' or 'global')
    self.page=1;self.message='';self:load_draft()
    local function changed(key,value)
        if self.loading then return end
        self.draft[key]=value;self.dirty=true
    end
    local function toggle(id,label,key,y)
        return NativeCycle{view_id=id,frame={l=1,t=y,r=1,h=1},label=label,label_width=32,
            options={{label='開啟',value=true,pen=COLOR_LIGHTGREEN},{label='關閉',value=false}},
            initial_option=self.draft[key],on_change=function(value) changed(key,value) end}
    end
    local function number(id,label,key,y)
        return NativeEdit{view_id=id,frame={l=1,t=y,r=1,h=1},native_label=label,label_text='',
            text=tostring(self.draft[key]),key='CUSTOM_'..({concurrency='N',timeoutMs='O',maxRetries='R',retryBaseMs='D'})[key],
            on_char=function(ch) return ch:match('%d')~=nil end,
            on_change=function(value) changed(key,tonumber(value)) end}
    end
    local function profile_field(id,label,key,y)
        return NativeEdit{view_id=id,frame={l=1,t=y,r=1,h=1},native_label=label,label_text='',key='CUSTOM_'..({label='L',baseUrl='U',model='M'})[key],
            text=self.profile[key] or '',on_change=function(value)
                if self.loading then return end
                self.profile[key]=value;self:profile_changed()
            end}
    end
    local w,h=dfhack.screen.getWindowSize()
    self:addviews{widgets.Window{view_id='window',frame={w=math.min(78,w-2),h=math.min(33,h-2)},
        frame_title='DF Local ZH',resizable=false,draggable=false,
        subviews={
            NativeCycle{view_id='scope',frame={l=1,t=0,r=1,h=1},label='設定範圍',label_width=24,
                options=settings.world()~='' and {{label='本存檔',value='save'},{label='全域預設',value='global'}} or
                    {{label='全域預設',value='global'}},initial_option=self.scope,
                on_change=function(value) self.scope=value;self:load_draft();self:refresh_fields() end},
            NativeTabs{view_id='tabs',frame={l=1,t=2,r=1,h=2},
                labels={'語言顯示','模型服務','翻譯處理','雲端同步','共享投稿'},
                get_cur_page=function() return self.page end,
                on_select=function(value) self.page=value;self.subviews.pages:setSelected(value) end},
            widgets.Pages{view_id='pages',frame={l=1,t=5,r=1,b=5},subviews={
                widgets.Panel{view_id='display',subviews={
                    NativeCycle{view_id='language',frame={l=1,t=1,r=1,h=1},label='語言',label_width=32,
                        options={{label='繁體中文',value='zh-Hant'},{label='簡體中文',value='zh-Hans'}},
                        initial_option=self.draft.language,on_change=function(value) changed('language',value) end},
                    toggle('pinyin', '拼音搜尋','pinyin',4),
                    toggle('colorPersistence','顏色持久化','colorPersistence',7),
                }},
                widgets.Panel{view_id='api',subviews={
                    NativeCycle{view_id='profile_select',frame={l=1,t=0,r=1,h=1},label='模型設定檔',label_width=26,
                        options=self:profile_options(),initial_option=self.profile_id,
                        on_change=function(id) self:select_profile(id) end},
                    NativeCycle{view_id='apiEnabled',frame={l=1,t=1,r=1,h=1},label='所有模型服務',label_width=26,
                        options={{label='開啟',value=true},{label='關閉',value=false}},initial_option=self.draft.apiEnabled,
                        on_change=function(value) changed('apiEnabled',value) end},
                    NativeCycle{view_id='apiParticipating',frame={l=1,t=2,r=1,h=1},label='啟用此 API',label_width=26,
                        enabled=function() return self:has_profile() end,
                        options={{label='開啟',value=true},{label='關閉',value=false}},initial_option=self:profile_participating(),
                        on_change=function(value) if not self.loading then self:set_participating(value) end end},
                    NativeCycle{view_id='kind',frame={l=1,t=3,r=1,h=1},label='協定',label_width=16,
                        options={{label='OpenAI API',value='Custom_OpenAI'},{label='Google',value='Google'},
                            {label='OpenAI',value='OpenAI'},{label='DeepSeek',value='DeepSeek'},
                            {label='Grok',value='Grok'},{label='OpenRouter',value='OpenRouter'}},
                        initial_option=self.profile.kind,on_change=function(value)
                            self.profile.kind=value;self:profile_changed()
                            if provider_urls[value] then
                                self.subviews.api_url:setText(provider_urls[value])
                            end
                        end},
                    profile_field('api_label','名稱','label',4),profile_field('api_url','服務網址','baseUrl',5),
                    profile_field('api_model','模型','model',6),
                    NativeLabel{frame={l=1,t=7,w=12,h=1},text='金鑰'},
                    SecretField{view_id='api_key',frame={l=14,t=7,r=1,h=1},has_key=self.profile.hasKey==true,
                        on_change=function(value) self.profile.key=value;self:profile_changed() end},
                    NativeLabel{view_id='api_key_help',frame={l=1,t=8,r=1,h=1},
                        text='點金鑰欄輸入或 Ctrl+V 貼上，Ctrl+S 套用',text_pen=COLOR_GREY},
                    NativeEdit{view_id='apiConcurrency',frame={l=1,t=9,r=1,h=1},native_label='此 API 並行數',label_text='',
                        text=tostring(self.profile.concurrency or 2),key='CUSTOM_B',on_char=function(ch) return ch:match('%d')~=nil end,
                        on_change=function(value) if not self.loading then
                            self.profile.concurrency=tonumber(value);self:profile_changed()
                            self.draft.apiPoolEnabled=true;self.draft.apiProfiles=clone(self.active_profiles)
                        end end},
                    NativeButton{view_id='new_profile',frame={l=1,t=10,w=22,h=1},key='CUSTOM_A',caption='新增設定檔',
                        on_activate=function() self:new_profile() end},
                    NativeButton{view_id='delete_profile',frame={l=26,t=10,w=24,h=1},key='CUSTOM_X',caption='刪除設定檔',
                        enabled=function() return self:has_profile() and not settings.is_pending() end,
                        on_activate=function() self:delete_profile() end},
                    NativeButton{view_id='test',frame={l=1,t=11,w=22,h=1},key='CUSTOM_T',caption='測試連線',
                        enabled=function() return self:has_profile() and not settings.is_pending() end,on_activate=function() self:test_connection() end},
                    NativeButton{view_id='clear_key',frame={l=26,t=11,w=20,h=1},key='CUSTOM_K',caption='清除金鑰',
                        on_activate=function() self.subviews.api_key:setValue('') end},
                    NativeLabel{view_id='poolHelp',frame={l=1,t=12,r=1,h=1},text='此 API 可單獨開關；各組並行數 1-16',text_pen=COLOR_GREY},
                }},
                widgets.Panel{view_id='translation',subviews={
                    toggle('backgroundTranslation','背景翻譯','backgroundTranslation',0),
                    NativeLabel{view_id='backgroundHelp',frame={l=1,t=1,r=1,h=1},
                        text='閒置時補譯背景佇列，前景請求優先',text_pen=COLOR_GREY},
                    number('concurrency','合計並行上限','concurrency',2),number('timeoutMs','逾時毫秒','timeoutMs',4),
                    number('maxRetries','最大重試次數','maxRetries',6),number('retryBaseMs','重試間隔毫秒','retryBaseMs',8),
                    NativeLabel{view_id='concurrencyHelp',frame={l=1,t=3,r=1,h=1},
                        text='所有 API 合計的請求上限（1-32）',text_pen=COLOR_GREY},
                    NativeLabel{view_id='timeoutHelp',frame={l=1,t=5,r=1,h=1},
                        text='單次模型請求的等待上限（毫秒）',text_pen=COLOR_GREY},
                    NativeLabel{view_id='retriesHelp',frame={l=1,t=7,r=1,h=1},
                        text='請求失敗後再次嘗試的次數（0-5）',text_pen=COLOR_GREY},
                    NativeLabel{view_id='retryDelayHelp',frame={l=1,t=9,r=1,h=1},
                        text='每次重試前等待的時間（毫秒）',text_pen=COLOR_GREY},
                    NativeButton{view_id='edit_prompt',frame={l=1,t=11,r=1,h=1},key='CUSTOM_P',caption='翻譯提示詞',
                        on_activate=function() self:edit_prompt() end},
                    NativeLabel{view_id='promptHelp',frame={l=1,t=12,r=1,h=1},
                        text='編輯翻譯指引，套用後供新的模型請求使用',text_pen=COLOR_GREY},
                }},
                widgets.Panel{view_id='cloud',subviews={
                    toggle('officialAutoDownload','自動下載官方譯庫','officialAutoDownload',0),
                    NativeButton{view_id='official_sync',frame={l=1,t=2,w=24,h=1},key='CUSTOM_J',caption='立即同步',
                        enabled=function() return not settings.is_pending() end,on_activate=function() self:sync_official() end},
                    NativeLabel{view_id='official_language',frame={l=1,t=4,r=1,h=1},text=function() return '目前語言：'..(self.draft.language=='zh-Hans' and '簡體中文' or '繁體中文') end},
                    NativeLabel{view_id='official_installed',frame={l=1,t=5,r=1,h=1},text=function() return '已安裝：'..(self:official_status().installedVersion or '尚無') end},
                    NativeLabel{view_id='official_available',frame={l=1,t=6,r=1,h=1},text=function() return '可用版本：'..(self:official_status().availableVersion or '尚無') end},
                    NativeLabel{view_id='official_phase',frame={l=1,t=7,r=1,h=1},text=function()
                        local value=self:official_status()
                        local phases={idle='尚未下載',checking='檢查更新',downloading='下載中',verifying='驗證中',pending='待啟用',complete='已完成',error='同步失敗',recovered='已回復前版'}
                        return '狀態：'..(phases[value.phase] or '尚未下載')..' '..tostring(value.progress or 0)..'%'
                    end},
                    NativeLabel{view_id='official_entries',frame={l=1,t=8,r=1,h=1},text=function() return '條目數：'..tostring(self:official_status().entries or 0) end},
                    NativeLabel{view_id='official_success',frame={l=1,t=9,r=1,h=1},text=function()
                        local value=self:official_status().lastSuccess or '';return '上次成功：'..(value=='' and '尚無' or value:gsub('T',' '):gsub('%.%d+Z$',' UTC'))
                    end},
                    NativeLabel{view_id='official_error',frame={l=1,t=10,r=1,h=1},text=function() return self:official_status().error or '' end,text_pen=COLOR_YELLOW},
                    NativeLabel{view_id='official_help',frame={l=1,t=11,r=1,h=1},text='遊戲中更新待啟用；關閉遊戲後重啟服務',text_pen=COLOR_GREY},
                    NativeLabel{view_id='official_offline',frame={l=1,t=12,r=1,h=1},text='關閉下載仍可離線使用；不需要模型金鑰',text_pen=COLOR_GREY},
                }},
                widgets.Panel{view_id='sharing',subviews={
                    toggle('sharedContributions','分享通用 AI 譯文（CC0）','sharedContributions',0),
                    NativeLabel{view_id='shared_privacy',frame={l=1,t=2,r=1,h=1},text='過濾專名；只分享通用句與安全模板',text_pen=COLOR_GREY},
                    NativeLabel{view_id='shared_consent',frame={l=1,t=3,r=1,h=1},text='不送存檔／API；啟用同意以 CC0 分享',text_pen=COLOR_GREY},
                    NativeLabel{view_id='shared_gate',frame={l=1,t=4,r=1,h=1},text='三裝置／網段＋AI 語意審核後收錄',text_pen=COLOR_GREY},
                    NativeLabel{view_id='shared_phase',frame={l=1,t=6,r=1,h=1},text=function()
                        local phases={idle='尚無待送資料',pending='等待背景上報',sending='上報中',complete='已完成',error='上報失敗'}
                        return '狀態：'..(phases[self:shared_status().phase] or '等待背景作業')
                    end},
                    NativeLabel{view_id='shared_count',frame={l=1,t=7,r=1,h=1},text=function()
                        local value=self:shared_status();return '待送：'..tostring(value.pending or 0)..'　已送：'..tostring(value.sent or 0)
                    end},
                    NativeLabel{view_id='shared_error',frame={l=1,t=8,r=1,h=1},text=function() return self:shared_status().error or '' end,text_pen=COLOR_YELLOW},
                    NativeButton{view_id='shared_clear',frame={l=1,t=10,w=28,h=1},key='CUSTOM_J',caption='清除待送出的資料',
                        enabled=function() return not settings.is_pending() end,on_activate=function() self:clear_shared() end},
                    NativeLabel{view_id='shared_help',frame={l=1,t=12,r=1,h=1},text='預設關閉；不掃描舊快取；AI 仍可能誤判',text_pen=COLOR_GREY},
                }},
            }},
            NativeLabel{view_id='message',frame={l=2,b=4,r=2,h=1},text=function() return self.message end,text_pen=COLOR_YELLOW},
            NativeButton{view_id='apply',frame={l=2,b=1,w=20,h=1},key='CUSTOM_CTRL_S',caption='套用',
                enabled=function() return not settings.is_pending() end,on_activate=function() self:apply() end},
            NativeButton{view_id='inherit',frame={l=24,b=1,w=27,h=1},key='CUSTOM_I',caption='沿用全域預設',
                enabled=function() return self.scope=='save' and not settings.is_pending() end,on_activate=function() self:apply(true) end},
            NativeButton{view_id='cancel',frame={l=2,b=0,w=18,h=1},key='LEAVESCREEN',caption='取消',on_activate=function() self:dismiss() end},
        }}}
end
function SettingsScreen:official_status()
    return settings.official_status and settings.official_status(self.draft.language) or {phase='idle',entries=0}
end
function SettingsScreen:sync_official()
    local ok,error=settings.submit({action='official-sync',language=self.draft.language},function(result)
        if self:isActive() then self.message=result.ok and '同步已排入背景；請查看狀態' or result.error end
    end)
    self.message=ok and '提交同步作業' or error;return ok,error
end
function SettingsScreen:shared_status()
    return settings.shared_status and settings.shared_status() or {phase='idle',pending=0,sent=0}
end
function SettingsScreen:clear_shared()
    local ok,error=settings.submit({action='shared-clear'},function(result)
        if self:isActive() then self.message=result.ok and '已清除待送資料；官方譯庫與快取保留' or result.error end
    end)
    self.message=ok and '清除待送資料中' or error;return ok,error
end
function SettingsScreen:edit_prompt()
    local defaults=settings.get_snapshot().promptDefaults
    local editor=PromptScreen{value=self.draft.translationPrompt or '',default_text=defaults and defaults.translation or '',
        on_accept=function(value) self.draft.translationPrompt=value;self.dirty=true;self.message='提示詞已更新；請套用以儲存' end}
    editor:show();return editor
end
function SettingsScreen:profile_options()
    local rows={}
    local profiles=clone(settings.get_snapshot().profiles)
    for id,value in pairs(self.profiles) do
        if value.label or profiles[id] then profiles[id]=value end
    end
    for id,value in pairs(profiles) do
        if not (self.deleted_profiles or {})[id] then
        local label=value.label or id
        if #label>26 then label=utf8.offset(label,13) and label:sub(1,utf8.offset(label,13)-1) or label end
        rows[#rows+1]={label=label,value=id}
        end
    end
    table.sort(rows,function(a,b) return a.value<b.value end)
    if #rows==0 then rows={{label='尚無設定檔',value='legacy'}} end
    return rows
end
function SettingsScreen:has_profile()
    if (self.deleted_profiles or {})[self.profile_id] then return false end
    return settings.get_snapshot().profiles[self.profile_id]~=nil or
        self.profiles[self.profile_id]~=nil and self.profiles[self.profile_id].label~=nil
end
function SettingsScreen:deleted_profile_ids()
    local ids={};for id in pairs(self.deleted_profiles or {}) do ids[#ids+1]=id end
    table.sort(ids);return ids
end
function SettingsScreen:delete_profile()
    if not self:has_profile() then return end
    local id=self.profile_id
    if settings.get_snapshot().profiles[id] then self.deleted_profiles[id]=true end
    if self.profiles[id] then self.profiles[id].key=nil end
    self.profiles[id]=nil;self.profile_dirty_ids[id]=nil
    local ids={};for _,member in ipairs(self.active_profiles) do if member~=id then ids[#ids+1]=member end end
    self.active_profiles=ids;self.draft.apiProfiles=clone(ids);self.draft.apiPoolEnabled=true
    local next_id=self:profile_options()[1].value
    if self.draft.apiProfile==id then self.draft.apiProfile=next_id end
    self:select_profile(next_id)
    self.message='已移除；套用後從所有存檔刪除'
end
function SettingsScreen:refresh_fields()
    self.loading=true
    for _,key in ipairs({'language','pinyin','colorPersistence','apiEnabled','backgroundTranslation','officialAutoDownload','sharedContributions'}) do self.subviews[key]:setOption(self.draft[key]) end
    for _,key in ipairs({'concurrency','timeoutMs','maxRetries','retryBaseMs'}) do self.subviews[key]:setText(tostring(self.draft[key])) end
    for _,entry in ipairs({{'api_label','label'},{'api_url','baseUrl'},{'api_model','model'}}) do self.subviews[entry[1]]:setText(self.profile[entry[2]] or '') end
    self.subviews.kind:setOption(self.profile.kind)
    self.subviews.apiParticipating:setOption(self:profile_participating())
    self.subviews.apiConcurrency:setText(tostring(self.profile.concurrency or 2))
    self.subviews.api_key.value=self.profile.key;self.subviews.api_key.has_key=self.profile.hasKey==true
    self.subviews.profile_select.options=self:profile_options()
    self.subviews.profile_select:setOption(self.profile_id)
    self.loading=false
end
function SettingsScreen:select_profile(id)
    self.profile_id=id
    self.profile=self.profiles[id] or clone(settings.get_snapshot().profiles[id] or {enabled=false})
    self.profiles[id]=self.profile;self:refresh_fields();self.dirty=true
end
function SettingsScreen:profile_participating()
    for _,id in ipairs(self.active_profiles) do if id==self.profile_id then return self.profile.enabled~=false end end
    return false
end
function SettingsScreen:set_participating(value)
    local ids={}
    for _,id in ipairs(self.active_profiles) do if id~=self.profile_id then ids[#ids+1]=id end end
    if value then
        ids[#ids+1]=self.profile_id
        if self.profile.enabled==false then self.profile.enabled=true;self:profile_changed() end
    end
    table.sort(ids)
    self.active_profiles=ids;self.draft.apiProfiles=clone(ids);self.draft.apiPoolEnabled=true;self.dirty=true
end
function SettingsScreen:new_profile()
    local index=1;while settings.get_snapshot().profiles['profile-'..index] or self.profiles['profile-'..index] do index=index+1 end
    self.profile_id='profile-'..index
    self.profile={label='API '..index,enabled=true,kind='Custom_OpenAI',baseUrl='',model='',concurrency=2}
    self.profiles[self.profile_id]=self.profile
    self:set_participating(true);self:refresh_fields();self:profile_changed()
end
function SettingsScreen:profile_updates()
    local values={}
    for id in pairs(self.profile_dirty_ids) do
        local value=clone(self.profiles[id]);value.id=id;value.hasKey=nil
        values[#values+1]=value
    end
    table.sort(values,function(a,b) return a.id<b.id end)
    return values
end
function SettingsScreen:apply(reset,on_complete)
    if not reset then
        local value=tonumber(self.subviews.apiConcurrency.text)
        if not value or value~=math.floor(value) or value<1 or value>16 then self.message='API 並行數須為 1-16';return false end
    end
    for key,limits in pairs({concurrency={1,32},timeoutMs={1000,120000},maxRetries={0,5},retryBaseMs={100,30000}}) do
        local value=tonumber(self.subviews[key].text)
        if not reset and (not value or value~=math.floor(value) or value<limits[1] or value>limits[2]) then
            self.message='數值超出允許範圍';return false
        end
        self.draft[key]=value
    end
    for _,profile in ipairs(reset and {} or self:profile_updates()) do
        local value=profile.concurrency or 2
        if not value or value~=math.floor(value) or value<1 or value>16 then self.message='API 並行數須為 1-16';return false end
    end
    local previous_language=runtime.language()
    local values=reset and {} or clone(self.draft)
    if self.scope=='save' and not reset then
        local global=settings.effective('global')
        local function equal(a,b)
            if type(a)~='table' or type(b)~='table' then return a==b end
            if #a~=#b then return false end
            for i,id in ipairs(a) do if b[i]~=id then return false end end
            return true
        end
        for key,value in pairs(values) do if equal(value,global[key]) then values[key]=nil end end
    end
    local request={action='save',scope=self.scope,
        reset=reset==true or self.scope=='save',profiles=reset and {} or self:profile_updates()}
    if not reset then
        local deleted=self:deleted_profile_ids()
        if #deleted>0 then request.deleteProfiles=deleted end
    end
    if next(values) then request.settings=values end
    local ok,error=settings.submit(request,function(result)
        if not self:isActive() then return end
        self.message=result.ok and '設定已套用' or result.error
        if result.ok then
            if previous_language~=runtime.language() then
                local page,scope=self.page,self.scope
                self:dismiss()
                screen=SettingsScreen{scope_override=scope}
                screen.page=page;screen.subviews.pages:setSelected(page)
                screen.message='設定已套用';screen:show()
            else self:load_draft();self:refresh_fields() end
        end
        if on_complete then on_complete(result,screen or self) end
    end)
    self.message=ok and '儲存中' or error
    return ok,error
end
function SettingsScreen:test_connection(on_complete)
    local profile=clone(self.profile);profile.id=self.profile_id;profile.enabled=true;profile.hasKey=nil
    local ok,error=settings.submit({action='test',profile=profile},function(result)
        if self:isActive() then self.message=result.ok and '連線成功' or result.error end
        if on_complete then on_complete(result) end
    end)
    self.message=ok and '連線測試中' or error
    return ok,error
end
function SettingsScreen:onDismiss()
    for _,profile in pairs(self.profiles) do profile.key=nil end
    self.subviews.api_key.value=nil;self.subviews.api_key.selected=false
end

function show()
    if screen and screen:isActive() then screen:raise();return screen end
    screen=SettingsScreen{};screen:show();return screen
end
SettingsEntry=defclass(SettingsEntry,overlay.OverlayWidget)
SettingsEntry.ATTRS{desc='模組設定',default_enabled=true,viewscreens={'title','dwarfmode'},
    default_pos={x=-27,y=-5},frame={w=25,h=2},
    visible=function() return df.global.game.main_interface.settings.open end}
function SettingsEntry:onRenderBody()
    local rect=self.frame_body
    paint(rect.x1,rect.y1,'模組設定',COLOR_LIGHTGREEN,rect.x2-rect.x1+1)
end
function SettingsEntry:onInput(keys)
    if keys.CUSTOM_CTRL_M or keys._MOUSE_L and self:getMousePos() then show();return true end
end
OVERLAY_WIDGETS={settings=SettingsEntry}
if not dfhack_flags.module then show() end
