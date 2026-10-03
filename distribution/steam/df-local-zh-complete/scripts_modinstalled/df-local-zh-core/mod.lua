--@module = true

-- load module scripts
helpers = reqscript('df-local-zh-core/helpers')
native = reqscript('df-local-zh-core/native')

-- load configuration scripts
local functions = reqscript('df-local-zh-core/functions')
local globals = reqscript('df-local-zh-core/globals')

-- collect MOD information
ID = helpers.MOD_INFO.ID
NUMERIC_VERSION = helpers.MOD_INFO.NUMERIC_VERSION
DISPLAYED_VERSION = helpers.MOD_INFO.DISPLAYED_VERSION

-- print a MOD-related message
function p(...)
  print("df-local-zh-core " .. string.format(...))
end

-- print a MOD-related error message
function e(...)
  dfhack.printerr("df-local-zh-core: " .. string.format(...))
end

-- check if a path is a directory, print an error message if not
local function is_dir(path, err)
  local ok = dfhack.filesystem.isdir(path)
  if not ok then
    e("%s - \"%s\" is not a directory", err, path)
  end
  return ok
end

-- find directories from a directory
local function find_dirs(dir)
  local dirs = {}
  for _, lang_tag in ipairs(dfhack.filesystem.listdir(dir)) do
    local dir = dir .. '/' .. lang_tag
    if dfhack.filesystem.isdir(dir) then
      table.insert(dirs, lang_tag)
    end
  end
  return dirs
end

-- find files matching a pattern from a directory
local function find_files(dir, exts)
  -- convert to table if a string is given
  if type(exts) == 'string' then
    exts = {exts}
  end

  local files = {}
  for _, file in ipairs(dfhack.filesystem.listdir(dir)) do
    for _, ext in ipairs(exts) do
      if file:match('%.' .. ext .. '$') then
        local file = dir .. '/' .. file
        if dfhack.filesystem.isfile(file) then
          table.insert(files, file)
        end
      end
    end
  end
  table.sort(files)
  return files
end

-- first loaded language tag for fonts
local first_lang_tag = nil

-- change the current language tag
function change_lang_tag(new_lang_tag)
  if type(new_lang_tag) ~= 'string' then
    e("language tag must be a string")
    return
  end

  native.set_lang_tag(new_lang_tag)
end

-- load font files from a directory
local function load_font(dir)
  p("is searching for font files from \"%s\"...", dir)
  for _, lang_tag in ipairs(find_dirs(dir)) do
    local lang_dir = dir .. '/' .. lang_tag
    p("is searching for \"%s\" font from: \"%s\"...", lang_tag, lang_dir)
    local font_files=find_files(lang_dir,'otf')
    table.sort(font_files)
    for _, file in ipairs(font_files) do
      p("is loading \"%s\" font from: \"%s\"...", lang_tag, file)
      native.add_font(lang_tag, file)
      -- set the first loaded language tag as the default language tag
      if not first_lang_tag then
        first_lang_tag = lang_tag
        change_lang_tag(lang_tag)
      end
    end
    -- Optional OS fonts remain on the player's PC and are never redistributed.
    local windows=os.getenv('WINDIR')
    if windows then
      for _,name in ipairs({'mingliub.ttc','msjh.ttc'}) do
        local fallback=windows..'/Fonts/'..name
        local file=io.open(fallback,'rb')
        if file then file:close();native.add_font(lang_tag,fallback) end
      end
    end
  end
end

-- load logo images from a directory
local function load_logo(dir)
  p("is searching for logo images from \"%s\"...", dir)
  for _, file in ipairs(find_files(dir, 'png')) do
    local lang_tag = file:match('([^/]+)%.png$')
    p("is loading logo image for language tag \"%s\" from: \"%s\"...", lang_tag, file)
    native.load_title_logo(lang_tag, file)
  end
end

