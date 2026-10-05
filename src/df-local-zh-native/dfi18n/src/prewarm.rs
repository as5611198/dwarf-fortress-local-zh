use crate::translation::TranslationResponse;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Condvar, Mutex, OnceLock, RwLock};
use std::time::{Duration, Instant, SystemTime};

#[derive(Deserialize)]
struct Manifest {
  version: u32,
  world: String,
  language: Option<String>,
  revision: String,
  rows: Vec<Row>,
}
#[derive(Deserialize)]
struct Row {
  text: String,
  translation: String,
  kind: String,
  alignment: Option<String>,
}
#[derive(Default, Clone, Serialize)]
struct Progress {
  world: String,
  language: String,
  revision: String,
  loaded: usize,
  ready: usize,
  queued: usize,
  pending: usize,
  stalled: usize,
  skipped: usize,
  canonical: usize,
  imported: usize,
  running: bool,
  elapsed_ms: f64,
  stalled_sources: Vec<serde_json::Value>,
  error: Option<String>,
}
#[derive(Default)]
struct Snapshot {
  progress: Progress,
  rows: HashMap<String, TranslationResponse>,
  previous: HashMap<String, Option<TranslationResponse>>,
}

fn prepare(
  bytes: &[u8],
  world: &str,
  language: &str,
  known: impl Fn(&str) -> Option<(TranslationResponse, bool)>,
) -> anyhow::Result<Snapshot> {
  let started = Instant::now();
  anyhow::ensure!(bytes.len() <= 32 * 1024 * 1024, "prewarm file too large");
  let manifest: Manifest = serde_json::from_slice(bytes)?;
  anyhow::ensure!(
    manifest.version == 1
      && manifest.world == world
      && manifest.language.as_deref().unwrap_or("zh-Hant") == language
      && !manifest.revision.is_empty()
      && manifest.revision.len() <= 128
      && manifest.rows.len() <= 200_000,
    "context mismatch"
  );
  let mut snapshot = Snapshot {
    progress: Progress {
      world: world.into(),
      language: language.into(),
      revision: manifest.revision,
      loaded: manifest.rows.len(),
      ..Default::default()
    },
    ..Default::default()
  };
  for row in manifest.rows {
    let invalid_source = row.text.is_empty()
      || row.text.len() > 8000
      || row.text.contains('\0')
      || row.text.contains("DFLIVE_")
      || row.text.contains('{')
      || !matches!(row.kind.as_str(), "plain" | "markup");
    let existing = if invalid_source { None } else { known(&row.text) };
    if let Some((existing, true)) = &existing {
      snapshot.progress.skipped += 1;
      snapshot.progress.canonical += usize::from(existing.translated != row.translation);
      snapshot.progress.ready += 1;
      continue;
    }
    if invalid_source || !crate::native_cache::valid_translation(&row.text, &row.translation) {
      snapshot.progress.stalled += 1;
      if snapshot.progress.stalled_sources.len() < 32 {
        snapshot.progress.stalled_sources.push(serde_json::json!({"field_id":"native_cache.original",
          "type":row.kind,"source":row.text.chars().take(300).collect::<String>()}));
      }
      continue;
    }
    if let Some((existing, _)) = &existing {
      if existing.translated == row.translation {
        snapshot.progress.skipped += 1;
        snapshot.progress.canonical += usize::from(existing.translated != row.translation);
        snapshot.progress.ready += 1;
        continue;
      }
    }
    snapshot.previous.insert(row.text.clone(), existing.map(|(response, _)| response));
    snapshot.rows.insert(
      row.text,
      TranslationResponse {
        translated: row.translation,
        alignment: match row.alignment.as_deref() {
          Some("center") => crate::translation::TextAlignment::Center,
          Some("right") => crate::translation::TextAlignment::Right,
          _ => Default::default(),
        },
      },
    );
    snapshot.progress.ready += 1;
    snapshot.progress.imported += 1;
  }
  snapshot.progress.elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
  Ok(snapshot)
}

