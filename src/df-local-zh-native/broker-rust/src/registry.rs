//! A single immutable world-name snapshot, shared by in-flight requests.
use crate::common::mentions;
use aho_corasick::{AhoCorasick, AhoCorasickKind};
use serde_json::{Value, json};
use std::{collections::{HashMap, HashSet}, sync::Arc};

pub(crate) struct Registry {
  pub value: Arc<Value>,
  identities: HashMap<String, usize>,
  matcher: Option<AhoCorasick>,
  aliases: Vec<String>,
  owners: Vec<Vec<usize>>,
  empty_aliases: Vec<usize>,
}

impl Registry {
  pub fn new(value: Value) -> Self {
    let mut identities = HashMap::new();
    let mut patterns = HashMap::new();
    let mut aliases = Vec::new();
    let mut owners: Vec<Vec<usize>> = Vec::new();
    let mut empty_aliases = Vec::new();
    for (i, row) in value["entities"].as_array().into_iter().flatten().enumerate() {
      if let Some(id) = row["id"].as_str() {
        // Preserve the old .find() behavior for malformed duplicate IDs.
        identities.entry(id.to_owned()).or_insert(i);
      }
      for alias in row["aliases"].as_array().into_iter().flatten().filter_map(Value::as_str) {
        if matches!(alias, "A" | "An" | "The") { continue; }
        if alias.is_empty() {
          if empty_aliases.last() != Some(&i) { empty_aliases.push(i); }
          continue;
        }
        let pattern = *patterns.entry(alias).or_insert_with(|| {
          aliases.push(alias.to_owned());
          owners.push(Vec::new());
          aliases.len() - 1
        });
        if owners[pattern].last() != Some(&i) { owners[pattern].push(i); }
      }
    }
    // NFA avoids a potentially huge DFA on a large world. Build errors retain
    // the legacy scan, so resource limits cannot silently discard names.
    let matcher = if aliases.is_empty() { None } else { match AhoCorasick::builder().kind(Some(AhoCorasickKind::ContiguousNFA)).build(&aliases) {
      Ok(matcher) => Some(matcher),
      Err(error) => { eprintln!("world-name index unavailable; using registry scan: {error}"); None }
    }};
    Self { value: Arc::new(value), identities, matcher, aliases, owners, empty_aliases }
  }

  pub fn empty(world: &str) -> Self {
    Self::new(json!({"world":world,"entities":[]}))
  }

  pub fn by_id(&self, id: &str) -> Option<&Value> {
    self.identities.get(id).map(|i| &self.value["entities"][*i])
  }

  pub fn matching(&self, text: &str) -> Vec<&Value> {
    let Some(matcher) = &self.matcher else { return self.scan(text); };
    let mut checked = HashSet::new();
    let mut rows = HashSet::new();
    for found in matcher.find_overlapping_iter(text) {
      let pattern = found.pattern().as_usize();
      // Verify with the established Unicode/non-overlapping boundary rule.
      // Aho-Corasick only selects candidate aliases, never decides identity.
      if checked.insert(pattern) && mentions(text, &self.aliases[pattern]) {
        rows.extend(self.owners[pattern].iter().copied());
      }
    }
    if !self.empty_aliases.is_empty() && mentions(text, "") {
      rows.extend(self.empty_aliases.iter().copied());
    }
    let mut rows: Vec<_> = rows.into_iter().collect();
    rows.sort_unstable();
    rows.into_iter().map(|i| &self.value["entities"][i]).collect()
  }

