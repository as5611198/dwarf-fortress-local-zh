use std::ffi;

unsafe extern "C-unwind" {
  fn string_size(ptr: *const ffi::c_void) -> usize;
  fn string_data(ptr: *const ffi::c_void) -> *const u8;
  fn cp437_cstr_ptr_to_utf8_slice(ptr: *const ffi::c_char, utf8_slice: *mut u8) -> usize;
  fn utf8_slice_to_cp437_codepoint(ptr: *const u8, len: usize) -> u8;
}

// Decode a C string pointer to a Rust UTF-8 String
pub fn c_string_to_string(ptr: *const ffi::c_char) -> String {
  if ptr.is_null() {
    return String::new();
  }

  let c_str = unsafe { ffi::CStr::from_ptr(ptr) };
  decode_bytes(c_str.to_bytes())
}

// Decode a C++ string pointer to a Rust UTF-8 String
pub fn cxx_string_to_string(ptr: *const ffi::c_void) -> String {
  if ptr.is_null() {return String::new()}
  let size = unsafe { string_size(ptr) };
  let bytes=unsafe {std::slice::from_raw_parts(string_data(ptr),size)};
  decode_bytes(bytes)
}
// Legacy CP437 remains the default. Only validated Chinese UTF-8 opts in.
pub fn chinese_utf8(bytes:&[u8])->Option<&str> {
  std::str::from_utf8(bytes).ok().filter(|text|text.chars().any(|ch|matches!(ch,'\u{3100}'..='\u{312f}'|'\u{3400}'..='\u{9fff}'|'\u{20000}'..='\u{323af}')))
}

// DF concatenates a UTF-8 nickname with a CP437 surname before rendering.
// Keep byte offsets for the color array, and never insert markup into a CJK
// sequence. Non-CJK legacy bytes retain their original CP437 interpretation.
pub fn character_spans(bytes:&[u8])->impl Iterator<Item=(usize,&[u8])> {
  let full_utf8=chinese_utf8(bytes).is_some();
  let mut offset=0;
  std::iter::from_fn(move || {
    if offset>=bytes.len() {return None}
    let start=offset;
    let length=match bytes[start] {0xc2..=0xdf=>2,0xe0..=0xef=>3,0xf0..=0xf4=>4,_=>1};
    let width=if full_utf8 || length>=3 && bytes.get(start..start+length).and_then(chinese_utf8).is_some() {length} else {1};
    offset+=width;
    Some((start,&bytes[start..offset]))
  })
}

fn decode_bytes(bytes:&[u8])->String {
  if let Some(text)=chinese_utf8(bytes) {return text.to_owned()}
  static LEGACY:std::sync::OnceLock<[char;256]>=std::sync::OnceLock::new();
  let legacy=LEGACY.get_or_init(||std::array::from_fn(|i|if i==0 {' '} else {cp437_codepoint_to_char(i as u8)}));
  let mut result=String::with_capacity(bytes.len());
  for (_,span) in character_spans(bytes) {
    if span.len()==1 {result.push(legacy[span[0] as usize]);}
    else if let Ok(text)=std::str::from_utf8(span) {result.push_str(text);}
  }
  result
}

// Convert a single CP437 codepoint to its character, '\u{0}' for NUL
pub fn cp437_codepoint_to_char(codepoint: u8) -> char {
  let c_string = if codepoint == 0 {
    ffi::CString::new("").unwrap()
  } else {
    ffi::CString::from_vec_with_nul(vec![codepoint, 0]).unwrap()
  };
  let ptr = c_string.as_c_str().as_ptr();
  let mut utf8_bytes: Vec<u8> = Vec::with_capacity(4); // max 4 bytes per char in UTF-8
  let utf8_size = unsafe { cp437_cstr_ptr_to_utf8_slice(ptr, utf8_bytes.as_mut_ptr()) };
  unsafe { utf8_bytes.set_len(utf8_size) };
  String::from_utf8(utf8_bytes).unwrap_or_default().chars().next().unwrap_or(' ')
}

// Convert a Rust string to a vector of CP437 codepoints
pub fn string_to_cp437_codepoints(s: &str) -> Vec<u8> {
  s.chars().map(|ch| char_to_cp437_codepoint(ch)).collect()
}

// Convert a character to its CP437 codepoint, 0 for not found
pub fn char_to_cp437_codepoint(ch: char) -> u8 {
  let ch = ch.to_string();
  unsafe { utf8_slice_to_cp437_codepoint(ch.as_ptr(), ch.len()) }
}

// Check if a character is representable in CP437
pub fn char_is_cp437(ch: char) -> bool {
  char_to_cp437_codepoint(ch) != 0
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn chinese_nickname_and_legacy_surname_share_a_render_line() {
    let mut bytes="'測試𠮷A1' Nos".as_bytes().to_vec();
    bytes.extend_from_slice(b"\x8cmilral");
    let name=ffi::CString::new(bytes).unwrap();
    assert_eq!(c_string_to_string(name.as_ptr()),"'測試𠮷A1' Nosîmilral");
    let spans=character_spans(name.as_bytes()).filter(|(_,span)|span.len()>1).collect::<Vec<_>>();
    assert_eq!(spans,vec![(1,"測".as_bytes()),(4,"試".as_bytes()),(7,"𠮷".as_bytes())]);
    // A broken trailing codepoint must remain legacy bytes; never slice past
    // the end or replace a malformed sequence with half of a CJK character.
    for length in 1..4 {
      let broken=ffi::CString::new(&"𠮷".as_bytes()[..length]).unwrap();
      assert!(!c_string_to_string(broken.as_ptr()).contains('𠮷'));
    }
  }
  #[test]
  fn chinese_names_keep_utf8_without_reinterpreting_legacy_latin() {
    let name=ffi::CString::new("鐵匠𠮷 A1").unwrap();
    assert_eq!(c_string_to_string(name.as_ptr()),"鐵匠𠮷 A1");
    assert!(chinese_utf8(&[0x82,0x20,0x41]).is_none());
    let latin=ffi::CString::new(vec![0x82,0x20,0x41]).unwrap();
    assert_eq!(c_string_to_string(latin.as_ptr()),"é A");
    assert!(chinese_utf8(&[0xff,0xe9,0x90,0xb5]).is_none());
  }
  #[test]
  fn test_string_to_cp437_codepoint() {
    assert_eq!(char_to_cp437_codepoint('\u{0}'), 0x0); // 0x00 mapped to space
    assert_eq!(char_to_cp437_codepoint('☺'), 0x01); // first CP437 character (except NULL)
    assert_eq!(char_to_cp437_codepoint(' '), 0x20); // space only maps back to 0x20, not 0x00
    assert_eq!(char_to_cp437_codepoint('A'), 0x41); // ASCII character - same codepoint
    assert_eq!(char_to_cp437_codepoint('é'), 0x82); // Latin character
    assert_eq!(char_to_cp437_codepoint('¥'), 0x9d); // Symbol character
    assert_eq!(char_to_cp437_codepoint('■'), 0xfe); // Last CP437 character (except 0xff)
    assert_eq!(char_to_cp437_codepoint('\u{a0}'), 0xff); // 0xff mapped to NBSP
    assert_eq!(char_to_cp437_codepoint('😀'), 0x00); // not found
    assert_eq!(char_to_cp437_codepoint('汉'), 0x00); // not found
  }
}
