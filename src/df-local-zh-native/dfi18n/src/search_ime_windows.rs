//! Public SDL/IMM/TSF adapter. No SDL internals or foreign vtables are patched.
//! All COM objects and SDL/IMM calls stay on the SDL polling thread.
use std::{cell::RefCell,collections::BTreeMap,ffi::c_void,rc::Rc,sync::{Mutex,OnceLock},sync::atomic::{AtomicBool,AtomicU64,Ordering}};
use windows::{core::{implement,Interface,BOOL},Win32::{Foundation::{HWND,POINT,RECT},System::Com::{CoCreateInstance,CLSCTX_INPROC_SERVER},UI::{Input::Ime::*,TextServices::*}}};
use super::search_input::{Rect,SDL_GetKeyboardFocus,SDL_GetVersion,SDL_SetHintWithPriority,SDL_StartTextInput,SDL_StopTextInput,SDL_IsTextInputActive,SDL_SetTextInputRect};

// The documented SDL_SysWMinfo ABI: version, subsystem, 64-byte platform union.
#[repr(C)]
struct WmInfo { version:[u8;3], subsystem:u32, info:[usize;8] }
#[link(name="SDL2",kind="raw-dylib")]
unsafe extern "C" { fn SDL_GetWindowWMInfo(window:*mut c_void,info:*mut WmInfo)->i32; }

pub static CANDIDATES:AtomicBool=AtomicBool::new(false);
static ENABLED:AtomicBool=AtomicBool::new(false);
static BEGINS:AtomicU64=AtomicU64::new(0);
static UPDATES:AtomicU64=AtomicU64::new(0);
static ENDS:AtomicU64=AtomicU64::new(0);
static SHOWN:AtomicU64=AtomicU64::new(0);
static REGISTERED:AtomicBool=AtomicBool::new(false);
static SDL_TEXT_INPUT_ACTIVE:AtomicBool=AtomicBool::new(false);
static SDL_KEYBOARD_FOCUS:AtomicBool=AtomicBool::new(false);
// IMM polling is only a fallback.  Once a public TSF candidate element is
// alive, an empty IMM buffer must not erase the newer TSF snapshot.
static TSF_UI_ACTIVE:AtomicBool=AtomicBool::new(false);
type Elements=Rc<RefCell<BTreeMap<u32,ITfUIElement>>>;

#[derive(Clone,Default,serde::Serialize)]
struct CandidateSnapshot { active:bool,first:u32,selected:u32,items:Vec<String> }
static SNAPSHOT:OnceLock<Mutex<CandidateSnapshot>>=OnceLock::new();
fn snapshot()->&'static Mutex<CandidateSnapshot> {SNAPSHOT.get_or_init(||Mutex::new(CandidateSnapshot::default()))}

fn update_candidate_snapshot(element:&ITfUIElement) {
    let Ok(list)=element.cast::<ITfCandidateListUIElement>() else {return};
    let count=unsafe {list.GetCount().unwrap_or(0)};
    let selected=unsafe {list.GetSelection().unwrap_or(0)};
    let page=unsafe {list.GetCurrentPage().unwrap_or(0)};
    let mut indices=[0u32;64];let mut page_count=0u32;
    let _=unsafe {list.GetPageIndex(&mut indices,&mut page_count as *mut u32)};
    let page_count=page_count.min(indices.len() as u32) as usize;
    let (first,last)=if page_count>0 {candidate_page_bounds(count,page,&indices[..page_count])} else {(0,count)};
    let mut items=Vec::new();
    for index in first..last.min(first+32) {
        if let Ok(value)=unsafe {list.GetString(index)} {
            let value=value.to_string();
            if !value.is_empty() {items.push(value)}
        }
    }
    let active=!items.is_empty();
    *snapshot().lock().unwrap()=CandidateSnapshot{active,first,selected,items};
    CANDIDATES.store(active,Ordering::Relaxed);
}
fn clear_candidate_snapshot() {
    *snapshot().lock().unwrap()=CandidateSnapshot::default();
    CANDIDATES.store(false,Ordering::Relaxed);
}

