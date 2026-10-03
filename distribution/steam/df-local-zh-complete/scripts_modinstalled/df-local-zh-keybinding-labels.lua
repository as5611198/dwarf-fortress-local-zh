--@module=true

-- Protect only the game's binding-name fields, not action descriptions or a
-- global list of words. Read public DFHack structures; never edit bindings.
local native = reqscript('df-local-zh-core/native')
local json = require('json')
local repeatutil = require('repeat-util')
local watch_name = 'df-local-zh-keybinding-labels'
local active = false

function collect(settings)
    local rows = {}
    if not settings or not settings.open or
        settings.current_mode ~= df.settings_tab_type.KEYBINDINGS then return rows end
    local bindings = settings.keybinding_binding_name[settings.keybinding_selected_category]
    if not bindings then return rows end
    for _, label in ipairs(bindings) do
        local source = label.value
        if #source > 0 and #source <= 1000 and not source:find('[^ -~]') then
            local _, address = df.sizeof(label)
            rows[#rows+1] = {address=address, source=source,
                translation=source, width=#source}
        end
    end
    return rows
end

function refresh()
    local ok, rows = pcall(collect, df.global.game.main_interface.settings)
    if not ok then rows = {} end
    if #rows > 0 or active then
        local accepted = native.native_literal_rows_set(json.encode(rows))
        active = accepted and #rows > 0
        return accepted
    end
    return true
end

function start()
    repeatutil.scheduleUnlessAlreadyScheduled(watch_name, 4, 'frames', refresh)
end

function stop()
    repeatutil.cancel(watch_name)
    native.native_literal_rows_set('[]')
    active = false
end

-- repeat-util clears its registry at unload. Reinstall after every transition
-- so keybindings work both at the title screen and inside a loaded world.
dfhack.onStateChange.df_local_zh_keybinding_labels = function()
    dfhack.timeout(1, 'frames', start)
end
