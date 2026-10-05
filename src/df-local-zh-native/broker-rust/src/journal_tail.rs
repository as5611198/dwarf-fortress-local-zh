//! Bounded JSONL framing across interrupted writes and atomic file replacement.
use anyhow::Result;
use serde_json::Value;
use std::{fs::File, io::{Read,Seek,SeekFrom}, path::Path, time::SystemTime};

const READ_BUDGET:u64=64*1024;
// Runtime paragraphs allow 64 links, each with up to 2,000 source bytes, in
// addition to 8,000 prose bytes. Account for JSON escaping and framing too.
const MAX_RECORD:usize=1024*1024;
// Responses contain both the original link array and translated link payloads.
const MAX_HISTORY_RECORD:usize=8*1024*1024;

#[derive(Default)]
pub struct Tail {
  offset:u64,
  frame:Frame,
  modified:Option<SystemTime>,
  identity:Option<(u64,u64)>,
}

impl Tail {
  pub fn take_rejected(&mut self)->u64 {std::mem::take(&mut self.frame.rejected)}

  pub fn read(&mut self,path:&Path)->Result<Vec<Value>> {
    let mut file=match File::open(path) {
      Ok(file)=>file,
      Err(error) if error.kind()==std::io::ErrorKind::NotFound=>{
        *self=Self::default();return Ok(Vec::new());
      },
      Err(error)=>return Err(error.into()),
    };
    let identity=file_identity(&file)?;
    let meta=file.metadata()?;
    let reset=self.identity!=Some(identity) || meta.len()<self.offset
      || (meta.len()==self.offset && self.modified.is_some() && meta.modified().ok()!=self.modified);
    let start=if reset {0} else {self.offset};
    file.seek(SeekFrom::Start(start))?;
    let mut data=Vec::new();
    (&mut file).take(READ_BUDGET).read_to_end(&mut data)?;
    let modified=file.metadata()?.modified().ok();
    // Failed reads leave the old state intact so a retry cannot skip bytes.
    if reset {*self=Self::default();}
    self.offset=start+data.len() as u64;self.identity=Some(identity);self.modified=modified;
    Ok(self.frame.feed(&data))
  }
}

struct Frame {
  partial:Vec<u8>,
  discarding:bool,
  rejected:u64,
  max_record:usize,
}
impl Default for Frame {fn default()->Self {Self::new(MAX_RECORD)}}
impl Frame {
  fn new(max_record:usize)->Self {Self{partial:Vec::new(),discarding:false,rejected:0,max_record}}
  fn feed(&mut self,data:&[u8])->Vec<Value> {
    let mut rows=Vec::new();
    for piece in data.split_inclusive(|b|*b==b'\n') {
      let ended=piece.last()==Some(&b'\n');
      let bytes=if ended {&piece[..piece.len()-1]} else {piece};
      if self.discarding {
        if ended {self.discarding=false;}
        continue;
      }
      if self.partial.len()+bytes.len()>self.max_record {
        self.partial.clear();self.discarding=!ended;
        self.rejected=self.rejected.saturating_add(1);
        continue;
      }
      self.partial.extend_from_slice(bytes);
      if ended {
        if self.partial.iter().any(|b|!b.is_ascii_whitespace()) {
          match serde_json::from_slice(&self.partial) {
            Ok(row)=>rows.push(row),
            Err(_)=>self.rejected=self.rejected.saturating_add(1),
          }
        }
        self.partial.clear();
      }
    }
    rows
  }
}

/// Replay only complete rows present when the file is opened. A single handle
/// pins the file identity; appends cannot extend startup indefinitely. Yield
/// after each bounded read so other async services remain schedulable.
#[cfg(test)]
pub(crate) async fn replay_snapshot(path:&Path,visit:impl FnMut(Value))->Result<u64> {
  replay_snapshot_progress(path,visit,|_|{}).await
}

pub(crate) async fn replay_snapshot_progress(path:&Path,mut visit:impl FnMut(Value),mut progress:impl FnMut(u64))->Result<u64> {
  let file=match File::open(path) {
    Ok(file)=>file,
    Err(error) if error.kind()==std::io::ErrorKind::NotFound=>return Ok(0),
    Err(error)=>return Err(error.into()),
  };
  let length=file.metadata()?.len();
  let mut reader=file.take(length);
  let mut frame=Frame::new(MAX_HISTORY_RECORD);
  let mut buffer=vec![0;READ_BUDGET as usize];
  while reader.limit()>0 {
    let count=reader.read(&mut buffer)?;
    anyhow::ensure!(count>0,"journal truncated during startup replay");
    for row in frame.feed(&buffer[..count]) {visit(row);}
    progress(count as u64);
    tokio::task::yield_now().await;
  }
  if !frame.discarding && frame.partial.iter().any(|b|!b.is_ascii_whitespace()) {
    frame.rejected=frame.rejected.saturating_add(1);
  }
  Ok(frame.rejected)
}

