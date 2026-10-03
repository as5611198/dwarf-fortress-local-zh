use std::collections::{HashMap, VecDeque};
use df_local_zh_broker::bounded::BoundedMap;
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::ffi::{c_char,c_void,CString};
use crate::{lang,native_cache,translation};
use crate::search_text::{self, PreparedText};

const MEMO_CAPACITY: usize=2048;
const MEMO_TEXT_LIMIT: usize=512;
static PINYIN_ENABLED: AtomicBool=AtomicBool::new(true);
#[derive(Default)]
struct SearchMemo {
  worlds: HashMap<String,HashMap<String,Arc<PreparedText>>>,
  order: VecDeque<(String,String)>,
  count: usize, hits: usize, builds: usize,
}
impl SearchMemo {
  fn clear(&mut self) { self.worlds.clear();self.order.clear();self.count=0; }
  fn remove(&mut self, world: &str, source: &str) {
    if self.worlds.get_mut(world).is_some_and(|rows| rows.remove(source).is_some()) { self.count-=1; }
    self.order.retain(|(old_world,old_source)| old_world!=world || old_source!=source);
  }
  fn get(&mut self, world: &str, source: &str) -> Option<Arc<PreparedText>> {
    let result=self.worlds.get(world)?.get(source)?.clone();self.hits+=1;Some(result)
  }
  fn insert(&mut self, world: &str, source: &str, text: Arc<PreparedText>) {
    if self.worlds.get(world).is_some_and(|rows| rows.contains_key(source)) { return; }
    if self.count==MEMO_CAPACITY {
      if let Some((old_world,old_source))=self.order.pop_front() {
        if let Some(rows)=self.worlds.get_mut(&old_world) {
          if rows.remove(&old_source).is_some() { self.count-=1; }
          if rows.is_empty() { self.worlds.remove(&old_world); }
        }
      }
    }
    self.worlds.entry(world.into()).or_default().insert(source.into(),text);
    self.order.push_back((world.into(),source.into()));self.count+=1;
  }
}

#[derive(Default)]
struct Node { children: HashMap<u8,usize>, values: Vec<String> }

#[derive(Default)]
struct SearchIndex {
  literals: HashMap<String, String>,
  aliases: HashMap<String, Vec<String>>,
  completed: BoundedMap<(String, String), String>,
  preloaded: HashMap<(String, String), (String, Option<String>)>,
  nodes: Vec<Node>,
  memo: Mutex<SearchMemo>,
}

