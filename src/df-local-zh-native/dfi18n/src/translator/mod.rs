use lua53_sys as lua;

use crate::{broker_client, game, lang, native_cache, tasks, translation};

mod rulesets;
mod simple;
mod setup_adventure;
mod dungeon_labels;
mod fortress_labels;

const SYNC_RULE_BYTES:usize=160;
const WORKER_RULE_BYTES:usize=4096;

static REFRESHED_RULES:std::sync::atomic::AtomicBool=std::sync::atomic::AtomicBool::new(false);
fn refreshed_rules(language:&str,request:&translation::TranslationRequest)->Option<translation::TranslationResponse> {
  if REFRESHED_RULES.load(std::sync::atomic::Ordering::Relaxed) && request.original().len()<=SYNC_RULE_BYTES {
    rulesets::translate(language,request.context())
  } else {None}
}
#[unsafe(no_mangle)]
extern "C" fn local_rules_refresh(_state:*mut std::ffi::c_void)->i32 {
  // Fresh rules take precedence over old dynamic responses, without touching
  // persisted player caches or resetting attached renderers.
  REFRESHED_RULES.store(true,std::sync::atomic::Ordering::Relaxed);0
}

// Pure local lookup: safe on the preload thread, without Lua or DF state.
pub(crate) fn static_lookup(language:&str,source:&str)->Option<translation::TranslationResponse> {
  rulesets::translate_equipment(language,source)
    .or_else(||simple::translate(language,translation::TranslationRequest::lookup(source).context()))
    .or_else(||rulesets::translate_finite(language,source))
    .or_else(||combat_lookup(language,source))
    .or_else(||item_lookup(language,source))
    .or_else(||history_lookup(language,source))
    .or_else(||preference_lookup(language,source))
}
fn history_lookup(language:&str,source:&str)->Option<translation::TranslationResponse> {
  df_local_zh_broker::offline_history::lookup_with_terms(source,&|s|simple::literal_term(language,s)
    .or_else(||rulesets::translate_equipment(language,s).map(|r|r.translated)),language=="zh-Hans")
    .map(|translated|translation::TranslationResponse{translated,alignment:Default::default()})
}
fn item_lookup(language:&str,source:&str)->Option<translation::TranslationResponse> {
  df_local_zh_broker::offline_items::lookup(source,&|s|simple::literal_term(language,s)
      .or_else(||rulesets::preference_material(language,s))
      .or_else(||rulesets::translate_equipment(language,s).map(|r|r.translated))
      .or_else(||rulesets::translate_finite(language,s).map(|r|r.translated)),language=="zh-Hans")
      .map(|translated|translation::TranslationResponse{translated,alignment:Default::default()})
}
fn combat_lookup(language:&str,source:&str)->Option<translation::TranslationResponse> {
  df_local_zh_broker::offline_combat::lookup(source,&|s|simple::literal_term(language,s)
    .or_else(||rulesets::translate_equipment(language,s).map(|r|r.translated)),language=="zh-Hans")
    .map(|translated|translation::TranslationResponse{translated,alignment:Default::default()})
}
fn preference_lookup(language:&str,source:&str)->Option<translation::TranslationResponse> {
  df_local_zh_broker::offline_preferences::lookup(source,&|s|simple::literal_term(language,s)
    .or_else(||rulesets::preference_material(language,s))
    .or_else(||rulesets::translate_equipment(language,s).map(|r|r.translated))
    .or_else(||rulesets::translate_finite(language,s).map(|r|r.translated)),language=="zh-Hans")
    .map(|translated|translation::TranslationResponse{translated,alignment:Default::default()})
}
#[cfg(test)]
pub(crate) fn fixture_static(source:&str,translation:&str) {simple::fixture_insert(source,translation,"LEFT");}

// Reset the translators and translation caches
pub fn reset() {
  rulesets::reset();
  simple::reset();
}

// Check if the content should skip translation
pub fn should_skip_translation(original: &str) -> bool {
  // don't skip game version strings
  if Some(original) == game::try_version() {
    return false;
  }

  original.len() < 2
    || original.starts_with("FPS: ")
    || !original.chars().any(|c| c.is_ascii_alphabetic())
}

