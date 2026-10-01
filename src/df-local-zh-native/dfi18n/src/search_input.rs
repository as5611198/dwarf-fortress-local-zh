use std::collections::VecDeque;
use std::ffi::{c_char,c_void,CStr};
use std::sync::{Mutex,OnceLock};
use std::sync::atomic::{AtomicBool,Ordering};


#[repr(C,align(8))]
#[derive(Clone,Copy)]
struct Event { bytes: [u8;56] }
impl Event {
  fn number(&self,offset: usize) -> u32 { u32::from_ne_bytes(self.bytes[offset..offset+4].try_into().unwrap()) }
  fn set(&mut self,offset: usize,value: u32) { self.bytes[offset..offset+4].copy_from_slice(&value.to_ne_bytes()); }
}
#[repr(C)]
struct Rect { x: i32,y: i32,w: i32,h: i32 }
#[cfg_attr(windows,link(name="SDL2",kind="raw-dylib"))]
unsafe extern "C" {
  fn SDL_StartTextInput();
  fn SDL_StopTextInput();
  fn SDL_IsTextInputActive() -> i32;
  fn SDL_SetTextInputRect(rect: *const Rect);
  fn SDL_GetClipboardText() -> *mut c_char;
  fn SDL_free(memory: *mut c_void);
  fn SDL_PushEvent(event: *mut Event) -> i32;
  fn SDL_GetWindowSize(window: *mut c_void,w: *mut i32,h: *mut i32);
}
#[derive(serde::Serialize)]
struct Action { kind: &'static str,text: String }
static ACTIVE: AtomicBool=AtomicBool::new(false);
static PREVIOUS: AtomicBool=AtomicBool::new(false);
static ACTIONS: OnceLock<Mutex<VecDeque<Action>>>=OnceLock::new();
fn actions() -> &'static Mutex<VecDeque<Action>> { ACTIONS.get_or_init(|| Mutex::new(VecDeque::new())) }
fn push(kind: &'static str,text: String) {
  let mut actions=actions().lock().unwrap();
  if actions.len()<256 && text.len()<=4096 { actions.push_back(Action {kind,text}); }
}
fn text(event: &Event) -> Option<String> {
  let bytes=&event.bytes[12..44];
  std::str::from_utf8(&bytes[..bytes.iter().position(|b| *b==0).unwrap_or(32)]).ok().map(str::to_owned)
}
fn capture(event: &Event) -> bool {
  match event.number(0) {
    0x303 => { if let Some(text)=text(event) { push("text",text); } true },
    0x302 => { if let Some(text)=text(event) { push("composition",text); } true },
    0x300 | 0x301 => {
      let key=event.number(20);
      let mods=u16::from_ne_bytes(event.bytes[24..26].try_into().unwrap());
      let ctrl=mods & 0x0cc0 != 0;
      let action=match key {
        8 => Some("backspace"),127 => Some("delete"),
        1073741904 => Some("left"),1073741903 => Some("right"),
        1073741898 => Some("home"),1073741901 => Some("end"),
        97 if ctrl => Some("select_all"),118 if ctrl => Some("paste"),
        _ => None,
      };
      if event.number(0)==0x300 {
        if action==Some("paste") {
          let pointer=unsafe { SDL_GetClipboardText() };
          if !pointer.is_null() {
            let text=unsafe { CStr::from_ptr(pointer) }.to_string_lossy().into_owned();
            unsafe { SDL_free(pointer as *mut c_void) };push("text",text);
          }
        } else if let Some(action)=action { push(action,String::new()); }
      }
      action.is_some() || ((32..127).contains(&key) && !ctrl)
    },
    _ => false,
  }
}
fn search_poll_event(event: *mut Event) -> i32 {
  loop {
    let result=call_search_poll_event(event);
    if result==0 || event.is_null() || !ACTIVE.load(Ordering::Relaxed) { return result; }
    if !capture(unsafe { &*event }) { return result; }
  }
}
macros::hook! { fn search_poll_event(event: *mut Event) -> i32; }
pub fn attach() -> anyhow::Result<()> {
  #[cfg(windows)]
  attach_search_poll_event(crate::memory::get_raw_pointer_by_key("search_poll_event")?)?;
  Ok(())
}
#[unsafe(no_mangle)]
extern "C" fn search_input_focus(state: *mut c_void) -> i32 {
  let active=lua53_sys::check_integer(state,1)!=0;
  let old=ACTIVE.swap(active,Ordering::Relaxed);
  if active {
    if !old { PREVIOUS.store(unsafe { SDL_IsTextInputActive()!=0 },Ordering::Relaxed); }
    if unsafe { SDL_IsTextInputActive()==0 } { unsafe { SDL_StartTextInput() }; }
    let mut rect=Rect {x:lua53_sys::check_integer(state,2) as i32,y:lua53_sys::check_integer(state,3) as i32,
      w:lua53_sys::check_integer(state,4) as i32,h:lua53_sys::check_integer(state,5) as i32};
    let dims=crate::df::gps::get_dimensions();let mut width=0;let mut height=0;
    unsafe { SDL_GetWindowSize(crate::df::renderer::get_sdl_info().window as *mut c_void,&mut width,&mut height) };
    if dims.width>0 && dims.height>0 {
      rect.x=rect.x*width/dims.width;rect.w=rect.w*width/dims.width;
      rect.y=rect.y*height/dims.height;rect.h=rect.h*height/dims.height;
    }
    unsafe { SDL_SetTextInputRect(&rect) };
  } else if old {
    actions().lock().unwrap().clear();
    if !PREVIOUS.load(Ordering::Relaxed) { unsafe { SDL_StopTextInput() }; }
  }
  0
}
#[unsafe(no_mangle)]
extern "C" fn search_input_drain(state: *mut c_void) -> i32 {
  let events: Vec<_>=actions().lock().unwrap().drain(..).collect();
  lua53_sys::push_string(state,&serde_json::to_string(&events).unwrap());1
}
#[unsafe(no_mangle)]
extern "C" fn search_push_text(state: *mut c_void) -> i32 {
  let text=lua53_sys::check_string(state,1);
  if text.len()>4096 || text.contains('\0') { lua53_sys::push_boolean(state,false);return 1; }
  let mut chunk=String::new();let mut ok=true;
  let mut send=|chunk: &str| {
    let mut event=Event {bytes:[0;56]};event.set(0,0x303);
    event.bytes[12..12+chunk.len()].copy_from_slice(chunk.as_bytes());
    ok &= unsafe { SDL_PushEvent(&mut event)==1 };
  };
  for character in text.chars() {
    if chunk.len()+character.len_utf8()>31 { send(&chunk);chunk.clear(); }
    chunk.push(character);
  }
  if !chunk.is_empty() { send(&chunk); }
  lua53_sys::push_boolean(state,ok);1
}
#[unsafe(no_mangle)]
extern "C" fn search_push_composition(state: *mut c_void) -> i32 {
  let text=lua53_sys::check_string(state,1);
  if text.len()>31 || text.contains('\0') { lua53_sys::push_boolean(state,false);return 1; }
  let mut event=Event {bytes:[0;56]};event.set(0,0x302);
  event.bytes[12..12+text.len()].copy_from_slice(text.as_bytes());
  event.set(48,text.chars().count() as u32);
  lua53_sys::push_boolean(state,unsafe { SDL_PushEvent(&mut event)==1 });1
}
#[unsafe(no_mangle)]
extern "C" fn search_push_key(state: *mut c_void) -> i32 {
  let key=lua53_sys::check_integer(state,1) as u32;
  let mods=lua53_sys::check_integer(state,2) as u16;
  let mut event=Event {bytes:[0;56]};event.set(0,0x300);event.set(20,key);
  event.bytes[24..26].copy_from_slice(&mods.to_ne_bytes());
  let pressed=unsafe { SDL_PushEvent(&mut event)==1 };
  event.set(0,0x301);
  let released=unsafe { SDL_PushEvent(&mut event)==1 };
  lua53_sys::push_boolean(state,pressed && released);1
}
#[unsafe(no_mangle)]
extern "C" fn search_widget_notify(state: *mut c_void) -> i32 {
  let widget=lua53_sys::check_integer(state,1) as *mut c_void;
  let callback=lua53_sys::check_integer(state,2) as *mut c_void;
  let called=unsafe { cpp::notify_search_textbox(widget,callback) };
  lua53_sys::push_boolean(state,called);1
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn utf8_sdl_commits_are_kept_intact_and_invalid_bytes_rejected() {
    let mut event=Event {bytes:[0;56]};event.set(0,0x303);
    let query="鐵 高腳杯 花崗岩";
    event.bytes[12..12+query.len()].copy_from_slice(query.as_bytes());
    assert_eq!(text(&event),Some(query.into()));
    event.bytes[12]=0xff;assert_eq!(text(&event),None);
  }
}