fn known(ctx: &Context, source: &str) -> Option<(TranslationResponse, bool)> {
  if let Some(value) = crate::translator::static_lookup(&ctx.language, source) {
    return Some((value, true));
  }
  let key = crate::native_cache::CacheKey {
    world: ctx.world.clone(),
    language: ctx.language.clone(),
    kind: if source.contains("[C:") { "markup" } else { "plain" }.into(),
    original: source.into(),
  };
  crate::native_cache::dynamic_lookup(&key).map(|value| (value, false))
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Context {
  path: PathBuf,
  world: String,
  language: String,
}
#[derive(Default)]
struct Desired {
  context: Option<Context>,
  paused: bool,
  generation: u64,
}
#[derive(Default)]
struct Service {
  desired: Mutex<Desired>,
  wake: Condvar,
  snapshots: RwLock<HashMap<String, Arc<Snapshot>>>,
  progress: Mutex<Progress>,
}
impl Service {
  fn request(&self, context: Option<Context>, paused: bool) {
    let mut desired = self.desired.lock().unwrap();
    if desired.context == context && desired.paused == paused {
      return;
    }
    desired.context = context.clone();
    desired.paused = paused;
    desired.generation += 1;
    let mut progress = self.progress.lock().unwrap();
    *progress = context
      .as_ref()
      .and_then(|ctx| {
        self
          .snapshots
          .read()
          .unwrap()
          .get(&ctx.language)
          .filter(|s| s.progress.world == ctx.world)
          .map(|s| s.progress.clone())
      })
      .unwrap_or_default();
    if let Some(ctx) = context {
      progress.world = ctx.world;
      progress.language = ctx.language;
    }
    self.wake.notify_one();
  }
  fn lookup(
    &self,
    key: &crate::native_cache::CacheKey,
    current: Option<&TranslationResponse>,
  ) -> Option<TranslationResponse> {
    let snapshot = self.snapshots.read().unwrap().get(&key.language)?.clone();
    if snapshot.progress.world != key.world {
      return None;
    }
    // A model result completed after this preload must win immediately.
    if snapshot.previous.get(&key.original)?.as_ref() != current {
      return None;
    }
    snapshot.rows.get(&key.original).cloned()
  }
  fn commit(&self, generation: u64, snapshot: Snapshot) -> bool {
    let search=crate::search::PreloadedIndex::new(&snapshot.progress.world,
      snapshot.rows.iter().map(|(source,response)| (source.clone(),response.translated.clone(),
        snapshot.previous.get(source).and_then(|r|r.as_ref()).map(|r|r.translated.clone()))));
    let desired = self.desired.lock().unwrap();
    if desired.generation != generation
      || desired.paused
      || !desired
        .context
        .as_ref()
        .is_some_and(|ctx| ctx.world == snapshot.progress.world && ctx.language == snapshot.progress.language)
    {
      return false;
    }
    let snapshot = Arc::new(snapshot);
    let retired=self.snapshots.write().unwrap().insert(snapshot.progress.language.clone(), snapshot.clone());
    // Keep generation validation and both publications in the same critical
    // section. A paused or obsolete preload cannot leave partial search rows.
    let retired_search=crate::search::replace_preloaded(&snapshot.progress.language,search);
    *self.progress.lock().unwrap() = snapshot.progress.clone();
    drop(desired);
    drop(retired_search);
    drop(retired);
    true
  }
  fn run(self: Arc<Self>) {
    let mut stamp: Option<(u64, SystemTime, u64)> = None;
    loop {
      let (observed, work) = {
        let desired = self.desired.lock().unwrap();
        (
          desired.generation,
          (!desired.paused).then(|| desired.context.clone().map(|ctx| (desired.generation, ctx))).flatten(),
        )
      };
      if let Some((generation, ctx)) = work {
        let metadata = std::fs::metadata(&ctx.path);
        if let Ok(metadata) = metadata {
          let next = (
            generation,
            metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH),
            metadata.len(),
          );
          if stamp.as_ref() != Some(&next) {
            stamp = Some(next);
            let started = Instant::now();
            {
              let desired = self.desired.lock().unwrap();
              if desired.generation == generation && !desired.paused {
                let mut progress = self.progress.lock().unwrap();
                progress.running = true;
                progress.pending = 1;
                progress.error = None;
              }
            }
            let result = (|| -> anyhow::Result<Snapshot> {
              anyhow::ensure!(metadata.len() <= 32 * 1024 * 1024, "prewarm file too large");
              let bytes = std::fs::read(&ctx.path)?;
              prepare(&bytes, &ctx.world, &ctx.language, |source| known(&ctx, source))
            })();
            match result {
              Ok(mut snapshot) => {
                snapshot.progress.elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                if self.commit(generation, snapshot) {
                  let desired = self.desired.lock().unwrap();
                  if desired.generation == generation {
                    self.progress.lock().unwrap().elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
                  }
                }
              }
              Err(_) => {
                let desired = self.desired.lock().unwrap();
                if desired.generation == generation {
                  let mut progress = self.progress.lock().unwrap();
                  progress.running = false;
                  progress.pending = 0;
                  progress.error = Some("Invalid or mismatched prewarm file".into());
                  progress.stalled = progress.stalled.max(1);
                }
              }
            }
          }
        }
      }
      let desired = self.desired.lock().unwrap();
      if desired.generation == observed {
        let _ = self.wake.wait_timeout(desired, Duration::from_secs(1)).unwrap();
      }
    }
  }
}

