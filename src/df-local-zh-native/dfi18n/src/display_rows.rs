//! Ephemeral display bindings, never persisted or merged into global dictionaries.
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};
use std::sync::atomic::{AtomicU64,Ordering};
use std::time::{Duration, Instant};

#[derive(Clone, Deserialize)]
pub(crate) struct Row {
  address: usize,
  source: String,
  pub translation: String,
  pub width: usize,
  #[serde(skip)]
  pub literal: bool,
}
#[derive(Default)]
struct Bindings {
  world: String,
  language: String,
  updated: Option<Instant>,
  rows: HashMap<usize, Row>,
  layout: Vec<(String,String,usize)>,
  positions: HashMap<crate::types::Coordinate,Row>,
}
impl Bindings {
  fn replace_literals(&mut self,world:String,language:String,rows:Vec<Row>)->bool {
    if rows.len()>2048 || world.len()>2000 || !matches!(language.as_str(),"zh-Hant"|"zh-Hans") {return false}
    let mut next=HashMap::new();
    for mut row in rows {
      if row.address==0 || row.source.is_empty() || row.source.len()>1000 ||
        !row.source.bytes().all(|b| (32..=126).contains(&b)) ||
        row.translation!=row.source || row.width!=row.source.len() {return false}
      row.literal=true;
      if next.insert(row.address,row).is_some() {return false}
    }
    self.positions.clear();self.layout.clear();
    self.world=world;self.language=language;self.rows=next;self.updated=Some(Instant::now());
    true
  }
  fn lookup_at(&mut self,address:usize,source:&str,world:&str,language:&str,position:crate::types::Coordinate)->Option<Row> {
    if self.world!=world || self.language!=language || self.updated?.elapsed()>Duration::from_secs(5) {return None}
    let row=self.lookup(address,source,world,language).or_else(||self.positions.get(&position).filter(|row|row.source==source).cloned())?;
    // DF can reallocate the strings between the Lua poll and native drawing.
    // Retain the proven row position only while the complete layout is unchanged.
    self.positions.insert(position,row.clone());
    Some(row)
  }
  fn replace(&mut self, world: String, language: String, rows: Vec<Row>) -> bool {
    if rows.len()>256 || world.len()>2000 || !matches!(language.as_str(),"zh-Hant"|"zh-Hans") {return false}
    let mut next=HashMap::new();
    let layout=rows.iter().map(|row|(row.source.clone(),row.translation.clone(),row.width)).collect();
    for row in rows {
      if row.address==0 || row.source.len()>8000 || row.source.contains('\0') ||
        row.width==0 || row.width>1000 || row.translation.chars().count()*2>row.width ||
        row.translation.chars().any(|c|c.is_ascii_alphabetic() || c=='\0' || c=='\n' || c=='\r') ||
        next.insert(row.address,row).is_some() {return false}
    }
    if self.world!=world || self.language!=language || self.layout!=layout {self.positions.clear()}
    self.layout=layout;self.world=world;self.language=language;self.rows=next;self.updated=Some(Instant::now());
    true
  }
  fn lookup(&self, address: usize, source: &str, world: &str, language: &str) -> Option<Row> {
    if self.world!=world || self.language!=language || self.updated?.elapsed()>Duration::from_secs(5) {return None}
    self.rows.get(&address).filter(|row|row.source==source).cloned()
  }
}
static BINDINGS: OnceLock<RwLock<Bindings>> = OnceLock::new();
static HITS: AtomicU64 = AtomicU64::new(0);
static LITERALS: OnceLock<RwLock<Bindings>> = OnceLock::new();
static LITERAL_HITS: AtomicU64 = AtomicU64::new(0);

