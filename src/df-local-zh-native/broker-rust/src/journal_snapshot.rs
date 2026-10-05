//! Staging only: source replacement requires the writer-pause coordinator.
#![allow(dead_code)] // Activated only after the generation/ack protocol is integrated.
use crate::{common::{hash,language,re,validate},service::runtime_key};
use anyhow::{Result,ensure};
use rusqlite::{Connection,params};
use serde_json::{Value,json};
use sha2::{Digest,Sha256};
use std::{fs::{File,Metadata},io::{BufRead,BufReader,BufWriter,Read,Seek,SeekFrom,Write},path::{Path,PathBuf},time::SystemTime};

const MAX_RECORD:usize=8*1024*1024;

#[derive(Clone,Copy)]
pub(crate) enum Kind { Requests,Responses,Failures,Display }
struct OwnedPath(PathBuf);
impl Drop for OwnedPath {
  fn drop(&mut self) {
    if let Err(error)=std::fs::remove_file(&self.0) {
      if error.kind()!=std::io::ErrorKind::NotFound {eprintln!("journal stage cleanup: {error}");}
    }
  }
}
#[derive(PartialEq)]
struct Stamp {len:u64,modified:Option<SystemTime>,created:Option<SystemTime>,hash:Vec<u8>}
impl Stamp {
  fn new(metadata:Metadata,hash:Vec<u8>)->Self {
    Self{len:metadata.len(),modified:metadata.modified().ok(),created:metadata.created().ok(),hash}
  }
  fn read(path:&Path)->Result<Self> {
    let mut file=File::open(path)?;let metadata=file.metadata()?;
    let mut digest=Sha256::new();let mut buf=[0;65536];let mut total=0;
    loop {let count=file.read(&mut buf)?;if count==0 {break;}digest.update(&buf[..count]);total+=count as u64;}
    let after=file.metadata()?;
    ensure!(total==metadata.len() && metadata.len()==after.len() && metadata.modified().ok()==after.modified().ok(),"journal changed while hashing");
    Ok(Self::new(metadata,digest.finalize().to_vec()))
  }
}
pub(crate) struct Staged {file:OwnedPath,source:PathBuf,source_stamp:Stamp,stage_stamp:Stamp}
impl Staged {
  pub fn path(&self)->&Path {&self.file.0}
  pub fn source_len(&self)->u64 {self.source_stamp.len}
  pub fn staged_len(&self)->u64 {self.stage_stamp.len}
  pub fn verify(&self)->Result<()> {
    ensure!(Stamp::read(&self.source)?==self.source_stamp,"journal source changed after staging");
    ensure!(Stamp::read(self.path())?==self.stage_stamp,"journal stage changed after staging");
    Ok(())
  }
}

