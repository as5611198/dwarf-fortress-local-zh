use df_local_zh_broker::{
  common::*,
  official::{ENDPOINT, Official},
  service::App,
  settings::defaults,
};
use serde_json::{Value, json};
use std::{
  sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
  },
  time::{Duration, Instant},
};
fn files(d: &std::path::Path) -> std::path::PathBuf {
  let source = d.join("source");
  let state = d.join("state");
  std::fs::create_dir_all(&source).unwrap();
  std::fs::create_dir_all(&state).unwrap();
  std::fs::write(
    source.join("hant.csv"),
    "text,translation,tags\nHealth,健康,\nWounds,傷口,\nChange to standard dig mode.,切換至一般挖掘模式。,\n",
  )
  .unwrap();
  std::fs::write(
    source.join("hans.csv"),
    "text,translation,tags\nHealth,健康,\nWounds,伤口,\nChange to standard dig mode.,切换至一般挖掘模式。,\n",
  )
  .unwrap();
  let mut settings = defaults();
  settings["officialAutoDownload"] = json!(false);
  atomic(
    &state.join("settings.json"),
    &json!({"version":1,"defaults":settings,"saves":{}}),
  )
  .unwrap();
  atomic(&source.join("config.json"),&json!({"port":19754,"language":"zh-Hant","staticDictionariesByLanguage":{"zh-Hant":["hant.csv"],"zh-Hans":["hans.csv"]}})).unwrap();
  source.join("config.json")
}

#[tokio::test]
async fn removed_registry_retires_cached_names_and_recreated_world_is_isolated() {
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let app = App::load(&cfg, &root).unwrap();
  let path = root.join("data/world-names.json");
  atomic(&path, &json!({"world":"old","entities":[{"id":"figure:1","aliases":["Urist"]}]})).unwrap();
  let old = app.registry("old");
  assert_eq!(old["entities"][0]["aliases"][0], "Urist");
  assert!(Arc::ptr_eq(&old, &app.registry("old")), "unchanged revision should share its snapshot");
  std::fs::remove_file(&path).unwrap();
  assert_eq!(app.registry("old")["entities"], json!([]), "removed names must not survive in the broker");
  let retired = Arc::downgrade(&old);
  drop(old);
  assert!(retired.upgrade().is_none(), "no historical registry remains owned by the cache");
  atomic(&path, &json!({"world":"new","entities":[{"id":"figure:2","aliases":["Domas"]}]})).unwrap();
  assert_eq!(app.registry("new")["entities"][0]["aliases"][0], "Domas");
  assert_eq!(app.registry("old")["entities"], json!([]));
}

#[tokio::test]
async fn registry_index_restores_names_and_updates_identity_without_provider_calls() {
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  atomic(&cfg.parent().unwrap().join("name-dictionary.json"), &json!({"Urist":"烏里斯特","Domas":"多瑪斯"})).unwrap();
  let template = "{{DFE0}} arrived.";
  append(&root.join("translations.jsonl"), &json!({"policy":POLICY,"language":"zh-Hant","kind":"entity",
    "source":template,"key":cache_key(template,"zh-Hant","entity"),"translation":"{{DFE0}}抵達了。"})).unwrap();
  let app = App::load(&cfg, &root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  atomic(&root.join("active-context.json"), &json!({"version":1,"world":"names","language":"zh-Hant"})).unwrap();
  let path = app.runtime.join("world-names.json");
  atomic(&path, &json!({"world":"names","entities":[
    {"id":"figure:1","nativeName":"Urist","aliases":["Urist"]},
    {"id":"figure:2","nativeName":"Domas","aliases":["Urist","Domas"]},
    {"id":"figure:3","aliases":["NotMentioned"]}
  ]})).unwrap();
  // Shared aliases still resolve in registry order, not hash-map iteration order.
  assert_eq!(app.translate("Urist arrived.", "zh-Hant", "names", 0).await.unwrap(), "多瑪斯抵達了。");
  assert_eq!(app.pin("figure:1", "zh-Hant", "names").await.unwrap(), "烏里斯特");
  let request = json!({"world":"names","language":"zh-Hant","text":"Urist","kind":"legends-name",
    "namePolicy":"native-v2","entityKind":"figure","entityId":1});
  assert_eq!(app.runtime_row(&request).await.unwrap()["translation"], "烏里斯特");
  atomic(&path, &json!({"world":"names","entities":[
    {"id":"figure:1","nativeName":"Domas","aliases":["Domas"]}
  ]})).unwrap();
  assert_eq!(app.pin("figure:1", "zh-Hant", "names").await.unwrap(), "多瑪斯");
  assert!(app.runtime_row(&request).await.is_err(), "retired native identity must not be accepted");
  assert_eq!(app.translate("Domas arrived.", "zh-Hant", "names", 0).await.unwrap(), "多瑪斯抵達了。");
  assert_eq!(app.pool.requests.load(Ordering::Relaxed), 0);
}

#[tokio::test]
async fn evicted_translation_remains_available_offline_after_restart_without_rewriting_journal() {
  use std::io::Write;
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let path = root.join("translations.jsonl");
  let mut journal = std::io::BufWriter::new(std::fs::File::create(&path).unwrap());
  let first = "The old translation must remain available.";
  let row = |source: &str, translation: &str| json!({"policy":POLICY,"language":"zh-Hant","kind":"exact",
    "source":source,"key":cache_key(source,"zh-Hant","exact"),"translation":translation});
  writeln!(journal,"{}",row(first,"舊譯文必須仍可使用。")).unwrap();
  for i in 0..16_384 {
    writeln!(journal,"{}",row(&format!("Archived message {i}."),&format!("歷史訊息 {i}。"))).unwrap();
  }
  journal.flush().unwrap();
  drop(journal);
  let before = std::fs::read(&path).unwrap();
  for _ in 0..2 {
    let app = App::load(&cfg, &root).unwrap();
    app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
    assert_eq!(app.translate(first,"zh-Hant","",0).await.unwrap(),"舊譯文必須仍可使用。");
    assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
    assert!(app.health()["cached"].as_u64().unwrap() <= 16_384);
  }
  assert_eq!(std::fs::read(path).unwrap(),before);
}

#[tokio::test]
async fn damaged_cache_query_is_not_sent_to_provider_and_releases_pending() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global",
    "profiles":[{"id":"fixture","enabled":true,"baseUrl":"http://127.0.0.1:1","model":"fixture"}],
    "settings":{"apiProfile":"fixture"}})).unwrap();
  let db=rusqlite::Connection::open(root.join("translations-index-v1.sqlite3")).unwrap();
  db.execute_batch("DROP TABLE records").unwrap();drop(db);
  assert!(app.translate("Cache failure must not spend tokens.","zh-Hant","",0).await.is_err());
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
  assert_eq!(app.health()["pending"],0);
}

