use std::collections::{HashMap, VecDeque};
use std::sync::{Mutex, OnceLock};
use ferrous_opencc::{OpenCC, config::BuiltinConfig};

const CAPACITY: usize = 2048;
static CONVERTER: OnceLock<OpenCC> = OnceLock::new();
#[derive(Default)]
struct Cache { rows: HashMap<String,String>, order: VecDeque<String> }
static CACHE: OnceLock<Mutex<Cache>> = OnceLock::new();

pub fn setup() {
  CONVERTER.get_or_init(|| OpenCC::from_config(BuiltinConfig::Tw2s).expect("embedded OpenCC dictionaries"));
}
pub fn simplified(text: &str) -> String {
  if text.is_ascii() { return text.to_owned(); }
  let cache=CACHE.get_or_init(|| Mutex::new(Cache::default()));
  if let Some(value)=cache.lock().unwrap().rows.get(text) { return value.clone(); }
  setup();
  let value=CONVERTER.get().unwrap().convert(text);
  if text.len()<=24000 {
    let mut cache=cache.lock().unwrap();
    if !cache.rows.contains_key(text) {
      if cache.rows.len()==CAPACITY {
        if let Some(old)=cache.order.pop_front() { cache.rows.remove(&old); }
      }
      cache.order.push_back(text.into());cache.rows.insert(text.into(),value.clone());
    }
  }
  value
}
pub fn localized(text: &str, language: &str) -> String {
  if language=="zh-Hans" { simplified(text) } else { text.into() }
}
pub fn direct(text: &str, language: &str) -> Option<crate::translation::TranslationResponse> {
  if !text.chars().any(|c| matches!(c,'\u{3400}'..='\u{9fff}'|'\u{20000}'..='\u{2ffff}')) { return None; }
  Some(crate::translation::TranslationResponse {translated:localized(text,language),alignment:Default::default()})
}
#[unsafe(no_mangle)]
extern "C" fn localize_text(state: *mut std::ffi::c_void) -> i32 {
  let value=lua53_sys::check_string(state,1);
  lua53_sys::push_string(state,&localized(&value,&crate::lang::current_lang_tag()));1
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn dynamic_conversion_preserves_colors_and_tokens() {
    let text="[C:6:1:1]鐵製高腳杯[B]{DWARF_NAME} 的記憶 123";
    assert_eq!(localized(text,"zh-Hans"),"[C:6:1:1]铁制高脚杯[B]{DWARF_NAME} 的记忆 123");
    assert_eq!(localized(text,"zh-Hant"),text);
    assert!(direct("An unknown paragraph.","zh-Hans").is_none());
  }
}
