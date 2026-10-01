--@module = true

local scriptmanager = require("script-manager")
local utils = require('utils')

-- the MOD ID
MOD_ID = "df-local-zh-complete"

-- MOD data directory
DATA_DIR = string.format("%s-data/", MOD_ID)

-- the MOD source path
MOD_SOURCE_PATH = assert(scriptmanager.getModSourcePath(MOD_ID), 'Own localization package is missing')
MOD_INFO = scriptmanager.get_mod_info_metadata(MOD_SOURCE_PATH, {'ID', 'NUMERIC_VERSION', 'DISPLAYED_VERSION'})

-- evaluate an expression in a safe environment
local eval_env = utils.df_shortcut_env()
function eval(s)
  local f, err = load('return ' .. s, 'expression', 't', eval_env)
  if err then
    qerror(err)
  end
  return f()
end

-- get all MOD data directory paths from different MODs
function data_paths()
  return {MOD_SOURCE_PATH .. 'dfi18n-data'}
end

-- parse a MOD data file into a table of key-value pairs
function parse_data_file(data_path)
  local data_file = data_path .. '/dfi18n.txt'
  local data = {}
  local ok, lines = pcall(io.lines, data_file)
  if ok then
    for line in lines do
      local _, _, key, value = line:find('^%[([^:]+):(.*)%]$')
      if key and value then
        table.insert(data, {
          key = key,
          value = value,
          dir = data_path
        })
      end
    end
  end
  return data
end
