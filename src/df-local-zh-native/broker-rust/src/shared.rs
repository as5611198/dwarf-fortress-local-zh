use crate::{
  common::*,
  official::{identity, safe_shared},
  settings::{Settings, world_key},
};
use anyhow::{Result, ensure};
use serde_json::{Value, json};
use std::{
  path::{Path, PathBuf},
  sync::{Arc, Mutex},
  time::Duration,
};
pub const ENDPOINT: &str = "https://df-zh-consensus.g402111111.workers.dev/v1/contributions";
fn secret(text: &str) -> bool {
  re(r"(?i)https?://|(?:sk-|AIza)[A-Za-z0-9_-]{8,}|PRIVATE KEY|api[ _-]?key|password|ignore (?:all |previous |prior )?instructions|system prompt|(?:named|called)\s+[a-z]|\b(?:save|world|region\d+|artifact):").is_match(text)
}
fn safe(text: &str, kind: &str) -> bool {
  if !safe_shared(text, kind) || text.chars().count() > 2000 || secret(text) {
    return false;
  }
  let plain = tokens().replace_all(text, "");
  let plain = plain.trim();
  if !plain.bytes().all(|c| (32..=126).contains(&c)) || re(r"[\\/<>@]|\[[^\]]*\]").is_match(plain) {
    return false;
  }
  if !re(r"^(?:He|She|They|It|His|Her|The|A|An|You)\b").is_match(plain)
    && !(kind == "entity" && re(r"^(?:feels|is|has|needs)\b").is_match(plain))
    && !re(r"^(?:Health|Wounds|Treatment|Equipment|Skills|Traits|Needs|Mood|Melee Combat)$").is_match(plain)
  {
    return false;
  }
  if re(r"[A-Za-z]+")
    .find_iter(plain)
    .skip(1)
    .any(|m| m.as_str().starts_with(|c: char| c.is_ascii_uppercase()) && m.as_str() != "Combat")
  {
    return false;
  }
  if re(r"(?i)\b(?:born|named|called|citizen|world|fortress|artifact|kill(?:ed|s)?|slain)\b").is_match(plain) {
    return false;
  }
  !re(r"^(?:He|She|They|It)\b").is_match(plain) || plain.ends_with(['.', '!', '?'])
}
pub fn validate_contribution(row: &Value) -> Result<()> {
  ensure!(
    row.is_object()
      && row.as_object().unwrap().keys().all(|k| [
        "schema",
        "rules",
        "language",
        "context",
        "kind",
        "origin",
        "text",
        "translation",
        "model",
        "license"
      ]
      .contains(&k.as_str()))
      && row["schema"] == 1
      && row["rules"] == POLICY
      && row["language"].as_str().is_some_and(language)
      && row["context"] == "general"
      && row["origin"] == "vanilla"
      && row["license"] == "CC0-1.0"
      && row["model"].as_str().is_some_and(|s| re(r"^[A-Za-z0-9_/.@:+-]{1,100}$").is_match(s) && !secret(s))
      && row["text"].as_str().is_some_and(|s| safe(s, row["kind"].as_str().unwrap_or("")))
      && row["translation"].as_str().is_some_and(|s| s.len() <= 4096 && !secret(s)),
    "unsafe contribution"
  );
  validate(row["text"].as_str().unwrap(), row["translation"].as_str().unwrap())?;
  Ok(())
}
fn row_id(row: &Value) -> String {
  hash(
    serde_json::to_vec(&json!([
      identity(row, row["language"].as_str().unwrap()),
      row["translation"]
    ]))
    .unwrap(),
  )
}
pub struct Shared {
  root: PathBuf,
  state: Mutex<Value>,
  phase: Mutex<Value>,
  settings: Arc<Mutex<Settings>>,
  gate: tokio::sync::Mutex<()>,
  client: reqwest::Client,
}
impl Shared {
  pub fn load(root: &Path, settings: Arc<Mutex<Settings>>) -> Result<Arc<Self>> {
    let directory = root.join("shared");
    let mut state = json!({"schema":1,"deviceId":format!("{}{}",uuid::Uuid::new_v4().simple(),uuid::Uuid::new_v4().simple()),"entries":[],"sent":0,"lastSuccess":""});
    let mut phase = json!({"phase":"idle"});
    if directory.join("state.json").exists() {
      let loaded = read_json(&directory.join("state.json"), 4 * 1024 * 1024);
      let valid = loaded.as_ref().is_ok_and(|s| {
        s["schema"] == 1
          && s["deviceId"].as_str().is_some_and(|s| re(r"^[a-f0-9]{64}$").is_match(s))
          && s["entries"].as_array().is_some_and(|a| {
            a.len() <= 500
              && a.iter().all(|j| {
                validate_contribution(&j["entry"]).is_ok()
                  && j["id"] == row_id(&j["entry"])
                  && j["scope"].as_str().is_some_and(|s| s.len() <= 128)
                  && j["created"].is_i64()
              })
          })
      });
      if valid {
        state = loaded.unwrap();
      } else {
        phase = json!({"phase":"error","error":"待送資料損壞，請清除後再試"});
      }
    }
    let s = Arc::new(Self {
      root: directory,
      state: Mutex::new(state),
      phase: Mutex::new(phase),
      settings,
      gate: tokio::sync::Mutex::new(()),
      client: reqwest::Client::builder()
        .https_only(true)
        .redirect(reqwest::redirect::Policy::none())
        .timeout(Duration::from_secs(10))
        .build()?,
    });
    s.publish("")?;
    Ok(s)
  }
  pub fn status(&self, scope: &str) -> Value {
    let state = self.state.lock().unwrap();
    let mut status = json!({"schema":1,"enabled":self.settings.lock().unwrap().effective(scope)["sharedContributions"]==true,"pending":state["entries"].as_array().unwrap().len(),"sent":state["sent"],"lastSuccess":state["lastSuccess"]});
    for (k, v) in self.phase.lock().unwrap().as_object().unwrap() {
      status[k] = v.clone();
    }
    status
  }
  pub fn publish(&self, scope: &str) -> Result<()> {
    atomic(&self.root.join("status.json"), &self.status(scope))
  }
  pub fn capture(&self, row: Value, scope: &str) -> Result<()> {
    if self.settings.lock().unwrap().effective(scope)["sharedContributions"] != true
      || validate_contribution(&row).is_err()
    {
      return Ok(());
    }
    let scope = world_key(scope);
    let id = row_id(&row);
    let mut state = self.state.lock().unwrap();
    let mut next = state.clone();
    let entries = next["entries"].as_array_mut().unwrap();
    entries.retain(|j| now() - j["created"].as_i64().unwrap_or(0) < 7 * 86400000);
    if entries.len() >= 500 || entries.iter().any(|j| j["id"] == id) {
      return Ok(());
    }
    entries.push(json!({"id":id,"entry":row,"scope":scope,"created":now(),"attempts":0,"nextAttempt":0}));
    atomic(&self.root.join("state.json"), &next)?;
    *state = next;
    drop(state);
    *self.phase.lock().unwrap() = json!({"phase":"pending"});
    self.publish(&scope)
  }
  pub async fn clear(&self) -> Result<()> {
    let _gate = self.gate.lock().await;
    let mut state = self.state.lock().unwrap();
    let mut next = state.clone();
    next["entries"] = json!([]);
    atomic(&self.root.join("state.json"), &next)?;
    *state = next;
    drop(state);
    *self.phase.lock().unwrap() = json!({"phase":"idle"});
    self.publish("")
  }
  pub async fn flush(&self, scope: &str) -> Result<()> {
    let Ok(_gate) = self.gate.try_lock() else {
      return Ok(());
    };
    let mut jobs = {
      let s = self.state.lock().unwrap();
      let settings = self.settings.lock().unwrap();
      s["entries"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|j| {
          j["stalled"] != true
            && now() - j["created"].as_i64().unwrap_or(0) < 7 * 86400000
            && j["nextAttempt"].as_i64().unwrap_or(0) <= now()
            && settings.effective(j["scope"].as_str().unwrap_or(""))["sharedContributions"] == true
        })
        .take(8)
        .cloned()
        .collect::<Vec<_>>()
    };
    if jobs.is_empty() {
      self.publish(scope)?;
      return Ok(());
    }
    *self.phase.lock().unwrap() = json!({"phase":"sending"});
    self.publish(scope)?;
    let device = self.state.lock().unwrap()["deviceId"].clone();
    let mut body = json!({"schema":1,"deviceId":device,"batchId":uuid::Uuid::new_v4().to_string(),"entries":[]});
    loop {
      body["entries"] = json!(jobs.iter().map(|j| j["entry"].clone()).collect::<Vec<_>>());
      if serde_json::to_vec(&body)?.len() <= 32768 {
        break;
      }
      jobs.pop();
    }
    ensure!(!jobs.is_empty(), "shared body too large");
    let upload = async {
      let mut r = self.client.post(ENDPOINT).json(&body).send().await?;
      ensure!(r.status() == 202, "upload rejected");
      let mut bytes = Vec::new();
      while let Some(c) = r.chunk().await? {
        ensure!(bytes.len() + c.len() <= 8192, "receipt too large");
        bytes.extend_from_slice(&c);
      }
      let receipt: Value = serde_json::from_slice(&bytes)?;
      let a = receipt["accepted"].as_array().ok_or_else(|| anyhow::anyhow!("receipt invalid"))?;
      ensure!(
        a.len() == jobs.len() && a.iter().zip(&jobs).all(|(r, j)| r["id"] == j["id"] && r["counted"].is_boolean()),
        "receipt invalid"
      );
      Ok(())
    };
    let consent = async {
      loop {
        if jobs.iter().any(|j| {
          self.settings.lock().unwrap().effective(j["scope"].as_str().unwrap_or(""))["sharedContributions"] != true
        }) {
          return Err(anyhow::anyhow!("consent revoked"));
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
      }
    };
    let result: Result<()> = tokio::select! {result=upload=>result,result=consent=>result};
    let mut s = self.state.lock().unwrap();
    let mut next = s.clone();
    let ids = jobs.iter().map(|j| j["id"].clone()).collect::<Vec<_>>();
    if result.is_ok() {
      next["entries"].as_array_mut().unwrap().retain(|j| !ids.contains(&j["id"]));
      next["sent"] = json!(next["sent"].as_u64().unwrap_or(0) + jobs.len() as u64);
      next["lastSuccess"] = json!(iso());
      *self.phase.lock().unwrap() = json!({"phase":"complete"});
    } else {
      for j in next["entries"].as_array_mut().unwrap() {
        if ids.contains(&j["id"]) {
          let attempts = j["attempts"].as_u64().unwrap_or(0) + 1;
          j["attempts"] = json!(attempts);
          j["nextAttempt"] = json!(now() + 86400000.min(60000 * (1_i64 << attempts.saturating_sub(1).min(10))));
          j["stalled"] = json!(attempts >= 6);
        }
      }
      *self.phase.lock().unwrap() = json!({"phase":"error","error":"共享上報失敗；保留待送資料稍後重試"});
    }
    atomic(&self.root.join("state.json"), &next)?;
    *s = next;
    drop(s);
    self.publish(scope)?;
    Ok(())
  }
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn share_does_not_accept_world_names_secrets_or_instructions() {
    for text in [
      "He likes Bob.",
      "The citizen was born here.",
      "https://example.com",
      "Health sk-abcdefghijk",
    ] {
      assert!(!safe(text, "exact"));
    }
    assert!(safe("He is optimistic.", "exact"));
  }
}
