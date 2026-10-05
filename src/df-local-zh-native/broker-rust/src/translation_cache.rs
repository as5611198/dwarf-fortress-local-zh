//! Bounded hot cache with a rebuildable, journal-verified disk index.
use crate::{bounded::BoundedMap, common::{POLICY, append, cache_key, iso, language, validate}};
use anyhow::{Context, Result, ensure};
use rusqlite::{Connection, ErrorCode, OptionalExtension, params};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{fs::File, io::{BufRead, BufReader, Read, Seek, SeekFrom}, path::{Path, PathBuf}, time::SystemTime};

pub(super) const MAX_ROW: usize = 512 * 1024;
const INDEX_FILE: &str = "translations-index-v1.sqlite3";
type Stamp = (u64, Option<SystemTime>, Option<SystemTime>);

pub(crate) struct TranslationCache {
  journal: PathBuf,
  db: Connection,
  hot: BoundedMap<String, String>,
  observed: Option<Stamp>,
  ready: bool,
  digest: Sha256,
  bytes: u64,
}

fn stamp(path: &Path) -> Result<Option<Stamp>> {
  match std::fs::metadata(path) {
    Ok(m) => Ok(Some((m.len(), m.modified().ok(), m.created().ok()))),
    Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
    Err(e) => Err(e.into()),
  }
}

