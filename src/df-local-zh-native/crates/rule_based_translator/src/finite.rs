//! Bounded, root-reachable finite grammar index. No grammar work at lookup time.
use crate::{RuleSets, Token};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;

const MAX_TEXT: usize = 4096;
const MAX_RULE: usize = 16384;
const MAX_SET: usize = 65536;
const MAX_WORK: usize = 200_000;
const MAX_STORED_BYTES: usize = 24 * 1024 * 1024;
type Pairs = Vec<(String, String)>;

#[derive(Default)]
pub struct FiniteIndex {
  entries: HashMap<String, String>,
}
impl FiniteIndex {
  pub fn compile(rules: &RuleSets) -> Self {
    let mut index = Self::default();
    let mut ambiguous = HashSet::new();
    let mut stored = 0;
    let Some(root) = rules.get("::") else {
      return index;
    };
    // Independent category budgets avoid a large earlier category consuming
    // the memory/work reserved for subsequent common UI categories.
    for root_rule in 0..root.len().min(128) {
      let mut compiler = Compiler {
        rules,
        memo: HashMap::new(),
        path: HashSet::new(),
        work: 0,
        stored_bytes: 0,
        root_rule: Some(root_rule),
      };
      let pairs = compiler.expand("::");
      for (source, target) in pairs.iter() {
        if source.is_empty() || source == target {
          continue;
        }
        let key = source.to_ascii_lowercase();
        if ambiguous.contains(&key) {
          continue;
        }
        if index.entries.get(&key).is_some_and(|old| old != target) {
          index.entries.remove(&key);
          ambiguous.insert(key);
        } else if !index.entries.contains_key(&key)
          && index.entries.len() < MAX_SET
          && stored + key.len() + target.len() <= MAX_STORED_BYTES
        {
          stored += key.len() + target.len();
          index.entries.insert(key, target.clone());
        }
      }
    }
    index
  }
  pub fn lookup(&self, text: &str) -> Option<&str> {
    if text.len() > MAX_TEXT {
      return None;
    }
    self.entries.get(&text.to_ascii_lowercase()).map(String::as_str)
  }
  pub fn len(&self) -> usize {
    self.entries.len()
  }
}

