use df_local_zh_broker::{common::atomic_bytes, service::Tail};
use serde_json::json;
use std::io::Write;

#[test]
fn journal_larger_atomic_replacement_starts_at_the_new_beginning() {
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  atomic_bytes(&path,b"{\"id\":1}\n").unwrap();let mut tail=Tail::default();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"id":1})]);
  atomic_bytes(&path,b"{\"id\":2}\n{\"id\":3}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"id":2}),json!({"id":3})]);
}

#[test]
fn journal_oversized_line_suffix_is_never_a_new_record() {
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  let mut file=std::fs::File::create(&path).unwrap();
  file.write_all(&vec![b'x';2*1024*1024]).unwrap();
  file.write_all(b"{\"id\":\"not-a-separate-row\"}\n{\"id\":\"real\"}\n").unwrap();drop(file);
  let mut tail=Tail::default();let mut actual=Vec::new();
  for _ in 0..40 {actual.extend(tail.read(&path).unwrap());}
  assert_eq!(actual,vec![json!({"id":"real"})]);
}

#[test]
fn journal_open_errors_are_not_reported_as_an_empty_success() {
  let d=tempfile::tempdir().unwrap();let mut tail=Tail::default();
  assert!(tail.read(&d.path().join("missing")).unwrap().is_empty());
  assert!(tail.read(d.path()).is_err());
}

#[test]
fn journal_absence_resets_partial_bytes_before_recreation() {
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  std::fs::write(&path,b"{\"id\":").unwrap();let mut tail=Tail::default();
  assert!(tail.read(&path).unwrap().is_empty());std::fs::remove_file(&path).unwrap();
  assert!(tail.read(&path).unwrap().is_empty());
  atomic_bytes(&path,b"{\"id\":22}\n{\"id\":33}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"id":22}),json!({"id":33})]);
}

#[test]
fn journal_utf8_split_at_read_boundary_and_later_append_is_not_replayed() {
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  let text="A".repeat(65526)+"𠮷中文";
  let record=json!({"text":text});let encoded=record.to_string()+"\n";
  // Nine prefix bytes place the first byte of 𠮷 at the final byte of the read.
  assert_eq!(encoded.as_bytes()[65535],0xf0);
  std::fs::write(&path,encoded).unwrap();let mut tail=Tail::default();
  assert!(tail.read(&path).unwrap().is_empty());
  assert_eq!(tail.read(&path).unwrap(),vec![record]);
  assert!(tail.read(&path).unwrap().is_empty());
  std::fs::OpenOptions::new().append(true).open(&path).unwrap().write_all(b"{\"next\":true}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"next":true})]);
  assert!(tail.read(&path).unwrap().is_empty());assert_eq!(tail.take_rejected(),0);
}

#[test]
fn journal_discard_state_survives_eof_then_resets_for_a_replacement() {
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  std::fs::write(&path,vec![b'x';2*1024*1024]).unwrap();let mut tail=Tail::default();
  for _ in 0..40 {assert!(tail.read(&path).unwrap().is_empty());}
  assert_eq!(tail.take_rejected(),1);assert_eq!(tail.take_rejected(),0);
  std::fs::OpenOptions::new().append(true).open(&path).unwrap().write_all(b"{\"fake\":true}\n{\"real\":true}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"real":true})]);
  atomic_bytes(&path,b"{\"replacement\":true}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"replacement":true})]);
}

#[test]
#[cfg(windows)]
fn journal_sharing_violation_keeps_partial_state_until_reading_recovers() {
  use std::os::windows::fs::OpenOptionsExt;
  let d=tempfile::tempdir().unwrap();let path=d.path().join("journal");
  std::fs::write(&path,b"{\"id\":").unwrap();let mut tail=Tail::default();
  assert!(tail.read(&path).unwrap().is_empty());
  let exclusive=std::fs::OpenOptions::new().read(true).share_mode(0).open(&path).unwrap();
  assert!(tail.read(&path).is_err());drop(exclusive);
  std::fs::OpenOptions::new().append(true).open(&path).unwrap().write_all(b"9}\n").unwrap();
  assert_eq!(tail.read(&path).unwrap(),vec![json!({"id":9})]);
  assert!(tail.read(&path).unwrap().is_empty());
}