#[tokio::test]
async fn reviewed_prose_is_available_without_ai_and_outranks_old_paragraphs() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let source="He is stubborn.  He dreams of raising a family.";
  std::fs::write(cfg.parent().unwrap().join("hant.csv"),format!(
    "text,translation,tags\nHe is stubborn.,他很固執。,[REVIEWED:1][PROSE:sentence]\nHe dreams of raising a family.,他夢想建立家庭。,[REVIEWED:1][PROSE:sentence]\n{source},舊譯文,\n")).unwrap();
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  assert_eq!(app.translate(source,"zh-Hant","",0).await.unwrap(),"他很固執。  他夢想建立家庭。");
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}

#[tokio::test]
async fn numeric_ui_changes_translate_offline_before_old_cache_and_respect_pins() {
  let d=tempfile::tempdir().unwrap();
  let cfg=files(d.path());
  let root=d.path().join("state");
  for (lang,file) in [("zh-Hant","hant.csv"),("zh-Hans","hans.csv")] {
    let rows=include_str!("../../../data-patches/simple/zh-Hant/numeric-ui.csv");
    std::fs::write(cfg.parent().unwrap().join(file),convert(rows,lang)).unwrap();
    append(&root.join("translations.jsonl"),&json!({"policy":POLICY,"language":lang,"kind":"exact",
      "source":"Sound Effects Volume (Fortress): 77%","key":cache_key("Sound Effects Volume (Fortress): 77%",lang,"exact"),
      "translation":"舊音效 77%"})).unwrap();
    atomic(&root.join(format!("fixed-{lang}.json")),&json!({"Master Volume: 42%":"自訂音量 42%"})).unwrap();
  }
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  let journal=std::fs::read(root.join("translations.jsonl")).unwrap();
  for lang in ["zh-Hant","zh-Hans"] {
    for n in 0..=100 {
      let source=format!("Sound Effects Volume (Fortress): {n}%");
      assert_eq!(app.translate(&source,lang,"",0).await.unwrap(),convert(&format!("音效音量（要塞）：{n}%"),lang));
    }
    assert_eq!(app.translate("Master Volume: 42%",lang,"",0).await.unwrap(),"自訂音量 42%");
    assert_eq!(app.translate("[C:2:0:1]Historical figures: 12,345",lang,"",0).await.unwrap(),convert("[C:2:0:1]歷史人物：12,345",lang));
    assert!(app.translate("Sound Effects Volume (Fortress): 1,23%",lang,"",0).await.is_err());
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
  assert_eq!(std::fs::read(root.join("translations.jsonl")).unwrap(),journal);
}

async fn single_runtime_sentence_reaches_provider(priority: &str) {
  use axum::{Json, Router, routing::post};
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let address = listener.local_addr().unwrap();
  let requests = Arc::new(AtomicUsize::new(0));
  let observed = requests.clone();
  let server = tokio::spawn(async move {
    axum::serve(listener, Router::new().route("/chat/completions", post(move |Json(body): Json<Value>| {
      let observed = observed.clone();
      async move {
        observed.fetch_add(1, Ordering::Relaxed);
        let input: Value = serde_json::from_str(body["messages"][1]["content"].as_str().unwrap()).unwrap();
        let items = input["items"].as_array().unwrap();
        assert_eq!(items.len(), 1, "A singleton must not wait for a second sentence");
        Json(json!({"choices":[{"message":{"content":json!({"translations":[{
          "id":items[0]["id"],"translation":"只有這一句等待翻譯。"
        }]}).to_string()}}]}))
      }
    }))).await.unwrap();
  });
  let app = App::load(&cfg, &root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global",
    "profiles":[{"id":"fixture","enabled":true,"baseUrl":format!("http://{address}"),"model":"fixture"}],
    "settings":{"apiProfile":"fixture"}})).unwrap();
  atomic(&root.join("active-context.json"), &json!({"version":1,"world":"region-test","language":"zh-Hant"})).unwrap();
  atomic(&root.join("data/runtime-visible.json"), &json!({"world":"region-test","ids":[]})).unwrap();
  append(&root.join("data/runtime-requests.jsonl"), &json!({"world":"region-test","language":"zh-Hant",
    "text":"A lone sentence awaits translation.","priority":priority})).unwrap();
  let worker = tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  let started = Instant::now();
  let completion = tokio::time::timeout(Duration::from_secs(2), async {
    loop {
      if let Ok(text) = std::fs::read_to_string(root.join("data/runtime-responses.jsonl")) {
        if let Some(line) = text.lines().find(|line| !line.is_empty()) {
          break serde_json::from_str::<Value>(line).unwrap();
        }
      }
      tokio::time::sleep(Duration::from_millis(10)).await;
    }
  }).await;
  worker.abort();
  server.abort();
  let row = completion.expect("One ordinary sentence must dispatch even when the Legends visibility list is empty");
  assert_eq!(row["translation"], "只有這一句等待翻譯。");
  assert_eq!(requests.load(Ordering::Relaxed), 1);
  assert_eq!(app.published.load(Ordering::Relaxed), 1);
  println!("SINGLE_RUNTIME {priority}: {} ms, one provider request", started.elapsed().as_millis());
}