// Translate the given TranslationRequest
pub fn translate(request: &translation::TranslationRequest) -> Option<translation::TranslationResponse> {
  if let Some(response)=crate::search::display_query(request.original()) { return Some(response); }
  let lang_tag = lang::current_lang_tag();
  if let Some(response)=fortress_labels::translate(request.context(),&lang_tag) {return Some(response)}
  if let Some(response)=setup_adventure::translate(request.context(),&lang_tag) {return Some(response)}
  if let Some(response)=dungeon_labels::translate(request.context(),&lang_tag) {return Some(response)}
  if let Some(response)=crate::nickname_display::lookup(request.original(),&lang_tag) {return Some(response)}
  if let Some(response)=crate::official::fixed(&lang_tag,request.original()) {return Some(response)}
  if let Some(response)=crate::chinese::direct(request.original(),&lang_tag) { return Some(response); }

  if let Some(response)=static_lookup(&lang_tag,request.original()) {return Some(response)}
  let stable_key = native_cache::key(&lang_tag, request);
  if let Some(response)=refreshed_rules(&lang_tag,request) {return Some(response)}
  if let Some(response)=crate::official::lookup(&lang_tag,request.original()) {return Some(response)}
  if let Some(response) = native_cache::lookup(&stable_key) { return Some(response); }

  if should_skip_translation(request.original()) || !native_cache::begin(&stable_key) { return None; }

  // spawn a task to perform the translation
  let request = request.clone();
  tasks::spawn(async move {
    let _pending=native_cache::PendingGuard(stable_key.clone());
    let result=tokio::time::timeout(broker_client::timeout()+std::time::Duration::from_secs(5),async {
    let _permit = tasks::translation_permit().await;
    let response = std::panic::catch_unwind(|| do_translate_for_language(&request, &lang_tag))
      .unwrap_or_else(|_|{log::warn!("Local translation worker panicked; trying Broker");None})
      .filter(|response| native_cache::valid_translation(request.original(), &response.translated));
    let response = match response {
      Some(response) => Some(response),
      None => broker_client::translate_for(request.original(),&lang_tag,&stable_key.world).await,
    };
    if stable_key.world == native_cache::current_world() && lang_tag == lang::current_lang_tag() {
      response
    } else { None }
    }).await;
    if result.is_err() {log::warn!("Native translation deadline exceeded");}
    // The world/language key is captured before dispatch, so completions cannot leak.
    native_cache::complete(stable_key, result.unwrap_or(None));
  });

  // return no translation for now
  None
}

// The translation task that performs the actual translation
pub async fn translate_task(request: translation::TranslationRequest) {
  let _ = translate(&request);
}

pub fn known(request: &translation::TranslationRequest) -> Option<translation::TranslationResponse> {
  if let Some(response)=crate::search::display_query(request.original()) { return Some(response); }
  let language = lang::current_lang_tag();
  if let Some(response)=fortress_labels::translate(request.context(),&language) {return Some(response)}
  if let Some(response)=setup_adventure::translate(request.context(),&language) {return Some(response)}
  if let Some(response)=dungeon_labels::translate(request.context(),&language) {return Some(response)}
  if let Some(response)=crate::nickname_display::lookup(request.original(),&language) {return Some(response)}
  crate::official::fixed(&language,request.original())
    .or_else(||crate::chinese::direct(request.original(),&language))
    .or_else(||static_lookup(&language,request.original()))
    .or_else(||refreshed_rules(&language,request))
    .or_else(||crate::official::lookup(&language,request.original()))
    .or_else(|| native_cache::lookup(&native_cache::key(&language, request)))
}

// Perform the actual translation using different methods
pub fn do_translate(request: &translation::TranslationRequest) -> Option<translation::TranslationResponse> {
  // Lua callers run on the game thread. Long rules are resolved by translate's
  // deduplicated worker and become available through known/cache_lookup later.
  if request.original().len()>SYNC_RULE_BYTES { return simple::translate(&lang::current_lang_tag(),request.context()); }
  do_translate_for_language(request, &lang::current_lang_tag())
}

