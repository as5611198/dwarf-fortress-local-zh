--@module = true
-- Redirect legacy startup references to the owned core; never attach both engines.
if not dfhack_flags.module then reqscript('df-local-zh-core').start() end
