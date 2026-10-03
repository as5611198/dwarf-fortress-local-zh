use crate::bounded::BoundedMap;
use crate::{
  common::*,
  equipment::Terms,
  official::Official,
  provider::Pool,
  settings::{Settings, clipboard},
  shared::Shared,
};
use anyhow::{Result, bail, ensure};
use serde_json::{Value, json};
use std::{
  collections::{HashMap, HashSet},
  path::{Path, PathBuf},
  sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
  },
  time::{Duration, Instant},
};
use tokio::sync::watch;
type Dict = HashMap<String, String>;
type Pending = HashMap<String, watch::Receiver<Option<(bool, String)>>>;
pub struct App {
  pub source: PathBuf,
  pub root: PathBuf,
  pub runtime: PathBuf,
  pub config: Value,
  pub settings: Arc<Mutex<Settings>>,
  pub official: Arc<Official>,
  pub pool: Arc<Pool>,
  pub shared: Arc<Shared>,
  builtins: HashMap<String, Dict>,
  glossaries: HashMap<String, Value>,
  name_dictionary: Value,
  races: Value,
  cache: Mutex<BoundedMap<String,String>>,
  fixed: HashMap<String, Dict>,
  pending: Mutex<Pending>,
  journal: Mutex<()>,
  equipment: HashMap<String, Terms>,
  pub runtime_active: AtomicUsize,
  pub published: AtomicUsize,
  pub failed: AtomicUsize,
  pub attempted: AtomicUsize,
  runtime_snapshot: Mutex<Value>,
  registry_cache: Mutex<(Option<(std::time::SystemTime,u64)>,Arc<Value>)>,
  prewarm_signature: Mutex<String>,
}
struct PendingGuard { app: Arc<App>, key: String }
impl Drop for PendingGuard {
  fn drop(&mut self) { self.app.pending.lock().unwrap().remove(&self.key); }
}
pub struct Prepared {
  pub text: String,
  pub kind: String,
  pub numbers: Vec<String>,
  pub entities: Vec<String>,
}
impl Prepared {
  pub fn restore(&self, translation: &str, source: &str) -> Result<String> {
    let s = re(r"\{\{DF([NE])(\d+)\}\}").replace_all(translation, |c: &regex::Captures| {
      c[2].parse::<usize>().ok().and_then(|n| if &c[1] == "N" {
        self.numbers.get(n)
      } else { self.entities.get(n) })
      .cloned()
      .unwrap_or(c[0].into())
    });
    if braced_item(source).is_some() { validate(source,&format!("{{{s}}}")) }
    else { validate(source, &s) }
  }
}
pub fn prepare(source: &str, glossary: &Value) -> Prepared {
  let source=braced_item(source).unwrap_or(source);
  let mut names = glossary
    .as_object()
    .map(|o| o.keys().filter(|k| !matches!(k.as_str(), "A" | "An" | "The")).cloned().collect::<Vec<_>>())
    .unwrap_or_default();
  names.sort_by_key(|k| std::cmp::Reverse(k.len()));
  let expr = format!(
    "{}|{}{}\\d+(?:[.,]\\d+)*",
    tokens().as_str(),
    if names.is_empty() {
      String::new()
    } else {
      names.iter().map(|s| regex::escape(s)).collect::<Vec<_>>().join("|") + "|"
    },
    ""
  );
  let mut numbers = Vec::new();
  let mut entities = Vec::new();
  let text = re(&expr)
    .replace_all(source, |c: &regex::Captures| {
      let m = c.get(0).unwrap();
      let part = m.as_str();
      if tokens().is_match(part) {
        return part.into();
      }
      if let Some(value) = glossary[part].as_str() {
        if source[..m.start()].chars().next_back().is_some_and(char::is_alphanumeric)
          || source[m.end()..].chars().next().is_some_and(char::is_alphanumeric)
        {
          return part.into();
        }
        entities.push(value.to_string());
        format!("{{{{DFE{}}}}}", entities.len() - 1)
      } else {
        numbers.push(part.into());
        format!("{{{{DFN{}}}}}", numbers.len() - 1)
      }
    })
    .into_owned();
  let kind = if !entities.is_empty() {
    "entity"
  } else if !numbers.is_empty() {
    "numeric"
  } else {
    "exact"
  };
  Prepared {
    text,
    kind: kind.into(),
    numbers,
    entities,
  }
}
fn csv_dict(path: &Path, target: &mut Dict) -> Result<()> {
  let bytes = std::fs::read(path)?;
  let bytes = bytes.strip_prefix(&[239, 187, 191]).unwrap_or(&bytes);
  let mut reader = csv::ReaderBuilder::new().flexible(true).from_reader(bytes);
  let headers = reader.headers()?.clone();
  let a = headers.iter().position(|s| s == "text").unwrap_or(0);
  let b = headers.iter().position(|s| s == "translation").unwrap_or(1);
  for row in reader.records() {
    let row = row?;
    if let (Some(text), Some(value)) = (row.get(a), row.get(b)) {
      if let Ok(value) = validate(text, value) {
        target.insert(text.into(), value);
      }
    }
  }
  Ok(())
}
impl App {
  pub fn load(config_path: &Path, root: &Path) -> Result<Arc<Self>> {
    let start = Instant::now();
    let config = read_json(config_path, 1024 * 1024)?;
    let source = config_path.parent().unwrap().to_path_buf();
    let runtime = root.join("data");
    std::fs::create_dir_all(&runtime)?;
    let settings = Arc::new(Mutex::new(Settings::load(root, &config)?));
    let official = Official::new(root)?;
    official.load()?;
    let pool = Pool::new()?;
    let shared = Shared::load(root, settings.clone())?;
    let mut builtins = HashMap::new();
    let mut glossaries = HashMap::new();
    let mut fixed = HashMap::new();
    let mut equipment = HashMap::new();
    for lang in ["zh-Hant", "zh-Hans"] {
      if let Some(p) = config["equipmentRulesDirectory"].as_str() {
        equipment.insert(lang.into(), Terms::load(&source.join(p).join(lang))?);
      }
      let mut dict = Dict::new();
      let simple = source.join("../dfi18n-data/simple").join(lang);
      if simple.is_dir() {
        let mut files = std::fs::read_dir(simple)?
          .filter_map(|x| x.ok())
          .map(|x| x.path())
          .filter(|p| p.extension().is_some_and(|e| e == "csv"))
          .collect::<Vec<_>>();
        files.sort();
        for p in files {
          csv_dict(&p, &mut dict)?;
        }
      }
      let mut files = Vec::new();
      if config["staticDictionaryLanguage"].as_str().is_none_or(|l| l == lang) {
        files.extend(config["staticDictionaries"].as_array().cloned().unwrap_or_default());
        if let Some(v) = config.get("reviewedDictionary") {
          files.push(v.clone());
        }
      }
      files.extend(config["staticDictionariesByLanguage"][lang].as_array().cloned().unwrap_or_default());
      for v in files {
        if let Some(p) = v.as_str() {
          csv_dict(&source.join(p), &mut dict)?;
        }
      }
      // Corrected rules remain higher priority than the shared layer.
      dict.insert(
        "will only do assigned tasks".into(),
        convert("只會執行指派的工作", lang),
      );
      builtins.insert(lang.into(), dict);
      let glossary_path = config["glossaryPathsByLanguage"][lang].as_str().or(config["glossaryPath"].as_str());
      let mut glossary = if let Some(p) = glossary_path {
        read_json(&source.join(p), 4 * 1024 * 1024)?
      } else {
        config.get("glossary").cloned().unwrap_or(json!({}))
      };
      if lang == "zh-Hans" {
        for v in glossary.as_object_mut().ok_or_else(|| anyhow::anyhow!("invalid glossary"))?.values_mut() {
          if let Some(s) = v.as_str() {
            *v = json!(convert(s, lang));
          }
        }
      }
      glossaries.insert(lang.into(), glossary);
      let path = root.join(format!("fixed-{lang}.json"));
      let mut pins = Dict::new();
      if path.exists() {
        let rows = read_json(&path, 1024 * 1024)?;
        for (k, v) in rows.as_object().ok_or_else(|| anyhow::anyhow!("invalid fixed file"))? {
          pins.insert(k.clone(), validate(k, v.as_str().unwrap_or(""))?);
        }
      }
      fixed.insert(lang.into(), pins);
    }
    let mut cache = BoundedMap::new(16384);
    let journal_path = root.join("translations.jsonl");
    if journal_path.exists() {
      use std::io::BufRead;
      for line in std::io::BufReader::new(std::fs::File::open(journal_path)?).lines() {
        let Ok(line) = line else { continue };
        let Ok(row) = serde_json::from_str::<Value>(&line) else {
          continue;
        };
        let lang = row["language"].as_str().unwrap_or("");
        let kind = row["kind"].as_str().unwrap_or("");
        let source = row["source"].as_str().unwrap_or("");
        if row["policy"] != POLICY
          || !language(lang)
          || !["exact", "numeric", "entity", "name", "link", "phonetic"].contains(&kind)
          || row["key"] != cache_key(source, lang, kind)
        {
          continue;
        }
        let validation = if matches!(kind, "name" | "link") {
          row["preferred"].as_str().unwrap_or("")
        } else {
          source
        };
        if let Ok(value) = validate(validation, row["translation"].as_str().unwrap_or("")) {
          cache.insert(row["key"].as_str().unwrap().into(), value);
        }
      }
    }
    let name_dictionary = read_json(&source.join("name-dictionary.json"), 8 * 1024 * 1024).unwrap_or(json!({}));
    let mut races = json!({});
    if let Some(path) = config["raceMap"].as_str() {
      let map = read_json(&source.join(path), 8 * 1024 * 1024)?;
      for row in map["races"].as_object().ok_or_else(|| anyhow::anyhow!("invalid race map"))?.values() {
        if let (Some(text), Some(value)) = (row["source"].as_str(), row["translation"].as_str()) {
          races[text] = json!(value);
        }
      }
    }
    let app = Arc::new(Self {
      source,
      root: root.into(),
      runtime,
      config,
      settings,
      official,
      pool,
      shared,
      builtins,
      glossaries,
      name_dictionary,
      races,
      cache: Mutex::new(cache),
      fixed,
      pending: Mutex::new(HashMap::new()),
      journal: Mutex::new(()),
      equipment,
      runtime_active: AtomicUsize::new(0),
      published: AtomicUsize::new(0),
      failed: AtomicUsize::new(0),
      attempted: AtomicUsize::new(0),
      runtime_snapshot: Mutex::new(json!({"foregroundActive":0,"backgroundActive":0,"foregroundQueued":0,"backgroundQueued":0,"unresolved":0})),
      registry_cache:Mutex::new((None,Arc::new(json!({"entities":[]})))),
      prewarm_signature:Mutex::new(String::new()),
    });
    app.publish_status()?;
    println!(
      "Rust Broker local load: {:.2} ms",
      start.elapsed().as_secs_f64() * 1000.0
    );
    Ok(app)
  }
  pub fn context(&self) -> Value {
    read_json(&self.root.join("active-context.json"), 8192)
      .ok()
      .filter(|v| {
        v["version"] == 1
          && v["world"].as_str().is_some_and(|s| s.len() <= 1024)
          && v["language"].as_str().is_some_and(language)
      })
      .unwrap_or_else(|| json!({"world":"","language":self.settings.lock().unwrap().effective("")["language"]}))
  }
  pub fn registry(&self, world: &str) -> Arc<Value> {
    let path=self.runtime.join("world-names.json");
    let stamp=std::fs::metadata(&path).ok().and_then(|m|Some((m.modified().ok()?,m.len())));
    let mut cache=self.registry_cache.lock().unwrap();
    if stamp!=cache.0 {
      let value=read_json(&path,32*1024*1024).ok().filter(|v|v["entities"].is_array());
      if let Some(value)=value {*cache=(stamp,Arc::new(value));}
    }
    if cache.1["world"]==world {cache.1.clone()} else {Arc::new(json!({"world":world,"entities":[]}))}
  }
  fn known(&self, source: &str, lang: &str) -> Option<String> {
    if let Some(v) = self.fixed.get(lang)?.get(source) {
      return Some(v.clone());
    }
    if let Some(v) = self.equipment.get(lang).and_then(|t| t.translate(source)) {
      return Some(v);
    }
    if let Some(v) = self.builtins.get(lang)?.get(source) {
      return Some(v.clone());
    }
    let pattern = re(r"^(?:\[C:[0-7]:[0-7]:[01]\]|\[[BPR]\])+");
    if let Some(prefix) = pattern.find(source) {
      if let Some(value) = self.known(&source[prefix.end()..], lang) {
        return Some(format!("{}{value}", prefix.as_str()));
      }
    }
    if let Some(body) = source.strip_prefix('.') {
      if body == "Needs setting" {
        if let Some(v) = self.builtins[lang].get(body) {
          return Some(format!(".{v}"));
        }
      }
    }
    if source.starts_with('{') && source.ends_with('}') && !source[1..source.len() - 1].contains(['{', '}']) {
      if let Some(v) = self.builtins[lang].get(&source[1..source.len() - 1]) {
        return Some(format!("{{{v}}}"));
      }
    }
    self.official.lookup(source, lang, "exact").or_else(|| self.official.lookup(source, lang, "entity"))
  }
  fn cached(&self, source: &str, lang: &str, kind: &str) -> Option<String> {
    self.cache.lock().unwrap().get(&cache_key(source, lang, kind)).cloned()
  }
  fn save_cache(&self, source: &str, lang: &str, kind: &str, value: &str, preferred: Option<&str>) -> Result<()> {
    let _guard = self.journal.lock().unwrap();
    let key = cache_key(source, lang, kind);
    if self.cache.lock().unwrap().get(&key).is_some_and(|s| s == value) {
      return Ok(());
    }
    let mut row = json!({"key":key,"policy":POLICY,"kind":kind,"source":source,"language":lang,"translation":value,"timestamp":iso()});
    if let Some(p) = preferred {
      row["preferred"] = json!(p);
    }
    append(&self.root.join("translations.jsonl"), &row)?;
    self.cache.lock().unwrap().insert(key, value.into());
    Ok(())
  }
  pub async fn translate(self: &Arc<Self>, source: &str, lang: &str, world: &str, priority: u8) -> Result<String> {
    ensure!(
      language(lang)
        && !source.trim().is_empty()
        && source.chars().count() <= 8000
        && !aliases(source)
        && !source.contains('\0'),
      "invalid source"
    );
    ensure!(
      world.is_empty() || self.context()["world"] == world,
      "translation world changed"
    );
    if let Some(v) = self.known(source, lang) {
      return Ok(v);
    }
    let key = serde_json::to_string(&json!([lang, world, source]))?;
    let (mut rx, first) = {
      let mut pending = self.pending.lock().unwrap();
      if let Some(rx) = pending.get(&key) {
        (rx.clone(), None)
      } else {
        ensure!(pending.len() < 128, "translation queue full");
        let (tx, rx) = watch::channel(None);
        pending.insert(key.clone(), rx.clone());
        (rx, Some(tx))
      }
    };
    if let Some(tx) = first {
      let app = self.clone();
      let source = source.to_string();
      let lang = lang.to_string();
      let world = world.to_string();
      tokio::spawn(async move {
        let _pending=PendingGuard {app:app.clone(),key};
        let deadline=Duration::from_millis(app.settings.lock().unwrap().effective(&world)["timeoutMs"].as_u64().unwrap_or(25000));
        let result = tokio::time::timeout(deadline,app.process(&source, &lang, &world, priority)).await
          .unwrap_or_else(|_|Err(anyhow::anyhow!("translation deadline exceeded")));
        let row = match result {
          Ok(s) => (true, s),
          Err(e) => (false, e.to_string()),
        };
        let _ = tx.send(Some(row));
      });
    }
    loop {
      if let Some((ok, value)) = rx.borrow().clone() {
        return if ok { Ok(value) } else { Err(anyhow::anyhow!(value)) };
      }
      rx.changed().await?;
    }
  }
  async fn process(self: &Arc<Self>, source: &str, lang: &str, world: &str, priority: u8) -> Result<String> {
    ensure!(
      !re(r"^(?:He|She) is not distracted after being unable to (?:be|pray to)$").is_match(source.trim()),
      "incomplete display fragment"
    );
    let registry = self.registry(world);
    let mut name_glossary = json!({});
    if !world.is_empty() {
      for row in registry["entities"].as_array().unwrap() {
        if let Some(aliases) = row["aliases"].as_array() {
          let matched =
            aliases.iter().filter_map(Value::as_str).any(|a| !matches!(a, "A" | "An" | "The") && mentions(source, a));
          if matched {
            let name = self.canonical(row, lang, world, priority).await?;
            for alias in aliases.iter().filter_map(Value::as_str) {
              if !matches!(alias, "A" | "An" | "The") || source.trim() == alias {
                name_glossary[alias] = json!(name);
              }
            }
          }
        }
      }
    }
    // Stable game glossary terms are template entities too, as in the legacy Broker.
    for (k, v) in self.glossaries[lang].as_object().unwrap() {
      if mentions(source, k) && name_glossary.get(k).is_none() {
        name_glossary[k] = v.clone();
      }
    }
    let prepared = prepare(source, &name_glossary);
    if let Some(shared) = self.official.lookup(&prepared.text, lang, &prepared.kind) {
      return prepared.restore(&shared, source);
    }
    if let Some(cached) = self.cached(&prepared.text, lang, &prepared.kind) {
      if let Ok(value) = prepared.restore(&cached, source) {
        return Ok(value);
      }
    }
    if let Some(cached) = self.cached(source, lang, "exact") {
      if name_glossary.as_object().unwrap().values().all(|v| cached.contains(v.as_str().unwrap_or(""))) {
        return Ok(cached);
      }
    }
    let mut glossary = json!({});
    for (k, v) in self.glossaries[lang].as_object().unwrap() {
      if mentions(&prepared.text, k) {
        glossary[k] = v.clone();
      }
    }
    let (s, profiles) = {
      let settings = self.settings.lock().unwrap();
      (settings.effective(world), settings.selected(world))
    };
    let (translated, model) = self
      .pool
      .translate(
        prepared.text.clone(),
        lang.into(),
        glossary,
        s,
        profiles,
        false,
        priority,
      )
      .await?;
    ensure!(
      world.is_empty() || self.context()["world"] == world,
      "translation world changed"
    );
    // Higher layers win even if an AI request completed later.
    if let Some(value) = self.known(source, lang) {
      return Ok(value);
    }
    if let Some(v) = self.official.lookup(&prepared.text, lang, &prepared.kind) {
      return prepared.restore(&v, source);
    }
    let restored = prepared.restore(&translated, source)?;
    self.save_cache(&prepared.text, lang, &prepared.kind, &translated, None)?;
    let model = if re(r"^[A-Za-z0-9_/.@:+-]{1,100}$").is_match(&model) {
      model
    } else {
      "configured-provider-pool".into()
    };
    let _=self.shared.capture(json!({"schema":1,"rules":POLICY,"language":lang,"context":"general","kind":prepared.kind,"origin":"vanilla","text":prepared.text,"translation":translated,"model":model,"license":"CC0-1.0"}),world);
    Ok(restored)
  }
  async fn canonical(self: &Arc<Self>, row: &Value, lang: &str, world: &str, priority: u8) -> Result<String> {
    let preferred = row["nativeName"]
      .as_str()
      .filter(|s| !s.is_empty())
      .or(row["preferred"].as_str())
      .ok_or_else(|| anyhow::anyhow!("name registry invalid"))?;
    let native = row["nativeName"].as_str().is_some_and(|s| !s.is_empty());
    let id = row["id"].as_str().ok_or_else(|| anyhow::anyhow!("name registry invalid"))?;
    let identity = serde_json::to_string(&json!([
      world,
      if native { format!("native-v2:{id}") } else { id.into() },
      preferred
    ]))?;
    if let Some(v) = self.cached(&identity, lang, "name") {
      return Ok(v);
    }
    let value = if let Some(v) = self.name_dictionary[preferred].as_str() {
      convert(v, lang)
    } else if !native && self.cached(preferred, lang, "exact").is_some() {
      self.cached(preferred, lang, "exact").unwrap()
    } else {
      let (s, profiles) = {
        let settings = self.settings.lock().unwrap();
        (settings.effective(world), settings.selected(world))
      };
      let mut glossary = json!({});
      if let Some(first) = preferred.split_whitespace().next() {
        if let Some(v) = self.name_dictionary[first].as_str() {
          glossary[first] = json!(convert(v, lang));
        }
      }
      self.pool.translate(preferred.into(), lang.into(), glossary, s, profiles, native, priority).await?.0
    };
    ensure!(self.context()["world"] == world, "translation world changed");
    let value = validate(preferred, &value)?;
    self.save_cache(&identity, lang, "name", &value, Some(preferred))?;
    Ok(value)
  }
  pub async fn pin(self: &Arc<Self>, id: &str, lang: &str, world: &str) -> Result<String> {
    let r = self.registry(world);
    let row = r["entities"]
      .as_array()
      .unwrap()
      .iter()
      .find(|r| r["id"] == id)
      .ok_or_else(|| anyhow::anyhow!("unknown figure"))?;
    self.canonical(row, lang, world, 0).await
  }
  pub fn health(&self) -> Value {
    let context = self.context();
    let world = context["world"].as_str().unwrap_or("");
    let lang = context["language"].as_str().unwrap_or("zh-Hant");
    let s = self.settings.lock().unwrap();
    let configured = s.effective(world)["apiEnabled"] == true && !s.selected(world).is_empty();
    json!({"service":"df-local-zh","engine":"rust","version":env!("CARGO_PKG_VERSION"),"policy":POLICY,"language":lang,"providerConfigured":configured,"cached":self.cache.lock().unwrap().len(),"pending":self.pending.lock().unwrap().len(),"providerBatch":self.pool.stats(),"official":self.official.status(lang),"runtime":self.runtime_status()})
  }
  fn runtime_status(&self)->Value {
    let mut status=self.runtime_snapshot.lock().unwrap().clone();
    status["attempted"]=json!(self.attempted.load(Ordering::Relaxed));
    status["published"]=json!(self.published.load(Ordering::Relaxed));
    status["failed"]=json!(self.failed.load(Ordering::Relaxed));
    status["active"]=json!(self.runtime_active.load(Ordering::Relaxed));
    status
  }
  pub fn publish_status(&self) -> Result<()> {
    let context = self.context();
    let world = context["world"].as_str().unwrap_or("");
    let lang = context["language"].as_str().unwrap_or("zh-Hant");
    let settings = self.settings.lock().unwrap();
    let effective = settings.effective(world);
    let controls = read_json(&self.runtime.join("translation-controls.json"), 8192).unwrap_or(json!({}));
    let paused = effective["backgroundTranslation"] != true || controls["backgroundPaused"] == true;
    let queued = self.pool.queued.load(Ordering::Relaxed);
    let active = self.pool.active.load(Ordering::Relaxed);
    let status = json!({"version":1,"timestamp":now(),"world":world,"language":lang,"providerConfigured":effective["apiEnabled"]==true&&!settings.selected(world).is_empty(),"cached":self.cache.lock().unwrap().len(),"backgroundPaused":paused,"foregroundActive":active,"backgroundActive":0,"foregroundQueued":queued,"backgroundQueued":0,"providerQueued":queued,"providerActive":active,"runtime":self.runtime_status()});
    drop(settings);
    atomic(&self.runtime.join("broker-status.json"), &status)
  }
  pub async fn settings_request(self: &Arc<Self>, request: &Value) -> Result<Value> {
    let id = request["id"].as_str().unwrap_or("");
    ensure!(re(r"^[a-zA-Z0-9_-]{1,80}$").is_match(id), "invalid request ID");
    let mut reply = json!({"version":1,"id":id,"ok":true});
    let world = request["world"].as_str().unwrap_or("");
    match request["action"].as_str().unwrap_or("") {
      "save" => {
        reply["snapshot"] = self.settings.lock().unwrap().apply(request)?;
      }
      "official-sync" => {
        let lang = request["language"].as_str().unwrap_or("");
        ensure!(language(lang), "invalid language");
        let o = self.official.clone();
        let lang = lang.to_string();
        tokio::spawn(async move {
          let _ = o.sync(lang).await;
        });
      }
      "official-clear" => {
        // Persist opt-out first, including per-save overrides; no UI draft/keys are saved.
        self.settings.lock().unwrap().disable_official_download()?;
        self.official.clear().await?;
        reply["snapshot"] = self.settings.lock().unwrap().snapshot(world);
        reply["restartRequired"] = json!(true);
      }
      "shared-clear" => self.shared.clear().await?,
      "clipboard" => reply["text"] = json!(clipboard()?),
      "test" => {
        let (s, profile) = {
          let settings = self.settings.lock().unwrap();
          let mut s = settings.effective(world);
          s["apiEnabled"] = json!(true);
          s["timeoutMs"] = json!(5000);
          s["maxRetries"] = json!(0);
          let p = if request["profile"].is_object() {
            settings.draft(&request["profile"])?
          } else {
            let selected = settings.selected(world);
            selected.into_iter().next().ok_or_else(|| anyhow::anyhow!("API unconfigured"))?
          };
          ensure!(p.1["enabled"] == true, "API disabled");
          (s, p)
        };
        let lang = s["language"].as_str().unwrap_or("zh-Hant").to_string();
        self.pool.translate("Connection test.".into(), lang, json!({}), s, vec![profile], false, 0).await?;
      }
      _ => bail!("unknown settings action"),
    }
    Ok(reply)
  }
  pub async fn runtime_row(self: &Arc<Self>, request: &Value) -> Result<Value> {
    let source = request["text"].as_str().unwrap_or("");
    let lang = request["language"].as_str().unwrap_or("zh-Hant");
    let world = request["world"].as_str().unwrap_or("");
    ensure!(
      !world.is_empty()
        && self.context()["world"] == world
        && language(lang)
        && !source.trim().is_empty()
        && source.len() <= 8000,
      "invalid runtime request"
    );
    let priority = if request["priority"] == "foreground" { 0 } else { 2 };
    let registry = self.registry(world);
    let entities = registry["entities"].as_array().unwrap();
    let payload = if request["kind"] == "legends-name" {
      ensure!(request["namePolicy"] == "native-v2", "invalid name policy");
      let id = format!(
        "{}:{}",
        request["entityKind"].as_str().unwrap_or(""),
        request["entityId"]
      );
      let row = entities.iter().find(|r| r["id"] == id).ok_or_else(|| anyhow::anyhow!("name identity mismatch"))?;
      ensure!(
        row["aliases"].as_array().is_some_and(|a| a.iter().any(|v| v == source))
          && (row["nativeName"].as_str().unwrap_or_else(|| row["aliases"][0].as_str().unwrap_or("")) == source),
        "name identity mismatch"
      );
      json!({"translation":self.canonical(row,lang,world,priority).await?})
    } else if request["kind"] == "legends-paragraph" {
      ensure!(request["namePolicy"] == "native-v2", "invalid name policy");
      let links = request["links"].as_array().ok_or_else(|| anyhow::anyhow!("invalid links"))?;
      ensure!(links.len() <= 64, "invalid links");
      let ts =
        re(r"\{\{DFL(\d+)\}\}").captures_iter(source).map(|c| c[1].parse::<usize>()).collect::<std::result::Result<Vec<_>,_>>()?;
      ensure!(
        ts.len() == links.len()
          && ts.iter().copied().collect::<HashSet<_>>().len() == links.len()
          && ts.iter().all(|n| *n < links.len()),
        "invalid links"
      );
      let kinds = [
        "figure",
        "site",
        "artifact",
        "book",
        "region",
        "layer",
        "entity",
        "building",
        "population",
        "art",
        "era",
        "collection",
      ];
      let mut results = Vec::new();
      for link in links {
        let t = link["type"].as_u64().ok_or_else(|| anyhow::anyhow!("invalid links"))? as usize;
        ensure!(t < kinds.len() && link["id"].as_u64().is_some(), "invalid links");
        let text = link["text"]
          .as_str()
          .filter(|s| !s.is_empty() && s.len() <= 2000)
          .ok_or_else(|| anyhow::anyhow!("invalid links"))?;
        let id = format!("{}:{}", kinds[t], link["id"]);
        let value = if let Some(row) = entities.iter().find(|r| r["id"] == id) {
          ensure!(
            aliases(text)
              || row["aliases"]
                .as_array()
                .is_some_and(|a| a.iter().filter_map(Value::as_str).any(|a| mentions(text, a))),
            "link identity mismatch"
          );
          let name = self.canonical(row, lang, world, priority).await?;
          if aliases(text) || row["aliases"].as_array().is_some_and(|a| a.iter().any(|a| a == text)) {
            name
          } else {
            self.translate(text, lang, world, priority).await?
          }
        } else {
          ensure!(t != 0 && !aliases(text), "link identity mismatch");
          self.translate(text, lang, world, priority).await?
        };
        results.push(json!({"translation":value}));
      }
      let without = re(r"\{\{DFL\d+\}\}").replace_all(source, "");
      let translation = if !re(r"\p{L}").is_match(&without) {
        source.into()
      } else {
        self.translate(source, lang, world, priority).await?
      };
      json!({"translation":translation,"links":results,"kind":"legends-paragraph","subjectId":request["subjectId"],"requestLinks":links})
    } else if let Some(figure) = request["figureId"].as_u64() {
      ensure!(request["namePolicy"] == "native-v2", "invalid name policy");
      let id = format!("figure:{figure}");
      let row = entities.iter().find(|r| r["id"] == id).ok_or_else(|| anyhow::anyhow!("caption identity mismatch"))?;
      let pattern = re(r#"^(.*), "([^"]+)", (.+)$"#);
      let matched = pattern.captures(source).ok_or_else(|| anyhow::anyhow!("caption identity mismatch"))?;
      let norm = |s: &str| s.to_lowercase().chars().filter(|c| c.is_alphanumeric()).collect::<String>();
      for i in [1, 2] {
        ensure!(
          row["aliases"]
            .as_array()
            .is_some_and(|a| a.iter().filter_map(Value::as_str).any(|a| norm(a) == norm(&matched[i]))),
          "caption identity mismatch"
        );
      }
      let name = self.canonical(row, lang, world, priority).await?;
      let role = match crate::display::role(&matched[3], &self.races, lang) {
        Ok(s) => s,
        Err(_) => self.translate(&matched[3], lang, world, priority).await?,
      };
      let translation = if row["nativeName"].as_str().is_some_and(|s| !s.is_empty()) {
        format!("{name}，{role}")
      } else {
        format!("{name}，「{name}」，{role}")
      };
      json!({"translation":validate(source,&translation)?})
    } else {
      ensure!(request.get("kind").is_none(), "invalid runtime kind");
      json!({"translation":self.translate(source,lang,world,priority).await?})
    };
    ensure!(self.context()["world"] == world, "translation world changed");
    let mut row = request.clone();
    row.as_object_mut().unwrap().remove("visibilityId");
    row.as_object_mut().unwrap().remove("priority");
    row.as_object_mut().unwrap().remove("links");
    for (k, v) in payload.as_object().unwrap() {
      row[k] = v.clone();
    }
    row["key"] = json!(runtime_key(request));
    row["language"] = json!(lang);
    Ok(row)
  }
  pub fn prewarm(&self) -> Result<()> {
    let context = self.context();
    let world = context["world"].as_str().unwrap_or("");
    if world.is_empty() {
      return Ok(());
    }
    let mut signature=format!("{world}:{:?}:{:?}",self.official.status("zh-Hant"),self.official.status("zh-Hans"));
    let mut inputs=vec![self.runtime.join("world-names.json")];
    if let Some(game)=std::env::var_os("DF_LOCAL_ZH_GAME_ROOT") {inputs.push(PathBuf::from(game).join("dfi18n-data/cache/translation-cache.csv"));}
    for input in inputs {let m=std::fs::metadata(input).ok();signature.push_str(&format!("{:?}",m.and_then(|m|Some((m.modified().ok()?,m.len())))));}
    let mut previous=self.prewarm_signature.lock().unwrap();
    if *previous==signature {return Ok(())}
    let registry = self.registry(world);
    let names = registry["entities"]
      .as_array()
      .unwrap()
      .iter()
      .flat_map(|r| r["aliases"].as_array().cloned().unwrap_or_default())
      .filter_map(|v| v.as_str().map(str::to_owned))
      .collect::<HashSet<_>>();
    for lang in ["zh-Hant", "zh-Hans"] {
      let mut rows = Vec::new();
      let mut combined = Dict::new();
      let mut cached_rows = Vec::new();
      if let Some(game) = std::env::var_os("DF_LOCAL_ZH_GAME_ROOT") {
        let path = PathBuf::from(game).join("dfi18n-data/cache/translation-cache.csv");
        if path.is_file() {
          let mut reader = csv::ReaderBuilder::new().flexible(true).from_path(path)?;
          let headers = reader.headers()?.clone();
          for row in reader.records().flatten() {
            let mut value = json!({});
            for (key, entry) in headers.iter().zip(row.iter()) {
              value[key] = json!(entry);
            }
            cached_rows.push(value);
          }
        }
      }
      let (native, unit) = crate::display::native_rows(&cached_rows, &names, lang);
      for row in native {
        combined.insert(
          row["text"].as_str().unwrap().into(),
          row["translation"].as_str().unwrap().into(),
        );
      }
      for (k, v) in &self.builtins[lang] {
        combined.insert(k.clone(), v.clone());
      }
      for row in self.official.rows(lang) {
        if row["kind"] == "exact" && row["context"] == "general" {
          let text = row["text"].as_str().unwrap();
          if !self.builtins[lang].contains_key(text) {
            combined.insert(text.into(), row["translation"].as_str().unwrap().into());
          }
        }
      }
      for (k, v) in &self.fixed[lang] {
        combined.insert(k.clone(), v.clone());
      }
      let mut sorted = combined.into_iter().collect::<Vec<_>>();
      sorted.sort_by(|a, b| a.0.cmp(&b.0));
      for (text, translation) in sorted {
        if !aliases(&text) && !text.contains(['{', '\0']) && !names.contains(&text) && text.len() <= 8000 {
          rows.push(
            json!({"kind":if text.starts_with('['){"markup"}else{"plain"},"text":text,"translation":translation}),
          );
        }
      }
      let revision = hash(serde_json::to_vec(&json!([world, lang, rows, unit]))?);
      let out = if lang == "zh-Hant" {
        "native-prewarm.json"
      } else {
        "native-prewarm-zh-Hans.json"
      };
      let current = read_json(&self.runtime.join(out), 32 * 1024 * 1024).ok();
      if current.as_ref().is_none_or(|v| v["revision"] != revision) {
        let data = json!({"version":1,"world":world,"language":lang,"revision":revision,"rows":rows,"unit":unit});
        ensure!(
          serde_json::to_vec(&data)?.len() <= 32 * 1024 * 1024,
          "prewarm too large"
        );
        atomic(&self.runtime.join(out), &data)?;
      }
      let small = if lang == "zh-Hant" {
        "native-prewarm-unit.json"
      } else {
        "native-prewarm-unit-zh-Hans.json"
      };
      let small_current = read_json(&self.runtime.join(small), 4 * 1024 * 1024).ok();
      if small_current.as_ref().is_none_or(|v| v["revision"] != revision) {
        let data = json!({"version":1,"world":world,"language":lang,"revision":revision,"unit":unit});
        ensure!(
          serde_json::to_vec(&data)?.len() <= 4 * 1024 * 1024,
          "unit prewarm too large"
        );
        atomic(&self.runtime.join(small), &data)?;
      }
    }
    *previous=signature;
    Ok(())
  }
}
pub fn runtime_key(row: &Value) -> String {
  let world = row["world"].as_str().unwrap_or("");
  let source = row["text"].as_str().unwrap_or("");
  let data = if row["kind"] == "legends-name" {
    json!([
      world,
      source,
      "legends-name-native-v2",
      row["entityKind"],
      row["entityId"]
    ])
  } else if row["kind"] == "legends-paragraph" {
    let links = row["links"]
      .as_array()
      .map(|a| a.iter().map(|l| json!([l["type"], l["id"], l["text"]])).collect::<Vec<_>>())
      .unwrap_or_default();
    json!([world, source, "legends-paragraph-native-v2", row["subjectId"], links])
  } else if row.get("figureId").is_some() {
    json!([world, source, "figure-caption-native-v2", row["figureId"]])
  } else {
    json!([world, source])
  };
  let mut bytes = Vec::new();
  if row["language"] == "zh-Hans" {
    bytes.extend_from_slice(b"zh-Hans\0");
  }
  bytes.extend_from_slice(&serde_json::to_vec(&data).unwrap());
  format!("DFLIVE_{}", hash(bytes))
}
pub struct Tail {
  offset: u64,
  tail: Vec<u8>,
  modified: Option<std::time::SystemTime>,
}
impl Default for Tail {
  fn default() -> Self {
    Self {
      offset: 0,
      tail: Vec::new(),
      modified: None,
    }
  }
}
impl Tail {
  pub fn read(&mut self, path: &Path) -> Result<Vec<Value>> {
    use std::io::{Read, Seek, SeekFrom};
    let Ok(mut file) = std::fs::File::open(path) else {
      return Ok(Vec::new());
    };
    let meta = file.metadata()?;
    if meta.len() < self.offset
      || (meta.len() == self.offset && self.modified.is_some() && meta.modified().ok() != self.modified)
    {
      self.offset = 0;
      self.tail.clear();
    }
    self.modified = meta.modified().ok();
    file.seek(SeekFrom::Start(self.offset))?;
    let mut data = Vec::new();
    file.take(64 * 1024).read_to_end(&mut data)?;
    self.offset += data.len() as u64;
    self.tail.extend(data);
    let mut rows = Vec::new();
    if let Some(end) = self.tail.iter().rposition(|c| *c == b'\n') {
      for line in self.tail[..end].split(|c| *c == b'\n') {
        if line.len() <= 32768 {
          if let Ok(v) = serde_json::from_slice(line) {
            rows.push(v);
          }
        }
      }
      self.tail.drain(..=end);
    }
    if self.tail.len() > 32768 {
      self.tail.clear();
    }
    Ok(rows)
  }
}
fn runtime_request_current(row: &Value, world: &str, visible: &HashSet<String>) -> bool {
  if row["world"] != world {
    return false;
  }
  // Fortress prose and background requests have no viewport identity. Only
  // view-bound requests (including Legends identities) require visibility.
  let view_bound = row.get("visibilityId").is_some()
    || row.get("kind").is_some()
    || row.get("figureId").is_some_and(|id| !id.is_null());
  !view_bound || row["visibilityId"].as_str().is_some_and(|id| visible.contains(id))
}

pub async fn run_background(app: Arc<App>) {
  let mut last_id = String::new();
  let mut settings_task:Option<tokio::task::JoinHandle<(String,Value)>>=None;
  let mut settings_reply:Option<(String,Value)>=None;
  let mut settings_reply_at=Instant::now()-Duration::from_secs(2);
  let mut previous_visible=HashSet::new();
  let mut tail = Tail::default();
  let mut deferred=false;
  let mut completed = BoundedMap::new(32768);
  let mut jobs = HashMap::<String, Value>::new();
  let mut inflight = HashMap::<String,Value>::new();
  let mut scope=String::new();
  let mut retry_generation=String::new();
  let mut failures = BoundedMap::<String, Value>::new(4096);
  let (done_tx, mut done_rx) = tokio::sync::mpsc::channel::<(String, Value, Result<Value>)>(64);
  let mut status_at = Instant::now();
  let mut prewarm_at = Instant::now() - Duration::from_secs(10);
  let mut prewarm_task:Option<tokio::task::JoinHandle<()>>=None;
  let mut shared_at = Instant::now() - Duration::from_secs(20);
  let mut auto_at = HashMap::<String, i64>::new();
  if let Ok(file) = std::fs::File::open(app.runtime.join("runtime-responses.jsonl")) {
    use std::io::BufRead;
    for line in std::io::BufReader::new(file).lines().map_while(Result::ok) {
      if let Ok(mut row) = serde_json::from_str::<Value>(&line) {
        if row["kind"] == "legends-paragraph" {
          row["links"] = row["requestLinks"].clone();
        }
        if row["key"] == runtime_key(&row)
          && validate(
            row["text"].as_str().unwrap_or(""),
            row["translation"].as_str().unwrap_or(""),
          )
          .is_ok()
        {
          completed.insert(runtime_key(&row),());
        }
      }
    }
  }
  if let Ok(file) = std::fs::File::open(app.runtime.join("runtime-failures.jsonl")) {
    use std::io::BufRead;
    for line in std::io::BufReader::new(file).lines().map_while(Result::ok) {
      if let Ok(row) = serde_json::from_str::<Value>(&line) {
        let key = runtime_key(&row);
        if row["key"] == key && row["attempts"].as_u64().is_some_and(|n| n <= 31) && !completed.contains_key(&key) {
          failures.insert(key, row);
        }
      }
    }
  }
  loop {
    while let Ok((key, row, result)) = done_rx.try_recv() {
      inflight.remove(&key);
      app.runtime_active.fetch_sub(1, Ordering::Relaxed);
      let context=app.context();
      if context["world"]!=row["world"] || context["language"].as_str().unwrap_or("zh-Hant")!=row["language"].as_str().unwrap_or("zh-Hant") {continue}
      let result=result.and_then(|output| {
        append(&app.runtime.join("runtime-responses.jsonl"), &output)?;
        Ok(output)
      });
      match result {
        Ok(_) => {
            completed.insert(key.clone(),());
            failures.remove(&key);
            app.published.fetch_add(1, Ordering::Relaxed);
        }
        Err(error) => {
          let settings = app.settings.lock().unwrap().effective(row["world"].as_str().unwrap_or(""));
          let count = failures.get(&key).and_then(|v| v["attempts"].as_u64()).unwrap_or(0) + 1;
          let mut failure = row.clone();
          failure["key"] = json!(key);
          failure["attempts"] = json!(count.min(31));
          failure["retryAt"] = json!(
            now() + 300000.min(settings["retryBaseMs"].as_i64().unwrap_or(1000) * (1_i64 << (count - 1).min(20)))
          );
          failure["reason"] = json!(error.to_string().chars().take(512).collect::<String>());
          failure["terminal"]=json!(count>settings["maxRetries"].as_u64().unwrap_or(2));
          failure["retryGeneration"]=json!(retry_generation);
          if let Err(e)=append(&app.runtime.join("runtime-failures.jsonl"), &failure) {eprintln!("runtime failure journal: {e}")}
          if failure["terminal"]!=true {jobs.insert(key.clone(),row);}
          failures.insert(key, failure);
          app.failed.fetch_add(1, Ordering::Relaxed);
        }
      }
    }
    if settings_task.as_ref().is_some_and(|t|t.is_finished()) {
      match settings_task.take().unwrap().await {
        Ok((id,answer))=>{
          settings_reply=Some((id,answer));
          settings_reply_at=Instant::now()-Duration::from_secs(2);
        },
        Err(e)=>{eprintln!("settings worker: {e}");last_id.clear();},
      }
    }
    if settings_reply.is_some() && settings_reply_at.elapsed()>=Duration::from_secs(1) {
      let (id,answer)=settings_reply.as_ref().unwrap();
      match atomic(&app.root.join("settings-response.json"),answer) {
        Ok(())=>{
          // Acknowledge only after delivery. Retry the saved reply, never the
          // potentially non-idempotent settings operation, on a write failure.
          if read_json(&app.root.join("settings-request.json"),32768).is_ok_and(|r|r["id"]==*id) {
            if let Err(e)=atomic(&app.root.join("settings-request.json"),&json!({"version":1,"processed":id})) {eprintln!("settings acknowledgement: {e}");}
          }
          settings_reply=None;
        }
        Err(e)=>{eprintln!("settings response: {e}");}
      }
      settings_reply_at=Instant::now();
    }
    if settings_task.is_none() && settings_reply.is_none() {if let Ok(request) = read_json(&app.root.join("settings-request.json"), 32768) {
      if let Some(id) = request["id"].as_str() {
        if id != last_id {
          last_id = id.into();
          let a=app.clone();let id=id.to_string();
          settings_task=Some(tokio::spawn(async move {
            let answer=tokio::time::timeout(Duration::from_secs(125),a.settings_request(&request)).await
              .ok().and_then(Result::ok).unwrap_or_else(||json!({"version":1,"id":id,"ok":false,"error":"設定無效或連線失敗"}));
            (id,answer)
          }));
        }
      }
    }}
    let context = app.context();
    let world = context["world"].as_str().unwrap_or("");
    let language = context["language"].as_str().unwrap_or("zh-Hant");
    let next_scope=format!("{world}\0{language}");
    if scope!=next_scope {
      scope=next_scope;tail=Tail::default();jobs.clear();
      failures.retain(|_,row|row["world"]==world && row["language"].as_str().unwrap_or("zh-Hant")==language);
    }
    let settings = app.settings.lock().unwrap().effective(world);
    // The first visible prose may fail before the asynchronous world-name
    // export is ready. A newly published registry is new translation context,
    // so allow the bounded retry budget again without requiring a UI revisit.
    let registry_revision=std::fs::metadata(app.runtime.join("world-names.json")).ok()
      .and_then(|m|Some((m.modified().ok()?.duration_since(std::time::UNIX_EPOCH).ok()?.as_nanos().to_string(),m.len())));
    let generation=hash(serde_json::to_vec(&json!([settings,app.settings.lock().unwrap().selected(world),registry_revision])).unwrap());
    if generation!=retry_generation {
      failures.retain(|_,row|row["retryGeneration"]==generation);
      retry_generation=generation;tail=Tail::default();
    }
    if settings["officialAutoDownload"] != true {auto_at.clear();}
    if settings["officialAutoDownload"] == true
      && now() - auto_at.get(language).copied().unwrap_or(0) > 6 * 60 * 60 * 1000
    {
      auto_at.insert(language.into(), now());
      let o = app.official.clone();
      let l = language.to_owned();
      tokio::spawn(async move {
        let _ = o.sync(l).await;
      });
    }
    let visible = read_json(&app.runtime.join("runtime-visible.json"), 2 * 1024 * 1024)
      .ok()
      .filter(|v| v["world"] == world)
      .and_then(|v| v["ids"].as_array().cloned())
      .unwrap_or_default();
    let visible = visible.iter().filter_map(Value::as_str).map(str::to_owned).collect::<HashSet<_>>();
    if visible!=previous_visible {tail=Tail::default();previous_visible=visible.clone();}
    jobs.retain(|_, row| runtime_request_current(row, world, &visible) && row["language"].as_str().unwrap_or("zh-Hant")==language);
    if deferred && jobs.len()<512 {tail=Tail::default();deferred=false;}
    if let Ok(rows) = tail.read(&app.runtime.join("runtime-requests.jsonl")) {
      for row in rows {
        if !runtime_request_current(&row, world, &visible)
          || row["language"].as_str().unwrap_or("zh-Hant")!=language
          || row["text"].as_str().is_none_or(|s| s.is_empty() || s.len() > 8000)
        {
          continue;
        }
        let key = runtime_key(&row);
        if !completed.contains_key(&key) && !inflight.contains_key(&key) && !failures.get(&key).is_some_and(|v|v["terminal"]==true) {
          if jobs.len()>=1024 && !jobs.contains_key(&key) {
            deferred=true;
            if row["priority"]=="foreground" {
              let background=jobs.iter().find(|(_,r)|r["priority"]!="foreground").map(|(k,_)|k.clone());
              if let Some(background)=background {jobs.remove(&background);} else {continue}
            } else {continue}
          }
          jobs.insert(key, row);
        }
      }
    }
    let paused = settings["backgroundTranslation"] != true
      || read_json(&app.runtime.join("translation-controls.json"), 8192).is_ok_and(|v| v["backgroundPaused"] == true);
    let mut keys = jobs.keys().cloned().collect::<Vec<_>>();
    keys.sort_by_key(|k| if jobs[k]["priority"] == "foreground" { 0 } else { 2 });
    for key in keys {
      if inflight.len() >= 16 {
        break;
      }
      let row = &jobs[&key];
      if row["priority"] != "foreground"
        && (paused
          || settings["apiEnabled"] != true
          || app.pool.active.load(Ordering::Relaxed) > 0
          || !inflight.is_empty())
      {
        continue;
      }
      if let Some(f) = failures.get(&key) {
        if now() < f["retryAt"].as_i64().unwrap_or(0)
          || f["attempts"].as_u64().unwrap_or(0) > settings["maxRetries"].as_u64().unwrap_or(2)
        {
          continue;
        }
      }
      let row = jobs.remove(&key).unwrap();
      let a = app.clone();
      let tx = done_tx.clone();
      inflight.insert(key.clone(),row.clone());
      app.runtime_active.fetch_add(1, Ordering::Relaxed);
      app.attempted.fetch_add(1, Ordering::Relaxed);
      tokio::spawn(async move {
        let deadline=Duration::from_millis(a.settings.lock().unwrap().effective(row["world"].as_str().unwrap_or(""))["timeoutMs"].as_u64().unwrap_or(25000));
        let request=row.clone();
        let mut task=tokio::spawn(async move {a.runtime_row(&request).await});
        let result=match tokio::time::timeout(deadline,&mut task).await {
          Ok(Ok(result))=>result,
          Ok(Err(_))=>Err(anyhow::anyhow!("runtime worker failed")),
          Err(_)=>{task.abort();Err(anyhow::anyhow!("runtime deadline exceeded"))},
        };
        let _ = tx.send((key, row, result)).await;
      });
    }
    if status_at.elapsed() > Duration::from_millis(500) {
      let foreground=|row:&&Value|row["priority"]=="foreground";
      let current=|row:&&Value|row["world"]==world && row["language"].as_str().unwrap_or("zh-Hant")==language;
      let active_fg=inflight.values().filter(current).filter(foreground).count();
      let active_total=inflight.values().filter(current).count();
      let queued=jobs.iter().filter(|(key,_)|!failures.get(*key).is_some_and(|f|f["terminal"]==true)).map(|(_,row)|row).collect::<Vec<_>>();
      let queued_fg=queued.iter().copied().filter(foreground).count();
      *app.runtime_snapshot.lock().unwrap()=json!({"foregroundActive":active_fg,"backgroundActive":active_total-active_fg,
        "foregroundQueued":queued_fg,"backgroundQueued":queued.len()-queued_fg,"unresolved":failures.values().filter(current).count(),"retryGeneration":retry_generation});
      let _ = app.publish_status();
      status_at = Instant::now();
    }
    if prewarm_at.elapsed() > Duration::from_secs(5) && prewarm_task.as_ref().is_none_or(|t|t.is_finished()) {
      let a=app.clone();
      prewarm_task=Some(tokio::task::spawn_blocking(move || {
        if let Err(e)=a.prewarm() {eprintln!("prewarm export: {e}")}
      }));
      prewarm_at = Instant::now();
    }
    if shared_at.elapsed() > Duration::from_secs(15) {
      let s = app.shared.clone();
      let scope = world.to_owned();
      tokio::spawn(async move {
        let _ = s.flush(&scope).await;
      });
      shared_at = Instant::now();
    }
    tokio::time::sleep(Duration::from_millis(100)).await;
  }
}
#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn quality_item_templates_translate_the_inner_prose() {
    let p=prepare("{olm Remains}", &json!({}));
    assert_eq!(p.text,"olm Remains");
    assert_eq!(p.restore("洞螈殘骸","{olm Remains}").unwrap(),"{洞螈殘骸}");
    let p=prepare("{DWARF_NAME} likes quartzite.", &json!({}));
    assert!(p.text.contains("{DWARF_NAME}"));
  }
  #[test]
  fn runtime_visibility_preserves_world_and_legends_boundaries() {
    let visible = HashSet::from([String::from("site:1")]);
    let plain = json!({"world":"region1","text":"One sentence","priority":"background"});
    assert!(runtime_request_current(&plain, "region1", &HashSet::new()));
    assert!(!runtime_request_current(&plain, "region2", &visible));
    let mut legend = json!({"world":"region1","kind":"legends-name","visibilityId":"site:1"});
    assert!(runtime_request_current(&legend, "region1", &visible));
    assert!(!runtime_request_current(&legend, "region1", &HashSet::new()));
    assert!(!runtime_request_current(&legend, "region2", &visible));
    legend.as_object_mut().unwrap().remove("visibilityId");
    assert!(!runtime_request_current(&legend, "region1", &visible));
    assert!(!runtime_request_current(&json!({"world":"region1","figureId":1}), "region1", &visible));
    assert!(!runtime_request_current(&json!({"world":"region1","visibilityId":"offscreen"}), "region1", &visible));
  }

  #[test]
  fn templates_protect_names_and_color_numbers() {
    let p = prepare("[C:7:0:1] Urist has 2 wounds.", &json!({"Urist":"烏瑞斯特"}));
    assert_eq!(p.text, "[C:7:0:1] {{DFE0}} has {{DFN0}} wounds.");
    assert_eq!(
      p.restore(
        "[C:7:0:1] {{DFE0}}有 {{DFN0}} 處傷口。",
        "[C:7:0:1] Urist has 2 wounds."
      )
      .unwrap(),
      "[C:7:0:1] 烏瑞斯特有 2 處傷口。"
    );
  }
  #[test]
  fn runtime_keys_keep_existing_language_compatibility() {
    let row = json!({"world":"region1","text":"Health"});
    assert_eq!(
      runtime_key(&row),
      format!("DFLIVE_{}", hash(br#"["region1","Health"]"#))
    );
    let mut hans = row;
    hans["language"] = json!("zh-Hans");
    assert_ne!(
      runtime_key(&hans),
      runtime_key(&json!({"world":"region1","text":"Health"}))
    );
  }
  #[test]
  fn file_tail_preserves_interrupted_record() {
    let d = tempfile::tempdir().unwrap();
    let p = d.path().join("requests");
    std::fs::write(&p, b"{\"id\":1}\n{\"id\":").unwrap();
    let mut t = Tail::default();
    assert_eq!(t.read(&p).unwrap(), vec![json!({"id":1})]);
    use std::io::Write;
    std::fs::OpenOptions::new().append(true).open(&p).unwrap().write_all(b"2}\n").unwrap();
    assert_eq!(t.read(&p).unwrap(), vec![json!({"id":2})]);
  }
}
