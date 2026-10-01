fn main() {
  let modules = vec!["string", "vector", "search_callback"];
  modules.iter().for_each(|module| {
    let file = format!("src/{}.cpp", module);
    cc::Build::new().cpp(true).file(&file).compile(module);
    println!("cargo:rerun-if-changed={}", file);
  });
}
