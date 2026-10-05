//! Bounded narrative composition. Native links (DFL) and local-only text spans
//! (DFT) remain opaque. This composer never assigns either token a target.
pub fn lookup(source:&str,simplified:bool)->Option<String> {
  lookup_with_terms(source,&|_|None,simplified)
}
pub fn lookup_with_terms(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  if source.len()>4096 || source.contains('@') {return None;}
  if let Some(date)=crate::offline_dates::lookup(source,simplified) {return Some(date);}
  if source=="Related Sites" {return Some(if simplified{"相关地点"}else{"相關地點"}.into());}
  if source=="Slayer" {return Some(if simplified{"杀戮者"}else{"殺戮者"}.into());}
  if source.ends_with(" Kill") || source.ends_with(" Kills") {
    return kill_count(&source.to_ascii_lowercase()).map(|n|format!("{}{n}次",if simplified{"击杀"}else{"擊殺"}));
  }
  let (date,body)=if let Some(rest)=source.strip_prefix("In ") {
    let (year,body)=rest.split_once(", ")?;
    (format!("{}，",date(year)?),body)
  }else{(String::new(),source)};
  let body=body.strip_suffix('.').or_else(||body.strip_suffix('!')).unwrap_or(body);
  // Replace only complete adapter-provided slots, never inferred names.
  let mut rest=body;let mut normalized=String::new();let mut tokens=Vec::new();
  while let Some(start)=rest.find("{{DF") {
    normalized.push_str(&rest[..start]);rest=&rest[start..];
    let end=rest.find("}}")?+2;let token=&rest[..end];
    if !token.starts_with("{{DFL") && !token.starts_with("{{DFT") {return None;}
    let index=&token[5..token.len()-2];
    if index.len()>2 || !index.bytes().all(|b|b.is_ascii_digit()) || index.len()>1 && index.starts_with('0') ||
      !index.parse::<u8>().is_ok_and(|n|n<64) || tokens.contains(&token) || tokens.len()>=8 {return None;}
    normalized.push_str(&format!("@{}",tokens.len()));tokens.push(token);rest=&rest[end..];
  }
  normalized.push_str(rest);
  if tokens.is_empty() || normalized.contains(['{','}','[',']','\n','\r']) {return None;}
  let target=match normalized.as_str() {
    "@0 became an enemy of @1"=>("@0與@1成為敵人","@0与@1成为敌人"),
    "@0 attacked @1"=>("@0攻擊了@1","@0攻击了@1"),
    "@0 attacked @1 at @2"=>("@0在@2攻擊了@1","@0在@2攻击了@1"),
    "@0 attacked @1 in @2"=>("@0在@2攻擊了@1","@0在@2攻击了@1"),
    "@0 attacked @1 in @2 @3 led the attack, and the defenders were led by @4"=>
      ("@0在@2攻擊了@1。@3率領進攻，@4率領防守","@0在@2攻击了@1。@3率领进攻，@4率领防守"),
    "@0 attacked @1 at @2 @3 led the attack"=>
      ("@0在@2攻擊了@1。@3率領進攻","@0在@2攻击了@1。@3率领进攻"),
    "@0 accepted an offer of peace from @1"=>
      ("@0接受了@1提出的和平提議","@0接受了@1提出的和平提议"),
    "@0 swore to support @1 in war if the latter did likewise"=>
      ("@0宣誓在戰爭中支援@1，條件是後者也提供同樣的支援","@0宣誓在战争中支援@1，条件是后者也提供同样的支援"),
    "@0 defeated @1 and pillaged @2"=>("@0擊敗了@1，並劫掠了@2","@0击败了@1，并劫掠了@2"),
    "@0 fought with @1 While defeated, the latter escaped unscathed"=>
      ("@0與@1交戰。後者雖然戰敗，仍毫髮無傷地逃脫","@0与@1交战。后者虽然战败，仍毫发无伤地逃脱"),
    "@0 struck down @1 in @2"=>("@0在@2殺死了@1","@0在@2杀死了@1"),
    "@0 routed @1 of @2 and destroyed @3"=>
      ("@0擊潰了來自@2的@1，並摧毀了@3","@0击溃了来自@2的@1，并摧毁了@3"),
    "@0 confronted @1"=>("@0與@1對峙","@0与@1对峙"),
    "@0 devoured @1 in @2"=>("@0在@2吞食了@1","@0在@2吞食了@1"),
    "@0 (enemy)"=>("@0（敵人）","@0（敌人）"),
    "@0 was a cave"=>("@0曾是一座洞穴","@0曾是一座洞穴"),
    "@0 was made a symbol of the monarch by @1"=>("@1將@0定為君主的象徵","@1将@0定为君主的象征"),
    "@0 was created by @1"=>("@1創造了@0","@1创造了@0"),
    "@0 was created by @1 in @2"=>("@1在@2創造了@0","@1在@2创造了@0"),
    "@0 was created in @1 by @2"=>("@2在@1創造了@0","@2在@1创造了@0"),
    "@0 was stored in @1 by @2"=>("@2將@0存放於@1","@2将@0存放于@1"),
    "@0 was stored in @1 in @2"=>("@0被存放於@2的@1","@0被存放于@2的@1"),
    "@0 was stolen by @1 from @2"=>("@1從@2偷走了@0","@1从@2偷走了@0"),
    "@0 was looted from @1 by @2 after defeating @3"=>
      ("@2擊敗@3後，從@1掠走了@0","@2击败@3后，从@1掠走了@0"),
    "@0 was looted from @1 by @2 after murdering @3"=>
      ("@2謀殺@3後，從@1掠走了@0","@2谋杀@3后，从@1掠走了@0"),
    "@0 was offered to @1 of @2 by @3"=>("@3將@0獻給@2的@1","@3将@0献给@2的@1"),
    "@0 was made a family heirloom by @1"=>("@1將@0定為傳家寶","@1将@0定为传家宝"),
    "@0 was claimed by @1"=>("@1宣稱擁有@0","@1宣称拥有@0"),
    "@0 was claimed by @1 from afar"=>("@1從遠方宣稱擁有@0","@1从远方宣称拥有@0"),
    "@0 was lost in @1"=>("@0遺失於@1","@0遗失于@1"),
    "@0 was found in @1 by @2"=>("@2在@1找到了@0","@2在@1找到了@0"),
    "@0 and @1 became childhood friends"=>("@0與@1成為兒時玩伴","@0与@1成为儿时玩伴"),
    "@0 and @1 became lovers"=>("@0與@1成為戀人","@0与@1成为恋人"),
    "@0 and @1 broke up"=>("@0與@1分手","@0与@1分手"),
    "@0 was born"=>("@0出生了","@0出生了"),
    "@0 was born in @1"=>("@0出生於@1","@0出生于@1"),
    "@0 was born to @1 and @2"=>("@0出生了，父母為@1與@2","@0出生了，父母为@1与@2"),
    "@0 was born to @1 and @2 in @3"=>("@0出生於@3，父母為@1與@2","@0出生于@3，父母为@1与@2"),
    "@0 married @1"|"@0 married @1 at @2"|"@0 married @1 in @2"=>
      if tokens.len()==2 {("@0與@1結婚","@0与@1结婚")}else{("@0與@1在@2結婚","@0与@1在@2结婚")},
    "@0 divorced @1"=>("@0與@1離婚","@0与@1离婚"),
    "@0 died"=>("@0死亡了","@0死亡了"),
    "@0 died in @1"=>("@0死於@1","@0死于@1"),
    "@0 died of old age"=>("@0年老去世","@0年老去世"),
    "@0 died of old age in @1"=>("@0在@1年老去世","@0在@1年老去世"),
    "@0 was struck down by @1"|"@0 was slain by @1"=>("@0被@1殺死","@0被@1杀死"),
    "@0 was struck down by @1 in @2"|"@0 was slain by @1 in @2"=>("@0在@2被@1殺死","@0在@2被@1杀死"),
    "@0 was struck down by @1 with @2 in @3"=>("@0在@3被@1以@2殺死","@0在@3被@1以@2杀死"),
    "@0 was shot and killed by @1 in @2"=>("@0在@2被@1射殺","@0在@2被@1射杀"),
    "the bodies of @0 and others were horribly mutilated by @1 in @2"=>
      ("@0與其他人的遺體在@2遭@1殘酷毀損","@0与其他人的遗体在@2遭@1残酷毁损"),
    "@0 formed a false friendship with @1 in order to extract information in @2"=>
      ("@0假意與@1交好，以便在@2套取情報","@0假意与@1交好，以便在@2套取情报"),
    "@0 attempted to corrupt @1 in order to have an agent in @2 @3 met with @4 and, while completely misreading the situation, made a threat. @5 valued the law and refused, despite being afraid"=>
      ("@0試圖拉攏@1，以便在@2安插代理人。@3與@4會面，卻完全誤判形勢，出言威脅。@5雖然害怕，但仍重視法律而拒絕",
       "@0试图拉拢@1，以便在@2安插代理人。@3与@4会面，却完全误判形势，出言威胁。@5虽然害怕，但仍重视法律而拒绝"),
    "@0 settled in @1"=>("@0定居於@1","@0定居于@1"),
    "@0 moved to @1"=>("@0遷居至@1","@0迁居至@1"),
    "@0 founded @1"=>("@0建立了@1","@0建立了@1"),
    "@0 of @1 founded @2"=>("@1所屬的@0建立了@2","@1所属的@0建立了@2"),
    "@0 of @1 constructed @2 in @3"=>("@1所屬的@0在@3建造了@2","@1所属的@0在@3建造了@2"),
    "@0 ruled from @1 of @2 in @3"=>
      ("@0以位於@3、屬於@2的@1為統治據點","@0以位于@3、属于@2的@1为统治据点"),
    "@0 constructed @1 in @2"=>("@0在@2建造了@1","@0在@2建造了@1"),
    "@0 joined @1"=>("@0加入了@1","@0加入了@1"),
    "@0 became a member of @1"=>("@0成為@1的成員","@0成为@1的成员"),
    "@0 left @1"=>("@0離開了@1","@0离开了@1"),
    "@0 started working at @1 in @2"=>("@0開始在@2的@1工作","@0开始在@2的@1工作"),
    "@0 was abducted by @1"=>("@0被@1綁架","@0被@1绑架"),
    "@0 was abducted by @1 from @2"=>("@0被@1從@2綁走","@0被@1从@2绑走"),
    "@0 was imprisoned by @1"=>("@0被@1監禁","@0被@1监禁"),
    "@0 escaped from @1"=>("@0逃離了@1","@0逃离了@1"),
    "@0 has been found dead"=>("@0被發現已經死亡","@0被发现已经死亡"),
    "@0 has gone missing"=>("@0失蹤了","@0失踪了"),
    "@0 has given birth to a boy"=>("@0生下了一個男孩","@0生下了一个男孩"),
    "@0 has given birth to a girl"=>("@0生下了一個女孩","@0生下了一个女孩"),
    "@0 has been possessed"=>("@0被附身了","@0被附身了"),
    "@0 is taken by a fey mood"=>("@0陷入了神秘的創作情緒","@0陷入了神秘的创作情绪"),
    "@0 was taken by a fey mood in @1"=>("@0在@1陷入了神秘的創作情緒","@0在@1陷入了神秘的创作情绪"),
    "@0 withdraws from society"=>("@0退出了社交生活","@0退出了社交生活"),
    "@0 has gone stark raving mad"=>("@0徹底發瘋了","@0彻底发疯了"),
    "@0 has gone berserk"=>("@0狂暴發作了","@0狂暴发作了"),
    _=>{
      // Only the adapter's verified, non-clickable subject prefix can certify
      // a biography. Existing fixed event templates retain precedence.
      let target=if date.is_empty() && tokens[0].starts_with("{{DFT") &&
          (normalized.starts_with("@0 was a ") || normalized.starts_with("@0 was an ")) {
        biography(&normalized,term,simplified)
      }else{detail(&normalized,term,simplified)};
      return finish(&date,target?,&tokens);
    },
  };
  finish(&date,if simplified{target.1}else{target.0}.to_owned(),&tokens)
}
fn finish(date:&str,mut result:String,tokens:&[&str])->Option<String> {
  for (i,token) in tokens.iter().enumerate(){result=result.replace(&format!("@{i}"),token);}
  Some(format!("{date}{result}。"))
}