fn do_translate_for_language(request: &translation::TranslationRequest, lang_tag: &str) -> Option<translation::TranslationResponse> {
  // add MOD info to game version strings
  if Some(request.original()) == game::try_version() {
    let translated = format!(
      "{} + {}-{} v{}",
      game::version(),
      crate::MOD_NAME,
      game::os_platform(),
      game::mod_version()
    );

    return Some(translation::TranslationResponse {
      translated,
      alignment: translation::TextAlignment::default(),
    });
  }

  // chain translation methods
  None
    .or_else(|| simple::translate(lang_tag, request.context()))
    .or_else(|| if request.original().len() <= WORKER_RULE_BYTES { rulesets::translate(lang_tag, request.context()) } else { None })
}

// Synchronous translation function called from Lua (will not use cache)
#[unsafe(no_mangle)]
extern "C" fn sync_translate(lua_state: *mut std::ffi::c_void) -> i32 {
  let content = lua::check_string(lua_state, 1);
  let request = translation::TranslationRequest::lookup(&content);
  let response = known(&request).or_else(|| do_translate(&request));
  if let Some(response) = response {
    lua::push_string(lua_state, &response.translated.as_str());
  } else {
    lua::push_nil(lua_state);
  }
  return 1;
}

// Asynchronous translation function called from Lua
#[unsafe(no_mangle)]
extern "C" fn async_translate(lua_state: *mut std::ffi::c_void) -> i32 {
  let content = lua::check_string(lua_state, 1);
  let request = translation::TranslationRequest::lookup(&content);
  let response = translate(&request);
  if let Some(response) = response {
    lua::push_string(lua_state, &response.translated.as_str());
  } else {
    lua::push_nil(lua_state);
  }
  return 1;
}

#[unsafe(no_mangle)]
extern "C" fn cache_lookup(state: *mut std::ffi::c_void) -> i32 {
  let content = lua::check_string(state, 1);
  if let Some(response) = known(&translation::TranslationRequest::lookup(&content)) {
    lua::push_string(state, &response.translated);
  } else { lua::push_nil(state); }
  1
}

// Explicit pins and installed local data only: no learned/official cache and no
// dispatch. Lua unit adapters use this before their persisted display caches.
#[unsafe(no_mangle)]
extern "C" fn local_lookup(state:*mut std::ffi::c_void)->i32 {
  let source=lua::check_string(state,1);let language=lang::current_lang_tag();
  // Legends headings are requested before the broker's dictionary loader is
  // ready on a cold page. Keep these two finite labels available in the
  // synchronous native path as well as the broker dictionary.
  let response=match (language.as_str(),source.as_str()) {
    ("zh-Hant","Related Historical Figures")=>Some(translation::TranslationResponse{translated:"相關歷史人物".into(),alignment:Default::default()}),
    ("zh-Hans","Related Historical Figures")=>Some(translation::TranslationResponse{translated:"相关历史人物".into(),alignment:Default::default()}),
    ("zh-Hant","Related Entities")=>Some(translation::TranslationResponse{translated:"相關組織".into(),alignment:Default::default()}),
    ("zh-Hans","Related Entities")=>Some(translation::TranslationResponse{translated:"相关组织".into(),alignment:Default::default()}),
    _=>None,
  }.or_else(||crate::official::fixed(&language,&source))
    .or_else(||simple::reviewed(&language,&source))
    .or_else(||rulesets::translate_equipment(&language,&source))
    .or_else(||rulesets::translate_finite(&language,&source))
    .or_else(||item_lookup(&language,&source))
    .or_else(||history_lookup(&language,&source))
    .or_else(||preference_lookup(&language,&source));
  if let Some(response)=response {lua::push_string(state,&response.translated);} else {lua::push_nil(state);}
  1
}

#[cfg(test)]
mod immediate_tests {
  use super::*;
  use std::sync::atomic::Ordering;

