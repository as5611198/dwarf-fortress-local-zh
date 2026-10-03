use std::collections::HashSet;
use df_local_zh_broker::bounded::BoundedMap;
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock, RwLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

use crate::translation::{TextAlignment, TranslationRequest, TranslationResponse};

const POLICY: &str = "df-local-native-1";
const CAPACITY: usize = 64;
static ENABLED: AtomicBool = AtomicBool::new(true);
static COLOR_PERSISTENCE: AtomicBool = AtomicBool::new(true);

#[derive(Clone, Debug, Hash, Eq, PartialEq, Serialize, Deserialize)]
pub(crate) struct CacheKey {
  pub world: String,
  pub language: String,
  pub kind: String,
  pub original: String,
}

pub(crate) struct MemoryCache {
  ready: BoundedMap<CacheKey, TranslationResponse>,
  pending: HashSet<CacheKey>,
  misses: BoundedMap<CacheKey, Instant>,
}
impl Default for MemoryCache {
  fn default()->Self {Self{ready:BoundedMap::new(4096),pending:HashSet::new(),misses:BoundedMap::new(2048)}}
}

impl MemoryCache {
  pub fn lookup(&self, key: &CacheKey) -> Option<TranslationResponse> {
    self.ready.get(key).cloned()
  }

  pub fn begin(&mut self, key: &CacheKey) -> bool {
    if self.ready.contains_key(key) || self.pending.contains(key) || self.pending.len() >= CAPACITY ||
      self.misses.get(key).is_some_and(|time| time.elapsed() < Duration::from_secs(20)) {
      return false;
    }
    self.pending.insert(key.clone());
    true
  }

  pub fn complete(&mut self, key: CacheKey, response: Option<TranslationResponse>) {
    self.pending.remove(&key);
    if let Some(response) = response {
      self.misses.remove(&key);
      self.ready.insert(key, response);
    } else if !self.ready.contains_key(&key) {
      self.misses.insert(key, Instant::now());
    }
  }
}

static MEMORY: OnceLock<RwLock<MemoryCache>> = OnceLock::new();
static WORLD: OnceLock<RwLock<String>> = OnceLock::new();
static FILE_LOCK: Mutex<()> = Mutex::new(());
static STATE_PATH: OnceLock<PathBuf> = OnceLock::new();

fn memory() -> &'static RwLock<MemoryCache> {
  MEMORY.get_or_init(|| RwLock::new(MemoryCache::default()))
}

fn state_path() -> &'static PathBuf {
  STATE_PATH.get_or_init(|| PathBuf::from("dfhack-config/mods/df-local-zh-complete/data/native-cache-v1.jsonl"))
}

pub fn key(language: &str, request: &TranslationRequest) -> CacheKey {
  CacheKey {
    world: WORLD.get_or_init(|| RwLock::new(String::new())).read().unwrap().clone(),
    language: language.into(),
    kind: if request.is_markup() || request.original().contains("[C:") { "markup" } else { "plain" }.into(),
    original: request.original().into(),
  }
}

pub fn current_world() -> String { WORLD.get_or_init(|| RwLock::new(String::new())).read().unwrap().clone() }

// The replacement preload must compare against dynamic results, not its old snapshot.
pub(crate) fn dynamic_lookup(key: &CacheKey) -> Option<TranslationResponse> {
  memory().read().unwrap().lookup(key)
}

pub fn lookup(key: &CacheKey) -> Option<TranslationResponse> {
  let current=dynamic_lookup(key);
  if let Some(response)=crate::prewarm::lookup(key,current.as_ref()) {return Some(response)}
  if let Some(response)=current { return Some(response); }
  if key.language!="zh-Hans" { return None; }
  let traditional=CacheKey {language:"zh-Hant".into(),..key.clone()};
  let mut response=memory().read().unwrap().lookup(&traditional)?;
  response.translated=crate::chinese::simplified(&response.translated);
  // Conversion of a validated ready row needs neither a worker nor disk I/O.
  crate::search::completed(&key.world,&key.language,&key.original,&response.translated);
  memory().write().unwrap().complete(key.clone(),Some(response.clone()));
  Some(response)
}
pub fn begin(key: &CacheKey) -> bool { memory().write().unwrap().begin(key) }
pub(crate) struct PendingGuard(pub CacheKey);
impl Drop for PendingGuard {
  fn drop(&mut self) {
    // Cancellation/panic must release the dedup slot without doing disk I/O.
    let mut cache=memory().write().unwrap();
    if cache.pending.contains(&self.0) {cache.complete(self.0.clone(),None);}
  }
}