fn connection(path: &Path) -> rusqlite::Result<Connection> {
  let db = Connection::open(path)?;
  db.busy_timeout(std::time::Duration::from_secs(2))?;
  db.execute_batch("PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL;
    PRAGMA cache_size=-2048; PRAGMA mmap_size=0; PRAGMA temp_store=FILE;
    CREATE TABLE IF NOT EXISTS records (key TEXT PRIMARY KEY, row TEXT NOT NULL) WITHOUT ROWID;
    CREATE TABLE IF NOT EXISTS snapshot (id INTEGER PRIMARY KEY CHECK(id=1), policy TEXT NOT NULL,
      bytes INTEGER NOT NULL, digest BLOB NOT NULL);")?;
  let integrity: String = db.query_row("PRAGMA quick_check(1)", [], |r| r.get(0))?;
  if integrity != "ok" {
    return Err(rusqlite::Error::SqliteFailure(rusqlite::ffi::Error::new(rusqlite::ffi::SQLITE_CORRUPT), None));
  }
  Ok(db)
}

// Preserve all validation and last-valid-record semantics of the old loader.
pub(super) fn valid_record(row: &Value) -> Option<(String, String)> {
  let lang = row["language"].as_str()?;
  let kind = row["kind"].as_str()?;
  let source = row["source"].as_str()?;
  let key = row["key"].as_str()?;
  if row["policy"] != POLICY || !language(lang)
    || !["exact", "numeric", "entity", "name", "link", "phonetic"].contains(&kind)
    || key != cache_key(source, lang, kind) { return None; }
  let validation = if matches!(kind, "name" | "link") { row["preferred"].as_str().unwrap_or("") } else { source };
  validate(validation, row["translation"].as_str().unwrap_or("")).ok().map(|value| (key.into(), value))
}

impl TranslationCache {
  pub fn open(root: &Path) -> Result<Self> {
    let path = root.join(INDEX_FILE);
    let db = match connection(&path) {
      Ok(db) => db,
      Err(error) if matches!(error.sqlite_error_code(), Some(ErrorCode::DatabaseCorrupt | ErrorCode::NotADatabase)) => {
        let backup = root.join(format!("translations-index-corrupt-{}.sqlite3", uuid::Uuid::new_v4()));
        std::fs::rename(&path, &backup).context("preserve corrupt translation index")?;
        eprintln!("Rebuilding corrupt translation index; preserved {}", backup.display());
        connection(&path)?
      }
      Err(error) => return Err(error).context("open translation index"),
    };
    let mut cache = Self { journal: root.join("translations.jsonl"), db,
      hot: BoundedMap::new(16_384), observed: None, ready: false, digest: Sha256::new(), bytes: 0 };
    cache.synchronize()?;
    if let Err(error) = cache.startup_maintenance() {
      eprintln!("Translation journal maintenance deferred: {error}");
      // Replacement may have succeeded before a later index/metadata error.
      cache.ready = false;
      cache.synchronize()?;
    }
    Ok(cache)
  }

  pub fn len(&self) -> usize { self.hot.len() }

  fn startup_maintenance(&mut self) -> Result<()> {
    crate::journal_compaction::cleanup_staging(&self.journal)?;
    const MIN_BYTES: u64 = 16 * 1024 * 1024;
    const MIN_GROWTH: u64 = 8 * 1024 * 1024;
    if self.bytes < MIN_BYTES { return Ok(()); }
    self.db.execute_batch("CREATE TABLE IF NOT EXISTS maintenance (
      id INTEGER PRIMARY KEY CHECK(id=1), policy TEXT NOT NULL, bytes INTEGER NOT NULL, digest BLOB NOT NULL)")?;
    let hash = self.digest.clone().finalize().to_vec();
    let previous: Option<(String,i64,Vec<u8>)> = self.db.query_row(
      "SELECT policy,bytes,digest FROM maintenance WHERE id=1",[],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?))).optional()?;
    if let Some((policy, size, old_hash)) = previous {
      if policy == POLICY && size >= 0 && self.bytes >= size as u64 {
        let growth = self.bytes - size as u64;
        if (growth == 0 && hash == old_hash) || (growth > 0 && growth < MIN_GROWTH) { return Ok(()); }
      }
    }
    let before = self.bytes;
    if let Some(after) = crate::journal_compaction::compact(&mut self.db,&self.journal,&hash,1024*1024)? {
      self.ready = false;
      self.synchronize()?;
      eprintln!("Translation journal compacted: {before} -> {after} bytes");
    }
    self.db.execute("INSERT OR REPLACE INTO maintenance(id,policy,bytes,digest) VALUES(1,?1,?2,?3)",
      params![POLICY,i64::try_from(self.bytes)?,self.digest.clone().finalize().to_vec()])?;
    Ok(())
  }

  fn synchronize(&mut self) -> Result<()> {
    let observed = stamp(&self.journal)?;
    if self.ready && observed == self.observed { return Ok(()); }
    let mut file = match File::open(&self.journal) {
      Ok(file) => Some(file),
      Err(e) if e.kind() == std::io::ErrorKind::NotFound && observed.is_none() => None,
      Err(e) => return Err(e).context("read translation journal"),
    };
    let mut digest = Sha256::new();
    let mut bytes = 0u64;
    if let Some(file) = file.as_mut() {
      let mut buffer = [0u8; 64 * 1024];
      loop {
        let n = file.read(&mut buffer)?;
        if n == 0 { break; }
        digest.update(&buffer[..n]); bytes += n as u64;
      }
    }
    ensure!(stamp(&self.journal)? == observed && observed.as_ref().map_or(0, |s| s.0) == bytes,
      "translation journal changed during verification");
    let hash = digest.clone().finalize().to_vec();
    let sql_bytes = i64::try_from(bytes)?;
    let previous: Option<(String, i64, Vec<u8>)> = self.db.query_row(
      "SELECT policy, bytes, digest FROM snapshot WHERE id=1", [], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).optional()?;
    if previous.as_ref().is_none_or(|(policy, size, old_hash)| policy != POLICY || *size != sql_bytes || *old_hash != hash) {
      let tx = self.db.transaction()?;
      tx.execute("DELETE FROM records", [])?;
      let mut rejected = 0usize;
      if let Some(mut file) = file {
        file.seek(SeekFrom::Start(0))?;
        let mut reader = BufReader::new(file);
        let mut line = Vec::new();
        let mut oversized = false;
        let mut insert = tx.prepare("INSERT INTO records(key,row) VALUES(?1,?2)
          ON CONFLICT(key) DO UPDATE SET row=excluded.row")?;
        loop {
          let buffer = reader.fill_buf()?;
          if buffer.is_empty() {
            if oversized { rejected += 1; }
            else if !line.is_empty() { import_line(&mut insert, &line, &mut rejected)?; }
            break;
          }
          let end = buffer.iter().position(|b| *b == b'\n').map(|i| i+1);
          let take = end.unwrap_or(buffer.len());
          if !oversized && line.len() + take <= MAX_ROW { line.extend_from_slice(&buffer[..take]); }
          else { oversized = true; line.clear(); }
          reader.consume(take);
          if end.is_some() {
            if oversized { rejected += 1; } else { import_line(&mut insert, &line, &mut rejected)?; }
            line.clear(); oversized = false;
          }
        }
      }
      ensure!(stamp(&self.journal)? == observed, "translation journal changed during indexing");
      tx.execute("INSERT OR REPLACE INTO snapshot(id,policy,bytes,digest) VALUES(1,?1,?2,?3)", params![POLICY, sql_bytes, hash])?;
      tx.commit()?;
      if rejected > 0 { eprintln!("Translation journal index skipped {rejected} invalid or oversized records"); }
    }
    self.hot.clear();
    self.observed = observed; self.ready = true; self.digest = digest; self.bytes = bytes;
    Ok(())
  }

  pub fn get(&mut self, source: &str, lang: &str, kind: &str) -> Result<Option<String>> {
    self.synchronize()?;
    let key = cache_key(source, lang, kind);
    if let Some(value) = self.hot.get(&key) { return Ok(Some(value.clone())); }
    for attempt in 0..2 {
      let row: Option<String> = self.db.query_row("SELECT row FROM records WHERE key=?1", [&key], |r| r.get(0)).optional()?;
      let Some(row) = row else { return Ok(None); };
      let parsed = serde_json::from_str::<Value>(&row).ok();
      if let Some((_, value)) = parsed.as_ref().and_then(valid_record).filter(|(stored, _)| stored == &key) {
        self.hot.insert(key, value.clone());
        return Ok(Some(value));
      }
      ensure!(attempt == 0, "translation index remains invalid after rebuilding");
      eprintln!("Invalid translation index record; rebuilding from journal");
      self.db.execute("DELETE FROM snapshot", [])?;
      self.ready = false;
      self.synchronize()?;
    }
    unreachable!("second invalid record returns an error")
  }

  pub fn save(&mut self, source: &str, lang: &str, kind: &str, value: &str, preferred: Option<&str>) -> Result<()> {
    let key = cache_key(source, lang, kind);
    let mut row = json!({"key":key,"policy":POLICY,"kind":kind,"source":source,
      "language":lang,"translation":value,"timestamp":iso()});
    if let Some(preferred) = preferred { row["preferred"] = json!(preferred); }
    ensure!(valid_record(&row).is_some(), "invalid translation cache write");
    let serialized = serde_json::to_vec(&row)?;
    ensure!(serialized.len() < MAX_ROW, "translation cache row too large");
    if self.get(source, lang, kind)?.as_deref() == Some(value) { return Ok(()); }
    append(&self.journal, &row)?;
    // Append is durable before indexing. If indexing fails, keep the old
    // observation so the next lookup reconstructs the journal, not an AI miss.
    let observed = stamp(&self.journal)?;
    let mut file = File::open(&self.journal)?;
    file.seek(SeekFrom::Start(self.bytes))?;
    let mut tail = Vec::new();
    file.take((MAX_ROW+2) as u64).read_to_end(&mut tail)?;
    let mut expected = serialized.clone(); expected.push(b'\n');
    let matches = tail == expected || (tail.first() == Some(&b'\n') && tail[1..] == expected);
    if !matches || observed.as_ref().map(|s| s.0) != Some(self.bytes + tail.len() as u64) {
      self.ready = false;
      self.synchronize()?;
      ensure!(self.get(source, lang, kind)?.as_deref() == Some(value), "translation journal changed during append");
      return Ok(());
    }
    let mut digest = self.digest.clone(); digest.update(&tail);
    let bytes = self.bytes + tail.len() as u64;
    let tx = self.db.transaction()?;
    tx.execute("INSERT INTO records(key,row) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET row=excluded.row",
      params![key, std::str::from_utf8(&serialized)?])?;
    tx.execute("INSERT OR REPLACE INTO snapshot(id,policy,bytes,digest) VALUES(1,?1,?2,?3)",
      params![POLICY, i64::try_from(bytes)?, digest.clone().finalize().to_vec()])?;
    tx.commit()?;
    self.hot.insert(key, value.into());
    self.observed = observed; self.digest = digest; self.bytes = bytes;
    Ok(())
  }
}

