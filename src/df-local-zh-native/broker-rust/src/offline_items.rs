//! Atomic, bounded item description composition shared by both runtimes.
pub fn lookup(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  if source.len()>4096 || !valid_slots(source) {return None;}
  let local=|hant,hans|if simplified{hans}else{hant};
  let known=|s:&str|->Option<String>{
    if s.is_empty() || s.contains(['[',']','{','}','.']) {return None;}
    let t=term(s)?;
    if t.is_empty() || t.len()>4096 || t.contains(['[',']','{','}']) || t.bytes().any(|c|c.is_ascii_alphabetic()) {return None;}
    Some(t)
  };
  // The raw artwork vocabulary calls geometric diamonds "菱形". Only
  // material positions carry the gemstone meaning; never override subjects
  // or the shared dictionary, since an image can depict diamond shapes.
  let material=|s:&str|->Option<String>{
    match s {"diamond"|"diamonds"=>Some(local("鑽石","钻石").into()),_=>known(s)}
  };
  if let Some(body)=source.strip_prefix("Burden: ") {
    let (carried,limit)=body.split_once('/')?;
    let carried=carried.strip_suffix('Γ')?;let limit=limit.strip_suffix('Γ')?;
    if !bounded_number(carried,true) || !bounded_number(limit,false) {return None;}
    return Some(format!("{}：{body}",local("負重","负重")));
  }
  if let Some(container)=source.strip_prefix("In ") {
    if !["backpack","bag","flask","waterskin","quiver","chest","coffer","box","barrel","bin","basket"].iter().any(|noun|container==*noun || container.ends_with(&format!(" {noun}"))) {return None;}
    return Some(format!("在{}{}",known(container)?,local("內","内")));
  }
  for (prefix,before,after) in [("Owner: ",local("擁有者：","拥有者："),""),("With ","由",local("攜帶","携带"))] {
    if let Some(role)=source.strip_prefix(prefix) {
      // Unidentified personal names must stay on the native identity path.
      // Only these established combat profession labels are safe nouns here.
      if !matches!(role,"Swordsdwarf"|"Swordman"|"Swordsman"|"Axedwarf"|"Axeman"|"Macedwarf"|"Maceman"|"Hammerdwarf"|"Hammerman"|"Speardwarf"|"Spearman"|"Marksdwarf"|"Crossbowman"|"Lasher"|"Wrestler"|"Recruit") {return None;}
      return Some(format!("{before}{}{after}",known(role)?));
    }
  }
  if let Some((token,item))=source.split_once(" was a legendary ") {
    let index=token.strip_prefix("{{DFL")?.strip_suffix("}}")?;
    if !index.parse::<u8>().is_ok_and(|n|n<64 && n.to_string()==index) {return None;}
    return Some(format!("{token}{}{}。",local("曾是傳奇的","曾是传奇的"),known(item.strip_suffix('.')?)?));
  }
  if !(source.starts_with("This is a ") || source.starts_with("This is an ") || source.starts_with("On the item is an image of ")) {return None;}
  let mut rest=source;let mut out=String::new();let mut count=0;let mut has_image=false;
  while !rest.is_empty() {
    let trimmed=rest.trim_start();let n=rest.len()-trimmed.len();out.push_str(&rest[..n]);rest=trimmed;
    if rest.is_empty(){break;}
    count+=1;if count>32{return None;}
    let end=rest.find('.')?;let sentence=&rest[..end];
    let translated=if let Some(body)=sentence.strip_prefix("On the item is an image of ") {
      let (subject,substance)=body.rsplit_once(" in ")?;
      has_image=true;
      format!("物品上有以{}{}{}{}。",material(substance)?,local("製成的","制成的"),image_subject(subject,&known,simplified)?,local("圖像","图像"))
    }else if count==1 {
      let item=sentence.strip_prefix("This is a ").or_else(||sentence.strip_prefix("This is an "))?;
      if let Some(stack)=item.strip_prefix("stack of ") {
        let (number,item)=stack.split_once(' ')?;
        if !bounded_number(number,false) {return None;}
        format!("{}{}，{}{number}。",local("這是一疊","这是一叠"),known(item)?,local("數量為","数量为"))
      }else{format!("{}{}。",local("這是","这是"),known(item)?)}
    }else if let Some(substance)=sentence.strip_prefix("It is made from ") {
      let name=material(substance).or_else(||{
        let plant=substance.strip_suffix(" cloth")?;
        Some(format!("{}布",known(plant)?))
      })?;
      format!("它由{name}{}。",local("製成","制成"))
    }else if let Some(quality)=sentence.strip_prefix("All craftsdwarfship is ").or_else(||sentence.strip_prefix("All craftsmanship is ")) {
      let quality=match quality {
        "of the highest quality"=>local("最高品質","最高品质"),"of superior quality"=>local("上等品質","上等品质"),
        "of exceptional quality"=>local("卓越品質","卓越品质"),"well-crafted"=>local("良好水準","良好水准"), "finely-crafted"=>local("精良水準","精良水准"),_=>return None};
      format!("{}{quality}。",local("所有工藝均為","所有工艺均为"))
    }else if let Some(size)=sentence.strip_prefix("It is sized for ") {
      format!("{}{}。",local("它的尺寸適合","它的尺寸适合"),known(size)?)
    }else if let Some((body,prefix,suffix))=[
      ("It is encrusted with ",local("它鑲嵌著","它镶嵌着"),""),
      ("It is studded with ",local("它綴有","它缀有"),local("飾釘","饰钉")),
      ("It is decorated with ",local("它裝飾著","它装饰着"),""),
      ("It is spattered with ",local("它濺有","它溅有"),""),
      ("It is encircled with bands of ",local("它環繞著","它环绕着"),local("飾帶","饰带")),
      ("This object is adorned with hanging rings of ",local("此物品飾有","此物品饰有"),local("吊環","吊环")),
      ("This object menaces with spikes of ",local("此物品帶有駭人的","此物品带有骇人的"),"尖刺"),
    ].into_iter().find_map(|(p,a,b)|sentence.strip_prefix(p).map(|s|(s,a,b))) {
      let list=crate::offline_prose::OfflineProse::list_with(body,&material,local("與","与"))?;
      format!("{prefix}{list}{suffix}。")
    }else if has_image {
      artwork_detail(sentence,&known,simplified)?
    }else{return None;};
    out.push_str(&translated);rest=&rest[end+1..];
  }
  (count>0 && out.len()<=16384).then_some(out)
}

