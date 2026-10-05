use std::sync::OnceLock;

// Get mutable help struct
pub fn get_help_mut() -> &'static mut Help {
  unsafe { (*GAME_MAIN_INTERFACE_HELP.get().unwrap() as *mut Help).as_mut_unchecked() }
}

// game.main_interface.help
static GAME_MAIN_INTERFACE_HELP: OnceLock<usize> = OnceLock::new();

// DFHack resolves this one-byte field in the process-lifetime global game
// interface. No widget pointer is retained and no game data is written.
static SQUAD_SCHEDULE_OPEN: OnceLock<usize> = OnceLock::new();
pub(crate) fn squad_schedule_open() -> bool {
  SQUAD_SCHEDULE_OPEN.get().is_some_and(|address|
    unsafe { std::ptr::read_volatile(*address as *const u8) == 1 })
}
#[unsafe(no_mangle)]
extern "C" fn set_game_main_interface_squad_schedule_open(state: *mut std::ffi::c_void) -> i32 {
  let address=lua53_sys::check_integer(state,1) as usize;
  assert_ne!(address,0,"Missing native squad schedule flag");
  let registered=SQUAD_SCHEDULE_OPEN.get_or_init(||address);
  assert_eq!(*registered,address,"Native squad schedule flag address changed");
  0
}

// Set game.main_interface.help from Lua
#[unsafe(no_mangle)]
extern "C" fn set_game_main_interface_help(lua_state: *mut std::ffi::c_void) -> i32 {
  let addr = lua53_sys::check_integer(lua_state, 1) as usize;
  GAME_MAIN_INTERFACE_HELP.set(addr).unwrap();
  0
}

#[repr(C)]
pub struct Help {
  pub open: bool,
  pub flag: u32,
  pub context_flag: u32,
  pub context: u32,
  pub header: [u8; 32],
  pub text: [super::MarkupTextBox; 20],
}
