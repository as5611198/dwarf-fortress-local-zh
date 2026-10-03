-- Initialize the owned native core before any adapters can draw translated keys.
reqscript('df-local-zh-core').start()

-- Apply the local language preference after the core changes views.
local function apply()
    local ok, mod = pcall(reqscript, 'df-local-zh-settings')
    if not ok then return end
    mod.apply_native()
end

local paths = reqscript('df-local-zh-paths')
local fortress_data_loaded=false
local broker_started=false
local adapters_started=false
local development_hidden=false

local function load_fortress_data()
    if fortress_data_loaded then return end
    local ok,native=pcall(reqscript,'df-local-zh-core/native')
    if not ok then return end
    local root=paths.broker_source()..'/data/'
    native.load_simple_dict('zh-Hant',root..'fortress-ui.csv')
    native.load_translation_rulesets('zh-Hant',root..'announcement-rules')
    native.load_simple_dict('zh-Hans',root..'fortress-ui-zh-Hans.csv')
    native.load_translation_rulesets('zh-Hans',root..'announcement-rules-zh-Hans')
    fortress_data_loaded=true
end

local function hide_development_overlays()
    if development_hidden then return end
    -- These status panels are useful while developing DFHack mods, but their
    -- labels are not part of the game's localization surface.
    for _, name in ipairs({'overlay.title_version', 'dfi18n-overlay.cloud_toggle'}) do
        pcall(dfhack.run_command, 'overlay', 'disable', name)
    end
    development_hidden=true
end

local function start_broker()
    if broker_started then return end
    local path = paths.broker_source() .. '/df-broker-launch.dll'
    local start, err = package.loadlib(path, 'start_broker')
    if not start then dfhack.printerr(tostring(err)); return end
    start()
    broker_started=true
end

local function start_runtime()
    local ok, runtime = pcall(reqscript, 'df-local-zh-runtime')
    if not ok then dfhack.printerr(tostring(runtime)); return end
    runtime.start()
end

local function start_reports()
    local ok, reports = pcall(reqscript, 'df-local-zh-reports')
    if not ok then dfhack.printerr(tostring(reports)); return end
    reports.start()
end

local function start_text_overlay()
    local ok, overlay = pcall(reqscript, 'df-local-zh-text-overlay')
    if not ok then dfhack.printerr(tostring(overlay)); return end
end

local function start_legends_filter()
    local ok, err = pcall(reqscript, 'df-local-zh-legends-filter')
    if not ok then dfhack.printerr(tostring(err)) end
end

local function start_embark_overlay()
    local ok, err = pcall(reqscript, 'df-local-zh-embark')
    if not ok then dfhack.printerr(tostring(err)) end
end

local function start_title_overlay()
    local ok, err = pcall(reqscript, 'df-local-zh-title-overlay')
    if not ok then dfhack.printerr(tostring(err)) end
end

local function start_status_ui()
    local ok,err=pcall(reqscript,'df-local-zh-status-ui')
    if not ok then dfhack.printerr(tostring(err)) end
    pcall(dfhack.run_command,'overlay','enable','df-local-zh-status-ui.status')
end

local function start_search()
    local ok,err=pcall(reqscript,'df-local-zh-search')
    if not ok then dfhack.printerr(tostring(err));return end
    pcall(dfhack.run_command,'overlay','enable','df-local-zh-search.search')
end

local function start_settings()
    local ok,err=pcall(reqscript,'df-local-zh-settings-ui')
    if not ok then dfhack.printerr(tostring(err));return end
    pcall(dfhack.run_command,'overlay','enable','df-local-zh-settings-ui.settings')
end

local function start_keybinding_labels()
    local ok, adapter = pcall(reqscript, 'df-local-zh-keybinding-labels')
    if not ok then dfhack.printerr(tostring(adapter));return end
    adapter.start()
end

local function start_extended_readers()
    for _,entry in ipairs({{'df-local-zh-history','history'},{'df-local-zh-adventure','adventure'}}) do
        local ok,err=pcall(reqscript,entry[1])
        if ok then pcall(dfhack.run_command,'overlay','enable',entry[1]..'.'..entry[2])
        else dfhack.printerr(tostring(err)) end
    end
end

local function disable_english_legends_filter()
    if dfhack.isWorldLoaded() and require('plugins.overlay').isOverlayEnabled('exportlegends.histfigfilter') then
        pcall(dfhack.run_command, 'overlay disable exportlegends.histfigfilter')
    end
end

local last_export
local function export_names()
    if dfhack.isWorldLoaded() and #df.global.world.history.figures > 0 then
        local stamp = dfhack.getSavePath() .. ':' .. #df.global.world.history.figures
        if stamp == last_export then return end
        local ok, err = pcall(dfhack.run_script, 'df-local-zh-names')
        if not ok then dfhack.printerr(tostring(err)) end
        if ok then last_export = stamp end
    end
end

dfhack.onStateChange.df_local_zh = function(code)
    if code == SC_CORE_INITIALIZED or code == SC_VIEWSCREEN_CHANGED or code == SC_WORLD_LOADED then
        if code~=SC_VIEWSCREEN_CHANGED then apply() end
        if not adapters_started then
        hide_development_overlays()
        load_fortress_data()
        start_broker()
        start_runtime()
        start_reports()
        start_text_overlay()
        start_legends_filter()
        start_embark_overlay()
        start_title_overlay()
        start_status_ui()
        start_search()
        start_settings()
        start_keybinding_labels()
        start_extended_readers()
        adapters_started=true
        end
        disable_english_legends_filter()
    end
    if code == SC_WORLD_LOADED or code == SC_VIEWSCREEN_CHANGED then
        export_names()
        dfhack.timeout(1, 'frames', export_names)
    end
    if code == SC_WORLD_UNLOADED then last_export = nil;apply() end
end

start_broker()
export_names()
hide_development_overlays()
apply()
load_fortress_data()
start_runtime()
start_reports()
start_text_overlay()
start_embark_overlay()
start_title_overlay()
start_status_ui()
start_search()
start_settings()
start_keybinding_labels()
start_extended_readers()
adapters_started=true