fn biography(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  let local=|hant,hans|if simplified{hans}else{hant};
  let mut clauses=source.split(". ");
  let first=clauses.next()?;
  let first=first.strip_prefix("@0 was a ").or_else(||first.strip_prefix("@0 was an "))?;
  let (race,birth)=first.split_once(" born in ").map(|(r,y)|(r,Some(y))).unwrap_or((first,None));
  if race.is_empty() || race.len()>128 || !race.bytes().all(|b|b.is_ascii_lowercase() || matches!(b,b' '|b'-')) {return None;}
  let race=term(&format!("DFL_LEGENDS_RACE:{race}"))?;
  if race.is_empty() || race.len()>512 || race.chars().any(|c|c.is_control() || c.is_ascii_alphabetic() ||
      matches!(c,'@'|'{'|'}'|'['|']'|'\u{fffd}')) {return None;}
  let mut result=format!("@0是{race}");
  if let Some(birth)=birth {result.push_str(&format!("，{}{birth}年",local("生於","生于"),birth=year(birth)?));}
  let Some(next)=clauses.next() else {return Some(result);};
  for (pronoun,possessive,zh,sex) in [("He","his","他","son"),("She","her","她","daughter"),("It","its",local("牠","它"),"")] {
    if let Some(relation)=next.strip_prefix(&format!("{pronoun} was the "))
        .and_then(|s|s.strip_suffix(" of @1 and @2")) {
      if sex.is_empty() || !relation.ends_with(sex) || relation.contains(',') || clauses.next().is_some() {return None;}
      let label=detail(&format!("@0 {relation}"),term,simplified)?;
      return Some(format!("{result}。{zh}是@1{}@2的{}",local("與","与"),label.strip_prefix("@0：")?));
    }
    if next==format!("{pronoun} was the only one of {possessive} kind") {
      result.push_str(&format!("。{zh}是其{}中唯一的{}",local("種類","种类"),local("個體","个体")));
      if let Some(association)=clauses.next() {
        let domains=association.strip_prefix("@1 was associated with ")?;
        let sphere=|s|match s {"wealth"=>Some(local("財富","财富")),"fire"=>Some("火"),_=>None};
        let domains=if let Some((a,b))=domains.split_once(" and ") {format!("{}及{}",sphere(a)?,sphere(b)?)}else{sphere(domains)?.to_owned()};
        result.push_str(&format!("。@1{}{domains}{}",local("與","与"),local("有關","有关")));
      }
      return clauses.next().is_none().then_some(result);
    }
  }
  None
}