impl SearchIndex {
  fn literal(&mut self, source: &str, translated: &str) {
    self.publish_literal(source,translated,true);
  }
  fn alias(&mut self, source: &str, translated: &str) {
    self.publish_literal(source,translated,false);
  }
  fn publish_literal(&mut self, source: &str, translated: &str, authoritative: bool) {
    if source.is_empty() || source.len()>8000 || translated.is_empty() { return; }
    self.memo.get_mut().unwrap().clear();
    let source=clean(source).to_lowercase();
    let translated=clean(translated);
    if authoritative { self.literals.insert(source.clone(),translated.clone()); }
    else {
      let values=self.aliases.entry(source.clone()).or_default();
      if !values.contains(&translated) { values.push(translated.clone()); }
    }
    if source.len()>128 { return; }
    if self.nodes.is_empty() { self.nodes.push(Node::default()); }
    let mut node=0;
    for byte in source.bytes() {
      node=if let Some(next)=self.nodes[node].children.get(&byte) { *next } else {
        let next=self.nodes.len(); self.nodes.push(Node::default());
        self.nodes[node].children.insert(byte,next);next
      };
    }
    self.nodes[node].values=if let Some(text)=self.literals.get(&source) { vec![text.clone()] }
      else { self.aliases.get(&source).cloned().unwrap_or_default() };
  }
  fn complete(&mut self, world: &str, source: &str, translated: &str) {
    let source=clean(source).to_lowercase();
    self.memo.get_mut().unwrap().remove(world,&source);
    self.completed.insert((world.into(), source), clean(translated));
  }
  fn localized(&self, world: &str, source: &str) -> String {
    if let Some(text)=self.literals.get(source) { return text.clone(); }
    let key=(world.into(),source.into());
    let completed=self.completed.get(&key);
    if let Some((text,baseline))=self.preloaded.get(&key) {
      if completed==baseline.as_ref() { return text.clone(); }
    }
    if let Some(text)=completed { return text.clone(); }
    if let Some(text)=self.aliases.get(source) { return text.join(""); }
    let mut result=String::new();
    let bytes=source.as_bytes();
    let mut position=0;
    while position<bytes.len() {
      let mut best=None;
      if !self.nodes.is_empty() && (position==0 || !word(bytes[position-1])) {
        let mut node=0;
        for end in position..bytes.len().min(position+128) {
          let Some(next)=self.nodes[node].children.get(&bytes[end]) else { break };
          node=*next;
          if !self.nodes[node].values.is_empty() && (end+1==bytes.len() || !word(bytes[end+1])) {
            best=Some((end+1,node));
          }
        }
      }
      if let Some((end,node))=best { result.push_str(&self.nodes[node].values.join(""));position=end; }
      else {
        let character=source[position..].chars().next().unwrap();
        result.push(character);position+=character.len_utf8();
      }
    }
    result
  }
  fn matches(&self, world: &str, source: &str, query: &str) -> bool {
    if source.len()>8000 || query.len()>512 { return false; }
    let tokens=search_text::query(query);
    let source=clean(source).to_lowercase();
    if tokens.iter().all(|token| source.contains(&token.text)) { return true; }
    let cached=self.memo.lock().unwrap().get(world,&source);
    let translated=if let Some(found)=cached { found } else {
      let text=self.localized(world,&source);
      let prepared=Arc::new(PreparedText::new(&text));
      let mut memo=self.memo.lock().unwrap();memo.builds+=1;
      if source.len()<=MEMO_TEXT_LIMIT && text.len()<=MEMO_TEXT_LIMIT { memo.insert(world,&source,prepared.clone()); }
      prepared
    };
    tokens.iter().all(|token| source.contains(&token.text) || translated.matches(token,PINYIN_ENABLED.load(Ordering::Relaxed)))
  }
}