#[cfg(test)]
pub(crate) fn fixture_complete(key: CacheKey, response: TranslationResponse) {
  memory().write().unwrap().complete(key, Some(response));
}

pub fn complete(key: CacheKey, response: Option<TranslationResponse>) {
  if let Some(response)=&response { crate::search::completed(&key.world,&key.language,&key.original,&response.translated); }
  memory().write().unwrap().complete(key.clone(), response.clone());
  if ENABLED.load(Ordering::Relaxed) && (key.kind!="markup" || COLOR_PERSISTENCE.load(Ordering::Relaxed)) {
    if let Some(response) = response {
      if let Err(error) = persist(state_path(), &key, &response) { log::warn!("Native cache write: {error}"); }
    }
  }
}

#[derive(Serialize, Deserialize)]
struct SavedRow {
  version: u32,
  policy: String,
  key: CacheKey,
  response: TranslationResponse,
}

fn persist(path: &Path, key: &CacheKey, response: &TranslationResponse) -> anyhow::Result<()> {
  let _lock = FILE_LOCK.lock().unwrap();
  append_private(path, key, response)?;
  export_legacy(key, response)?;
  Ok(())
}

fn append_private(path: &Path, key: &CacheKey, response: &TranslationResponse) -> anyhow::Result<()> {
  if let Some(parent) = path.parent() { fs::create_dir_all(parent)?; }
  let row = SavedRow { version: 1, policy: POLICY.into(), key: key.clone(), response: response.clone() };
  let mut file = OpenOptions::new().create(true).append(true).open(path)?;
  // A leading newline separates a new row from an interrupted trailing write.
  file.write_all(b"\n")?;
  serde_json::to_writer(&mut file, &row)?;
  file.write_all(b"\n")?;
  Ok(())
}

fn restore(path: &Path, cache: &mut MemoryCache) -> anyhow::Result<usize> {
  let file = match fs::File::open(path) {
    Ok(file) => file,
    Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(0),
    Err(error) => return Err(error.into()),
  };
  let mut restored = 0;
  for line in BufReader::new(file).lines() {
    let line = line?;
    let Ok(row) = serde_json::from_str::<SavedRow>(&line) else { continue };
    if row.version == 1 && row.policy == POLICY && valid_translation(&row.key.original, &row.response.translated) {
      crate::search::completed(&row.key.world,&row.key.language,&row.key.original,&row.response.translated);
      cache.complete(row.key, Some(row.response));
      restored += 1;
    }
  }
  Ok(restored)
}

pub fn valid_translation(original: &str, translated: &str) -> bool {
  if let Some(inner)=df_local_zh_broker::common::braced_item(original) {
    return translated.strip_prefix('{').and_then(|s|s.strip_suffix('}'))
      .is_some_and(|text|valid_translation(inner,text));
  }
  if translated.is_empty() || translated.len() > 24000 || translated.contains('\0') { return false; }
  let tags = |text: &str| -> Vec<String> {
    static TAGS: OnceLock<regex::Regex> = OnceLock::new();
    TAGS.get_or_init(|| regex::Regex::new(r"\[[^\[\]]+\]|\{[^{}]+\}").unwrap())
      .find_iter(text).map(|m| m.as_str().to_owned()).collect()
  };
  if tags(original) != tags(translated) { return false; }
  static TOKENS: OnceLock<regex::Regex> = OnceLock::new();
  let stripped = TOKENS.get_or_init(|| regex::Regex::new(r"\[[^\[\]]+\]|\{[^{}]+\}").unwrap())
    .replace_all(translated, "");
  // Runtime palette aliases identify fragments; their identifiers are not display numbers.
  let plain_original = TOKENS.get().unwrap().replace_all(original, "");
  let is_alias = plain_original.len() >= 7 && plain_original.starts_with('L') &&
    plain_original.as_bytes()[1..7].iter().all(|c| c.is_ascii_alphanumeric()) && plain_original.as_bytes()[7..].iter().all(|c| *c == b'_');
  if !is_alias {
    static NUMBERS: OnceLock<regex::Regex> = OnceLock::new();
    let numbers = NUMBERS.get_or_init(|| regex::Regex::new(r"[0-9]+(?:[.,][0-9]+)*").unwrap());
    let mut before: Vec<_> = numbers.find_iter(&plain_original).map(|m| m.as_str()).collect();
    let mut after: Vec<_> = numbers.find_iter(&stripped).map(|m| m.as_str()).collect();
    before.sort_unstable(); after.sort_unstable();
    if before != after { return false; }
  }
  stripped.chars().any(|c| !c.is_ascii()) && !stripped.chars().any(|c| c.is_ascii_alphabetic())
}

