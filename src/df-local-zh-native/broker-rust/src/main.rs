#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
use axum::{
  Json, Router,
  extract::{DefaultBodyLimit, State},
  http::{HeaderMap, StatusCode},
  response::IntoResponse,
  routing::{get, post},
};
use df_local_zh_broker::{
  common::*,
  service::{App, run_background},
};
use serde_json::{Value, json};
use std::{path::PathBuf, sync::Arc};
async fn health(State(app): State<Arc<App>>) -> Json<Value> {
  Json(app.health())
}
async fn translate(State(app): State<Arc<App>>, headers: HeaderMap, Json(payload): Json<Value>) -> impl IntoResponse {
  if headers.contains_key("origin") {
    return (
      StatusCode::FORBIDDEN,
      Json(json!({"error":"browser requests disabled"})),
    );
  }
  let context = app.context();
  let lang = payload["language"].as_str().unwrap_or(context["language"].as_str().unwrap_or("zh-Hant"));
  let world = payload["world"].as_str().unwrap_or("");
  let source = payload["text"].as_str().unwrap_or("");
  if !language(lang)
    || world.len() > 1024
    || world.contains('\0')
    || source.trim().is_empty()
    || source.chars().count() > 8000
  {
    return (StatusCode::BAD_REQUEST, Json(json!({"error":"invalid request"})));
  }
  match app.translate(source, lang, world, 0).await {
    Ok(value) => (StatusCode::OK, Json(json!({"translation":value}))),
    Err(_) => (
      StatusCode::SERVICE_UNAVAILABLE,
      Json(json!({"error":"translation unavailable"})),
    ),
  }
}
async fn pin(State(app): State<Arc<App>>, headers: HeaderMap, Json(payload): Json<Value>) -> impl IntoResponse {
  if headers.contains_key("origin") {
    return (
      StatusCode::FORBIDDEN,
      Json(json!({"error":"browser requests disabled"})),
    );
  }
  let context = app.context();
  let id = payload["id"].as_str().unwrap_or("");
  if !re(r"^figure:\d+$").is_match(id) {
    return (StatusCode::BAD_REQUEST, Json(json!({"error":"invalid figure ID"})));
  }
  let lang = payload["language"].as_str().unwrap_or(context["language"].as_str().unwrap_or("zh-Hant"));
  let world = payload["world"].as_str().unwrap_or(context["world"].as_str().unwrap_or(""));
  match app.pin(id, lang, world).await {
    Ok(t) => (StatusCode::OK, Json(json!({"translation":t}))),
    Err(_) => (
      StatusCode::SERVICE_UNAVAILABLE,
      Json(json!({"error":"figure translation unavailable"})),
    ),
  }
}
#[tokio::main]
async fn main() {
  if run().await.is_err() {
    eprintln!("Rust Broker failed: check local configuration and port availability.");
    std::process::exit(1);
  }
}
async fn run() -> anyhow::Result<()> {
  let args = std::env::args_os().skip(1).collect::<Vec<_>>();
  let exe = std::env::current_exe()?;
  let source = exe.parent().unwrap();
  let config = args.first().map(PathBuf::from).unwrap_or_else(|| source.join("config.json"));
  let state = args
    .get(1)
    .map(PathBuf::from)
    .or_else(|| std::env::var_os("DF_LOCAL_ZH_STATE_DIRECTORY").map(PathBuf::from))
    .unwrap_or_else(|| std::env::current_dir().unwrap().join("dfhack-config/mods/df-local-zh-complete"));
  if let Some(i) = args.iter().position(|a| a == "--game-root") {
    if let Some(root) = args.get(i + 1) {
      unsafe {
        std::env::set_var("DF_LOCAL_ZH_GAME_ROOT", root);
      }
    }
  }
  let cfg = read_json(&config, 1024 * 1024)?;
  let port = args
    .iter()
    .position(|a| a == "--port")
    .and_then(|i| args.get(i + 1))
    .and_then(|v| v.to_str())
    .and_then(|v| v.parse::<u64>().ok())
    .unwrap_or_else(|| cfg["port"].as_u64().unwrap_or(19753));
  anyhow::ensure!((1024..=65535).contains(&port), "invalid port");
  // Bind before loading/writing state: a duplicate process cannot race with the owner.
  let listener = match tokio::net::TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, port as u16)).await {
    Ok(l) => l,
    Err(e) => {
      let client = reqwest::Client::builder().no_proxy().timeout(std::time::Duration::from_secs(2)).build()?;
      if let Ok(r) = client.get(format!("http://127.0.0.1:{port}/health")).send().await {
        if let Ok(v) = r.json::<Value>().await {
          if v["service"] == "df-local-zh" && v["engine"] == "rust" && v["policy"] == POLICY {
            return Ok(());
          }
        }
      }
      return Err(e.into());
    }
  };
  let app = App::load(&config, &state)?;
  tokio::spawn(run_background(app.clone()));
  let router = Router::new()
    .route("/health", get(health))
    .route("/v2/translate", post(translate))
    .route("/v2/pin-figure", post(pin))
    .layer(DefaultBodyLimit::max(32768))
    .with_state(app);
  axum::serve(listener, router).await?;
  Ok(())
}