-- load simple dictionary data from a directory
local function load_simple_dict_data(dir)
  p("is searching for simple translator data from \"%s\"...", dir)
  -- TODO: remove legacy merged CSV support in future versions
  for _, file in ipairs(find_files(dir, 'csv')) do
    local lang_tag = file:match('([^/]+)%.csv$')
    p("is loading simple translator data for language tag \"%s\" from: \"%s\"...", lang_tag, file)
    local ok, err = native.load_simple_dict(lang_tag, file)
    if not ok then error(err) end
  end
  for _, lang_tag in ipairs(find_dirs(dir)) do
    local lang_dir = dir .. '/' .. lang_tag
    p("is loading simple translator data for language tag \"%s\" from: \"%s\"...", lang_tag, lang_dir)
    for _, file in ipairs(find_files(lang_dir, 'csv')) do
      local ok, err = native.load_simple_dict(lang_tag, file)
      if not ok then error(err) end
    end
  end
end

-- load translation rulesets data from a directory
local function load_translation_rulesets_data(dir)
  p("is searching for rulesets translator data from \"%s\"...", dir)
  for _, lang_tag in ipairs(find_dirs(dir)) do
    local lang_dir = dir .. '/' .. lang_tag
    p("is loading rulesets translator data for language tag \"%s\" from: \"%s\"...", lang_tag, lang_dir)
    local ok, err = native.load_translation_rulesets(lang_tag, lang_dir)
    if not ok then error(err) end
  end
end

-- load translator data from a directory
local function load_data(type, dir)
  if type == 'simple' then
    load_simple_dict_data(dir)
  elseif type == 'rulesets' then
    load_translation_rulesets_data(dir)
  else
    e("unknown translator data type \"%s\" for directory \"%s\"", type, dir)
  end
end

-- setup the MOD
function setup()
  -- setup the MOD
  native.runtime_worker_threads_set(2)
  native.setup()

  -- add memory regions
  for i, mem in ipairs(dfhack.internal.getMemRanges()) do
    if mem.read and mem.execute and (string.match(mem.name, '%bDwarf Fortress%.exe$') or mem.name:match('[\\/]dfhack%.dll$') or mem.name:match('[\\/]ucrtbase%.dll$') or mem.name:match('[\\/]vcruntime140%.dll$') or mem.name:match('[\\/]SDL2%.dll$') or string.match(mem.name, '%bdfhooks_dfhack%.dll$') or string.match(mem.name, '%bdwarfort$') or string.match(mem.name, '%blibg_src_lib%.so$') or string.match(mem.name, '%blibdfhack%.so$')) then
      native.add_memory_region(mem.name, mem.base_addr or 0, mem.start_addr, mem.end_addr)
    end
  end

  -- add memory searches
  local functions = (native.OS == "windows") and functions.WINDOWS_MEMORY_SEARCH or functions.LINUX_MEMORY_SEARCH
  for _, entry in ipairs(functions) do
    native.add_memory_search(entry[1], entry[2], entry[3], entry[4])
  end

  -- setup global variable or field offsets
  local globals = globals.GLOBALS
  for _, stmt in ipairs(globals) do
    native.setup_globals(stmt)
  end
end

-- load MOD data
function load()
  p("is loading data...")

  -- for each MOD data directory path
  for _, data_path in ipairs(helpers.data_paths()) do
    -- for each MOD data information
    for _, data_info in ipairs(helpers.parse_data_file(data_path)) do
      if data_info.key == 'FONT' then
        local value = data_info.value
        local dir = data_info.dir .. '/' .. value
        if not is_dir(dir, "failed to load fonts") then
          goto next
        end

        load_font(dir)
      elseif data_info.key == 'LOGO' then
        local value = data_info.value
        local dir = data_info.dir .. '/' .. value
        if not is_dir(dir, "failed to load fonts") then
          goto next
        end

        load_logo(dir)
      elseif data_info.key == 'DATA' then
        local _, _, type, value = data_info.value:find('^([^:]+):(.*)$')
        local dir = data_info.dir .. '/' .. value
        if not is_dir(dir, string.format("failed to load %s translator data", type)) then
          goto next
        end

        load_data(type, dir)
      else
        e("unknown data file entry key \"%s\" in data path \"%s\"", data_info.key, data_info.dir)
      end

      ::next::
    end
  end

  p("has loaded data.")
end

-- initialize the MOD
function init()
  return native.init(native.OS, native.DF_PLATFORM, native.DF_VERSION, DISPLAYED_VERSION)