fn text_input_needs_restart(active:bool)->bool { !active }

fn merge_imm_snapshot(tsf_active:bool,current:CandidateSnapshot,incoming:Option<CandidateSnapshot>)->CandidateSnapshot {
    if tsf_active { current } else { incoming.unwrap_or_default() }
}

fn publish_imm_snapshot(incoming:Option<CandidateSnapshot>) {
    let mut current=snapshot().lock().unwrap();
    let merged=merge_imm_snapshot(TSF_UI_ACTIVE.load(Ordering::Relaxed),current.clone(),incoming);
    let active=merged.active;
    *current=merged;
    CANDIDATES.store(active,Ordering::Relaxed);
}

fn update_imm_candidate_snapshot(hwnd: HWND) {
    if TSF_UI_ACTIVE.load(Ordering::Relaxed) {return}
    let context=unsafe {ImmGetContext(hwnd)};
    if context.0.is_null() {return}
    let size=unsafe {ImmGetCandidateListW(context,0,None,0)} as usize;
    if !(24..=1048576).contains(&size) {
        unsafe {let _=ImmReleaseContext(hwnd,context);}
        publish_imm_snapshot(None);
        return
    }
    let mut bytes=vec![0u8;size];
    let copied=unsafe {ImmGetCandidateListW(context,0,Some(bytes.as_mut_ptr() as *mut CANDIDATELIST),size as u32)} as usize;
    unsafe {let _=ImmReleaseContext(hwnd,context);}
    if copied<24 || copied>bytes.len() {publish_imm_snapshot(None);return}
    bytes.truncate(copied);
    let read_u32=|offset:usize| -> Option<u32> {
        let end=offset.checked_add(4)?;
        Some(u32::from_le_bytes(bytes.get(offset..end)?.try_into().ok()?))
    };
    let count=read_u32(8).unwrap_or(0).min(64);
    let selected=read_u32(12).unwrap_or(0);
    let first=read_u32(16).unwrap_or(0).min(count);
    let raw_page_size=read_u32(20).unwrap_or(0);
    let page_size=if raw_page_size==0 {count.saturating_sub(first)} else {raw_page_size.min(count.saturating_sub(first))};
    let mut items=Vec::new();
    for index in first..first.saturating_add(page_size) {
        let Some(offset)=read_u32(24usize.saturating_add(index as usize*4)).map(|value|value as usize) else {break};
        if offset>=copied {continue}
        let mut utf16=Vec::new();
        let mut cursor=offset;
        while cursor+1<copied && utf16.len()<256 {
            let value=u16::from_le_bytes([bytes[cursor],bytes[cursor+1]]);cursor+=2;
            if value==0 {break}
            utf16.push(value);
        }
        if let Ok(value)=String::from_utf16(&utf16) {
            if !value.is_empty() {items.push(value)}
        }
    }
    if items.is_empty() {publish_imm_snapshot(None)} else {
        publish_imm_snapshot(Some(CandidateSnapshot{active:true,first,selected,items}));
    }
}

fn candidate_page_bounds(count:u32,page:u32,indices:&[u32])->(u32,u32) {
    let Some(&start)=indices.get(page as usize) else {return (0,0)};
    let end=indices.get(page as usize+1).copied().unwrap_or(count);
    let start=start.min(count);let end=end.min(count);
    if end<start {(start,start)} else {(start,end)}
}

#[cfg(test)]
mod tests {
    use super::{candidate_page_bounds,merge_imm_snapshot,text_input_needs_restart,CandidateSnapshot};

    #[test]
    fn focus_resume_restarts_text_input_when_sdl_stopped_it() {
        assert!(text_input_needs_restart(false));
        assert!(!text_input_needs_restart(true));
    }

