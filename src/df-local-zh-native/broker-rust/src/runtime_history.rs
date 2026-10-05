//! Recover startup history without treating an unavailable journal as empty.
use crate::{bounded::BoundedMap,common::{now,validate},journal_tail::replay_snapshot_progress,service::runtime_key};
use anyhow::{Context,Result};
use serde_json::{Value,json};
use std::{path::Path,sync::{Arc,atomic::{AtomicU64,Ordering}},time::{Duration,Instant}};
use tokio::task::JoinHandle;

pub(crate) struct Snapshot {
  pub completed:BoundedMap<String,()>,
  pub failures:BoundedMap<String,Value>,
}

async fn load(path:&Path,progress:&AtomicU64)->Result<Snapshot> {
  let mut completed=BoundedMap::new(32768);
  let mut failures=BoundedMap::new(4096);
  let rejected=replay_snapshot_progress(&path.join("runtime-responses.jsonl"),|mut row| {
    if row["kind"]=="legends-paragraph" {row["links"]=row["requestLinks"].clone();}
    let key=runtime_key(&row);
    if row["key"]==key && validate(row["text"].as_str().unwrap_or(""),row["translation"].as_str().unwrap_or("")).is_ok() {
      completed.insert(key,());
    }
  },|bytes|{progress.fetch_add(bytes,Ordering::Relaxed);}).await.context("runtime response journal")?;
  if rejected>0 {eprintln!("runtime response journal startup skipped {rejected} invalid, oversized or incomplete rows");}
  let rejected=replay_snapshot_progress(&path.join("runtime-failures.jsonl"),|row| {
    let key=runtime_key(&row);
    if row["key"]==key && row["attempts"].as_u64().is_some_and(|n|n<=31) && !completed.contains_key(&key) {
      failures.insert(key,row);
    }
  },|bytes|{progress.fetch_add(bytes,Ordering::Relaxed);}).await.context("runtime failure journal")?;
  if rejected>0 {eprintln!("runtime failure journal startup skipped {rejected} invalid, oversized or incomplete rows");}
  // Neither map is published if either history file could not be read fully.
  Ok(Snapshot{completed,failures})
}

fn retry_delay(attempts:u32)->Duration {
  Duration::from_secs((1u64<<attempts.saturating_sub(1).min(5)).min(30))
}