  fn scan(&self, text: &str) -> Vec<&Value> {
    self.value["entities"].as_array().into_iter().flatten().filter(|row| {
      row["aliases"].as_array().is_some_and(|aliases| aliases.iter().filter_map(Value::as_str)
        .any(|a| !matches!(a, "A" | "An" | "The") && mentions(text, a)))
    }).collect()
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::{hint::black_box, time::Instant};

  fn ids(rows: Vec<&Value>) -> Vec<&str> {
    rows.into_iter().map(|row| row["id"].as_str().unwrap()).collect()
  }

  // Retained pre-index algorithm, independent of the index construction.
  fn scan(value: &Value, text: &str) -> Vec<usize> {
    value["entities"].as_array().unwrap().iter().enumerate().filter_map(|(i,row)| {
      row["aliases"].as_array().is_some_and(|a| a.iter().filter_map(Value::as_str)
        .any(|a| !matches!(a,"A"|"An"|"The") && mentions(text,a))).then_some(i)
    }).collect()
  }

  #[test]
  fn mentions_preserve_unicode_boundaries_overlaps_and_registry_order() {
    let r = Registry::new(json!({"world":"fixture","entities":[
      {"id":"first","aliases":["Urist","The Copper Hall","山𠮷"]},
      {"id":"second","aliases":["Copper Hall","Urist"]},
      {"id":"ignored","aliases":["A","An","The",3,null]},
      {"id":"punctuation","aliases":["(Hall)","Stål","aaa"]},
      {"id":"absent"}
    ]}));
    assert_eq!(ids(r.matching("The Copper Hall welcomed Urist, 山𠮷 and Stål.")),
      ["first","second","punctuation"]);
    assert!(r.matching("AUrist Urist2 山𠮷中 Stålé A An The").is_empty());
    assert_eq!(ids(r.matching("(Hall) Urist's Urist_ Urist")), ["first","second","punctuation"]);
    assert!(r.matching("aaaa").is_empty());
    assert_eq!(r.by_id("second").unwrap()["aliases"][0], "Copper Hall");
    assert!(r.by_id("missing").is_none());
  }

  #[test]
  fn mentions_match_legacy_scan_for_empty_aliases_and_repeated_patterns() {
    let r = Registry::new(json!({"entities":[
      {"id":"empty","aliases":[""]},
      {"id":"short","aliases":["-","--","aaa","-a"]},
      {"id":"long","aliases":["aaa-","a-a","é","𠮷"]},
      {"id":"duplicate","aliases":["aaa","aaa","é"]}
    ]}));
    let atoms = ["", " ", "-", "aaa", "a-a", "é", "𠮷", "9", "_", "\n"];
    for a in atoms { for b in atoms { for c in atoms {
      let text = format!("{a}{b}{c}");
      let expected: Vec<_> = scan(&r.value, &text).into_iter().map(|i| &r.value["entities"][i]).collect();
      assert_eq!(r.matching(&text), expected, "{text:?}");
    }}}
    assert!(Registry::empty("new").matching("Urist").is_empty());
  }

  #[test]
  fn duplicate_identity_keeps_first_row_and_scan_fallback_keeps_all_matches() {
    let mut r = Registry::new(json!({"entities":[
      {"id":"figure:1","aliases":["Urist"],"preferred":"first"},
      {"id":"figure:1","aliases":["Domas"],"preferred":"second"}
    ]}));
    assert_eq!(r.by_id("figure:1").unwrap()["preferred"], "first");
    let expected = r.matching("Urist met Domas").into_iter().cloned().collect::<Vec<_>>();
    r.matcher = None; // Exercise the actual safe fallback if the index cannot be built.
    assert_eq!(r.matching("Urist met Domas"), expected.iter().collect::<Vec<_>>());
  }

  #[test]
  #[ignore = "explicit performance acceptance; compares a 20,000-entity scan on the same process"]
  fn registry_mention_benchmark() {
    let rows: Vec<_> = (0..20_000).map(|i| json!({"id":format!("figure:{i}"),
      "aliases":[format!("Urist Clan{i}"),format!("Copper Hall{i}")]})).collect();
    let start = Instant::now();
    let r = Registry::new(json!({"world":"large","entities":rows}));
    let build = start.elapsed();
    let queries = ["Urist Clan19999 arrived at Copper Hall12345.",
      "The dwarf is content after drinking.", "Urist Clan19 and Urist Clan190 are friends."];
    let start = Instant::now();
    let mut baseline_count = 0;
    for _ in 0..30 { for q in queries { baseline_count += black_box(scan(&r.value, black_box(q))).len(); }}
    let baseline = start.elapsed();
    let start = Instant::now();
    let mut indexed_count = 0;
    for _ in 0..30 { for q in queries { indexed_count += black_box(r.matching(black_box(q))).len(); }}
    let indexed = start.elapsed();
    assert_eq!(baseline_count, 120);
    assert_eq!(indexed_count, baseline_count);
    println!("REGISTRY_BENCH build_ms={:.3} scan_ms={:.3} query_ms={:.3} speedup={:.1} matcher_bytes={}",
      build.as_secs_f64()*1000.0, baseline.as_secs_f64()*1000.0, indexed.as_secs_f64()*1000.0,
      baseline.as_secs_f64()/indexed.as_secs_f64(), r.matcher.as_ref().map_or(0, AhoCorasick::memory_usage));
    assert!(indexed * 4 < baseline, "name lookup still scales like the full registry scan");
  }

  #[test]
  #[ignore = "read-only real registry benchmark; requires DF_REGISTRY_BENCHMARK path"]
  fn registry_real_world_benchmark() {
    let path = std::env::var_os("DF_REGISTRY_BENCHMARK").expect("DF_REGISTRY_BENCHMARK");
    let start = Instant::now();
    let value = crate::common::read_json(std::path::Path::new(&path), 32*1024*1024).unwrap();
    let read = start.elapsed();
    let rows = value["entities"].as_array().unwrap();
    let count = rows.len();
    assert!(count > 1000, "use a representative world");
    let queries: Vec<_> = rows.iter().step_by((count/60).max(1)).take(60)
      .filter_map(|r| r["aliases"].as_array()?.iter().filter_map(Value::as_str).find(|a| !a.is_empty()))
      .map(|a| format!("{a} arrived.")).collect();
    let start = Instant::now();
    let r = Registry::new(value);
    let build = start.elapsed();
    let start = Instant::now();
    let expected: Vec<_> = queries.iter().map(|q| scan(&r.value, q)).collect();
    let scan_time = start.elapsed();
    let start = Instant::now();
    let actual: Vec<_> = queries.iter().map(|q| r.matching(q)).collect();
    let query_time = start.elapsed();
    for (expected, actual) in expected.iter().zip(actual) {
      assert_eq!(expected.iter().map(|i| &r.value["entities"][*i]).collect::<Vec<_>>(), actual);
    }
    println!("REAL_REGISTRY rows={count} queries={} read_ms={:.3} build_ms={:.3} scan_ms={:.3} query_ms={:.3} matcher_bytes={}",
      queries.len(), read.as_secs_f64()*1000.0, build.as_secs_f64()*1000.0,
      scan_time.as_secs_f64()*1000.0, query_time.as_secs_f64()*1000.0,
      r.matcher.as_ref().map_or(0, AhoCorasick::memory_usage));
  }
}
