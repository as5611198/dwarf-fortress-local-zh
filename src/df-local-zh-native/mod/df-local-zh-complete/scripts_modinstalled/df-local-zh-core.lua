--@module = true
local mod = reqscript('df-local-zh-core/mod')
function start() return mod.start() end
if not dfhack_flags.module then start() end