fn bounded_number(s:&str,zero:bool)->bool {
  !s.is_empty() && s.len()<=10 && s.bytes().all(|b|b.is_ascii_digit()) && (zero || s.bytes().any(|b|b!=b'0'))
}

fn native_slot(source:&str)->Option<u8> {
  let index=source.strip_prefix("{{DFL")?.strip_suffix("}}")?;
  let n=index.parse::<u8>().ok()?;
  (n<64 && n.to_string()==index).then_some(n)
}

// Each native slot is an occurrence, even when two occurrences refer to the
// same person. Keep the same eight-occurrence bound as the history composer.
fn valid_slots(mut source:&str)->bool {
  if source.contains(['[',']']) {return false;}
  let mut seen=0u64;let mut count=0;
  while let Some(start)=source.find('{') {
    if source[..start].contains('}') {return false;}
    source=&source[start..];
    let Some(end)=source.find("}}") else {return false;};
    let Some(index)=native_slot(&source[..end+2]) else {return false;};
    let bit=1u64<<index;
    if seen&bit!=0 || count>=8 {return false;}
    seen|=bit;count+=1;source=&source[end+2..];
  }
  !source.contains('}')
}

fn image_subject(source:&str,known:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  crate::offline_prose::OfflineProse::list_with(source,&|s| {
    if native_slot(s).is_some() {return Some(s.into());}
    // English articles do not need a Chinese classifier; the noun dictionary
    // remains the authority. Never keep an unknown proper name as raw text.
    let noun=s.strip_prefix("a ").or_else(||s.strip_prefix("an ")).or_else(||s.strip_prefix("the ")).unwrap_or(s);
    known(noun)
  },if simplified{"与"}else{"與"})
}

