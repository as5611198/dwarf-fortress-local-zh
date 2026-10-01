use std::collections::HashMap;
use std::fs::File;
use std::sync::{OnceLock, RwLock, RwLockReadGuard, RwLockWriteGuard};

use anyhow::Result;

use lua53_sys as lua;

use crate::translation;

// Reset the simple translators
pub fn reset() {
  get_dicts_mut().clear();
}

// Simple dictionary maps original text to translated text along with tags
type SimpleDictionary = HashMap<String, (String, HashMap<String, String>)>;

// A collection of simple dictionaries grouped by language tag
type SimpleDictionaries = HashMap<String, SimpleDictionary>;

fn merge_dictionary(dict:&mut SimpleDictionary,candidate:SimpleDictionary) {
  for (source,value) in candidate {
    if dict.get(&source).is_some_and(|(_,tags)|tags.get("REVIEWED").map(String::as_str)==Some("1")) &&
      value.1.get("REVIEWED").map(String::as_str)!=Some("1") {continue}
    dict.insert(source,value);
  }
}

// Global storage for simple dictionaries
static DICTS: OnceLock<RwLock<SimpleDictionaries>> = OnceLock::new();

// Getting access to the dictionaries
fn get_dicts() -> RwLockReadGuard<'static, SimpleDictionaries> {
  DICTS.get_or_init(|| RwLock::new(SimpleDictionaries::new())).read().unwrap()
}

// Getting mutable access to the dictionaries
fn get_dicts_mut() -> RwLockWriteGuard<'static, SimpleDictionaries> {
  DICTS.get_or_init(|| RwLock::new(SimpleDictionaries::new())).write().unwrap()
}

#[cfg(test)]
pub(crate) fn fixture_insert(text: &str, translated: &str, alignment: &str) {
  get_dicts_mut().entry("en".into()).or_default().insert(
    text.into(), (translated.into(), HashMap::from([("ALIGNMENT".into(), alignment.into())])),
  );
}

#[cfg(test)]
mod arena_tests {
  use super::*;
  use crate::{translator,translation,native_cache};
  #[test]
  fn reviewed_terms_survive_runtime_alias_import() {
    let mut dict=HashMap::from([("Needs setting".into(),("需要復位".into(),parse_tags("[REVIEWED:1]")))]);
    merge_dictionary(&mut dict,HashMap::from([("Needs setting".into(),("需要設定".into(),HashMap::new()))]));
    assert_eq!(dict["Needs setting"].0,"需要復位");
    merge_dictionary(&mut dict,HashMap::from([("Needs setting".into(),("需要复位".into(),parse_tags("[REVIEWED:1]")))]));
    assert_eq!(dict["Needs setting"].0,"需要复位");
  }
  #[test]
  #[ignore="requires DF_LOCAL_PACKAGE integration data path"]
  fn package_arena_corrections_return_on_first_hook_without_workers() {
    use std::sync::atomic::Ordering;
    let root=std::path::PathBuf::from(std::env::var("DF_LOCAL_PACKAGE").unwrap());
    for language in ["zh-Hant","zh-Hans"] {
      let mut candidate=SimpleDictionary::new();
      let mut expected=Vec::new();
      load_csv(root.join(format!("dfi18n-data/simple/{language}/zzzzzzz-creature-names.csv")),|row:Entry| {
        candidate.insert(row.text,(row.translation,parse_tags(&row.tags)));
      }).unwrap();
      load_csv(root.join(format!("dfi18n-data/simple/{language}/zzzzzzzz-arena-corrections.csv")),|row:Entry| {
        candidate.insert(row.text.clone(),(row.translation.clone(),parse_tags(&row.tags)));
        expected.push((row.text,row.translation));
      }).unwrap();
      merge_dictionary(get_dicts_mut().entry("en".into()).or_default(),candidate);
      for stem in ["Aardvark Man","Alligator Man","Grizzly Bear Man","Dragon"] {
        let want=get_dicts()["en"][stem].0.clone();
        assert!(!want.contains("男人") && !want.contains("德拉貢"));
        expected.push((format!("{stem} 2"),format!("{want} 2")));
      }
      for (source,want) in expected {
        let request=translation::TranslationRequest::fixture(&source,false,0);
        native_cache::fixture_complete(native_cache::key("en",&request),translation::TranslationResponse{translated:"需要設定".into(),alignment:Default::default()});
        let before=crate::tasks::SUBMISSIONS.load(Ordering::SeqCst);
        assert_eq!(translator::translate(&request).unwrap().translated,want,"{language}: {source}");
        assert_eq!(crate::tasks::SUBMISSIONS.load(Ordering::SeqCst),before);
      }
    }
  }
  #[test]
  fn numbered_species_precede_wrong_model_cache_and_keep_identifiers() {
    for (stem,want) in [("Aardvark Man","土豚人"),("Alligator Man","短吻鱷人"),("Grizzly Bear Man","灰熊人"),("Dragon","巨龍")] {
      get_dicts_mut().entry("en".into()).or_default().insert(stem.into(),(want.into(),HashMap::from([("CREATURE".into(),"1".into())])));
      let source=format!("{stem} 27");
      let request=translation::TranslationRequest::fixture(&source,false,0);
      native_cache::fixture_complete(native_cache::key("en",&request),translation::TranslationResponse{translated:"錯誤 男人 27".into(),alignment:Default::default()});
      assert_eq!(translator::known(&request).unwrap().translated,format!("{want} 27"));
    }
    fixture_insert("Joe","喬","LEFT");
    assert!(translator::known(&translation::TranslationRequest::fixture("Joe 27",false,0)).is_none());
  }
  #[test]
  fn reviewed_health_label_handles_palette_without_reusing_bad_cache() {
    fixture_insert("Needs setting","需要復位","LEFT");
    for source in ["Needs setting",".Needs setting","[C:6:0:1].Needs setting","[C:4:1:0]Needs setting"] {
      let request=translation::TranslationRequest::fixture(source,true,0);
      native_cache::fixture_complete(native_cache::key("en",&request),translation::TranslationResponse{translated:"需要設定".into(),alignment:Default::default()});
      let want=source.replace("Needs setting","需要復位");
      assert_eq!(translator::known(&request).unwrap().translated,want);
    }
  }
}

