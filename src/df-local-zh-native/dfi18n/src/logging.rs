use df_local_zh_broker::bounded::BoundedMap;
use std::sync::{OnceLock, RwLock};

use crate::{tasks, translation, translator};
use std::sync::atomic::{AtomicBool, Ordering};
static DEVELOPER_MODE: AtomicBool = AtomicBool::new(false);
static TRACE_ENABLED: AtomicBool = AtomicBool::new(false);
static TRACE: OnceLock<std::sync::Mutex<TraceBuffer>> = OnceLock::new();
#[derive(Default)]
struct TraceBuffer {
  rows: Vec<serde_json::Value>,
  bytes: usize,
  incomplete: bool,
}
impl TraceBuffer {
  fn record(&mut self, mut row: serde_json::Value) {
    let index = self.rows.iter().position(|old| ["text","x","y","screen","hook"].iter()
      .all(|key|old[*key]==row[*key]));
    if let Some(index) = index {
      // A source-only notification must not erase the text chosen by the hook.
      if row.get("selectedRows").is_none() { return; }
      row["firstSelectedRows"] = self.rows[index].get("firstSelectedRows")
        .or_else(|| self.rows[index].get("selectedRows")).cloned()
        .unwrap_or_else(|| row["selectedRows"].clone());
      row["selectionChanged"] = (row["firstSelectedRows"] != row["selectedRows"]).into();
      let size = row.to_string().len();
      if size > 65536 { self.incomplete = true; return; }
      let next_bytes = self.bytes - self.rows[index].to_string().len() + size;
      if next_bytes > 4*1024*1024 { self.incomplete = true; return; }
      self.rows[index] = row;
      self.bytes = next_bytes;
    } else {
      if let Some(selected)=row.get("selectedRows").cloned() {
        row["firstSelectedRows"]=selected; row["selectionChanged"]=false.into();
      }
      let size = row.to_string().len();
      if size<=65536 && self.rows.len()<512 && self.bytes+size<=4*1024*1024 {
        self.rows.push(row); self.bytes += size;
      } else { self.incomplete = true; }
    }
  }
}
#[unsafe(no_mangle)]
extern "C" fn core_trace_enable(state: *mut std::ffi::c_void) -> i32 {
  TRACE_ENABLED.store(lua53_sys::check_integer(state,1)!=0,Ordering::Relaxed);
  *TRACE.get_or_init(|| std::sync::Mutex::new(TraceBuffer::default())).lock().unwrap()=TraceBuffer::default();0
}
#[unsafe(no_mangle)]
extern "C" fn core_trace_read(state: *mut std::ffi::c_void) -> i32 {
  let trace=std::mem::take(&mut *TRACE.get_or_init(|| std::sync::Mutex::new(TraceBuffer::default())).lock().unwrap());
  lua53_sys::push_string(state,&serde_json::to_string(&trace.rows).unwrap());1
}
#[unsafe(no_mangle)]
extern "C" fn core_trace_status(state: *mut std::ffi::c_void) -> i32 {
  let trace=TRACE.get_or_init(|| std::sync::Mutex::new(TraceBuffer::default())).lock().unwrap();
  lua53_sys::push_string(state,&serde_json::json!({"schema":2,"rows":trace.rows.len(),
    "bytes":trace.bytes,"incomplete":trace.incomplete,
    "enabled":TRACE_ENABLED.load(Ordering::Relaxed)}).to_string());1
}
pub fn developer_mode() -> bool { DEVELOPER_MODE.load(Ordering::Relaxed) }
#[unsafe(no_mangle)]
extern "C" fn developer_mode_enable() -> i32 { DEVELOPER_MODE.store(true, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn developer_mode_disable() -> i32 { DEVELOPER_MODE.store(false, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn developer_mode_get_status(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_boolean(state, developer_mode()); 1
}

static VISITED: OnceLock<RwLock<BoundedMap<String,()>>> = OnceLock::new();

pub fn trace_text(request: &translation::TranslationRequest) {
  if TRACE_ENABLED.load(Ordering::Relaxed) {
    let position=request.coordinate();
    let row=serde_json::json!({"text":request.original(),"x":position.column,"y":position.row,
      "screen":request.view_screen()});
    TRACE.get_or_init(|| std::sync::Mutex::new(TraceBuffer::default())).lock().unwrap().record(row);
  }
}

/// Opt-in evidence of the block selected for drawing. Clipping and occlusion
/// still require screenshot review; this is not a claim that every glyph drew.
pub fn trace_selected(request: &translation::TranslationRequest, block: &crate::text::TextBlock,
                      hook: &str, layer: &str) {
  if !TRACE_ENABLED.load(Ordering::Relaxed) { return; }
  let selected_rows: Vec<_> = block.iter().map(|row|row.iter().map(|fragment| {
    let color=fragment.color_pair();
    serde_json::json!({"text":fragment.content(),
      "foreground":[color.foreground.r,color.foreground.g,color.foreground.b],
      "background":[color.background.r,color.background.g,color.background.b]})
  }).collect::<Vec<_>>()).collect();
  let position=request.coordinate();
  let row=serde_json::json!({"text":request.original(),"x":position.column,"y":position.row,
    "screen":request.view_screen(),"hook":hook,"layer":layer,"selectedRows":selected_rows,
    "columns":block.columns(),"translationEnabled":crate::control::is_enabled()});
  TRACE.get_or_init(||std::sync::Mutex::new(TraceBuffer::default())).lock().unwrap().record(row);
}

pub fn log_text(request: &translation::TranslationRequest, backtrace: &str, ptr: *const std::ffi::c_void) {
  trace_text(request);
  if !developer_mode() || translator::known(request).is_some() { return; }
  let key = request.key().to_owned();
  let context = request.context().clone();
  let content = context.original();

  if translator::should_skip_translation(content) {
    return;
  }

  // only log new translation requests once
  let visited = VISITED.get_or_init(|| RwLock::new(BoundedMap::new(8192)));
  if visited.read().unwrap().contains_key(&key) {
    return;
  }

  visited.write().unwrap().insert(key.to_owned(),());

  // spawn a task to perform the translation
  let request = request.clone();
  let content = content.to_owned();
  let backtrace = backtrace.to_owned();
  let ptr = ptr as usize;
  tasks::spawn(async move {
    // ensure the translation is performed and cached
    translator::translate_task(request.clone()).await;
    let response = translator::translate(&request);
    if response.is_none() {
      let function = match &context {
        translation::TranslationContext::addst { .. } => "addst",
        translation::TranslationContext::addst_flag { .. } => "addst_flag",
        translation::TranslationContext::addcoloredst { .. } => "addcoloredst",
        translation::TranslationContext::top_addst { .. } => "top_addst",
        translation::TranslationContext::markup_text_box { .. } => "mtb_process_string_to_lines",
        translation::TranslationContext::dfhack { .. } => "dfhack",
      };
      let mut lines = vec![format!("========== {key}"), format!("[{function}] {backtrace}")];

      let viewscreen = request.view_screen();
      lines.push(format!("viewscreen: {viewscreen}"));

      let coordinate = request.coordinate();
      lines.push(format!("coordinate: {coordinate:?}"));

      let color_pair = request.color_pair();
      if let Some(color_pair) = color_pair {
        lines.push(format!("color_pair: {color_pair:?}"));
      }

      match context {
        translation::TranslationContext::addst_flag { flag, .. } => {
          lines.push(format!("flag: {flag:#010b}"));
        }
        _ => {}
      }

      let is_markup = request.is_markup();
      lines.push(format!(
        "---- {} ({ptr:#x}) ----",
        if is_markup { "MarkupText" } else { "PlainText" }
      ));

      lines.push(content.to_owned());

      let debug_string = lines.join("\n");

      log::debug!("{debug_string}");
    }
  });
}

#[cfg(test)]
mod trace_tests {
  use super::*;

  #[test]
  fn trace_keeps_selected_text_when_source_is_seen_again() {
    let mut trace = TraceBuffer::default();
    let source = serde_json::json!({"text":"Moving","x":1,"y":2,"screen":"dungeon"});
    trace.record(source.clone());
    trace.record(serde_json::json!({"text":"Moving","x":1,"y":2,"screen":"dungeon",
      "selectedRows":[[{"text":"移動中","foreground":[0,255,0],"background":[0,0,0]}]],
      "translationEnabled":true}));
    trace.record(source);
    assert_eq!(trace.rows.len(),1);
    assert_eq!(trace.rows[0]["selectedRows"][0][0]["text"],"移動中");
    assert_eq!(trace.rows[0]["selectedRows"][0][0]["foreground"],serde_json::json!([0,255,0]));
  }

  #[test]
  fn trace_retains_context_and_updates_a_changed_selection() {
    let mut trace = TraceBuffer::default();
    for (screen,x,selected) in [("menu",0,"Moving"),("dungeon",0,"移動中"),("dungeon",1,"移動中")] {
      trace.record(serde_json::json!({"text":"Moving","x":x,"y":2,"screen":screen,"selectedRows":selected}));
    }
    trace.record(serde_json::json!({"text":"Moving","x":0,"y":2,"screen":"dungeon","selectedRows":"移動"}));
    assert_eq!(trace.rows.len(),3);
    assert_eq!(trace.rows[0]["selectedRows"],"Moving");
    assert_eq!(trace.rows[1]["selectedRows"],"移動");
    assert_eq!(trace.rows[2]["x"],1);
  }

  #[test]
  fn trace_does_not_hide_an_english_first_selection_after_a_late_translation() {
    let mut trace = TraceBuffer::default();
    trace.record(serde_json::json!({"text":"Moving","x":0,"y":2,"screen":"dungeon","selectedRows":"Moving"}));
    trace.record(serde_json::json!({"text":"Moving","x":0,"y":2,"screen":"dungeon","selectedRows":"移動中"}));
    assert_eq!(trace.rows[0]["selectedRows"],"移動中");
    assert_eq!(trace.rows[0]["firstSelectedRows"],"Moving");
    assert_eq!(trace.rows[0]["selectionChanged"],true);
  }

  #[test]
  fn trace_reports_overflow_without_growing_or_truncating_unicode() {
    let mut trace = TraceBuffer::default();
    for x in 0..513 {
      trace.record(serde_json::json!({"text":"𠮷","x":x,"y":2,"screen":"dungeon"}));
    }
    assert_eq!(trace.rows.len(),512);
    assert_eq!(trace.rows[0]["text"],"𠮷");
    assert!(trace.incomplete);
    let mut large = TraceBuffer::default();
    large.record(serde_json::json!({"text":"𠮷".repeat(65536),"x":0,"y":0,"screen":"dungeon"}));
    assert!(large.rows.is_empty());
    assert!(large.incomplete);
  }
}