#[derive(Serialize, Deserialize)]
struct LegacyRow {
  version: String,
  fingerprint: String,
  source: String,
  language: String,
  kind: String,
  rules_first: String,
  original: String,
  status: String,
  translation: String,
  alignment: String,
}

fn legacy_path() -> PathBuf { PathBuf::from("dfi18n-data/cache/translation-cache.csv") }

fn export_legacy(key: &CacheKey, response: &TranslationResponse) -> anyhow::Result<()> {
  let path = legacy_path();
  fs::create_dir_all(path.parent().unwrap())?;
  let header = !path.exists() || fs::metadata(&path)?.len() == 0;
  let mut writer = csv::WriterBuilder::new().has_headers(header)
    .from_writer(OpenOptions::new().create(true).append(true).open(path)?);
  writer.serialize(LegacyRow {
    version: "2".into(), fingerprint: POLICY.into(), source: "local".into(),
    language: key.language.clone(), kind: key.kind.clone(), rules_first: "false".into(),
    original: key.original.clone(), status: "translated".into(), translation: response.translated.clone(),
    alignment: match response.alignment { TextAlignment::Left => "left", TextAlignment::Center => "center", TextAlignment::Right => "right" }.into(),
  })?;
  writer.flush()?;
  Ok(())
}

fn import_legacy() -> anyhow::Result<usize> {
  let path = legacy_path();
  if !path.exists() { return Ok(0); }
  let rows = csv::Reader::from_path(path)?.deserialize::<LegacyRow>().collect::<Result<Vec<_>, _>>()?;
  let Some(fingerprint) = rows.iter().rev().find(|row| row.language == "zh-Hant").map(|row| row.fingerprint.clone()) else { return Ok(0) };
  let registry: serde_json::Value = fs::read_to_string("dfhack-config/mods/df-local-zh-complete/data/world-names.json")
    .ok().and_then(|text| serde_json::from_str(&text).ok()).unwrap_or_default();
  let world = registry.get("world").and_then(|value| value.as_str()).unwrap_or("");
  let mut cache = memory().write().unwrap();
  let before: HashSet<_> = cache.ready.keys().cloned().collect();
  let imported = import_rows(rows, &fingerprint, world, &mut cache);
  let migrated: Vec<_> = cache.ready.iter().filter(|(key, _)| !before.contains(*key))
    .map(|(key, response)| (key.clone(), response.clone())).collect();
  drop(cache);
  let _lock = FILE_LOCK.lock().unwrap();
  for (key, response) in migrated {
    crate::search::completed(&key.world,&key.language,&key.original,&response.translated);
    append_private(state_path(), &key, &response)?;
  }
  Ok(imported)
}

fn import_rows(rows: Vec<LegacyRow>, fingerprint: &str, world: &str, cache: &mut MemoryCache) -> usize {
  let mut imported = 0;
  let mut seen = HashSet::new();
  for row in rows.into_iter().rev() {
    if row.version != "2" || row.fingerprint != fingerprint || row.language != "zh-Hant" ||
      !["plain", "markup"].contains(&row.kind.as_str()) || row.rules_first != "false" { continue; }
    let kind = if row.original.contains("[C:") { "markup".into() } else { row.kind };
    let key = CacheKey { world: world.into(), language: row.language, kind, original: row.original };
    // A rejected latest update must not resurrect an older translation.
    if !seen.insert(key.clone()) || cache.ready.contains_key(&key) || row.status != "translated" ||
      !valid_translation(&key.original, &row.translation) { continue; }
    cache.complete(key, Some(TranslationResponse { translated: row.translation, alignment: match row.alignment.as_str() {
      "center" => TextAlignment::Center, "right" => TextAlignment::Right, _ => TextAlignment::Left,
    } }));
    imported += 1;
  }
  imported
}