    #[test]
    fn imm_poll_does_not_clear_a_live_tsf_candidate_snapshot() {
        let current=CandidateSnapshot{active:true,first:0,selected:1,items:vec!["一".into(),"壹".into()]};
        let merged=merge_imm_snapshot(true,current.clone(),None);
        assert_eq!(merged.items,current.items);
        assert!(merged.active);
    }

    #[test]
    fn imm_poll_clears_its_snapshot_when_no_tsf_ui_is_active() {
        let current=CandidateSnapshot{active:true,first:0,selected:0,items:vec!["一".into()]};
        let merged=merge_imm_snapshot(false,current,None);
        assert!(!merged.active);
        assert!(merged.items.is_empty());
    }

    #[test]
    fn candidate_page_bounds_clamps_missing_or_reversed_page_indices() {
        assert_eq!(candidate_page_bounds(8,1,&[0,4,8]),(4,8));
        assert_eq!(candidate_page_bounds(8,4,&[0,4,8]),(0,0));
        assert_eq!(candidate_page_bounds(8,1,&[6,2,1]),(2,2));
    }
}

#[implement(ITfUIElementSink)]
struct UiSink { manager:ITfUIElementMgr, elements:Elements }
impl UiSink {
    fn remember(&self,id:u32)->windows::core::Result<bool> {
        let element=unsafe {self.manager.GetUIElement(id)}?;
        if element.cast::<ITfCandidateListUIElement>().is_err() {return Ok(false)}
        self.elements.borrow_mut().insert(id,element);
        TSF_UI_ACTIVE.store(true,Ordering::Relaxed);
        if let Some(element)=self.elements.borrow().get(&id) {update_candidate_snapshot(element)}
        CANDIDATES.store(true,Ordering::Relaxed);
        Ok(true)
    }
}
#[allow(non_snake_case)]
impl ITfUIElementSink_Impl for UiSink_Impl {
    fn BeginUIElement(&self,id:u32,show:*mut BOOL)->windows::core::Result<()> {
        if ENABLED.load(Ordering::Relaxed) && self.remember(id).unwrap_or(false) {
            BEGINS.fetch_add(1,Ordering::Relaxed);
            // SDL 2.26 can already have its UI-less sink active when the mod
            // loads. Switching this element to native presentation can end
            // the TSF UI-element stream immediately, losing both the page and
            // subsequent selection updates. Keep presentation in our Lua
            // fallback; Windows still owns composition and selection keys.
            // Do not call Show from a TSF/SDL callback: the TIP can reenter it.
            if !show.is_null() {unsafe {*show=BOOL(0)}}
        }
        Ok(())
    }
    fn UpdateUIElement(&self,id:u32)->windows::core::Result<()> {
        if ENABLED.load(Ordering::Relaxed) && self.remember(id).unwrap_or(false) {
            UPDATES.fetch_add(1,Ordering::Relaxed);
            if let Some(element)=self.elements.borrow().get(&id) {update_candidate_snapshot(element)}
        }
        Ok(())
    }
    fn EndUIElement(&self,id:u32)->windows::core::Result<()> {
        if self.elements.borrow_mut().remove(&id).is_some() {
            ENDS.fetch_add(1,Ordering::Relaxed);
            CANDIDATES.store(!self.elements.borrow().is_empty(),Ordering::Relaxed);
            if self.elements.borrow().is_empty() {
                TSF_UI_ACTIVE.store(false,Ordering::Relaxed);
                clear_candidate_snapshot()
            }
        }
        Ok(())
    }
}
struct Registration { manager:ITfThreadMgrEx, source:ITfSource,cookie:u32,_sink:ITfUIElementSink }
impl Registration {
    fn new()->windows::core::Result<Self> {
        let manager:ITfThreadMgrEx=unsafe {CoCreateInstance(&CLSID_TF_ThreadMgr,None,CLSCTX_INPROC_SERVER)}?;
        let mut client_id=0u32;
        unsafe {manager.ActivateEx(&mut client_id,TF_TMAE_UIELEMENTENABLEDONLY)?};
        let registration=(|| -> windows::core::Result<Self> {
        let source:ITfSource=manager.cast()?;
        let elements=Rc::new(RefCell::new(BTreeMap::new()));
        let sink:ITfUIElementSink=UiSink{manager:manager.cast()?,elements:elements.clone()}.into();
        let cookie=unsafe {source.AdviseSink(&ITfUIElementSink::IID,&sink)}?;
        REGISTERED.store(true,Ordering::Relaxed);
        Ok(Self{manager:manager.clone(),source,cookie,_sink:sink})
        })();
        if registration.is_err() {let _=unsafe {manager.Deactivate()};}
        registration
    }
}
impl Drop for Registration {
    fn drop(&mut self) {
        // The source releases its callback reference before our sink is released.
        let _=unsafe {self.source.UnadviseSink(self.cookie)};
        let _=unsafe {self.manager.Deactivate()};
        REGISTERED.store(false,Ordering::Relaxed);
        TSF_UI_ACTIVE.store(false,Ordering::Relaxed);
        CANDIDATES.store(false,Ordering::Relaxed);
    }
}