#[cfg(windows)]
fn file_identity(file:&File)->std::io::Result<(u64,u64)> {
  use std::os::windows::io::AsRawHandle;
  use windows_sys::Win32::Storage::FileSystem::{BY_HANDLE_FILE_INFORMATION,GetFileInformationByHandle};
  let mut info=BY_HANDLE_FILE_INFORMATION::default();
  // The borrowed File owns a valid handle throughout the call; Windows writes
  // exactly this initialized structure and does not retain its pointer.
  if unsafe {GetFileInformationByHandle(file.as_raw_handle() as _,&mut info)}==0 {
    return Err(std::io::Error::last_os_error());
  }
  Ok((u64::from(info.dwVolumeSerialNumber),(u64::from(info.nFileIndexHigh)<<32)|u64::from(info.nFileIndexLow)))
}

#[cfg(unix)]
fn file_identity(file:&File)->std::io::Result<(u64,u64)> {
  use std::os::unix::fs::MetadataExt;
  let meta=file.metadata()?;Ok((meta.dev(),meta.ino()))
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;
  use std::io::Write;

  #[tokio::test]
  async fn snapshot_isolates_bad_rows_and_keeps_large_complete_records() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
    let mut file=File::create(&path).unwrap();
    file.write_all(b"\xff\xfe\n").unwrap();
    for _ in 0..(MAX_HISTORY_RECORD/65536+1) {file.write_all(&[b'x';65536]).unwrap();}
    file.write_all(b"{\"fake\":true}\n").unwrap();
    let large=json!({"text":"𠮷".repeat(300000)});
    writeln!(file,"{large}").unwrap();
    file.write_all(b"{\"real\":true}\n{\"uncommitted\":true}").unwrap();drop(file);
    let mut rows=Vec::new();
    let rejected=replay_snapshot(&path,|row|rows.push(row)).await.unwrap();
    assert_eq!(rows,vec![large,json!({"real":true})]);
    assert_eq!(rejected,3,"Bad UTF-8, a single overlong physical line and uncommitted EOF must each count once");
  }

  #[tokio::test]
  async fn snapshot_end_is_fixed_before_concurrent_append() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
    std::fs::write(&path,b"{\"id\":1}\n").unwrap();let mut rows=Vec::new();
    assert_eq!(replay_snapshot(&path,|row| {
      rows.push(row);
      std::fs::OpenOptions::new().append(true).open(&path).unwrap().write_all(b"{\"id\":2}\n").unwrap();
    }).await.unwrap(),0);
    assert_eq!(rows,vec![json!({"id":1})]);
    rows.clear();
    replay_snapshot(&path,|row|rows.push(row)).await.unwrap();
    assert_eq!(rows,vec![json!({"id":1}),json!({"id":2})]);
  }

  #[tokio::test]
  async fn snapshot_replacement_never_mixes_file_generations() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
    let old_tail=json!({"text":"A".repeat(100000)});
    let original=format!("{{\"id\":1}}\n{old_tail}\n");
    std::fs::write(&path,&original).unwrap();let mut rows=Vec::new();
    let replacement=d.path().join("new");std::fs::write(&replacement,b"{\"new\":true}\n").unwrap();
    replay_snapshot(&path,|row| {
      if rows.is_empty() {
        if let Err(error)=std::fs::rename(&replacement,&path) {
          // Windows may refuse replacement while a reader owns the old file.
          // This is safe deferral, not permission to read a mixed snapshot.
          assert!(cfg!(windows) && matches!(error.raw_os_error(),Some(5|32)),"unexpected replacement error: {error}");
          assert_eq!(std::fs::read(&path).unwrap(),original.as_bytes());
        }
      }
      rows.push(row);
    }).await.unwrap();
    assert_eq!(rows,vec![json!({"id":1}),old_tail]);
    if replacement.exists() {std::fs::rename(&replacement,&path).unwrap();}
    rows.clear();replay_snapshot(&path,|row|rows.push(row)).await.unwrap();
    assert_eq!(rows,vec![json!({"new":true})]);
  }

  #[tokio::test]
  async fn snapshot_reports_open_and_mid_replay_truncation_errors() {
    let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
    assert_eq!(replay_snapshot(&path,|_|panic!("missing file")).await.unwrap(),0);
    assert!(replay_snapshot(d.path(),|_|panic!("directory")).await.is_err());
    std::fs::write(&path,format!("{{\"id\":1}}\n{}\n"," ".repeat(100000))).unwrap();
    let error=replay_snapshot(&path,|_| {
      std::fs::OpenOptions::new().write(true).open(&path).unwrap().set_len(0).unwrap();
    }).await.unwrap_err();
    assert!(error.to_string().contains("truncated"));
  }

  #[test]
  fn snapshot_yields_before_reading_the_next_chunk() {
    use std::{future::Future,task::{Context,Poll,Waker}};
    let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
    std::fs::write(&path,"{\"id\":1}\n".repeat(10000)).unwrap();
    let seen=std::cell::Cell::new(0usize);
    let mut future=Box::pin(replay_snapshot(&path,|_|seen.set(seen.get()+1)));
    assert!(matches!(future.as_mut().poll(&mut Context::from_waker(Waker::noop())),Poll::Pending));
    assert!(seen.get()>0 && seen.get()<10000,"A single poll cannot replay the entire large journal");
  }
}
