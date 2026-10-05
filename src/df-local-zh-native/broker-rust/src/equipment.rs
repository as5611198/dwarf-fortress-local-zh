use crate::common::re;
use anyhow::Result;
use std::{collections::HashMap, path::Path};
#[derive(Default)]
pub struct Terms {
  materials: HashMap<String, String>,
  species: HashMap<String, String>,
  nouns: HashMap<String, String>,
  meat_nouns: HashMap<String, String>,
  meat_modifiers: HashMap<String, String>,
  sizes: Vec<(String, String)>,
}
// Borrow the original suffix so both lookup paths preserve its exact position.
// Malformed counts stay in the source and fail the item grammar atomically.
pub fn split_stack_count(source:&str)->(&str,&str) {
  if let Some((core,tail))=source.rsplit_once(" [") {
    if let Some(digits)=tail.strip_suffix(']') {
      if (1..=10).contains(&digits.len()) && digits.bytes().all(|b|b.is_ascii_digit()) {
        return source.split_at(core.len());
      }
    }
  }
  (source,"")
}
pub fn material_name(source:&str,materials:&HashMap<String,String>,species:&HashMap<String,String>)->Option<String> {
  if let Some(t)=materials.get(source) {return Some(t.clone());}
  let (animal,material)=source.rsplit_once(' ')?;
  if !matches!(material,"leather"|"wool"|"silk"|"bone"|"shell"|"horn"|"tooth"|"ivory") {return None;}
  Some(format!("{}{}",species.get(animal)?,materials.get(material)?))
}
// Food modifiers and species belong to the meat grammar, not the generic
// material/noun join: "prepared iron brain" must remain unknown.
pub fn meat_name(mut source:&str,species:&HashMap<String,String>,nouns:&HashMap<String,String>,modifiers:&HashMap<String,String>)->Option<String> {
  let mut prefix=String::new();
  for choices in [&["rotten"][..],&["preserved"][..],&["prepared","chopped"][..]] {
    for key in choices {
      if let Some(rest)=source.strip_prefix(key).and_then(|s|s.strip_prefix(' ')) {
        prefix.push_str(modifiers.get(*key)?);source=rest;break;
      }
    }
  }
  if let Some(noun)=nouns.get(source) {return Some(format!("{prefix}{noun}"));}
  let (animal,noun)=source.rsplit_once(' ')?;
  Some(format!("{prefix}{}{}",species.get(animal)?,nouns.get(noun)?))
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
  pub fn preference_material(&self,text:&str)->Option<String> {
    material_name(text,&self.materials,&self.species)
  }
  pub fn load(root: &Path) -> Result<Self> {
    let read = |p: &Path| -> Result<toml::Value> { Ok(toml::from_str(&std::fs::read_to_string(p)?)?) };
    let mut t = Self::default();
    let materials = read(&root.join("materials/state.toml"))?;
    t.materials.extend(literals(&materials, &["", "shared::main", "adjective"]));
    let species=root.join("creatures/name.toml");
    if species.is_file() {t.species.extend(literals(&read(&species)?, &["singular"]));}
    let mut files = std::fs::read_dir(root.join("items"))?
      .filter_map(|e| e.ok())
      .map(|e| e.path())
      .filter(|p| p.extension().is_some_and(|s| s == "toml"))
      .collect::<Vec<_>>();
    files.sort();
    for file in files {
      let d = read(&file)?;
      if file.file_stem().is_some_and(|s|s=="meat") {
        t.meat_nouns.extend(literals(&d,&["singular::main","plural::main"]));
        t.meat_modifiers.extend(literals(&d,&["^0","^1","^prefix"]).into_iter().map(|(s,v)|(s.trim_end().into(),v)));
      }
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
    let (core,count)=split_stack_count(source);
    let mut inner=core.to_string();
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
    // Stocks put stack size inside the ownership parentheses, while group
    // headings put it outside. Keep its native position and reject two counts.
    let (core_item,inside_count)=split_stack_count(&inner);
    let inside_count=inside_count.to_string();
    if !count.is_empty() && !inside_count.is_empty() {return None;}
    inner=core_item.to_string();
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
    let wrap = |s: &str| format!("{prefix}{size}{s}{inside_count}{suffix}{count}");
    // Drinks, powders and liquids are material state names, not item nouns.
    // Require a stack count so ordinary material labels retain their existing
    // dictionary/context precedence (e.g. geometric diamond versus gemstone).
    if (!count.is_empty() || !inside_count.is_empty()) && size.is_empty() {
      if let Some(v)=self.materials.get(&core) {return Some(wrap(v));}
    }
    if let Some(v) = self.nouns.get(&core) {
      if inner.starts_with(&core) || !count.is_empty() || !inside_count.is_empty() || !matches!(core.as_str(), "pick" | "picks") {
        return Some(wrap(v));
      }
    }
    if let Some(v)=meat_name(&core,&self.species,&self.meat_nouns,&self.meat_modifiers) {return Some(wrap(&v));}
    for (i, _) in core.match_indices(' ') {
      if let (Some(material), Some(noun)) = (material_name(&core[..i],&self.materials,&self.species), self.nouns.get(&core[i + 1..])) {
        return Some(wrap(&format!("{material}{noun}")));
      }
    }
    None
  }
}
#[cfg(test)]
mod tests {
  #[test]
  fn root_material_state_literals_are_loaded_for_item_composition() {
    let d=tempfile::tempdir().unwrap();std::fs::create_dir(d.path().join("materials")).unwrap();
    std::fs::create_dir(d.path().join("items")).unwrap();
    std::fs::write(d.path().join("materials/state.toml"),"[[rulesets]]\n[rulesets.rules]\nbirch=\"樺樹\"\n").unwrap();
    std::fs::write(d.path().join("items/bed.toml"),"[[rulesets]]\nname=\"plural::main\"\n[rulesets.rules]\nbeds=\"床\"\n").unwrap();
    let terms=super::Terms::load(d.path()).unwrap();
    assert_eq!(terms.translate("birch beds").as_deref(),Some("樺樹床"));
  }
  use super::*;
  #[test]
  fn stock_material_stacks_keep_count_inside_ownership_and_quality() {
    let t=Terms {
      materials:HashMap::from([("dwarven ale".into(),"矮人精釀".into()),("dwarven rum".into(),"矮人朗姆酒".into())]),
      nouns:HashMap::from([("battle axe".into(),"戰斧".into()),("pick".into(),"鶴嘴鋤".into())]),
      ..Default::default()
    };
    for (source,want) in [
      ("Dwarven ale [20]","矮人精釀 [20]"),
      ("(dwarven ale [5])","(矮人精釀 [5])"),
      ("☼(dwarven rum [5])☼","☼(矮人朗姆酒 [5])☼"),
      ("(dwarven rum) [20]","(矮人朗姆酒) [20]"),
      ("(battle axe [5])","(戰斧 [5])"),
      ("(Pick [5])","(鶴嘴鋤 [5])"),
    ] {
      assert_eq!(t.translate(source).as_deref(),Some(want),"{source}");
    }
    // The quantity adapter must not change undecorated material vocabulary or
    // emit a partial translation of an unidentified item/malformed quantity.
    for source in ["dwarven ale","unknown ale [5]","(unknown ale [5])",
      "(dwarven ale [oops])","dwarven ale [5] trailing","dwarven ale [５]",
      "dwarven ale [99999999999]","(dwarven ale [5]) [20]"] {
      assert!(t.translate(source).is_none(),"{source}");
    }
  }
  #[test]
  #[ignore="requires DF_OFFLINE_PACKAGE path"]
  fn prepared_meat_keeps_species_wrappers_and_count() {
    let root=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
    for (lang,want) in [("zh-Hant","☼預備的蒼蠅腦☼ [5]"),("zh-Hans","☼预备的苍蝇脑☼ [5]")] {
      let terms=Terms::load(&root.join("dfi18n-data/rulesets").join(lang)).unwrap();
      assert_eq!(terms.translate("☼prepared fly brain☼ [5]").as_deref(),Some(want));
      for source in ["prepared unknown beast brain [5]","prepared fly unknown organ [5]","prepared iron brain","prepared fly brain [oops]"] {
        assert!(terms.translate(source).is_none(),"{source}");
      }
    }
  }
  #[test]
  fn equipment_keeps_quality_size_material_and_stack() {
    let t = Terms {
      materials: HashMap::from([("iron".into(), "鐵".into())]),
      nouns: HashMap::from([("left gauntlet".into(), "左手套".into())]),
      sizes: vec![("large".into(), "大型".into())],
      ..Default::default()
    };
    assert_eq!(
      t.translate("☼large iron left gauntlet☼ [2]"),
      Some("☼大型鐵左手套☼ [2]".into())
    );
    assert!(t.translate("Urist's instrument").is_none());
  }
}
