use std::collections::{VecDeque,HashSet};
use std::ffi::{c_char,c_void,CStr};
use std::sync::{Mutex,OnceLock};
use std::sync::atomic::{AtomicBool,AtomicU64,Ordering};


#[repr(C,align(8))]
#[derive(Clone,Copy)]
struct Event { bytes: [u8;56] }
impl Event {
  fn number(&self,offset: usize) -> u32 { u32::from_ne_bytes(self.bytes[offset..offset+4].try_into().unwrap()) }
  fn set(&mut self,offset: usize,value: u32) { self.bytes[offset..offset+4].copy_from_slice(&value.to_ne_bytes()); }
}
#[repr(C)]
#[derive(Clone,Copy,PartialEq,Eq)]
pub(crate) struct Rect { pub x: i32,pub y: i32,pub w: i32,pub h: i32 }
#[cfg_attr(windows,link(name="SDL2",kind="raw-dylib"))]
unsafe extern "C" {
  pub(crate) fn SDL_StartTextInput();
  pub(crate) fn SDL_StopTextInput();
  pub(crate) fn SDL_IsTextInputActive() -> i32;
  pub(crate) fn SDL_SetTextInputRect(rect: *const Rect);
  pub(crate) fn SDL_GetKeyboardFocus() -> *mut c_void;
  pub(crate) fn SDL_GetVersion(version:*mut u8);
  pub(crate) fn SDL_SetHintWithPriority(name:*const c_char,value:*const c_char,priority:i32)->i32;
  fn SDL_GetClipboardText() -> *mut c_char;
  fn SDL_SetClipboardText(text: *const c_char) -> i32;
  fn SDL_free(memory: *mut c_void);
  fn SDL_PushEvent(event: *mut Event) -> i32;
  fn SDL_GetWindowSize(window: *mut c_void,w: *mut i32,h: *mut i32);
}
#[cfg(windows)]
unsafe extern "system" {
  fn OpenClipboard(window: *mut c_void) -> i32;
  fn CloseClipboard() -> i32;
  fn GetClipboardData(format: u32) -> *mut c_void;
  fn GlobalLock(memory: *mut c_void) -> *mut c_void;
  fn GlobalUnlock(memory: *mut c_void) -> i32;
  fn GlobalSize(memory: *mut c_void) -> usize;
}
#[cfg(windows)]
const CF_UNICODETEXT: u32 = 13;
#[derive(serde::Serialize)]
struct Action { kind: &'static str,text: String,start:i32,length:i32 }
static ACTIVE: AtomicBool=AtomicBool::new(false);
static GENERATION:AtomicU64=AtomicU64::new(0);
static RECT:Mutex<Rect>=Mutex::new(Rect{x:0,y:0,w:20,h:1});
#[derive(Default)]
struct Ownership { composing:bool,cycle:bool,keys:HashSet<u32> }
static OWNERSHIP:OnceLock<Mutex<Ownership>>=OnceLock::new();
fn ownership()->&'static Mutex<Ownership> {OWNERSHIP.get_or_init(||Mutex::new(Ownership::default()))}
static ACTIONS: OnceLock<Mutex<VecDeque<Action>>>=OnceLock::new();
fn actions() -> &'static Mutex<VecDeque<Action>> { ACTIONS.get_or_init(|| Mutex::new(VecDeque::new())) }
fn push(kind: &'static str,text: String) {
  let mut actions=actions().lock().unwrap();
  if actions.len()<2048 && text.len()<=32768 { actions.push_back(Action {kind,text,start:0,length:0}); }
}
fn composition(text:String,start:i32,length:i32) {
  if text.len()>4096 {return}
  let mut owner=ownership().lock().unwrap();
  owner.cycle|=owner.composing || !text.is_empty();
  owner.composing=!text.is_empty();
  drop(owner);
  let mut queue=actions().lock().unwrap();
  // Composition is a snapshot. Replace stale snapshots, preserving commits
  // and ensuring the final empty snapshot can always clear the editor.
  queue.retain(|action|action.kind!="composition");
  queue.push_back(Action{kind:"composition",text,start,length});
}
pub(crate) fn cancel_composition() {
  let mut owner=ownership().lock().unwrap();
  owner.composing=false;owner.cycle=false;
  drop(owner);push("cancel",String::new());
}
fn text(event: &Event) -> Option<String> {
  let bytes=&event.bytes[12..44];
  std::str::from_utf8(&bytes[..bytes.iter().position(|b| *b==0).unwrap_or(32)]).ok().map(str::to_owned)
}
#[cfg(windows)]
fn decode_windows_clipboard_utf16(words: &[u16]) -> Option<String> {
  if words.len()>32769 {return None}
  let end=words.iter().position(|word| *word==0)?;
  let text=String::from_utf16(&words[..end]).ok()?;
  (text.len()<=32768).then_some(text)
}
#[cfg(windows)]
fn windows_clipboard_text() -> Option<String> {
  if unsafe {OpenClipboard(std::ptr::null_mut())} == 0 { return None; }
  let result=(|| {
    let handle=unsafe {GetClipboardData(CF_UNICODETEXT)};
    if handle.is_null() { return None; }
    let size=unsafe {GlobalSize(handle)};
    if size<2 || size>65538 || size%2!=0 { return None; }
    let pointer=unsafe {GlobalLock(handle)} as *const u16;
    if pointer.is_null() { return None; }
    let words=unsafe {std::slice::from_raw_parts(pointer,size/2)};
    let result=decode_windows_clipboard_utf16(words);
    unsafe {GlobalUnlock(handle)};
    result
  })();
  unsafe {CloseClipboard()};
  result
}
fn clipboard_text() -> Option<String> {
  #[cfg(windows)]
  {return windows_clipboard_text();}
  #[cfg(not(windows))] {
  let pointer=unsafe {SDL_GetClipboardText()};
  if pointer.is_null() { return None; }
  let text=unsafe {CStr::from_ptr(pointer)}.to_str().ok().map(str::to_owned);
  unsafe {SDL_free(pointer as *mut c_void)};
  text
  }
}
fn capture(event: &Event) -> bool {
  match event.number(0) {
    0x303 => {
      let mut owner=ownership().lock().unwrap();owner.cycle|=owner.composing;owner.composing=false;drop(owner);
      if let Some(text)=text(event) { push("text",text); } true
    },
    0x302 => { if let Some(text)=text(event) { composition(text,event.number(44) as i32,event.number(48) as i32); } true },
    0x305 => {
      // SDL_TextEditingExtEvent owns an SDL-allocated UTF-8 string.
      let pointer=usize::from_ne_bytes(event.bytes[16..24].try_into().unwrap()) as *mut c_char;
      if !pointer.is_null() {
        let text=unsafe {CStr::from_ptr(pointer)}.to_str().ok().map(str::to_owned);
        unsafe {SDL_free(pointer as *mut c_void)};
        if let Some(text)=text {composition(text,event.number(24) as i32,event.number(28) as i32)}
      }
      true
    },
    0x300 | 0x301 => {
      let key=event.number(20);
      let mut owner=ownership().lock().unwrap();
      // Preserve IME/mode-switch modifier handling. Windows already saw keys
      // before SDL; swallowing here only prevents game/Lua shortcut leakage.
      let modifier=(1073742048..=1073742055).contains(&key);
      let ime=owner.composing || owner.cycle;
      let owned_release=event.number(0)==0x301 && owner.keys.remove(&key);
      if !modifier && (ime || owned_release) {
        if event.number(0)==0x300 {owner.keys.insert(key);}
        return true;
      }
      drop(owner);
      let mods=u16::from_ne_bytes(event.bytes[24..26].try_into().unwrap());
      let ctrl=mods & 0x0cc0 != 0;
      let action=match key {
        8 => Some("backspace"),127 => Some("delete"),
        1073741904 => Some("left"),1073741903 => Some("right"),
        1073741898 => Some("home"),1073741901 => Some("end"),
        97 if ctrl => Some("select_all"),118 if ctrl => Some("paste"),
        99 if ctrl => Some("copy"),120 if ctrl => Some("cut"),
        _ => None,
      };
      if event.number(0)==0x300 {
        if action==Some("paste") {
          if let Some(text)=clipboard_text() { push("text",text); }
        } else if let Some(action)=action { push(action,String::new()); }
      }
      action.is_some() || ((32..127).contains(&key) && !ctrl)
    },
    _ => false,
  }
}
fn search_poll_event(event: *mut Event) -> i32 {
  #[cfg(windows)] {
    let mut rect=*RECT.lock().unwrap();
    let dims=crate::df::gps::get_dimensions();let mut width=0;let mut height=0;
    let window=unsafe {SDL_GetKeyboardFocus()};
    if !window.is_null() {unsafe {SDL_GetWindowSize(window,&mut width,&mut height)}}
    if dims.width>0 && dims.height>0 && width>0 && height>0 {
      rect.x=rect.x*width/dims.width;rect.w=(rect.w*width/dims.width).max(1);
      rect.y=rect.y*height/dims.height;rect.h=(rect.h*height/dims.height).max(1);
      rect.x=rect.x.clamp(0,width-1);rect.y=rect.y.clamp(0,height-1);
      rect.w=rect.w.min(width-rect.x);rect.h=rect.h.min(height-rect.y);
    }
    crate::search_ime_windows::sync(ACTIVE.load(Ordering::Relaxed),GENERATION.load(Ordering::Relaxed),rect);
  }
  loop {
    let result=call_search_poll_event(event);
    #[cfg(windows)] {
      crate::search_ime_windows::after_pump();
      if crate::search_ime_windows::composing() {ownership().lock().unwrap().cycle=true;}
    }
    if result==0 {ownership().lock().unwrap().cycle=false;return result}
    if event.is_null() {return result}
    let current=unsafe {&*event};
    // Always consume releases of keys owned before focus moved.
    if !ACTIVE.load(Ordering::Relaxed) {
      if current.number(0)==0x301 && ownership().lock().unwrap().keys.remove(&current.number(20)) {continue}
      return result;
    }
    if !capture(unsafe { &*event }) { return result; }
  }
}
macros::hook! { fn search_poll_event(event: *mut Event) -> i32; }
pub fn attach() -> anyhow::Result<()> {
  unsafe {SDL_SetHintWithPriority(c"SDL_IME_SHOW_UI".as_ptr(),c"1".as_ptr(),2);}
  #[cfg(windows)]
  attach_search_poll_event(crate::memory::get_raw_pointer_by_key("search_poll_event")?)?;
  Ok(())
}
#[unsafe(no_mangle)]
extern "C" fn search_input_focus(state: *mut c_void) -> i32 {
  let active=lua53_sys::check_integer(state,1)!=0;
  let old=ACTIVE.swap(active,Ordering::Relaxed);
  if old!=active {GENERATION.fetch_add(1,Ordering::Relaxed);}
  if active {
    let rect=Rect {x:lua53_sys::check_integer(state,2) as i32,y:lua53_sys::check_integer(state,3) as i32,
      w:lua53_sys::check_integer(state,4) as i32,h:lua53_sys::check_integer(state,5) as i32};
    *RECT.lock().unwrap()=rect;
  } else if old {
    actions().lock().unwrap().clear();
    cancel_composition();
  }
  0
}
#[unsafe(no_mangle)]
extern "C" fn search_ime_status(state:*mut c_void)->i32 {
  #[cfg(windows)] let status=crate::search_ime_windows::status();
  #[cfg(not(windows))] let status=serde_json::json!({"tsf_registered":false});
  lua53_sys::push_string(state,&status.to_string());1
}
#[unsafe(no_mangle)]
extern "C" fn search_ime_candidates(state:*mut c_void)->i32 {
  #[cfg(windows)] let candidates=crate::search_ime_windows::candidates();
  #[cfg(not(windows))] let candidates=serde_json::json!({"active":false,"first":0,"selected":0,"items":[]});
  lua53_sys::push_string(state,&candidates.to_string());1
}
#[unsafe(no_mangle)]
extern "C" fn search_input_drain(state: *mut c_void) -> i32 {
  let events: Vec<_>=actions().lock().unwrap().drain(..).collect();
  lua53_sys::push_string(state,&serde_json::to_string(&events).unwrap());1
}
// SDL's public setter takes UTF-8. Never pass search text to DFHack's CP437
// clipboard setter: that converts each UTF-8 byte to an unrelated character.
#[unsafe(no_mangle)]
extern "C" fn search_clipboard_write(state: *mut c_void) -> i32 {
  let text=lua53_sys::check_string(state,1);
  let ok=text.len()<=32768 && std::ffi::CString::new(text).ok()
    .is_some_and(|text|unsafe {SDL_SetClipboardText(text.as_ptr())==0});
  lua53_sys::push_boolean(state,ok);1
}
#[unsafe(no_mangle)]
extern "C" fn search_push_text(state: *mut c_void) -> i32 {
  let text=lua53_sys::check_string(state,1);
  if text.len()>32768 || text.contains('\0') { lua53_sys::push_boolean(state,false);return 1; }
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
  static INPUT_TEST:Mutex<()>=Mutex::new(());
  #[cfg(windows)]
  #[test]
  fn clipboard_rejects_unterminated_oversized_and_broken_surrogates() {
    assert!(decode_windows_clipboard_utf16(&[0x597d]).is_none());
    assert!(decode_windows_clipboard_utf16(&[0xd840,0]).is_none());
    assert!(decode_windows_clipboard_utf16(&vec![0;32770]).is_none());
    assert_eq!(decode_windows_clipboard_utf16(&[0xd842,0xdfb7,0]),Some("𠮷".into()));
    let mut words=vec![0x597d;12000];words.push(0);
    assert!(decode_windows_clipboard_utf16(&words).is_none());
  }
  #[test]
  fn composition_churn_cannot_drop_commits_or_the_final_clear() {
    let _serial=INPUT_TEST.lock().unwrap();actions().lock().unwrap().clear();
    push("text","𠮷".into());
    for _ in 0..4096 {composition("ㄅ".into(),0,1);}
    composition(String::new(),0,0);
    let queue=actions().lock().unwrap().drain(..).collect::<Vec<_>>();
    assert_eq!(queue.len(),2);assert_eq!(queue[0].text,"𠮷");
    assert_eq!(queue[1].kind,"composition");assert!(queue[1].text.is_empty());
    *ownership().lock().unwrap()=Ownership::default();
  }
  #[test]
  fn clipboard_shortcuts_are_owned_by_the_utf8_bridge() {
    let _serial=INPUT_TEST.lock().unwrap();
    *ownership().lock().unwrap()=Ownership::default();
    actions().lock().unwrap().clear();
    for key in [99,120] {
      let mut event=Event{bytes:[0;56]};event.set(0,0x300);event.set(20,key);
      event.bytes[24..26].copy_from_slice(&0x40u16.to_ne_bytes());
      assert!(capture(&event),"Clipboard shortcut leaked to the CP437 editor");
      event.set(0,0x301);assert!(capture(&event));
    }
    let queue:Vec<_>=actions().lock().unwrap().drain(..).map(|action|action.kind).collect();
    assert_eq!(queue,vec!["copy","cut"]);
  }
  #[cfg(windows)]
  #[test]
  fn windows_clipboard_utf16_keeps_cjk_text_intact() {
    assert_eq!(decode_windows_clipboard_utf16(&[0x597d,0]),Some("好".to_owned()));
  }
  #[test]
  fn composing_keys_do_not_edit_the_committed_query_or_escape_to_game() {
    let _serial=INPUT_TEST.lock().unwrap();
    actions().lock().unwrap().clear();
    let mut event=Event {bytes:[0;56]};event.set(0,0x302);
    event.bytes[12..15].copy_from_slice("ㄅ".as_bytes());
    assert!(capture(&event));
    for key in [8,127,1073741904,1073741903,1073741906,1073741905,13,27,32,49,1073741899,1073741902] {
      event=Event {bytes:[0;56]};event.set(0,0x300);event.set(20,key);
      assert!(capture(&event),"IME key {key} leaked to game");
    }
    let captured:Vec<_>=actions().lock().unwrap().drain(..).collect();
    assert_eq!(captured.len(),1,"Candidate keys must not become Lua edits");
    event=Event {bytes:[0;56]};event.set(0,0x303);
    event.bytes[12..15].copy_from_slice("八".as_bytes());
    assert!(capture(&event));
    event=Event {bytes:[0;56]};event.set(0,0x300);event.set(20,13);
    assert!(capture(&event),"Commit Enter must not select a game item");
  }
  #[test]
  fn utf8_sdl_commits_are_kept_intact_and_invalid_bytes_rejected() {
    let mut event=Event {bytes:[0;56]};event.set(0,0x303);
    let query="鐵 高腳杯 花崗岩";
    event.bytes[12..12+query.len()].copy_from_slice(query.as_bytes());
    assert_eq!(text(&event),Some(query.into()));
    event.bytes[12]=0xff;assert_eq!(text(&event),None);
  }
}