struct Compiler<'a> {
  rules: &'a RuleSets,
  memo: HashMap<String, Arc<Pairs>>,
  path: HashSet<String>,
  work: usize,
  stored_bytes: usize,
  root_rule: Option<usize>,
}
impl Compiler<'_> {
  fn expand(&mut self, id: &str) -> Arc<Pairs> {
    if id.starts_with('%') || self.path.contains(id) || self.path.len() >= 24 || self.work >= MAX_WORK {
      return Arc::new(vec![]);
    }
    if let Some(pairs) = self.memo.get(id) {
      return pairs.clone();
    }
    self.path.insert(id.into());
    let mut out = vec![];
    if let Some(rules) = self.rules.get(id) {
      for (rule_id, (source, target)) in rules.iter().enumerate() {
        if id == "::" && self.root_rule.is_some_and(|i| i != rule_id) {
          continue;
        }
        // One large category (creatures/materials) must not starve
        // later menu, profession, health and unit categories.
        if id == "::" {
          self.work = 0;
        }
        if self.work >= MAX_WORK {
          break;
        }
        self.work += 1;
        // Captures with the same identifier have last-match semantics in
        // the recursive engine. Skip these rather than change meaning.
        let refs: Vec<_> = source
          .iter()
          .filter_map(|t| {
            if let Token::Reference(r) = t {
              Some(r.as_str())
            } else {
              None
            }
          })
          .collect();
        if refs.iter().collect::<HashSet<_>>().len() != refs.len() {
          continue;
        }
        let mut candidates = vec![(String::new(), HashMap::<&str, String>::new())];
        for token in source {
          match token {
            Token::Literal(l) => {
              for (s, _) in &mut candidates {
                s.push_str(l);
              }
            }
            Token::Reference(r) => {
              let mut choices = self.expand(r);
              let limit = if source.len() == 1 { MAX_SET } else { MAX_RULE };
              if candidates.len().saturating_mul(choices.len()) > limit {
                // Preserve the grammar's explicit empty optional
                // prefix; do not enumerate every species/material
                // permutation just to translate a bare noun.
                if candidates.iter().any(|(s, _)| s.is_empty()) {
                  candidates.retain(|(s, _)| s.is_empty());
                } else if choices.iter().any(|(s, _)| s.is_empty()) {
                  choices = Arc::new(choices.iter().filter(|(s, _)| s.is_empty()).cloned().collect());
                }
              }
              if choices.is_empty() || candidates.len().saturating_mul(choices.len()) > limit {
                candidates.clear();
                break;
              }
              let mut next = vec![];
              for (s, values) in &candidates {
                for (literal, translated) in choices.iter() {
                  self.work += 1;
                  if self.work >= MAX_WORK {
                    break;
                  }
                  if s.len() + literal.len() > MAX_TEXT {
                    continue;
                  }
                  let mut v = values.clone();
                  v.insert(r, translated.clone());
                  next.push((format!("{s}{literal}"), v));
                }
                if self.work >= MAX_WORK {
                  break;
                }
              }
              // Never publish a truncated Cartesian product.
              if self.work >= MAX_WORK {
                next.clear();
              }
              candidates = next;
            }
          }
        }
        let mut batch = vec![];
        for (s, values) in candidates {
          if s.len() > MAX_TEXT {
            continue;
          }
          let mut t = String::new();
          let mut valid = true;
          for token in target {
            match token {
              Token::Literal(l) => t.push_str(l),
              Token::Reference(r) => {
                if let Some(v) = values.get(r.as_str()) {
                  t.push_str(v);
                } else {
                  valid = false;
                  break;
                }
              }
            }
            if t.len() > MAX_TEXT {
              valid = false;
              break;
            }
          }
          if valid {
            batch.push((s, t));
          }
        }
        let bytes = batch.iter().map(|(s, t)| s.len() + t.len()).sum::<usize>();
        if out.len() + batch.len() <= MAX_SET && self.stored_bytes.saturating_add(bytes) <= MAX_STORED_BYTES {
          self.stored_bytes += bytes;
          out.extend(batch);
        }
      }
    }
    self.path.remove(id);
    let out = Arc::new(out);
    self.memo.insert(id.into(), out.clone());
    out
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use indexmap::IndexMap;
  fn l(s: &str) -> Token {
    Token::Literal(s.into())
  }
  fn r(s: &str) -> Token {
    Token::Reference(s.into())
  }
  #[test]
  #[ignore = "requires DF_LOCAL_RULESETS"]
  fn packaged_index_diagnostics() {
    let mut t = crate::Translator::default();
    t.load_from_dir(std::env::var("DF_LOCAL_RULESETS").unwrap()).unwrap();
    for name in [
      "::",
      "::materials",
      "::materials::state",
      "::materials::state::shared::main",
      "::professions",
      "::tiles",
      "::plain_needs",
    ] {
      let mut c = Compiler {
        rules: t.dump(),
        memo: HashMap::new(),
        path: HashSet::new(),
        work: 0,
        stored_bytes: 0,
        root_rule: None,
      };
      let out = c.expand(name);
      eprintln!("{name}: {} rows {} work {} bytes", out.len(), c.work, c.stored_bytes);
      for s in ["iron", "quartzite", "Miner", "Dense white mountain heather"] {
        eprintln!(" {s}: {:?}", out.iter().find(|(a, _)| a == s));
      }
    }
  }
  #[test]
  fn finite_root_composition_reorders_captures_without_promoting_fragments() {
    let rules = IndexMap::from([
      (
        "::".into(),
        IndexMap::from([(
          vec![r("::who"), l(" is "), r("::job")],
          vec![r("::job"), l("："), r("::who")],
        )]),
      ),
      (
        "::who".into(),
        IndexMap::from([(vec![l("He")], vec![l("他")]), (vec![l("She")], vec![l("她")])]),
      ),
      ("::job".into(), IndexMap::from([(vec![l("a miner")], vec![l("礦工")])])),
    ]);
    let index = FiniteIndex::compile(&rules);
    assert_eq!(index.lookup("She is a miner"), Some("礦工：她"));
    assert_eq!(index.lookup("HE IS A MINER"), Some("礦工：他"));
    assert_eq!(index.lookup("a miner"), None);
    assert_eq!(index.lookup("They are miners"), None);
  }
  #[test]
  fn products_are_bounded_and_a_later_category_still_compiles() {
    let many = IndexMap::from_iter((0..200).map(|i| (vec![l(&format!("choice-{i}"))], vec![l(&format!("選項{i}"))])));
    let rules = IndexMap::from([
      (
        "::".into(),
        IndexMap::from([
          (vec![r("::a"), r("::b")], vec![r("::a"), r("::b")]),
          (vec![l("Safe")], vec![l("安全")]),
        ]),
      ),
      ("::a".into(), many.clone()),
      ("::b".into(), many),
    ]);
    let index = FiniteIndex::compile(&rules);
    assert_eq!(index.len(), 1);
    assert_eq!(index.lookup("Safe"), Some("安全"));
    assert!(index.lookup("choice-1choice-2").is_none());
    assert!(index.lookup(&"𠀀".repeat(1025)).is_none());
  }
  #[test]
  fn ambiguous_recursive_and_dynamic_branches_are_not_guessed() {
    let rules = IndexMap::from([
      (
        "::".into(),
        IndexMap::from([
          (vec![r("::a")], vec![r("::a")]),
          (vec![r("::b")], vec![r("::b")]),
          (vec![r("::")], vec![r("::")]),
          (vec![r("%any::")], vec![l("錯誤")]),
          (vec![l("Safe")], vec![l("安全")]),
        ]),
      ),
      ("::a".into(), IndexMap::from([(vec![l("bank")], vec![l("銀行")])])),
      ("::b".into(), IndexMap::from([(vec![l("Bank")], vec![l("河岸")])])),
    ]);
    let index = FiniteIndex::compile(&rules);
    assert_eq!(index.lookup("Safe"), Some("安全"));
    assert_eq!(index.lookup("bank"), None);
    assert_eq!(index.lookup("anything"), None);
  }
}
