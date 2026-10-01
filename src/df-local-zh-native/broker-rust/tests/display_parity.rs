use df_local_zh_broker::{
  common::*,
  display::{native_rows, role},
};
use serde_json::json;
use std::collections::HashSet;

#[test]
fn color_aliases_and_latest_fingerprint_remain_local_and_bilingual() {
  let rows = vec![
    json!({"original":"He is tired.","translation":"他很累。","fingerprint":"old","language":"zh-Hant","kind":"plain","status":"translated"}),
    json!({"original":"[C:2:0:1]L123___","translation":"[C:2:0:1]樂觀","fingerprint":"new","language":"zh-Hant","kind":"markup","status":"translated"}),
    json!({"original":"He is calm.","translation":"他很冷靜。","fingerprint":"new","language":"zh-Hant","kind":"plain","status":"translated"}),
    json!({"original":"[C:2:0:1]L456___","translation":"[C:1:0:1]不安全","fingerprint":"new","language":"zh-Hant","kind":"markup","status":"translated"}),
  ];
  let (plain, unit) = native_rows(&rows, &HashSet::new(), "zh-Hans");
  assert!(plain.is_empty());
  assert_eq!(
    unit["sources"],
    json!([{"text":"He is calm.","translation":"他很冷静。"}])
  );
  assert_eq!(
    unit["fragments"],
    json!([{"translation":"乐观","color":66,"key":"L123___"}])
  );
}

#[test]
fn legends_roles_use_existing_fixed_race_rules_without_api() {
  let races = json!({"dwarf":"矮人","toad man":"蟾蜍人"});
  assert_eq!(
    role("female dwarven necromancer", &races, "zh-Hant").unwrap(),
    "女性矮人死靈法師"
  );
  assert_eq!(
    role("female dwarven necromancer", &races, "zh-Hans").unwrap(),
    "女性矮人死灵法师"
  );
  assert_eq!(role("toad woman", &races, "zh-Hant").unwrap(), "蟾蜍人");
  assert_eq!(role("force", &races, "zh-Hant").unwrap(), "力量");
  assert!(role("invented role", &races, "zh-Hant").is_err());
}

#[tokio::test]
async fn broker_emits_small_unit_file_at_same_revision() {
  let d = tempfile::tempdir().unwrap();
  atomic(&d.path().join("config.json"), &json!({})).unwrap();
  let app = df_local_zh_broker::service::App::load(&d.path().join("config.json"), &d.path().join("state")).unwrap();
  atomic(
    &app.root.join("active-context.json"),
    &json!({"version":1,"world":"fixture","language":"zh-Hant"}),
  )
  .unwrap();
  atomic(
    &app.runtime.join("world-names.json"),
    &json!({"world":"fixture","entities":[]}),
  )
  .unwrap();
  app.prewarm().unwrap();
  let bulk = read_json(&app.runtime.join("native-prewarm.json"), 1024 * 1024).unwrap();
  let small = read_json(&app.runtime.join("native-prewarm-unit.json"), 1024 * 1024).unwrap();
  assert_eq!(bulk["revision"], small["revision"]);
  assert_eq!(bulk["unit"], small["unit"]);
}
