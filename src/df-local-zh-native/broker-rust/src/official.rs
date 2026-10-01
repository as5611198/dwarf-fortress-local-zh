use crate::common::*;
use anyhow::{Result, bail, ensure};
use base64::{Engine, engine::general_purpose::STANDARD};
use ed25519_dalek::{Signature, VerifyingKey, pkcs8::DecodePublicKey};
use serde_json::{Value, json};
use std::{
  collections::{HashMap, HashSet},
  path::{Path, PathBuf},
  sync::{Arc, Mutex},
  time::{Duration, Instant},
};
pub const ENDPOINT: &str = "https://df-zh-official-library.g402111111.workers.dev/manifest.json";
pub const MAX_PACKAGE: usize = 32 * 1024 * 1024;
pub const MAX_MANIFEST: usize = 128 * 1024;
pub fn trust() -> HashMap<String, VerifyingKey> {
  [
 ("df-official-20261001","-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA8zVT2uHOkHng+IB68VGPJe5TqtoNGRe0/SgmaOmfUHI=\n-----END PUBLIC KEY-----\n"),
 ("df-consensus-20261001","-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAPFoKX7eAHMUeiDTfQCLhvbLHzPkXMxSI1vxAm5mHvRg=\n-----END PUBLIC KEY-----\n")].into_iter().map(|(id,pem)|(id.into(),VerifyingKey::from_public_key_pem(pem).unwrap())).collect()
}
fn version(v: &Value) -> bool {
  v.as_str().is_some_and(|s| re(r"^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$").is_match(s))
}
pub fn verify_manifest(bytes: &[u8], keys: &HashMap<String, VerifyingKey>) -> Result<Value> {
  ensure!(bytes.len() <= MAX_MANIFEST, "manifest too large");
  let e: Value = serde_json::from_slice(bytes)?;
  let key = keys.get(e["keyId"].as_str().unwrap_or("")).ok_or_else(|| anyhow::anyhow!("signature key unknown"))?;
  let payload = e["payload"].as_str().ok_or_else(|| anyhow::anyhow!("signature encoding invalid"))?;
  let sig = e["signature"].as_str().ok_or_else(|| anyhow::anyhow!("signature encoding invalid"))?;
  let p = STANDARD.decode(payload)?;
  let s = STANDARD.decode(sig)?;
  ensure!(
    STANDARD.encode(&p) == payload && STANDARD.encode(&s) == sig && s.len() == 64,
    "signature encoding invalid"
  );
  key.verify_strict(&p, &Signature::from_slice(&s)?).map_err(|_| anyhow::anyhow!("signature invalid"))?;
  let m: Value = serde_json::from_slice(&p)?;
  ensure!(
    m["schema"] == 1
      && m["rules"] == POLICY
      && m["sequence"].as_u64().is_some_and(|n| n > 0 && n <= 9007199254740991)
      && version(&m["version"])
      && m["publishedAt"].as_str().is_some_and(|s| chrono::DateTime::parse_from_rfc3339(s).is_ok()),
    "manifest incompatible"
  );
  let revoked = m["withdrawn"].as_array().ok_or_else(|| anyhow::anyhow!("withdrawal invalid"))?;
  ensure!(
    revoked.len() <= 1000 && revoked.iter().all(version) && !revoked.contains(&m["version"]),
    "withdrawal invalid"
  );
  let packages = m["packages"].as_array().ok_or_else(|| anyhow::anyhow!("packages invalid"))?;
  let mut seen = HashSet::new();
  ensure!(!packages.is_empty() && packages.len() <= 2, "packages invalid");
  for p in packages {
    let l = p["language"].as_str().unwrap_or("");
    ensure!(
      language(l)
        && seen.insert(l)
        && p["path"] == format!("releases/{}/{l}.json", m["version"].as_str().unwrap())
        && p["format"] == "json"
        && p.get("delta") == Some(&Value::Null)
        && p["entries"].as_u64().is_some_and(|n| n <= 200000)
        && p["bytes"].as_u64().is_some_and(|n| n > 0 && n <= MAX_PACKAGE as u64)
        && p["sha256"].as_str().is_some_and(|s| re(r"^[0-9a-f]{64}$").is_match(s)),
      "package metadata invalid"
    );
  }
  Ok(m)
}
pub fn safe_shared(text: &str, kind: &str) -> bool {
  if text.trim().is_empty()||text.chars().count()>8000||aliases(text)||re(r"[\x00-\x08\x0b\x0c\x0e-\x1f]|DFLIVE_|region\d+|\b(?:figure|entity|artifact):\d+|^(?:World|Folder|Portable Folder):|^In \d+,|\b(?:became the|was struck down by)\b|^(?:He|She) is not distracted after being unable to (?:be|pray to)$").is_match(text)||text.contains("likes")&&!text.contains("{DWARF_NAME}"){return false;}
  let ts = tokens().find_iter(text).map(|m| m.as_str()).collect::<Vec<_>>();
  if ts.iter().any(|s| s.starts_with('{') && !re(r"^(?:\{DWARF_NAME\}|\{\{DF[NE]\d+\}\})$").is_match(s)) {
    return false;
  }
  match kind {
    "exact" => !ts.iter().any(|s| s.starts_with('{')),
    "entity" => ts.iter().any(|s| re(r"^(?:\{DWARF_NAME\}|\{\{DFE\d+\}\})$").is_match(s)),
    "numeric" => ts.iter().any(|s| re(r"^\{\{DFN\d+\}\}$").is_match(s)),
    _ => false,
  }
}
pub fn identity(row: &Value, lang: &str) -> String {
  serde_json::to_string(&json!([
    POLICY,
    lang,
    row["context"],
    row["kind"],
    row["origin"],
    row["text"]
  ]))
  .unwrap()
}
pub fn validate_package(bytes: &[u8], p: &Value, m: &Value) -> Result<Value> {
  ensure!(
    bytes.len() <= MAX_PACKAGE && p["bytes"].as_u64() == Some(bytes.len() as u64) && p["sha256"] == hash(bytes),
    "package hash/size invalid"
  );
  let pack: Value = serde_json::from_slice(bytes)?;
  ensure!(
    pack["schema"] == 1
      && pack["version"] == m["version"]
      && pack["language"] == p["language"]
      && pack["rules"] == POLICY,
    "package incompatible"
  );
  let entries = pack["entries"].as_array().ok_or_else(|| anyhow::anyhow!("package incompatible"))?;
  ensure!(
    p["entries"].as_u64() == Some(entries.len() as u64),
    "package incompatible"
  );
  let mut seen = HashSet::new();
  for row in entries {
    ensure!(
      row.is_object()
        && row.as_object().unwrap().keys().all(|k| [
          "text",
          "translation",
          "context",
          "kind",
          "origin",
          "source",
          "review",
          "conversion",
          "alignment"
        ]
        .contains(&k.as_str()))
        && ["general", "ui", "description", "name-template"].contains(&row["context"].as_str().unwrap_or(""))
        && row["origin"] == "vanilla"
        && ["reviewed", "ai-reviewed"].contains(&row["review"].as_str().unwrap_or(""))
        && version(&row["source"])
        && (row.get("conversion").is_none() || row["conversion"] == "zh-Hant-opencc-unreviewed-terminology")
        && (row.get("alignment").is_none()
          || ["left", "center", "right"].contains(&row["alignment"].as_str().unwrap_or("")))
        && row["text"].as_str().is_some_and(|s| safe_shared(s, row["kind"].as_str().unwrap_or(""))),
      "unsafe shared entry"
    );
    validate(row["text"].as_str().unwrap(), row["translation"].as_str().unwrap_or(""))?;
    ensure!(
      seen.insert(identity(row, pack["language"].as_str().unwrap())),
      "duplicate shared identity"
    );
  }
  Ok(pack)
}
struct Store {
  state: Value,
  snapshots: HashMap<String, Value>,
  index: HashMap<String, String>,
  progress: HashMap<String, Value>,
  withdrawn: HashSet<String>,
  requested: HashSet<String>,
}
pub struct Official {
  pub root: PathBuf,
  endpoint: String,
  keys: HashMap<String, VerifyingKey>,
  store: Mutex<Store>,
  gate: tokio::sync::Mutex<()>,
  client: reqwest::Client,
}
impl Official {
  pub fn new(directory: &Path) -> Result<Arc<Self>> {
    Self::with_trust(directory, ENDPOINT.into(), trust())
  }
  pub fn with_trust(directory: &Path, endpoint: String, keys: HashMap<String, VerifyingKey>) -> Result<Arc<Self>> {
    Ok(Arc::new(Self {
      root: directory.join("official"),
      endpoint,
      keys,
      store: Mutex::new(Store {
        state: json!({"schema":1,"highestSequence":0,"highestManifest":null,"languages":{}}),
        snapshots: HashMap::new(),
        index: HashMap::new(),
        progress: HashMap::new(),
        withdrawn: HashSet::new(),
        requested: HashSet::new(),
      }),
      gate: tokio::sync::Mutex::new(()),
      client: reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(20))
        .build()?,
    }))
  }
  fn verified_record(&self, record: &Value, lang: &str, withdrawn: &HashSet<String>) -> Result<Value> {
    ensure!(
      version(&record["version"]) && record["version"].as_str().is_some_and(|s| !withdrawn.contains(s)),
      "local record invalid"
    );
    let v = record["version"].as_str().unwrap();
    let seq = record["sequence"].as_u64().ok_or_else(|| anyhow::anyhow!("local sequence invalid"))?;
    let digest = record["sha256"].as_str().unwrap_or("");
    ensure!(
      re(r"^[0-9a-f]{64}$").is_match(digest)
        && record["packageFile"] == format!("{v}-{lang}-{digest}.json")
        && record["manifestFile"] == format!("{v}-{seq}.manifest.json"),
      "local record invalid"
    );
    let path = self.root.join(record["manifestFile"].as_str().unwrap());
    ensure!(
      std::fs::metadata(&path)?.len() <= MAX_MANIFEST as u64,
      "manifest too large"
    );
    let m = verify_manifest(&std::fs::read(path)?, &self.keys)?;
    ensure!(m["version"] == v && m["sequence"] == seq, "local manifest mismatch");
    let p = m["packages"]
      .as_array()
      .unwrap()
      .iter()
      .find(|p| p["language"] == lang)
      .ok_or_else(|| anyhow::anyhow!("local descriptor invalid"))?;
    ensure!(p["sha256"] == digest, "local descriptor invalid");
    let path = self.root.join(record["packageFile"].as_str().unwrap());
    ensure!(
      std::fs::metadata(&path)?.len() <= MAX_PACKAGE as u64,
      "package too large"
    );
    validate_package(&std::fs::read(path)?, p, &m)
  }
  pub fn load(&self) -> Result<()> {
    let started = Instant::now();
    std::fs::create_dir_all(&self.root)?;
    let mut s = self.store.lock().unwrap();
    if self.root.join("state.json").exists() {
      match read_json(&self.root.join("state.json"), 2 * 1024 * 1024) {
        Ok(state)
          if state["schema"] == 1 && state["highestSequence"].as_u64().is_some() && state["languages"].is_object() =>
        {
          s.state = state
        }
        _ => {
          for lang in ["zh-Hant", "zh-Hans"] {
            s.progress.insert(
              lang.into(),
              json!({"phase":"error","error":"本機譯庫狀態損壞；保留靜態翻譯"}),
            );
          }
        }
      }
    }
    // Signed highest manifest is the durable anti-rollback and withdrawal authority.
    let mut records = Vec::new();
    for row in s.state["languages"].as_object().unwrap().values() {
      for k in ["active", "pending", "previous"] {
        if row[k].is_object() {
          records.push(row[k].clone());
        }
      }
    }
    for r in records {
      if !version(&r["version"]) {
        continue;
      }
      let expected = format!("{}-{}.manifest.json", r["version"].as_str().unwrap(), r["sequence"]);
      if r["manifestFile"] != expected {
        continue;
      }
      if std::fs::metadata(self.root.join(&expected)).is_ok_and(|i| i.len() <= MAX_MANIFEST as u64) {
        if let Ok(bytes) = std::fs::read(self.root.join(expected)) {
          if let Ok(m) = verify_manifest(&bytes, &self.keys) {
            if m["sequence"].as_u64().unwrap() > s.state["highestSequence"].as_u64().unwrap_or(0) {
              s.state["highestSequence"] = m["sequence"].clone();
              s.state["highestManifest"] = json!(hash(&bytes));
              s.state["highestManifestFile"] = r["manifestFile"].clone();
            }
            for v in m["withdrawn"].as_array().unwrap() {
              s.withdrawn.insert(v.as_str().unwrap().into());
            }
          }
        }
      }
    }
    if let Some(file) = s.state["highestManifestFile"].as_str() {
      if re(r"^[a-zA-Z0-9._-]+\.manifest\.json$").is_match(file)
        && std::fs::metadata(self.root.join(file)).is_ok_and(|i| i.len() <= MAX_MANIFEST as u64)
      {
        if let Ok(bytes) = std::fs::read(self.root.join(file)) {
          if let Ok(m) = verify_manifest(&bytes, &self.keys) {
            for v in m["withdrawn"].as_array().unwrap() {
              s.withdrawn.insert(v.as_str().unwrap().into());
            }
          }
        }
      }
    }
    // New service snapshot is a safe game-launch boundary. Never hot-swap while running.
    for lang in ["zh-Hant", "zh-Hans"] {
      let row = s.state["languages"][lang].clone();
      if !row.is_object() {
        continue;
      }
      let mut active = None;
      for key in ["pending", "active", "previous"] {
        if let Ok(pack) = self.verified_record(&row[key], lang, &s.withdrawn) {
          active = Some((key, pack));
          break;
        }
      }
      if let Some((key, pack)) = active {
        if key == "pending" {
          if row["active"]["version"].as_str().is_some_and(|v| !s.withdrawn.contains(v)) {
            s.state["languages"][lang]["previous"] = row["active"].clone();
          }
          s.state["languages"][lang]["active"] = row["pending"].clone();
          s.state["languages"][lang].as_object_mut().unwrap().remove("pending");
        }
        if key == "previous" {
          s.state["languages"][lang]["active"] = row["previous"].clone();
          s.state["languages"][lang].as_object_mut().unwrap().remove("previous");
        }
        for entry in pack["entries"].as_array().unwrap() {
          s.index.insert(identity(entry, lang), entry["translation"].as_str().unwrap().into());
        }
        s.snapshots.insert(lang.into(), pack);
      } else {
        s.progress.insert(lang.into(), json!({"phase":"error","error":"已安裝譯庫驗證失敗"}));
      }
      s.progress.entry(lang.into()).or_insert(json!({}))["loadMs"] = json!(started.elapsed().as_secs_f64() * 1000.0);
    }
    atomic(&self.root.join("state.json"), &s.state)?;
    drop(s);
    for lang in ["zh-Hant", "zh-Hans"] {
      self.publish(lang)?;
    }
    Ok(())
  }
  pub fn lookup(&self, text: &str, lang: &str, kind: &str) -> Option<String> {
    self
      .store
      .lock()
      .unwrap()
      .index
      .get(&serde_json::to_string(&json!([POLICY, lang, "general", kind, "vanilla", text])).unwrap())
      .cloned()
  }
  pub fn rows(&self, lang: &str) -> Vec<Value> {
    self.store.lock().unwrap().snapshots.get(lang).and_then(|p| p["entries"].as_array()).cloned().unwrap_or_default()
  }
  pub fn status(&self, lang: &str) -> Value {
    let s = self.store.lock().unwrap();
    let row = &s.state["languages"][lang];
    let snapshot = s.snapshots.get(lang);
    let installed = row["active"]["version"].as_str().unwrap_or("");
    let available = row["pending"]["version"].as_str().unwrap_or(installed);
    let mut status = json!({"schema":1,"language":lang,"installedVersion":installed,"activeVersion":snapshot.map(|p|p["version"].clone()).unwrap_or(json!("")),"availableVersion":available,"entries":snapshot.and_then(|p|p["entries"].as_array()).map(|a|a.len()).unwrap_or(0),"lastSuccess":row["lastSuccess"].as_str().unwrap_or(""),"phase":if row["pending"].is_object(){"pending"}else if snapshot.is_some(){"complete"}else{"idle"},"progress":if snapshot.is_some()||row["pending"].is_object(){100}else{0},"activation":"關閉遊戲後，下次啟動採用新版；目前畫面保持同一版本"});
    if let Some(v) = s.progress.get(lang).and_then(Value::as_object) {
      for (k, v) in v {
        status[k] = v.clone();
      }
    }
    status
  }
  fn publish(&self, lang: &str) -> Result<()> {
    atomic(&self.root.join(format!("status-{lang}.json")), &self.status(lang))
  }
  fn progress(&self, lang: &str, value: Value) {
    self.store.lock().unwrap().progress.insert(lang.into(), value);
    let _ = self.publish(lang);
  }
  async fn get(&self, url: reqwest::Url, limit: usize, lang: &str, phase: &str) -> Result<Vec<u8>> {
    ensure!(
      url.scheme() == "https" && url.username().is_empty() && url.password().is_none(),
      "HTTPS required"
    );
    let mut r = self.client.get(url).header("Accept", "application/json").send().await?;
    ensure!(r.status().is_success(), "download HTTP failure");
    ensure!(
      r.content_length().is_none_or(|n| n <= limit as u64),
      "download too large"
    );
    let mut bytes = Vec::new();
    let mut last = Instant::now();
    while let Some(chunk) = r.chunk().await? {
      ensure!(bytes.len() + chunk.len() <= limit, "download too large");
      bytes.extend_from_slice(&chunk);
      if last.elapsed() > Duration::from_millis(250) {
        self.progress(lang,json!({"phase":phase,"downloadedBytes":bytes.len(),"totalBytes":limit,"progress":(bytes.len()*100/limit).min(99)}));
        last = Instant::now();
      }
    }
    Ok(bytes)
  }
  pub async fn sync(self: Arc<Self>, lang: String) -> Result<()> {
    ensure!(language(&lang), "language unsupported");
    {
      let mut s = self.store.lock().unwrap();
      if !s.requested.insert(lang.clone()) {
        return Ok(());
      }
    }
    let _gate = self.gate.lock().await;
    let started = Instant::now();
    let mut error = None;
    for attempt in 0..=2 {
      match self.download(&lang).await {
        Ok(()) => {
          error = None;
          break;
        }
        Err(e) => {
          error = Some(e);
          if attempt < 2 {
            tokio::time::sleep(Duration::from_secs(1 << attempt)).await;
          }
        }
      }
    }
    {
      let mut s = self.store.lock().unwrap();
      s.requested.remove(&lang);
      s.progress.entry(lang.clone()).or_insert(json!({}))["syncMs"] = json!(started.elapsed().as_secs_f64() * 1000.0);
    }
    if let Some(e) = error {
      let reason = e.to_string();
      let message = if reason.contains("signature") {
        "譯庫簽章驗證失敗"
      } else if reason.contains("rollback") {
        "拒絕舊版或衝突清單"
      } else if reason.contains("hash") || reason.contains("size") || reason.contains("too large") {
        "譯庫大小或雜湊不符"
      } else if reason.contains("incompatible") || reason.contains("unsafe") || reason.contains("duplicate") {
        "譯庫不相容或內容無效"
      } else {
        "下載或寫入失敗；保留原版"
      };
      self.progress(
        &lang,
        json!({"phase":"error","error":message,"progress":0,"syncMs":started.elapsed().as_secs_f64()*1000.0}),
      );
      bail!("official sync failed");
    }
    self.publish(&lang)?;
    Ok(())
  }
  async fn download(&self, lang: &str) -> Result<()> {
    self.progress(lang, json!({"phase":"checking","progress":0}));
    let endpoint = reqwest::Url::parse(&self.endpoint)?;
    let envelope = self.get(endpoint.clone(), MAX_MANIFEST, lang, "checking").await?;
    let m = verify_manifest(&envelope, &self.keys)?;
    let digest = hash(&envelope);
    {
      let s = self.store.lock().unwrap();
      let highest = s.state["highestSequence"].as_u64().unwrap_or(0);
      let seq = m["sequence"].as_u64().unwrap();
      ensure!(
        seq >= highest
          && (seq != highest || s.state["highestManifest"].is_null() || s.state["highestManifest"] == digest),
        "untrusted rollback"
      );
    }
    // Persist authenticated rollback/revocation authority even if the replacement
    // download later fails. Existing running snapshots remain pinned until restart.
    self.accept_authority(&envelope, &m)?;
    let p = m["packages"]
      .as_array()
      .unwrap()
      .iter()
      .find(|p| p["language"] == lang)
      .ok_or_else(|| anyhow::anyhow!("language unavailable"))?;
    self.progress(
      lang,
      json!({"phase":"downloading","availableVersion":m["version"],"progress":0}),
    );
    {
      let s = self.store.lock().unwrap();
      let row = &s.state["languages"][lang];
      let current = if row["pending"].is_object() {
        &row["pending"]
      } else {
        &row["active"]
      };
      if current["sha256"] == p["sha256"] && current["sequence"] == m["sequence"] {
        drop(s);
        self.store.lock().unwrap().progress.remove(lang);
        return Ok(());
      }
    }
    let bytes = self
      .get(
        endpoint.join(p["path"].as_str().unwrap())?,
        p["bytes"].as_u64().unwrap() as usize,
        lang,
        "downloading",
      )
      .await?;
    self.progress(
      lang,
      json!({"phase":"verifying","availableVersion":m["version"],"progress":100}),
    );
    validate_package(&bytes, p, &m)?;
    let v = m["version"].as_str().unwrap();
    let seq = m["sequence"].as_u64().unwrap();
    let sha = p["sha256"].as_str().unwrap();
    let record = json!({"version":v,"sequence":seq,"sha256":sha,"packageFile":format!("{v}-{lang}-{sha}.json"),"manifestFile":format!("{v}-{seq}.manifest.json")});
    // Temp + fsync + atomic rename. State pointer is last; failures leave old snapshots intact.
    atomic_bytes(&self.root.join(record["packageFile"].as_str().unwrap()), &bytes)?;
    atomic_bytes(&self.root.join(record["manifestFile"].as_str().unwrap()), &envelope)?;
    let mut s = self.store.lock().unwrap();
    let mut state = s.state.clone();
    state["highestSequence"] = m["sequence"].clone();
    state["highestManifest"] = json!(digest);
    state["highestManifestFile"] = record["manifestFile"].clone();
    if !state["languages"][lang].is_object() {
      state["languages"][lang] = json!({});
    }
    state["languages"][lang]["pending"] = record;
    state["languages"][lang]["lastSuccess"] = json!(iso());
    for revoked in m["withdrawn"].as_array().unwrap() {
      if state["languages"][lang]["previous"]["version"] == *revoked {
        state["languages"][lang].as_object_mut().unwrap().remove("previous");
      }
    }
    atomic(&self.root.join("state.json"), &state)?;
    s.state = state;
    drop(s);
    self.progress(lang, json!({"phase":"pending","availableVersion":v,"progress":100}));
    Ok(())
  }
  fn accept_authority(&self, envelope: &[u8], m: &Value) -> Result<()> {
    let digest = hash(envelope);
    let mut s = self.store.lock().unwrap();
    let highest = s.state["highestSequence"].as_u64().unwrap_or(0);
    let seq = m["sequence"].as_u64().unwrap();
    ensure!(
      seq >= highest
        && (seq != highest || s.state["highestManifest"].is_null() || s.state["highestManifest"] == digest),
      "untrusted rollback"
    );
    let file = format!("{}-{seq}.manifest.json", m["version"].as_str().unwrap());
    atomic_bytes(&self.root.join(&file), envelope)?;
    let mut state = s.state.clone();
    state["highestSequence"] = json!(seq);
    state["highestManifest"] = json!(digest);
    state["highestManifestFile"] = json!(file);
    atomic(&self.root.join("state.json"), &state)?;
    s.state = state;
    for v in m["withdrawn"].as_array().unwrap() {
      s.withdrawn.insert(v.as_str().unwrap().into());
    }
    Ok(())
  }
}
#[cfg(test)]
mod tests {
  use super::*;
  use ed25519_dalek::{Signer, SigningKey};
  fn fixture() -> (HashMap<String, VerifyingKey>, Vec<u8>, Vec<u8>) {
    let key = SigningKey::from_bytes(&[42; 32]);
    let pack=serde_json::to_vec(&json!({"schema":1,"version":"fixture-1","language":"zh-Hant","rules":POLICY,"entries":[{"text":"Health","translation":"健康","context":"general","kind":"exact","origin":"vanilla","source":"fixture","review":"reviewed"}]})).unwrap();
    let m = json!({"schema":1,"rules":POLICY,"sequence":1,"version":"fixture-1","publishedAt":"2026-10-01T00:00:00Z","withdrawn":[],"packages":[{"language":"zh-Hant","path":"releases/fixture-1/zh-Hant.json","format":"json","delta":null,"entries":1,"bytes":pack.len(),"sha256":hash(&pack)}]});
    let payload = serde_json::to_vec(&m).unwrap();
    let envelope=serde_json::to_vec(&json!({"keyId":"test","payload":STANDARD.encode(&payload),"signature":STANDARD.encode(key.sign(&payload).to_bytes())})).unwrap();
    (HashMap::from([("test".into(), key.verifying_key())]), envelope, pack)
  }
  #[test]
  fn forged_signature_hash_and_incompatible_package_rejected() {
    let (keys, bytes, pack) = fixture();
    let m = verify_manifest(&bytes, &keys).unwrap();
    assert!(validate_package(&pack, &m["packages"][0], &m).is_ok());
    let mut e: Value = serde_json::from_slice(&bytes).unwrap();
    e["signature"] = json!(STANDARD.encode([0; 64]));
    assert!(verify_manifest(&serde_json::to_vec(&e).unwrap(), &keys).is_err());
    let mut broken = pack.clone();
    broken[0] = 0;
    assert!(validate_package(&broken, &m["packages"][0], &m).is_err());
    let mut bad: Value = serde_json::from_slice(&pack).unwrap();
    bad["rules"] = json!("future");
    let b = serde_json::to_vec(&bad).unwrap();
    let mut p = m["packages"][0].clone();
    p["sha256"] = json!(hash(&b));
    p["bytes"] = json!(b.len());
    assert!(validate_package(&b, &p, &m).is_err());
  }
  #[test]
  fn names_runtime_aliases_and_fragments_never_shared() {
    for s in [
      "region123",
      "World: Test",
      "DFLIVE_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "He likes Bob.",
      "He is not distracted after being unable to pray to",
    ] {
      assert!(!safe_shared(s, "exact"));
    }
  }
  #[test]
  fn signed_authority_rejects_rollback_and_conflicts_even_without_replacement() {
    let (keys, old, _) = fixture();
    let d = tempfile::tempdir().unwrap();
    let o = Official::with_trust(d.path(), ENDPOINT.into(), keys.clone()).unwrap();
    o.load().unwrap();
    let m = verify_manifest(&old, &keys).unwrap();
    o.accept_authority(&old, &m).unwrap();
    let mut newer = m.clone();
    newer["sequence"] = json!(2);
    newer["version"] = json!("fixture-2");
    newer["packages"][0]["path"] = json!("releases/fixture-2/zh-Hant.json");
    newer["withdrawn"] = json!(["fixture-1"]);
    let sign = |v: &Value| {
      let p = serde_json::to_vec(v).unwrap();
      serde_json::to_vec(&json!({"keyId":"test","payload":STANDARD.encode(&p),"signature":STANDARD.encode(SigningKey::from_bytes(&[42;32]).sign(&p).to_bytes())})).unwrap()
    };
    let envelope = sign(&newer);
    let verified = verify_manifest(&envelope, &keys).unwrap();
    o.accept_authority(&envelope, &verified).unwrap();
    assert!(o.accept_authority(&old, &m).is_err());
    let mut conflicting = newer;
    conflicting["publishedAt"] = json!("2026-10-02T00:00:00Z");
    assert!(o.accept_authority(&sign(&conflicting), &conflicting).is_err());
    let reloaded = Official::with_trust(d.path(), ENDPOINT.into(), keys).unwrap();
    reloaded.load().unwrap();
    assert!(reloaded.store.lock().unwrap().withdrawn.contains("fixture-1"));
    assert_eq!(reloaded.store.lock().unwrap().state["highestSequence"], 2);
  }
  #[test]
  fn pending_activation_offline_reload_and_language_separation() {
    let (keys, envelope, pack) = fixture();
    let d = tempfile::tempdir().unwrap();
    let o = Official::with_trust(d.path(), ENDPOINT.into(), keys.clone()).unwrap();
    o.load().unwrap();
    let m = verify_manifest(&envelope, &keys).unwrap();
    let sha = m["packages"][0]["sha256"].as_str().unwrap();
    let record = json!({"version":"fixture-1","sequence":1,"sha256":sha,"packageFile":format!("fixture-1-zh-Hant-{sha}.json"),"manifestFile":"fixture-1-1.manifest.json"});
    atomic_bytes(&o.root.join(record["packageFile"].as_str().unwrap()), &pack).unwrap();
    atomic_bytes(&o.root.join("fixture-1-1.manifest.json"), &envelope).unwrap();
    atomic(&o.root.join("state.json"),&json!({"schema":1,"highestSequence":1,"highestManifest":hash(&envelope),"languages":{"zh-Hant":{"pending":record}}})).unwrap();
    assert!(o.lookup("Health", "zh-Hant", "exact").is_none());
    let reloaded = Official::with_trust(d.path(), ENDPOINT.into(), keys).unwrap();
    reloaded.load().unwrap();
    assert_eq!(reloaded.lookup("Health", "zh-Hant", "exact"), Some("健康".into()));
    assert!(reloaded.lookup("Health", "zh-Hans", "exact").is_none());
  }
}
