mod string;
pub use string::*;

mod vector;
pub use vector::*;

unsafe extern "C-unwind" {
  pub fn notify_search_textbox(widget: *mut std::ffi::c_void, callback: *mut std::ffi::c_void) -> bool;
}
