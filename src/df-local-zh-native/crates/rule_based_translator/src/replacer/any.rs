use crate::*;

pub struct AnyReplacer;

impl Replacer for AnyReplacer {
  fn replace(&self, context: &mut Context, identifier: &str, base: &str, config: &str,
    text: &str, translator: &Translator, level: usize) -> Vec<ResultTree> {
    let mut results = Vec::new();
    for end in text.char_indices().map(|(index, _)| index).skip(1).chain(std::iter::once(text.len())).take(128) {
      if context.calls >= 4096 || context.expired() { break; }
      let captured = &text[..end];
      let translated = if config.is_empty() { Some(captured.to_owned()) } else {
        let reference = to_canonical_identifier(config, base);
        translator.do_translate(context, captured, &reference, level + 1).into_iter()
          .find(|result| result.remaining.is_empty()).map(|result| result.translated)
      };
      if let Some(translated) = translated {
        results.push(ResultTree::new(identifier.into(), format!("{{{identifier}}}"), captured.into(),
          translated, text[end..].into(), IndexMap::new()));
      }
    }
    results
  }
}
