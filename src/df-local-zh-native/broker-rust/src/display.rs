//! Fixed Legends roles and local display-cache export, compatible with the old Broker.
use crate::common::*;
use anyhow::{Result, bail};
use serde_json::{Value, json};
use std::collections::{BTreeMap, HashSet};

pub fn role(source: &str, races: &Value, language: &str) -> Result<String> {
  let (gender, mut text) = if let Some(s) = source.strip_prefix("male ") {
    ("男性", s.to_owned())
  } else if let Some(s) = source.strip_prefix("female ") {
    ("女性", s.to_owned())
  } else {
    ("", source.to_owned())
  };
  if let Some(s) = text.strip_prefix("dwarven ") {
    text = format!("dwarf {s}");
  }
  let special = match text.as_str() {
    "force" => Some("力量"),
    "brute bride of twilight" => Some("暮光蠻獸新娘"),
    "kelenken hen" => Some("凱倫肯"),
    _ => None,
  };
  if let Some(s) = special {
    return Ok(convert(&format!("{gender}{s}"), language));
  }
  if races[&text].is_null() {
    if let Some(s) = text.strip_suffix(" woman") {
      text = format!("{s} man");
    }
  }
  if let Some(s) = races[&text].as_str() {
    return Ok(convert(&format!("{gender}{s}"), language));
  }
  for (title, zh) in [
    ("chaos follower", "混沌追隨者"),
    ("risen stalker", "復甦潛行者"),
    ("necromancer", "死靈法師"),
    ("bridegroom", "新郎"),
    ("husband", "丈夫"),
    ("wife", "妻子"),
    ("consort", "伴侶"),
    ("god", "男神"),
    ("goddess", "女神"),
    ("deity", "神祇"),
  ] {
    if let Some(race) = text.strip_suffix(&format!(" {title}")) {
      if let Some(s) = races[race].as_str() {
        return Ok(convert(&format!("{gender}{s}{zh}"), language));
      }
    }
  }
  bail!("unmapped Legends role")
}

pub fn native_rows(rows: &[Value], names: &HashSet<String>, language: &str) -> (Vec<Value>, Value) {
  let base = if rows.iter().any(|r| r["language"] == language) {
    language
  } else {
    "zh-Hant"
  };
  let fingerprint = rows
    .iter()
    .rev()
    .find(|r| r["language"] == base && r.get("fingerprint").is_some())
    .map(|r| r["fingerprint"].clone())
    .unwrap_or(Value::Null);
  let mut latest = BTreeMap::new();
  for row in rows {
    if row["language"] == base
      && row["fingerprint"] == fingerprint
      && matches!(row["kind"].as_str(), Some("plain" | "markup"))
    {
      if let Some(text) = row["original"].as_str() {
        latest.insert(text, row);
      }
    }
  }
  let mut plain = Vec::new();
  let mut sources = Vec::new();
  let mut bindings = Vec::new();
  let mut fragments = BTreeMap::new();
  for (text, row) in latest {
    if row["status"] != "translated" || text.is_empty() || text.chars().count() > 8000 {
      continue;
    }
    let translation = convert(row["translation"].as_str().unwrap_or(""), language);
    if text.starts_with("[C:") {
      if let Some(c) = re(r"^\[C:([0-7]):([0-7]):([01])\](.+)$").captures(text) {
        let prefix = &text[..c.get(4).unwrap().start()];
        if aliases(&c[4]) && translation.starts_with(prefix) {
          let s = re(r"\[C:\d+:\d+:\d+\]").replace_all(&translation, "").into_owned();
          if !s.is_empty() && !re(r"[A-Za-z{}\[\]]").is_match(&s) {
            let color =
              c[1].parse::<u8>().unwrap() + 8 * c[2].parse::<u8>().unwrap() + 64 * c[3].parse::<u8>().unwrap();
            fragments.insert((color, s.clone()), json!({"translation":s,"color":color,"key":&c[4]}));
          }
          continue;
        }
      }
    }
    if aliases(text) || re(r"\blikes\b").is_match(text) {
      continue;
    }
    let Ok(v) = validate(text, &translation) else { continue };
    if names.contains(text) {
      bindings.push(json!({"text":text,"translation":v}));
    } else if re(r"^(?:He|She|His|Her)\b|^Overall, (?:he|she)\b").is_match(text) {
      sources.push(json!({"text":text,"translation":v}));
    } else if !text.contains('{') {
      let mut r = json!({"text":text,"translation":v,"kind":row["kind"]});
      if matches!(row["alignment"].as_str(), Some("center" | "right")) {
        r["alignment"] = row["alignment"].clone();
      }
      plain.push(r);
    }
  }
  (
    plain,
    json!({"sources":sources,"names":bindings,"fragments":fragments.into_values().collect::<Vec<_>>()}),
  )
}
