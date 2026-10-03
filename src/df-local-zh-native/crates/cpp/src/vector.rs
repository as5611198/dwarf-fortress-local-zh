use std::{ffi, marker::PhantomData, ops::Deref, sync::Arc};

#[cfg(test)]
mod ownership_tests {
  use super::*;
  #[test]
  fn borrowed_wrappers_release_their_allocation_without_owning_foreign_memory() {
    for _ in 0..1000 {
      let borrowed=CppVector::<u8>::from_raw(std::ptr::null_mut());
      let weak=Arc::downgrade(&borrowed.inner);
      drop(borrowed);
      assert!(weak.upgrade().is_none(),"Borrowed wrapper leaked its allocation");
    }
  }
}

unsafe extern "C-unwind" {
  fn cpp_create_vector() -> *mut RawCppVector;
  fn cpp_delete_vector(ptr: *mut RawCppVector);
  fn cpp_vector_size(ptr: *const RawCppVector) -> usize;
  fn cpp_vector_get(ptr: *const RawCppVector, index: usize) -> *mut ffi::c_void;
  fn cpp_vector_clear(ptr: *mut RawCppVector);
  fn cpp_vector_push_back(ptr: *mut RawCppVector, element: *mut ffi::c_void);
}

// C++ vector wrapper
#[derive(Clone)]
pub struct CppVector<'a, T: Clone + 'static> {
  inner: Arc<CppVectorInner<'a, T>>,
}

impl<'a, T: Clone> Deref for CppVector<'a, T> {
  type Target = CppVectorInner<'a, T>;

  // Deref implementation to access the inner CppVectorInner
  fn deref(&self) -> &Self::Target {
    unsafe { Arc::as_ptr(&self.inner).as_ref_unchecked() }
  }
}

impl<'a, T: Clone> CppVector<'a, T> {
  // Create a new CppVector
  pub fn new() -> Self {
    let ptr = unsafe { cpp_create_vector() };
    let inner = CppVectorInner {
      ptr,
      owned: true,
      _marker: PhantomData,
    };
    CppVector { inner: Arc::new(inner) }
  }

  // Create a CppVector from a raw C++ vector pointer
  pub fn from_raw(ptr: *mut RawCppVector) -> Self {
    let inner = CppVectorInner {
      ptr,
      owned: false,
      _marker: PhantomData,
    };

    CppVector { inner: Arc::new(inner) }
  }
}

// Inner structure for CppVector reference counting
pub struct CppVectorInner<'a, T> {
  ptr: *mut RawCppVector,
  owned: bool,
  _marker: PhantomData<&'a T>,
}

unsafe impl<T> Send for CppVectorInner<'static, T> {}
unsafe impl<T> Sync for CppVectorInner<'static, T> {}
impl<'a, T> Drop for CppVectorInner<'a, T> {
  // Destroy the C++ vector when the CppVectorInner is dropped
  fn drop(&mut self) {
    if self.owned { unsafe { cpp_delete_vector(self.ptr) }; }
  }
}

impl<T: Clone> CppVector<'_, T> {
  // Get the raw C++ vector pointer
  pub fn raw(&self) -> *mut RawCppVector {
    self.ptr
  }

  // Get a mutable raw C++ vector pointer
  pub fn raw_mut(&mut self) -> *mut RawCppVector {
    self.ptr
  }

  // Get the size of the C++ vector
  pub fn size(&self) -> usize {
    unsafe { cpp_vector_size(self.ptr) }
  }

  // Get an element from the C++ vector by index
  pub fn get(&self, index: usize) -> &mut T {
    unsafe { (cpp_vector_get(self.ptr, index) as *mut T).as_mut_unchecked() }
  }

  // Clear the C++ vector
  pub fn clear(&mut self) {
    unsafe { cpp_vector_clear(self.ptr) };
  }

  // Push an element to the back of the C++ vector
  pub fn push_back(&mut self, element: &mut T) {
    unsafe { cpp_vector_push_back(self.ptr, element as *mut T as *mut ffi::c_void) };
  }
}

#[repr(C)]
#[derive(Debug)]
pub struct RawCppVector {
  pub begin: usize,
  pub end: usize,
  pub capacity: usize,
}
