use std::fs;
use std::sync::{OnceLock, RwLock, RwLockWriteGuard};
use std::{collections::HashMap, ffi};

use lua53_sys as lua;
use sdl2_sys as sdl;

use crate::df;

const LOGO_PNG: &[u8] = include_bytes!("logo.png");

static LOGO_SURFACE: OnceLock<sdl::Surface<'static>> = OnceLock::new();

static LOGO_TEXTURE: OnceLock<RwLock<Option<sdl::Texture<'static>>>> = OnceLock::new();

fn get_logo_surface() -> &'static sdl::Surface<'static> {
  LOGO_SURFACE.get_or_init(|| sdl::Surface::load_image(LOGO_PNG))
}

pub fn get_logo_texture() -> sdl::Texture<'static> {
  let mut cached=LOGO_TEXTURE.get_or_init(||RwLock::new(None)).write().unwrap();
  if cached.as_ref().is_none_or(|t|t.raw().is_null()) {
    let sdl_renderer = df::renderer::get_sdl_info().renderer();
    let surface = get_logo_surface();
    *cached=Some(sdl::Texture::from_raw_surface(&sdl_renderer, surface.raw_mut()));
  }
  cached.as_ref().unwrap().clone()
}

// Decode during package setup, never from the per-frame title renderer.
static TITLE_LOGO_PATHS: OnceLock<RwLock<HashMap<String, sdl::Surface<'static>>>> = OnceLock::new();

// Getting mutable access to the title logo paths
pub fn get_title_logo_paths_mut() -> RwLockWriteGuard<'static, HashMap<String, sdl::Surface<'static>>> {
  TITLE_LOGO_PATHS.get_or_init(|| RwLock::new(HashMap::new())).write().unwrap()
}

// Logo textures cache grouped by language tag
static TITLE_LOGO: OnceLock<RwLock<HashMap<String, sdl::Texture<'static>>>> = OnceLock::new();

// Getting mutable access to the title logo textures cache
pub fn get_title_logo_mut() -> RwLockWriteGuard<'static, HashMap<String, sdl::Texture<'static>>> {
  TITLE_LOGO.get_or_init(|| RwLock::new(HashMap::new())).write().unwrap()
}

// Get title logo texture by language tag
pub fn get_title_logo_by_lang_tag(lang_tag: &str) -> Option<sdl::Texture<'static>> {
  let mut title_logo = get_title_logo_mut();
  if let Some(texture)=title_logo.get(lang_tag).filter(|t|!t.raw().is_null()) {return Some(texture.clone())}
  title_logo.remove(lang_tag);

  let title_logo_paths = get_title_logo_paths_mut();
  if let Some(surface) = title_logo_paths.get(lang_tag) {
    let sdl_renderer = df::renderer::get_sdl_info().renderer();
        let texture = sdl::Texture::from_surface(&sdl_renderer, surface);
        return Some(title_logo.entry(lang_tag.to_owned()).or_insert(texture).to_owned());
  }

  None
}

// Load title logo texture from Lua
#[unsafe(no_mangle)]
extern "C" fn load_title_logo(lua_state: *mut ffi::c_void) -> i32 {
  let lang_tag = lua::check_string(lua_state, 1);
  let path_str = lua::check_string(lua_state, 2);
  match fs::read(&path_str).map_err(anyhow::Error::from).and_then(|data|sdl::Surface::try_load_image(&data)) {
    Ok(surface)=>{get_title_logo_paths_mut().insert(lang_tag.clone(),surface);get_title_logo_mut().remove(&lang_tag);},
    Err(error)=>log::warn!("Title logo load failed for {lang_tag}: {error}"),
  }
  0
}