fn role(source:&str,simplified:bool)->Option<&'static str> {
  let pair=match source {
    "weaponsmith"=>("武器匠","武器匠"),"hunter"=>("獵人","猎人"),"woodcutter"=>("樵夫","樵夫"),
    "dean"=>("院長","院长"),"princess"=>("公主","公主"),"king"=>("國王","国王"),
    "queen"=>("女王","女王"),"mayor"=>("市長","市长"),"priest"=>("祭司","祭司"),
    "merchant"=>("商人","商人"),"tavern keeper"=>("酒保","酒保"),
    "master of beasts"=>("獸群主管","兽群主管"),
    "law-giver"=>("立法者","立法者"),"marshal"=>("元帥","元帅"),
    "chief butler"=>("總管家","总管家"),"royal chef"=>("王室主廚","王室主厨"),
    "head advisor"=>("首席顧問","首席顾问"),"head housekeeper"=>("家務總管","家务总管"),
    "head chamberlain"=>("內務總管","内务总管"),"royal executioner"=>("王室劊子手","王室刽子手"),
    "justiciar"=>("司法官","司法官"),"chief treasurer"=>("財政總管","财政总管"),
    "keeper of the seal"=>("掌璽官","掌玺官"),"fire administrator"=>("火務管理官","火务管理官"),
    "lord"=>("領主","领主"),"lady"=>("女領主","女领主"),
    "baron"=>("男爵","男爵"),"baroness"=>("女男爵","女男爵"),
    "high counselor"=>("高階顧問","高阶顾问"),"high chef"=>("高階主廚","高阶主厨"),
    "judge"=>("法官","法官"),"grain administrator"=>("糧務管理官","粮务管理官"),
    "road official"=>("道路官員","道路官员"),
    _=>return None,
  };
  Some(if simplified{pair.1}else{pair.0})
}
fn detail(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  let local=|hant,hans|if simplified{hans}else{hant};
  if source.starts_with("@0 held ") {return festival(source,term,simplified);}
  if let Some(rest)=source.strip_prefix("@0 was a ").or_else(||source.strip_prefix("@0 was an ")) {
    let (race,kind)=if let Some(race)=rest.strip_suffix(" civilization of @1") {(race,0)}
      else if let Some(race)=rest.strip_suffix(" group from @1") {(race,1)}else{return None;};
    if race.is_empty() || race.len()>128 || !race.bytes().all(|b|b.is_ascii_lowercase() || matches!(b,b' '|b'-')) {return None;}
    let race=term(&format!("DFL_LEGENDS_RACE:{race}"))?;
    if race.is_empty() || race.len()>512 || race.chars().any(|c|c.is_control() || c.is_ascii_alphabetic() ||
        matches!(c,'@'|'{'|'}'|'['|']'|'\u{fffd}')) {return None;}
    return Some(if kind==0 {format!("@0是@1的{race}文明")}
      else {format!("@0是{}@1的{race}{}",local("來自","来自"),local("團體","团体"))});
  }
  if let Some(rest)=source.strip_prefix("@0 of @1 ") {
    // Keep the native actor and affiliation separate. Only these complete
    // methods certify a position event; unknown titles/aftermath reject it.
    let actor=local("@1所屬的@0","@1所属的@0");
    if let Some(title)=rest.strip_prefix("compelled the creation of the position of ")
        .and_then(|s|s.strip_suffix(" with threats of violence")) {
      return Some(format!("{actor}以暴力{}迫使{}{}被{}",local("威脅","威胁"),
        role(title,simplified)?,local("一職","一职"),local("設立","设立")));
    }
    if let Some(rest)=rest.strip_prefix("created the position of ") {
      for (suffix,method) in [(" as a matter of course",local("按慣例","按惯例")),
          (" through force of argument",local("以辯論的力量","以辩论的力量")),
          (", pushed by a wave of popular support",local("在民意支持的浪潮推動下","在民意支持的浪潮推动下")),
          (" pushed by a wave of popular support",local("在民意支持的浪潮推動下","在民意支持的浪潮推动下"))] {
        if let Some(title)=rest.strip_suffix(suffix) {
          return Some(format!("{actor}{method}{}了{}{}",local("設立","设立"),
            role(title,simplified)?,local("一職","一职")));
        }
      }
    }
    return None;
  }
  let known=|s:&str| {
    if s.is_empty() || s.len()>256 || s.contains(['@','{','}','[',']','.']) ||
        s.chars().any(char::is_control) {return None;}
    let t=term(s)?;
    (!t.is_empty() && t.len()<=1024 && !t.chars().any(|c|c.is_control() || c.is_ascii_alphabetic() ||
        matches!(c,'@'|'{'|'}'|'['|']'|'\u{fffd}'))).then_some(t)
  };
  for (prefix,outcome) in [("@0 did poorly trading ","成果不佳"),("@0 broke even trading ","收支平衡")] {
    if let Some(goods)=source.strip_prefix(prefix).and_then(|s|s.strip_suffix(" from @1 to @2")) {
      return Some(format!("@0{}@1向@2交易{}，{outcome}",local("從","从"),known(goods)?));
    }
  }
  if let Some(animal)=source.strip_prefix("@0 devoured a ").or_else(||source.strip_prefix("@0 devoured an "))
      .and_then(|s|s.strip_suffix(" of @1 in @2")) {
    return Some(format!("@0在@2吞食了@1的一{}{}",local("隻","只"),known(animal)?));
  }
  if let Some(r)=source.strip_prefix("@0 became a ").and_then(|s|s.strip_suffix(" in @1")) {
    return Some(format!("@0在@1{}{}",local("成為","成为"),role(r,simplified)?));
  }
  if let Some(r)=source.strip_prefix("@0 stopped being a ").and_then(|s|s.strip_suffix(" in @1")) {
    return Some(format!("@0{}@1{}{}",local("不再於","不再于"),local("擔任","担任"),role(r,simplified)?));
  }
  if let Some(r)=source.strip_prefix("@0 became the ").and_then(|s|s.strip_suffix(" of @1")) {
    return Some(format!("@0{}@1的{}",local("成為","成为"),role(r,simplified)?));
  }
  let rest=source.strip_prefix("@0 ").or_else(||source.strip_prefix("@0, "))?;
  if rest.starts_with("b. ") || rest.starts_with("d. ") {
    return Some(format!("@0：{}",lifespan(rest,simplified)?));
  }
  if let Some(r)=rest.strip_prefix('(').and_then(|s|s.strip_suffix(')')) {
    let (r,years)=if let Some((r,range))=r.split_once(", ") {
      let (from,to)=range.split_once(" to ").or_else(||range.split_once('-'))?;
      let from=year(from)?;
      let years=if to=="present" {format!("，{from}年至今")}
      else {
        let to=year(to)?;
        if from.parse::<u32>().ok()?>to.parse::<u32>().ok()? {return None;}
        format!("，{from}年至{to}年")
      };
      (r,years)
    }else{(r,String::new())};
    let r=match r {"member"=>local("成員","成员"),"former member"=>local("前成員","前成员"),
      "site occ"=>local("在此任職","在此任职"),_=>role(r,simplified)?};
    return Some(format!("@0（{r}{years}）"));
  }
  let (relationship,years)=rest.split_once(", ").unwrap_or((rest,""));
  let relationship=match relationship {
    "mother"=>local("母親","母亲"),"father"=>local("父親","父亲"),
    "eldest son"=>local("長子","长子"),"second eldest son"=>"次子","youngest son"=>"幼子",
    "eldest daughter"=>local("長女","长女"),"second eldest daughter"=>"次女","youngest daughter"=>"幼女",
    "spouse"=>"配偶","former spouse"=>"前配偶",
    "deceased spouse"=>"已故配偶","wife"=>"妻子","husband"=>"丈夫",
    "lover"=>local("戀人","恋人"),"only daughter"=>local("獨生女","独生女"),
    "only son"=>local("獨生子","独生子"),
    "object of worship"=>local("崇拜的對象","崇拜的对象"),
    "object of faithful worship"=>local("虔誠崇拜的對象","虔诚崇拜的对象"),
    "object of casual worship"=>local("偶爾崇拜的對象","偶尔崇拜的对象"),
    "object of dubious worship"=>local("心存疑慮的崇拜對象","心存疑虑的崇拜对象"),
    "object of ardent worship"=>local("熱忱崇拜的對象","热忱崇拜的对象"),
    other=>{
      let (order,sex)=other.split_once(" eldest ")?;
      let order=match order {
        "third"=>"三","fourth"=>"四","fifth"=>"五","sixth"=>"六","seventh"=>"七","eighth"=>"八",
        "ninth"=>"九","tenth"=>"十","eleventh"=>"十一","twelfth"=>"十二","thirteenth"=>"十三",
        "fourteenth"=>"十四","fifteenth"=>"十五","sixteenth"=>"十六","seventeenth"=>"十七",
        "eighteenth"=>"十八","nineteenth"=>"十九","twentieth"=>"二十",_=>return None,
      };
      let sex=match sex {"son"=>"子","daughter"=>"女",_=>return None};
      let years=if years.is_empty(){String::new()}else{format!("，{}",lifespan(years,simplified)?)};
      return Some(format!("@0：第{order}{sex}{years}"));
    },
  };
  let mut result=format!("@0：{relationship}");
  if years.is_empty(){return Some(result);}
  result.push_str(&format!("，{}",lifespan(years,simplified)?));
  Some(result)
}
fn history_slot(s:&str)->bool {
  s.len()==2 && s.starts_with('@') && matches!(s.as_bytes()[1],b'0'..=b'7')
}
fn ascension_story(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  let (figure,position)=source.strip_prefix("the story of the ascension of ")?.split_once(" to the position of ")?;
  let figure=if history_slot(figure) {figure.to_owned()}else{
    let (race,figure)=figure.strip_prefix("the ")?.rsplit_once(' ')?;
    if !history_slot(figure) || race.is_empty() || race.len()>128 ||
        !race.bytes().all(|b|b.is_ascii_lowercase() || matches!(b,b' '|b'-')) {return None;}
    let race=term(&format!("DFL_LEGENDS_RACE:{race}"))?;
    if race.is_empty() || race.len()>512 || race.chars().any(|c|c.is_control() || c.is_ascii_alphabetic() ||
        matches!(c,'@'|'{'|'}'|'['|']'|'\u{fffd}')) {return None;}
    format!("{race} {figure}")
  };
  let (position,rest)=position.split_once(" of ")?;
  let (entity,event_date)=rest.split_once(" in ")?;
  if !history_slot(entity) {return None;}
  Some(format!("「{figure}{}{event_date}升任{entity}的{position}」的故事",
    if simplified{"于"}else{"於"},event_date=date(event_date)?,position=role(position,simplified)?))
}
fn festival(source:&str,term:&dyn Fn(&str)->Option<String>,simplified:bool)->Option<String> {
  let local=|hant,hans|if simplified{hans}else{hant};
  let slot=|s:&str|s.len()==2 && s.starts_with('@') && matches!(s.as_bytes()[1],b'0'..=b'7');
  let rest=source.strip_prefix("@0 held ")?;
  let mut clauses=rest.split(". ");
  let (activity,rest)=clauses.next()?.rsplit_once(" in ")?;
  let (site,occasion)=rest.split_once(" as part of ")?;
  if !slot(site) || !slot(occasion) {return None;}
  let (activity,kind)=match activity {
    "a ceremony"=>(local("儀式","仪式").to_owned(),0),
    "a story recital"=>(local("故事朗誦","故事朗诵").to_owned(),1),
    "a procession"=>(local("遊行","游行").to_owned(),2),
    other if other.starts_with("the story of the ascension of ")=>(ascension_story(other,term,simplified)?,3),
    other=>{
      let (name,label)=if let Some(name)=other.strip_prefix("a recital of ") {(name,local("朗誦","朗诵"))}
        else {(other.strip_prefix("a performance of ")?,"表演")};
      if !slot(name) {return None;}
      (format!("{name}的{label}"),1)
    },
  };
  let verb=if kind==3 {local("講述","讲述")}else{local("舉行","举行")};
  let mut result=format!("@0在{site}{verb}了{activity}，{}{occasion}的一部分",local("作為","作为"));
  if kind==2 {
    let building=clauses.next()?.strip_prefix("It started at ")?
      .strip_suffix(" and returned there after following its route")?;
    if !slot(building) {return None;}
    result.push_str(&format!("。{}{building}{}",local("遊行從","游行从"),
      local("出發，沿路線行進後返回原處","出发，沿路线行进后返回原处")));
  }
  if let Some(clause)=clauses.next() {
    if kind==1 || kind==3 {return None;}
    let list=clause.strip_prefix("The event featured ")?;
    let mut features=if let Some((before,last))=list.rsplit_once(" and ") {
      let mut v=before.split(", ").collect::<Vec<_>>();v.push(last);v
    }else{
      if list.contains(", ") {return None;}vec![list]
    };
    if features.is_empty() || features.len()>16 {return None;}
    let mut seen=Vec::new();let mut translated=Vec::new();
    for feature in features.drain(..) {
      if seen.contains(&feature) {return None;}seen.push(feature);
      let target=match feature {
        "storytelling"=>local("說故事","说故事").to_owned(),"incense burning"=>"焚香".to_owned(),
        "candles"=>local("蠟燭","蜡烛").to_owned(),"images"=>local("圖像","图像").to_owned(),
        "costumes"=>local("服裝","服装").to_owned(),"banners"=>local("旗幟","旗帜").to_owned(),
        other if other.starts_with("a telling of the story of the ascension of ")=>
          format!("{}{}",local("講述","讲述"),ascension_story(other.strip_prefix("a telling of ")?,term,simplified)?),
        other=>{
          let (name,label)=if let Some(name)=other.strip_prefix("a recital of ") {(name,local("朗誦","朗诵"))}
            else {(other.strip_prefix("a performance of ")?,"表演")};
          if !slot(name) {return None;}format!("{name}的{label}")
        },
      };
      translated.push(target);
    }
    let last=translated.pop()?;
    let list=if translated.is_empty(){last}else{format!("{}及{last}",translated.join("、"))};
    result.push_str(&format!("。{}包含{list}",local("活動","活动")));
  }
  clauses.next().is_none().then_some(result)
}
fn lifespan(source:&str,simplified:bool)->Option<String> {
  let (years,kills)=source.split_once(", ").map(|(years,kills)|(years,Some(kills))).unwrap_or((source,None));
  let (birth,death)=if let Some(b)=years.strip_prefix("b. ") {
    let (b,d)=b.split_once(" d. ").map(|(b,d)|(b,Some(d))).unwrap_or((b,None));
    (Some(year(b)?),match d {Some(d)=>Some(year(d)?),None=>None})
  }else{(None,Some(year(years.strip_prefix("d. ")?)?))};
  if let (Some(b),Some(d))=(birth,death) {if b.parse::<u32>().ok()?>d.parse::<u32>().ok()? {return None;}}
  let mut details=Vec::new();
  if let Some(b)=birth {details.push(format!("{}{b}年",if simplified{"生于"}else{"生於"}));}
  if let Some(d)=death {details.push(format!("{}{d}年",if simplified{"卒于"}else{"卒於"}));}
  if let Some(kills)=kills {details.push(format!("{}{}次",if simplified{"击杀"}else{"擊殺"},kill_count(kills)?));}
  Some(details.join("，"))
}
fn kill_count(source:&str)->Option<u32> {
  let (number,plural)=if let Some(n)=source.strip_suffix(" kills") {(n,true)}else{(source.strip_suffix(" kill")?,false)};
  fn small(n:&str)->Option<u32> {
    ["one","two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","thirteen",
      "fourteen","fifteen","sixteen","seventeen","eighteen","nineteen"].iter().position(|s|*s==n).map(|i|i as u32+1)
  }
  let n=if let Some(n)=small(number) {n}
    else if !number.starts_with('0') && year(number).is_some() {number.parse().ok()?}
    else {
      let (tens,ones)=number.split_once('-').map(|(t,o)|(t,Some(o))).unwrap_or((number,None));
      let tens=match tens {"twenty"=>20,"thirty"=>30,"forty"=>40,"fifty"=>50,"sixty"=>60,"seventy"=>70,"eighty"=>80,"ninety"=>90,_=>return None};
      let ones=match ones {Some(o)=>{let n=small(o)?;if n>9{return None;}n},None=>0};
      tens+ones
    };
  ((n>1)==plural && n>0).then_some(n)
}
fn year(value:&str)->Option<&str> {
  (!value.is_empty() && value.len()<=7 && value.bytes().all(|b|b.is_ascii_digit())).then_some(value)
}
fn date(value:&str)->Option<String> {
  if let Some((season,y))=value.strip_prefix("the ").and_then(|s|s.split_once(" of ")) {
    let season=match season {
      "early spring"=>"初春","midspring"=>"仲春","late spring"=>"暮春",
      "early summer"=>"初夏","midsummer"=>"仲夏","late summer"=>"夏末",
      "early autumn"=>"初秋","midautumn"=>"仲秋","late autumn"=>"深秋",
      "early winter"=>"初冬","midwinter"=>"仲冬","late winter"=>"冬末",_=>return None,
    };
    Some(format!("{}年{season}",year(y)?))
  }else{Some(format!("{}年",year(value.strip_prefix("the year ").unwrap_or(value))?))}
}