#[tokio::test]
async fn single_foreground_runtime_sentence_dispatches_without_legends_visibility() {
  single_runtime_sentence_reaches_provider("foreground").await;
}

#[tokio::test]
#[cfg(windows)]
async fn startup_history_sharing_violations_recover_without_resetting_completed_or_terminal_work() {
  use std::os::windows::fs::OpenOptionsExt;
  for journal in ["runtime-responses.jsonl","runtime-failures.jsonl"] {
    let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
    let app=App::load(&cfg,&root).unwrap();
    app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
    atomic(&root.join("active-context.json"),&json!({"version":1,"world":"recovery","language":"zh-Hant"})).unwrap();
    let request=json!({"world":"recovery","language":"zh-Hant","text":"Health","priority":"foreground"});
    let mut historical=app.runtime_row(&request).await.unwrap();
    if journal=="runtime-failures.jsonl" {
      let settings=app.settings.lock().unwrap();
      historical["attempts"]=json!(31);historical["terminal"]=json!(true);
      historical["retryGeneration"]=json!(hash(serde_json::to_vec(&json!([
        settings.effective("recovery"),settings.selected("recovery"),Value::Null
      ])).unwrap()));
    }
    let history_path=app.runtime.join(journal);append(&history_path,&historical).unwrap();
    let held=std::fs::OpenOptions::new().read(true).share_mode(0).open(&history_path).unwrap();
    append(&app.runtime.join("runtime-requests.jsonl"),&request).unwrap();
    let mut fresh=request;fresh["text"]=json!("Wounds");
    append(&app.runtime.join("runtime-requests.jsonl"),&fresh).unwrap();
    atomic(&root.join("settings-request.json"),&json!({"id":"during-recovery","action":"save",
      "scope":"global","settings":{"apiEnabled":false}})).unwrap();
    let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
    let settings_responsive=tokio::time::timeout(Duration::from_secs(2),async {
      loop {
        if read_json(&root.join("settings-response.json"),65536)
          .is_ok_and(|r|r["id"]=="during-recovery" && r["ok"]==true) {break;}
        tokio::time::sleep(Duration::from_millis(20)).await;
      }
    }).await.is_ok();
    let waiting_status=tokio::time::timeout(Duration::from_secs(2),async {
      loop {
        if let Ok(status)=read_json(&app.runtime.join("broker-status.json"),32768) {
          if status["runtime"]["history"]["state"]=="retrying" {break status;}
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
      }
    }).await.unwrap_or(Value::Null);
    let attempts_while_locked=app.attempted.load(Ordering::Relaxed);
    drop(held);
    let recovered=tokio::time::timeout(Duration::from_secs(4),async {
      loop {
        if app.published.load(Ordering::Relaxed)>0 && read_json(&app.runtime.join("broker-status.json"),32768)
          .is_ok_and(|v|v["runtime"]["history"]["state"]=="ready") {break;}
        tokio::time::sleep(Duration::from_millis(20)).await;
      }
    }).await;
    worker.abort();let _=worker.await;
    assert_eq!(attempts_while_locked,0,"{journal}: incomplete history must not reset completed work or retry budgets");
    assert!(settings_responsive,"History recovery must not block settings delivery");
    assert_eq!(waiting_status["runtime"]["history"]["state"],"retrying");
    recovered.expect("Releasing a history lock must recover automatically without another request or restart");
    assert_eq!(app.attempted.load(Ordering::Relaxed),1,"Only fresh Wounds may dispatch after history recovery");
    assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
  }
}

#[tokio::test]
async fn history_recovery_rechecks_the_current_world_and_language_before_dispatch() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"old","language":"zh-Hant"})).unwrap();
  let old=json!({"world":"old","language":"zh-Hant","text":"Health","priority":"foreground"});
  let historical=app.runtime_row(&old).await.unwrap();
  let history=app.runtime.join("runtime-responses.jsonl");std::fs::create_dir(&history).unwrap();
  append(&app.runtime.join("runtime-requests.jsonl"),&old).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::sleep(Duration::from_millis(250)).await;
  let while_blocked=app.attempted.load(Ordering::Relaxed);
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"new","language":"zh-Hans"})).unwrap();
  append(&app.runtime.join("runtime-requests.jsonl"),&json!({"world":"new","language":"zh-Hans","text":"Wounds","priority":"foreground"})).unwrap();
  std::fs::remove_dir(&history).unwrap();append(&history,&historical).unwrap();
  let result=tokio::time::timeout(Duration::from_secs(3),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(20)).await;}
  }).await;
  worker.abort();let _=worker.await;
  result.expect("Recovery must resume in the currently active scope");
  assert_eq!(while_blocked,0);assert_eq!(app.attempted.load(Ordering::Relaxed),1);
  let lines=std::fs::read_to_string(&history).unwrap();
  let rows:Vec<Value>=lines.lines().map(|s|serde_json::from_str(s).unwrap()).collect();
  assert_eq!(rows.len(),2,"Old work must not be re-published after the scope switch");
  assert_eq!(rows[1]["world"],"new");assert_eq!(rows[1]["language"],"zh-Hans");
  assert_eq!(rows[1]["translation"],"伤口");
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}