fn import_line(insert: &mut rusqlite::Statement<'_>, line: &[u8], rejected: &mut usize) -> Result<()> {
  let row = serde_json::from_slice::<Value>(line).ok();
  if let Some((key, _)) = row.as_ref().and_then(valid_record) {
    insert.execute(params![key, std::str::from_utf8(line)?])?;
  } else if line.iter().any(|b| !b.is_ascii_whitespace()) { *rejected += 1; }
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::io::Write;

  fn row(source: &str, translation: &str, lang: &str, kind: &str) -> Value {
    json!({"key":cache_key(source,lang,kind),"policy":POLICY,"source":source,
      "translation":translation,"language":lang,"kind":kind})
  }

  #[test]
  fn eviction_and_restart_use_disk_without_appending_duplicate_translations() {
    let d = tempfile::tempdir().unwrap();
    let mut cache = TranslationCache::open(d.path()).unwrap();
    cache.hot = BoundedMap::new(2);
    for source in ["First.", "Second.", "Third."] {
      cache.save(source,"zh-Hant","exact","已翻譯。",None).unwrap();
    }
    assert_eq!(cache.len(),2);
    assert!(!cache.hot.contains_key(&cache_key("First.","zh-Hant","exact")));
    let before = std::fs::read(&cache.journal).unwrap();
    cache.save("First.","zh-Hant","exact","已翻譯。",None).unwrap();
    assert_eq!(std::fs::read(&cache.journal).unwrap(),before);
    // A persistent trigger makes an unnecessary re-import fail on restart.
    cache.db.execute_batch("CREATE TRIGGER forbid_reimport BEFORE INSERT ON records
      BEGIN SELECT RAISE(ABORT,'unchanged journal must reuse its index'); END;").unwrap();
    drop(cache);
    let mut reopened = TranslationCache::open(d.path()).unwrap();
    assert_eq!(reopened.get("First.","zh-Hant","exact").unwrap().as_deref(),Some("已翻譯。"));
    assert_eq!(std::fs::read(&reopened.journal).unwrap(),before);
  }

  #[test]
  fn import_keeps_latest_valid_row_and_language_kind_and_name_validation() {
    let d = tempfile::tempdir().unwrap();
    let path = d.path().join("translations.jsonl");
    for value in ["他很平靜。","他很冷靜。","English must be rejected."] {
      append(&path,&row("He is calm.",value,"zh-Hant","exact")).unwrap();
    }
    append(&path,&row("He is calm.","他很冷静。","zh-Hans","exact")).unwrap();
    let template = "{{DFN0}} dwarves.";
    append(&path,&row(template,"{{DFN0}}名矮人。","zh-Hant","numeric")).unwrap();
    let mut bad = row("Invalid policy.","錯誤策略。","zh-Hant","exact");
    bad["policy"]=json!("old"); append(&path,&bad).unwrap();
    bad=row("Invalid key.","錯誤鍵。","zh-Hant","exact");bad["key"]=json!("other");append(&path,&bad).unwrap();
    let mut name = row("[\"world\",\"figure:7\",\"Urist 2\"]","烏里斯特 2","zh-Hant","name");
    name["preferred"]=json!("Urist 2");append(&path,&name).unwrap();
    name["translation"]=json!("烏里斯特 3");append(&path,&name).unwrap();
    let before=std::fs::read(&path).unwrap();
    let mut cache = TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("He is calm.","zh-Hant","exact").unwrap().as_deref(),Some("他很冷靜。"));
    assert_eq!(cache.get("He is calm.","zh-Hans","exact").unwrap().as_deref(),Some("他很冷静。"));
    assert_eq!(cache.get(template,"zh-Hant","numeric").unwrap().as_deref(),Some("{{DFN0}}名矮人。"));
    assert!(cache.get(template,"zh-Hant","exact").unwrap().is_none());
    assert!(cache.get("Invalid policy.","zh-Hant","exact").unwrap().is_none());
    assert!(cache.get("Invalid key.","zh-Hant","exact").unwrap().is_none());
    assert_eq!(cache.get(name["source"].as_str().unwrap(),"zh-Hant","name").unwrap().as_deref(),Some("烏里斯特 2"));
    assert_eq!(std::fs::read(path).unwrap(),before);
  }

  #[test]
  fn oversized_and_interrupted_rows_do_not_hide_the_following_valid_translation() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut f=File::create(&path).unwrap();
    f.write_all(&vec![b'x';MAX_ROW*3]).unwrap();f.write_all(b"\n").unwrap();
    writeln!(f,"{}",row("After oversized.","過長紀錄之後。","zh-Hant","exact")).unwrap();
    f.write_all(b"{\"interrupted\":").unwrap();drop(f);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("After oversized.","zh-Hant","exact").unwrap().as_deref(),Some("過長紀錄之後。"));
    cache.save("After interruption.","zh-Hant","exact","中斷之後。",None).unwrap();
    drop(cache);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("After interruption.","zh-Hant","exact").unwrap().as_deref(),Some("中斷之後。"));
    // Legacy journals may end with valid JSON but no line terminator.
    std::fs::write(&path,row("No newline.","沒有換行。","zh-Hant","exact").to_string()).unwrap();
    assert_eq!(cache.get("No newline.","zh-Hant","exact").unwrap().as_deref(),Some("沒有換行。"));
    assert!(cache.get("After oversized.","zh-Hant","exact").unwrap().is_none());
  }

  #[test]
  fn deletion_and_same_length_replacement_cannot_resurrect_cleared_translations() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut cache=TranslationCache::open(d.path()).unwrap();
    cache.save("Old.","zh-Hant","exact","舊。",None).unwrap();
    std::fs::remove_file(&path).unwrap();
    assert!(cache.get("Old.","zh-Hant","exact").unwrap().is_none());
    assert_eq!(cache.len(),0);
    cache.save("New.","zh-Hant","exact","新。",None).unwrap();
    let stamp=std::fs::metadata(&path).unwrap();
    let text=std::fs::read_to_string(&path).unwrap();
    drop(cache);
    // Keep length and mtime identical: cold-start SHA-256 must still detect it.
    std::fs::write(&path,text.replace("新。","改。")).unwrap();
    File::options().write(true).open(&path).unwrap().set_modified(stamp.modified().unwrap()).unwrap();
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("New.","zh-Hant","exact").unwrap().as_deref(),Some("改。"));
    std::fs::write(&path,b"").unwrap();
    assert!(cache.get("New.","zh-Hant","exact").unwrap().is_none());
  }

  #[test]
  fn index_failure_after_durable_append_recovers_without_a_second_append() {
    let d=tempfile::tempdir().unwrap();let mut cache=TranslationCache::open(d.path()).unwrap();
    cache.db.execute_batch("CREATE TRIGGER reject_index BEFORE INSERT ON records
      BEGIN SELECT RAISE(ABORT,'injected index commit failure'); END;").unwrap();
    assert!(cache.save("Durable.","zh-Hant","exact","已落盤。",None).is_err());
    assert_eq!(cache.len(),0);
    assert!(cache.get("Durable.","zh-Hant","exact").is_err(),"index failure must not become an AI cache miss");
    let before=std::fs::read(&cache.journal).unwrap();
    cache.db.execute_batch("DROP TRIGGER reject_index").unwrap();
    assert_eq!(cache.get("Durable.","zh-Hant","exact").unwrap().as_deref(),Some("已落盤。"));
    cache.save("Durable.","zh-Hant","exact","已落盤。",None).unwrap();
    assert_eq!(std::fs::read(&cache.journal).unwrap(),before);
  }

  #[test]
  fn corrupt_index_is_preserved_and_rebuilt_from_the_unchanged_journal() {
    let d=tempfile::tempdir().unwrap();
    let mut cache=TranslationCache::open(d.path()).unwrap();
    cache.save("Recover.","zh-Hant","exact","恢復。",None).unwrap();
    let journal=std::fs::read(&cache.journal).unwrap();drop(cache);
    std::fs::write(d.path().join(INDEX_FILE),b"not a sqlite database").unwrap();
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("Recover.","zh-Hant","exact").unwrap().as_deref(),Some("恢復。"));
    assert_eq!(std::fs::read(&cache.journal).unwrap(),journal);
    let backups:Vec<_>=std::fs::read_dir(d.path()).unwrap().flatten()
      .filter(|p|p.file_name().to_string_lossy().starts_with("translations-index-corrupt-")).collect();
    assert_eq!(backups.len(),1);
    assert_eq!(std::fs::read(backups[0].path()).unwrap(),b"not a sqlite database");
  }

  #[test]
  fn invalid_index_payload_recovers_from_journal_without_poisoning_the_lookup() {
    let d=tempfile::tempdir().unwrap();let mut cache=TranslationCache::open(d.path()).unwrap();
    cache.save("Recover row.","zh-Hant","exact","恢復這筆。",None).unwrap();
    let before=std::fs::read(&cache.journal).unwrap();
    cache.db.execute("UPDATE records SET row='not json'",[]).unwrap();
    cache.hot.clear();
    assert_eq!(cache.get("Recover row.","zh-Hant","exact").unwrap().as_deref(),Some("恢復這筆。"));
    assert_eq!(std::fs::read(&cache.journal).unwrap(),before);
    // A validator-invalid journal row is a genuine miss after reconstruction,
    // not a permanent database failure that prevents obtaining a valid result.
    let invalid=row("Rejected row.","English only.","zh-Hant","exact");
    cache.db.execute("INSERT INTO records(key,row) VALUES(?1,?2)",
      params![invalid["key"].as_str().unwrap(),invalid.to_string()]).unwrap();
    assert!(cache.get("Rejected row.","zh-Hant","exact").unwrap().is_none());
  }

  #[test]
  fn journal_write_failure_never_creates_an_index_only_success() {
    let d=tempfile::tempdir().unwrap();let mut cache=TranslationCache::open(d.path()).unwrap();
    std::fs::create_dir(&cache.journal).unwrap();
    assert!(cache.save("Unwritten.","zh-Hant","exact","未寫入。",None).is_err());
    assert_eq!(cache.len(),0);
    std::fs::remove_dir(&cache.journal).unwrap();
    assert!(cache.get("Unwritten.","zh-Hant","exact").unwrap().is_none());
  }

  #[test]
  fn startup_compacts_superseded_translations_and_reopens_without_losing_values() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut old=row("Repeated history.","舊譯文。","zh-Hant","exact");
    old["provenance"]=json!("x".repeat(1024));
    let line=old.to_string();
    let mut writer=std::io::BufWriter::new(File::create(&path).unwrap());
    for _ in 0..16_384 {writeln!(writer,"{line}").unwrap();}
    let latest=row("Repeated history.","最新譯文。","zh-Hant","exact");
    writeln!(writer,"{latest}").unwrap();writer.flush().unwrap();drop(writer);
    assert!(std::fs::metadata(&path).unwrap().len()>16*1024*1024);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(std::fs::metadata(&path).unwrap().len(),latest.to_string().len() as u64+1,"obsolete history should be reclaimed");
    assert_eq!(std::fs::read_to_string(&path).unwrap(),format!("{latest}\n"),"obsolete history should be reclaimed");
    assert_eq!(cache.get("Repeated history.","zh-Hant","exact").unwrap().as_deref(),Some("最新譯文。"));
    cache.save("After compaction.","zh-Hant","exact","整理後。",None).unwrap();drop(cache);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("Repeated history.","zh-Hant","exact").unwrap().as_deref(),Some("最新譯文。"));
    assert_eq!(cache.get("After compaction.","zh-Hant","exact").unwrap().as_deref(),Some("整理後。"));
  }

  #[test]
  fn replacement_before_index_commit_failure_is_recoverable_on_restart() {
    let d=tempfile::tempdir().unwrap();let mut cache=TranslationCache::open(d.path()).unwrap();
    let mut old=row("Committed journal.","已提交。","zh-Hant","exact");old["extra"]=json!("x".repeat(1024));
    let line=old.to_string();
    let mut writer=std::io::BufWriter::new(File::create(&cache.journal).unwrap());
    for _ in 0..16_384 {writeln!(writer,"{line}").unwrap();}writer.flush().unwrap();drop(writer);
    cache.synchronize().unwrap();
    cache.db.execute_batch("CREATE TRIGGER reject_snapshot BEFORE INSERT ON snapshot
      BEGIN SELECT RAISE(ABORT,'injected index snapshot failure'); END;").unwrap();
    assert!(cache.startup_maintenance().is_err());
    assert_eq!(std::fs::metadata(&cache.journal).unwrap().len(),line.len() as u64+1);
    cache.db.execute_batch("DROP TRIGGER reject_snapshot").unwrap();drop(cache);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    assert_eq!(cache.get("Committed journal.","zh-Hant","exact").unwrap().as_deref(),Some("已提交。"));
  }

  #[test]
  #[cfg(windows)]
  fn unchanged_maintenance_watermark_skips_another_full_scan() {
    use std::os::windows::fs::OpenOptionsExt;
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    // An opaque record cannot be compacted. Its size crosses the startup gate.
    let mut file=File::create(&path).unwrap();
    for _ in 0..257 {file.write_all(&[b'x';64*1024]).unwrap();}drop(file);
    let mut cache=TranslationCache::open(d.path()).unwrap();
    let exclusive=File::options().read(true).share_mode(0).open(&path).unwrap();
    // Metadata is already validated by synchronize; maintenance must now use
    // its persisted watermark rather than trying to reopen the locked journal.
    cache.startup_maintenance().unwrap();
    drop(exclusive);
    assert_eq!(std::fs::metadata(&path).unwrap().len(),257*64*1024);
  }

  #[test]
  #[ignore = "explicit 100,000-row startup compaction benchmark"]
  fn journal_compaction_benchmark() {
    use std::time::Instant;
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut writer=std::io::BufWriter::new(File::create(&path).unwrap());
    for revision in 0..10 {for i in 0..10_000 {
      let translation=if revision==9 {format!("最新歷史紀錄 {i}。")} else {format!("先前歷史紀錄 {i}。")};
      writeln!(writer,"{}",row(&format!("History entry {i}."),&translation,"zh-Hant","exact")).unwrap();
    }}
    writer.flush().unwrap();drop(writer);
    let before=std::fs::metadata(&path).unwrap().len();assert!(before>16*1024*1024);
    let start=Instant::now();let mut cache=TranslationCache::open(d.path()).unwrap();let first=start.elapsed();
    let after=std::fs::metadata(&path).unwrap().len();assert_eq!(after*10,before);
    for i in 0..10_000 {
      assert_eq!(cache.get(&format!("History entry {i}."),"zh-Hant","exact").unwrap(),Some(format!("最新歷史紀錄 {i}。")));
    }
    let compact_hash=crate::common::hash(std::fs::read(&path).unwrap());drop(cache);
    let start=Instant::now();let mut cache=TranslationCache::open(d.path()).unwrap();let reopen=start.elapsed();
    assert_eq!(cache.get("History entry 0.","zh-Hant","exact").unwrap().as_deref(),Some("最新歷史紀錄 0。"));
    assert_eq!(cache.get("History entry 9999.","zh-Hant","exact").unwrap().as_deref(),Some("最新歷史紀錄 9999。"));
    assert_eq!(crate::common::hash(std::fs::read(&path).unwrap()),compact_hash);
    println!("COMPACTION_BENCH original_rows=100000 retained_keys=10000 before_bytes={before} after_bytes={after} first_open_ms={:.3} reopen_ms={:.3}",
      first.as_secs_f64()*1000.0,reopen.as_secs_f64()*1000.0);
  }

  #[test]
  #[ignore = "explicit 50,000-record durable-cache benchmark"]
  fn durable_cache_benchmark() {
    use std::time::Instant;
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut out=std::io::BufWriter::new(File::create(&path).unwrap());
    for i in 0..50_000 {
      writeln!(out,"{}",row(&format!("Historical text {i}."),&format!("歷史文字 {i}。"),"zh-Hant","exact")).unwrap();
    }
    out.flush().unwrap();drop(out);
    let journal_before=crate::common::hash(std::fs::read(&path).unwrap());
    let start=Instant::now();let mut legacy=BoundedMap::new(16_384);
    for line in BufReader::new(File::open(&path).unwrap()).lines() {
      let value:Value=serde_json::from_str(&line.unwrap()).unwrap();
      if let Some((key,value))=valid_record(&value) {legacy.insert(key,value);}
    }
    let legacy_time=start.elapsed();
    assert!(!legacy.contains_key(&cache_key("Historical text 0.","zh-Hant","exact")));drop(legacy);
    let start=Instant::now();let mut cache=TranslationCache::open(d.path()).unwrap();
    let first=start.elapsed();
    for i in 0..50_000 {
      assert_eq!(cache.get(&format!("Historical text {i}."),"zh-Hant","exact").unwrap(),Some(format!("歷史文字 {i}。")));
    }
    assert_eq!(cache.len(),16_384);
    assert!(!cache.hot.contains_key(&cache_key("Historical text 0.","zh-Hant","exact")));
    assert_eq!(cache.get("Historical text 0.","zh-Hant","exact").unwrap().as_deref(),Some("歷史文字 0。"));
    drop(cache);
    let start=Instant::now();let mut cache=TranslationCache::open(d.path()).unwrap();let restart=start.elapsed();
    assert_eq!(cache.len(),0);
    let start=Instant::now();
    for i in 0..1000 {
      assert_eq!(cache.get(&format!("Historical text {i}."),"zh-Hant","exact").unwrap(),Some(format!("歷史文字 {i}。")));
    }
    let lookup=start.elapsed();
    assert_eq!(crate::common::hash(std::fs::read(&path).unwrap()),journal_before);
    println!("DURABLE_CACHE_BENCH rows=50000 journal_bytes={} index_bytes={} legacy_load_ms={:.3} first_import_ms={:.3} reopen_ms={:.3} cold_1000_queries_ms={:.3} max_observed_hot_entries=16384",
      std::fs::metadata(&path).unwrap().len(),std::fs::metadata(d.path().join(INDEX_FILE)).unwrap().len(),
      legacy_time.as_secs_f64()*1000.0,first.as_secs_f64()*1000.0,restart.as_secs_f64()*1000.0,lookup.as_secs_f64()*1000.0);
  }
}