end

-- reload the MOD data
-- TODO: fix the rendering issues after reload
function reload()
  e('Native core changes require a normal game restart.')
  return false
end

-- enable the MOD
function enable()
  native.enable()
end

-- disable the MOD
function disable()
  native.disable()
end

-- toggle the MOD between enabled and disabled
function toggle()
  native.toggle()
end

-- translate content synchronously
function sync_translate(content)
  if type(content) ~= 'string' then
    e("content to translate must be a string")
    return nil
  end

  return native.sync_translate(content)
end

-- translate content asynchronously (returns nil if translation is not ready)
function async_translate(content)
  if type(content) ~= 'string' then
    e("content to translate must be a string")
    return nil
  end

  return native.async_translate(content)
end

-- setup hooks on DFHack
local last_vs = nil
function setup_hooks()
  -- hook viewscreen change to set view screen
  dfhack.onStateChange.df_local_zh_core = function(sc)
    if sc == SC_WORLD_LOADED or sc == SC_WORLD_UNLOADED then
      native.native_set_world(dfhack.isWorldLoaded() and dfhack.getSavePath() or '')
    end
    if sc ~= SC_VIEWSCREEN_CHANGED and sc ~= SC_WORLD_LOADED then
      return
    end

    local vss = ''
    local vs = df.global.gview.view
    while vs ~= nil do
      vss = vss .. '::' .. tostring(dfhack.gui.getFocusStrings(vs)[1])
      vs = vs.child
    end

    if vss == last_vs then
      return
    end

    native.set_view_screen(vss)
    last_vs = vss
  end

  -- hook on Tab label rendering
  local TabBar = require('gui.widgets.tab_bar')
  local Tab = TabBar.Tab
  local call_onRenderBody = Tab.onRenderBody
  Tab.onRenderBody = function(self, dc)
    if not dfhack.screen.inGraphicsMode() then
      call_onRenderBody(self, dc)
      return
    end

    local pen = self.get_pens().t

    local x = dc.x + 2 -- skip left border
    local y = dc.y
    local fg = pen.fg
    local bg = pen.bg
    local bold = pen.bold and 1 or 0
    local content = self.label
    local flag = pen.top_of_text and 8 or 0 -- TOP_OF_TEXT = 8

    call_onRenderBody(self, dc)

    if native.is_enabled() then
      native.dfhack_addstr_flag(x, y, fg, bg, bold, content, flag)
    end
  end
end

function get_cloud_status() return native.cloud_get_status() end
function set_cloud_enabled(value)
  if value then native.cloud_enable() else native.cloud_disable() end
  return native.cloud_get_status()
end
function get_developer_mode() return native.developer_mode_get_status() end
function set_developer_mode(value)
  if value then native.developer_mode_enable() else native.developer_mode_disable() end
  return native.developer_mode_get_status()
end
function get_worker_threads() return native.runtime_worker_threads_get() end
function set_worker_threads(value) return native.runtime_worker_threads_set(tonumber(value) or 2) end
function get_persistent_cache() return native.persistent_cache_get_status() end
function set_persistent_cache(value)
  if value then native.persistent_cache_enable() else native.persistent_cache_disable() end
  return native.persistent_cache_get_status()
end
function clear_persistent_cache() return native.persistent_cache_clear() end
function set_cloud_endpoint(value) return native.cloud_set_endpoint(value) end

function start()
  if started then return true end
  if starting then error('Recursive native core initialization') end
  starting = true
  prepare()
  native.set_lang_tag('zh-Hant')
  native.native_set_world(dfhack.isWorldLoaded() and dfhack.getSavePath() or '')
  native.set_view_screen(table.concat(dfhack.gui.getFocusStrings(dfhack.gui.getCurViewscreen()), '::'))
  local ok, err = init()
  if not ok then starting = false; error(err or 'Native hook initialization failed') end
  setup_hooks()
  enable()
  started = true
  starting = false
  p('enabled; workers=%d; dictionary and completed cache are synchronous', get_worker_threads())
  return true
end

function prepare()
  if prepared then return true end
  setup()
  load()
  prepared = true
  return true
end
