use crate::common::*;
use anyhow::{Result, ensure};
use serde_json::{Value, json};
use std::path::{Path, PathBuf};
pub const DEFAULT_PROMPT: &str = include_str!("gameplay-prompt.txt");
pub fn defaults() -> Value {
  json!({"language":"zh-Hant","pinyin":true,"colorPersistence":true,"apiEnabled":true,"apiProfile":"legacy","apiProfiles":[],"apiPoolEnabled":false,"backgroundTranslation":true,"concurrency":2,"timeoutMs":25000,"maxRetries":2,"retryBaseMs":1000,"translationPrompt":"","officialAutoDownload":true,"sharedContributions":false})
}
pub fn world_key(value: &str) -> String {
  value.trim_end_matches(['\\', '/']).rsplit(['\\', '/']).next().unwrap_or("").into()
}
fn merge(target: &mut Value, source: &Value) {
  if let Some(obj) = source.as_object() {
    for (k, v) in obj {
      target[k] = v.clone();
    }
  }
}
fn id(value: &str) -> bool {
  re(r"^[a-zA-Z0-9_-]{1,48}$").is_match(value) && !matches!(value, "__proto__" | "constructor" | "prototype")
}
pub fn validate_overrides(value: &Value) -> Result<Value> {
  let fields = value.as_object().ok_or_else(|| anyhow::anyhow!("settings must be object"))?;
  let allowed = defaults();
  let mut result = value.clone();
  for (k, v) in fields {
    ensure!(allowed.get(k).is_some(), "unknown settings field");
    match k.as_str() {
      "language" => ensure!(v.as_str().is_some_and(language), "unsupported language"),
      "apiProfile" => ensure!(v.as_str().is_some_and(id), "invalid profile ID"),
      "apiProfiles" => {
        let a = v.as_array().ok_or_else(|| anyhow::anyhow!("profile list"))?;
        ensure!(a.len() <= 16, "profile list");
        let mut seen = std::collections::HashSet::new();
        for x in a {
          ensure!(x.as_str().is_some_and(id) && seen.insert(x.to_string()), "profile list");
        }
      }
      "translationPrompt" => ensure!(
        v.as_str().is_some_and(|s| s.chars().count() <= 8192 && !re(r"[\x00-\x08\x0b\x0c\x0e-\x1f]").is_match(s)),
        "invalid prompt"
      ),
      "concurrency" | "timeoutMs" | "maxRetries" | "retryBaseMs" => {
        let range = match k.as_str() {
          "concurrency" => 1..=32,
          "timeoutMs" => 1000..=120000,
          "maxRetries" => 0..=5,
          _ => 100..=30000,
        };
        ensure!(v.as_i64().is_some_and(|n| range.contains(&n)), "invalid number");
      }
      _ => ensure!(v.is_boolean(), "invalid flag"),
    }
  }
  if value.get("apiProfiles").is_some() && value.get("apiPoolEnabled").is_none() {
    result["apiPoolEnabled"] = json!(true);
  }
  Ok(result)
}
pub fn validate_profile(name: &str, input: &Value) -> Result<Value> {
  ensure!(id(name) && input.is_object(), "invalid profile");
  for k in input.as_object().unwrap().keys() {
    ensure!(
      [
        "label",
        "enabled",
        "kind",
        "baseUrl",
        "model",
        "key",
        "inheritLegacy",
        "concurrency"
      ]
      .contains(&k.as_str()),
      "unknown profile field"
    );
  }
  let mut p = json!({"label":name,"enabled":true,"kind":"Custom_OpenAI","baseUrl":"","model":"","key":"","inheritLegacy":false,"concurrency":2});
  merge(&mut p, input);
  for (key, limit) in [
    ("label", 80),
    ("kind", 40),
    ("baseUrl", 2048),
    ("model", 200),
    ("key", 8192),
  ] {
    ensure!(
      p[key].as_str().is_some_and(|s| s.chars().count() <= limit && !re(r"[\x00-\x1f]").is_match(s)),
      "invalid profile field"
    );
  }
  ensure!(
    p["enabled"].is_boolean()
      && p["inheritLegacy"].is_boolean()
      && p["concurrency"].as_i64().is_some_and(|x| (1..=16).contains(&x)),
    "invalid profile flags"
  );
  if let Some(url) = p["baseUrl"].as_str().filter(|s| !s.is_empty()) {
    let u = reqwest::Url::parse(url)?;
    ensure!(
      u.username().is_empty()
        && u.password().is_none()
        && u.query().is_none()
        && u.fragment().is_none()
        && (u.scheme() == "https"
          || u.scheme() == "http" && matches!(u.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"))),
      "unsafe API URL"
    );
  }
  if p["enabled"] == true && p["inheritLegacy"] != true {
    ensure!(
      !p["baseUrl"].as_str().unwrap().is_empty() && !p["model"].as_str().unwrap().is_empty(),
      "API URL/model missing"
    );
  }
  Ok(p)
}
pub struct Settings {
  pub root: PathBuf,
  pub document: Value,
  pub profiles: Value,
}
impl Settings {
  pub fn load(root: &Path, config: &Value) -> Result<Self> {
    std::fs::create_dir_all(root)?;
    let path = root.join("settings.json");
    let exists = path.exists();
    let mut document = if exists {
      read_json(&path, 1024 * 1024)?
    } else {
      json!({"version":1,"defaults":{},"saves":{}})
    };
    ensure!(
      document["version"] == 1
        && document["saves"].is_object()
        && document.as_object().unwrap().keys().all(|k| ["version", "defaults", "saves"].contains(&k.as_str())),
      "invalid local settings file"
    );
    let mut base = defaults();
    base["language"] = config.get("language").cloned().unwrap_or(json!("zh-Hant"));
    merge(&mut base, &validate_overrides(&document["defaults"])?);
    document["defaults"] = base;
    for (k, v) in document["saves"].as_object_mut().unwrap() {
      ensure!(
        !k.is_empty()
          && k.len() <= 128
          && !k.contains(['\\', '/', '\0'])
          && !matches!(k.as_str(), "__proto__" | "constructor" | "prototype"),
        "invalid save ID"
      );
      *v = validate_overrides(v)?;
    }
    let profile_path = root.join("api-profiles.private.json");
    let profile_exists = profile_path.exists();
    let mut profiles = if profile_exists {
      read_json(&profile_path, 4 * 1024 * 1024)?
    } else {
      json!({"version":1,"profiles":{"legacy":{"label":"Existing API","enabled":false}}})
    };
    if !profile_exists && config["provider"].is_object() {
      let mut p = config["provider"].clone();
      if let Some(env) = p["keyEnv"].as_str() {
        p["key"] = json!(std::env::var(env).unwrap_or_default());
        p.as_object_mut().unwrap().remove("keyEnv");
      }
      profiles["profiles"]["legacy"] = p;
    }
    ensure!(
      profiles["version"] == 1 && profiles["profiles"].is_object(),
      "invalid private profiles file"
    );
    for (k, v) in profiles["profiles"].as_object_mut().unwrap() {
      *v = validate_profile(k, v)?;
    }
    let s = Self {
      root: root.into(),
      document,
      profiles,
    };
    if !exists {
      atomic(&path, &s.document)?;
    }
    if !profile_exists {
      atomic(&profile_path, &s.profiles)?;
    }
    s.publish()?;
    Ok(s)
  }
  pub fn effective(&self, world: &str) -> Value {
    let mut v = self.document["defaults"].clone();
    merge(&mut v, &self.document["saves"][world_key(world)]);
    v
  }
  pub fn snapshot(&self, world: &str) -> Value {
    let mut public = self.profiles["profiles"].clone();
    for (_, p) in public.as_object_mut().unwrap() {
      let has = p["key"].as_str().is_some_and(|s| !s.is_empty());
      p.as_object_mut().unwrap().remove("key");
      p.as_object_mut().unwrap().remove("inheritLegacy");
      p["hasKey"] = json!(has);
    }
    json!({"version":1,"document":self.document,"effective":self.effective(world),"world":world_key(world),"profiles":public,"promptDefaults":{"translation":DEFAULT_PROMPT}})
  }
  pub fn publish(&self) -> Result<()> {
    atomic(&self.root.join("settings-public.json"), &self.snapshot(""))
  }
  pub fn draft(&self, update: &Value) -> Result<(String, Value)> {
    let name = update["id"].as_str().ok_or_else(|| anyhow::anyhow!("profile ID"))?;
    let mut p = self.profiles["profiles"].get(name).cloned().unwrap_or(json!({"label":name,"enabled":false}));
    let mut fields = update.clone();
    fields.as_object_mut().ok_or_else(|| anyhow::anyhow!("profile"))?.remove("id");
    if let Some(clear) = fields.as_object_mut().unwrap().remove("clearKey") {
      ensure!(clear.is_boolean(), "clear key flag");
      if clear == true {
        fields["key"] = json!("");
      }
    }
    merge(&mut p, &fields);
    p["inheritLegacy"] = json!(false);
    Ok((name.into(), validate_profile(name, &p)?))
  }
  pub fn apply(&mut self, change: &Value) -> Result<Value> {
    let scope = change["scope"].as_str().unwrap_or("");
    ensure!(matches!(scope, "save" | "global"), "invalid scope");
    let world = change["world"].as_str().unwrap_or("");
    let save = world_key(world);
    ensure!(scope != "save" || !save.is_empty(), "save requires world");
    let mut doc = self.document.clone();
    let mut profiles = self.profiles.clone();
    let mut updates = change["profiles"].as_array().cloned().unwrap_or_default();
    if change["profile"].is_object() {
      updates.push(change["profile"].clone());
    }
    ensure!(updates.len() <= 16, "profile updates");
    let deletions = change["deleteProfiles"].as_array().cloned().unwrap_or_default();
    ensure!(deletions.len() <= 16, "profile deletions");
    let mut deleted = std::collections::HashSet::new();
    for v in deletions {
      let name = v.as_str().ok_or_else(|| anyhow::anyhow!("deletion"))?;
      ensure!(
        id(name) && profiles["profiles"].get(name).is_some() && deleted.insert(name.to_string()),
        "deletion"
      );
    }
    for u in updates {
      let (name, p) = self.draft(&u)?;
      ensure!(!deleted.contains(&name), "update deleted profile");
      profiles["profiles"][name] = p;
    }
    let transitional = profiles.clone();
    for name in &deleted {
      profiles["profiles"].as_object_mut().unwrap().remove(name);
    }
    let vals = validate_overrides(change.get("settings").unwrap_or(&json!({})))?;
    if scope == "global" {
      merge(&mut doc["defaults"], &vals);
    } else if change["reset"] == true {
      if vals.as_object().unwrap().is_empty() {
        doc["saves"].as_object_mut().unwrap().remove(&save);
      } else {
        doc["saves"][&save] = vals;
      }
    } else {
      if !doc["saves"][&save].is_object() {
        doc["saves"][&save] = json!({});
      }
      merge(&mut doc["saves"][&save], &vals);
    }
    let mut names = profiles["profiles"].as_object().unwrap().keys().cloned().collect::<Vec<_>>();
    names.sort();
    let fallback = names.first().cloned().unwrap_or("legacy".into());
    // Preserve the selected provider sets in every scope, including inherited defaults.
    let before = doc.clone();
    let previous_empty = self.profiles["profiles"].as_object().unwrap().is_empty();
    let fix = |row: &mut Value, effective: &Value| {
      let selected = if effective["apiPoolEnabled"] == true {
        effective["apiProfiles"].as_array().cloned().unwrap_or_default()
      } else {
        vec![effective["apiProfile"].clone()]
      };
      let desired = selected.into_iter().filter(|v| !deleted.contains(v.as_str().unwrap_or(""))).collect::<Vec<_>>();
      if row["apiProfile"].as_str().is_some_and(|s| deleted.contains(s))
        || previous_empty && row["apiProfile"] == "legacy" && !names.contains(&"legacy".into())
      {
        row["apiProfile"] = json!(fallback);
      }
      if let Some(a) = row["apiProfiles"].as_array_mut() {
        a.retain(|v| !deleted.contains(v.as_str().unwrap_or("")));
      }
      let mut after = effective.clone();
      merge(&mut after, row);
      let selected_after = if after["apiPoolEnabled"] == true {
        after["apiProfiles"].as_array().cloned().unwrap_or_default()
      } else {
        vec![after["apiProfile"].clone()]
      };
      if selected_after != desired {
        row["apiPoolEnabled"] = json!(true);
        row["apiProfiles"] = json!(desired);
      }
    };
    if !deleted.is_empty() || previous_empty {
      fix(&mut doc["defaults"], &before["defaults"]);
      for (k, row) in doc["saves"].as_object_mut().unwrap() {
        let mut e = before["defaults"].clone();
        merge(&mut e, &before["saves"][k]);
        fix(row, &e);
      }
    }
    for row in std::iter::once(&doc["defaults"]).chain(doc["saves"].as_object().unwrap().values()) {
      validate_overrides(row)?;
      if let Some(name) = row["apiProfile"].as_str() {
        ensure!(
          names.contains(&name.to_string()) || name == "legacy" && names.is_empty(),
          "unknown API profile"
        );
      }
      if let Some(a) = row["apiProfiles"].as_array() {
        for v in a {
          ensure!(names.contains(&v.as_str().unwrap_or("").into()), "unknown API profile");
        }
      }
    }
    // Ordered commit: new credentials, valid references, then deletions.
    atomic(
      &self.root.join("api-profiles.private.json"),
      if deleted.is_empty() { &profiles } else { &transitional },
    )?;
    atomic(&self.root.join("settings.json"), &doc)?;
    if !deleted.is_empty() {
      atomic(&self.root.join("api-profiles.private.json"), &profiles)?;
    }
    self.document = doc;
    self.profiles = profiles;
    self.publish()?;
    Ok(self.snapshot(world))
  }
  pub fn selected(&self, world: &str) -> Vec<(String, Value)> {
    let s = self.effective(world);
    let ids = if s["apiPoolEnabled"] == true {
      s["apiProfiles"].as_array().cloned().unwrap_or_default()
    } else {
      vec![s["apiProfile"].clone()]
    };
    ids
      .iter()
      .filter_map(|id| {
        let name = id.as_str()?;
        let mut p = self.profiles["profiles"].get(name)?.clone();
        if p["enabled"] != true {
          return None;
        }
        if s["apiPoolEnabled"] != true {
          p["concurrency"] = s["concurrency"].clone();
        }
        Some((name.into(), p))
      })
      .collect()
  }
}
#[cfg(windows)]
pub fn clipboard() -> Result<String> {
  use windows_sys::Win32::System::{DataExchange::*, Memory::*};
  unsafe {
    ensure!(OpenClipboard(std::ptr::null_mut()) != 0, "clipboard unavailable");
    struct Close;
    impl Drop for Close {
      fn drop(&mut self) {
        unsafe {
          CloseClipboard();
        }
      }
    }
    let _close = Close;
    let h = GetClipboardData(13);
    ensure!(!h.is_null(), "clipboard unavailable");
    let p = GlobalLock(h) as *const u16;
    ensure!(!p.is_null(), "clipboard unavailable");
    let n = GlobalSize(h) / 2;
    let slice = std::slice::from_raw_parts(p, n.min(8193));
    let len = slice.iter().position(|x| *x == 0).unwrap_or(slice.len());
    let text = String::from_utf16(&slice[..len]);
    GlobalUnlock(h);
    let text = text?;
    validate_overrides(&json!({"translationPrompt":text}))?;
    Ok(text)
  }
}
#[cfg(not(windows))]
pub fn clipboard() -> Result<String> {
  anyhow::bail!("clipboard unavailable")
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn restart_preserves_private_bytes_and_redacts_keys() {
    let d = tempfile::tempdir().unwrap();
    let mut s = Settings::load(d.path(), &json!({})).unwrap();
    s.apply(&json!({"scope":"global","profiles":[{"id":"test","enabled":true,"baseUrl":"https://example.com/v1","model":"test","key":"private-fixture"}],"settings":{"apiProfile":"test"}})).unwrap();
    let p = d.path().join("api-profiles.private.json");
    let original = std::fs::read(&p).unwrap();
    let reloaded = Settings::load(d.path(), &json!({})).unwrap();
    assert_eq!(std::fs::read(p).unwrap(), original);
    assert!(!reloaded.snapshot("").to_string().contains("private-fixture"));
    assert_eq!(reloaded.snapshot("")["profiles"]["test"]["hasKey"], true);
  }
  #[test]
  fn invalid_apply_leaves_files_unchanged() {
    let d = tempfile::tempdir().unwrap();
    let mut s = Settings::load(d.path(), &json!({})).unwrap();
    let before = std::fs::read(d.path().join("settings.json")).unwrap();
    assert!(s.apply(&json!({"scope":"global","settings":{"language":"en"}})).is_err());
    assert_eq!(std::fs::read(d.path().join("settings.json")).unwrap(), before);
  }
  #[test]
  fn per_save_and_delete_pool_preserves_disabled_selection() {
    let d = tempfile::tempdir().unwrap();
    let mut s = Settings::load(d.path(), &json!({})).unwrap();
    s.apply(&json!({"scope":"global","profiles":[{"id":"a","enabled":false},{"id":"b","enabled":false}],"settings":{"apiProfile":"a"}})).unwrap();
    s.apply(&json!({"scope":"save","world":"save/region1","settings":{"language":"zh-Hans"}})).unwrap();
    s.apply(&json!({"scope":"global","deleteProfiles":["a"]})).unwrap();
    assert_eq!(s.effective("region1")["language"], "zh-Hans");
    assert_eq!(s.effective("")["apiProfiles"], json!([]));
    assert_eq!(s.effective("")["apiPoolEnabled"], true);
  }
}