static SERVICE: OnceLock<Arc<Service>> = OnceLock::new();
fn service() -> &'static Arc<Service> {
  SERVICE.get_or_init(|| {
    let value = Arc::new(Service::default());
    let worker = value.clone();
    std::thread::Builder::new().name("df-local-prewarm".into()).spawn(move || worker.run()).expect("prewarm worker");
    value
  })
}
pub(crate) fn lookup(
  key: &crate::native_cache::CacheKey,
  current: Option<&TranslationResponse>,
) -> Option<TranslationResponse> {
  SERVICE.get()?.lookup(key, current)
}
#[unsafe(no_mangle)]
extern "C" fn native_prewarm_request(state: *mut std::ffi::c_void) -> i32 {
  let path = lua53_sys::check_string(state, 1);
  let world = lua53_sys::check_string(state, 2);
  let language = lua53_sys::check_string(state, 3);
  let paused = lua53_sys::check_integer(state, 4) != 0;
  let context = (!world.is_empty() && matches!(language.as_str(), "zh-Hant" | "zh-Hans")).then(|| Context {
    path: path.into(),
    world,
    language,
  });
  service().request(context, paused);
  0
}
#[unsafe(no_mangle)]
extern "C" fn native_prewarm_status(state: *mut std::ffi::c_void) -> i32 {
  let progress = service().progress.lock().unwrap().clone();
  lua53_sys::push_string(state, &serde_json::to_string(&progress).unwrap());
  1
}