fn artwork_detail(source:&str,known:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  let local=|hant,hans|if simplified{hans}else{hant};
  if let Some((subject,others))=source.split_once(" is surrounded by ") {
    return Some(format!("{}被{}{}。",image_subject(subject,known,simplified)?,image_subject(others,known,simplified)?,local("包圍著","包围着")));
  }
  let body=source.strip_prefix("The artwork relates to the ")?;
  let (event,body)=body.split_once(" of ")?;
  let event=match event {"appointment"=>local("獲任命","获任命"),"election"=>local("當選","当选"),_=>return None};
  let (person,body)=body.split_once(" to the position of ")?;
  native_slot(person)?;
  let (role,body)=body.split_once(" of ")?;
  if !matches!(role,"champion"|"mayor"|"king"|"queen"|"priest"|"dean") {return None;}
  let (entity,year)=body.split_once(" in ")?;
  native_slot(entity)?;
  if year.is_empty() || year.len()>7 || !year.bytes().all(|b|b.is_ascii_digit()) {return None;}
  Some(format!("{}{person}{}{year}年{event}{}{entity}{}的事件。",local("這件藝術品描繪了","这件艺术品描绘了"),local("於","于"),local("為","为"),known(role)?))
}

#[cfg(test)]
mod tests {
  use super::*;
  fn inventory_term(s:&str)->Option<String> {match s {
    "prepared fly brain"=>Some("預備的蒼蠅腦".into()),
    "leopard seal leather backpack"=>Some("豹海豹皮革背包".into()),
    "Swordsdwarf"=>Some("劍矮人".into()),_=>None,
  }}
  #[test]
  fn item_stack_preserves_count_spacing_and_unknown_fallback() {
    assert_eq!(lookup("This is a stack of 5 prepared fly brain.  ",&inventory_term,false).as_deref(),Some("這是一疊預備的蒼蠅腦，數量為5。  "));
    assert_eq!(lookup("This is a stack of 20 prepared fly brain.",&inventory_term,true).as_deref(),Some("这是一叠預備的蒼蠅腦，数量为20。"));
    for s in ["This is a stack of 0 prepared fly brain.","This is a stack of -1 prepared fly brain.","This is a stack of 999999999999 prepared fly brain.","This is a stack of 5 unknown food.","This is a stack of 5 prepared fly brain. Unknown trailing prose."] {
      assert!(lookup(s,&inventory_term,false).is_none(),"{s}");
    }
  }
  #[test]
  fn inventory_metadata_keeps_weight_glyph_and_typed_subjects() {
    for (source,want) in [("Burden: 58Γ/83Γ","負重：58Γ/83Γ"),("Burden: 0Γ/100Γ","負重：0Γ/100Γ"),
      ("Owner: Swordsdwarf","擁有者：劍矮人"),("With Swordsdwarf","由劍矮人攜帶"),
      ("In leopard seal leather backpack","在豹海豹皮革背包內")] {
      assert_eq!(lookup(source,&inventory_term,false).as_deref(),Some(want),"{source}");
    }
    assert_eq!(lookup("Burden: 58Γ/83Γ",&inventory_term,true).as_deref(),Some("负重：58Γ/83Γ"));
    for source in ["Burden: 58Γ/83Γ trailing","Burden: -58Γ/83Γ","Burden: 58/83","Burden: 58Γ/0Γ",
      "Burden: 999999999999Γ/83Γ","In an unknown bag","Owner: Urist","With an unknown person"] {
      assert!(lookup(source,&inventory_term,false).is_none(),"{source}");
    }
  }
  #[test]
  fn diamond_material_does_not_reuse_artwork_shape_translation() {
    for simplified in [false,true] {
      let terms=|s:&str|match s {
        "iron battle axe"=>Some(if simplified{"铁战斧"}else{"鐵戰斧"}.into()),
        "silver"=>Some(if simplified{"银"}else{"銀"}.into()),
        "diamond"|"diamonds"=>Some("菱形".into()),_=>None,
      };
      let want=if simplified{"这是铁战斧。 它镶嵌着钻石。"}else{"這是鐵戰斧。 它鑲嵌著鑽石。"};
      for gem in ["diamond","diamonds"] {
        assert_eq!(lookup(&format!("This is an iron battle axe. It is encrusted with {gem}."),&terms,simplified).as_deref(),Some(want));
      }
      // The same English noun has two different meanings in this sentence.
      assert_eq!(lookup("On the item is an image of diamonds in diamond.",&terms,simplified).as_deref(),
        Some(if simplified{"物品上有以钻石制成的菱形图像。"}else{"物品上有以鑽石製成的菱形圖像。"}));
      assert_eq!(lookup("On the item is an image of diamonds in silver.",&terms,simplified).as_deref(),
        Some(if simplified{"物品上有以银制成的菱形图像。"}else{"物品上有以銀製成的菱形圖像。"}));
      assert!(lookup("This is an iron battle axe. It is encrusted with diamonds and unknown gems.",&terms,simplified).is_none());
    }
  }
  fn art_term(s:&str)->Option<String> {
    match s {
      "cat bone"=>Some("貓骨".into()),"pig bone"=>Some("豬骨".into()),
      "silver"=>Some("銀".into()),"dwarves"=>Some("矮人".into()),
      "giant tiger"=>Some("巨型虎".into()),"mayor"=>Some("市長".into()),
      "champion"=>Some("冠軍".into()),"iron battle axe"=>Some("鐵戰斧".into()),_=>None,
    }
  }
  #[test]
  fn standalone_artwork_preserves_native_link_subjects() {
    assert_eq!(lookup("On the item is an image of {{DFL0}} and dwarves in cat bone. {{DFL1}} is surrounded by the dwarves.",&art_term,false).as_deref(),
      Some("物品上有以貓骨製成的{{DFL0}}與矮人圖像。 {{DFL1}}被矮人包圍著。"));
    assert_eq!(lookup("On the item is an image of a giant tiger in silver.",&art_term,false).as_deref(),
      Some("物品上有以銀製成的巨型虎圖像。"));
    assert_eq!(lookup("This is an iron battle axe. On the item is an image of a giant tiger in silver.",&art_term,false).as_deref(),
      Some("這是鐵戰斧。 物品上有以銀製成的巨型虎圖像。"));
    let hans=|s:&str|match s {"cat bone"=>Some("猫骨".into()),"dwarves"=>Some("矮人".into()),_=>None};
    assert_eq!(lookup("On the item is an image of {{DFL0}} and dwarves in cat bone. {{DFL1}} is surrounded by the dwarves.",&hans,true).as_deref(),
      Some("物品上有以猫骨制成的{{DFL0}}与矮人图像。 {{DFL1}}被矮人包围着。"));
  }
  #[test]
  fn artwork_appointment_and_election_keep_person_office_and_year() {
    for (event,hant,hans) in [("appointment","獲任命","获任命"),("election","當選","当选")] {
      let source=format!("On the item is an image of {{{{DFL0}}}} and dwarves in cat bone. {{{{DFL1}}}} is surrounded by the dwarves. The artwork relates to the {event} of {{{{DFL2}}}} to the position of champion of {{{{DFL3}}}} in 1.");
      assert_eq!(lookup(&source,&art_term,false),Some(format!("物品上有以貓骨製成的{{{{DFL0}}}}與矮人圖像。 {{{{DFL1}}}}被矮人包圍著。 這件藝術品描繪了{{{{DFL2}}}}於1年{hant}為{{{{DFL3}}}}冠軍的事件。")));
      let terms=|s:&str|match s {"cat bone"=>Some("猫骨".into()),"champion"=>Some("冠军".into()),_=>art_term(s)};
      assert_eq!(lookup(&source,&terms,true),Some(format!("物品上有以猫骨制成的{{{{DFL0}}}}与矮人图像。 {{{{DFL1}}}}被矮人包围着。 这件艺术品描绘了{{{{DFL2}}}}于1年{hans}为{{{{DFL3}}}}冠军的事件。")));
    }
  }
  #[test]
  fn artwork_rejects_unknown_clauses_and_malformed_identity_slots_atomically() {
    for source in [
      "On the item is an image of Urist in silver.",
      "On the item is an image of {{DFL0}} in unknown metal.",
      "On the item is an image of {{DFL0}} in silver. {{DFL1}} does an unknown ritual.",
      "On the item is an image of {{DFL0}} in silver. The artwork relates to the election of {{DFL1}} to the position of mysterywizard of {{DFL2}} in 3.",
      "On the item is an image of {{DFL0}} in silver. The artwork relates to the election of {{DFL1}} to the position of mayor of {{DFL2}} in -3.",
      "On the item is an image of {{DFL0}} in silver. The artwork relates to the election of {{DFL1}} to the position of mayor of {{DFL2}} in 99999999.",
      "On the item is an image of {{DFL0}} in silver. {{DFL0}} is surrounded by dwarves.",
      "On the item is an image of {{DFL+1}} in silver.",
      "On the item is an image of {{DFL01}} in silver.",
      "On the item is an image of {{DFL64}} in silver.",
      "On the item is an image of {{DFL0}}[C:1:0:0] in silver.",
      "On the item is an image of {{DFL0}} in silver.[C:1:0:0]",
      "{{DFL0}} is surrounded by dwarves.",
    ] {assert!(lookup(source,&art_term,false).is_none(),"{source}");}
    let many=(0..9).map(|i|format!("{{{{DFL{i}}}}}")).collect::<Vec<_>>().join(" and ");
    assert!(lookup(&format!("On the item is an image of {many} in silver."),&art_term,false).is_none());
  }
  #[test]
  fn decorated_items_are_atomic_and_lists_are_bounded() {
    let terms=|s:&str| match s {"iron battle axe"=>Some("鐵戰斧".into()),"silver"=>Some("銀".into()),"gold"=>Some("金".into()),"diamonds"=>Some("鑽石".into()),_=>None};
    assert_eq!(lookup("This is an iron battle axe. It is encrusted with diamonds. It is encircled with bands of silver and gold. All craftsmanship is of the highest quality.",&terms,false).as_deref(),Some("這是鐵戰斧。 它鑲嵌著鑽石。 它環繞著銀與金飾帶。 所有工藝均為最高品質。"));
    assert!(lookup("This is an iron battle axe. It is decorated with silver and unknown metal.",&terms,false).is_none());
    assert!(lookup("This is an iron battle axe. It is decorated with silver. Unknown inscription.",&terms,false).is_none());
  }
  #[test]
  fn legendary_headers_and_size_keep_their_subject() {
    let terms=|s:&str|match s {"alunite slab"=>Some("明礬石板".into()),"silver helm"=>Some("銀頭盔".into()),"trolls"=>Some("巨魔".into()),_=>None};
    assert_eq!(lookup("{{DFL0}} was a legendary alunite slab.",&terms,false).as_deref(),Some("{{DFL0}}曾是傳奇的明礬石板。"));
    assert_eq!(lookup("This is a silver helm. It is sized for trolls.",&terms,false).as_deref(),Some("這是銀頭盔。 它的尺寸適合巨魔。"));
    assert!(lookup("{{DFL+1}} was a legendary alunite slab.",&terms,false).is_none());
  }
  fn term(s:&str)->Option<String> {match s {"pig tail trousers"=>Some("豬尾草長褲".into()),"pig tail cloth"=>Some("豬尾草布".into()),"iron battle axe"=>Some("鐵戰斧".into()),_=>None}}
  #[test]
  fn item_paragraph_is_immediate_and_atomic() {
    assert_eq!(lookup("This is a pig tail trousers.  It is made from pig tail cloth.  ",&term,false).as_deref(),Some("這是豬尾草長褲。  它由豬尾草布製成。  "));
    assert_eq!(lookup("This is an iron battle axe. All craftsdwarfship is of the highest quality.",&term,false).as_deref(),Some("這是鐵戰斧。 所有工藝均為最高品質。"));
    assert_eq!(lookup("This is an iron battle axe.",&term,true).as_deref(),Some("这是鐵戰斧。"));
    for s in ["This is an unknown object.","This is an iron battle axe. It has unknown runes.","This is an iron battle axe. It is made from unknown metal.","This is an iron battle axe.[C:evil]"] {assert!(lookup(s,&term,false).is_none(),"{s}");}
    assert!(lookup(&"This is an iron battle axe. ".repeat(200),&term,false).is_none());
  }
}
