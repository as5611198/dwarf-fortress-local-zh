use anyhow::{Result, bail};
use regex::Regex;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{path::Path, sync::OnceLock};
pub const POLICY: &str = "df-zh-3";
pub fn hash(bytes: impl AsRef<[u8]>) -> String {
  format!("{:x}", Sha256::digest(bytes.as_ref()))
}
pub fn cache_key(text: &str, language: &str, kind: &str) -> String {
  let policy = if kind == "exact" {
    POLICY.to_string()
  } else {
    format!("{POLICY}:{kind}")
  };
  hash(serde_json::to_vec(&json!([policy, language, text])).unwrap())
}
pub fn language(value: &str) -> bool {
  matches!(value, "zh-Hant" | "zh-Hans")
}
pub fn now() -> i64 {
  chrono::Utc::now().timestamp_millis()
}
pub fn iso() -> String {
  chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}
pub fn re(pattern: &str) -> std::sync::Arc<Regex> {
  static REGEXES: OnceLock<std::sync::Mutex<std::collections::HashMap<String, std::sync::Arc<Regex>>>> =
    OnceLock::new();
  let mut cache = REGEXES.get_or_init(Default::default).lock().unwrap();
  if let Some(regex) = cache.get(pattern) {
    return regex.clone();
  }
  let regex = std::sync::Arc::new(Regex::new(pattern).expect("valid regex"));
  if cache.len() < 256 {
    cache.insert(pattern.into(), regex.clone());
  }
  regex
}
pub fn tokens() -> &'static Regex {
  static TOKENS: OnceLock<std::sync::Arc<Regex>> = OnceLock::new();
  TOKENS.get_or_init(||re(r"\{\{[^{}\r\n]*\}\}|\{[^{}\r\n]+\}|\[[^\[\]\r\n]+\]|</?[A-Za-z][^>\r\n]*>|%(?:\d+\$)?[-+0 #]*\d*(?:\.\d+)?[a-zA-Z]"))
}
pub fn aliases(text: &str) -> bool {
  re(r"(?:^|[^A-Za-z0-9_])(?:L[A-Za-z0-9]{3}_+|L[A-Za-z0-9]{6}_+|P_____|DFLIVE_[0-9a-f]{64})(?:$|[^A-Za-z0-9_])")
    .is_match(text)
    || text
      .split(|c: char| !c.is_ascii_alphanumeric())
      .any(|w| w.len() == 7 && w.starts_with('L') && w[1..].bytes().any(|b| b.is_ascii_digit()))
}
fn sorted_matches(regex: &Regex, text: &str) -> Vec<String> {
  let mut v = regex.find_iter(text).map(|m| m.as_str().to_owned()).collect::<Vec<_>>();
  v.sort();
  v
}
pub fn validate(source: &str, output: &str) -> Result<String> {
  let value = output.trim();
  if value.is_empty() {
    bail!("empty translation")
  }
  if value.contains("```") || (value.starts_with(['[', '{']) && tokens().find(value).is_none_or(|m| m.start() != 0)) {
    bail!("structured or fenced output")
  }
  if source.starts_with("An ")
    && source.chars().nth(3).is_some_and(|c| c.is_ascii_lowercase())
    && value.starts_with('安')
  {
    bail!("misread English article")
  }
  if sorted_matches(tokens(), source) != sorted_matches(tokens(), value) {
    bail!("format token mismatch")
  }
  let plain_source = tokens().replace_all(source, "");
  let plain_output = tokens().replace_all(value, "");
  if sorted_matches(&re(r"\d+(?:[.,]\d+)*"), &plain_source) != sorted_matches(&re(r"\d+(?:[.,]\d+)*"), &plain_output) {
    bail!("number mismatch")
  }
  let mut prose = plain_output.to_string();
  for id in [
    "gui/overlay",
    "gui/launcher",
    "gui/control-panel",
    "quickstart-guide",
    "DFHack",
    "Windows",
    "ESC",
    "Armok",
    "run",
    "1B",
    "DF",
    "MS",
  ] {
    if plain_source.contains(id) {
      prose = prose.replacen(id, "", plain_source.matches(id).count());
    }
  }
  if re(r"\p{Latin}").is_match(&prose) {
    bail!("residual English")
  }
  if re(r"\p{L}").is_match(&plain_source) && !re(r"\p{Han}").is_match(&plain_output) {
    bail!("missing Chinese")
  }
  if value.chars().count() > 200.max(source.chars().count() * 4) {
    bail!("excessive translation length")
  }
  Ok(value.into())
}
pub fn mentions(text: &str, term: &str) -> bool {
  text.match_indices(term).any(|(i, _)| {
    text[..i].chars().next_back().is_none_or(|c| !c.is_alphanumeric())
      && text[i + term.len()..].chars().next().is_none_or(|c| !c.is_alphanumeric())
  })
}
pub fn convert(text: &str, lang: &str) -> String {
  use ferrous_opencc::{OpenCC, config::BuiltinConfig};
  static HANT: OnceLock<OpenCC> = OnceLock::new();
  static HANS: OnceLock<OpenCC> = OnceLock::new();
  let cc = if lang == "zh-Hans" {
    HANS.get_or_init(|| OpenCC::from_config(BuiltinConfig::T2s).unwrap())
  } else {
    HANT.get_or_init(|| OpenCC::from_config(BuiltinConfig::S2twp).unwrap())
  };
  cc.convert(text)
}
pub fn read_json(path: &Path, limit: u64) -> Result<Value> {
  if std::fs::metadata(path)?.len() > limit {
    bail!("local file too large")
  }
  Ok(serde_json::from_slice(&std::fs::read(path)?)?)
}
pub fn atomic_bytes(path: &Path, bytes: &[u8]) -> Result<()> {
  use std::io::Write;
  if let Some(parent) = path.parent() {
    std::fs::create_dir_all(parent)?;
  }
  let tmp = path.with_extension(format!("{}.tmp", uuid::Uuid::new_v4()));
  let result = (|| {
    let mut file = std::fs::OpenOptions::new().write(true).create_new(true).open(&tmp)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    drop(file);
    replace(&tmp, path)
  })();
  let _ = std::fs::remove_file(tmp);
  result
}
pub fn atomic(path: &Path, value: &Value) -> Result<()> {
  let mut bytes = serde_json::to_vec(value)?;
  bytes.push(b'\n');
  atomic_bytes(path, &bytes)
}
#[cfg(not(windows))]
fn replace(from: &Path, to: &Path) -> Result<()> {
  Ok(std::fs::rename(from, to)?)
}
#[cfg(windows)]
fn replace(from: &Path, to: &Path) -> Result<()> {
  use std::os::windows::ffi::OsStrExt;
  let f = from.as_os_str().encode_wide().chain([0]).collect::<Vec<_>>();
  let t = to.as_os_str().encode_wide().chain([0]).collect::<Vec<_>>();
  if unsafe {
    windows_sys::Win32::Storage::FileSystem::MoveFileExW(
      f.as_ptr(),
      t.as_ptr(),
      windows_sys::Win32::Storage::FileSystem::MOVEFILE_REPLACE_EXISTING
        | windows_sys::Win32::Storage::FileSystem::MOVEFILE_WRITE_THROUGH,
    )
  } == 0
  {
    bail!("disk commit failed")
  };
  Ok(())
}
pub fn append(path: &Path, value: &Value) -> Result<()> {
  use std::io::{Read, Seek, SeekFrom, Write};
  if let Some(parent) = path.parent() {
    std::fs::create_dir_all(parent)?;
  }
  let mut f = std::fs::OpenOptions::new().create(true).read(true).append(true).open(path)?;
  if f.metadata()?.len() > 0 {
    f.seek(SeekFrom::End(-1))?;
    let mut tail = [0];
    f.read_exact(&mut tail)?;
    if tail[0] != b'\n' {
      f.write_all(b"\n")?;
    }
  }
  f.write_all(&serde_json::to_vec(value)?)?;
  f.write_all(b"\n")?;
  f.sync_data()?;
  Ok(())
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn journal_identity_matches_javascript() {
    assert_eq!(
      cache_key("Health", "zh-Hant", "exact"),
      hash(br#"["df-zh-3","zh-Hant","Health"]"#)
    );
  }
  #[test]
  fn rejects_broken_tokens_numbers_and_english() {
    for text in ["健康 2", "Health 1", "健康 1 {{DFL1}}"] {
      assert!(validate("Health 1 {{DFL0}}", text).is_err());
    }
    assert!(validate("Health 1 {{DFL0}}", "健康 1 {{DFL0}}").is_ok());
  }
  #[test]
  fn failed_atomic_commit_retains_old_file() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("state");
    atomic(&p, &json!({"old":true})).unwrap();
    let blocked = d.path().join("blocked");
    std::fs::write(&blocked, b"file").unwrap();
    assert!(atomic(&blocked.join("state"), &json!({"new":true})).is_err());
    assert_eq!(read_json(&p, 1024).unwrap(), json!({"old":true}));
  }
}
