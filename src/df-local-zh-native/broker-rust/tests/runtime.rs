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
async fn full_published_package_loads_with_isolated_state() {
  let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../distribution/steam/df-local-zh-complete");
  let d = tempfile::tempdir().unwrap();
  let app = App::load(&root.join("broker/config.json"), d.path()).unwrap();
  assert_eq!(app.translate("Wounds", "zh-Hant", "", 0).await.unwrap(), "傷口");
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
