use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use pinyin::ToPinyinMulti;

const QUERY_CAPACITY: usize = 64;
const PRONUNCIATION_VARIANTS: usize = 4;
static VARIANTS: OnceLock<RwLock<HashMap<char, char>>> = OnceLock::new();
fn variants() -> &'static RwLock<HashMap<char, char>> { VARIANTS.get_or_init(|| RwLock::new(HashMap::new())) }

pub fn normalize(text: &str) -> String {
  if text.is_ascii() { return text.to_ascii_lowercase(); }
  let variants=variants().read().unwrap();
  crate::chinese::simplified(text).chars().map(|character| match character {
    '巖'=>'岩','臺'|'檯'=>'台',other=>*variants.get(&other).unwrap_or(&other),
  }).flat_map(char::to_lowercase).collect()
}

pub fn install_variants(map: HashMap<char,char>) {
  *variants().write().unwrap()=map;
  query_cache().lock().unwrap().clear();
}

fn latin_query(text: &str) -> Option<String> {
  let mut result=String::new();
  for character in text.chars().flat_map(char::to_lowercase) {
    let character=match character {
      'ā'|'á'|'ǎ'|'à'=>'a','ē'|'é'|'ě'|'è'=>'e','ī'|'í'|'ǐ'|'ì'=>'i',
      'ō'|'ó'|'ǒ'|'ò'=>'o','ū'|'ú'|'ǔ'|'ù'=>'u','ü'|'ǖ'|'ǘ'|'ǚ'|'ǜ'=>'v',
      '1'..='5'|'\''=>continue,other=>other,
    };
    if !character.is_ascii_alphabetic() { return None; }
    result.push(character);
  }
  (result.len()>=2).then_some(result)
}

pub struct Token { pub text: String, pub phonetic: Option<String> }
#[derive(Default)]
struct QueryCache { rows: HashMap<String,Arc<Vec<Token>>>, order: VecDeque<String> }
impl QueryCache { fn clear(&mut self) { self.rows.clear();self.order.clear(); } }
static QUERIES: OnceLock<Mutex<QueryCache>>=OnceLock::new();
fn query_cache() -> &'static Mutex<QueryCache> { QUERIES.get_or_init(|| Mutex::new(QueryCache::default())) }
pub fn query(text: &str) -> Arc<Vec<Token>> {
  let mut cache=query_cache().lock().unwrap();
  if let Some(found)=cache.rows.get(text) { return found.clone(); }
  let tokens: Arc<Vec<Token>>=Arc::new(text.split_whitespace().map(|token| Token {
    text:normalize(token),phonetic:latin_query(token),
  }).collect());
  if cache.rows.len()==QUERY_CAPACITY {
    if let Some(old)=cache.order.pop_front() { cache.rows.remove(&old); }
  }
  cache.order.push_back(text.into());cache.rows.insert(text.into(),tokens.clone());tokens
}

#[derive(Default,Clone)]
struct Pronunciation { full: String, initials: String }
fn pronounce(text: &str) -> Vec<Pronunciation> {
  let mut rows=vec![Pronunciation::default()];
  for character in text.chars() {
    if let Some(readings)=character.to_pinyin_multi() {
      let readings: Vec<_>=readings.into_iter().map(|reading| reading.plain()).collect();
      let previous=rows.clone();rows.clear();
      for reading in readings {
        for prefix in &previous {
          let mut row=prefix.clone();
          row.full.extend(reading.chars().map(|character| if character=='ü' {'v'} else {character}));
          if let Some(initial)=reading.chars().next() { row.initials.push(initial); }
          if !rows.iter().any(|old: &Pronunciation| old.full==row.full) { rows.push(row); }
          if rows.len()==PRONUNCIATION_VARIANTS { break; }
        }
        if rows.len()==PRONUNCIATION_VARIANTS { break; }
      }
    } else if character.is_alphanumeric() {
      for row in &mut rows {
        row.full.push(character);
        if character.is_ascii_alphanumeric() { row.initials.push(character); }
      }
    }
  }
  rows
}

pub struct PreparedText { text: String, phonetic: OnceLock<Vec<Pronunciation>> }
impl PreparedText {
  pub fn new(text: &str) -> Self { Self {text:normalize(text),phonetic:OnceLock::new()} }
  pub fn matches(&self, token: &Token, pinyin_enabled: bool) -> bool {
    self.text.contains(&token.text) || pinyin_enabled && token.phonetic.as_ref().is_some_and(|query|
      self.phonetic.get_or_init(|| pronounce(&self.text)).iter().any(|row|
        row.full.contains(query) || row.initials.contains(query)))
  }
}

#[cfg(test)]
mod variant_tests {
  use super::*;
  #[test]
  fn traditional_and_simplified_search_use_the_same_key() {
    assert_eq!(normalize("鐵製高腳杯與花崗岩"),normalize("铁制高脚杯与花岗岩"));
    assert_eq!(normalize("繁體中文搜尋"),normalize("繁体中文搜寻"));
  }
}
