use std::{collections::HashMap, marker::PhantomData, ops::Deref, sync::{Arc, Mutex, OnceLock, Weak, atomic::{AtomicPtr, Ordering}}};

use crate::*;

// SDL destroys every texture when its renderer is destroyed. Clear live
// wrappers first so cached clones cannot use or destroy those pointers again.
type TexturePointers=HashMap<usize,Vec<Weak<AtomicPtr<SDL_Texture>>>>;
static TEXTURES:OnceLock<Mutex<TexturePointers>>=OnceLock::new();
fn registered(renderer: &Renderer<'_>, ptr:*mut SDL_Texture)->Arc<AtomicPtr<SDL_Texture>> {
  let pointer=Arc::new(AtomicPtr::new(ptr));
  let mut all=TEXTURES.get_or_init(||Mutex::new(HashMap::new())).lock().unwrap();
  let items=all.entry(renderer.raw() as usize).or_default();
  if items.len()%128==0 {items.retain(|p|p.strong_count()>0);}
  items.push(Arc::downgrade(&pointer));
  pointer
}
pub fn invalidate_renderer_textures(renderer:*const SDL_Renderer) {
  let pointers=TEXTURES.get_or_init(||Mutex::new(HashMap::new())).lock().unwrap().remove(&(renderer as usize));
  for pointer in pointers.into_iter().flatten().filter_map(|p|p.upgrade()) {
    let raw=pointer.swap(std::ptr::null_mut(),Ordering::AcqRel);
    if !raw.is_null() {unsafe {SDL_DestroyTexture(raw)};}
  }
}

#[cfg(test)]
mod lifetime_tests {
  use super::*;
  #[cfg_attr(target_os="windows",link(name="SDL2",kind="raw-dylib"))]
  unsafe extern "C" {fn SDL_CreateSoftwareRenderer(surface:*mut SDL_Surface)->*mut SDL_Renderer;}
  #[test]
  fn renderer_destruction_invalidates_all_cached_texture_clones() {
    let surface=Surface::new(16,16);
    let raw=unsafe {SDL_CreateSoftwareRenderer(surface.raw_mut())};assert!(!raw.is_null());
    let renderer=Renderer::from_raw(raw);
    let texture=Texture::from_surface(&renderer,&surface);let clone=texture.clone();
    assert!(!texture.raw().is_null());
    invalidate_renderer_textures(raw);
    assert!(texture.raw().is_null());assert!(clone.raw().is_null());
    unsafe {SDL_DestroyRenderer(raw)};
    drop(texture);drop(clone); // must not free an already-destroyed SDL pointer
  }
}

#[allow(non_upper_case_globals)]
const SDL_ScaleModeBest: u32 = 2;
const SDL_BLENDMODE_BLEND: u32 = 1;

// SDL Texture wrapper
#[derive(Clone)]
pub struct Texture<'a> {
  inner: Arc<TextureInner<'a>>,
}

impl<'a> Deref for Texture<'a> {
  type Target = TextureInner<'a>;

  // Deref implementation to access the inner TextureInner
  fn deref(&self) -> &Self::Target {
    unsafe { Arc::as_ptr(&self.inner).as_ref_unchecked() }
  }
}

impl<'a> PartialEq for Texture<'_> {
  // PartialEq implementation to compare two Texture instances
  fn eq(&self, other: &Self) -> bool {
    self.raw() == other.raw()
  }
}

impl<'a> Texture<'a> {
  // Create a new SDL Texture from a renderer and surface
  pub fn from_surface(renderer: &Renderer<'a>, surface: &Surface<'a>) -> Self {
    let ptr = unsafe { SDL_CreateTextureFromSurface(renderer.raw_mut(), surface.raw_mut()) };

    if ptr.is_null() {
      log::error!("Failed to create texture from surface");
    }

    let inner = TextureInner {
      ptr:registered(renderer,ptr),
      _renderer:renderer.clone(),
      _marker: PhantomData,
    };
    inner.set_scale_mode(SDL_ScaleModeBest);
    inner.set_blend_mode(SDL_BLENDMODE_BLEND);

    Texture { inner: Arc::new(inner) }
  }

  // Create a new SDL Texture from a renderer and raw surface pointer
  pub fn from_raw_surface(renderer: &Renderer<'a>, surface_ptr: *mut SDL_Surface) -> Self {
    let ptr = unsafe { SDL_CreateTextureFromSurface(renderer.raw_mut(), surface_ptr) };

    if ptr.is_null() {
      log::error!("Failed to create texture from surface pointer");
    }

    let inner = TextureInner {
      ptr:registered(renderer,ptr),
      _renderer:renderer.clone(),
      _marker: PhantomData,
    };
    inner.set_scale_mode(SDL_ScaleModeBest);
    inner.set_blend_mode(SDL_BLENDMODE_BLEND);

    Texture { inner: Arc::new(inner) }
  }
}

// Inner structure for Texture reference counting
pub struct TextureInner<'a> {
  ptr: Arc<AtomicPtr<SDL_Texture>>,
  _renderer:Renderer<'a>,
  _marker: PhantomData<&'a ()>,
}

unsafe impl Send for TextureInner<'static> {}
unsafe impl Sync for TextureInner<'static> {}
impl<'a> Drop for TextureInner<'a> {
  // Destroy the SDL Texture when the TextureInner is dropped
  fn drop(&mut self) {
    let ptr=self.ptr.swap(std::ptr::null_mut(),Ordering::AcqRel);
    if !ptr.is_null() {unsafe { SDL_DestroyTexture(ptr) };}
  }
}

impl TextureInner<'_> {
  // Get the raw SDL_Texture pointer
  pub fn raw(&self) -> *const SDL_Texture {
    self.ptr.load(Ordering::Acquire)
  }

  // Get a mutable raw SDL_Texture pointer
  pub fn raw_mut(&self) -> *mut SDL_Texture {
    self.ptr.load(Ordering::Acquire)
  }

  // Get the size of the texture
  pub fn size(&self) -> (i32, i32) {
    let mut w: ffi::c_int = 0;
    let mut h: ffi::c_int = 0;
    let pw = &mut w as *mut ffi::c_int;
    let ph = &mut h as *mut ffi::c_int;

    if unsafe { SDL_QueryTexture(self.raw_mut(), std::ptr::null_mut(), std::ptr::null_mut(), pw, ph) != 0 } {
      log::error!("Failed to query texture size");
      return (0, 0);
    }

    (w, h)
  }

  // Set the scale mode of the texture
  fn set_scale_mode(&self, scale_mode: u32) {
    if unsafe { SDL_SetTextureScaleMode(self.raw_mut(), scale_mode) != 0 } {
      log::error!("Failed to set texture scale mode");
    }
  }

  // Set the blend mode of the texture
  fn set_blend_mode(&self, blend_mode: u32) {
    if unsafe { SDL_SetTextureBlendMode(self.raw_mut(), blend_mode) != 0 } {
      log::error!("Failed to set texture blend mode");
    }
  }

  // Set the color modulation of the texture
  pub fn set_color_mod(&self, r: u8, g: u8, b: u8) {
    if unsafe { SDL_SetTextureColorMod(self.raw_mut(), r, g, b) != 0 } {
      log::error!("Failed to set texture color mod");
    }
  }
}

// Dummy SDL Texture
#[repr(C)]
#[derive(Copy, Clone)]
#[allow(non_camel_case_types)]
pub struct SDL_Texture {
  _unused: [u8; 0],
}