#[cfg(test)]
mod tests {
  use super::*;
  fn response(text: &str) -> TranslationResponse {
    TranslationResponse {
      translated: text.into(),
      alignment: Default::default(),
    }
  }
  fn manifest(rows: serde_json::Value) -> Vec<u8> {
    serde_json::to_vec(&serde_json::json!({"version":1,"world":"one","revision":"first","rows":rows})).unwrap()
  }
  #[test]
  fn known_rows_skip_import_and_reviewed_terms_keep_priority() {
    let bytes = manifest(serde_json::json!([
      {"text":"Known label","translation":"已知標籤","kind":"plain"},
      {"text":"Needs setting","translation":"需要設定","kind":"plain"},
      {"text":"New label","translation":"新增標籤","kind":"plain"}
    ]));
    let snapshot = prepare(&bytes, "one", "zh-Hant", |text| match text {
      "Known label" => Some((response("已知標籤"), false)),
      "Needs setting" => Some((response("需要復位"), true)),
      _ => None,
    })
    .unwrap();
    assert_eq!(snapshot.progress.ready, 3);
    assert_eq!(snapshot.progress.skipped, 2);
    assert_eq!(snapshot.progress.canonical, 1);
    assert_eq!(snapshot.rows.len(), 1);
    assert_eq!(snapshot.rows["New label"].translated, "新增標籤");
  }
  #[test]
  fn an_already_reviewed_product_identifier_is_ready_without_importing_unvalidated_text() {
    let bytes = manifest(serde_json::json!([{"text":"DFHack Launcher","translation":"DFHack 啟動器","kind":"plain"}]));
    let snapshot = prepare(&bytes, "one", "zh-Hant", |_| Some((response("DFHack 啟動器"), true))).unwrap();
    assert_eq!(snapshot.progress.ready, 1);
    assert_eq!(snapshot.progress.stalled, 0);
    assert_eq!(snapshot.progress.imported, 0);
  }
  #[test]
  fn invalid_row_does_not_block_following_text_or_change_tokens() {
    let bytes = manifest(serde_json::json!([
      {"text":"3 stones","translation":"4顆石頭","kind":"plain"},
      {"text":"[C:7:0:1]Report","translation":"[C:6:0:1]公告","kind":"markup"},
      {"text":"[C:7:0:1]Next","translation":"[C:7:0:1]下一則","kind":"markup","alignment":"right"}
    ]));
    let snapshot = prepare(&bytes, "one", "zh-Hant", |_| None).unwrap();
    assert_eq!(snapshot.progress.stalled, 2);
    assert_eq!(snapshot.progress.ready, 1);
    assert_eq!(snapshot.rows["[C:7:0:1]Next"].translated, "[C:7:0:1]下一則");
    assert!(matches!(
      snapshot.rows["[C:7:0:1]Next"].alignment,
      crate::translation::TextAlignment::Right
    ));
  }
  #[test]
  fn world_language_and_malformed_files_are_rejected() {
    let bytes = manifest(serde_json::json!([]));
    assert!(prepare(&bytes, "other", "zh-Hant", |_| None).is_err());
    assert!(prepare(&bytes, "one", "zh-Hans", |_| None).is_err());
    assert!(prepare(b"{unfinished", "one", "zh-Hant", |_| None).is_err());
  }
  fn context(world: &str, language: &str) -> Context {
    Context {
      path: "fixture.json".into(),
      world: world.into(),
      language: language.into(),
    }
  }
  #[test]
  fn published_snapshot_is_world_scoped_and_cancelled_work_cannot_commit() {
    let service = Service::default();
    service.request(Some(context("one", "zh-Hant")), false);
    let generation = service.desired.lock().unwrap().generation;
    let bytes = manifest(serde_json::json!([{"text":"New label","translation":"新增標籤","kind":"plain"}]));
    assert!(service.commit(generation, prepare(&bytes, "one", "zh-Hant", |_| None).unwrap()));
    let key = crate::native_cache::CacheKey {
      world: "one".into(),
      language: "zh-Hant".into(),
      kind: "plain".into(),
      original: "New label".into(),
    };
    assert_eq!(service.lookup(&key, None).unwrap().translated, "新增標籤");
    assert!(
      service
        .lookup(
          &crate::native_cache::CacheKey {
            world: "other".into(),
            ..key.clone()
          },
          None
        )
        .is_none()
    );
    assert!(
      service
        .lookup(
          &crate::native_cache::CacheKey {
            language: "zh-Hans".into(),
            ..key
          },
          None
        )
        .is_none()
    );
    service.request(Some(context("other", "zh-Hant")), false);
    assert!(!service.commit(generation, prepare(&bytes, "one", "zh-Hant", |_| None).unwrap()));
  }
  #[test]
  fn pause_cancels_publication_and_new_model_results_win() {
    let service = Service::default();
    let ctx = context("one", "zh-Hant");
    service.request(Some(ctx.clone()), false);
    let generation = service.desired.lock().unwrap().generation;
    let bytes = manifest(serde_json::json!([{"text":"Changed label","translation":"新譯文","kind":"plain"}]));
    let snapshot = prepare(&bytes, "one", "zh-Hant", |_| Some((response("舊譯文"), false))).unwrap();
    assert!(service.commit(generation, snapshot));
    let key = crate::native_cache::CacheKey {
      world: "one".into(),
      language: "zh-Hant".into(),
      kind: "plain".into(),
      original: "Changed label".into(),
    };
    assert_eq!(
      service.lookup(&key, Some(&response("舊譯文"))).unwrap().translated,
      "新譯文"
    );
    assert!(service.lookup(&key, Some(&response("最新模型譯文"))).is_none());
    service.request(Some(ctx), true);
    assert!(!service.commit(generation, prepare(&bytes, "one", "zh-Hant", |_| None).unwrap()));
  }
  #[test]
  fn refresh_keeps_rows_from_the_previous_preload() {
    let service = service();
    let mut ctx = context("prewarm-reload-test", "zh-Hant");
    ctx.path = "missing-prewarm-fixture.json".into();
    service.request(Some(ctx.clone()), false);
    let generation = service.desired.lock().unwrap().generation;
    let bytes = serde_json::to_vec(&serde_json::json!({"version":1,"world":ctx.world,"revision":"first",
      "rows":[{"text":"Prewarm refresh fixture label","translation":"快照刷新測試標籤","kind":"plain"}]}))
    .unwrap();
    assert!(service.commit(
      generation,
      prepare(&bytes, &ctx.world, &ctx.language, |source| known(&ctx, source)).unwrap()
    ));
    let second = prepare(&bytes, &ctx.world, &ctx.language, |source| known(&ctx, source)).unwrap();
    assert_eq!(
      second.progress.imported, 1,
      "Preload rows must survive replacement of their old snapshot"
    );
    assert!(service.commit(generation, second));
    let key = crate::native_cache::CacheKey {
      world: ctx.world,
      language: ctx.language,
      kind: "plain".into(),
      original: "Prewarm refresh fixture label".into(),
    };
    assert_eq!(service.lookup(&key, None).unwrap().translated, "快照刷新測試標籤");
    service.request(None, false);
  }
  #[test]
  fn replacement_snapshot_removes_retired_search_rows_and_memo() {
    let language="prewarm-search-retirement";
    let service=Service::default();
    service.request(Some(context("one",language)),false);
    let generation=service.desired.lock().unwrap().generation;
    let make=|world:&str,rows| {
      let bytes=serde_json::to_vec(&serde_json::json!({"version":1,"world":world,
        "language":language,"revision":"fixture","rows":rows})).unwrap();
      prepare(&bytes,world,language,|_|None).unwrap()
    };
    let first=make("one",serde_json::json!([{"text":"Retired label","translation":"已移除譯文","kind":"plain"}]));
    assert!(service.commit(generation,first));
    assert!(crate::search::fixture_matches(language,"one","Retired label","移除"));
    assert!(service.commit(generation,make("one",serde_json::json!([]))));
    assert!(!crate::search::fixture_matches(language,"one","Retired label","移除"),
      "Search must retire rows and memo results omitted from an accepted snapshot");
    service.request(Some(context("two",language)),false);
    let next=service.desired.lock().unwrap().generation;
    let row=serde_json::json!([{"text":"Current label","translation":"目前譯文","kind":"plain"}]);
    assert!(service.commit(next,make("two",row.clone())));
    assert!(crate::search::fixture_matches(language,"two","Current label","目前"));
    assert!(!crate::search::fixture_matches(language,"one","Current label","目前"));
    assert!(!service.commit(generation,make("one",serde_json::json!([]))));
    assert!(crate::search::fixture_matches(language,"two","Current label","目前"),
      "Obsolete work must not clear the newer search snapshot");
    service.request(Some(context("two",language)),true);
    assert!(!service.commit(next,make("two",serde_json::json!([]))));
    assert!(crate::search::fixture_matches(language,"two","Current label","目前"),
      "Paused work must leave the last accepted snapshot intact");
  }
  #[test]
  #[ignore = "requires DF_LOCAL_PREWARM and DF_LOCAL_BENCH_OUTPUT; read-only real data benchmark"]
  fn real_manifest_bulk_load_and_repeat_skip_without_model_workers() {
    use std::sync::atomic::Ordering;
    let path = PathBuf::from(std::env::var("DF_LOCAL_PREWARM").unwrap());
    let started = Instant::now();
    let bytes = std::fs::read(&path).unwrap();
    let read_ms = started.elapsed().as_secs_f64() * 1000.0;
    let header: Manifest = serde_json::from_slice(&bytes).unwrap();
    let world = header.world.clone();
    let language = header.language.as_deref().unwrap_or("zh-Hant").to_owned();
    let before = crate::tasks::SUBMISSIONS.load(Ordering::SeqCst);
    let service = Service::default();
    service.request(
      Some(Context {
        path,
        world: world.clone(),
        language: language.clone(),
      }),
      false,
    );
    let generation = service.desired.lock().unwrap().generation;
    let snapshot = prepare(&bytes, &world, &language, |_| None).unwrap();
    let parse_validate_ms = snapshot.progress.elapsed_ms;
    let existing = snapshot.rows.clone();
    let load_started = Instant::now();
    assert!(service.commit(generation, snapshot));
    let publish_ms = load_started.elapsed().as_secs_f64() * 1000.0;
    let repeated = prepare(&bytes, &world, &language, |source| {
      existing.get(source).cloned().map(|r| (r, false))
    })
    .unwrap();
    assert_eq!(repeated.progress.imported, 0);
    assert_eq!(repeated.progress.ready, existing.len());
    assert_eq!(crate::tasks::SUBMISSIONS.load(Ordering::SeqCst), before);
    let result = serde_json::json!({"bytes":bytes.len(),"rows":header.rows.len(),"ready":existing.len(),
      "read_ms":read_ms,"parse_validate_ms":parse_validate_ms,"publish_search_ms":publish_ms,
      "repeat_ms":repeated.progress.elapsed_ms,"repeat_imported":0,"rejected":repeated.progress.stalled,
      "rejected_sources":repeated.progress.stalled_sources,"worker_submissions_added":0,"cold_load_ms":read_ms+parse_validate_ms+publish_ms});
    std::fs::write(
      std::env::var("DF_LOCAL_BENCH_OUTPUT").unwrap(),
      serde_json::to_vec_pretty(&result).unwrap(),
    )
    .unwrap();
    println!("PREWARM_BENCHMARK {result}");
  }
}