  #[test]
  fn long_local_rule_is_available_to_worker_but_not_uncached_sync_lookup() {
    let path=std::env::temp_dir().join(format!("df-long-rule-test-{}",std::process::id()));
    std::fs::create_dir_all(&path).unwrap();
    let source="This ancient workshop was built by travelers from the northern mountains. Its carefully arranged furnaces can refine unusual metals and craft equipment for the defenders of the fortress.";
    std::fs::write(path.join("index.toml"),format!("[[rulesets]]\n[rulesets.rules]\n{source:?} = \"這座古老工坊能精煉特殊金屬，為要塞守軍製作裝備。\"\n")).unwrap();
    rulesets::fixture_rules("long-rule-test",&path);
    let request=translation::TranslationRequest::lookup(source);
    assert_eq!(do_translate_for_language(&request,"long-rule-test").map(|r|r.translated),
      Some("這座古老工坊能精煉特殊金屬，為要塞守軍製作裝備。".into()));
    // Refreshed rules are queried on render/cache lookup paths and must stay short.
    local_rules_refresh(std::ptr::null_mut());
    assert!(refreshed_rules("long-rule-test",&request).is_none());
    assert!(do_translate(&request).is_none());
    std::fs::remove_dir_all(path).unwrap();
  }

  #[test]
  fn worker_rule_limit_preserves_utf8_and_rejects_oversized_rules() {
    let path=std::env::temp_dir().join(format!("df-rule-boundary-test-{}",std::process::id()));
    std::fs::create_dir_all(&path).unwrap();
    let at_limit=format!("{}a", "界".repeat(1365));
    let over_limit=format!("{at_limit}b");
    assert_eq!(at_limit.len(),4096);
    std::fs::write(path.join("index.toml"),format!("[[rulesets]]\n[rulesets.rules]\n{at_limit:?} = \"界線內\"\n{over_limit:?} = \"界線外\"\n")).unwrap();
    rulesets::fixture_rules("rule-boundary-test",&path);
    assert_eq!(do_translate_for_language(&translation::TranslationRequest::lookup(&at_limit),"rule-boundary-test").map(|r|r.translated),Some("界線內".into()));
    assert!(do_translate_for_language(&translation::TranslationRequest::lookup(&over_limit),"rule-boundary-test").is_none());
    std::fs::remove_dir_all(path).unwrap();
  }

  #[test]
  #[ignore = "requires DF_MOD_SAMPLES and DF_LOCAL_RULESETS audit paths"]
  fn benchmark_real_mod_rules_without_ai() {
    rule_based_translator::register_default_replacers();
    rulesets::fixture_rules("mod-audit",std::path::Path::new(&std::env::var("DF_LOCAL_RULESETS").unwrap()));
    let samples:Vec<serde_json::Value>=serde_json::from_slice(&std::fs::read(std::env::var("DF_MOD_SAMPLES").unwrap()).unwrap()).unwrap();
    let mut records=Vec::new();
    for sample in samples {
      let source=sample["text"].as_str().unwrap();
      let request=translation::TranslationRequest::lookup(source);
      let start=std::time::Instant::now();
      let response=do_translate_for_language(&request,"mod-audit");
      let elapsed=start.elapsed().as_secs_f64()*1000.0;
      records.push(serde_json::json!({"mod_id":sample["mod_id"],"text":source,"bytes":source.len(),"old_limit_eligible":source.len()<=160,"milliseconds":elapsed,"translation":response.map(|r|r.translated)}));
    }
    std::fs::write(std::env::var("DF_MOD_BENCH_OUT").unwrap(),serde_json::to_vec_pretty(&records).unwrap()).unwrap();
  }

  #[test]
  fn refreshed_rule_precedes_old_dynamic_translation() {
    let path=std::env::temp_dir().join(format!("df-local-refresh-test-{}",std::process::id()));
    std::fs::create_dir_all(&path).unwrap();
    std::fs::write(path.join("index.toml"),"[[rulesets]]\n[rulesets.rules]\n\"Refresh fixture arrived\" = \"新版規則已抵達\"\n").unwrap();
    rulesets::fixture_rules("en",&path);
    let request=translation::TranslationRequest::fixture("Refresh fixture arrived",false,0);
    native_cache::fixture_complete(native_cache::key("en",&request),translation::TranslationResponse{
      translated:"舊快取".into(),alignment:Default::default()});
    local_rules_refresh(std::ptr::null_mut());
    assert_eq!(known(&request).unwrap().translated,"新版規則已抵達");
    std::fs::remove_file(path.join("index.toml")).unwrap();std::fs::remove_dir(path).unwrap();
  }

