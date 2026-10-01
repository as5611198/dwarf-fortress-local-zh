use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};

use crate::{glyph, markup, text, translator};

// Atomic flag to enable the MOD on the end of the current frame
static ENABLING: OnceLock<AtomicBool> = OnceLock::new();

// Getting the enabling flag
fn enabling() -> &'static AtomicBool {
  ENABLING.get_or_init(|| AtomicBool::new(false))
}

// Atomic flag to disable the MOD on the end of the current frame
static DISABLING: OnceLock<AtomicBool> = OnceLock::new();

// Getting the disabling flag
fn disabling() -> &'static AtomicBool {
  DISABLING.get_or_init(|| AtomicBool::new(false))
}

// Atomic flag to indicate if the MOD is enabled
static ENABLED: OnceLock<AtomicBool> = OnceLock::new();

// Temporary render scope for UI values that are already in their final form.
// A depth counter keeps nested widget rendering balanced.
static INTERCEPTION_BYPASS: OnceLock<AtomicUsize> = OnceLock::new();

fn interception_bypass() -> &'static AtomicUsize {
  INTERCEPTION_BYPASS.get_or_init(|| AtomicUsize::new(0))
}

pub fn is_interception_bypassed() -> bool {
  interception_bypass().load(Ordering::SeqCst) > 0
}

#[unsafe(no_mangle)]
extern "C" fn interception_bypass_enable() -> i32 {
  interception_bypass().fetch_add(1, Ordering::SeqCst);
  0
}

#[unsafe(no_mangle)]
extern "C" fn interception_bypass_disable() -> i32 {
  let mut current = interception_bypass().load(Ordering::SeqCst);
  while current > 0 {
    match interception_bypass().compare_exchange(current, current - 1,
        Ordering::SeqCst, Ordering::SeqCst) {
      Ok(_) => break,
      Err(next) => current = next,
    }
  }
  0
}

// Getting the enabled state
fn enabled() -> &'static AtomicBool {
  ENABLED.get_or_init(|| AtomicBool::new(false))
}

// Enable hooks to show translated text
#[unsafe(no_mangle)]
extern "C" fn enable() -> i32 {
  enabling().store(true, std::sync::atomic::Ordering::SeqCst);
  0
}

// Disable hooks to show original text
#[unsafe(no_mangle)]
extern "C" fn disable() -> i32 {
  disabling().store(true, std::sync::atomic::Ordering::SeqCst);
  0
}

// Toggle hooks based on current state
#[unsafe(no_mangle)]
extern "C" fn toggle() -> i32 {
  if is_enabled() {
    disable();
  } else {
    enable();
  }
  0
}

// Check if MOD is enabled
pub fn is_enabled() -> bool {
  enabled().load(std::sync::atomic::Ordering::SeqCst)
}

#[unsafe(export_name = "is_enabled")]
extern "C" fn lua_is_enabled(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_boolean(state, is_enabled());
  1
}

// Toggle hooks based on enabling/disabling flags
pub fn toggle_enabled() {
  if enabling().load(std::sync::atomic::Ordering::SeqCst) {
    set_enabled(true);
    log::info!("Hooks enabled");
  }

  if disabling().load(std::sync::atomic::Ordering::SeqCst) {
    set_enabled(false);
    log::info!("Hooks disabled");
  }
}

// Set enabled state and reset flags
fn set_enabled(state: bool) {
  enabling().store(false, std::sync::atomic::Ordering::SeqCst);
  disabling().store(false, std::sync::atomic::Ordering::SeqCst);
  enabled().store(state, std::sync::atomic::Ordering::SeqCst);
}

// Atomic flag to reset the MOD on the end of the current frame
static RESETTING: OnceLock<AtomicBool> = OnceLock::new();

// Getting the resetting flag
fn resetting() -> &'static AtomicBool {
  RESETTING.get_or_init(|| AtomicBool::new(false))
}

// Reset the MOD
#[unsafe(no_mangle)]
extern "C" fn reset(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_boolean(state, false);
  lua53_sys::push_string(state, "Attached native renderers cannot be reset; restart the game to change the core.");
  2
}

// Perform the reset if requested
pub fn do_reset_if_requested() {
  if resetting().load(std::sync::atomic::Ordering::SeqCst) {
    resetting().store(false, std::sync::atomic::Ordering::SeqCst);

    glyph::reset();
    translator::reset();
    text::reset();
    markup::reset();

    log::info!("MOD state reset");
  }
}
