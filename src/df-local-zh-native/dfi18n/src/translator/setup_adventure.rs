//! Contextual creation labels. Never install these meanings in the global dictionary.
use crate::translation::{TranslationContext, TranslationResponse};

pub(super) fn translate(context: &TranslationContext, language: &str) -> Option<TranslationResponse> {
    let screen = match context {
        TranslationContext::addst { viewscreen, .. }
        | TranslationContext::addst_flag { viewscreen, .. }
        | TranslationContext::addcoloredst { viewscreen, .. }
        | TranslationContext::top_addst { viewscreen, .. }
        | TranslationContext::markup_text_box { viewscreen, .. }
        | TranslationContext::dfhack { viewscreen, .. } => viewscreen.as_str(),
    };
    lookup(screen, context.original(), language).map(|translated| TranslationResponse {
        translated, alignment: Default::default(),
    })
}

fn lookup(screen: &str, source: &str, language: &str) -> Option<String> {
    lookup_with(screen,source,language,&|s|super::simple::literal_term(language,s))
}
fn lookup_with(screen: &str, source: &str, language: &str, term: &dyn Fn(&str)->Option<String>) -> Option<String> {
    if screen!="::t::setupadventure" || !matches!(language,"zh-Hant"|"zh-Hans") {return None}
    let simplified=language=="zh-Hans";
    let literal=match source {
        "Back"=>Some("返回"),
        "Home"=>Some("出身地"),
        _=>None,
    };
    if let Some(value)=literal {return Some(value.into())}
    if source.len()>512 || source.contains(['\0','\r','\n','[',']']) {return None}
    if let Some((species,sex))=source.rsplit_once(", ") {
        if matches!(sex,"♂"|"♀") {
            let label=term(species)?;
            if label.is_empty() || label.chars().any(|c|c.is_ascii_alphabetic()) {return None}
            return Some(format!("{label}, {sex}"));
        }
    }
    let (prefix,name)=if let Some(name)=source.strip_prefix("From ") {
        (if simplified {"来自"} else {"來自"},name)
    } else if let Some(name)=source.strip_prefix("Select ") {
        (if simplified {"选择"} else {"選擇"},name)
    } else {return None};
    if name.trim().is_empty() {return None}
    // Named civilizations are literal; existing race labels still use local data.
    let label=if source.starts_with("Select ") {term(name)} else {None};
    Some(format!("{prefix} {}",label.as_deref().unwrap_or(name)))
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn creation_labels_are_scoped_and_preserve_name_literals() {
        let screen = "::t::setupadventure";
        for lang in ["zh-Hant", "zh-Hans"] {
            assert_eq!(lookup(screen, "Back", lang).as_deref(), Some("返回"));
            assert_eq!(lookup(screen, "Home", lang).as_deref(), Some("出身地"));
            assert_eq!(lookup(screen, "From Fixture, The Test Kingdom", lang).as_deref(),
                Some(if lang=="zh-Hant" {"來自 Fixture, The Test Kingdom"} else {"来自 Fixture, The Test Kingdom"}));
            assert_eq!(lookup(screen, "Select 測試𠮷", lang).as_deref(),
                Some(if lang=="zh-Hant" {"選擇 測試𠮷"} else {"选择 測試𠮷"}));
            for other in ["", "::t::dwarfmode", "::t::setupadventure/other", "setupadventure"] {
                assert!(lookup(other, "Back", lang).is_none(), "anatomy/global lookup must keep its own meaning");
                assert!(lookup(other, "From Fixture", lang).is_none());
            }
            for invalid in ["From ", "Select ", "Select name\nextra", "From [C:1:0:0]name", "Back injury"] {
                assert!(lookup(screen, invalid, lang).is_none(), "{invalid}");
            }
            assert!(lookup(screen, &format!("Select {}", "a".repeat(513)), lang).is_none());
        }
        assert!(lookup(screen,"Back","en").is_none());
    }
    #[test]
    fn sex_symbols_keep_their_identity_after_species_translation() {
        let term=|s:&str|match s {"alpaca"=>Some("羊駝".into()),"Dwarf"=>Some("矮人".into()),_=>None};
        for (source,expected) in [("alpaca, ♀","羊駝, ♀"),("Dwarf, ♂","矮人, ♂")] {
            assert_eq!(lookup_with("::t::setupadventure",source,"zh-Hant",&term).as_deref(),Some(expected));
            assert!(lookup_with("::t::dwarfmode",source,"zh-Hant",&term).is_none());
        }
        for source in ["unknown creature, ♀","alpaca, ♀ injured","alpaca, any"] {
            assert!(lookup_with("::t::setupadventure",source,"zh-Hant",&term).is_none());
        }
    }
}