#[cfg(test)]
mod tests {
  #[test]
  fn ceremony_ascension_feature_preserves_complete_linked_story_and_list() {
    let source="In the early autumn of 70, {{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured a telling of the story of the ascension of {{DFL2}} to the position of law-giver of {{DFL3}} in 70, images, candles, banners, a recital of {{DFT1}} and a performance of {{DFT2}}.";
    assert_eq!(lookup(source,false).as_deref(),Some("70年初秋，{{DFL0}}在{{DFL1}}舉行了儀式，作為{{DFT0}}的一部分。活動包含講述「{{DFL2}}於70年升任{{DFL3}}的立法者」的故事、圖像、蠟燭、旗幟、{{DFT1}}的朗誦及{{DFT2}}的表演。"));
    assert_eq!(lookup(source,true).as_deref(),Some("70年初秋，{{DFL0}}在{{DFL1}}举行了仪式，作为{{DFT0}}的一部分。活动包含讲述「{{DFL2}}于70年升任{{DFL3}}的立法者」的故事、图像、蜡烛、旗帜、{{DFT1}}的朗诵及{{DFT2}}的表演。"));
    for rejected in [
      source.replace("{{DFL2}} to the position","Unverified Figure to the position"),
      source.replace("law-giver","mysterywizard"),
      source.replace("{{DFL3}} in 70","Unverified Entity in 70"),
      source.replace("in 70, images","in an unknown year, images"),
      source.replace("images, candles","unknown feature, candles"),
      source.replace("in 70, images","in 70 and triumphed, images"),
      format!("{source} Unknown aftermath"),
    ] {for simplified in [false,true] {assert!(lookup(&rejected,simplified).is_none(),"{rejected}");}}
    let typed="{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured a telling of the story of the ascension of the human {{DFT1}} to the position of law-giver of {{DFT2}} in the early summer of 3 and candles.";
    let term=|s:&str|match s {"DFL_LEGENDS_RACE:human"=>Some("人類".into()),_=>None};
    assert_eq!(super::lookup_with_terms(typed,&term,false).as_deref(),Some("{{DFL0}}在{{DFL1}}舉行了儀式，作為{{DFT0}}的一部分。活動包含講述「人類 {{DFT1}}於3年初夏升任{{DFT2}}的立法者」的故事及蠟燭。"));
    assert!(lookup(typed,false).is_none());
    assert!(super::lookup_with_terms(&typed.replace("human","unknown beast"),&term,false).is_none());
  }
  #[test]
  fn commemorative_position_story_preserves_both_dates_and_all_named_roles() {
    let term=|s:&str|match s {"DFL_LEGENDS_RACE:human"=>Some("人類".into()),_=>None};
    let source="In the early winter of 4, {{DFL0}} held the story of the ascension of the human {{DFT0}} to the position of law-giver of {{DFT1}} in the early summer of 3 in {{DFL1}} as part of {{DFT2}}.";
    assert_eq!(super::lookup_with_terms(source,&term,false).as_deref(),
      Some("4年初冬，{{DFL0}}在{{DFL1}}講述了「人類 {{DFT0}}於3年初夏升任{{DFT1}}的立法者」的故事，作為{{DFT2}}的一部分。"));
    let term=|s:&str|match s {"DFL_LEGENDS_RACE:human"=>Some("人类".into()),_=>None};
    assert_eq!(super::lookup_with_terms(source,&term,true).as_deref(),
      Some("4年初冬，{{DFL0}}在{{DFL1}}讲述了「人类 {{DFT0}}于3年初夏升任{{DFT1}}的立法者」的故事，作为{{DFT2}}的一部分。"));
    let source="In 71, {{DFL0}} held the story of the ascension of the human {{DFT0}} to the position of law-giver of {{DFT1}} in 70 in {{DFL1}} as part of {{DFT2}}.";
    assert_eq!(super::lookup_with_terms(source,&term,true).as_deref(),
      Some("71年，{{DFL0}}在{{DFL1}}讲述了「人类 {{DFT0}}于70年升任{{DFT1}}的立法者」的故事，作为{{DFT2}}的一部分。"));
    for rejected in [
      source.replace("human {{DFT0}}","unknown beast {{DFT0}}"),
      source.replace("law-giver","mysterywizard"),
      source.replace("human {{DFT0}}","human Unverified Figure"),
      source.replace("of {{DFT1}} in 70","of Unknown Entity in 70"),
      source.replace("in 70 in","in the unknown summer of 70 in"),
      format!("{source} Unknown aftermath"),
    ] {assert!(super::lookup_with_terms(&rejected,&term,true).is_none(),"{rejected}");}
  }
  #[test]
  fn festival_activities_preserve_all_named_roles_and_features() {
    for (source,hant,hans) in [
      ("In the early winter of 4, {{DFL0}} held a recital of {{DFT0}} in {{DFL1}} as part of {{DFT1}}.",
       "4年初冬，{{DFL0}}在{{DFL1}}舉行了{{DFT0}}的朗誦，作為{{DFT1}}的一部分。",
       "4年初冬，{{DFL0}}在{{DFL1}}举行了{{DFT0}}的朗诵，作为{{DFT1}}的一部分。"),
      ("{{DFL0}} held a performance of {{DFT0}} in {{DFL1}} as part of {{DFT1}}.",
       "{{DFL0}}在{{DFL1}}舉行了{{DFT0}}的表演，作為{{DFT1}}的一部分。",
       "{{DFL0}}在{{DFL1}}举行了{{DFT0}}的表演，作为{{DFT1}}的一部分。"),
      ("{{DFL0}} held a story recital in {{DFL1}} as part of {{DFT0}}.",
       "{{DFL0}}在{{DFL1}}舉行了故事朗誦，作為{{DFT0}}的一部分。",
       "{{DFL0}}在{{DFL1}}举行了故事朗诵，作为{{DFT0}}的一部分。"),
      ("{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured storytelling, a recital of {{DFT1}}, a performance of {{DFT2}}, candles, images and costumes.",
       "{{DFL0}}在{{DFL1}}舉行了儀式，作為{{DFT0}}的一部分。活動包含說故事、{{DFT1}}的朗誦、{{DFT2}}的表演、蠟燭、圖像及服裝。",
       "{{DFL0}}在{{DFL1}}举行了仪式，作为{{DFT0}}的一部分。活动包含说故事、{{DFT1}}的朗诵、{{DFT2}}的表演、蜡烛、图像及服装。"),
      ("{{DFL0}} held a procession in {{DFL1}} as part of {{DFT0}}. It started at {{DFT1}} and returned there after following its route. The event featured incense burning, candles, images, a performance of {{DFT2}} and banners.",
       "{{DFL0}}在{{DFL1}}舉行了遊行，作為{{DFT0}}的一部分。遊行從{{DFT1}}出發，沿路線行進後返回原處。活動包含焚香、蠟燭、圖像、{{DFT2}}的表演及旗幟。",
       "{{DFL0}}在{{DFL1}}举行了游行，作为{{DFT0}}的一部分。游行从{{DFT1}}出发，沿路线行进后返回原处。活动包含焚香、蜡烛、图像、{{DFT2}}的表演及旗帜。"),
      ("{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured candles.",
       "{{DFL0}}在{{DFL1}}舉行了儀式，作為{{DFT0}}的一部分。活動包含蠟燭。",
       "{{DFL0}}在{{DFL1}}举行了仪式，作为{{DFT0}}的一部分。活动包含蜡烛。"),
      ("{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured storytelling and banners.",
       "{{DFL0}}在{{DFL1}}舉行了儀式，作為{{DFT0}}的一部分。活動包含說故事及旗幟。",
       "{{DFL0}}在{{DFL1}}举行了仪式，作为{{DFT0}}的一部分。活动包含说故事及旗帜。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
  }
  #[test]
  fn festival_unknown_names_features_and_aftermath_reject_atomically() {
    for source in [
      "{{DFL0}} held a recital of Unverified Poem in {{DFL1}} as part of {{DFT0}}",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of Unverified Festival",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured unknown ritual",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured candles, images",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured candles, and images",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured candles and candles",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. The event featured candles. Unknown aftermath",
      "{{DFL0}} held a recital of {{DFT0}} in {{DFL1}} as part of {{DFT1}}. The event featured candles",
      "{{DFL0}} held a ceremony in {{DFL1}} as part of {{DFT0}}. It started at {{DFT1}} and returned there after following its route",
      "{{DFL0}} held a procession in {{DFL1}} as part of {{DFT0}}. It started at Unverified Building and returned there after following its route",
      "{{DFL0}} held a procession in {{DFL1}} as part of {{DFT0}}. It started at {{DFT1}} and disappeared",
      "{{DFL0}} held a procession in {{DFL1}} as part of {{DFT0}}",
      "{{DFL0}} held a competition in {{DFL1}} as part of {{DFT0}}",
    ] {assert!(lookup(source,false).is_none(),"{source}");}
  }
  #[test]
  fn entity_introductions_require_complete_typed_race_and_verified_world() {
    let term=|s:&str|match s {"DFL_LEGENDS_RACE:human"=>Some("人類".into()),_=>None};
    assert_eq!(super::lookup_with_terms("{{DFL0}} was a human civilization of {{DFT0}}.",&term,false).as_deref(),
      Some("{{DFL0}}是{{DFT0}}的人類文明。"));
    assert_eq!(super::lookup_with_terms("{{DFL0}} was a human group from {{DFT0}}.",&term,false).as_deref(),
      Some("{{DFL0}}是來自{{DFT0}}的人類團體。"));
    for source in ["{{DFL0}} was a human civilization of Unverified World.",
      "{{DFL0}} was a human mystery group from {{DFT0}}.",
      "{{DFL0}} was a human group from {{DFT0}}. Unknown aftermath"] {
      assert!(super::lookup_with_terms(source,&term,false).is_none(),"{source}");
    }
  }
  #[test]
  fn ruling_retains_ruler_building_entity_and_site() {
    let source="In 5, {{DFL0}} ruled from {{DFL1}} of {{DFL2}} in {{DFL3}}";
    assert_eq!(lookup(source,false).as_deref(),Some("5年，{{DFL0}}以位於{{DFL3}}、屬於{{DFL2}}的{{DFL1}}為統治據點。"));
    assert_eq!(lookup(source,true).as_deref(),Some("5年，{{DFL0}}以位于{{DFL3}}、属于{{DFL2}}的{{DFL1}}为统治据点。"));
    for rejected in [
      "{{DFL0}} ruled from Unverified Building of {{DFL1}} in {{DFL2}}",
      "{{DFL0}} ruled from {{DFL1}} of {{DFL2}} in {{DFL3}} until a revolt",
      "{{DFL0}} ruled from {{DFL1}} of {{DFL1}} in {{DFL2}}",
    ] {for simplified in [false,true] {assert!(lookup(rejected,simplified).is_none(),"{rejected}");}}
  }
  #[test]
  fn native_popular_support_punctuation_preserves_the_complete_method() {
    let source="In 5, {{DFL0}} of {{DFL1}} created the position of baron, pushed by a wave of popular support.";
    for simplified in [false,true] {
      let expected=if simplified {
        "5年，{{DFL1}}所属的{{DFL0}}在民意支持的浪潮推动下设立了男爵一职。"
      }else {
        "5年，{{DFL1}}所屬的{{DFL0}}在民意支持的浪潮推動下設立了男爵一職。"
      };
      assert_eq!(lookup(source,simplified).as_deref(),Some(expected));
      for rejected in [
        "{{DFL0}} of {{DFL1}} created the position of baron,, pushed by a wave of popular support",
        "{{DFL0}} of {{DFL1}} created the position of wizard, pushed by a wave of popular support",
        "{{DFL0}} of {{DFL1}} created the position of baron, pushed by a wave of popular support. Then a revolt occurred",
        "{{DFL0}} of {{DFL1}} created the position of baron, pushed by a wave of violent opposition",
      ] {assert!(lookup(rejected,simplified).is_none(),"{rejected}");}
    }
  }
  #[test]
  fn affiliated_founders_builders_and_battle_commanders_keep_every_actor() {
    for (source,hant,hans) in [
      ("In 1, {{DFL0}} of {{DFL1}} founded {{DFL2}}", "1年，{{DFL1}}所屬的{{DFL0}}建立了{{DFL2}}。", "1年，{{DFL1}}所属的{{DFL0}}建立了{{DFL2}}。"),
      ("In 7, {{DFL0}} of {{DFL1}} constructed {{DFL2}} in {{DFL3}}", "7年，{{DFL1}}所屬的{{DFL0}}在{{DFL3}}建造了{{DFL2}}。", "7年，{{DFL1}}所属的{{DFL0}}在{{DFL3}}建造了{{DFL2}}。"),
      ("{{DFL0}} constructed {{DFL1}} in {{DFL2}}", "{{DFL0}}在{{DFL2}}建造了{{DFL1}}。", "{{DFL0}}在{{DFL2}}建造了{{DFL1}}。"),
      ("In the early spring of 4, {{DFL0}} attacked {{DFL1}} in {{DFL2}} {{DFL3}} led the attack, and the defenders were led by {{DFL4}}", "4年初春，{{DFL0}}在{{DFL2}}攻擊了{{DFL1}}。{{DFL3}}率領進攻，{{DFL4}}率領防守。", "4年初春，{{DFL0}}在{{DFL2}}攻击了{{DFL1}}。{{DFL3}}率领进攻，{{DFL4}}率领防守。"),
      ("{{DFL0}} attacked {{DFL1}} at {{DFL2}} {{DFL3}} led the attack", "{{DFL0}}在{{DFL2}}攻擊了{{DFL1}}。{{DFL3}}率領進攻。", "{{DFL0}}在{{DFL2}}攻击了{{DFL1}}。{{DFL3}}率领进攻。"),
      ("{{DFL0}} accepted an offer of peace from {{DFL1}}", "{{DFL0}}接受了{{DFL1}}提出的和平提議。", "{{DFL0}}接受了{{DFL1}}提出的和平提议。"),
      ("{{DFL0}} swore to support {{DFL1}} in war if the latter did likewise", "{{DFL0}}宣誓在戰爭中支援{{DFL1}}，條件是後者也提供同樣的支援。", "{{DFL0}}宣誓在战争中支援{{DFL1}}，条件是后者也提供同样的支援。"),
      ("{{DFL0}} defeated {{DFL1}} and pillaged {{DFL2}}", "{{DFL0}}擊敗了{{DFL1}}，並劫掠了{{DFL2}}。", "{{DFL0}}击败了{{DFL1}}，并劫掠了{{DFL2}}。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in [
      "{{DFL0}} of {{DFL1}} founded {{DFL2}} and later abandoned it",
      "{{DFL0}} of {{DFL1}} constructed Unverified Building in {{DFL2}}",
      "{{DFL0}} attacked {{DFL1}} in {{DFL2}} Bob led the attack, and the defenders were led by {{DFL3}}",
      "{{DFL0}} attacked {{DFL1}} at {{DFL2}} {{DFL3}} led the defense",
      "{{DFL0}} swore to support {{DFL1}} in war if the former did likewise",
      "{{DFL0}} accepted an offer of peace from {{DFL1}}. Unknown aftermath",
      "{{DFL0}} defeated {{DFL1}} and pillaged {{DFL1}}",
    ] {for simplified in [false,true] {assert!(lookup(source,simplified).is_none(),"{source}");}}
  }
  #[test]
  fn position_creation_keeps_coercion_argument_and_custom_distinct() {
    for simplified in [false,true] {
      let local=|hant,hans|if simplified{hans}else{hant};
      for (role,title) in [
        ("law-giver", "立法者"), ("marshal",local("元帥","元帅")),
        ("chief butler",local("總管家","总管家")), ("royal chef",local("王室主廚","王室主厨")),
        ("head advisor",local("首席顧問","首席顾问")), ("head housekeeper",local("家務總管","家务总管")),
        ("head chamberlain",local("內務總管","内务总管")), ("royal executioner",local("王室劊子手","王室刽子手")),
        ("justiciar","司法官"), ("chief treasurer",local("財政總管","财政总管")),
        ("keeper of the seal",local("掌璽官","掌玺官")), ("fire administrator",local("火務管理官","火务管理官")),
        ("lord",local("領主","领主")),("lady",local("女領主","女领主")),
        ("baron","男爵"),("baroness","女男爵"),("high counselor",local("高階顧問","高阶顾问")),
        ("high chef",local("高階主廚","高阶主厨")),("judge","法官"),
        ("grain administrator",local("糧務管理官","粮务管理官")),("road official",local("道路官員","道路官员")),
      ] {
        let source=format!("In 3, {{{{DFL0}}}} became the {role} of {{{{DFL1}}}}");
        assert_eq!(lookup(&source,simplified),Some(format!("3年，{{{{DFL0}}}}{}{{{{DFL1}}}}的{title}。",local("成為","成为"))),"{source}");
        for (verb,method,translated) in [
          ("created the position of","as a matter of course",format!("按{}{}了{title}{}",local("慣例","惯例"),local("設立","设立"),local("一職","一职"))),
          ("created the position of","through force of argument",format!("以{}的力量{}了{title}{}",local("辯論","辩论"),local("設立","设立"),local("一職","一职"))),
          ("compelled the creation of the position of","with threats of violence",format!("以暴力{}迫使{title}{}被{}",local("威脅","威胁"),local("一職","一职"),local("設立","设立"))),
          ("created the position of","pushed by a wave of popular support",format!("在民意支持的浪潮{}下{}了{title}{}",local("推動","推动"),local("設立","设立"),local("一職","一职"))),
        ] {
          let source=format!("In the early summer of 3, {{{{DFL0}}}} of {{{{DFL1}}}} {verb} {role} {method}.");
          assert_eq!(lookup(&source,simplified),Some(format!("3年初夏，{{{{DFL1}}}}{}{{{{DFL0}}}}{translated}。",local("所屬的","所属的"))),"{source}");
        }
      }
      for source in [
        "{{DFL0}} of {{DFL1}} created the position of mysterywizard as a matter of course",
        "{{DFL0}} of {{DFL1}} created the position of law-giver through violence",
        "{{DFL0}} of {{DFL1}} created the position of law-giver as a matter of course. Unknown aftermath",
        "{{DFL0}} of {{DFL1}} compelled the creation of the position of law-giver through force of argument",
        "{{DFL0}} became the law-giver of {{DFL1}} with extra powers",
      ] {assert!(lookup(source,simplified).is_none(),"{source}");}
    }
  }
  #[test]
  fn verified_subject_biographies_preserve_birth_parents_and_unique_kind() {
    for simplified in [false,true] {
      let term=|s:&str| match s {
        "DFL_LEGENDS_RACE:human"=>Some(if simplified{"人类"}else{"人類"}.to_owned()),
        "DFL_LEGENDS_RACE:dragon"=>Some(if simplified{"龙"}else{"龍"}.to_owned()),
        "DFL_LEGENDS_RACE:giant grizzly bear"=>Some("巨型灰熊".to_owned()), _=>None,
      };
      for (source,hant,hans) in [
        ("{{DFT0}} was a human born in 55. He was the third eldest son of {{DFL0}} and {{DFL1}}",
         "{{DFT0}}是人類，生於55年。他是{{DFL0}}與{{DFL1}}的第三子。","{{DFT0}}是人类，生于55年。他是{{DFL0}}与{{DFL1}}的第三子。"),
        ("{{DFT0}} was a human born in 55. She was the only daughter of {{DFL0}} and {{DFL1}}",
         "{{DFT0}}是人類，生於55年。她是{{DFL0}}與{{DFL1}}的獨生女。","{{DFT0}}是人类，生于55年。她是{{DFL0}}与{{DFL1}}的独生女。"),
        ("{{DFT0}} was a human born in 0", "{{DFT0}}是人類，生於0年。","{{DFT0}}是人类，生于0年。"),
        ("{{DFT0}} was a giant grizzly bear", "{{DFT0}}是巨型灰熊。","{{DFT0}}是巨型灰熊。"),
        ("{{DFT0}} was a dragon. He was the only one of his kind. {{DFL0}} was associated with wealth and fire",
         "{{DFT0}}是龍。他是其種類中唯一的個體。{{DFL0}}與財富及火有關。","{{DFT0}}是龙。他是其种类中唯一的个体。{{DFL0}}与财富及火有关。"),
        ("{{DFT0}} was a dragon. She was the only one of her kind", "{{DFT0}}是龍。她是其種類中唯一的個體。","{{DFT0}}是龙。她是其种类中唯一的个体。"),
        ("{{DFT0}} was a dragon. It was the only one of its kind", "{{DFT0}}是龍。牠是其種類中唯一的個體。","{{DFT0}}是龙。它是其种类中唯一的个体。"),
      ] {
        assert_eq!(super::lookup_with_terms(source,&term,simplified).as_deref(),Some(if simplified{hans}else{hant}),"{source}");
      }
      for bad in [
        "{{DFT0}} was a unknown beast born in 55",
        "{{DFT0}} was a human born in -1", "{{DFT0}} was a human born in 55 extra",
        "{{DFT0}} was a human born in 55. He was the third eldest daughter of {{DFL0}} and {{DFL1}}",
        "{{DFT0}} was a human born in 55. She was the third eldest son of {{DFL0}} and {{DFL1}}",
        "{{DFT0}} was a human born in 55. He was the third eldest son of {{DFL0}}",
        "{{DFT0}} was a dragon. He was the only one of her kind",
        "{{DFT0}} was a dragon. He was the only one of his kind. Unknown trailing prose",
        "{{DFT0}} was a dragon. He was the only one of his kind. {{DFL0}} was associated with unknown and fire",
        "{{DFT0}} was a dragon. He was the only one of his kind. {{DFL0}} was associated with wealth and fire and wealth",
        "{{DFL0}} was a human born in 55", "Unverified Name was a human born in 55",
        "In 55, {{DFT0}} was a human", "{{DFT0}} was a human. {{DFT1}} became king",
      ] {assert!(super::lookup_with_terms(bad,&term,simplified).is_none(),"{bad}");}
    }
    for target in ["human","[C:1]人類","錯\n誤","人類�","{{DFL0}}",""] {
      assert!(super::lookup_with_terms("{{DFT0}} was a human born in 55",&|_|Some(target.into()),false).is_none());
    }
  }
  #[test]
  fn trading_outcomes_and_unlinked_animals_are_not_lost() {
    for (source,hant,hans) in [
      ("In the early winter of 74, {{DFL0}} did poorly trading birch beds from {{DFL1}} to {{DFL2}}",
       "74年初冬，{{DFL0}}從{{DFL1}}向{{DFL2}}交易樺木床，成果不佳。", "74年初冬，{{DFL0}}从{{DFL1}}向{{DFL2}}交易桦木床，成果不佳。"),
      ("In the early winter of 77, {{DFL0}} broke even trading alder beds from {{DFL1}} to {{DFL2}}",
       "77年初冬，{{DFL0}}從{{DFL1}}向{{DFL2}}交易榿木床，收支平衡。", "77年初冬，{{DFL0}}从{{DFL1}}向{{DFL2}}交易桤木床，收支平衡。"),
      ("In the midwinter of 13, {{DFL0}} devoured a eagle of {{DFL1}} in {{DFL2}}",
       "13年仲冬，{{DFL0}}在{{DFL2}}吞食了{{DFL1}}的一隻鷹。", "13年仲冬，{{DFL0}}在{{DFL2}}吞食了{{DFL1}}的一只鹰。"),
    ] {
      for (simplified,want) in [(false,hant),(true,hans)] {
        let term=|s:&str|match (s,simplified) {
          ("birch beds",false)=>Some("樺木床".into()),("birch beds",true)=>Some("桦木床".into()),
          ("alder beds",false)=>Some("榿木床".into()),("alder beds",true)=>Some("桤木床".into()),
          ("eagle",false)=>Some("鷹".into()),("eagle",true)=>Some("鹰".into()),_=>None,
        };
        assert_eq!(super::lookup_with_terms(source,&term,simplified).as_deref(),Some(want),"{source}");
      }
    }
    for source in ["{{DFL0}} did poorly trading unknown beds from {{DFL1}} to {{DFL2}}",
      "{{DFL0}} broke even trading birch beds from {{DFL1}} to {{DFL2}}. Unknown event.",
      "{{DFL0}} devoured a unknown animal of {{DFL1}} in {{DFL2}}"] {
      assert!(super::lookup_with_terms(source,&|_|None,false).is_none());
    }
    for bad in ["partly English","[C:1]錯誤","�","錯\n誤","{{DFT0}}"] {
      assert!(super::lookup_with_terms("{{DFL0}} broke even trading alder beds from {{DFL1}} to {{DFL2}}",
        &|_|Some(bad.into()),false).is_none());
    }
  }
  #[test]
  fn local_literal_slots_preserve_text_without_certifying_click_targets() {
    for (source,hant,hans) in [
      ("{{DFT0}}, only daughter, b. 95", "{{DFT0}}：獨生女，生於95年。", "{{DFT0}}：独生女，生于95年。"),
      ("In 79, {{DFT0}} married {{DFL0}}", "79年，{{DFT0}}與{{DFL0}}結婚。", "79年，{{DFT0}}与{{DFL0}}结婚。"),
    ] {
      assert_eq!(super::lookup(source,false).as_deref(),Some(hant));
      assert_eq!(super::lookup(source,true).as_deref(),Some(hans));
    }
    for source in ["{{DFT00}}, only daughter, b. 95", "{{DFT64}} only daughter, b. 95",
      "{{DFT0}} married {{DFT0}}", "{{DFX0}} only daughter, b. 95",
      "{{DFT0}}, only daughter, b. 95. Unknown event."] {
      assert!(super::lookup(source,false).is_none(),"{source}");
    }
  }
  #[test]
  fn legends_native_relationships_and_active_occupations_are_complete() {
    for (source,hant,hans) in [
      ("In 73, {{DFL0}} became a merchant in {{DFL1}}", "73年，{{DFL0}}在{{DFL1}}成為商人。", "73年，{{DFL0}}在{{DFL1}}成为商人。"),
      ("In 100, {{DFL0}} became a tavern keeper in {{DFL1}}", "100年，{{DFL0}}在{{DFL1}}成為酒保。", "100年，{{DFL0}}在{{DFL1}}成为酒保。"),
      ("In 92, {{DFL0}} became the master of beasts of {{DFL1}}", "92年，{{DFL0}}成為{{DFL1}}的獸群主管。", "92年，{{DFL0}}成为{{DFL1}}的兽群主管。"),
      ("In 100, {{DFL0}} started working at {{DFL1}} in {{DFL2}}", "100年，{{DFL0}}開始在{{DFL2}}的{{DFL1}}工作。", "100年，{{DFL0}}开始在{{DFL2}}的{{DFL1}}工作。"),
      ("{{DFL0}} object of faithful worship", "{{DFL0}}：虔誠崇拜的對象。", "{{DFL0}}：虔诚崇拜的对象。"),
      ("{{DFL0}} object of worship", "{{DFL0}}：崇拜的對象。", "{{DFL0}}：崇拜的对象。"),
      ("{{DFL0}} deceased spouse, b. 47 d. 80", "{{DFL0}}：已故配偶，生於47年，卒於80年。", "{{DFL0}}：已故配偶，生于47年，卒于80年。"),
      ("{{DFL0}} wife, b. 63", "{{DFL0}}：妻子，生於63年。", "{{DFL0}}：妻子，生于63年。"),
      ("{{DFL0}} husband, b. 63", "{{DFL0}}：丈夫，生於63年。", "{{DFL0}}：丈夫，生于63年。"),
      ("{{DFL0}} lover, b. 61", "{{DFL0}}：戀人，生於61年。", "{{DFL0}}：恋人，生于61年。"),
      ("{{DFL0}} only daughter, b. 95", "{{DFL0}}：獨生女，生於95年。", "{{DFL0}}：独生女，生于95年。"),
      ("{{DFL0}} only son, b. 95", "{{DFL0}}：獨生子，生於95年。", "{{DFL0}}：独生子，生于95年。"),
      ("{{DFL0}} (master of beasts, 92 to present)", "{{DFL0}}（獸群主管，92年至今）。", "{{DFL0}}（兽群主管，92年至今）。"),
      ("{{DFL0}} (merchant, 73 to 92)", "{{DFL0}}（商人，73年至92年）。", "{{DFL0}}（商人，73年至92年）。"),
      ("{{DFL0}} (site occ)", "{{DFL0}}（在此任職）。", "{{DFL0}}（在此任职）。"),
      ("Related Sites", "相關地點", "相关地点"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in ["{{DFL0}} lover, b. 95 d. 94", "{{DFL0}} lover, b. 61 more text",
      "{{DFL0}} (merchant, 92 to 73)", "{{DFL0}} (merchant, 92 to present and later)",
      "{{DFL0}} (merchant, 92 to present to 100)", "{{DFL0}} (merchant, -1 to present)",
      "{{DFL0}} (mysterywizard, 92 to present)", "{{DFL0}} object of unknown worship",
      "{{DFL0}} started working at {{DFL1}} in {{DFL2}}. Unknown event.",
      "Related Sites Unknown event"] {
      assert!(lookup(source,false).is_none(),"{source}");
      assert!(lookup(source,true).is_none(),"{source}");
    }
  }
  #[test]
  fn adventure_dates_preserve_day_year_and_season_without_specific_save_data() {
    for simplified in [false,true] {
      let month=if simplified {"花岗岩月"} else {"花崗岩月"};
      for (day,ordinal) in [(1,"1st"),(2,"2nd"),(3,"3rd"),(11,"11th"),(12,"12th"),(13,"13th"),(15,"15th"),(21,"21st"),(22,"22nd"),(23,"23rd"),(28,"28th")] {
        for year in [0,100,98765] {
          assert_eq!(super::lookup(&format!("{ordinal} Granite, {year}"),simplified),Some(format!("{year}年{month}{day}日")));
          assert_eq!(super::lookup(&format!("{ordinal} Granite, early spring, {year}"),simplified),Some(format!("{year}年初春 {month}{day}日")));
          assert_eq!(super::lookup(&format!("This event occurred on the {ordinal} Granite in the year {year}."),simplified),
            Some(format!("此事件發生於{year}年{month}{day}日。").replace("發生於",if simplified {"发生于"}else{"發生於"})));
        }
      }
      assert_eq!(super::lookup("28th Obsidian, late winter, 2147483647",simplified),Some("2147483647年暮冬 黑曜石月28日".into()));
      for invalid in ["0th Granite, 100","29th Granite, 100","01st Granite, 100","11st Granite, 100",
        "1th Granite, 100","1st Unknown, 100","1st Granite, summer, 100","1st Granite, late winter, 100",
        "1st Granite, -100","1st Granite, 2147483648","1st Granite, 100 trailing",
        "This event occurred on the 1st Granite in the year 100. Unknown sentence.",
        "This event occurred on the 1st Granite in the year 100[C:7:0:0]."] {
        assert!(super::lookup(invalid,simplified).is_none(),"{invalid}");
      }
    }
  }
  use super::*;
  #[test]
  fn active_history_events_preserve_roles_outcomes_and_links() {
    for (source,hant,hans) in [
      ("In the midspring of 6, {{DFL0}} became an enemy of {{DFL1}}",
       "6年仲春，{{DFL0}}與{{DFL1}}成為敵人。", "6年仲春，{{DFL0}}与{{DFL1}}成为敌人。"),
      ("In the midspring of 6, {{DFL0}} attacked {{DFL1}}",
       "6年仲春，{{DFL0}}攻擊了{{DFL1}}。", "6年仲春，{{DFL0}}攻击了{{DFL1}}。"),
      ("{{DFL9}} attacked {{DFL2}} at {{DFL63}}.",
       "{{DFL9}}在{{DFL63}}攻擊了{{DFL2}}。", "{{DFL9}}在{{DFL63}}攻击了{{DFL2}}。"),
      ("In the midspring of 6, {{DFL0}} fought with {{DFL1}} While defeated, the latter escaped unscathed.",
       "6年仲春，{{DFL0}}與{{DFL1}}交戰。後者雖然戰敗，仍毫髮無傷地逃脫。",
       "6年仲春，{{DFL0}}与{{DFL1}}交战。后者虽然战败，仍毫发无伤地逃脱。"),
      ("In the midwinter of 15, {{DFL0}} struck down {{DFL1}} in {{DFL2}}",
       "15年仲冬，{{DFL0}}在{{DFL2}}殺死了{{DFL1}}。", "15年仲冬，{{DFL0}}在{{DFL2}}杀死了{{DFL1}}。"),
      ("{{DFL0}} routed {{DFL1}} of {{DFL2}} and destroyed {{DFL3}}",
       "{{DFL0}}擊潰了來自{{DFL2}}的{{DFL1}}，並摧毀了{{DFL3}}。",
       "{{DFL0}}击溃了来自{{DFL2}}的{{DFL1}}，并摧毁了{{DFL3}}。"),
      ("{{DFL0}} confronted {{DFL1}}", "{{DFL0}}與{{DFL1}}對峙。", "{{DFL0}}与{{DFL1}}对峙。"),
      ("{{DFL0}} devoured {{DFL1}} in {{DFL2}}", "{{DFL0}}在{{DFL2}}吞食了{{DFL1}}。", "{{DFL0}}在{{DFL2}}吞食了{{DFL1}}。"),
      ("{{DFL0}} (enemy)", "{{DFL0}}（敵人）。", "{{DFL0}}（敌人）。"),
      ("{{DFL0}} was a cave.", "{{DFL0}}曾是一座洞穴。", "{{DFL0}}曾是一座洞穴。"),
      ("{{DFL0}} was made a symbol of the monarch by {{DFL1}}",
       "{{DFL1}}將{{DFL0}}定為君主的象徵。", "{{DFL1}}将{{DFL0}}定为君主的象征。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in [
      "{{DFL0}} attacked {{DFL1}}. An unknown event followed.",
      "{{DFL0}} attacked Bob at {{DFL1}}",
      "{{DFL0}} attacked {{DFL1}} at {{DFL1}}",
      "{{DFL0}} fought with {{DFL1}} While defeated, the former escaped unscathed.",
      "{{DFL0}} fought with {{DFL1}} While defeated, the latter escaped injured.",
      "{{DFL0}} routed {{DFL1}} of {{DFL2}} and destroyed {{DFL3}} during something unknown",
      "{{DFL0}} was a cave. Unknown prose.",
      "{{DFL0}} (enemy, 10-9)",
    ] {
      for simplified in [false,true] {assert!(lookup(source,simplified).is_none(),"{source}");}
    }
  }
  #[test]
  fn looting_deaths_and_intrigue_preserve_actor_and_victim() {
    for (source,hant,hans) in [
      ("In the late spring of 88, {{DFL0}} was looted from {{DFL1}} by {{DFL2}} after defeating {{DFL3}}",
       "88年暮春，{{DFL2}}擊敗{{DFL3}}後，從{{DFL1}}掠走了{{DFL0}}。",
       "88年暮春，{{DFL2}}击败{{DFL3}}后，从{{DFL1}}掠走了{{DFL0}}。"),
      ("In 233, {{DFL0}} was looted from {{DFL1}} by {{DFL2}} after murdering {{DFL3}}",
       "233年，{{DFL2}}謀殺{{DFL3}}後，從{{DFL1}}掠走了{{DFL0}}。",
       "233年，{{DFL2}}谋杀{{DFL3}}后，从{{DFL1}}掠走了{{DFL0}}。"),
      ("In the midautumn of 79, {{DFL0}} was shot and killed by {{DFL1}} in {{DFL2}}",
       "79年仲秋，{{DFL0}}在{{DFL2}}被{{DFL1}}射殺。", "79年仲秋，{{DFL0}}在{{DFL2}}被{{DFL1}}射杀。"),
      ("In the midautumn of 79, the bodies of {{DFL0}} and others were horribly mutilated by {{DFL1}} in {{DFL2}}",
       "79年仲秋，{{DFL0}}與其他人的遺體在{{DFL2}}遭{{DFL1}}殘酷毀損。",
       "79年仲秋，{{DFL0}}与其他人的遗体在{{DFL2}}遭{{DFL1}}残酷毁损。"),
      ("In the midspring of 37, {{DFL0}} formed a false friendship with {{DFL1}} in order to extract information in {{DFL2}}",
       "37年仲春，{{DFL0}}假意與{{DFL1}}交好，以便在{{DFL2}}套取情報。",
       "37年仲春，{{DFL0}}假意与{{DFL1}}交好，以便在{{DFL2}}套取情报。"),
      ("In the early autumn of 52, {{DFL0}} attempted to corrupt {{DFL1}} in order to have an agent in {{DFL2}} {{DFL3}} met with {{DFL4}} and, while completely misreading the situation, made a threat. {{DFL5}} valued the law and refused, despite being afraid.",
       "52年初秋，{{DFL0}}試圖拉攏{{DFL1}}，以便在{{DFL2}}安插代理人。{{DFL3}}與{{DFL4}}會面，卻完全誤判形勢，出言威脅。{{DFL5}}雖然害怕，但仍重視法律而拒絕。",
       "52年初秋，{{DFL0}}试图拉拢{{DFL1}}，以便在{{DFL2}}安插代理人。{{DFL3}}与{{DFL4}}会面，却完全误判形势，出言威胁。{{DFL5}}虽然害怕，但仍重视法律而拒绝。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in [
      "{{DFL0}} was looted from {{DFL1}} by {{DFL2}} after defeating {{DFL3}} and then disappeared.",
      "{{DFL0}} was looted from {{DFL1}} by {{DFL2}} after defeating Bob",
      "{{DFL0}} formed a false friendship with {{DFL1}} in order to extract information in {{DFL2}}. Something else happened.",
      "{{DFL0}} was shot and killed by {{DFL1}} in {{DFL1}}",
    ] {assert!(lookup(source,false).is_none(),"{source}");}
  }
  #[test]
  fn bare_lifespans_and_kill_counts_are_distinct_from_relationships() {
    for (source,hant,hans) in [
      ("{{DFL0}} b. 82 d. 157","{{DFL0}}：生於82年，卒於157年。","{{DFL0}}：生于82年，卒于157年。"),
      ("{{DFL0}} b. 0","{{DFL0}}：生於0年。","{{DFL0}}：生于0年。"),
      ("{{DFL0}} d. 233, two kills","{{DFL0}}：卒於233年，擊殺2次。","{{DFL0}}：卒于233年，击杀2次。"),
      ("{{DFL0}} b. 18 d. 82, one kill","{{DFL0}}：生於18年，卒於82年，擊殺1次。","{{DFL0}}：生于18年，卒于82年，击杀1次。"),
      ("{{DFL0}} third eldest daughter, b. 4 d. 82","{{DFL0}}：第三女，生於4年，卒於82年。","{{DFL0}}：第三女，生于4年，卒于82年。"),
      ("{{DFL0}} sixth eldest son, b. 37 d. 79","{{DFL0}}：第六子，生於37年，卒於79年。","{{DFL0}}：第六子，生于37年，卒于79年。"),
      ("{{DFL0}} twentieth eldest daughter, b. 90","{{DFL0}}：第二十女，生於90年。","{{DFL0}}：第二十女，生于90年。"),
      ("Two Kills","擊殺2次","击杀2次"),("One Kill","擊殺1次","击杀1次"),
      ("Twenty-three Kills","擊殺23次","击杀23次"),("157 Kills","擊殺157次","击杀157次"),
      ("Slayer","殺戮者","杀戮者"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in ["{{DFL0}} b. 90 d. 89", "{{DFL0}} b. -1", "{{DFL0}} d. 10000000",
      "{{DFL0}} d. 82, two kills of Bob", "{{DFL0}} d. 82, one kills", "{{DFL0}} d. 82, two kill",
      "{{DFL0}} d. 82, 01 kills", "{{DFL0}} third eldest daughter, b. 5 d. 4", "{{DFL0}} third eldest dragon, b. 5",
      "{{DFL0}} b. 82 {{DFL1}}", "Two Kills. Unknown event", "In 27, Two Kills", "One Kills", "Zero Kills",
      "Twenty-ten Kills", "Twenty-three thousand Kills", "10000000 Kills"] {
      assert!(lookup(source,false).is_none(),"{source}");
    }
  }
  #[test]
  fn remote_claims_and_storage_keep_distance_and_both_places() {
    for (source,hant,hans) in [
      ("In the early autumn of 119, {{DFL0}} was claimed by {{DFL1}} from afar.",
       "119年初秋，{{DFL1}}從遠方宣稱擁有{{DFL0}}。", "119年初秋，{{DFL1}}从远方宣称拥有{{DFL0}}。"),
      ("In 161, {{DFL0}} was stored in {{DFL1}} in {{DFL2}}",
       "161年，{{DFL0}}被存放於{{DFL2}}的{{DFL1}}。", "161年，{{DFL0}}被存放于{{DFL2}}的{{DFL1}}。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant));
      assert_eq!(lookup(source,true).as_deref(),Some(hans));
    }
    for source in ["In 161, {{DFL0}} was stored in {{DFL1}} in {{DFL2}} by an unknown person.",
      "In 119, {{DFL0}} was claimed by {{DFL1}} from afar during a mystery."] {assert!(lookup(source,false).is_none());}
  }
  #[test]
  fn occupations_and_family_metadata_preserve_dates() {
    for (source,hant,hans) in [
      ("In 27, {{DFL0}} became a weaponsmith in {{DFL1}}", "27年，{{DFL0}}在{{DFL1}}成為武器匠。", "27年，{{DFL0}}在{{DFL1}}成为武器匠。"),
      ("In 47, {{DFL0}} stopped being a hunter in {{DFL1}}", "47年，{{DFL0}}不再於{{DFL1}}擔任獵人。", "47年，{{DFL0}}不再于{{DFL1}}担任猎人。"),
      ("In the early winter of 79, {{DFL0}} became the dean of {{DFL1}}", "79年初冬，{{DFL0}}成為{{DFL1}}的院長。", "79年初冬，{{DFL0}}成为{{DFL1}}的院长。"),
      ("{{DFL0}} mother, d. 81", "{{DFL0}}：母親，卒於81年。", "{{DFL0}}：母亲，卒于81年。"),
      ("{{DFL0}} second eldest son, b. 31 d. 79", "{{DFL0}}：次子，生於31年，卒於79年。", "{{DFL0}}：次子，生于31年，卒于79年。"),
      ("{{DFL0}} youngest daughter, b. 68", "{{DFL0}}：幼女，生於68年。", "{{DFL0}}：幼女，生于68年。"),
      ("{{DFL0}} former spouse, b. 18 d. 82", "{{DFL0}}：前配偶，生於18年，卒於82年。", "{{DFL0}}：前配偶，生于18年，卒于82年。"),
      ("{{DFL0}} object of ardent worship", "{{DFL0}}：熱忱崇拜的對象。", "{{DFL0}}：热忱崇拜的对象。"),
      ("{{DFL0}} (former member)", "{{DFL0}}（前成員）。", "{{DFL0}}（前成员）。"),
      ("{{DFL0}} (dean, 79-81)", "{{DFL0}}（院長，79年至81年）。", "{{DFL0}}（院长，79年至81年）。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    for source in ["{{DFL0}} became a mysterywizard in {{DFL1}}", "{{DFL0}} mother, d. -81", "{{DFL0}} mother, d. 81 nonsense", "{{DFL0}} (dean, 79-81-82)", "{{DFL0}} (dean, 81-79)", "{{DFL0}} youngest son, b. 91 d. 80", "{{DFL0}} mother {{DFL1}}", "{{DFL0}} became the @1 of {{DFL2}}"] {assert!(lookup(source,false).is_none(),"{source}");}
  }
  #[test]
  fn seasonal_dates_preserve_year_and_part_of_season() {
    for (date,want) in [("early spring","初春"),("midspring","仲春"),("late spring","暮春"),
      ("early summer","初夏"),("midsummer","仲夏"),("late summer","夏末"),
      ("early autumn","初秋"),("midautumn","仲秋"),("late autumn","深秋"),
      ("early winter","初冬"),("midwinter","仲冬"),("late winter","冬末")] {
      for simplified in [false,true] {
        assert_eq!(lookup(&format!("In the {date} of 73, {{{{DFL0}}}} died."),simplified),Some(format!("73年{want}，{{{{DFL0}}}}死亡了。")));
      }
    }
    for source in ["In the almost spring of 73, {{DFL0}} died.","In the midsummer of -3, {{DFL0}} died.","In the early winter of 99999999, {{DFL0}} died."] {assert!(lookup(source,false).is_none());}
  }
  #[test]
  fn observed_social_and_artifact_events_retain_all_roles() {
    for (source,hant,hans) in [
      ("{{DFL0}} and {{DFL1}} became childhood friends.","{{DFL0}}與{{DFL1}}成為兒時玩伴。","{{DFL0}}与{{DFL1}}成为儿时玩伴。"),
      ("{{DFL0}} and {{DFL1}} became lovers.","{{DFL0}}與{{DFL1}}成為戀人。","{{DFL0}}与{{DFL1}}成为恋人。"),
      ("{{DFL0}} and {{DFL1}} broke up.","{{DFL0}}與{{DFL1}}分手。","{{DFL0}}与{{DFL1}}分手。"),
      ("{{DFL0}} was offered to {{DFL1}} of {{DFL2}} by {{DFL3}}", "{{DFL3}}將{{DFL0}}獻給{{DFL2}}的{{DFL1}}。", "{{DFL3}}将{{DFL0}}献给{{DFL2}}的{{DFL1}}。"),
      ("{{DFL0}} was made a family heirloom by {{DFL1}}", "{{DFL1}}將{{DFL0}}定為傳家寶。", "{{DFL1}}将{{DFL0}}定为传家宝。"),
      ("{{DFL0}} was claimed by {{DFL1}}", "{{DFL1}}宣稱擁有{{DFL0}}。", "{{DFL1}}宣称拥有{{DFL0}}。"),
      ("{{DFL0}} was lost in {{DFL1}}", "{{DFL0}}遺失於{{DFL1}}。", "{{DFL0}}遗失于{{DFL1}}。"),
      ("{{DFL0}} was found in {{DFL1}} by {{DFL2}}", "{{DFL2}}在{{DFL1}}找到了{{DFL0}}。", "{{DFL2}}在{{DFL1}}找到了{{DFL0}}。"),
      ("{{DFL0}} was struck down by {{DFL1}} with {{DFL2}} in {{DFL3}}", "{{DFL0}}在{{DFL3}}被{{DFL1}}以{{DFL2}}殺死。", "{{DFL0}}在{{DFL3}}被{{DFL1}}以{{DFL2}}杀死。"),
      ("{{DFL0}} was taken by a fey mood in {{DFL1}}", "{{DFL0}}在{{DFL1}}陷入了神秘的創作情緒。", "{{DFL0}}在{{DFL1}}陷入了神秘的创作情绪。"),
    ] {
      assert_eq!(lookup(source,false).as_deref(),Some(hant),"{source}");
      assert_eq!(lookup(source,true).as_deref(),Some(hans),"{source}");
    }
    assert!(lookup("{{DFL0}} and {{DFL1}} became lovers. Unknown event.",false).is_none());
    assert!(lookup("{{DFL0}} was offered to {{DFL1}} of {{DFL2}} by {{DFL3}} after unknown event",false).is_none());
  }
  #[test]
  fn dates_and_links_survive_reordering() {
    assert_eq!(lookup("In 25, {{DFL0}} was created in {{DFL1}} by {{DFL2}}",false).as_deref(),Some("25年，{{DFL2}}在{{DFL1}}創造了{{DFL0}}。"));
    assert_eq!(lookup("In 25, {{DFL0}} was created in {{DFL1}} by {{DFL2}}",true).as_deref(),Some("25年，{{DFL2}}在{{DFL1}}创造了{{DFL0}}。"));
    assert_eq!(lookup("In 125, {{DFL0}} was created by {{DFL1}}",false).as_deref(),Some("125年，{{DFL1}}創造了{{DFL0}}。"));
    assert_eq!(lookup("In 9, {{DFL0}} was stored in {{DFL1}} by {{DFL2}}.",true).as_deref(),Some("9年，{{DFL2}}将{{DFL0}}存放于{{DFL1}}。"));
    assert_eq!(lookup("In the year 302, {{DFL0}} married {{DFL1}} in {{DFL2}}.",false).as_deref(),Some("302年，{{DFL0}}與{{DFL1}}在{{DFL2}}結婚。"));
    assert_eq!(lookup("{{DFL0}} has been found dead.",false).as_deref(),Some("{{DFL0}}被發現已經死亡。"));
    assert_eq!(lookup("{{DFL0}} is taken by a fey mood!",false).as_deref(),Some("{{DFL0}}陷入了神秘的創作情緒。"));
    assert!(lookup("{{DFL+1}} has been found dead.",false).is_none());
    assert!(lookup("{{DFL0}} married @1.",false).is_none());
  }
  #[test]
  fn unknown_or_malformed_narratives_never_partially_translate() {
    for s in ["In 1, Bob was created by Alice.","In 1, {{DFL0}} was created by {{DFL64}}", "In 1, {{DFL00}} died.","In 1, {{DFL0}} was stored in {{DFL1}} by {{DFL1}}", "In 1, {{DFL0}} died. Something unknown happened.","In 999999999999999, {{DFL0}} died.","{{DFL0}} has been found dead.[C:evil]", "{{DFL0}} was elected king"] {assert!(lookup(s,false).is_none(),"{s}");}
    assert!(lookup(&"x".repeat(9000),false).is_none());
  }
}
