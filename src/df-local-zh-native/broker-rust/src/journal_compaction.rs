//! Reclaim only superseded valid rows. Opaque rows remain byte-for-byte intact.
use crate::translation_cache::{MAX_ROW, valid_record};
use anyhow::{Result, ensure};
use rusqlite::{Connection, params};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::{fs::File, io::{BufRead, BufReader, BufWriter, Read, Seek, SeekFrom, Write}, path::{Path, PathBuf}};

struct StagedFile(PathBuf);
impl Drop for StagedFile {
  fn drop(&mut self) {
    if let Err(error)=std::fs::remove_file(&self.0) {
      if error.kind()!=std::io::ErrorKind::NotFound {eprintln!("Unable to clean journal staging file: {error}");}
    }
  }
}

pub(super) fn compact(db: &mut Connection, journal: &Path, expected_hash: &[u8], minimum_saved: u64) -> Result<Option<u64>> {
  compact_with_replace(db,journal,expected_hash,minimum_saved,crate::common::replace)
}

// Called only at broker startup, before accepting requests. The broker's
// single-writer ownership makes a prior UUID staging file an abandoned stage.
pub(super) fn cleanup_staging(journal:&Path)->Result<()> {
  let parent=journal.parent().ok_or_else(||anyhow::anyhow!("journal has no parent"))?;
  let stem=journal.file_stem().and_then(|s|s.to_str()).ok_or_else(||anyhow::anyhow!("invalid journal filename"))?;
  let prefix=format!("{stem}.compact-");
  for entry in std::fs::read_dir(parent)? {
    let entry=entry?;
    if !entry.file_type()?.is_file() {continue;}
    let name=entry.file_name();let Some(name)=name.to_str() else {continue;};
    if name.strip_prefix(&prefix).and_then(|s|s.strip_suffix(".tmp"))
      .is_some_and(|s|uuid::Uuid::parse_str(s).is_ok()) {std::fs::remove_file(entry.path())?;}
  }
  Ok(())
}

