//! Explicit numeric UI templates. Compiled at dictionary load, never learned
//! from literal numbers or AI output. Lookup is bounded and does not grow a cache.
use std::collections::HashMap;

#[derive(Default)]
pub struct NumericTemplates {
    entries: HashMap<String, Option<Entry>>,
}
struct Entry { source: String, pieces: Vec<String>, order: Vec<usize> }

fn template(text: &str) -> Option<(Vec<String>, Vec<&str>)> {
    if text.len() > 4096 || text.contains('\0') { return None; }
    let mut pieces = Vec::new();
    let mut names = Vec::new();
    let mut rest = text;
    while let Some(start) = rest.find("{{") {
        pieces.push(rest[..start].to_owned());
        rest = &rest[start + 2..];
        let end = rest.find("}}")?;
        let name = &rest[..end];
        if !["count", "minimum", "maximum", "value", "year"].contains(&name)
            || names.contains(&name) || names.len() >= 8 { return None; }
        names.push(name);
        rest = &rest[end + 2..];
    }
    pieces.push(rest.to_owned());
    if names.is_empty() || pieces.iter().any(|s| s.contains(['{', '}'])) { return None; }
    Some((pieces, names))
}

impl NumericTemplates {
    pub fn insert(&mut self, source: &str, translated: &str) {
        let Some((parts, names)) = template(source) else { return; };
        // Keep fixed identifiers out of numeric templates entirely.
        if parts.iter().any(|s| s.bytes().any(|b| b.is_ascii_digit())) { return; }
        let key = parts.join("\0");
        // An invalid replacement must not leave an older compiled translation
        // active while the exact dictionary has already accepted the new row.
        if self.entries.get(&key).and_then(Option::as_ref).is_some_and(|e| e.source == source) {
            self.entries.remove(&key);
        }
        let Some((pieces, output_names)) = template(translated) else { return; };
        if names.len() != output_names.len() { return; }
        let Some(order) = output_names.iter().map(|n| names.iter().position(|s| s == n)).collect::<Option<Vec<_>>>() else { return; };
        let entry = Entry { source: source.into(), pieces, order };
        match self.entries.entry(key) {
            std::collections::hash_map::Entry::Vacant(v) => { v.insert(Some(entry)); }
            std::collections::hash_map::Entry::Occupied(mut o) => {
                // Ambiguous templates must not depend on hash iteration order.
                if o.get().as_ref().is_some_and(|e| e.source == source) { o.insert(Some(entry)); }
                else { o.insert(None); }
            }
        }
    }

    pub fn lookup(&self, text: &str) -> Option<(String, &str)> {
        if self.entries.is_empty() || text.len() > 4096 || text.contains('\0') { return None; }
        let bytes = text.as_bytes();
        let mut key = String::with_capacity(text.len());
        let mut numbers = Vec::new();
        let (mut i, mut literal) = (0, 0);
        while i < bytes.len() {
            let signed = matches!(bytes[i], b'-' | b'+') && bytes.get(i + 1).is_some_and(u8::is_ascii_digit);
            if !bytes[i].is_ascii_digit() && !signed { i += 1; continue; }
            let start = i;
            if signed { i += 1; }
            while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
            if bytes.get(i) == Some(&b',') && bytes.get(i + 1).is_some_and(u8::is_ascii_digit) {
                let first_digits = i - start - usize::from(signed);
                if first_digits > 3 { return None; }
                while bytes.get(i) == Some(&b',') && bytes.get(i + 1).is_some_and(u8::is_ascii_digit) {
                    i += 1;
                    let group = i;
                    while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
                    if i - group != 3 { return None; }
                }
            }
            if bytes.get(i) == Some(&b'.') && bytes.get(i + 1).is_some_and(u8::is_ascii_digit) {
                i += 1;
                while i < bytes.len() && bytes[i].is_ascii_digit() { i += 1; }
            }
            if numbers.len() >= 8 { return None; }
            key.push_str(&text[literal..start]);
            key.push('\0');
            numbers.push(&text[start..i]);
            literal = i;
        }
        if numbers.is_empty() { return None; }
        key.push_str(&text[literal..]);
        let entry = self.entries.get(&key)?.as_ref()?;
        if entry.order.len() != numbers.len() { return None; }
        let mut result = entry.pieces[0].clone();
        for (i, capture) in entry.order.iter().enumerate() {
            result.push_str(numbers[*capture]);
            result.push_str(&entry.pieces[i + 1]);
        }
        Some((result, &entry.source))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn explicit_numbers_preserve_spelling_and_order_without_cache_growth() {
        let mut dict = NumericTemplates::default();
        dict.insert("Range: {{minimum}} to {{maximum}}", "最大 {{maximum}}，最小 {{minimum}}");
        dict.insert("Volume: {{count}}%", "音量：{{count}}%");
        for n in 0..=100 {
            assert_eq!(dict.lookup(&format!("Volume: {n}%")).unwrap().0, format!("音量：{n}%"));
        }
        assert_eq!(dict.lookup("Range: -1.25 to +12,345.67").unwrap().0, "最大 +12,345.67，最小 -1.25");
        for source in ["Volume: abc%", "Volume: 1,23%", "Volume: 1.2.3%", "Volume: 1e9%", "Volume: 77% extra", "Range: 1 to "] {
            assert!(dict.lookup(source).is_none(), "{source}");
        }
        assert_eq!(dict.entries.len(), 2);
    }
    #[test]
    fn rejects_prose_missing_captures_identifiers_and_ambiguous_templates() {
        let mut dict = NumericTemplates::default();
        for (a,b) in [("Version 1.2", "版本 1.2"), ("Name: {{subject}}", "名字：{{subject}}"),
            ("Count: {{count}}", "數量"), ("Count: {{count}}", "{{value}}"),
            ("Count: {{count}}", "{{count}} {{count}}"), ("Level 2: {{count}}", "{{count}}"),
            ("Count: {{count}}", "{{count}} {{") ] { dict.insert(a,b); }
        assert!(dict.entries.is_empty());
        dict.insert("Count: {{count}}", "數量 {{count}}");
        dict.insert("Count: {{value}}", "值 {{value}}");
        assert!(dict.lookup("Count: 9").is_none());
        assert!(dict.lookup(&"9".repeat(4097)).is_none());
    }
    #[test]
    fn invalid_replacement_cannot_leave_stale_compiled_output() {
        let mut dict = NumericTemplates::default();
        dict.insert("Count: {{count}}", "數量 {{count}}");
        assert_eq!(dict.lookup("Count: 5").unwrap().0, "數量 5");
        dict.insert("Count: {{count}}", "遺漏數字");
        assert!(dict.lookup("Count: 5").is_none());
        dict.insert("Count: {{count}}", "計數 {{count}}");
        assert_eq!(dict.lookup("Count: 5").unwrap().0, "計數 5");
    }
}