fn word(byte: u8) -> bool { byte.is_ascii_alphanumeric() || byte==b'_' || byte>=128 }
fn clean(text: &str) -> String {
  if !text.contains('[') { return text.to_owned(); }
  static TAGS: OnceLock<regex::Regex>=OnceLock::new();
  TAGS.get_or_init(|| regex::Regex::new(r"\[[^\[\]]+\]").unwrap()).replace_all(text,"").into_owned()
}
static INDEX: OnceLock<RwLock<HashMap<String,SearchIndex>>>=OnceLock::new();
fn indices() -> &'static RwLock<HashMap<String,SearchIndex>> { INDEX.get_or_init(|| RwLock::new(HashMap::new())) }
pub fn literals(language: &str, rows: impl IntoIterator<Item=(String,String)>) {
  let mut indices=indices().write().unwrap();let index=indices.entry(language.into()).or_default();
  for (source,text) in rows { index.literal(&source,&text); }
}
pub fn aliases(language: &str, rows: impl IntoIterator<Item=(String,String)>) {
  let mut indices=indices().write().unwrap();let index=indices.entry(language.into()).or_default();
  for (source,text) in rows { index.alias(&source,&text); }
}
pub fn completed(world: &str, language: &str, source: &str, translated: &str) {
  indices().write().unwrap().entry(language.into()).or_default().complete(world,source,translated);
}
pub(crate) fn preloaded_batch(world:&str,language:&str,rows:impl IntoIterator<Item=(String,String,Option<String>)>) {
  let mut indices=indices().write().unwrap();let index=indices.entry(language.into()).or_default();
  for (source,text,baseline) in rows {
    let source=clean(&source).to_lowercase();
    index.memo.get_mut().unwrap().remove(world,&source);
    index.preloaded.insert((world.into(),source),(clean(&text),baseline.map(|text|clean(&text))));
  }
}
pub fn matches(source: &str, query: &str) -> bool {
  let language=lang::current_lang_tag();let world=native_cache::current_world();
  indices().read().unwrap().get(&language).is_some_and(|index| index.matches(&world,source,query))
}
static QUERIES: OnceLock<RwLock<HashMap<String,String>>>=OnceLock::new();
static QUERY_COUNT: AtomicUsize=AtomicUsize::new(0);
static COMPARISONS: AtomicUsize=AtomicUsize::new(0);
static MATCHES: AtomicUsize=AtomicUsize::new(0);
fn queries() -> &'static RwLock<HashMap<String,String>> { QUERIES.get_or_init(|| RwLock::new(HashMap::new())) }
pub fn display_query(source: &str) -> Option<translation::TranslationResponse> {
  if QUERY_COUNT.load(Ordering::Relaxed)==0 || !(source.contains("LZHS") || source.contains("lzhs")) { return None; }
  static HANDLES: OnceLock<regex::Regex>=OnceLock::new();
  let pattern=HANDLES.get_or_init(|| regex::Regex::new(r"(?i)lzhs[0-9]{3}___").unwrap());
  let queries=queries().read().unwrap();
  let mut changed=false;
  let text=pattern.replace_all(source,|capture: &regex::Captures| {
    queries.get(&capture[0].to_ascii_lowercase()).map(|query| { changed=true;query.clone() }).unwrap_or_else(|| capture[0].to_owned())
  });
  changed.then_some(translation::TranslationResponse {translated:text.into_owned(),alignment:translation::TextAlignment::Left})
}
#[unsafe(no_mangle)]
extern "C" fn search_columns(state: *mut c_void) -> i32 {
  let text=lua53_sys::check_string(state,1);
  if text.len()>512 { lua53_sys::push_integer(state,0);return 1; }
  static WIDTHS:OnceLock<RwLock<BoundedMap<(String,i32,i32,String),usize>>>=OnceLock::new();
  let size=crate::df::renderer::get_renderer_info().orig_size();
  let key=(crate::lang::current_lang_tag(),size.width,size.height,text.clone());
  let widths=WIDTHS.get_or_init(||RwLock::new(BoundedMap::new(512)));
  if let Some(columns)=widths.read().unwrap().get(&key) {lua53_sys::push_integer(state,*columns as isize);return 1;}
  let mut row=crate::text::TextRow::new(crate::types::ColorPair::default());
  row.push_text(text);
  let columns=row.columns();widths.write().unwrap().insert(key,columns);
  lua53_sys::push_integer(state,columns as isize);1
}
#[unsafe(no_mangle)]
extern "C" fn search_set_query(state: *mut c_void) -> i32 {
  let slot=lua53_sys::check_integer(state,1);
  let query=lua53_sys::check_string(state,2);
  if !(0..128).contains(&slot) || query.len()>512 || query.contains('\0') { lua53_sys::push_nil(state);return 1; }
  let token=format!("lzhs{slot:03}___");
  let mut queries=queries().write().unwrap();
  if query.is_empty() { queries.remove(&token); } else { queries.insert(token.clone(),query.clone()); }
  QUERY_COUNT.store(queries.len(),Ordering::Relaxed);
  let token=if query.is_empty() {String::new()} else {token.to_uppercase()};
  lua53_sys::push_string(state,&token);1
}
#[unsafe(no_mangle)]
extern "C" fn search_clear() -> i32 { queries().write().unwrap().clear();QUERY_COUNT.store(0,Ordering::Relaxed);0 }
#[unsafe(no_mangle)]
extern "C" fn search_matches(state: *mut c_void) -> i32 {
  let source=lua53_sys::check_string(state,1);let query=lua53_sys::check_string(state,2);
  lua53_sys::push_boolean(state,matches(&source,&query));1
}
#[unsafe(no_mangle)]
extern "C" fn search_metrics(state: *mut c_void) -> i32 {
  lua53_sys::push_integer(state,COMPARISONS.load(Ordering::Relaxed) as isize);
  lua53_sys::push_integer(state,MATCHES.load(Ordering::Relaxed) as isize);2
}
#[unsafe(no_mangle)]
extern "C" fn search_cache_metrics(state: *mut c_void) -> i32 {
  let language=lang::current_lang_tag();let indices=indices().read().unwrap();
  let (count,hits,builds)=indices.get(&language).map(|index| {
    let memo=index.memo.lock().unwrap();(memo.count,memo.hits,memo.builds)
  }).unwrap_or_default();
  for value in [count,hits,builds] { lua53_sys::push_integer(state,value as isize); } 3
}
#[unsafe(no_mangle)]
extern "C" fn search_pinyin_enable(state: *mut c_void) -> i32 {
  PINYIN_ENABLED.store(lua53_sys::check_integer(state,1)!=0,Ordering::Relaxed);0
}
#[unsafe(no_mangle)]
extern "C" fn search_load_normalization(state: *mut c_void) -> i32 {
  let path=lua53_sys::check_string(state,1);
  let result=(|| -> anyhow::Result<()> {
    let map=serde_json::from_str(&std::fs::read_to_string(path)?)?;
    search_text::install_variants(map);
    for index in indices().write().unwrap().values_mut() { index.memo.get_mut().unwrap().clear(); }
    Ok(())
  })();
  match result {
    Ok(())=>{lua53_sys::push_boolean(state,true);lua53_sys::push_nil(state);},
    Err(error)=>{lua53_sys::push_boolean(state,false);lua53_sys::push_string(state,&error.to_string());},
  } 2
}
// MSVC's bounded string find, verified against the live 53.16 call stack.
// Only our registered handles change its result; all ordinary queries forward.
fn search_find(haystack: *const c_char,length: usize,position: usize,needle: *const c_char,needle_length: usize) -> usize {
  if QUERY_COUNT.load(Ordering::Relaxed)!=0 && needle_length>=10 && needle_length<=12 &&
      !needle.is_null() && !haystack.is_null() && unsafe { *needle==b'L' as c_char || *needle==b'l' as c_char } {
    let bytes=unsafe { std::slice::from_raw_parts(needle as *const u8,needle_length) };
    if let Ok(needle)=std::str::from_utf8(bytes) {
      let query=queries().read().unwrap().get(&needle.trim().to_lowercase()).cloned();
      if let Some(query)=query {
        COMPARISONS.fetch_add(1,Ordering::Relaxed);
        if position!=0 || length>8000 { return usize::MAX; }
        let bytes=unsafe { std::slice::from_raw_parts(haystack as *const u8,length) };
        let source=if bytes.is_ascii() { String::from_utf8_lossy(bytes).into_owned() }
          else if let Ok(value)=CString::new(bytes) { cp437_string::c_string_to_string(value.as_ptr()) }
          else { return usize::MAX; };
        if matches(&source,&query) { MATCHES.fetch_add(1,Ordering::Relaxed);return 0; }
        return usize::MAX;
      }
    }
  }
  call_search_find(haystack,length,position,needle,needle_length)
}
macros::hook! { fn search_find(haystack: *const c_char,length: usize,position: usize,needle: *const c_char,needle_length: usize) -> usize; }
pub fn attach() -> anyhow::Result<()> {
  #[cfg(windows)]
  attach_search_find(crate::memory::get_raw_pointer_by_key("search_find")?)?;
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  fn index() -> SearchIndex {
    let mut index=SearchIndex::default();
    for (source,translated) in [("iron","鐵"),("magnetite","磁鐵礦"),("goblet","高腳杯"),
      ("goblets","高腳杯"),("granite","花崗岩"),("blocks","方塊")] {
      index.literal(source,translated);
    }
    index
  }
  #[test]
  fn model_completion_wins_over_a_late_preload_search_batch() {
    let language="preload-search-fixture";
    completed("one",language,"Fixture label","模型新譯文");
    preloaded_batch("one",language,[("Fixture label".into(),"快取舊譯文".into(),None)]);
    let guard=indices().read().unwrap();
    assert_eq!(guard[language].localized("one","fixture label"),"模型新譯文");
    drop(guard);
    preloaded_batch("one",language,[("Second label".into(),"快取譯文".into(),None)]);
    assert_eq!(indices().read().unwrap()[language].localized("one","second label"),"快取譯文");
    completed("one",language,"Second label","最新譯文");
    assert_eq!(indices().read().unwrap()[language].localized("one","second label"),"最新譯文");
  }
  #[test]
  fn chinese_query_matches_localized_compound_names_and_ore() {
    let index=index();
    assert!(index.matches("world","Iron Goblet","鐵"));
    assert!(index.matches("world","magnetite blocks","鐵"));
    assert!(index.matches("world","iron goblet","高腳杯"));
    assert!(index.matches("world","granite blocks","花崗岩"));
    assert!(!index.matches("world","iron goblet","花崗岩"));
    assert!(!index.matches("world","ironic goblet","鐵"));
  }
  #[test]
  fn queries_keep_all_tokens_and_english_search() {
    let index=index();
    assert!(index.matches("world","Iron Goblet","鐵 高腳杯"));
    assert!(index.matches("world","Iron Goblet","IRON goblet"));
    assert!(!index.matches("world","granite blocks","鐵 高腳杯"));
  }
  #[test]
  fn completed_display_text_wins_and_is_world_scoped() {
    let mut index=index();
    index.complete("one","The Violet Wonder","紫色奇蹟");
    assert!(index.matches("one","the violet wonder","奇蹟"));
    assert!(!index.matches("two","the violet wonder","奇蹟"));
    index.complete("one","The Violet Wonder","紫色寶物");
    assert!(!index.matches("one","the violet wonder","奇蹟"));
    assert!(index.matches("one","the violet wonder","寶物"));
  }
  #[test]
  fn dictionary_corrections_replace_stale_cache_and_compound_terms() {
    let mut index=index();
    index.complete("world","goblet","酒杯");
    index.alias("goblet","杯子");
    assert!(index.matches("world","goblet","高腳杯"));
    assert!(!index.matches("world","goblet","酒杯"));
    index.literal("goblet","高足杯");
    assert!(index.matches("world","iron goblet","高足杯"));
    assert!(!index.matches("world","iron goblet","高腳杯"));
    assert!(!index.matches("world","iron goblet","杯子"));
  }
  #[test]
  fn traditional_variant_forms_match_persisted_display_names() {
    let mut index=index();
    index.complete("world","granite blocks","[C:7:0:0]花崗巖塊");
    assert!(index.matches("world","granite blocks","花崗岩"));
    assert!(index.matches("world","granite blocks","花崗巖"));
    assert!(!index.matches("world","granite blocks","鐵"));
  }

  #[test]
  fn mainland_pinyin_and_initials_match_known_local_text() {
    let index=index();
    for query in ["tie", "gaojiaobei", "gao jiao bei", "gjb", "gao1jiao3bei1", "gāojiǎobēi", "tiegaojiaobei"] {
      assert!(index.matches("world","iron goblet",query),"Pinyin query: {query}");
    }
    assert!(index.matches("world","granite blocks","huagangyan"));
    assert!(index.matches("world","granite blocks","hgy"));
    assert!(!index.matches("world","iron goblet","huagangyan"));
  }

  #[test]
  fn pinyin_keeps_english_matching_and_invalidates_retranslated_text() {
    let mut index=index();
    assert!(index.matches("world","iron goblet","IRON"));
    assert!(index.matches("world","iron goblet","tie goblet"));
    index.complete("one","A named object","花崗岩");
    assert!(index.matches("one","a named object","huagangyan"));
    assert!(!index.matches("two","a named object","huagangyan"));
    index.complete("one","A named object","鐵製高腳杯");
    assert!(!index.matches("one","a named object","huagangyan"));
    assert!(index.matches("one","a named object","gaojiaobei"));
  }

  #[test]
  fn repeated_searches_reuse_bounded_text_and_rebuild_after_a_dictionary_correction() {
    let mut index=index();
    for _ in 0..100 { assert!(index.matches("world","iron goblet","gaojiaobei")); }
    {
      let memo=index.memo.lock().unwrap();
      assert_eq!(memo.builds,1);assert_eq!(memo.hits,99);assert_eq!(memo.count,1);
    }
    index.literal("goblet","酒杯");
    assert!(!index.matches("world","iron goblet","gaojiaobei"));
    assert!(index.matches("world","iron goblet","jiubei"));
    for id in 0..MEMO_CAPACITY+32 { let _=index.matches("world",&format!("iron goblet {id}"),"tie"); }
    assert_eq!(index.memo.lock().unwrap().count,MEMO_CAPACITY);
  }
}
