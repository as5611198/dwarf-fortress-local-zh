//! Save-independent preference grammar. Only typed name placeholders survive.
use crate::offline_prose::OfflineProse;

fn slot(s:&str)->bool {
  s.strip_prefix("{PREF_NAME_").and_then(|s|s.strip_suffix('}'))
    .is_some_and(|s|s.parse::<u8>().is_ok_and(|n|(1..=16).contains(&n)) && !s.starts_with('0'))
}
pub fn lookup(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  if source.len()>4096 || !(source.starts_with("{DWARF_NAME} likes ") ||
    ["When possible, ","He absolutely detests ","She absolutely detests ","It absolutely detests "].iter().any(|s|source.starts_with(s))) {return None;}
  let word=|s|match (simplified,s) {
    (true,"喜歡")=>"喜欢",(true,"條件允許時，")=>"条件允许时，",(true,"偏好食用")=>"偏好食用",
    (true,"極其厭惡")=>"极其厌恶",(true,"的聲音")=>"的声音",(true,"的樣貌")=>"的样貌",(true,"與")=>"与",_=>s};
  let item=|s:&str|->Option<String>{
    if slot(s) {return Some(s.into());}
    for (prefix,suffix) in [("the words of ","的文字"),("the sound of ","的聲音"),("the sight of ","的樣貌")] {
      if let Some(name)=s.strip_prefix(prefix) {return slot(name).then(||format!("{name}{}",word(suffix)));}
    }
    if let Some(s)=s.strip_prefix("the color ") {return term(s);}
    if let Some((animal,reason))=s.split_once(" for their ").or_else(||s.split_once(" for its ")) {
      let reason=term(&format!("DFL_PREF_REASON:{reason}")).or_else(||term(reason))?;
      let animal=term(&format!("DFL_PREF_SUBJECT:{animal}")).or_else(||term(animal))?;
      return Some(format!("{animal}（{reason}）"));
    }
    term(&format!("DFL_PREF_ITEM:{s}")).or_else(||term(s))
  };
  let mut output=String::new();let mut rest=source;let mut count=0;
  while !rest.is_empty() {
    let n=rest.len()-rest.trim_start_matches(char::is_whitespace).len();
    output.push_str(&rest[..n]);rest=&rest[n..];if rest.is_empty(){break;}
    count+=1;if count>8{return None;}
    let end=rest.find('.')?;
    let sentence=&rest[..end];
    let (body,prefix)=if let Some(body)=sentence.strip_prefix("{DWARF_NAME} likes ") {
      (body,format!("{{DWARF_NAME}}{}",word("喜歡")))
    } else {
      let mut found=None;
      for (upper,lower,zh) in [("He","he","他"),("She","she","她"),("It","it",if simplified {"它"}else{"牠"})] {
        if let Some(body)=sentence.strip_prefix(&format!("When possible, {lower} prefers to consume ")) {
          found=Some((body,format!("{}{zh}{}",word("條件允許時，"),word("偏好食用"))));break;
        }
        if let Some(body)=sentence.strip_prefix(&format!("{upper} absolutely detests ")) {
          found=Some((body,format!("{zh}{}",word("極其厭惡"))));break;
        }
      }
      found?
    };
    output.push_str(&prefix);output.push_str(&OfflineProse::list_with(body,&item,word("與"))?);output.push('。');
    rest=&rest[end+1..];
  }
  (count>0).then_some(output)
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn material_preferences_do_not_reuse_color_gold() {
    let terms=|s:&str|match s {
      "gold"=>Some("金色".into()),
      "DFL_PREF_ITEM:gold"=>Some("金".into()),
      _=>None,
    };
    assert_eq!(lookup("{DWARF_NAME} likes gold.",&terms,false).as_deref(),Some("{DWARF_NAME}喜歡金。"));
    assert_eq!(lookup("{DWARF_NAME} likes the color gold.",&terms,false).as_deref(),Some("{DWARF_NAME}喜歡金色。"));
    assert!(lookup("{DWARF_NAME} likes unknown metal.",&terms,false).is_none());
  }
  #[test]
  fn poetry_words_use_only_a_verified_name_slot() {
    assert_eq!(lookup("{DWARF_NAME} likes the words of {PREF_NAME_1}.",&|_|None,false).as_deref(),
      Some("{DWARF_NAME}喜歡{PREF_NAME_1}的文字。"));
    assert_eq!(lookup("{DWARF_NAME} likes the words of {PREF_NAME_1}.",&|_|None,true).as_deref(),
      Some("{DWARF_NAME}喜欢{PREF_NAME_1}的文字。"));
    assert!(lookup("{DWARF_NAME} likes the words of arbitrary player name.",&|_|None,false).is_none());
    assert!(lookup("{DWARF_NAME} likes the words of {PREF_NAME_17}.",&|_|None,false).is_none());
  }
  #[test]
  fn preference_reasons_use_context_before_generic_ui_terms() {
    let terms=|s:&str|match s {
      "leopards"=>Some("豹".into()),
      "spots"=>Some("地點".into()),
      "DFL_PREF_REASON:spots"=>Some("斑點".into()),
      "ash"=>Some("灰燼".into()),
      "DFL_PREF_SUBJECT:ash"=>Some("白蠟樹".into()),
      "DFL_PREF_REASON:autumn coloration"=>Some("秋季的色彩".into()),
      _=>None,
    };
    assert_eq!(lookup("{DWARF_NAME} likes leopards for their spots.",&terms,false).as_deref(),
      Some("{DWARF_NAME}喜歡豹（斑點）。"));
    assert_eq!(terms("spots").as_deref(),Some("地點"));
    assert_eq!(lookup("{DWARF_NAME} likes ash for their autumn coloration.",&terms,false).as_deref(),
      Some("{DWARF_NAME}喜歡白蠟樹（秋季的色彩）。"));
    assert_eq!(lookup("{DWARF_NAME} likes ash.",&terms,false).as_deref(),Some("{DWARF_NAME}喜歡灰燼。"));
    assert!(lookup("{DWARF_NAME} likes leopards for their unknown feature.",&terms,false).is_none());
  }
  fn term(s:&str)->Option<String> {
    Some(match s {"silver"=>"銀","water buffalos"=>"水牛","water wallowing"=>"在水中打滾","lychee wine"=>"荔枝酒","fire snakes"=>"火蛇","blue-gray"=>"藍灰色",_=>return None}.into())
  }
  #[test]
  fn complete_preferences_preserve_only_typed_name_slots_and_fail_atomically() {
    let source="{DWARF_NAME} likes silver, water buffalos for their water wallowing, the color blue-gray and the sound of {PREF_NAME_1}.  When possible, she prefers to consume lychee wine.  She absolutely detests fire snakes.";
    assert_eq!(lookup(source,&term,false).as_deref(),Some("{DWARF_NAME}喜歡銀、水牛（在水中打滾）、藍灰色與{PREF_NAME_1}的聲音。  條件允許時，她偏好食用荔枝酒。  她極其厭惡火蛇。"));
    for s in ["{DWARF_NAME} likes silver and unknown ore.","{DWARF_NAME} likes the sound of arbitrary player name.","{DWARF_NAME} likes {PREF_NAME_999}.","{DWARF_NAME} likes silver. Unknown trailing prose."] {assert!(lookup(s,&term,false).is_none(),"{s}");}
    assert!(lookup(&source.repeat(50),&term,false).is_none());
  }
}
