use std::collections::HashMap;
use std::sync::{OnceLock, RwLock, RwLockReadGuard, RwLockWriteGuard};

use rule_based_translator::{RuleSets, Token, Translator};

use crate::translation;

// Reset the rulesets translators
pub fn reset() {
  get_translators_mut().clear();
  equipment_mut().clear();
}

#[derive(Default)]
struct EquipmentTerms {
  materials: HashMap<String, String>,
  nouns: HashMap<String, String>,
  sizes: HashMap<String, String>,
}

static EQUIPMENT: OnceLock<RwLock<HashMap<String, EquipmentTerms>>> = OnceLock::new();

fn equipment_mut() -> RwLockWriteGuard<'static, HashMap<String, EquipmentTerms>> {
  EQUIPMENT.get_or_init(|| RwLock::new(HashMap::new())).write().unwrap()
}

fn literal(tokens: &[Token]) -> Option<String> {
  tokens.iter().map(|token| match token { Token::Literal(text) => Some(text.as_str()), _ => None }).collect()
}

fn equipment_terms(rulesets: &RuleSets) -> EquipmentTerms {
  let mut terms = EquipmentTerms::default();
  let extend = |name: &str, target: &mut HashMap<String, String>| {
    if let Some(rules) = rulesets.get(name) {
      for (source, translated) in rules {
        if let (Some(source), Some(translated)) = (literal(source), literal(translated)) {
          if source.starts_with(|c: char| c.is_ascii_lowercase()) &&
            source.chars().all(|c| c.is_ascii_lowercase() || c == ' ' || c == '-') {
            target.insert(source.trim_end().to_owned(), translated);
          }
        }
      }
    }
  };
  for name in ["::materials::state::shared::main", "::materials::state::adjective"] {
    extend(name, &mut terms.materials);
  }
  let categories: std::collections::BTreeSet<_> = rulesets.keys().filter_map(|name|
    name.strip_prefix("::items::").and_then(|name| name.split("::").next())).collect();
  for category in categories {
    let base=format!("::items::{category}");
    let mut nouns=HashMap::new();
    for part in ["main","default::main","singular::main","plural::main"] {
      extend(&format!("{base}::{part}"),&mut nouns);
    }
    // Item-specific modifiers cannot bleed into unrelated categories.
    for part in ["^chain","^handedness","^length"] {
      let mut modifiers=HashMap::new();
      extend(&format!("{base}::{part}"),&mut modifiers);
      let additions: Vec<_> = modifiers.iter().flat_map(|(source,text)| nouns.iter().map(move |(noun,translation)|
        (format!("{source} {noun}"),format!("{text}{translation}")))).collect();
      nouns.extend(additions);
    }
    terms.nouns.extend(nouns);
    extend(&format!("{base}::^material"),&mut terms.materials);
  }
  extend("::items::prefix::maybe_equipment_size",&mut terms.sizes);
  terms
}

#[cfg(test)]
mod equipment_tests {
  use super::*;

  #[test]
  fn arena_equipment_wrappers_survive_sync_lookup() {
    let terms = EquipmentTerms {materials: HashMap::from([("copper".into(),"銅".into()),("silver".into(),"銀".into())]),
      nouns:HashMap::from([("mace".into(),"頁鎚".into()),("war hammer".into(),"戰錘".into())]),..Default::default()};
    for (source,want) in [("{copper mace}","{銅頁鎚}"),("{silver war hammer}","{銀戰錘}"),
      ("X{☼silver war hammer☼}X","X{☼銀戰錘☼}X"),("{*copper mace*} [2]","{*銅頁鎚*} [2]")] {
      assert_eq!(equipment_name(source,&terms).as_deref(),Some(want),"{source}");
    }
    for source in ["{copper mace","copper mace}","{He picks up a stone.}","{silver war hammer}+"] {
      assert_eq!(equipment_name(source,&terms),None,"{source}");
    }
  }

