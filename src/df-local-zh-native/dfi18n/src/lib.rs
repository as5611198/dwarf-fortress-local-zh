#![feature(macro_metavar_expr_concat)]

mod backtrace;
mod cjk;
mod chinese;
mod control;
mod df;
mod game;
mod glyph;
mod hooks;
mod lang;
mod logger;
mod logging;
mod logo;
mod markup;
mod memory;
mod native_cache;
mod display_rows;
mod prewarm;
mod official;
mod broker_client;
mod screen;
mod search;
mod search_text;
mod search_input;
mod tasks;
mod text;
mod translation;
mod translator;
mod types;

use lua53_sys as lua;

pub use backtrace::backtrace;

// The Translation MOD name
pub const MOD_NAME: &str = "df_local_zh_core";
// The directory to store data files and logs
pub const DATA_DIRECTORY: &str = "df-local-zh-core-data";

// Setup the MOD
#[unsafe(no_mangle)]
extern "C" fn setup() -> i32 {
  logger::setup();
  tasks::setup();
  rule_based_translator::register_default_replacers();
  native_cache::setup();
  chinese::setup();
  official::setup();
  0
}

#[unsafe(no_mangle)]
extern "C" fn core_validate_hooks(state: *mut std::ffi::c_void) -> i32 {
  match memory::run_searches() {
    Ok(()) => { lua::push_boolean(state, true); lua::push_nil(state); }
    Err(error) => { lua::push_boolean(state, false); lua::push_string(state, &error.to_string()); }
  }
  2
}

// Initialize the MOD from Lua and setup hooks for the game
#[unsafe(no_mangle)]
extern "C" fn init(lua_state: *mut std::ffi::c_void) -> i32 {
  let os = lua::check_string(lua_state, 1);
  let platform = lua::check_string(lua_state, 2);
  let version = lua::check_string(lua_state, 3);
  let mod_version = lua::check_string(lua_state, 4);
  game::set_game_info(os, platform, version, mod_version);

  log::info!("Initializing...");
  log::info!("Game version: {}", game::version());
  log::info!("Game platform: {}", game::os_platform());
  log::info!("MOD version: {}", game::mod_version());

  if let Err(err) = memory::run_searches() {
    log::error!("failed to run memory searches: {}", err);
    lua::push_boolean(lua_state, false); lua::push_string(lua_state, &err.to_string());
    return 2;
  }

  if logger::level() <= flexi_logger::LevelFilter::Debug {
    log::debug!("Pointers:");
    for (key, (file_offset, memory_address)) in memory::pointers().iter() {
      log::debug!(
        "pointer {key} at [{}:0x{:08x}] 0x{memory_address:08x}",
        file_offset.0,
        file_offset.1
      );
    }
  }

  if let Err(err) = hooks::attach_all() {
    log::error!("failed to attach hooks: {}", err);
    lua::push_boolean(lua_state, false); lua::push_string(lua_state, &err.to_string());
    return 2;
  }
  lua::push_boolean(lua_state, true); lua::push_nil(lua_state);
  2
}

// XXX: debug function for testing
#[unsafe(no_mangle)]
extern "C" fn debug(lua_state: *mut std::ffi::c_void) -> i32 {
  let str = lua::check_string(lua_state, 1);
  let num = lua::check_integer(lua_state, 2);
  log::warn!("Debug function called with str={str} num={num}");
  lua::push_string(lua_state, "bar");
  lua::push_integer(lua_state, num + 1);
  lua::push_boolean(lua_state, true);
  lua::push_boolean(lua_state, false);
  return 4;
}