#[tokio::test]
async fn startup_journal_corruption_does_not_forget_later_completed_work() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"journal-test","language":"zh-Hant"})).unwrap();
  let request=json!({"world":"journal-test","language":"zh-Hant","text":"Health","priority":"foreground"});
  let completed=app.runtime_row(&request).await.unwrap();
  std::fs::write(app.runtime.join("runtime-responses.jsonl"),b"\xff\xfe\n").unwrap();
  append(&app.runtime.join("runtime-responses.jsonl"),&completed).unwrap();
  append(&app.runtime.join("runtime-requests.jsonl"),&request).unwrap();
  let mut fresh=request;fresh["text"]=json!("Wounds");
  append(&app.runtime.join("runtime-requests.jsonl"),&fresh).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  let result=tokio::time::timeout(Duration::from_secs(3),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(10)).await;}
  }).await;
  worker.abort();let _=worker.await;
  result.expect("Healthy new work must still complete after a corrupt history row");
  assert_eq!(app.attempted.load(Ordering::Relaxed),1,"Completed Health must be restored even after invalid UTF-8, leaving only Wounds to dispatch");
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}

#[tokio::test]
async fn journal_large_valid_legends_request_reaches_completion_without_api() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let link_text="A".repeat(2000);
  std::fs::write(cfg.parent().unwrap().join("hant.csv"),format!("text,translation,tags\n{link_text},已知長名稱,\n")).unwrap();
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"apiEnabled":false}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"journal-test","language":"zh-Hant"})).unwrap();
  atomic(&app.runtime.join("runtime-visible.json"),&json!({"world":"journal-test","ids":["paragraph"]})).unwrap();
  let links:Vec<_>=(0..64).map(|id|json!({"type":1,"id":id,"text":link_text})).collect();
  let text=(0..64).map(|i|format!("{{{{DFL{i}}}}}")).collect::<Vec<_>>().join(" ");
  let request=json!({"world":"journal-test","language":"zh-Hant","text":text,"links":links,
    "kind":"legends-paragraph","namePolicy":"native-v2","subjectId":1,"visibilityId":"paragraph","priority":"foreground"});
  assert!(serde_json::to_vec(&request).unwrap().len()>64*1024);
  append(&app.runtime.join("runtime-requests.jsonl"),&request).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  let result=tokio::time::timeout(Duration::from_secs(3),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(10)).await;}
  }).await;
  worker.abort();
  result.expect("A syntactically valid 64-link request must not be silently discarded by the journal reader");
  let rows=std::fs::read_to_string(app.runtime.join("runtime-responses.jsonl")).unwrap();
  let response:Value=serde_json::from_str(rows.lines().next().unwrap()).unwrap();
  assert_eq!(response["translation"],text);
  assert_eq!(response["links"].as_array().unwrap().len(),64);
  for link in response["links"].as_array().unwrap() {assert_eq!(link["translation"],"已知長名稱");}
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}