  #[test]
  #[ignore = "requires DF_LOCAL_RULESETS integration data path"]
  fn installed_weapon_and_tool_rules_supply_sync_nouns() {
    rule_based_translator::register_default_replacers();
    let path = std::env::var("DF_LOCAL_RULESETS").unwrap();
    let mut translator = Translator::default();
    translator.load_from_dir(path).unwrap();
    let terms = equipment_terms(translator.dump());
    assert_eq!(equipment_name("Iron picks [3]", &terms).as_deref(), Some("鐵鶴嘴鋤 [3]"));
    assert_eq!(equipment_name("steel great axes [2]", &terms).as_deref(), Some("鋼巨斧 [2]"));
    assert_eq!(equipment_name("wooden carving knives [5]", &terms).as_deref(), Some("木製切肉刀 [5]"));
    assert_eq!(equipment_name("He picks up a stone.", &terms), None);
  }

  #[test]
  #[ignore = "requires DF_LOCAL_RULESETS integration data path"]
  fn installed_item_title_rules_cover_armor_sizes_and_wrappers() {
    rule_based_translator::register_default_replacers();
    let path = std::env::var("DF_LOCAL_RULESETS").unwrap();
    let hans = path.ends_with("zh-Hans");
    let mut translator = Translator::default();
    translator.load_from_dir(path).unwrap();
    let terms = equipment_terms(translator.dump());
    for (source,hant,hans_text) in [
      ("{silver shield}","{銀尖盾}","{银尖盾}"),
      ("x{large silver helm}x","x{大銀頭盔}x","x{大银头盔}x"),
      ("{large silver breastplate}","{大銀板甲}","{大银板甲}"),
      ("XX{☼small iron high boots☼}XX [2]","XX{☼小鐵高筒靴☼}XX [2]","XX{☼小铁高筒靴☼}XX [2]"),
      ("+steel left gauntlet+","+鋼左護手+","+钢左护手+"),
      ("{leather backpack}","{皮革背包}","{皮革背包}"),
      ("silver bucklers [3]","銀圓盾 [3]","银圆盾 [3]"),
      ("{copper bolts} [20]","{銅弩矢} [20]","{铜弩矢} [20]"),
      ("{wooden bucket}","{木製提桶}","{木制提桶}"),
    ] {
      assert_eq!(equipment_name(source,&terms).as_deref(),Some(if hans {hans_text} else {hant}),"{source}");
    }
    for source in ["large silver unknown item","large He picks up a stone","{silver shield}+"] {
      assert_eq!(equipment_name(source,&terms),None,"{source}");
    }
  }
}

fn equipment_name(text: &str, terms: &EquipmentTerms) -> Option<String> {
  if text.len() > 200 { return None; }
  let (core, count) = match text.rsplit_once(" [") {
    Some((core, count)) if count.ends_with(']') && count[..count.len()-1].chars().all(|c| c.is_ascii_digit())
      && count.len() > 1 => (core, format!(" [{}", count)),
    _ => (text, String::new()),
  };
  let mut core=core;
  let mut prefix=String::new();
  let mut suffix=String::new();
  for _ in 0..9 {
    let pair=[("XX","XX"),("X","X"),("x","x"),("{","}"),("(",")"),("$","$"),("‼","‼"),
      ("-","-"),("+","+"),("*","*"),("≡","≡"),("☼","☼"),("«","»"),("◄","►")]
      .into_iter().find(|(l,r)| core.len()>l.len()+r.len() && core.starts_with(l) && core.ends_with(r));
    let Some((left,right))=pair else {break};
    core=&core[left.len()..core.len()-right.len()];
    prefix.push_str(left);suffix=format!("{right}{suffix}");
  }
  if !core.starts_with(|c: char| c.is_ascii_alphabetic()) ||
    !core.chars().all(|c| c.is_ascii_alphabetic() || c == ' ' || c == '-' || c == '\'') { return None; }
  let lower = core.to_ascii_lowercase();
  let (lower,size)=terms.sizes.iter().find_map(|(source,text)|
    lower.strip_prefix(&format!("{source} ")).map(|rest|(rest,text.as_str())))
    .unwrap_or((&lower,""));
  if let Some(noun) = terms.nouns.get(lower) {
    if core == lower || !count.is_empty() || !matches!(lower, "pick" | "picks") {
      return Some(format!("{prefix}{size}{noun}{suffix}{count}"));
    }
  }
  for (space, _) in lower.match_indices(' ') {
    if let (Some(material), Some(noun)) = (terms.materials.get(&lower[..space]), terms.nouns.get(&lower[space+1..])) {
      return Some(format!("{prefix}{size}{material}{noun}{suffix}{count}"));
    }
  }
  None
}

