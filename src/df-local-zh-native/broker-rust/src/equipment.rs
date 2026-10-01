use crate::common::re;
use anyhow::Result;
use std::{collections::HashMap, path::Path};
#[derive(Default)]
pub struct Terms {
  materials: HashMap<String, String>,
  nouns: HashMap<String, String>,
  sizes: Vec<(String, String)>,
}
fn literals(doc: &toml::Value, names: &[&str]) -> Vec<(String, String)> {
  doc
    .get("rulesets")
    .and_then(toml::Value::as_array)
    .into_iter()
    .flatten()
    .filter(|r| names.contains(&r.get("name").and_then(toml::Value::as_str).unwrap_or("")))
    .flat_map(|r| r.get("rules").and_then(toml::Value::as_table).into_iter().flatten())
    .filter_map(|(s, v)| {
      v.as_str().filter(|v| re(r"^[a-z][a-z -]*$").is_match(s) && !v.contains('{')).map(|v| (s.clone(), v.into()))
    })
    .collect()
}
impl Terms {
  pub fn load(root: &Path) -> Result<Self> {
    let read = |p: &Path| -> Result<toml::Value> { Ok(toml::from_str(&std::fs::read_to_string(p)?)?) };
    let mut t = Self::default();
    let materials = read(&root.join("materials/state.toml"))?;
    t.materials.extend(literals(&materials, &["shared::main", "adjective"]));
    let mut files = std::fs::read_dir(root.join("items"))?
      .filter_map(|e| e.ok())
      .map(|e| e.path())
      .filter(|p| p.extension().is_some_and(|s| s == "toml"))
      .collect::<Vec<_>>();
    files.sort();
    for file in files {
      let d = read(&file)?;
      let mut nouns = literals(&d, &["main", "default::main", "singular::main", "plural::main"]);
      for name in ["^chain", "^handedness", "^length"] {
        let mods = literals(&d, &[name]);
        let combos = mods
          .iter()
          .flat_map(|(s, v)| nouns.iter().map(move |(n, tr)| (format!("{} {n}", s.trim_end()), format!("{v}{tr}"))))
          .collect::<Vec<_>>();
        nouns.extend(combos);
      }
      t.nouns.extend(nouns);
      t.materials.extend(literals(&d, &["^material"]).into_iter().map(|(s, v)| (s.trim_end().into(), v)));
      t.sizes
        .extend(literals(&d, &["prefix::maybe_equipment_size"]).into_iter().map(|(s, v)| (s.trim_end().into(), v)));
    }
    Ok(t)
  }
  pub fn translate(&self, source: &str) -> Option<String> {
    if source.chars().count() > 100 {
      return None;
    }
    let pattern = re(r"^(.*?)( \[\d+\])?$");
    let m = pattern.captures(source)?;
    let mut inner = m[1].to_string();
    let count = m.get(2).map(|m| m.as_str()).unwrap_or("");
    let mut prefix = String::new();
    let mut suffix = String::new();
    for _ in 0..9 {
      let pair = [
        ("XX", "XX"),
        ("X", "X"),
        ("x", "x"),
        ("{", "}"),
        ("(", ")"),
        ("$", "$"),
        ("‼", "‼"),
        ("-", "-"),
        ("+", "+"),
        ("*", "*"),
        ("≡", "≡"),
        ("☼", "☼"),
        ("«", "»"),
        ("◄", "►"),
      ]
      .into_iter()
      .find(|(l, r)| inner.len() > l.len() + r.len() && inner.starts_with(l) && inner.ends_with(r));
      let Some((l, r)) = pair else {
        break;
      };
      prefix.push_str(l);
      suffix = r.to_string() + &suffix;
      inner = inner[l.len()..inner.len() - r.len()].into();
    }
    if !re(r"^[A-Za-z][A-Za-z' -]*$").is_match(&inner) {
      return None;
    }
    let mut core = inner.to_lowercase();
    let mut size = String::new();
    for (s, v) in &self.sizes {
      if core.starts_with(&format!("{s} ")) {
        size = v.clone();
        core = core[s.len() + 1..].into();
        break;
      }
    }
    let wrap = |s: &str| format!("{prefix}{size}{s}{suffix}{count}");
    if let Some(v) = self.nouns.get(&core) {
      if inner.starts_with(&core) || !count.is_empty() || !matches!(core.as_str(), "pick" | "picks") {
        return Some(wrap(v));
      }
    }
    for (i, _) in core.match_indices(' ') {
      if let (Some(material), Some(noun)) = (self.materials.get(&core[..i]), self.nouns.get(&core[i + 1..])) {
        return Some(wrap(&format!("{material}{noun}")));
      }
    }
    None
  }
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn equipment_keeps_quality_size_material_and_stack() {
    let t = Terms {
      materials: HashMap::from([("iron".into(), "鐵".into())]),
      nouns: HashMap::from([("left gauntlet".into(), "左手套".into())]),
      sizes: vec![("large".into(), "大型".into())],
    };
    assert_eq!(
      t.translate("☼large iron left gauntlet☼ [2]"),
      Some("☼大型鐵左手套☼ [2]".into())
    );
    assert!(t.translate("Urist's instrument").is_none());
  }
}
