//! Opt-in audit against a built package, with empty temporary player state.
use df_local_zh_broker::{service::App,common::{atomic,convert},settings::defaults};
use serde_json::{json,Value};
use std::sync::atomic::Ordering;
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_current_personality_quotes_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,target) in [
      ("\"Yes, I want more.  Is that so bad?\"","「沒錯，我還想要更多。這有那麼糟嗎？」"),
      ("\"I'm feel like I'm about to snap.\"","「我覺得自己快要崩潰了。」"),
      ("\"Who cares what they think?\"","「誰在乎他們怎麼想？」"),
      ("\"I consider laws to be more of a suggestion than anything.\"","「對我來說，法律更像是建議。」"),
      ("\"It's not perfect, but it's good enough.  Why fret about it?\"","「雖然不完美，但已經夠好了。何必為此煩惱？」"),
      ("\"That isn't funny.\"","「那一點也不好笑。」"),
      ("\"Try to focus on the practical side of the matter.\"","「試著專注於事情實際的一面。」"),
    ] {
      // Packaging uses phrase-aware OpenCC; Rust's fallback conversion is character-only.
      let expected=if language=="zh-Hans" && source=="\"Try to focus on the practical side of the matter.\"" {
        "「试着专注于事情实际的一面。」".to_owned()
      } else { convert(target,language) };
      assert_eq!(app.translate(source,language,"",0).await.unwrap(),expected,"{language}: {source}");
    }
    assert!(app.translate("\"Yes, I want more.  Is that so bad? Unreviewed trailing prose.\"",language,"",0).await.is_err());
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_resident_compound_appearance_and_material_preferences_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,target) in [
      ("His very long beard is braided.  His medium-length sideburns are neatly combed.  His medium-length moustache is neatly combed.  His hair is clean-shaven.  His ears are very splayed out.  His teeth are tangled.  He has a scratchy voice.  He has very low cheekbones, and he has a narrow chin.  His nose bridge is convex.  His slightly wide-set narrow cobalt eyes are sunken.  His eyelashes are extremely long.  His hair is charcoal.  His skin is pale chestnut.  His nose is slightly hooked.",
       "他的長長的鬍鬚編成辮子。  他的中等長度的鬢角梳理得很整齊。  他的中等長度的髭鬚梳理得很整齊。  他的頭髮剃得乾乾淨淨。  他的耳朵大幅向外張開。  他的牙齒交錯不齊。  他的聲音粗啞。  他的顴骨很低，且下巴狹窄。  他的鼻樑向外凸起。  他的間距略寬且狹長的鈷藍色眼睛深陷。  他的睫毛極長。  他的頭髮呈木炭灰。  他的皮膚呈淡栗色。  他的鼻子略呈鉤狀。"),
      ("{DWARF_NAME} likes gypsum, gold, blue jade, black-cap wood, silvery gibbon leather, cotton fabric, thrones, ballista parts, guineafowls for their social nature, the words of {PREF_NAME_1}, the sound of {PREF_NAME_2} and the sight of {PREF_NAME_3}.  When possible, he prefers to consume creepy crawler, maize beer and rambutan seeds.  He absolutely detests blood gnats.  ",
       "{DWARF_NAME}喜歡軟石膏、金、藍翡翠、黑菇木、銀白長臂猿皮革、棉布、王座、弩炮部件、珍珠雞（合群的天性）、{PREF_NAME_1}的文字、{PREF_NAME_2}的聲音與{PREF_NAME_3}的樣貌。  條件允許時，他偏好食用恐怖爬行者、玉米啤酒與紅毛果種子。  他極其厭惡血飛蟲。  "),
      ("Disdains self-control","輕視自制"),("Greedy","貪婪"),
      ("Emotionally distant","情感疏離"),("Vain","自戀"),("Recovers slowly","恢復緩慢"),
      ("\"I go with the flow sometimes.\"","「我有時會順其自然。」"),
    ] {
      assert_eq!(app.translate(source,language,"",0).await.unwrap(),convert(target,language),"{language}: {source}");
    }
    for source in ["He has very low cheekbones, and she has a narrow chin.",
      "He has very low cheekbones, and he has an unknown chin.",
      "{DWARF_NAME} likes unknown wood and gold."] {
      assert!(app.translate(source,language,"",0).await.is_err(),"Unsafe resident fallback: {source}");
    }
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_resident_appearance_and_poetry_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,target) in [
      ("His sideburns are clean-shaven.  His long moustache is neatly combed.  His emerald eyes are slightly wide-set.",
       "他的鬢角剃得乾乾淨淨。  他的長長的髭鬚梳理得很整齊。  他的祖母綠色眼睛間距略寬。"),
      ("{DWARF_NAME} likes warthog hoof, blue peafowls for their enormous fan tails and the words of {PREF_NAME_1}.",
       "{DWARF_NAME}喜歡疣豬蹄、藍孔雀（巨大的扇形尾羽）與{PREF_NAME_1}的文字。"),
    ] {
      assert_eq!(app.translate(source,language,"",0).await.unwrap(),convert(target,language),"{language}: {source}");
    }
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_combat_combinations_translate_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,target) in [
      ("slash/iron scimitar","斬擊／鐵短彎刀"), ("stab/iron scimitar","刺擊／鐵短彎刀"),
      ("slap/flat/iron scimitar","拍擊／平面／鐵短彎刀"),
      ("strike/pommel/iron scimitar","打擊／柄頭／鐵短彎刀"),
      ("strike/copper shield","打擊／銅尖盾"),
      ("punch/left hand","拳擊／左手"), ("punch/right hand","拳擊／右手"),
      ("kick/left foot","踢擊／左腳"), ("kick/right foot","踢擊／右腳"),
      ("Attack right lower leg:","攻擊右小腿："), ("Attack right foot:","攻擊右腳："),
    ] {
      assert_eq!(app.translate(source,language,"",0).await.unwrap(),convert(target,language),"{language}: {source}");
    }
    for source in ["slash/unknown weapon", "strike/flat/unknown weapon", "Attack unknown body:"] {
      assert!(app.translate(source,language,"",0).await.is_err(),"Unsafe combat fallback: {source}");
    }
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_appearance_preserves_body_context_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  let source="Her very long hair is neatly combed.  Her teeth are tangled.  Her nose bridge is convex.  Her cobalt eyes are sunken.  She has very low cheekbones.  Her somewhat narrow ears are splayed out.  Her head is broad.  Her nose is somewhat narrow.  Her hair is burnt sienna.  Her skin is brown.";
  let target="她的長長的頭髮梳理得很整齊。  她的牙齒交錯不齊。  她的鼻樑向外凸起。  她的鈷藍色眼睛深陷。  她的顴骨很低。  她的略窄的耳朵向外張開。  她的頭部寬闊。  她的鼻子略窄。  她的頭髮呈焦赭色。  她的皮膚呈棕色。";
  for language in ["zh-Hant","zh-Hans"] {
    let independent="Her sunken narrow copper eyes are incredibly close-set.  Her somewhat tall ears are fuse-lobed.  Her nose is hooked.  She has very low cheekbones.  She has a scratchy voice.  Her quite dense hair is curly.  Her long hair is arranged in double braids.  She is average in size.  Her somewhat short head is somewhat narrow.  Her eyelashes are short.  Her hair is ochre.  Her skin is pale chestnut.";
    let independent_target="她的深陷狹長的銅色眼睛間距極為狹窄。  她的略高的耳朵耳垂貼連。  她的鼻子呈鉤狀。  她的顴骨很低。  她的聲音粗啞。  她的相當濃密的頭髮捲曲。  她的長髮編成雙辮。  她體型中等。  她的略短的頭部略顯狹窄。  她的睫毛很短。  她的頭髮呈赭黃色。  她的皮膚呈淡栗色。";
    assert_eq!(app.translate(independent,language,"",0).await.unwrap(),convert(independent_target,language));
    let additional="Her somewhat splayed out ears have great swinging lobes.  She has a grating, raspy voice.  Her raw umber eyes are bulging.  Her nose bridge is very convex.  She has very low cheekbones.  Her hair is clean-shaven.  Her eyelashes are extremely long.  Her nose is slightly hooked.  Her hair is goldenrod.  Her skin is pale chestnut.";
    let additional_target="她的略向外張開的耳朵有又大又晃動的耳垂。  她的聲音刺耳而沙啞。  她的生赭色眼睛向外凸出。  她的鼻樑明顯向外凸起。  她的顴骨很低。  她的頭髮剃得乾乾淨淨。  她的睫毛極長。  她的鼻子略呈鉤狀。  她的頭髮呈金麒麟黃。  她的皮膚呈淡栗色。";
    assert_eq!(app.translate(additional,language,"",0).await.unwrap(),convert(additional_target,language));
    for (possessive,pronoun,zh) in [("Her","She","她"),("His","He","他"),("Its","It","牠")] {
      let source=source.replace("Her",possessive).replace("She",pronoun);
      let zh=if language=="zh-Hans" && zh=="牠" {"它"}else{zh};
      assert_eq!(app.translate(&source,language,"",0).await.unwrap(),convert(&target.replace("她",zh),language),"{language}: {source}");
    }
    for source in ["She is unknown in size.","Her ears are arranged in double braids.","Her cobalt eyes are neatly combed.","Her mysterious hair is neatly combed.",
      "Her cobalt eyes are sunken. Unknown trailing prose.","Her cobalt eyes is sunken."] {
      assert!(app.translate(source,language,"",0).await.is_err(),"Unsafe appearance fallback: {source}");
    }
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="diagnostic, not a coverage gate; requires DF_OFFLINE_PACKAGE, DF_RAW_CORPUS and DF_RAW_BROKER_OUTPUT"]
async fn packaged_broker_raw_corpus_diagnostic() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let corpus:Value=serde_json::from_slice(&std::fs::read(std::env::var("DF_RAW_CORPUS").unwrap()).unwrap()).unwrap();
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  let mut samples=Vec::new();
  for language in ["zh-Hant","zh-Hans"] {
    for (page,row) in corpus["pages"].as_object().unwrap() {
      for value in row["sources"].as_array().unwrap() {
        let source=value.as_str().unwrap();let start=std::time::Instant::now();
        let result=app.translate(source,language,"",0).await;
        let (translation,error)=match result {Ok(value)=>(Some(value),None),Err(error)=>(None,Some(error.to_string()))};
        samples.push(json!({"page":page,"language":language,"source":source,"translation":translation,
          "error":error,"ms":start.elapsed().as_secs_f64()*1000.0}));
      }
    }
  }
  assert!(!samples.is_empty());
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
  atomic(std::path::Path::new(&std::env::var("DF_RAW_BROKER_OUTPUT").unwrap()),&json!({
    "scope":"Broker raw fragment diagnostic, not whole-game or visual acceptance",
    "apiRequests":0,"samples":samples})).unwrap();
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_item_diamonds_are_materials_and_artwork_diamonds_are_shapes() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,hant,hans) in [
      ("This is an iron battle axe. It is encrusted with diamonds. It is encircled with bands of silver and gold.","這是鐵戰斧。 它鑲嵌著鑽石。 它環繞著銀與金飾帶。","这是铁战斧。 它镶嵌着钻石。 它环绕着银与金饰带。"),
      ("On the item is an image of diamonds in diamond.","物品上有以鑽石製成的菱形圖像。","物品上有以钻石制成的菱形图像。"),
      ("On the item is an image of diamonds in silver.","物品上有以銀製成的菱形圖像。","物品上有以银制成的菱形图像。"),
      ("diamonds","菱形","菱形"),
    ] {assert_eq!(app.translate(source,language,"",0).await.unwrap(),if language=="zh-Hans" {hans}else{hant},"{language}: {source}");}
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE path"]
async fn packaged_preferences_preserve_botanical_context_without_ai() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  for language in ["zh-Hant","zh-Hans"] {
    for (source,hant,hans) in [
      ("{DWARF_NAME} likes ash for their autumn coloration.","{DWARF_NAME}喜歡白蠟樹（秋季的色彩）。","{DWARF_NAME}喜欢白蜡树（秋季的色彩）。"),
      ("{DWARF_NAME} likes chestnut for their chestnuts.","{DWARF_NAME}喜歡板栗樹（栗子）。","{DWARF_NAME}喜欢板栗树（栗子）。"),
      ("{DWARF_NAME} likes eggplant for their fruit.","{DWARF_NAME}喜歡茄子（果實）。","{DWARF_NAME}喜欢茄子（果实）。"),
    ] {assert_eq!(app.translate(source,language,"",0).await.unwrap(),if language=="zh-Hans"{hans}else{hant},"{source}");}
    assert!(app.translate("{DWARF_NAME} likes ash for their unknown experimental trait.",language,"",0).await.is_err());
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
}
#[tokio::test]
#[ignore="requires DF_OFFLINE_PACKAGE and DF_OFFLINE_CORPUS paths"]
async fn packaged_personality_without_ai_or_learned_cache() {
  let package=std::path::PathBuf::from(std::env::var("DF_OFFLINE_PACKAGE").unwrap());
  let corpus:Value=serde_json::from_slice(&std::fs::read(std::env::var("DF_OFFLINE_CORPUS").unwrap()).unwrap()).unwrap();
  let d=tempfile::tempdir().unwrap();
  let mut settings=defaults();settings["apiEnabled"]=json!(false);settings["officialAutoDownload"]=json!(false);
  atomic(&d.path().join("settings.json"),&json!({"version":1,"defaults":settings,"saves":{}})).unwrap();
  let app=App::load(&package.join("broker/config.json"),d.path()).unwrap();
  let mut results=Vec::new();let mut missing=0;
  for language in ["zh-Hant","zh-Hans"] {
    let pages=corpus.get("pages").unwrap_or(&corpus);
    for (page,row) in pages.as_object().unwrap() {
      for source in row["sources"].as_array().unwrap() {
        let source=source.as_str().unwrap();
        if !source.bytes().any(|b|b.is_ascii_alphabetic()){continue;}
        let now=std::time::Instant::now();
        let result=app.translate(source,language,"",0).await.ok();
        if result.is_none(){missing+=1;println!("MISS {language} {page}: {source}");}
        results.push(json!({"page":page,"language":language,"source":source,"translation":result,"ms":now.elapsed().as_secs_f64()*1000.0}));
      }
    }
    assert_eq!(app.translate("Mason",language,"",0).await.unwrap(),convert("石匠",language));
  }
  assert_eq!(app.pool.requests.load(Ordering::Relaxed),0);
  if let Ok(output)=std::env::var("DF_OFFLINE_OUTPUT") {atomic(std::path::Path::new(&output),&json!({"missing":missing,"samples":results,"apiRequests":0})).unwrap();}
  assert_eq!(missing,0,"Incomplete local corpus; inspect MISS records");
}