pub fn translate_equipment(lang_tag: &str, text: &str) -> Option<translation::TranslationResponse> {
  let terms = EQUIPMENT.get_or_init(|| RwLock::new(HashMap::new())).read().unwrap();
  equipment_name(text, terms.get(lang_tag)?).map(|translated| translation::TranslationResponse {
    translated, alignment: translation::TextAlignment::default(),
  })
}

#[cfg(test)]
pub(crate) fn fixture_equipment(lang_tag: &str, materials: &[(&str, &str)], nouns: &[(&str, &str)]) {
  equipment_mut().insert(lang_tag.into(), EquipmentTerms {
    materials: materials.iter().map(|(a,b)| ((*a).into(),(*b).into())).collect(),
    nouns: nouns.iter().map(|(a,b)| ((*a).into(),(*b).into())).collect(),
    ..Default::default()
  });
}

// Translate text based on the provided language tag and context
pub fn translate(
  lang_tag: &str,
  context: &translation::TranslationContext,
) -> Option<translation::TranslationResponse> {
  let translators = get_translators();
  let translator = translators.get(lang_tag)?;
  let text = context.original();

  translator.translate(text).map(|translated| translation::TranslationResponse {
    translated,
    alignment: translation::TextAlignment::default(),
  })
}

// A global registry of translators categorized by type and language tag
static TRANSLATORS: OnceLock<RwLock<HashMap<String, Translator>>> = OnceLock::new();

// Getting access to the translators registry
fn get_translators() -> RwLockReadGuard<'static, HashMap<String, Translator>> {
  TRANSLATORS.get_or_init(|| RwLock::new(HashMap::new())).read().unwrap()
}

// Getting mutable access to the translators registry
fn get_translators_mut() -> RwLockWriteGuard<'static, HashMap<String, Translator>> {
  TRANSLATORS.get_or_init(|| RwLock::new(HashMap::new())).write().unwrap()
}

#[cfg(test)]
pub(crate) fn fixture_rules(language:&str,path:&std::path::Path) {
  let mut translator=Translator::default();
  translator.load_from_dir(path).unwrap();
  get_translators_mut().insert(language.into(),translator);
}

// Load rulesets from a directory for a specific language
#[unsafe(no_mangle)]
extern "C" fn load_translation_rulesets(lua_state: *mut std::ffi::c_void) -> i32 {
  let lang_tag = lua53_sys::check_string(lua_state, 1);
  let path = lua53_sys::check_string(lua_state, 2);

  let mut translators = get_translators_mut();
  let mut candidate = translators.get(&lang_tag).cloned().unwrap_or_default();
  if let Err(error) = candidate.load_from_dir(&path) {
    log::error!("Rulesets load failed for {path:?}: {error:#}");
    lua53_sys::push_boolean(lua_state, false);
    lua53_sys::push_string(lua_state, &format!("{error:#}"));
    return 2;
  }
  crate::search::aliases(&lang_tag,candidate.dump().values().flat_map(|rules| rules.iter())
    .filter_map(|(source,text)| Some((literal(source)?,literal(text)?))));
  equipment_mut().insert(lang_tag.clone(), equipment_terms(candidate.dump()));
  translators.insert(lang_tag.clone(), candidate);

  log::info!("Loaded Rulesets translator for language {lang_tag:?} from {path:?}");
  lua53_sys::push_boolean(lua_state, true);
  lua53_sys::push_nil(lua_state);
  2
}
