//! Independent structured summaries. Names are opaque values, never AI tokens.
use serde::Deserialize;
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Event { pub id:i32,pub kind:String,pub year:i32,#[serde(default)]pub references:Vec<Reference> }
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Reference {pub role:String,pub id:i32,pub name:String}
pub fn render(event:&Event)->anyhow::Result<String> {
    render_language(event,None)
}
fn render_language(event:&Event,language:Option<&str>)->anyhow::Result<String> {
    let localized=|text:&str|language.map(|lang|crate::chinese::localized(text,lang)).unwrap_or_else(||text.to_owned());
    anyhow::ensure!(event.kind.len()<=96 && event.kind.bytes().all(|b|b.is_ascii_uppercase() || b==b'_' || b.is_ascii_digit()),"invalid event kind");
    anyhow::ensure!(event.references.len()<=24,"too many references");
    let title=match event.kind.as_str() {
        "HIST_FIGURE_DIED"=>"人物死亡","CREATED_SITE"=>"建立據點","WAR_ATTACKED_SITE"=>"進攻據點",
        "WAR_DESTROYED_SITE"=>"摧毀據點","WAR_FIELD_BATTLE"=>"野戰","WAR_PEACE_ACCEPTED"=>"接受和平",
        "WAR_PEACE_REJECTED"=>"拒絕和平","WAR_PLUNDERED_SITE"=>"掠奪據點","WAR_SITE_TAKEN_OVER"=>"佔領據點",
        "ADD_HF_ENTITY_LINK"=>"加入組織","REMOVE_HF_ENTITY_LINK"=>"離開組織","CHANGE_HF_JOB"=>"改變職業",
        "CHANGE_HF_STATE"=>"人物狀態改變","ADD_HF_HF_LINK"=>"建立人物關係","REMOVE_HF_HF_LINK"=>"解除人物關係",
        "ARTIFACT_CREATED"=>"製作神器","ARTIFACT_LOST"=>"遺失神器","ARTIFACT_FOUND"=>"發現神器",
        "ARTIFACT_POSSESSED"=>"持有神器","ARTIFACT_HIDDEN"=>"藏匿神器","ARTIFACT_RECOVERED"=>"取回神器",
        "ARTIFACT_DROPPED"=>"丟下神器","ARTIFACT_TRANSFORMED"=>"改造神器","ARTIFACT_COPIED"=>"複製神器",
        "ENTITY_CREATED"=>"建立組織","ENTITY_INCORPORATED"=>"組織合併","ENTITY_ACTION"=>"組織活動",
        "CREATED_BUILDING"=>"建立建築","REPLACED_BUILDING"=>"替換建築","SITE_DIED"=>"據點滅亡",
        "SITE_RETIRED"=>"據點退出活動","RECLAIM_SITE"=>"收復據點","HF_DESTROYED_SITE"=>"人物摧毀據點",
        "HIST_FIGURE_ABDUCTED"=>"人物遭綁架","HIST_FIGURE_REVIVED"=>"人物復活","BODY_ABUSED"=>"遺體遭辱",
        "FIRST_CONTACT"=>"首次接觸","FIRST_CONTACT_FAILED"=>"首次接觸失敗","DIPLOMAT_LOST"=>"外交官失蹤",
        "MASTERPIECE_CREATED_ITEM"=>"製作傑作","MASTERPIECE_LOST"=>"傑作遺失","HF_LEARNS_SECRET"=>"得知秘密",
        "HF_DOES_INTERACTION"=>"施展能力","HF_WOUNDED"=>"人物受傷","HF_NEW_PET"=>"取得寵物",
        _=>"歷史事件",
    };
    let year=if event.year<0 {"年代不詳".into()}else{format!("{} 年",event.year)};
    let mut out=localized(&format!("{year}：{title}"));
    if title=="歷史事件" {out.push_str(&format!("（{}）",event.kind))}
    let mut seen=std::collections::HashSet::new();
    for reference in &event.references {
        anyhow::ensure!(reference.name.len()<=1024 && !reference.name.chars().any(|c|c.is_control()),"invalid reference name");
        if reference.id<0 || !seen.insert((&reference.role,reference.id)) {continue}
        let label=match reference.role.as_str() {
            "figure"=>"人物","victim"=>"死者","slayer"=>"殺害者","creator"=>"創作者","builder"=>"建造者",
            "target"=>"對象","entity"=>"組織","site"=>"據點","artifact"=>"神器",_=>continue,
        };
        let name=if reference.name.is_empty() {format!("#{0}",reference.id)} else {reference.name.clone()};
        out.push_str(&localized(&format!("；{label}：")));
        out.push_str(&name);
    }
    Ok(out)
}
#[unsafe(no_mangle)]
extern "C" fn history_event_render(state:*mut std::ffi::c_void)->i32 {
    let value=lua53_sys::check_string(state,1);
    let result=if value.len()<=32768 {serde_json::from_str::<Event>(&value).ok().and_then(|event|render_language(&event,Some(&crate::lang::current_lang_tag())).ok())}else{None};
    if let Some(text)=result {lua53_sys::push_string(state,&text)}
    else {lua53_sys::push_nil(state)};1
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]fn typed_death_preserves_names_and_does_not_invent_missing_people() {
        let event=Event{id:12,year:250,kind:"HIST_FIGURE_DIED".into(),references:vec![
            Reference{role:"victim".into(),id:10,name:"Urist「𠮷」".into()},Reference{role:"slayer".into(),id:-1,name:"".into()}]};
        assert_eq!(render(&event).unwrap(),"250 年：人物死亡；死者：Urist「𠮷」");
    }
    #[test]fn unknown_events_keep_identity_and_reject_controls() {
        let mut event=Event{id:1,year:-1,kind:"NEW_EVENT".into(),references:vec![]};
        assert_eq!(render(&event).unwrap(),"年代不詳：歷史事件（NEW_EVENT）");
        event.references.push(Reference{role:"figure".into(),id:2,name:"invalid\nname".into()});
        assert!(render(&event).is_err());
    }
    #[test]fn simplified_templates_preserve_opaque_proper_names() {
        let event=Event{id:1,year:10,kind:"HIST_FIGURE_DIED".into(),references:vec![
            Reference{role:"victim".into(),id:1,name:"鐵匠𠮷".into()}]};
        assert!(render_language(&event,Some("zh-Hans")).unwrap().ends_with("死者：鐵匠𠮷"));
    }
}
