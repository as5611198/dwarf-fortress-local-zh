//! Broker-verified local official snapshot, independent of model caches.
//! Each process pins both language snapshots once. Downloads never hot-swap prose.
use std::collections::HashMap;
use std::sync::{OnceLock, RwLock};
use serde::{Deserialize, Serialize};
use crate::translation::TranslationResponse;

#[derive(Deserialize)]
struct File {
  schema: u32,
  version: String,
  language: String,
  rules: String,
  entries: Vec<Row>,
}
#[derive(Deserialize)]
struct Row {
  text: String,
  translation: String,
  kind: String,
  alignment: Option<String>,
  context: Option<String>,
}
#[derive(Default, Serialize)]
struct Snapshot {
  version: String,
  entries: usize,
  elapsed_ms: f64,
  #[serde(skip)]
  rows: HashMap<String, TranslationResponse>,
  #[serde(skip)]
  fixed: HashMap<String, TranslationResponse>,
}
fn prepare(bytes:&[u8], language:&str)->anyhow::Result<Snapshot> {
  let start=std::time::Instant::now();
  anyhow::ensure!(bytes.len()<=32*1024*1024,"official snapshot too large");
  let file:File=serde_json::from_slice(bytes)?;
  anyhow::ensure!(file.schema==1 && file.language==language && file.rules=="df-zh-3" &&
    !file.version.is_empty() && file.version.len()<=64 && file.entries.len()<=200000,"official context incompatible");
  let mut snapshot=Snapshot {version:file.version,..Default::default()};
  for row in file.entries {
    if row.context.as_deref().is_some_and(|context|context!="general") {continue}
    anyhow::ensure!(!row.text.is_empty() && row.text.len()<=8000 && !row.text.contains("DFLIVE_") &&
      matches!(row.kind.as_str(),"exact"|"entity"|"numeric") && crate::native_cache::valid_translation(&row.text,&row.translation),"official content invalid");
    let response=TranslationResponse {translated:row.translation,alignment:match row.alignment.as_deref() {
      Some("center")=>crate::translation::TextAlignment::Center,
      Some("right")=>crate::translation::TextAlignment::Right,
      _=>Default::default(),
    }};
    anyhow::ensure!(snapshot.rows.insert(row.text,response).is_none(),"duplicate official row");
  }
  snapshot.entries=snapshot.rows.len();snapshot.elapsed_ms=start.elapsed().as_secs_f64()*1000.;Ok(snapshot)
}
static SNAPSHOTS:OnceLock<RwLock<HashMap<String,Snapshot>>>=OnceLock::new();
pub fn setup() {
  SNAPSHOTS.get_or_init(||RwLock::new(HashMap::new()));
  std::thread::Builder::new().name("df-official-load".into()).spawn(|| {
    let root=std::path::PathBuf::from("dfhack-config/mods/df-local-zh-complete");
    let state=std::fs::read(root.join("official/state.json")).ok()
      .filter(|bytes|bytes.len()<=128*1024).and_then(|bytes|serde_json::from_slice::<serde_json::Value>(&bytes).ok()).unwrap_or_default();
    let mut withdrawn=std::collections::HashSet::<String>::new();
    if let Some(file)=state["highestManifestFile"].as_str() {
      if file.len()<128 && !file.contains(['/', '\\', ':']) && file.ends_with(".manifest.json") {
        let path=root.join("official").join(file);
        if std::fs::metadata(&path).is_ok_and(|i|i.len()<=128*1024) {
          if let Ok(bytes)=std::fs::read(path) {
            if let Ok(manifest)=df_local_zh_broker::official::verify_manifest(&bytes,&df_local_zh_broker::official::trust()) {
              for v in manifest["withdrawn"].as_array().unwrap() {withdrawn.insert(v.as_str().unwrap().into());}
            }
          }
        }
      }
    }
    if let Some(rows)=state["languages"].as_object() {
      for row in rows.values() {for key in ["pending","active","previous"] {
        if let Ok(manifest)=signed_manifest(&root.join("official"),&row[key]) {
          for version in manifest["withdrawn"].as_array().unwrap() {withdrawn.insert(version.as_str().unwrap().into());}
        }
      }}
    }
    for language in ["zh-Hant","zh-Hans"] {
      let mut snapshot=Snapshot::default();
      // Every game process pins once. Pending is safe at this startup boundary,
      // irrespective of whether the background Broker has committed its pointer yet.
      for record in ["pending","active","previous"] {
        let row=&state["languages"][language][record];
        if row["version"].as_str().is_some_and(|v|withdrawn.contains(v)) {continue}
        if let Ok(value)=load_record(&root.join("official"),row,language) {snapshot=value;break}
      }
      let pins=root.join(format!("fixed-{language}.json"));
      if std::fs::metadata(&pins).is_ok_and(|info|info.len()<=1024*1024) {
        if let Ok(bytes)=std::fs::read(&pins) {
          if let Ok(rows)=serde_json::from_slice::<HashMap<String,String>>(&bytes) {
            for (text,translation) in rows {
              if crate::native_cache::valid_translation(&text,&translation) {
                snapshot.fixed.insert(text,TranslationResponse{translated:translation,alignment:Default::default()});
              }
            }
          }
        }
      }
      SNAPSHOTS.get().unwrap().write().unwrap().insert(language.into(),snapshot);
    }
  }).expect("official loader");
}
fn load_record(root:&std::path::Path,row:&serde_json::Value,language:&str)->anyhow::Result<Snapshot> {
  use sha2::Digest;
  let file=row["packageFile"].as_str().ok_or_else(||anyhow::anyhow!("missing official record"))?;
  let sha=row["sha256"].as_str().ok_or_else(||anyhow::anyhow!("missing hash"))?;
  anyhow::ensure!(file.len()<256 && !file.contains(['/', '\\', ':']) && file.ends_with(".json") && sha.len()==64,"invalid record path");
  let path=root.join(file);anyhow::ensure!(std::fs::metadata(&path)?.len()<=32*1024*1024,"package too large");
  let bytes=std::fs::read(path)?;
  let digest=format!("{:064x}",base16ct::HexDisplay(&sha2::Sha256::digest(&bytes)));anyhow::ensure!(digest==sha,"official hash invalid");
  let manifest=signed_manifest(root,row)?;
  let descriptor=manifest["packages"].as_array().unwrap().iter().find(|p|p["language"]==language)
    .ok_or_else(||anyhow::anyhow!("official language missing"))?;
  anyhow::ensure!(descriptor["sha256"]==sha && row["version"]==manifest["version"] &&
    !manifest["withdrawn"].as_array().unwrap().contains(&row["version"]),"official record incompatible");
  df_local_zh_broker::official::validate_package(&bytes,descriptor,&manifest)?;
  prepare(&bytes,language)
}
fn signed_manifest(root:&std::path::Path,row:&serde_json::Value)->anyhow::Result<serde_json::Value> {
  let version=row["version"].as_str().ok_or_else(||anyhow::anyhow!("missing version"))?;
  let sequence=row["sequence"].as_u64().ok_or_else(||anyhow::anyhow!("missing sequence"))?;
  let file=row["manifestFile"].as_str().ok_or_else(||anyhow::anyhow!("missing manifest"))?;
  anyhow::ensure!(version.len()<=64 && !version.contains(['/', '\\', ':']) &&
    file==format!("{version}-{sequence}.manifest.json"),"invalid signed manifest path");
  let path=root.join(file);anyhow::ensure!(std::fs::metadata(&path)?.len()<=128*1024,"manifest too large");
  let manifest=df_local_zh_broker::official::verify_manifest(&std::fs::read(path)?,&df_local_zh_broker::official::trust())?;
  anyhow::ensure!(manifest["version"]==version && manifest["sequence"]==sequence,"manifest record mismatch");
  Ok(manifest)
}
fn find(source:&str,rows:&HashMap<String,TranslationResponse>)->Option<TranslationResponse> {
  if let Some(value)=rows.get(source) {return Some(value.clone())}
  static BOUNDARIES:OnceLock<regex::Regex>=OnceLock::new();
  let tags=BOUNDARIES.get_or_init(||regex::Regex::new(r"^(?:\[C:[0-7]:[0-7]:[01]\]|\[[BPR]\])+").unwrap());
  let prefix=tags.find(source).map(|m|m.as_str()).unwrap_or("");
  let suffix=source.strip_prefix(prefix)?;
  let mut value=rows.get(suffix)?.clone();value.translated=format!("{prefix}{}",value.translated);Some(value)
}
pub(crate) fn fixed(language:&str,source:&str)->Option<TranslationResponse> {
  let maps=SNAPSHOTS.get()?.read().unwrap();find(source,&maps.get(language)?.fixed)
}
pub(crate) fn lookup(language:&str,source:&str)->Option<TranslationResponse> {
  let maps=SNAPSHOTS.get()?.read().unwrap();find(source,&maps.get(language)?.rows)
}
#[unsafe(no_mangle)]
extern "C" fn official_library_lookup(state:*mut std::ffi::c_void)->i32 {
  let source=lua53_sys::check_string(state,1);
  let language=crate::lang::current_lang_tag();
  let value=fixed(&language,&source).or_else(||crate::translator::static_lookup(&language,&source)).or_else(||lookup(&language,&source));
  if let Some(value)=value {lua53_sys::push_string(state,&value.translated)} else {lua53_sys::push_nil(state)};1
}
#[unsafe(no_mangle)]
extern "C" fn official_library_status(state:*mut std::ffi::c_void)->i32 {
  let language=lua53_sys::check_string(state,1);
  let maps=SNAPSHOTS.get_or_init(||RwLock::new(HashMap::new())).read().unwrap();
  lua53_sys::push_string(state,&serde_json::to_string(&maps.get(&language)).unwrap());1
}
#[cfg(test)]
mod tests {
  use super::*;
  fn bytes(language:&str,translation:&str)->Vec<u8> {
    serde_json::to_vec(&serde_json::json!({"schema":1,"version":"first","language":language,"rules":"df-zh-3",
      "entries":[{"text":"Official isolated sentence.","translation":translation,"kind":"exact"}]})).unwrap()
  }
  #[test]
  fn native_batch_no_ai_language_pins_and_late_model_priority() {
    let before=crate::tasks::SUBMISSIONS.load(std::sync::atomic::Ordering::SeqCst);
    let hant=prepare(&bytes("zh-Hant","官方繁體句子。"),"zh-Hant").unwrap();
    assert!(prepare(&bytes("zh-Hant","官方繁體句子。"),"zh-Hans").is_err());
    SNAPSHOTS.get_or_init(||RwLock::new(HashMap::new())).write().unwrap().insert("en".into(),hant);
    let request=crate::translation::TranslationRequest::fixture("Official isolated sentence.",false,0);
    crate::native_cache::fixture_complete(crate::native_cache::key("en",&request),TranslationResponse{translated:"晚到的模型。".into(),alignment:Default::default()});
    assert_eq!(crate::translator::known(&request).unwrap().translated,"官方繁體句子。");
    crate::translator::fixture_static("Official isolated sentence.","內建優先。");
    assert_eq!(crate::translator::known(&request).unwrap().translated,"內建優先。");
    SNAPSHOTS.get().unwrap().write().unwrap().get_mut("en").unwrap().fixed.insert("Official isolated sentence.".into(),TranslationResponse{translated:"使用者優先。".into(),alignment:Default::default()});
    assert_eq!(crate::translator::known(&request).unwrap().translated,"使用者優先。");
    assert_eq!(crate::tasks::SUBMISSIONS.load(std::sync::atomic::Ordering::SeqCst),before);
  }
  #[test]
  fn malformed_numbers_and_content_cannot_publish() {
    assert!(prepare(b"{broken","zh-Hant").is_err());
    assert!(prepare(&bytes("zh-Hant","Wrong English"),"zh-Hant").is_err());
    let snapshot=prepare(&bytes("zh-Hant","完整句子。"),"zh-Hant").unwrap();
    assert_eq!(find("[P][C:7:0:0]Official isolated sentence.",&snapshot.rows).unwrap().translated,"[P][C:7:0:0]完整句子。");
  }
}
