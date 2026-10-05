//! Explicitly reviewed sentences and value clauses, with atomic composition.
use std::collections::HashMap;
#[derive(Default)]
pub struct OfflineProse {
  sentences: HashMap<String, String>,
  clauses: HashMap<String, String>,
  abilities: HashMap<String, String>,
  tails: HashMap<String, String>,
  emotions: HashMap<String, String>,
  reasons: HashMap<String, String>,
  appearance: HashMap<String, String>,
  simplified: bool,
}
impl OfflineProse {
  pub fn set_language(&mut self, language: &str) {
    self.simplified = language == "zh-Hans";
  }
  fn local<'a>(&self, text: &'a str) -> &'a str {
    if !self.simplified {
      return text;
    }
    match text {
      "如同他所屬文化中的其他人，他" => "如同他所属文化中的其他人，他",
      "如同她所屬文化中的其他人，她" => "如同她所属文化中的其他人，她",
      "如同牠所屬文化中的其他人，牠" => "如同它所属文化中的其他人，它",
      "他個人" => "他个人",
      "她個人" => "她个人",
      "牠個人" => "它个人",
      "具備" => "具备",
      "與" => "与",
      "牠" => "它",
      _ => text,
    }
  }
  pub fn insert(&mut self, source: &str, target: &str, kind: &str) {
    let source=match kind {
      "emotion"=>source.strip_prefix("DFL_EMOTION:").unwrap_or(source),
      "reason"=>source.strip_prefix("DFL_REASON:").unwrap_or(source),
      "appearance"=>source.strip_prefix("DFL_APPEARANCE:").unwrap_or(source),
      _=>source,
    };
    self.sentences.remove(source);
    self.clauses.remove(source);
    self.abilities.remove(source);
    self.tails.remove(source);
    self.emotions.remove(source);
    self.reasons.remove(source);
    self.appearance.remove(source);
    if source.len() > 4096 || target.len() > 4096 {
      return;
    }
    let map = match kind {
      "sentence" => &mut self.sentences,
      "value" => &mut self.clauses,
      "ability" => &mut self.abilities,
      "tail" => &mut self.tails,
      "emotion" => &mut self.emotions,
      "reason" => &mut self.reasons,
      "appearance" => &mut self.appearance,
      _ => return,
    };
    if map.len() >= 16384 {
      return;
    }
    map.insert(source.into(), target.into());
  }
  pub fn lookup(&self, source: &str) -> Option<String> {
    if source.is_empty() || source.len() > 4096 {
      return None;
    }
    let mut rest = source;
    let mut out = String::with_capacity(source.len());
    let mut count = 0;
    while !rest.is_empty() {
      let whitespace = rest.len() - rest.trim_start_matches(char::is_whitespace).len();
      if whitespace > 0 {
        out.push_str(&rest[..whitespace]);
        rest = &rest[whitespace..];
        continue;
      }
      if rest.starts_with("[P]") {
        out.push_str("[P]");
        rest = &rest[3..];
        continue;
      }
      if rest.starts_with("[C:") {
        let (tag,remaining)=Self::color(rest)?;
        out.push_str(tag);
        rest=remaining;
        continue;
      }
      count += 1;
      if count > 64 {
        return None;
      }
      // Reviewed quotes/events may themselves contain several sentences.
      if let Some(full)=self.sentences.get(rest.trim_end()) {
        out.push_str(full);out.push_str(&rest[rest.trim_end().len()..]);
        break;
      }
      // Only sentence-final punctuation is accepted. Decimal/name dots
      // won't match a reviewed sentence and therefore fail atomically.
      let mut end = rest.find(|c| c == '.' || c == '!' || c == '?').map(|n| n + 1).unwrap_or(rest.len());
      if let Some(thought)=self.thought(&rest[..end]) {
        out.push_str(&thought);rest=&rest[end..];continue;
      }
      // Vanilla changes palette between a strength and a weakness in one sentence.
      if let Some(tag)=rest[..end].find("[C:") {end=rest[..tag].trim_end().len();}
      if end==0 {return None;}
      let sentence = &rest[..end];
      if let Some(translated) = self.sentences.get(sentence) {
        out.push_str(translated);
      } else {
        out.push_str(&self.values(sentence).or_else(|| self.ability_sentence(sentence))
          .or_else(||self.appearance_sentence(sentence)).or_else(||self.conflict(sentence))?);
      }
      rest = &rest[end..];
    }
    (count > 0).then_some(out)
  }
  fn color(source:&str)->Option<(&str,&str)> {
    if !source.starts_with('[') {return Some(("",source));}
    let b=source.as_bytes();
    if b.len()<9 || &b[..3]!=b"[C:" || b[4]!=b':' || b[6]!=b':' || b[8]!=b']'
      || !(b'0'..=b'7').contains(&b[3]) || !(b'0'..=b'7').contains(&b[5]) || !(b'0'..=b'1').contains(&b[7]) {return None;}
    Some((&source[..9],&source[9..]))
  }
  fn appearance_sentence(&self, source:&str)->Option<String> {
    let sentence=source.strip_suffix('.')?;
    for (he,his,zh) in [("He","His","他"),("She","Her","她"),("It","Its","牠")] {
      let zh=self.local(zh);
      if let Some(body)=sentence.strip_prefix(&format!("{he} is ")) {
        return self.appearance.get(&format!("self:{body}")).map(|s|format!("{zh}{s}。"));
      }
      if let Some(body)=sentence.strip_prefix(&format!("{he} has ")) {
        // Vanilla joins exactly two body descriptions with the same subject.
        // Each clause must independently be in the reviewed typed inventory.
        let lower=he.to_ascii_lowercase();
        if let Some((first,second))=body.split_once(&format!(", and {lower} has ")) {
          let first=self.appearance.get(&format!("has:{first}"))?;
          let second=self.appearance.get(&format!("has:{second}"))?;
          return Some(format!("{zh}的{first}，且{second}。"));
        }
        return self.appearance.get(&format!("has:{body}")).map(|s|format!("{zh}的{s}。"));
      }
      let Some(body)=sentence.strip_prefix(&format!("{his} ")) else {continue;};
      let (subject,predicate,verb)=["is","are","has","have"].into_iter()
        .find_map(|verb|body.split_once(&format!(" {verb} ")).map(|(s,p)|(s,p,verb)))?;
      // Fixed body inventory and exact typed lookups; no scans over dictionaries
      // or guessing the meaning of an unknown subject/adjective combination.
      for (part,expected_verb) in [("nose bridge","is"),("hair","is"),("beard","is"),
        ("moustache","is"),("sideburns","are"),("eyes","are"),("ears","are"),
        ("nose","is"),("head","is"),("skin","is"),("teeth","are"),("lips","are"),("voice","is"),
        ("eyelashes","are")] {
        let feature=verb=="has" || verb=="have";
        let expected=if feature {if expected_verb=="is" {"has"}else{"have"}}else{expected_verb};
        if verb!=expected || !(subject==part || subject.strip_suffix(part).is_some_and(|s|s.ends_with(' '))) {continue;}
        let subject=self.appearance.get(&format!("subject:{subject}"))?;
        let kind=if feature {"feature"}else{"predicate"};
        let predicate=self.appearance.get(&format!("{kind}:{part}:{predicate}"))?;
        return Some(format!("{zh}的{subject}{predicate}。"));
      }
      return None;
    }
    None
  }
  fn thought(&self,source:&str)->Option<String> {
    let source=source.strip_suffix('.')?;
    let (body,subject)=[("He felt ","他"),("She felt ","她"),("It felt ","牠"),
      ("He was ","他"),("She was ","她"),("It was ","牠")].into_iter()
      .find_map(|(s,t)|source.strip_prefix(s).map(|body|(body,self.local(t))))?;
    let (emotion_color,body)=Self::color(body)?;
    for (at,_) in body.match_indices(' ').take(16) {
      let Some(emotion)=self.emotions.get(&body[..at]) else {continue;};
      let (first_color,rest)=Self::color(body[at+1..].trim_start())?;
      let rest=rest.trim_start();
      let memory=if let Some(rest)=rest.strip_prefix("remembering") {Some((rest,if self.simplified {"回忆起"}else{"回憶起"}))}
        else {rest.strip_prefix("dwelling upon").map(|rest|(rest,if self.simplified{"反复思索"}else{"反覆思索"}))};
      let (reason_color,reason,memory_color,memory_text)=if let Some((rest,verb))=memory {
        if !rest.starts_with(char::is_whitespace) && !rest.starts_with("[C:") {return None;}
        let (tag,rest)=Self::color(rest.trim_start())?;
        (tag,rest.trim_start(),first_color,verb)
      }else{(first_color,rest,"","")};
      let reason=self.reasons.get(reason)?;
      let experience=if memory_text.is_empty(){""}else if self.simplified{"的经历"}else{"的經歷"};
      return Some(format!("{subject}因{memory_color}{memory_text}{reason_color}{reason}{experience}而感到{emotion_color}{emotion}{reason_color}。"));
    }
    None
  }
  fn conflict(&self,source:&str)->Option<String> {
    // Only one reviewed tail can extend an independently known base sentence.
    for (at,_) in source.match_indices(", ").take(16) {
      if let Some(tail)=self.tails.get(&source[at+2..]) {
        if let Some(base)=self.sentences.get(&format!("{}.",&source[..at])) {
          return Some(format!("{}，{tail}",base.strip_suffix('。')?));
        }
      }
    }
    None
  }
  fn values(&self, source: &str) -> Option<String> {
    let source = source.strip_suffix('.')?;
    let (body, prefix) = [
      ("Like others in his culture, he ", "如同他所屬文化中的其他人，他"),
      ("Like others in her culture, she ", "如同她所屬文化中的其他人，她"),
      ("Like others in its culture, it ", "如同牠所屬文化中的其他人，牠"),
      ("He personally ", "他個人"),
      ("She personally ", "她個人"),
      ("It personally ", "牠個人"),
    ]
    .into_iter()
    .find_map(|(s, t)| source.strip_prefix(s).map(|rest| (rest, t)))?;
    Some(format!(
      "{}{}。",
      self.local(prefix),
      Self::list(body, &self.clauses, "，也")?
    ))
  }
  fn ability_sentence(&self, source: &str) -> Option<String> {
    let (body, punctuation) = if let Some(s) = source.strip_suffix('.') {
      (s, "。")
    } else {
      (source.strip_suffix(',')?, "，")
    };
    for (he, lower, zh) in [("He", "he", "他"), ("She", "she", "她"), ("It", "it", "牠")] {
      let zh = self.local(zh);
      let has = self.local("具備");
      let and = self.local("與");
      if let Some(body)=body.strip_prefix(&format!("{he} is ")) {
        if let Some((good,bad))=body.split_once(&format!(", but {lower} is ")) {
          return Some(format!("{zh}{}，但{zh}{}{punctuation}",Self::list(good,&self.abilities,and)?,Self::list(bad,&self.abilities,and)?));
        }
        return Some(format!("{zh}{}{punctuation}",Self::list(body,&self.abilities,and)?));
      }
      if let Some(body)=body.strip_prefix(&format!("but {lower} is ")) {
        return Some(format!("但{zh}{}{punctuation}",Self::list(body,&self.abilities,and)?));
      }
      if let Some(body) = body.strip_prefix(&format!("{he} has ")) {
        if let Some((good, bad)) = body.split_once(&format!(", but {lower} has ")) {
          return Some(format!(
            "{zh}{has}{}，但{zh}有{}{punctuation}",
            Self::list(good, &self.abilities, and)?,
            Self::list(bad, &self.abilities, and)?
          ));
        }
        return Some(format!(
          "{zh}{has}{}{punctuation}",
          Self::list(body, &self.abilities, and)?
        ));
      }
      if let Some(body) = body.strip_prefix(&format!("but {lower} has ")) {
        return Some(format!(
          "但{zh}有{}{punctuation}",
          Self::list(body, &self.abilities, and)?
        ));
      }
    }
    None
  }
  fn list(body: &str, dict: &HashMap<String, String>, conjunction: &str) -> Option<String> {
    Self::list_with(body,&|text|dict.get(text).cloned(),conjunction)
  }
  pub(crate) fn list_with(body:&str,lookup:&dyn Fn(&str)->Option<String>,conjunction:&str)->Option<String> {
    if body.len()>4096 {return None;}
    if let Some(full)=lookup(body) {return Some(full);}
    let mut boundaries:Vec<_>=body.match_indices(", ").map(|(i,_)|(i,2,"、"))
      .chain(body.match_indices(" and ").map(|(i,_)|(i,5,conjunction))).collect();
    if boundaries.len()>64 {return None;}
    boundaries.sort_by_key(|b|b.0);
    // Dynamic programming avoids both an exponential split search and dictionary scans.
    let mut suffixes:HashMap<usize,String>=HashMap::new();
    suffixes.insert(body.len(),String::new());
    let starts:Vec<_>=std::iter::once(0).chain(boundaries.iter().map(|(i,n,_)|i+n)).collect();
    for start in starts.into_iter().rev() {
      if let Some(full)=lookup(&body[start..]) {suffixes.insert(start,full);continue;}
      let mut result=None;
      for &(end,len,glue) in &boundaries {
        if end<=start {continue;}
        let Some(tail)=suffixes.get(&(end+len)) else {continue;};
        if let Some(head)=lookup(&body[start..end]) {
          let candidate=format!("{head}{glue}{tail}");
          if result.as_ref().is_some_and(|old|old!=&candidate) {return None;}
          result=Some(candidate);
        }
      }
      if let Some(result)=result {suffixes.insert(start,result);}
    }
    suffixes.remove(&0)
  }
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn compound_appearance_requires_two_reviewed_clauses_with_same_pronoun() {
    for language in ["zh-Hant", "zh-Hans"] {
      let mut p=OfflineProse::default();p.set_language(language);
      p.insert("DFL_APPEARANCE:has:very low cheekbones","顴骨很低","appearance");
      p.insert("DFL_APPEARANCE:has:a narrow chin","下巴狹窄","appearance");
      for (upper,lower,zh) in [("He","he","他"),("She","she","她"),("It","it",if language=="zh-Hans"{"它"}else{"牠"})] {
        let source=format!("{upper} has very low cheekbones, and {lower} has a narrow chin.");
        assert_eq!(p.lookup(&source),Some(format!("{zh}的顴骨很低，且下巴狹窄。")));
      }
      for source in ["He has unknown cheeks, and he has a narrow chin.",
        "He has very low cheekbones, and he has an unknown chin.",
        "He has very low cheekbones, and she has a narrow chin.",
        "He has very low cheekbones, and he has a narrow chin, and he has a narrow chin.",
        "He has very low cheekbones and he has a narrow chin.",
        "He has very low cheekbones, and he has a narrow chin. Unknown prose."] {
        assert!(p.lookup(source).is_none(),"{source}");
      }
    }
  }
  #[test]
  fn appearance_body_size_is_reviewed_and_unknown_trailing_text_is_rejected() {
    let mut p=fixture();
    p.insert("DFL_APPEARANCE:self:average in size","體型中等","appearance");
    for (pronoun,target) in [("He","他"),("She","她"),("It","牠")] {
      assert_eq!(p.lookup(&format!("{pronoun} is average in size.")).as_deref(),Some(format!("{target}體型中等。").as_str()));
    }
    for source in ["She is unknown in size.","She are average in size.","She is average in size. Unknown trailing prose."] {
      assert!(p.lookup(source).is_none(),"{source}");
    }
  }
  #[test]
  fn appearance_uses_body_specific_terms_and_rejects_unknown_fragments() {
    let mut p=fixture();
    for (source,target) in [
      ("subject:very long hair","長長的頭髮"),("predicate:hair:neatly combed","梳理得很整齊"),
      ("subject:cobalt eyes","鈷藍色眼睛"),("predicate:eyes:sunken","深陷"),
      ("has:very low cheekbones","顴骨很低"),
    ] {p.insert(&format!("DFL_APPEARANCE:{source}"),target,"appearance");}
    assert_eq!(p.lookup("Her very long hair is neatly combed.  Her cobalt eyes are sunken.  She has very low cheekbones.").as_deref(),
      Some("她的長長的頭髮梳理得很整齊。  她的鈷藍色眼睛深陷。  她的顴骨很低。"));
    for source in ["Her very long hair are neatly combed.","Her cobalt eyes is sunken.",
      "Her mysterious hair is neatly combed.","Her cobalt eyes are neatly combed.",
      "Her cobalt eyes are sunken. Unknown trailing prose.","A player's hair is neatly combed."] {
      assert!(p.lookup(source).is_none(),"{source}");
    }
  }
  #[test]
  fn appearance_ear_features_are_distinct_from_predicate_adjectives() {
    let mut p=fixture();
    p.insert("DFL_APPEARANCE:subject:somewhat splayed out ears","略向外張開的耳朵","appearance");
    p.insert("DFL_APPEARANCE:feature:ears:great swinging lobes","有又大又晃動的耳垂","appearance");
    p.insert("DFL_APPEARANCE:subject:eyelashes","睫毛","appearance");
    p.insert("DFL_APPEARANCE:predicate:eyelashes:extremely long","極長","appearance");
    assert_eq!(p.lookup("Her somewhat splayed out ears have great swinging lobes. Her eyelashes are extremely long.").as_deref(),
      Some("她的略向外張開的耳朵有又大又晃動的耳垂。 她的睫毛極長。"));
    for source in ["Her somewhat splayed out ears are great swinging lobes.",
      "Her somewhat splayed out ears has great swinging lobes.","Her eyelashes have extremely long."] {
      assert!(p.lookup(source).is_none(),"{source}");
    }
  }
  #[test]
  fn thoughts_compose_reviewed_emotions_reasons_and_keep_semantic_colors() {
    let mut p=fixture();
    p.insert("fondness","親近","emotion");
    p.insert("grim satisfaction","冷酷的滿足","emotion");
    p.insert("talking with a friend","與朋友交談","reason");
    p.insert("after a bath","洗澡","reason");
    assert_eq!(p.lookup("He felt fondness talking with a friend.").as_deref(),Some("他因與朋友交談而感到親近。"));
    assert_eq!(p.lookup("[C:7:0:0]He felt [C:3:0:1]fondness [C:7:0:0]talking with a friend.").as_deref(),Some("[C:7:0:0]他因[C:7:0:0]與朋友交談而感到[C:3:0:1]親近[C:7:0:0]。"));
    assert_eq!(p.lookup("She felt grim satisfaction remembering after a bath.").as_deref(),Some("她因回憶起洗澡的經歷而感到冷酷的滿足。"));
    assert_eq!(p.lookup("[C:7:0:0]She felt [C:3:0:1]fondness [C:5:0:0]remembering[C:7:0:0] after a bath.").as_deref(),Some("[C:7:0:0]她因[C:5:0:0]回憶起[C:7:0:0]洗澡的經歷而感到[C:3:0:1]親近[C:7:0:0]。"));
    assert!(p.lookup("She felt fondness rememberingafter a bath.").is_none());
    for source in ["He felt unknown talking with a friend.","He felt fondness meeting Unknown.","He felt [C:9:0:0]fondness [C:7:0:0]after a bath.","He felt fondness talking with a friend. An unknown sentence."] {assert!(p.lookup(source).is_none(),"{source}");}
  }
  #[test]
  fn interior_palette_and_bounded_ambiguous_lists() {
    let mut p=fixture();p.insert("a good memory","良好的記憶力","ability");p.insert("poor spatial senses","不佳的空間感","ability");
    assert_eq!(p.lookup("[C:2:0:0]She has a good memory, [C:4:0:0]but she has poor spatial senses.").as_deref(),Some("[C:2:0:0]她具備良好的記憶力， [C:4:0:0]但她有不佳的空間感。"));
    let terms=HashMap::from([("a","甲"),("a and b","甲乙"),("b and c","乙丙"),("c","丙")]);
    assert!(OfflineProse::list_with("a and b and c",&|s|terms.get(s).map(|s|s.to_string()),"與").is_none());
    assert!(OfflineProse::list_with(&"x, ".repeat(66),&|_|None,"與").is_none());
  }
  #[test]
  fn personality_conflicts_values_with_commas_and_physical_abilities() {
    let mut p=fixture();
    p.insert("though he is conflicted by this since he values harmony.","但他重視和諧，因此對此感到矛盾。","tail");
    assert_eq!(p.lookup("He is stubborn, though he is conflicted by this since he values harmony.").as_deref(),Some("他很固執，但他重視和諧，因此對此感到矛盾。"));
    assert!(p.lookup("He is stubborn, though he has unknown motives.").is_none());
    p.insert("values decorum, dignity and proper behavior","重視禮儀、尊嚴與合宜舉止","value");
    assert_eq!(p.lookup("He personally values decorum, dignity and proper behavior and values leisure time.").as_deref(),Some("他個人重視禮儀、尊嚴與合宜舉止，也重視休閒時間。"));
    p.insert("strong","強壯","ability");p.insert("quick to tire","容易疲勞","ability");
    assert_eq!(p.lookup("She is strong, but she is quick to tire.").as_deref(),Some("她強壯，但她容易疲勞。"));
  }
  fn fixture() -> OfflineProse {
    let mut p = OfflineProse::default();
    p.insert("He is stubborn.", "他很固執。", "sentence");
    p.insert("He dreams of raising a family.", "他夢想建立家庭。", "sentence");
    p.insert("values family greatly", "非常重視家庭", "value");
    p.insert("respects fair-dealing and fair-play", "尊重公平交易與公平競爭", "value");
    p.insert("values leisure time", "重視休閒時間", "value");
    p
  }
  #[test]
  fn first_lookup_composes_sentences_and_retains_palette_and_spacing() {
    let p = fixture();
    assert_eq!(
      p.lookup("[P][C:7:0:0]He is stubborn.  [C:6:0:1]He dreams of raising a family.  ").as_deref(),
      Some("[P][C:7:0:0]他很固執。  [C:6:0:1]他夢想建立家庭。  ")
    );
    assert!(p.lookup("He is stubborn.  An unknown sentence.").is_none());
    assert!(p.lookup("He is stubborn. [C:evil]He is stubborn.").is_none());
    assert!(p.lookup(&"He is stubborn. ".repeat(500)).is_none());
  }
  #[test]
  fn values_parse_internal_and_without_splitting_a_clause() {
    let p = fixture();
    assert_eq!(p.lookup("Like others in his culture, he values family greatly, respects fair-dealing and fair-play and values leisure time.").as_deref(),
            Some("如同他所屬文化中的其他人，他非常重視家庭、尊重公平交易與公平競爭，也重視休閒時間。"));
    assert_eq!(
      p.lookup("She personally values leisure time and values family greatly.").as_deref(),
      Some("她個人重視休閒時間，也非常重視家庭。")
    );
    assert!(p.lookup("He personally values leisure time and invents unknown values.").is_none());
  }
  #[test]
  fn abilities_compose_strengths_and_weaknesses_without_guessing_unknown_traits() {
    let mut p = fixture();
    for (s, t) in [
      ("a good memory", "良好的記憶力"),
      ("willpower", "意志力"),
      ("poor spatial senses", "不佳的空間感"),
    ] {
      p.insert(s, t, "ability");
    }
    assert_eq!(
      p.lookup("She has a good memory and willpower, but she has poor spatial senses.  ").as_deref(),
      Some("她具備良好的記憶力與意志力，但她有不佳的空間感。  ")
    );
    assert_eq!(
      p.lookup("He has a good memory,").as_deref(),
      Some("他具備良好的記憶力，")
    );
    assert!(p.lookup("He has unknown powers.").is_none());
  }
  #[test]
  fn language_switch_changes_grammar_glue_and_extended_unicode_is_preserved() {
    let mut p = OfflineProse::default();
    p.set_language("zh-Hans");
    p.insert("values skill", "重视𠀀技艺", "value");
    p.insert("a good memory", "良好的记忆力", "ability");
    p.insert("willpower", "意志力", "ability");
    assert_eq!(
      p.lookup("Like others in his culture, he values skill.").as_deref(),
      Some("如同他所属文化中的其他人，他重视𠀀技艺。")
    );
    assert_eq!(
      p.lookup("She has a good memory and willpower.").as_deref(),
      Some("她具备良好的记忆力与意志力。")
    );
    assert!(p.lookup("He personally values skill.𠀀").is_none());
  }
}