  #[test]
  fn exact_dictionary_returns_on_first_hook_call_without_a_worker() {
    simple::fixture_insert("Native exact hit", "原生當幀命中", "CENTER");
    let request = translation::TranslationRequest::fixture("Native exact hit", false, 0);
    let before = tasks::SUBMISSIONS.load(Ordering::SeqCst);
    let response = translate(&request).expect("Exact dictionary hit must return on the first Hook call");
    assert_eq!(response.translated, "原生當幀命中");
    assert!(matches!(response.alignment, translation::TextAlignment::Center));
    assert_eq!(tasks::SUBMISSIONS.load(Ordering::SeqCst), before);
  }

  #[test]
  fn complete_combat_label_returns_on_first_hook_without_a_worker() {
    simple::fixture_insert("Combat source weapon", "鐵彎刀", "LEFT");
    let request = translation::TranslationRequest::fixture("strike/pommel/Combat source weapon", false, 0);
    let before = tasks::SUBMISSIONS.load(Ordering::SeqCst);
    assert_eq!(translate(&request).unwrap().translated, "打擊／柄頭／鐵彎刀");
    assert_eq!(tasks::SUBMISSIONS.load(Ordering::SeqCst), before);
  }

  #[test]
  fn a_pending_miss_cannot_hide_a_new_dictionary_entry() {
    let request = translation::TranslationRequest::fixture("Known after miss", false, 0);
    assert!(native_cache::begin(&native_cache::key("en", &request)));
    simple::fixture_insert("Known after miss", "未命中後發布的中文", "LEFT");
    let response = translate(&request).expect("A pending placeholder must not shadow known Chinese");
    assert_eq!(response.translated, "未命中後發布的中文");
  }

  #[test]
  fn exact_colored_markup_keeps_palette_and_paragraph_tags() {
    let source = "[C:6:1:1]Colored announcement[B][C:7:0:0]Second line";
    let translated = "[C:6:1:1]彩色公告[B][C:7:0:0]第二行";
    simple::fixture_insert(source, translated, "LEFT");
    let request = translation::TranslationRequest::fixture(source, true, 0);
    assert_eq!(translate(&request).expect("Known markup must be synchronous").translated, translated);
  }

  #[test]
  fn completed_memory_result_is_shared_across_repaints_without_a_worker() {
    let request = translation::TranslationRequest::fixture("Completed native memory", false, 0);
    let expected = translation::TranslationResponse { translated: "完成的原生記憶體譯文".into(), alignment: translation::TextAlignment::Left };
    native_cache::fixture_complete(native_cache::key("en", &request), expected.clone());
    let before = tasks::SUBMISSIONS.load(Ordering::SeqCst);
    for flag in [0, 8, 0x80000000] {
      let repaint = translation::TranslationRequest::fixture("Completed native memory", false, flag);
      assert_eq!(translate(&repaint), Some(expected.clone()));
    }
    assert_eq!(tasks::SUBMISSIONS.load(Ordering::SeqCst), before);
  }

  #[test]
  fn equipment_noun_precedes_a_poisoned_persistent_cache() {
    rulesets::fixture_equipment("en", &[ ("iron", "鐵"), ("steel", "鋼") ],
      &[ ("pick", "十字鎬"), ("picks", "十字鎬"), ("battle axes", "戰斧") ]);
    let request = translation::TranslationRequest::fixture("Iron picks [3]", false, 0);
    simple::fixture_insert("Iron picks [3]", "鐵 拾取了 [3]", "LEFT");
    native_cache::fixture_complete(native_cache::key("en", &request),
      translation::TranslationResponse { translated: "鐵 拾取了 [3]".into(), alignment: translation::TextAlignment::Left });
    let before = tasks::SUBMISSIONS.load(Ordering::SeqCst);
    assert_eq!(translate(&request).unwrap().translated, "鐵十字鎬 [3]");
    assert_eq!(translate(&translation::TranslationRequest::fixture("Steel pick", false, 0)).unwrap().translated,
      "鋼十字鎬");
    assert_eq!(translate(&translation::TranslationRequest::fixture("Steel battle axes [2]", false, 0)).unwrap().translated,
      "鋼戰斧 [2]");
    assert!(rulesets::translate_equipment("en", "He picks up a stone.").is_none());
    assert!(rulesets::translate_equipment("en", "Pick").is_none());
    assert_eq!(tasks::SUBMISSIONS.load(Ordering::SeqCst), before);
  }
}