// A fresh file-backed TEMP index is intentionally independent of every hot or
// derived translation cache. Never export a bounded cache as complete history.
pub(crate) fn stage(source:&Path,kind:Kind,minimum_saved:u64)->Result<Option<Staged>> {
  let file=File::open(source)?;let metadata=file.metadata()?;let original_len=metadata.len();
  let mut reader=BufReader::new(file.take(original_len));
  let mut db=Connection::open_in_memory()?;
  db.execute_batch("PRAGMA temp_store=FILE; PRAGMA temp.cache_size=-2048;
    CREATE TEMP TABLE spans (key TEXT PRIMARY KEY, offset INTEGER NOT NULL UNIQUE, bytes INTEGER NOT NULL);")?;
  let mut digest=Sha256::new();let mut offset=0u64;let mut length=0u64;
  let mut line=Vec::new();let mut oversized=false;
  {
    let tx=db.transaction()?;
    {
      let mut insert=tx.prepare("INSERT INTO spans(key,offset,bytes) VALUES(?1,?2,?3)
        ON CONFLICT(key) DO UPDATE SET offset=excluded.offset,bytes=excluded.bytes")?;
      loop {
        let buffer=reader.fill_buf()?;
        if buffer.is_empty() {
          if length>0 {span(&mut insert,kind,&[],offset,length)?;offset+=length;}
          break;
        }
        let end=buffer.iter().position(|b|*b==b'\n').map(|n|n+1);
        let take=end.unwrap_or(buffer.len());digest.update(&buffer[..take]);length+=take as u64;
        if !oversized && line.len()+take<=MAX_RECORD {line.extend_from_slice(&buffer[..take]);}
        else {oversized=true;line.clear();}
        reader.consume(take);
        if end.is_some() {
          span(&mut insert,kind,&line,offset,length)?;
          offset+=length;length=0;line.clear();oversized=false;
        }
      }
    }
    tx.commit()?;
  }
  ensure!(offset==original_len,"journal truncated during snapshot scan");
  let wanted:i64=db.query_row("SELECT COALESCE(SUM(bytes),0) FROM spans",[],|r|r.get(0))?;
  let wanted=u64::try_from(wanted)?;ensure!(wanted<=original_len,"invalid staged journal size");
  let saved=original_len-wanted;
  if saved==0 || saved<minimum_saved || saved<original_len/4 {return Ok(None);}
  let path=source.with_extension(format!("stage-{}.tmp",uuid::Uuid::new_v4()));
  let out=File::options().write(true).create_new(true).open(&path)?;
  let owned=OwnedPath(path); // Cleanup ownership begins only after create_new.
  let mut out=BufWriter::new(out);let mut original=reader.into_inner().into_inner();
  {
    let mut query=db.prepare("SELECT offset,bytes FROM spans ORDER BY offset")?;let mut rows=query.query([])?;
    while let Some(row)=rows.next()? {
      let start:u64=u64::try_from(row.get::<_,i64>(0)?)?;
      let bytes:u64=u64::try_from(row.get::<_,i64>(1)?)?;
      original.seek(SeekFrom::Start(start))?;
      ensure!(std::io::copy(&mut (&mut original).take(bytes),&mut out)?==bytes,"journal truncated while staging");
    }
  }
  out.flush()?;out.get_ref().sync_all()?;drop(out);drop(original);
  let source_stamp=Stamp::new(metadata,digest.finalize().to_vec());
  let stage_stamp=Stamp::read(&owned.0)?;
  ensure!(stage_stamp.len==wanted,"unexpected staged journal size");
  let staged=Staged{file:owned,source:source.to_owned(),source_stamp,stage_stamp};
  staged.verify()?;
  Ok(Some(staged))
}

fn span(insert:&mut rusqlite::Statement<'_>,kind:Kind,line:&[u8],offset:u64,length:u64)->Result<()> {
  let identity=serde_json::from_slice::<Value>(line).ok().as_ref().and_then(|row|retention_key(kind,row));
  let key=identity.map_or_else(||format!("opaque:{offset}"),|key|format!("valid:{key}"));
  insert.execute(params![key,i64::try_from(offset)?,i64::try_from(length)?])?;Ok(())
}

fn known_fields(row:&Value,fields:&[&str])->bool {
  row.as_object().is_some_and(|m|m.keys().all(|key|fields.contains(&key.as_str())))
}
fn lang(row:&Value)->Option<&str> {
  match row.get("language") {None=>Some("zh-Hant"),Some(value)=>value.as_str().filter(|s|language(s))}
}
fn source(row:&Value)->bool {
  row["world"].as_str().is_some_and(|s|!s.is_empty()) && lang(row).is_some()
    && row["text"].as_str().is_some_and(|s|!s.is_empty() && s.len()<=8000)
}
fn request_shape(row:&Value)->bool {
  if !source(row) || row.get("visibilityId").is_some_and(|v|!v.is_string())
    || row.get("priority").is_some_and(|v|!matches!(v.as_str(),Some("foreground"|"background"|"recent"))) {return false;}
  match row.get("kind").and_then(Value::as_str) {
    None if row.get("kind").is_none()=>{
      row.get("links").is_none() && row.get("requestLinks").is_none()
        && row.get("figureId").is_none_or(|v|v.as_u64().is_some() && row["namePolicy"]=="native-v2")
    },
    Some("legends-name")=>row["namePolicy"]=="native-v2" && row.get("figureId").is_none()
      && row["entityId"].as_u64().is_some() && row["entityKind"].as_str().is_some_and(|s|re(r"^[a-z_]+$").is_match(s)),
    Some("legends-paragraph")=>{
      if row["namePolicy"]!="native-v2" {return false;}
      let Some(links)=row["links"].as_array().filter(|v|v.len()<=64) else {return false;};
      if !links.iter().all(|link|known_fields(link,&["type","id","text"])
        && link["type"].as_u64().is_some_and(|n|n<12) && link["id"].as_u64().is_some()
        && link["text"].as_str().is_some_and(|s|!s.is_empty() && s.len()<=2000)) {return false;}
      let mut seen=std::collections::HashSet::new();
      for token in re(r"\{\{DFL(\d+)\}\}").captures_iter(row["text"].as_str().unwrap()) {
        let Ok(index)=token[1].parse::<usize>() else {return false;};
        if index>=links.len() || !seen.insert(index) {return false;}
      }
      seen.len()==links.len()
    },
    _=>false,
  }
}

fn retention_key(kind:Kind,row:&Value)->Option<String> {
  const REQUEST:&[&str]=&["world","language","text","kind","namePolicy","priority","figureId","entityKind","entityId","links","subjectId","visibilityId"];
  const RESPONSE:&[&str]=&["world","language","text","kind","namePolicy","figureId","entityKind","entityId","links","subjectId","requestLinks","key","translation"];
  const FAILURE_EXTRA:&[&str]=&["key","attempts","retryAt","reason","terminal","retryGeneration"];
  match kind {
    Kind::Requests if known_fields(row,REQUEST) && request_shape(row)=>
      Some(hash(serde_json::to_vec(&json!([runtime_key(row),row["visibilityId"],row["priority"]])).ok()?)),
    Kind::Responses if known_fields(row,RESPONSE)=>{
      let mut request=row.clone();
      if row["kind"]=="legends-paragraph" {
        request["links"]=row["requestLinks"].clone();
        request.as_object_mut()?.remove("requestLinks");
        let links=row["links"].as_array()?;let inputs=request["links"].as_array()?;
        if links.len()!=inputs.len() || !links.iter().zip(inputs).all(|(output,input)|
          known_fields(output,&["translation"]) && validate(input["text"].as_str().unwrap_or(""),output["translation"].as_str().unwrap_or("")).is_ok()) {return None;}
      }
      if !request_shape(&request) || row["key"]!=runtime_key(&request)
        || validate(row["text"].as_str()?,row["translation"].as_str()?).is_err() {return None;}
      row["key"].as_str().map(str::to_owned)
    },
    Kind::Failures if row.as_object()?.keys().all(|k|REQUEST.contains(&k.as_str()) || FAILURE_EXTRA.contains(&k.as_str())) && request_shape(row)=>{
      if row["key"]!=runtime_key(row) || !row["attempts"].as_u64().is_some_and(|n|(1..=31).contains(&n))
        || row["retryAt"].as_i64().is_none() || !row["terminal"].is_boolean() || !row["reason"].is_string()
        || !row["retryGeneration"].as_str().is_some_and(|s|re(r"^[0-9a-f]{64}$").is_match(s)) {return None;}
      Some(hash(serde_json::to_vec(&json!([row["key"],row["retryGeneration"],row["visibilityId"]])).ok()?))
    },
    Kind::Display=>display_key(row),
    _=>None,
  }
}

fn display_key(row:&Value)->Option<String> {
  if !known_fields(row,&["version","world","language","kind","text","translation","color","key"]) || row["version"]!=1 {return None;}
  let language=lang(row)?;let kind=row["kind"].as_str()?;let translated=row["translation"].as_str()?;
  if translated.is_empty() || translated.len()>24000 {return None;}
  let clean_markup=||re(r"\[C:[0-7]:[0-7]:[01]\]|\[[BPR]\]").replace_all(translated,"").into_owned();
  let forbidden=|s:&str|s.chars().any(|c|c.is_ascii_alphabetic() || "{}[]".contains(c));
  let identity=if kind=="fragment" {
    if row["world"]!=false && !row["world"].is_string() {return None;}
    if forbidden(&clean_markup()) || !row["color"].as_u64().is_some_and(|n|n<=127)
      || row.get("key").is_some_and(|v|!v.as_str().is_some_and(|s|re(r"^L[0-9A-Za-z]{6}_*$").is_match(s))) {return None;}
    json!([row["color"],translated])
  } else {
    if !source(row) {return None;}
    let text=row["text"].as_str()?;
    if kind=="native" {
      let plain=clean_markup();
      if forbidden(&plain) || plain.is_ascii() {return None;}
      let tokens=|s:&str|{let mut values=re(r"\[[^\[\]]+\]").find_iter(s).map(|m|m.as_str().to_owned()).collect::<Vec<_>>();values.sort();values};
      if tokens(text)!=tokens(translated) {return None;}
    } else if kind=="source" || kind=="name" {
      let clean=translated.replace("{DWARF_NAME}","");
      if forbidden(&clean) || (clean!=translated && (kind!="source" || !text.starts_with("{DWARF_NAME} likes ") || translated.matches("{DWARF_NAME}").count()!=1)) {return None;}
    } else {return None;}
    json!(text)
  };
  Some(hash(serde_json::to_vec(&json!([row["world"],language,kind,identity])).ok()?))
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;
  use std::io::Write;

  fn request(text:&str, priority:&str, visibility:Option<&str>)->Value {
    let mut row=json!({"world":"test","language":"zh-Hant","text":text,"priority":priority});
    if let Some(visibility)=visibility {row["visibilityId"]=json!(visibility);}
    row
  }

  fn response(row:&Value, translation:&str)->Value {
    let mut value=row.clone();
    value.as_object_mut().unwrap().remove("priority");
    value.as_object_mut().unwrap().remove("visibilityId");
    value["translation"]=json!(translation);
    value["key"]=json!(runtime_key(row));
    value
  }

  fn write_rows(path:&Path, rows:&[Value]) {
    let mut file=File::create(path).unwrap();
    for row in rows {writeln!(file,"{}",serde_json::to_string(row).unwrap()).unwrap();}
    file.sync_all().unwrap();
  }
  #[test]
  fn staging_reclaims_duplicate_requests_without_modifying_the_source() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("runtime-requests.jsonl");
    let a=json!({"world":"test","language":"zh-Hant","text":"Health","priority":"foreground"}).to_string()+"\n";
    let b=json!({"world":"test","language":"zh-Hant","text":"Wounds","priority":"foreground"}).to_string()+"\n";
    let original=a.repeat(20)+&b+&a;
    std::fs::write(&source,&original).unwrap();
    let staged=stage(&source,Kind::Requests,0).unwrap().expect("Repeated requests should yield a compacted stage");
    assert_eq!(std::fs::read_to_string(staged.path()).unwrap(),b+&a);
    assert_eq!(std::fs::read_to_string(&source).unwrap(),original,"Staging must never replace an active writer's source");
  }

  #[test]
  fn request_identity_keeps_view_and_priority_variants() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("runtime-requests.jsonl");
    let foreground=request("Health","foreground",Some("sheet"));
    let background=request("Health","background",Some("sheet"));
    let other_view=request("Health","foreground",Some("unit"));
    let unique=request("Wounds","foreground",None);
    let mut rows=Vec::new();
    for _ in 0..20 {rows.push(foreground.clone());}
    rows.extend([background.clone(),other_view.clone(),unique.clone(),foreground.clone()]);
    write_rows(&source,&rows);
    let staged=stage(&source,Kind::Requests,0).unwrap().unwrap();
    let data=std::fs::read_to_string(staged.path()).unwrap();
    assert!(data.contains(&serde_json::to_string(&background).unwrap()));
    assert!(data.contains(&serde_json::to_string(&other_view).unwrap()));
    assert!(data.contains(&serde_json::to_string(&unique).unwrap()));
    assert_eq!(data.matches("Health").count(),3,"foreground, background, and the other viewport are distinct identities");
  }

  #[test]
  fn response_keeps_latest_valid_and_preserves_newer_invalid_bytes() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("runtime-responses.jsonl");
    let req=request("Health","foreground",None);
    let old=response(&req,"健康");
    let newest=response(&req,"生命值");
    let mut invalid=response(&req,"still English");
    invalid["translation"]=json!("broken");
    let mut rows=Vec::new();for _ in 0..20 {rows.push(old.clone());}
    rows.extend([newest.clone(),invalid.clone()]);write_rows(&source,&rows);
    let staged=stage(&source,Kind::Responses,0).unwrap().unwrap();
    let data=std::fs::read_to_string(staged.path()).unwrap();
    assert!(data.contains("生命值"),"newest valid response should replace the older value");
    assert!(data.contains("broken"),"newer invalid response must remain opaque instead of deleting history");
    assert!(!data.contains("\"translation\":\"健康\""));
  }

  #[test]
  fn failures_are_separated_by_retry_generation_and_visibility() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("runtime-failures.jsonl");
    let mut first=request("Health","foreground",Some("sheet"));
    first["key"]=json!(runtime_key(&first));first["attempts"]=json!(1);first["retryAt"]=json!(100_i64);
    first["reason"]=json!("timeout");first["terminal"]=json!(false);first["retryGeneration"]=json!("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    let mut second=first.clone();second["retryGeneration"]=json!("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
    let mut other=first.clone();other["visibilityId"]=json!("unit");
    let mut rows=Vec::new();for _ in 0..20 {rows.push(first.clone());}
    rows.extend([second.clone(),other.clone()]);write_rows(&source,&rows);
    let staged=stage(&source,Kind::Failures,0).unwrap().unwrap();
    let data=std::fs::read_to_string(staged.path()).unwrap();
    assert!(data.contains(&serde_json::to_string(&second).unwrap()));
    assert!(data.contains(&serde_json::to_string(&other).unwrap()));
    assert_eq!(data.matches("retryGeneration").count(),3,"generation and viewport variants must all survive");
  }

  #[test]
  fn display_keeps_world_language_kind_and_fragment_color_identities() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("unit-display-cache.jsonl");
    let native=json!({"version":1,"world":"test","language":"zh-Hant","kind":"native","text":"Health","translation":"生命值"});
    let source_row=json!({"version":1,"world":"test","language":"zh-Hant","kind":"source","text":"Hello","translation":"你好"});
    let other_world=json!({"version":1,"world":"other","language":"zh-Hant","kind":"source","text":"Hello","translation":"你好"});
    let fragment=json!({"version":1,"world":false,"language":"zh-Hant","kind":"fragment","translation":"紅色","color":3,"key":"Labc123"});
    let mut rows=Vec::new();for _ in 0..20 {rows.push(native.clone());}
    rows.extend([source_row.clone(),other_world.clone(),fragment.clone(),json!({"version":1,"world":"test","language":"zh-Hant","kind":"source","text":"Hello","translation":"bad","future":true})]);
    write_rows(&source,&rows);
    let staged=stage(&source,Kind::Display,0).unwrap().unwrap();
    let data=std::fs::read_to_string(staged.path()).unwrap();
    assert!(data.contains("生命值")&&data.contains("你好")&&data.contains("紅色"));
    assert!(data.contains("\"future\":true"),"unknown schema rows must remain opaque");
    assert!(data.contains("\"world\":\"other\""),"world is part of display identity");
  }

  #[test]
  fn malformed_and_oversized_records_survive_byte_for_byte() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("mixed.jsonl");
    let long_text="Health ".to_owned()+&"x".repeat(3900);
    let valid=request(&long_text,"foreground",None).to_string()+"\n";
    let invalid="{not-json}\n";
    let oversized="x".repeat(MAX_RECORD+1)+"\n";
    let unterminated="{\"future\":true}";
    // Enough duplicate history is included to exceed the 25% reclaim floor
    // even though the opaque oversized row is intentionally retained.
    let mut bytes=valid.repeat(3000).into_bytes();bytes.extend_from_slice(invalid.as_bytes());bytes.extend_from_slice(oversized.as_bytes());bytes.extend_from_slice(unterminated.as_bytes());
    std::fs::write(&source,&bytes).unwrap();
    let staged=stage(&source,Kind::Requests,0).unwrap().unwrap();
    let compact=std::fs::read(staged.path()).unwrap();
    assert!(compact.windows(invalid.len()).any(|w|w==invalid.as_bytes()));
    assert!(compact.windows(unterminated.len()).any(|w|w==unterminated.as_bytes()));
    assert!(compact.windows(oversized.len()).any(|w|w==oversized.as_bytes()));
  }

  #[test]
  fn insufficient_reclaim_does_not_create_a_stage() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("small.jsonl");
    let rows=[request("Health","foreground",None),request("Wounds","foreground",None)];
    write_rows(&source,&rows);
    assert!(stage(&source,Kind::Requests,0).unwrap().is_none());
  }

  #[test]
  fn verify_detects_source_or_stage_tampering_and_drop_cleans_only_owned_file() {
    let d=tempfile::tempdir().unwrap();let source=d.path().join("runtime-requests.jsonl");
    let row=request("Health","foreground",None).to_string()+"\n";
    std::fs::write(&source,row.repeat(20)).unwrap();
    let staged=stage(&source,Kind::Requests,0).unwrap().unwrap();let staged_path=staged.path().to_owned();
    std::fs::OpenOptions::new().append(true).open(&source).unwrap().write_all(b"x").unwrap();
    assert!(staged.verify().is_err());
    assert!(staged_path.exists());
    drop(staged);assert!(!staged_path.exists());assert!(source.exists());
  }
}