fn compact_with_replace(db: &mut Connection, journal: &Path, expected_hash: &[u8], minimum_saved: u64,
  replace: impl FnOnce(&Path,&Path)->Result<()>) -> Result<Option<u64>> {
  // This table is rebuilt from the authoritative file, never from the cache
  // index. SQLite's file-backed temp store keeps unique-key memory bounded.
  db.execute_batch("PRAGMA temp_store=FILE; DROP TABLE IF EXISTS temp.compact_rows;
    CREATE TEMP TABLE compact_rows (key TEXT PRIMARY KEY, offset INTEGER NOT NULL UNIQUE, bytes INTEGER NOT NULL);
    PRAGMA temp.cache_size=-2048;")?;
  let result = stage_and_replace(db,journal,expected_hash,minimum_saved,replace);
  let cleanup = db.execute_batch("DROP TABLE IF EXISTS temp.compact_rows");
  match result { Err(error)=>Err(error), Ok(result)=>{cleanup?;Ok(result)} }
}

fn stage_and_replace(db: &mut Connection, journal: &Path, expected_hash: &[u8], minimum_saved: u64,
  replace: impl FnOnce(&Path,&Path)->Result<()>) -> Result<Option<u64>> {
  let source=File::open(journal)?;
  let observed=source.metadata()?;
  let mut reader=BufReader::new(source);
  let mut original=Sha256::new();
  let mut offset=0u64;
  let mut length=0u64;
  let mut line=Vec::new();
  let mut oversized=false;
  {
    let tx=db.transaction()?;
    {
      let mut insert=tx.prepare("INSERT INTO compact_rows(key,offset,bytes) VALUES(?1,?2,?3)
        ON CONFLICT(key) DO UPDATE SET offset=excluded.offset,bytes=excluded.bytes")?;
      loop {
        let buffer=reader.fill_buf()?;
        if buffer.is_empty() {
          if length>0 {record_span(&mut insert,&line,oversized,offset,length)?;offset+=length;}
          break;
        }
        let end=buffer.iter().position(|b|*b==b'\n').map(|i|i+1);
        let take=end.unwrap_or(buffer.len());
        original.update(&buffer[..take]);length+=take as u64;
        if !oversized && line.len()+take<=MAX_ROW {line.extend_from_slice(&buffer[..take]);}
        else {oversized=true;line.clear();}
        reader.consume(take);
        if end.is_some() {
          record_span(&mut insert,&line,oversized,offset,length)?;
          offset+=length;length=0;line.clear();oversized=false;
        }
      }
    }
    tx.commit()?;
  }
  ensure!(&original.finalize()[..]==expected_hash,"translation journal changed before compaction");
  let wanted: i64=db.query_row("SELECT COALESCE(SUM(bytes),0) FROM compact_rows",[],|r|r.get(0))?;
  let wanted=u64::try_from(wanted)?;
  ensure!(wanted<=offset,"invalid compaction size");
  let saved=offset-wanted;
  if saved==0 || saved<minimum_saved || saved<offset/4 {return Ok(None);}

  let stage_path=journal.with_extension(format!("compact-{}.tmp",uuid::Uuid::new_v4()));
  let file=File::options().create_new(true).write(true).open(&stage_path)?;
  let staged=StagedFile(stage_path);
  let mut out=BufWriter::new(file);
  let mut source=reader.into_inner();
  {
    let mut query=db.prepare("SELECT offset,bytes FROM compact_rows ORDER BY offset")?;
    let mut rows=query.query([])?;
    while let Some(row)=rows.next()? {
      let start:i64=row.get(0)?;let length:i64=row.get(1)?;
      source.seek(SeekFrom::Start(u64::try_from(start)?))?;
      let count=std::io::copy(&mut (&mut source).take(u64::try_from(length)?),&mut out)?;
      ensure!(count==length as u64,"journal shortened while staging compaction");
    }
  }
  out.flush()?;out.get_ref().sync_all()?;drop(out);drop(source);
  // Check the current path as well as the already-open source handle. An
  // externally replaced/appended journal must not be overwritten by our stage.
  let current_hash=hash_file(journal)?;
  let current=std::fs::metadata(journal)?;
  ensure!(current_hash==expected_hash && current.len()==observed.len()
    && current.modified().ok()==observed.modified().ok() && current.created().ok()==observed.created().ok(),
    "translation journal changed while staging compaction");
  replace(&staged.0,journal)?;
  Ok(Some(wanted))
}

fn record_span(insert:&mut rusqlite::Statement<'_>,line:&[u8],oversized:bool,offset:u64,length:u64)->Result<()> {
  let key=if oversized {None} else {
    serde_json::from_slice::<Value>(line).ok().as_ref().and_then(valid_record).map(|(key,_)|key)
  };
  // Each opaque record gets its own key. Only positively validated rows can
  // supersede earlier rows, preserving other policy versions and partial data.
  let key=key.map_or_else(||format!("opaque:{offset}"),|key|format!("valid:{key}"));
  insert.execute(params![key,i64::try_from(offset)?,i64::try_from(length)?])?;
  Ok(())
}

fn hash_file(path:&Path)->Result<Vec<u8>> {
  let mut file=File::open(path)?;let mut hash=Sha256::new();let mut buffer=[0u8;64*1024];
  loop {let n=file.read(&mut buffer)?;if n==0 {break;}hash.update(&buffer[..n]);}
  Ok(hash.finalize().to_vec())
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::common::{POLICY,cache_key};
  use serde_json::json;

  fn row(text:&str,translation:&str,lang:&str)->String {
    json!({"policy":POLICY,"key":cache_key(text,lang,"exact"),"language":lang,
      "kind":"exact","source":text,"translation":translation}).to_string()+"\n"
  }
  fn db()->Connection {Connection::open_in_memory().unwrap()}

  #[test]
  fn retained_rows_keep_original_order_latest_valid_and_language_separation() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let old=row("Calm.","平靜。","zh-Hant");
    let hans=row("Calm.","冷静。","zh-Hans");
    let other=row("Other.","其他。","zh-Hant");
    let latest=row("Calm.","冷靜。","zh-Hant");
    let invalid=row("Calm.","bad English","zh-Hant");
    let source=format!("{}{}{}{}{}",old.repeat(10),hans,other,latest,invalid);
    std::fs::write(&path,&source).unwrap();
    let expected=format!("{hans}{other}{latest}{invalid}");
    assert_eq!(compact(&mut db(),&path,&hash_file(&path).unwrap(),0).unwrap(),Some(expected.len() as u64));
    assert_eq!(std::fs::read_to_string(&path).unwrap(),expected);
  }

  #[test]
  fn opaque_oversized_unknown_policy_and_partial_bytes_are_preserved() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let mut old:Value=serde_json::from_str(&row("One.","舊。","zh-Hant")).unwrap();
    old["extra"]=json!("x".repeat(300_000));
    let mut opaque=vec![b'x';MAX_ROW+5];opaque.extend_from_slice(b"\r\n\n");
    opaque.extend_from_slice(b"{\"policy\":\"future\",\"private\":\"kept\"}\n");
    let latest=row("One.","新。","zh-Hant");
    let mut source=(old.to_string()+"\n").repeat(5).into_bytes();source.extend_from_slice(&opaque);
    source.extend_from_slice(latest.as_bytes());source.extend_from_slice(b"{\"partial\":");
    std::fs::write(&path,&source).unwrap();
    let mut expected=opaque;expected.extend_from_slice(latest.as_bytes());expected.extend_from_slice(b"{\"partial\":");
    assert_eq!(compact(&mut db(),&path,&hash_file(&path).unwrap(),0).unwrap(),Some(expected.len() as u64));
    assert_eq!(crate::common::hash(std::fs::read(&path).unwrap()),crate::common::hash(&expected));
  }

  #[test]
  fn insignificant_savings_leave_original_bytes_and_do_not_call_replace() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let text=row("One.","一。","zh-Hant")+&row("Two.","二。","zh-Hant");
    std::fs::write(&path,&text).unwrap();
    assert!(compact_with_replace(&mut db(),&path,&hash_file(&path).unwrap(),0,|_,_|panic!("no saving")).unwrap().is_none());
    std::fs::write(&path,format!("{text}{text}")).unwrap();
    assert!(compact_with_replace(&mut db(),&path,&hash_file(&path).unwrap(),1024*1024,|_,_|panic!("below minimum saving")).unwrap().is_none());
    assert_eq!(std::fs::read_to_string(&path).unwrap(),format!("{text}{text}"));
  }

  #[test]
  fn replacement_failure_preserves_original_and_removes_its_staging_file() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let text=row("One.","一。","zh-Hant").repeat(10);std::fs::write(&path,&text).unwrap();
    let mut database=db();
    let result=compact_with_replace(&mut database,&path,&hash_file(&path).unwrap(),0,|stage,target| {
      assert!(stage.is_file());assert_eq!(target,path);
      anyhow::bail!("injected replacement failure")
    });
    assert!(result.is_err());assert_eq!(std::fs::read_to_string(&path).unwrap(),text);
    assert_eq!(std::fs::read_dir(d.path()).unwrap().count(),1);
    assert!(compact(&mut database,&path,&hash_file(&path).unwrap(),0).unwrap().is_some(),"failure must leave maintenance reusable");
  }

  #[test]
  fn stale_source_digest_never_replaces_newer_content() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let old=row("One.","一。","zh-Hant").repeat(10);std::fs::write(&path,&old).unwrap();
    let hash=hash_file(&path).unwrap();let current=old+&row("Two.","二。","zh-Hant");
    std::fs::write(&path,&current).unwrap();
    assert!(compact_with_replace(&mut db(),&path,&hash,0,|_,_|panic!("source changed")).is_err());
    assert_eq!(std::fs::read_to_string(&path).unwrap(),current);
    assert_eq!(std::fs::read_dir(d.path()).unwrap().count(),1);
  }

  #[test]
  fn startup_cleanup_removes_only_abandoned_uuid_stages() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("translations.jsonl");
    let stale=path.with_extension(format!("compact-{}.tmp",uuid::Uuid::new_v4()));
    let unrelated=d.path().join("translations.compact-my-notes.tmp");
    let other=d.path().join(format!("other.compact-{}.tmp",uuid::Uuid::new_v4()));
    for p in [&path,&stale,&unrelated,&other] {std::fs::write(p,b"retained unless an abandoned stage").unwrap();}
    cleanup_staging(&path).unwrap();
    assert!(!stale.exists());
    for p in [&path,&unrelated,&other] {assert_eq!(std::fs::read(p).unwrap(),b"retained unless an abandoned stage");}
  }
}