#[tokio::test]
async fn runtime_language_switch_replays_the_previously_inactive_journal() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"region-test","language":"zh-Hant"})).unwrap();
  append(&root.join("data/runtime-requests.jsonl"),&json!({"world":"region-test","language":"zh-Hans","text":"Wounds","priority":"foreground"})).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::sleep(Duration::from_millis(250)).await;
  assert_eq!(app.published.load(Ordering::Relaxed),0,"Inactive language must not dispatch");
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"region-test","language":"zh-Hans"})).unwrap();
  let result=tokio::time::timeout(Duration::from_secs(2),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(10)).await;}
  }).await;
  worker.abort();result.expect("A context switch must reconsider deferred journal rows");
}

#[tokio::test]
async fn paused_runtime_queue_reports_real_backlog_without_provider_work() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","settings":{"backgroundTranslation":false}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"region-test","language":"zh-Hant"})).unwrap();
  for text in ["Health","Wounds"] {
    append(&root.join("data/runtime-requests.jsonl"),&json!({"world":"region-test","language":"zh-Hant","text":text,"priority":"background"})).unwrap();
  }
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::sleep(Duration::from_millis(650)).await;
  let status=read_json(&root.join("data/broker-status.json"),32768).unwrap();worker.abort();
  assert_eq!(status["runtime"]["backgroundQueued"],2,"Queued is not the count of HTTP requests");
  assert_eq!(status["runtime"]["foregroundActive"],0);
}

#[tokio::test]
async fn runtime_visibility_change_reconsiders_a_previously_hidden_sentence() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"visibility-test","language":"zh-Hant"})).unwrap();
  append(&root.join("data/runtime-requests.jsonl"),&json!({"world":"visibility-test","language":"zh-Hant",
    "text":"Wounds","priority":"foreground","visibilityId":"view-1"})).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::sleep(Duration::from_millis(250)).await;
  assert_eq!(app.published.load(Ordering::Relaxed),0);
  atomic(&root.join("data/runtime-visible.json"),&json!({"world":"visibility-test","ids":["view-1"]})).unwrap();
  let result=tokio::time::timeout(Duration::from_secs(2),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(20)).await;}
  }).await;
  worker.abort();result.expect("Returning to a view must replay its skipped requests");
}

#[tokio::test]
async fn runtime_settings_response_write_failure_retains_the_request_until_delivery() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  // A directory at the response path simulates denied/failed atomic replacement.
  std::fs::create_dir(root.join("settings-response.json")).unwrap();
  atomic(&root.join("settings-request.json"),&json!({"id":"write-failure","action":"snapshot"})).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::sleep(Duration::from_millis(450)).await;
  let retained=read_json(&root.join("settings-request.json"),32768).unwrap()["id"]=="write-failure";
  std::fs::remove_dir(root.join("settings-response.json")).unwrap();
  let result=tokio::time::timeout(Duration::from_secs(3),async {
    loop {
      if read_json(&root.join("settings-response.json"),32768).is_ok_and(|r|r["id"]=="write-failure") {break}
      tokio::time::sleep(Duration::from_millis(20)).await;
    }
  }).await;
  worker.abort();
  assert!(retained,"Never acknowledge a request before its response is durable");
  result.expect("Delivery must retry without repeating the settings operation");
}

#[tokio::test]
async fn single_background_runtime_sentence_dispatches_without_legends_visibility() {
  single_runtime_sentence_reaches_provider("background").await;
}
#[tokio::test]
async fn runtime_failed_sentence_is_retried_without_another_journal_request() {
  use axum::{Json,Router,routing::post};
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();let address=listener.local_addr().unwrap();
  let requests=Arc::new(AtomicUsize::new(0));let observed=requests.clone();
  let server=tokio::spawn(async move {axum::serve(listener,Router::new().route("/chat/completions",post(move || {
    let observed=observed.clone();async move {
      let n=observed.fetch_add(1,Ordering::Relaxed);
      Json(json!({"choices":[{"message":{"content":json!({"translations":[{"id":"0","translation":if n==0 {"Still English"}else{"他很樂觀。"}}]}).to_string()}}]}))
    }
  }))).await.unwrap()});
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","profiles":[{"id":"fixture","enabled":true,"baseUrl":format!("http://{address}"),"model":"fixture"}],"settings":{"apiProfile":"fixture","retryBaseMs":100,"maxRetries":1}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"retry-test","language":"zh-Hant"})).unwrap();
  append(&root.join("data/runtime-requests.jsonl"),&json!({"world":"retry-test","language":"zh-Hant","text":"He is optimistic.","priority":"foreground"})).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  let result=tokio::time::timeout(Duration::from_secs(3),async {
    while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(20)).await;}
  }).await;
  worker.abort();server.abort();
  result.expect("A failed job must be requeued without another UI request");
  assert_eq!(requests.load(Ordering::Relaxed),2);
}
#[tokio::test]
async fn full_published_package_loads_with_isolated_state() {
  let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../distribution/steam/df-local-zh-complete");
  let d = tempfile::tempdir().unwrap();
  let app = App::load(&root.join("broker/config.json"), d.path()).unwrap();
  assert_eq!(app.translate("Wounds", "zh-Hant", "", 0).await.unwrap(), "傷口");
}

