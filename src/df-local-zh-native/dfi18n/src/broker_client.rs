use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{OnceLock, RwLock};
use std::time::Duration;

use crate::native_cache::valid_translation;
use crate::translation::{TextAlignment, TranslationResponse};

static ENABLED: AtomicBool = AtomicBool::new(true);
static TIMEOUT_MS: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(25000);
static ENDPOINT: OnceLock<RwLock<String>> = OnceLock::new();
fn endpoint() -> &'static RwLock<String> { ENDPOINT.get_or_init(|| RwLock::new("http://127.0.0.1:19753/v2/translate".into())) }

fn request_payload(source: &str, language: &str, world: &str) -> serde_json::Value {
  serde_json::json!({"text":source,"language":language,"world":world})
}

pub async fn translate(source: &str) -> Option<TranslationResponse> {
  translate_for(source,&crate::lang::current_lang_tag(),&crate::native_cache::current_world()).await
}

pub async fn translate_for(source: &str, language: &str, world: &str) -> Option<TranslationResponse> {
  if !ENABLED.load(Ordering::Relaxed) || source.is_empty() || source.len() > 8000 { return None; }
  static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
  let client = CLIENT.get_or_init(|| reqwest::Client::builder().no_proxy().timeout(Duration::from_secs(60)).build().unwrap());
  let url = endpoint().read().unwrap().clone();
  let response = client.post(url).timeout(Duration::from_millis(TIMEOUT_MS.load(Ordering::Relaxed)))
    .json(&request_payload(source,language,world)).send().await.ok()?;
  if !response.status().is_success() { return None; }
  let body: serde_json::Value = response.json().await.ok()?;
  let translated = body.get("translation")?.as_str()?;
  if !valid_translation(source, translated) { return None; }
  Some(TranslationResponse { translated: translated.into(), alignment: TextAlignment::Left })
}

#[unsafe(no_mangle)]
extern "C" fn cloud_enable() -> i32 { ENABLED.store(true, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn cloud_disable() -> i32 { ENABLED.store(false, Ordering::Relaxed); 0 }
#[unsafe(no_mangle)]
extern "C" fn broker_timeout_set(state: *mut std::ffi::c_void) -> i32 {
  let value=lua53_sys::check_integer(state,1);
  if (1000..=120000).contains(&value) { TIMEOUT_MS.store(value as u64,Ordering::Relaxed); }
  0
}
#[unsafe(no_mangle)]
extern "C" fn cloud_get_status(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_boolean(state, ENABLED.load(Ordering::Relaxed));
  lua53_sys::push_boolean(state, true); 2
}
#[unsafe(no_mangle)]
extern "C" fn cloud_set_endpoint(state: *mut std::ffi::c_void) -> i32 {
  let input = lua53_sys::check_string(state, 1);
  match parse_endpoint(&input) {
    Some(value) => {
      *endpoint().write().unwrap() = value.clone();
      lua53_sys::push_string(state, &value); lua53_sys::push_nil(state);
    }
    None => { lua53_sys::push_nil(state); lua53_sys::push_string(state, "The native core uses the local Broker; configure AI API in the Broker."); }
  }
  2
}

fn parse_endpoint(input: &str) -> Option<String> {
  let input = if input.contains("://") { input.to_owned() } else { format!("http://{input}") };
  let parsed = reqwest::Url::parse(&input);
  match parsed {
    Ok(mut url) if url.scheme() == "http" && matches!(url.host_str(), Some("127.0.0.1" | "localhost")) &&
      url.username().is_empty() && url.password().is_none() => {
      if url.port().is_none() { let _ = url.set_port(Some(19753)); }
      url.set_path("/v2/translate"); url.set_query(None); url.set_fragment(None);
      Some(url.to_string())
    }
    _ => None,
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn endpoint_stays_on_the_local_broker() {
    assert_eq!(parse_endpoint("127.0.0.1").as_deref(), Some("http://127.0.0.1:19753/v2/translate"));
    assert_eq!(parse_endpoint("http://localhost:12345/old?key=secret").as_deref(), Some("http://localhost:12345/v2/translate"));
    assert!(parse_endpoint("https://example.com").is_none());
    assert!(parse_endpoint("http://127.0.0.1@example.com").is_none());
    assert!(parse_endpoint("http://user:pass@127.0.0.1").is_none());
  }

  #[test]
  fn native_request_captures_language_and_world_before_dispatch() {
    let payload=request_payload("A requested text","zh-Hans","region3");
    assert_eq!(payload["text"],"A requested text");
    assert_eq!(payload["language"],"zh-Hans");
    assert_eq!(payload["world"],"region3");
  }

  #[test]
  #[ignore = "requires the running local Broker"]
  fn local_broker_completion_publishes_a_ready_result_without_sleep() {
    use crate::native_cache::{CacheKey, MemoryCache};
    // A standalone test has no attached game world; do not send a fake world
    // identity to a live Broker that deliberately rejects stale world requests.
    let key = CacheKey { world: "".into(), language: "zh-Hant".into(), kind: "plain".into(), original: "Health".into() };
    let mut cache = MemoryCache::default();
    assert!(cache.begin(&key));
    let response = crate::tasks::get().block_on(async {
      tokio::time::timeout(Duration::from_secs(5), translate_for(&key.original, &key.language, &key.world)).await.expect("Broker completion deadline").expect("Broker must provide known Chinese")
    });
    cache.complete(key.clone(), Some(response.clone()));
    assert_eq!(cache.lookup(&key), Some(response));
    assert!(!cache.begin(&key));
    println!("BROKER_COMPLETION ready=true repeated_dispatch=false sleep=false");
  }
}