pub(crate) fn lookup(address:usize,source:&str,position:crate::types::Coordinate)->Option<Row> {
  // Literal labels are proven by the public std::string address AND source.
  // Never remember their screen position: unrelated text can occupy it later.
  if let Some(row)=LITERALS.get().and_then(|b|b.read().unwrap().lookup(address,source,
    &crate::native_cache::current_world(),&crate::lang::current_lang_tag())) {
    LITERAL_HITS.fetch_add(1,Ordering::Relaxed);return Some(row)
  }
  let row=BINDINGS.get()?.write().unwrap().lookup_at(address,source,&crate::native_cache::current_world(),&crate::lang::current_lang_tag(),position);
  if row.is_some() {HITS.fetch_add(1,Ordering::Relaxed);}
  row
}

#[unsafe(no_mangle)]
extern "C" fn native_literal_rows_set(state:*mut std::ffi::c_void)->i32 {
  let data=lua53_sys::check_string(state,1);
  let ok=data.len()<=1024*1024 && serde_json::from_str::<Vec<Row>>(&data).ok().is_some_and(|rows|
    LITERALS.get_or_init(||RwLock::new(Bindings::default())).write().unwrap()
      .replace_literals(crate::native_cache::current_world(),crate::lang::current_lang_tag(),rows));
  lua53_sys::push_boolean(state,ok);1
}

#[unsafe(no_mangle)]
extern "C" fn native_display_rows_set(state:*mut std::ffi::c_void)->i32 {
  let data=lua53_sys::check_string(state,1);
  let ok=data.len()<=1024*1024 && serde_json::from_str::<Vec<Row>>(&data).ok().is_some_and(|rows|
    BINDINGS.get_or_init(||RwLock::new(Bindings::default())).write().unwrap()
      .replace(crate::native_cache::current_world(),crate::lang::current_lang_tag(),rows));
  lua53_sys::push_boolean(state,ok);1
}

#[unsafe(no_mangle)]
extern "C" fn native_display_rows_status(state:*mut std::ffi::c_void)->i32 {
  let rows=BINDINGS.get().map(|b|b.read().unwrap().rows.len()).unwrap_or(0);
  let literal_rows=LITERALS.get().map(|b|b.read().unwrap().rows.len()).unwrap_or(0);
  lua53_sys::push_string(state,&serde_json::json!({"rows":rows,"draw_hits":HITS.load(Ordering::Relaxed),
    "literal_rows":literal_rows,"literal_draw_hits":LITERAL_HITS.load(Ordering::Relaxed)}).to_string());1
}