#[tokio::test]
async fn completed_name_registry_retries_terminal_prose_once() {
  use axum::{Json,Router,routing::post};
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let listener=tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();let address=listener.local_addr().unwrap();
  let count=Arc::new(AtomicUsize::new(0));let seen=count.clone();
  let server=tokio::spawn(async move {axum::serve(listener,Router::new().route("/chat/completions",post(move || {
    let seen=seen.clone();async move {
      let n=seen.fetch_add(1,Ordering::Relaxed);
      Json(json!({"choices":[{"message":{"content":json!({"translations":[{"id":"0","translation":if n==0 {"Still English"} else {"一支探險隊抵達了。"}}]}).to_string()}}]}))
    }
  }))).await.unwrap()});
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","profiles":[{"id":"fixture","enabled":true,"baseUrl":format!("http://{address}"),"model":"fixture"}],"settings":{"apiProfile":"fixture","maxRetries":0}})).unwrap();
  atomic(&root.join("active-context.json"),&json!({"version":1,"world":"registry-test","language":"zh-Hant"})).unwrap();
  append(&root.join("data/runtime-requests.jsonl"),&json!({"world":"registry-test","language":"zh-Hant","text":"An expedition has arrived.","priority":"foreground"})).unwrap();
  let worker=tokio::spawn(df_local_zh_broker::service::run_background(app.clone()));
  tokio::time::timeout(Duration::from_secs(2),async {while app.failed.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(20)).await;}}).await.unwrap();
  tokio::time::sleep(Duration::from_millis(350)).await;
  assert_eq!(count.load(Ordering::Relaxed),1,"Terminal validation errors must not spin");
  atomic(&root.join("data/world-names.json"),&json!({"version":1,"world":"registry-test","entities":[]})).unwrap();
  let result=tokio::time::timeout(Duration::from_secs(2),async {while app.published.load(Ordering::Relaxed)==0 {tokio::time::sleep(Duration::from_millis(20)).await;}}).await;
  worker.abort();server.abort();
  result.expect("New name context must reconsider prose rejected before export finished");
  assert_eq!(count.load(Ordering::Relaxed),2);
}
#[tokio::test]
async fn offline_bilingual_reload_fixed_priority_and_no_mutation() {
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  atomic(&root.join("fixed-zh-Hant.json"), &json!({"Health":"自訂健康"})).unwrap();
  let app = App::load(&cfg, &root).unwrap();
  let before = std::fs::read(root.join("api-profiles.private.json")).unwrap();
  assert_eq!(app.translate("Health", "zh-Hant", "", 0).await.unwrap(), "自訂健康");
  assert_eq!(app.translate("Wounds", "zh-Hant", "", 0).await.unwrap(), "傷口");
  assert_eq!(app.translate("Wounds", "zh-Hans", "", 0).await.unwrap(), "伤口");
  assert!(app.translate("Unknown prose", "zh-Hant", "", 0).await.is_err());
  assert_eq!(app.pool.requests.load(Ordering::Relaxed), 0);
  drop(app);
  let restarted = App::load(&cfg, &root).unwrap();
  assert_eq!(restarted.translate("Wounds", "zh-Hans", "", 0).await.unwrap(), "伤口");
  assert_eq!(std::fs::read(root.join("api-profiles.private.json")).unwrap(), before);
}
#[tokio::test]
async fn rust_requests_batch_deduplicate_mask_names_and_restart_cache() {
  use axum::{Json, Router, routing::post};
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let count = Arc::new(AtomicUsize::new(0));
  let seen = Arc::new(std::sync::Mutex::new(Vec::<Value>::new()));
  let count2 = count.clone();
  let seen2 = seen.clone();
  let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let addr = listener.local_addr().unwrap();
  let router = Router::new().route(
    "/chat/completions",
    post(move |Json(body): Json<Value>| {
      let c = count2.clone();
      let seen = seen2.clone();
      async move {
        c.fetch_add(1, Ordering::Relaxed);
        assert_eq!(body["temperature"], 0);
        seen.lock().unwrap().push(body.clone());
        let input: Value = serde_json::from_str(body["messages"][1]["content"].as_str().unwrap()).unwrap();
        let rows = input["items"]
          .as_array()
          .unwrap()
          .iter()
          .map(|r| {
            let text = r["text"].as_str().unwrap();
            let translated = match text {
              "He is optimistic." => "他很樂觀。",
              "She is calm." => "她很冷靜。",
              "{{DFE0}} is optimistic." => "{{DFE0}}很樂觀。",
              _ => "健康",
            };
            json!({"id":r["id"],"translation":translated})
          })
          .collect::<Vec<_>>();
        tokio::time::sleep(Duration::from_millis(40)).await;
        Json(json!({"choices":[{"message":{"content":json!({"translations":rows}).to_string()}}]}))
      }
    }),
  );
  let server = tokio::spawn(async move { axum::serve(listener, router).await.unwrap() });
  let app = App::load(&cfg, &root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","profiles":[{"id":"fixture","enabled":true,"baseUrl":format!("http://{addr}"),"model":"fixture-model","key":"test-only"}],"settings":{"apiProfile":"fixture","concurrency":2}})).unwrap();
  let (a, b, c) = tokio::join!(
    app.translate("He is optimistic.", "zh-Hant", "", 0),
    app.translate("He is optimistic.", "zh-Hant", "", 0),
    app.translate("She is calm.", "zh-Hant", "", 0)
  );
  assert_eq!(a.unwrap(), "他很樂觀。");
  assert_eq!(b.unwrap(), "他很樂觀。");
  assert_eq!(c.unwrap(), "她很冷靜。");
  assert!(count.load(Ordering::Relaxed) <= 2);
  assert_eq!(app.pool.items.load(Ordering::Relaxed), 2);
  atomic(
    &root.join("active-context.json"),
    &json!({"version":1,"world":"region-test","language":"zh-Hant"}),
  )
  .unwrap();
  atomic(
    &root.join("data/world-names.json"),
    &json!({"world":"region-test","entities":[{"id":"figure:1","preferred":"Urist","aliases":["Urist"]}]}),
  )
  .unwrap();
  std::fs::write(
    cfg.parent().unwrap().join("name-dictionary.json"),
    "{\"Urist\":\"烏瑞斯特\"}",
  )
  .unwrap();
  let restarted = App::load(&cfg, &root).unwrap();
  assert_eq!(
    restarted.translate("Urist is optimistic.", "zh-Hant", "region-test", 0).await.unwrap(),
    "烏瑞斯特很樂觀。"
  );
  assert!(seen.lock().unwrap().iter().all(|v| !v.to_string().contains("Urist")));
  server.abort();
  assert_eq!(
    restarted.translate("He is optimistic.", "zh-Hant", "", 0).await.unwrap(),
    "他很樂觀。"
  );
  assert!(!root.join("shared/state.json").exists());
}
#[tokio::test]
async fn sync_acknowledgement_never_changes_unsaved_settings_or_api_drafts() {
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let app = App::load(&cfg, &root).unwrap();
  let before = std::fs::read(root.join("settings.json")).unwrap();
  let key = std::fs::read(root.join("api-profiles.private.json")).unwrap();
  let answer =
    app.settings_request(&json!({"id":"fixture-sync","action":"official-sync","language":"zh-Hant"})).await.unwrap();
  assert_eq!(answer["ok"], true);
  assert!(answer.get("snapshot").is_none());
  assert_eq!(std::fs::read(root.join("settings.json")).unwrap(), before);
  assert_eq!(std::fs::read(root.join("api-profiles.private.json")).unwrap(), key);
}
#[tokio::test]
async fn failed_api_falls_back_to_second_profile_without_leaking_error_body() {
  use axum::{Json, Router, http::StatusCode, routing::post};
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let a = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let b = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
  let aa = a.local_addr().unwrap();
  let bb = b.local_addr().unwrap();
  let bad = tokio::spawn(async move {
    axum::serve(
      a,
      Router::new().route(
        "/chat/completions",
        post(|| async { (StatusCode::UNAUTHORIZED, "private-key-in-error-body") }),
      ),
    )
    .await
    .unwrap()
  });
  let good = tokio::spawn(async move {
    axum::serve(
      b,
      Router::new().route(
        "/chat/completions",
        post(|Json(body): Json<Value>| async move {
          let input: Value = serde_json::from_str(body["messages"][1]["content"].as_str().unwrap()).unwrap();
          let rows = input["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|r| json!({"id":r["id"],"translation":"他很樂觀。"}))
            .collect::<Vec<_>>();
          Json(json!({"choices":[{"message":{"content":json!({"translations":rows}).to_string()}}]}))
        }),
      ),
    )
    .await
    .unwrap()
  });
  let app = App::load(&cfg, &root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"global","profiles":[{"id":"first","enabled":true,"baseUrl":format!("http://{aa}"),"model":"fixture"},{"id":"second","enabled":true,"baseUrl":format!("http://{bb}"),"model":"fixture"}],"settings":{"apiProfiles":["first","second"],"apiPoolEnabled":true}})).unwrap();
  let result = app.translate("He is optimistic.", "zh-Hant", "", 0).await;
  bad.abort();
  good.abort();
  assert_eq!(result.unwrap(), "他很樂觀。");
}
#[tokio::test]
#[ignore = "explicit live cloud download, isolated temporary state"]
async fn real_signed_cloud_download_and_offline_reload() {
  let d = tempfile::tempdir().unwrap();
  let o = Official::new(d.path()).unwrap();
  let started = Instant::now();
  o.load().unwrap();
  for lang in ["zh-Hant", "zh-Hans"] {
    let begin = Instant::now();
    o.clone().sync(lang.into()).await.unwrap();
    println!(
      "LIVE_SYNC {lang} {:.2}ms {}",
      begin.elapsed().as_secs_f64() * 1000.0,
      o.status(lang)
    );
    assert_eq!(o.status(lang)["phase"], "pending");
  }
  let reloaded = Official::with_trust(
    d.path(),
    "https://127.0.0.1:1/manifest.json".into(),
    df_local_zh_broker::official::trust(),
  )
  .unwrap();
  let begin = Instant::now();
  reloaded.load().unwrap();
  for lang in ["zh-Hant", "zh-Hans"] {
    assert_eq!(reloaded.status(lang)["phase"], "complete");
    assert!(!reloaded.rows(lang).is_empty());
    println!("OFFLINE_LOAD {lang} {}", reloaded.status(lang));
  }
  println!(
    "OFFLINE_RELOAD {:.2}ms total {:.2}ms endpoint={ENDPOINT}",
    begin.elapsed().as_secs_f64() * 1000.0,
    started.elapsed().as_secs_f64() * 1000.0
  );
}
#[test]
fn bundled_binary_runs_with_no_node_in_path() {
  let d = tempfile::tempdir().unwrap();
  let cfg = files(d.path());
  let root = d.path().join("state");
  let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
  let mut config = read_json(&cfg, 8192).unwrap();
  config["port"] = json!(port);
  atomic(&cfg, &config).unwrap();
  let mut command = std::process::Command::new(env!("CARGO_BIN_EXE_df-local-zh-broker"));
  command
    .arg(&cfg)
    .arg(&root)
    .env(
      "PATH",
      if cfg!(windows) {
        "C:/Windows/System32"
      } else {
        "/nonexistent"
      },
    )
    .stdout(std::process::Stdio::null())
    .stderr(std::process::Stdio::null());
  #[cfg(windows)]
  {
    use std::os::windows::process::CommandExt;
    command.creation_flags(0x08000000);
  }
  struct Child(std::process::Child);
  impl Drop for Child {
    fn drop(&mut self) {
      let _ = self.0.kill();
      let _ = self.0.wait();
    }
  }
  let _child = Child(command.spawn().unwrap());
  use std::io::{Read, Write};
  let start = Instant::now();
  loop {
    if let Ok(mut stream) = std::net::TcpStream::connect((std::net::Ipv4Addr::LOCALHOST, port)) {
      stream.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
      stream.write_all(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n").unwrap();
      let mut response = String::new();
      stream.read_to_string(&mut response).unwrap();
      assert!(response.contains("\"engine\":\"rust\""), "{response}");
      println!("NO_NODE_START {:.2} ms", start.elapsed().as_secs_f64() * 1000.0);
      return;
    }
    assert!(start.elapsed() < Duration::from_secs(10), "Rust startup deadline");
    std::thread::sleep(Duration::from_millis(25));
  }
}

#[tokio::test]
async fn official_clear_settings_action_preserves_secrets_and_disables_all_scopes() {
  let d=tempfile::tempdir().unwrap();let cfg=files(d.path());let root=d.path().join("state");
  let app=App::load(&cfg,&root).unwrap();
  app.settings.lock().unwrap().apply(&json!({"scope":"save","world":"region1","settings":{"officialAutoDownload":true,"language":"zh-Hans","translationPrompt":"keep this"}})).unwrap();
  let secrets=std::fs::read(root.join("api-profiles.private.json")).unwrap();
  let response=app.settings_request(&json!({"id":"clear-test","action":"official-clear","world":"region1"})).await.unwrap();
  assert_eq!(response["ok"],true);assert_eq!(response["restartRequired"],true);
  assert_eq!(response["snapshot"]["effective"]["officialAutoDownload"],false);
  assert_eq!(response["snapshot"]["effective"]["translationPrompt"],"keep this");
  assert_eq!(response["snapshot"]["effective"]["language"],"zh-Hans");
  assert_eq!(app.settings.lock().unwrap().effective("")["officialAutoDownload"],false);
  assert_eq!(std::fs::read(root.join("api-profiles.private.json")).unwrap(),secrets);
  assert_eq!(app.official.status("zh-Hant")["phase"],"cleared");
}