pub(crate) struct Recovery {
  task:Option<JoinHandle<Result<Snapshot>>>,
  progress:Arc<AtomicU64>,
  observed_progress:u64,
  progressed_at:Instant,
  retry_at:Instant,
  attempts:u32,
  error:Option<String>,
  cancelling:bool,
  ready:bool,
}
impl Recovery {
  pub fn new()->Self {
    Self{task:None,progress:Arc::new(AtomicU64::new(0)),observed_progress:0,
      progressed_at:Instant::now(),retry_at:Instant::now(),attempts:0,error:None,cancelling:false,ready:false}
  }
  pub fn ready(&self)->bool {self.ready}
  pub fn status(&self)->Value {
    json!({"state":if self.ready {"ready"} else if self.error.is_some() {"retrying"} else {"loading"},
      "attempts":self.attempts,"bytesRead":self.progress.load(Ordering::Relaxed),"error":self.error,
      "retryAt":if !self.ready && self.task.is_none() {Some(now()+self.retry_at.saturating_duration_since(Instant::now()).as_millis() as i64)} else {None}})
  }
  fn failed(&mut self,error:String) {
    let bounded=error.chars().take(512).collect::<String>();
    if self.error.as_ref()!=Some(&bounded) {eprintln!("runtime history recovery: {bounded}");}
    self.error=Some(bounded);self.retry_at=Instant::now()+retry_delay(self.attempts);
  }
  fn watch_progress(&mut self,at:Instant) {
    let bytes=self.progress.load(Ordering::Relaxed);
    if bytes!=self.observed_progress {
      self.observed_progress=bytes;self.progressed_at=at;
    } else if self.task.is_some() && !self.cancelling && at.saturating_duration_since(self.progressed_at)>=Duration::from_secs(30) {
      self.task.as_ref().unwrap().abort();self.cancelling=true;
      self.error=Some("runtime history read stalled; restarting".into());
      eprintln!("runtime history recovery: no read progress for 30 seconds; cancelling reader");
    }
  }
  pub async fn poll(&mut self,path:&Path)->Option<Snapshot> {
    if self.ready {return None;}
    if self.task.as_ref().is_some_and(|task|task.is_finished()) {
      let result=self.task.take().unwrap().await;
      self.cancelling=false;
      match result {
        Ok(Ok(snapshot))=>{
          self.ready=true;self.error=None;
          if self.attempts>1 {eprintln!("runtime history recovered after {} attempts",self.attempts);}
          return Some(snapshot);
        },
        Ok(Err(error))=>self.failed(format!("{error:#}")),
        Err(_)=>self.failed("runtime history reader stopped unexpectedly".into()),
      }
    }
    self.watch_progress(Instant::now());
    if self.task.is_none() && Instant::now()>=self.retry_at {
      self.attempts=self.attempts.saturating_add(1);
      self.progress.store(0,Ordering::Relaxed);self.observed_progress=0;self.progressed_at=Instant::now();
      let path=path.to_owned();let progress=self.progress.clone();
      self.task=Some(tokio::spawn(async move {load(&path,&progress).await}));
    }
    None
  }
}
impl Drop for Recovery {
  fn drop(&mut self) {if let Some(task)=self.task.take() {task.abort();}}
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn retry_delay_is_capped_without_overflow() {
    for (attempts,seconds) in [(0,1),(1,1),(2,2),(5,16),(6,30),(u32::MAX,30)] {
      assert_eq!(retry_delay(attempts),Duration::from_secs(seconds));
    }
  }
  #[tokio::test]
  async fn progress_extends_watchdog_but_stalls_cancel_the_owned_task() {
    let mut recovery=Recovery::new();
    let marker=Arc::new(());let weak=Arc::downgrade(&marker);
    recovery.task=Some(tokio::spawn(async move {let _held=marker;std::future::pending().await}));
    let began=Instant::now();recovery.progressed_at=began;
    recovery.progress.store(65536,Ordering::Relaxed);
    recovery.watch_progress(began+Duration::from_secs(60));
    assert!(!recovery.cancelling,"Continued progress must not hit a total-duration deadline");
    recovery.watch_progress(began+Duration::from_secs(91));
    assert!(recovery.cancelling);
    assert!(matches!(recovery.task.take().unwrap().await,Err(error) if error.is_cancelled()));
    assert!(weak.upgrade().is_none(),"Cancelled snapshot work must release owned resources");
  }
  #[tokio::test]
  async fn dropping_recovery_aborts_unfinished_work() {
    let mut recovery=Recovery::new();let marker=Arc::new(());let weak=Arc::downgrade(&marker);
    recovery.task=Some(tokio::spawn(async move {let _held=marker;std::future::pending().await}));
    drop(recovery);
    tokio::time::timeout(Duration::from_secs(1),async {
      while weak.upgrade().is_some() {tokio::task::yield_now().await;}
    }).await.unwrap();
  }
  #[tokio::test]
  async fn task_panic_backs_off_then_recovers_instead_of_staying_pending() {
    let d=tempfile::tempdir().unwrap();let mut recovery=Recovery::new();
    recovery.attempts=1;
    recovery.task=Some(tokio::spawn(async {panic!("fixture history task panic")}));
    while !recovery.task.as_ref().unwrap().is_finished() {tokio::task::yield_now().await;}
    assert!(recovery.poll(d.path()).await.is_none());
    assert_eq!(recovery.status()["state"],"retrying");
    assert!(recovery.task.is_none());
    assert!(recovery.retry_at>Instant::now(),"Task failures must not spin-retry");
    recovery.poll(d.path()).await;
    assert_eq!(recovery.attempts,1);
    recovery.retry_at=Instant::now();
    let snapshot=tokio::time::timeout(Duration::from_secs(1),async {
      loop {
        if let Some(snapshot)=recovery.poll(d.path()).await {break snapshot;}
        tokio::task::yield_now().await;
      }
    }).await.unwrap();
    assert!(snapshot.completed.is_empty() && snapshot.failures.is_empty());
    assert!(recovery.ready());assert_eq!(recovery.attempts,2);
    assert_eq!(recovery.status()["error"],Value::Null);
  }
}