#[cfg(test)]
mod tests {
  use super::*;
  fn row(address:usize, source:&str, translated:&str)->Row {
    Row {address,source:source.into(),translation:translated.into(),width:54,literal:false}
  }
  #[test]
  fn binding_labels_keep_exact_text_and_do_not_allow_unrelated_translation() {
    let mut labels=Bindings::default();
    let rows=["Enter","Numpad Enter","Shift+Enter","Ctrl+Mwheel up","Leftbracket","Home","F11"]
      .iter().enumerate().map(|(i,s)|Row {address:i+100,source:(*s).into(),translation:(*s).into(),width:s.len(),literal:false}).collect();
    assert!(labels.replace_literals("world".into(),"zh-Hant".into(),rows));
    let hit=labels.lookup(100,"Enter","world","zh-Hant").unwrap();
    assert_eq!(hit.translation,"Enter");
    assert!(hit.literal);
    assert!(labels.lookup(900,"Enter","world","zh-Hant").is_none());
    assert!(labels.lookup(100,"Home","world","zh-Hant").is_none());
    assert!(labels.lookup(100,"Enter","other","zh-Hant").is_none());
    assert!(labels.lookup(100,"Enter","world","zh-Hans").is_none());
    assert!(!labels.replace_literals("world".into(),"zh-Hant".into(),vec![row(100,"Enter","回車")]));
    assert_eq!(labels.lookup(100,"Enter","world","zh-Hant").unwrap().translation,"Enter");
    assert!(!labels.replace_literals("world".into(),"zh-Hant".into(),vec![row(0,"Enter","Enter")]));
    assert!(labels.replace_literals("world".into(),"zh-Hans".into(),vec![]));
    assert!(labels.lookup(100,"Enter","world","zh-Hant").is_none());
  }
  #[test]
  fn binding_label_batch_supports_full_categories_and_rejects_controls() {
    let mut labels=Bindings::default();
    let rows=(1..=341).map(|address|Row {address,source:"Enter".into(),translation:"Enter".into(),width:5,literal:false}).collect();
    assert!(labels.replace_literals("world".into(),"zh-Hant".into(),rows));
    assert_eq!(labels.rows.len(),341);
    assert!(!labels.replace_literals("world".into(),"zh-Hant".into(),vec![row(1,"Enter\n","Enter\n")]));
    assert_eq!(labels.rows.len(),341);
    labels.updated=Some(Instant::now()-Duration::from_secs(6));
    assert!(labels.lookup(1,"Enter","world","zh-Hant").is_none());
  }
  #[test]
  fn reallocated_game_strings_do_not_expose_fragment_translation_between_polls() {
    let mut bindings=Bindings::default();
    let position=crate::types::Coordinate{column:86,row:10};
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![row(100,"It is spattered with ","它沾滿血跡。")]));
    assert_eq!(bindings.lookup_at(100,"It is spattered with ","arena","zh-Hant",position).unwrap().translation,"它沾滿血跡。");
    assert_eq!(bindings.lookup_at(200,"It is spattered with ","arena","zh-Hant",position).unwrap().translation,"它沾滿血跡。");
    assert!(bindings.lookup_at(200,"Another item", "arena","zh-Hant",position).is_none());
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![row(300,"It is spattered with ","它沾滿血跡。" )]));
    assert_eq!(bindings.lookup_at(400,"It is spattered with ","arena","zh-Hant",position).unwrap().translation,"它沾滿血跡。");
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![]));
    assert!(bindings.lookup_at(400,"It is spattered with ","arena","zh-Hant",position).is_none());
  }
  #[test]
  fn rebuilt_lines_keep_paragraph_choice_without_dictionary_writes() {
    let mut bindings=Bindings::default();
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![row(100,"It is spattered with ","它沾滿血跡。"),row(200,"kobold blood.","")]));
    for _ in 0..100 {
      assert_eq!(bindings.lookup(100,"It is spattered with ","arena","zh-Hant").unwrap().translation,"它沾滿血跡。");
      assert_eq!(bindings.lookup(200,"kobold blood.","arena","zh-Hant").unwrap().translation,"");
    }
    assert!(bindings.lookup(100,"Another item", "arena","zh-Hant").is_none());
    assert!(bindings.lookup(101,"It is spattered with ","arena","zh-Hant").is_none());
    assert!(bindings.lookup(100,"It is spattered with ","other","zh-Hant").is_none());
    assert!(bindings.lookup(100,"It is spattered with ","arena","zh-Hans").is_none());
    bindings.updated=Some(Instant::now()-Duration::from_secs(6));
    assert!(bindings.lookup(100,"It is spattered with ","arena","zh-Hant").is_none());
  }
  #[test]
  fn batches_are_atomic_bounded_and_clearable() {
    let mut bindings=Bindings::default();
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![row(100,"a","甲")]));
    assert!(!bindings.replace("arena".into(),"zh-Hant".into(),vec![row(100,"a","乙"),row(100,"b","丙")]));
    assert_eq!(bindings.lookup(100,"a","arena","zh-Hant").unwrap().translation,"甲");
    assert!(!bindings.replace("arena".into(),"zh-Hant".into(),vec![row(0,"a","甲")]));
    assert!(!bindings.replace("arena".into(),"zh-Hant".into(),vec![row(200,"a","English")]));
    assert!(bindings.replace("arena".into(),"zh-Hant".into(),vec![]));
    assert!(bindings.lookup(100,"a","arena","zh-Hant").is_none());
  }
}
