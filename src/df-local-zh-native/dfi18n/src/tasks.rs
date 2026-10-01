use std::sync::OnceLock;

use tokio::runtime::{Builder, Runtime};
use tokio::task::JoinHandle;
use std::sync::atomic::{AtomicUsize, Ordering};

// The Tokio runtime for running asynchronous tasks
static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static WORKERS: AtomicUsize = AtomicUsize::new(2);
static TRANSLATIONS: OnceLock<TranslationLimiter> = OnceLock::new();

struct TranslationLimiter {
  limit: AtomicUsize,
  active: AtomicUsize,
  changed: tokio::sync::Notify,
}
impl TranslationLimiter {
  fn new(limit:usize)->Self {
    Self {limit:AtomicUsize::new(limit),active:AtomicUsize::new(0),changed:tokio::sync::Notify::new()}
  }
  fn resize(&self,limit:usize) {
    self.limit.store(limit,Ordering::SeqCst);
    self.changed.notify_waiters();
  }
  async fn acquire(&self)->TranslationPermit<'_> {
    loop {
      let notified=self.changed.notified();
      tokio::pin!(notified);
      notified.as_mut().enable();
      if self.active.fetch_update(Ordering::SeqCst,Ordering::SeqCst,|active|
        (active<self.limit.load(Ordering::SeqCst)).then_some(active+1)).is_ok() {
        return TranslationPermit {limiter:self};
      }
      notified.await;
    }
  }
}
pub(crate) struct TranslationPermit<'a> {limiter:&'a TranslationLimiter}
impl Drop for TranslationPermit<'_> {
  fn drop(&mut self) {
    self.limiter.active.fetch_sub(1,Ordering::SeqCst);
    self.limiter.changed.notify_waiters();
  }
}
fn translations()->&'static TranslationLimiter {TRANSLATIONS.get_or_init(||TranslationLimiter::new(2))}

pub(crate) static SUBMISSIONS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

// Setup the Tokio runtime
pub fn setup() {
  RUNTIME.get_or_init(|| Builder::new_multi_thread().worker_threads(WORKERS.load(Ordering::Relaxed)).enable_all().build().unwrap());
}

// Gets the Tokio runtime
pub fn get() -> &'static Runtime {
  RUNTIME.get_or_init(|| Builder::new_multi_thread().worker_threads(WORKERS.load(Ordering::Relaxed)).enable_all().build().unwrap())
}

pub(crate) async fn translation_permit() -> TranslationPermit<'static> {
  translations().acquire().await
}

#[unsafe(no_mangle)]
extern "C" fn translation_concurrency_get(state:*mut std::ffi::c_void)->i32 {
  lua53_sys::push_integer(state,translations().limit.load(Ordering::SeqCst) as isize);1
}
#[unsafe(no_mangle)]
extern "C" fn translation_concurrency_set(state:*mut std::ffi::c_void)->i32 {
  let value=lua53_sys::check_integer(state,1);
  if (1..=32).contains(&value) {translations().resize(value as usize);}
  translation_concurrency_get(state)
}

#[unsafe(no_mangle)]
extern "C" fn runtime_worker_threads_get(state: *mut std::ffi::c_void) -> i32 {
  lua53_sys::push_integer(state, WORKERS.load(Ordering::Relaxed) as isize); 1
}
#[unsafe(no_mangle)]
extern "C" fn runtime_worker_threads_set(state: *mut std::ffi::c_void) -> i32 {
  let value = lua53_sys::check_integer(state, 1);
  if RUNTIME.get().is_none() && (1..=4).contains(&value) { WORKERS.store(value as usize, Ordering::Relaxed); }
  runtime_worker_threads_get(state)
}

// Spawn an asynchronous task on the Tokio runtime
pub fn spawn<F>(future: F) -> JoinHandle<F::Output>
where
  F: std::future::Future<Output = ()> + Send + 'static,
{
  SUBMISSIONS.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
  get().spawn(future)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn request_limit_can_grow_and_shrink_without_resetting_cpu_runtime() {
    get().block_on(async {
      let limiter=TranslationLimiter::new(2);
      let first=limiter.acquire().await;
      let second=limiter.acquire().await;
      assert!(tokio::time::timeout(std::time::Duration::from_millis(10),limiter.acquire()).await.is_err());
      limiter.resize(4);
      let third=limiter.acquire().await;
      let fourth=limiter.acquire().await;
      assert_eq!(limiter.active.load(Ordering::Relaxed),4);
      limiter.resize(1);
      drop(first);drop(second);drop(third);
      assert!(tokio::time::timeout(std::time::Duration::from_millis(10),limiter.acquire()).await.is_err());
      drop(fourth);
      let permit=tokio::time::timeout(std::time::Duration::from_millis(100),limiter.acquire()).await.unwrap();
      assert_eq!(limiter.active.load(Ordering::Relaxed),1);
      drop(permit);
      assert_eq!(limiter.active.load(Ordering::Relaxed),0);
    });
  }
}