#[derive(Default)]
struct Session { hwnd:Option<HWND>,previous:bool,generation:u64,tsf:Option<Registration>,rect:Option<Rect> }
thread_local! {static SESSION:RefCell<Session>=RefCell::new(Session::default());}
fn window()->Option<HWND> {
    let focus=unsafe {SDL_GetKeyboardFocus()};
    if focus.is_null() {return None}
    let mut info=WmInfo{version:[0;3],subsystem:0,info:[0;8]};
    unsafe {SDL_GetVersion(info.version.as_mut_ptr())};
    if unsafe {SDL_GetWindowWMInfo(focus,&mut info)}==0 || info.subsystem!=1 {return None}
    Some(HWND(info.info[0] as *mut c_void))
}
fn cancel(hwnd:HWND) {
    let context=unsafe {ImmGetContext(hwnd)};
    if !context.0.is_null() {unsafe {
        let _=ImmNotifyIME(context,NI_COMPOSITIONSTR,CPS_CANCEL,0);
        let _=ImmReleaseContext(hwnd,context);
    }}
}
fn position(hwnd:HWND,rect:Rect) {
    let context=unsafe {ImmGetContext(hwnd)};
    if context.0.is_null() {return}
    let area=RECT{left:rect.x,top:rect.y,right:rect.x+rect.w,bottom:rect.y+rect.h};
    // Match SDL's documented Windows adapter: composition uses the full client
    // rectangle and the candidate list is excluded below that rectangle.
    let anchor=POINT{x:rect.x,y:rect.y+rect.h};
    unsafe {
        let _=ImmSetCompositionWindow(context,&COMPOSITIONFORM{dwStyle:CFS_RECT,ptCurrentPos:POINT{x:rect.x,y:rect.y},rcArea:area});
        let _=ImmSetCandidateWindow(context,&CANDIDATEFORM{dwIndex:0,dwStyle:CFS_EXCLUDE,ptCurrentPos:anchor,rcArea:area});
        let _=ImmReleaseContext(hwnd,context);
    }
}
fn stop(session:&mut Session) {
    ENABLED.store(false,Ordering::Relaxed);
    if let Some(hwnd)=session.hwnd {cancel(hwnd)}
    session.tsf=None;
    if session.hwnd.is_some() && !session.previous {unsafe {SDL_StopTextInput()}}
    session.hwnd=None;session.rect=None;
    SDL_TEXT_INPUT_ACTIVE.store(false,Ordering::Relaxed);
    SDL_KEYBOARD_FOCUS.store(false,Ordering::Relaxed);
    clear_candidate_snapshot();
    super::search_input::cancel_composition();
}
pub fn sync(active:bool,generation:u64,rect:Rect) {
    SESSION.with(|cell| {
        let mut session=cell.borrow_mut();
        // Candidate UI and remote/on-screen keyboards can briefly move the
        // native focus while the SDL window remains the active text target.
        // Keep the established HWND through that transient gap so a ↓/Enter
        // candidate choice cannot cancel the composition session.
        let focused_window=if active {window()} else {None};
        SDL_KEYBOARD_FOCUS.store(focused_window.is_some(),Ordering::Relaxed);
        let hwnd=if active {focused_window.or(session.hwnd)} else {None};
        if session.hwnd!=hwnd || session.generation!=generation {
            stop(&mut session);
            session.generation=generation;
            if let Some(hwnd)=hwnd {
                unsafe {
                    SDL_SetHintWithPriority(c"SDL_IME_SHOW_UI".as_ptr(),c"1".as_ptr(),2);
                    SDL_SetHintWithPriority(c"SDL_IME_INTERNAL_EDITING".as_ptr(),c"0".as_ptr(),2);
                }
                session.previous=unsafe {SDL_IsTextInputActive()!=0};
                if !session.previous {unsafe {SDL_StartTextInput()}}
                session.hwnd=Some(hwnd);
                ENABLED.store(true,Ordering::Relaxed);
                match Registration::new() {
                    Ok(registration)=>session.tsf=Some(registration),
                    Err(error)=>log::warn!("IME public TSF sink unavailable: {error}; SDL/IMM remains active"),
                }
            }
        }
        if let Some(hwnd)=session.hwnd {
            let text_input_active=unsafe {SDL_IsTextInputActive()!=0};
            SDL_TEXT_INPUT_ACTIVE.store(text_input_active,Ordering::Relaxed);
            if text_input_needs_restart(text_input_active) {unsafe {SDL_StartTextInput()};}
            if session.rect!=Some(rect) {
                unsafe {SDL_SetTextInputRect(&rect)};
                position(hwnd,rect);session.rect=Some(rect);
            }
        }
    });
}
pub fn after_pump() {
    // IMM is the public native-UI path used when SDL_IME_SHOW_UI is enabled.
    // Polling its documented candidate list keeps the in-game fallback in sync
    // without taking ownership of candidate navigation keys.
    SESSION.with(|cell| {
        if let Some(hwnd)=cell.borrow().hwnd {update_imm_candidate_snapshot(hwnd)}
    });
}
pub fn composing()->bool {
    SESSION.with(|cell| {
        let hwnd=cell.borrow().hwnd;
        hwnd.is_some_and(|hwnd| {
            let context=unsafe {ImmGetContext(hwnd)};
            if context.0.is_null() {return false}
            let size=unsafe {ImmGetCompositionStringW(context,GCS_COMPSTR,None,0)};
            unsafe {let _=ImmReleaseContext(hwnd,context);}
            size>0
        })
    }) || CANDIDATES.load(Ordering::Relaxed)
}
pub fn candidates()->serde_json::Value {
    serde_json::to_value(snapshot().lock().unwrap().clone()).unwrap_or_else(|_|serde_json::json!({"active":false,"first":0,"selected":0,"items":[]}))
}
pub fn status()->serde_json::Value {
    serde_json::json!({"tsf_registered":REGISTERED.load(Ordering::Relaxed),"candidate_active":CANDIDATES.load(Ordering::Relaxed),
        "candidate_ui":"tsf_game_fallback",
        "candidate_begin":BEGINS.load(Ordering::Relaxed),"candidate_update":UPDATES.load(Ordering::Relaxed),
        "candidate_end":ENDS.load(Ordering::Relaxed),"ui_restored":SHOWN.load(Ordering::Relaxed),
        "sdl_text_input_active":SDL_TEXT_INPUT_ACTIVE.load(Ordering::Relaxed),
        "sdl_keyboard_focus":SDL_KEYBOARD_FOCUS.load(Ordering::Relaxed)})
}