pub fn setup() {
  if let Err(error) = refresh() { log::warn!("Native cache restore: {error}"); }
  if let Err(error) = import_legacy() { log::warn!("Legacy native cache import: {error}"); }
}

#[unsafe(no_mangle)]
extern "C" fn core_cache_metrics(state: *mut std::ffi::c_void) -> i32 {
  let cache = memory().read().unwrap();
  lua53_sys::push_integer(state, cache.ready.len() as isize);
  lua53_sys::push_integer(state, cache.pending.len() as isize);
  lua53_sys::push_integer(state, crate::tasks::SUBMISSIONS.load(Ordering::Relaxed) as isize);
  3
}

fn refresh() -> anyhow::Result<usize> { restore(state_path(), &mut memory().write().unwrap()) }

#[unsafe(no_mangle)]
extern "C" fn persistent_cache_refresh() -> i32 { if let Err(error) = refresh() { log::warn!("Native cache refresh: {error}"); } 0 }
#[unsafe(no_mangle)]
extern "C" fn persistent_cache_enable() -> i32 { ENABLED.store(true, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn persistent_cache_disable() -> i32 { ENABLED.store(false, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn persistent_cache_get_status(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_boolean(state, ENABLED.load(Ordering::Relaxed)); 1
}
#[unsafe(no_mangle)]
extern "C" fn color_persistence_set(state: *mut std::ffi::c_void) -> i32 {
  COLOR_PERSISTENCE.store(lua53_sys::check_integer(state,1)!=0,Ordering::Relaxed);0
}
#[unsafe(no_mangle)]
extern "C" fn native_set_world(state: *mut std::ffi::c_void) -> i32 {
  *WORLD.get_or_init(|| RwLock::new(String::new())).write().unwrap() = lua53_sys::check_string(state, 1);
  0
}
#[unsafe(no_mangle)]
extern "C" fn persistent_cache_clear(state: *mut std::ffi::c_void) -> i32 {
  let _lock = FILE_LOCK.lock().unwrap();
  let ok = match fs::remove_file(state_path()) { Ok(()) => true, Err(error) => error.kind() == std::io::ErrorKind::NotFound };
  if ok { *memory().write().unwrap() = MemoryCache::default(); }
  lua53_sys::push_boolean(state, ok); 1
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn ready_and_miss_caches_remain_bounded_during_long_sessions() {
    let mut cache=MemoryCache::default();
    for i in 0..20000 {
      let mut k=key("long-session","plain");k.original=format!("Unique sentence {i}");
      cache.complete(k.clone(),Some(response()));
      k.original.push('x');cache.complete(k,None);
    }
    assert!(cache.ready.len()<=4096,"Ready rows grow without bound");
    assert!(cache.misses.len()<=2048,"Failed sources grow without bound");
  }
  #[test]
  fn native_validation_understands_item_wrappers_and_protects_template_names() {
    assert!(valid_translation("{olm Remains}","{洞螈殘骸}"));
    assert!(!valid_translation("{DWARF_NAME} likes stone.","某人喜歡石頭。"));
  }
  fn key(world: &str, kind: &str) -> CacheKey {
    CacheKey { world: world.into(), language: "zh-Hant".into(), kind: kind.into(), original: "[C:6:0:1]Report[B]Next".into() }
  }
  fn response() -> TranslationResponse { TranslationResponse { translated: "[C:6:0:1]公告[B]下一則".into(), alignment: TextAlignment::Right } }

  #[test]
  fn simplified_lookup_reuses_a_known_traditional_result_synchronously() {
    let hant=CacheKey {world:"conversion-fixture".into(),language:"zh-Hant".into(),kind:"markup".into(),
      original:"[C:6:0:1]An iron goblet.".into()};
    fixture_complete(hant.clone(),TranslationResponse {translated:"[C:6:0:1]鐵製高腳杯。".into(),alignment:TextAlignment::Right});
    let hans=CacheKey {language:"zh-Hans".into(),..hant};
    let result=lookup(&hans).expect("known Chinese must not be resubmitted after switching to Simplified");
    assert_eq!(result.translated,"[C:6:0:1]铁制高脚杯。");
    assert_eq!(result.alignment,TextAlignment::Right);
  }

  #[test]
  fn completed_lookup_is_immediate_and_does_not_dispatch_again() {
    let mut cache = MemoryCache::default(); let key = key("one", "markup");
    assert!(cache.begin(&key)); assert!(!cache.begin(&key));
    cache.complete(key.clone(), Some(response()));
    assert_eq!(cache.lookup(&key), Some(response())); assert!(!cache.begin(&key));
  }
  #[test]
  fn completed_result_replaces_a_pending_or_negative_entry() {
    let mut cache = MemoryCache::default(); let key = key("one", "markup");
    cache.complete(key.clone(), None); assert!(!cache.begin(&key));
    cache.complete(key.clone(), Some(response())); assert_eq!(cache.lookup(&key), Some(response()));
    cache.complete(key.clone(), None); assert_eq!(cache.lookup(&key), Some(response()));
  }
  #[test]
  fn cache_isolates_world_language_and_markup() {
    let mut cache = MemoryCache::default(); let known = key("one", "markup");
    cache.complete(known.clone(), Some(response()));
    assert!(cache.lookup(&key("two", "markup")).is_none());
    assert!(cache.lookup(&key("one", "plain")).is_none());
    let mut other = known; other.language = "zh-Hans".into(); assert!(cache.lookup(&other).is_none());
  }
  #[test]
  fn miss_queue_is_bounded_and_duplicates_do_not_take_slots() {
    let mut cache = MemoryCache::default();
    for i in 0..CAPACITY { let mut key = key("one", "plain"); key.original = i.to_string(); assert!(cache.begin(&key)); assert!(!cache.begin(&key)); }
    assert!(!cache.begin(&key("one", "markup")));
  }
  #[test]
  fn restart_restores_alignment_palette_and_ignores_interrupted_rows() {
    let path = std::env::temp_dir().join(format!("df-local-cache-test-{}.jsonl", std::process::id()));
    fs::write(&path, "{broken").unwrap();
    let saved_key = key("one", "markup");
    append_private(&path, &saved_key, &response()).unwrap();
    let mut cache = MemoryCache::default(); assert_eq!(restore(&path, &mut cache).unwrap(), 1);
    assert_eq!(cache.lookup(&saved_key), Some(response())); fs::remove_file(path).unwrap();
  }
  #[test]
  fn malformed_translation_cannot_enter_the_native_cache() {
    assert!(valid_translation("[C:7:0:1]Text[B]Next", "[C:7:0:1]文字[B]下一則"));
    assert!(!valid_translation("[C:7:0:1]Text", "[C:6:0:1]文字"));
    assert!(!valid_translation("Text", "Mixed 中文"));
    assert!(!valid_translation("12 dwarves and 12 items", "12 個矮人與物品"));
    assert!(valid_translation("12 dwarves and 12 items", "12 個物品與 12 個矮人"));
    assert!(valid_translation("L123abc___", "彩色譯文"));
  }
  #[test]
  fn legacy_import_uses_latest_update_and_does_not_resurrect_rejected_text() {
    let row = |translation: &str| LegacyRow { version: "2".into(), fingerprint: "old".into(), source: "local".into(),
      language: "zh-Hant".into(), kind: "plain".into(), rules_first: "false".into(), original: "Report".into(),
      status: "translated".into(), translation: translation.into(), alignment: "left".into() };
    let mut cache = MemoryCache::default();
    assert_eq!(import_rows(vec![row("舊譯文"), row("新譯文")], "old", "one", &mut cache), 1);
    let saved_key = CacheKey { world: "one".into(), language: "zh-Hant".into(), kind: "plain".into(), original: "Report".into() };
    assert_eq!(cache.lookup(&saved_key).unwrap().translated, "新譯文");
    let mut cache = MemoryCache::default();
    assert_eq!(import_rows(vec![row("舊譯文"), row("Invalid 中文")], "old", "one", &mut cache), 0);
    assert!(cache.lookup(&saved_key).is_none());
  }
}