// Translate text based on the provided language tag and context
pub fn translate(
  lang_tag: &str,
  context: &translation::TranslationContext,
) -> Option<translation::TranslationResponse> {
  // Extract the text to be translated from the context, colored text is not handled here
  let text = context.original();

  let dicts = get_dicts();
  dicts.get(lang_tag).and_then(|dict| {
    let mut prefix="";
    let mut body=text;
    static PALETTE:OnceLock<regex::Regex>=OnceLock::new();
    if let Some(m)=PALETTE.get_or_init(||regex::Regex::new(r"^(?:\[C:\d+:\d+:\d+\])+").unwrap()).find(text) {
      prefix=m.as_str();body=&text[m.end()..];
    }
    let derived=if body.len()<=200 {
      body.rsplit_once(' ').and_then(|(stem,number)| {
        if number.is_empty() || !number.bytes().all(|c|c.is_ascii_digit()) {return None}
        let (translation,tags)=dict.get(stem).or_else(||dict.get(&stem.to_ascii_lowercase()))?;
        (tags.get("CREATURE").map(String::as_str)==Some("1")).then(||format!("{prefix}{translation} {number}"))
      })
    } else {None};
    if let Some(translated)=derived {
      return Some(translation::TranslationResponse{translated,alignment:Default::default()});
    }
    let dot=body.starts_with('.') && body[1..]==*"Needs setting";
    let key=if dot {&body[1..]} else {body};
    // Older dictionaries contain complete palette-tagged strings as exact
    // keys. Prefer a reviewed body correction, then retain those exact hits.
    let (entry, output_prefix, output_dot)=if let Some(entry)=dict.get(key) {
      (entry,prefix,dot)
    } else {
      (dict.get(text)?,"",false)
    };
    Some(entry).and_then(|(translated, tags)| {
      Some(translation::TranslationResponse {
        translated: format!("{output_prefix}{}{translated}",if output_dot {"."} else {""}),
        alignment: match tags.get("ALIGNMENT").map(|s| s.as_str()) {
          Some("LEFT") => translation::TextAlignment::Left,
          Some("RIGHT") => translation::TextAlignment::Right,
          Some("CENTER") => translation::TextAlignment::Center,
          _ => translation::TextAlignment::Left,
        },
      })
    })
  })
}

// Load a simple dictionary from a CSV file into the global storage
#[unsafe(no_mangle)]
extern "C" fn load_simple_dict(lua_state: *mut std::ffi::c_void) -> i32 {
  let lang_tag = lua::check_string(lua_state, 1);
  let path_str = lua::check_string(lua_state, 2);

  let mut candidate = SimpleDictionary::new();
  if let Err(err) = load_csv(
    &path_str,
    |Entry {
       text,
       translation,
       tags,
     }| {
      candidate.insert(text, (translation, parse_tags(&tags)));
    },
  ) {
    log::warn!("Failed to load simple translator data from {path_str:?}: {err}");
    lua::push_boolean(lua_state, false); lua::push_string(lua_state, &err.to_string());
    return 2;
  };
  let mut dicts=get_dicts_mut();
  let dict=dicts.entry(lang_tag.to_string()).or_default();
  candidate.retain(|source,value| !dict.get(source).is_some_and(|(_,tags)|
    tags.get("REVIEWED").map(String::as_str)==Some("1") && value.1.get("REVIEWED").map(String::as_str)!=Some("1")));
  crate::search::literals(&lang_tag,candidate.iter().map(|(source,(text,_))| (source.clone(),text.clone())));
  merge_dictionary(dict,candidate);
  log::info!("Loaded Simple translator data for language {lang_tag:?} from {path_str:?}");
  lua::push_boolean(lua_state, true); lua::push_nil(lua_state);
  2
}

// CSV entry
#[derive(Debug, serde::Deserialize)]
struct Entry {
  // Original text
  text: String,
  // Translated text
  translation: String,
  // Tags
  tags: String,
}

// Load CSV file and process each entry with the provided function
fn load_csv<T: serde::de::DeserializeOwned, P: AsRef<std::path::Path>, F>(path: P, mut f: F) -> Result<()>
where
  F: FnMut(T),
{
  for entry in csv::Reader::from_reader(File::open(path)?).deserialize::<T>() {
    f(entry?);
  }

  Ok(())
}

static DF_TAG_REGEX: OnceLock<regex::Regex> = OnceLock::new();

// Get the regex for DF txt tags
// TODO: move to `utils` module
fn get_df_tag_regex() -> &'static regex::Regex {
  DF_TAG_REGEX.get_or_init(|| regex::Regex::new(r"\[([^\[:]+):([^:\]]+)\]").unwrap())
}

// Parse tags in DF txt format [KEY:VALUE]
fn parse_tags(tags_str: &str) -> HashMap<String, String> {
  let mut tags = HashMap::new();
  let regex = get_df_tag_regex();
  for cap in regex.captures_iter(tags_str) {
    if let (Some(key), Some(value)) = (cap.get(1), cap.get(2)) {
      tags.insert(key.as_str().to_owned(), value.as_str().to_owned());
    }
  }
  tags
}
