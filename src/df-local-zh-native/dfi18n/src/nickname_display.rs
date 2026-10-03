//! Small, temporary bindings for the visible unit's nickname headers.
//! Nicknames remain literal; Lua supplies only independently localized suffixes.
use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};
use std::time::{Duration, Instant};
use serde::Deserialize;
use crate::translation::TranslationResponse;

#[derive(Deserialize)]
struct Row { source: String, translation: String }
#[derive(Default)]
struct Headers {
  world: String,
  language: String,
  updated: Option<Instant>,
  rows: HashMap<String, String>,
}
impl Headers {
  fn replace(&mut self, world: String, language: String, rows: Vec<Row>) -> bool {
    if rows.len()>8 || world.len()>2000 || !matches!(language.as_str(),"zh-Hant"|"zh-Hans") {return false}
    let mut next=HashMap::new();
    for row in rows {
      if row.source.len()>1024 || row.translation.len()>2048 || !row.source.contains('`') ||
        row.source.contains(['\0','\n','\r']) || row.translation.contains(['\0','\n','\r']) ||
        row.translation.is_empty() || next.insert(row.source,row.translation).is_some() {return false}
    }
    self.world=world;self.language=language;self.rows=next;self.updated=Some(Instant::now());true
  }
  fn lookup(&self, source: &str, world: &str, language: &str) -> Option<TranslationResponse> {
    if self.world!=world || self.language!=language || self.updated?.elapsed()>Duration::from_secs(5) {return None}
    Some(TranslationResponse{translated:self.rows.get(source)?.clone(),alignment:Default::default()})
  }
}
static HEADERS: OnceLock<RwLock<Headers>>=OnceLock::new();
pub fn lookup(source:&str,language:&str)->Option<TranslationResponse> {
  if !source.contains('`') || source.len()>1024 {return None}
  HEADERS.get()?.read().unwrap().lookup(source,&crate::native_cache::current_world(),language)
}
#[unsafe(no_mangle)]
extern "C" fn native_nickname_rows_set(state:*mut std::ffi::c_void)->i32 {
  let text=lua53_sys::check_string(state,1);
  let ok=text.len()<=32768 && serde_json::from_str::<Vec<Row>>(&text).is_ok_and(|rows|
    HEADERS.get_or_init(||RwLock::new(Headers::default())).write().unwrap()
      .replace(crate::native_cache::current_world(),crate::lang::current_lang_tag(),rows));
  lua53_sys::push_boolean(state,ok);1
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn headers_are_exact_scoped_bounded_and_expiring() {
    let mut headers=Headers::default();
    let source="`鐵𠮷 A1' Surname, Mason";
    let value="`鐵𠮷 A1' 姓氏, 石匠";
    let row=||Row{source:source.into(),translation:value.into()};
    assert!(headers.replace("one".into(),"zh-Hant".into(),vec![row()]));
    assert_eq!(headers.lookup(source,"one","zh-Hant").unwrap().translated,value);
    assert!(headers.lookup(source,"two","zh-Hant").is_none());
    assert!(headers.lookup(source,"one","zh-Hans").is_none());
    assert!(headers.lookup("`other' Surname, Mason","one","zh-Hant").is_none());
    assert!(!headers.replace("one".into(),"zh-Hant".into(),vec![row(),row()]));
    assert!(!headers.replace("one".into(),"zh-Hant".into(),(0..9).map(|_|row()).collect()));
    headers.updated=Some(Instant::now()-Duration::from_secs(6));
    assert!(headers.lookup(source,"one","zh-Hant").is_none());
    assert!(headers.replace("one".into(),"zh-Hant".into(),vec![]));
    assert!(headers.lookup(source,"one","zh-Hant").is_none());
  }
}
