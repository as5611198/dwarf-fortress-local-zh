//! Short movement fields drawn separately by the native adventure UI.
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
    // Observed native movement fields have this context even inside Attack.
    // These meanings are never entered into a global or persistent dictionary.
    if screen != "::t::dungeonmode/Default" || !matches!(language,"zh-Hant"|"zh-Hans") {
        return None;
    }
    let simplified = language == "zh-Hans";
    let translated = match context.original() {
        "Moving" => if simplified { "移动中" } else { "移動中" },
        "north" => "北方", "south" => "南方", "west" => "西方",
        "east" => if simplified { "东方" } else { "東方" },
        "northeast" => if simplified { "东北方" } else { "東北方" },
        "northwest" => "西北方", "southeast" => if simplified { "东南方" } else { "東南方" },
        "southwest" => "西南方",
        _ => return actor_header(context.original(), language),
    };
    Some(TranslationResponse { translated: translated.into(), alignment: Default::default() })
}

fn actor_header(source: &str, language: &str) -> Option<TranslationResponse> {
    actor_header_with(source, &|term| {
        super::simple::literal_term(language, term)
            .or_else(|| super::rulesets::translate_finite(language, term).map(|r| r.translated))
    }).map(|translated| TranslationResponse { translated, alignment: Default::default() })
}

fn actor_header_with(source: &str, term: &dyn Fn(&str) -> Option<String>) -> Option<String> {
    // Two complete role formats observed in the native attack-target list.
    // Do not infer roles from arbitrary dictionary words or translate names.
    if source.len() > 512 { return None; }
    let (role, name) = source.strip_prefix("The human ")?.split_once(' ')?;
    let role_key = match role { "mason" => "Mason", "planter" => "Planter", _ => return None };
    let (first, surname) = name.split_once(' ')?;
    let name_word = |word: &str| {
        let mut bytes = word.bytes();
        matches!(bytes.next(), Some(b'A'..=b'Z')) && bytes.all(|b| b.is_ascii_lowercase())
    };
    if !name_word(first) || !name_word(surname) { return None; }
    let species = term("human")?;
    let role = term(role_key)?;
    let chinese = |label: &str| {
        !label.is_empty() && label.len() <= 128 && label.trim() == label
            && label.chars().any(|c| matches!(c as u32, 0x3400..=0x9fff | 0x20000..=0x323af))
            && !label.chars().any(|c| c.is_ascii_alphabetic() || c.is_control() || matches!(c, '[' | ']' | '{' | '}'))
    };
    if !chinese(&species) || !chinese(&role) { return None; }
    Some(format!("{species}{role} {name}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context(screen: &str, source: &str) -> TranslationContext {
        TranslationContext::addst {
            content: source.into(), viewscreen: screen.into(),
            coordinate: Default::default(), color_pair: Default::default(),
        }
    }

    #[test]
    fn native_movement_fields_translate_only_in_observed_adventure_context() {
        let screen = "::t::dungeonmode/Default";
        for (source, hant, hans) in [
            ("Moving", "移動中", "移动中"),
            ("north", "北方", "北方"), ("south", "南方", "南方"),
            ("east", "東方", "东方"), ("west", "西方", "西方"),
            ("northeast", "東北方", "东北方"), ("northwest", "西北方", "西北方"),
            ("southeast", "東南方", "东南方"), ("southwest", "西南方", "西南方"),
        ] {
            for (lang, expected) in [("zh-Hant",hant),("zh-Hans",hans)] {
                assert_eq!(translate(&context(screen,source),lang).map(|r|r.translated).as_deref(),Some(expected),"{source} {lang}");
                for other in ["", "::t::dwarfmode/Default", "::t::legends", "dungeonmode/Default", "::t::dungeonmode/Default/extra"] {
                    assert!(translate(&context(other,source),lang).is_none(),"context leaked to {other}");
                }
            }
            assert!(translate(&context(screen,source),"en").is_none());
        }
    }

    #[test]
    fn movement_field_matching_preserves_prose_names_and_controls() {
        for source in ["Moving east", "Moving Mountains", "east gate", "Moving ",
                       " Moving", "east\n", "east\0", "[C:1:0:1]east", "East", " "] {
            assert!(translate(&context("::t::dungeonmode/Default",source),"zh-Hant").is_none(),"{source:?}");
        }
    }

    #[test]
    fn observed_actor_headers_localize_roles_and_preserve_literal_names() {
        // Losing either role, translating a name, or accepting only the first
        // observed identity breaks this contract.
        for (human, planter) in [("人類", "播種者"), ("人类", "播种者")] {
            let term = |s: &str| match s {
                "human" => Some(human.into()),
                "Mason" => Some("石匠".into()),
                "Planter" => Some(planter.into()),
                _ => None,
            };
            assert_eq!(actor_header_with("The human mason Inspuz Uromarad", &term),
                       Some(format!("{human}石匠 Inspuz Uromarad")));
            assert_eq!(actor_header_with("The human planter Itlud Gomnifih", &term),
                       Some(format!("{human}{planter} Itlud Gomnifih")));
            assert_eq!(actor_header_with("The human mason Test Different", &term),
                       Some(format!("{human}石匠 Test Different")));
        }
    }

    #[test]
    fn actor_headers_fall_back_atomically_for_unknown_or_unsafe_fields() {
        let term = |s: &str| match s {
            "human" => Some("人類".into()), "Mason" => Some("石匠".into()),
            "Planter" => Some("播種者".into()), "told" => Some("告訴".into()),
            _ => None,
        };
        for source in ["The human told Inspuz Uromarad", "The human captain Inspuz Uromarad",
                       "The elf mason Inspuz Uromarad", "The human mason Inspuz",
                       "The human mason Inspuz Uromarad attacked", "The human mason Inspuz Uromarad.",
                       "The human mason Inspuz  Uromarad", "The human mason inspuz Uromarad",
                       "The human mason [C:1:0:1]Inspuz Uromarad", "The human mason Inspuz Uromarad\n",
                       "The human mason Inspuz Uromarad\0", " The human mason Inspuz Uromarad",
                       "The human mason 測試𠮷 姓氏", "the human mason Inspuz Uromarad"] {
            assert!(actor_header_with(source, &term).is_none(), "{source:?}");
        }
        assert!(actor_header_with(&format!("The human mason {} Uromarad", "A".repeat(513)), &term).is_none());
        for invalid in ["", "Mason", "石匠 Mason", "[C:1:0:1]石匠", "石匠\0"] {
            assert!(actor_header_with("The human mason Inspuz Uromarad", &|s| {
                Some(if s == "human" { "人類" } else { invalid }.into())
            }).is_none(), "unsafe dictionary output: {invalid:?}");
        }
        for screen in ["", "::t::dwarfmode/Default", "::t::dungeonmode/Default/extra"] {
            assert!(translate(&context(screen, "The human mason Inspuz Uromarad"), "zh-Hant").is_none());
        }
        assert!(translate(&context("::t::dungeonmode/Default", "The human mason Inspuz Uromarad"), "en").is_none());
    }
}
