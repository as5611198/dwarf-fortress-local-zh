//! Complete combat menu labels, composed atomically from known local terms.
pub fn lookup(source: &str, term: &dyn Fn(&str) -> Option<String>, simplified: bool) -> Option<String> {
    // This path runs before dispatch: bound work and reject markup/names rather
    // than emitting a partially translated label or queuing individual pieces.
    if source.len() > 256 || !source.is_ascii() || source.trim() != source
        || source.bytes().any(|b| b.is_ascii_control()) { return None; }
    let local = |hant, hans| if simplified { hans } else { hant };
    let known = |s: &str| {
        let translated = term(s)?;
        (!translated.is_empty() && translated.len() <= 512
            && !translated.chars().any(|c| c.is_control() || c.is_ascii_alphabetic()
                || matches!(c, '[' | ']' | '{' | '}' | '\u{fffd}')))
            .then_some(translated)
    };
    if let Some(part) = source.strip_prefix("Attack ").and_then(|s| s.strip_suffix(':')) {
        if !body_part(part) { return None; }
        return Some(format!("{}{}：", local("攻擊", "攻击"), known(part)?));
    }
    let (action, rest) = source.split_once('/')?;
    let (component, subject) = match rest.split_once('/') {
        Some((part, subject)) if !subject.contains('/') => (Some(part), subject),
        None => (None, rest),
        _ => return None,
    };
    let action_text = match action {
        "slash" => local("斬擊", "斩击"), "stab" => local("刺擊", "刺击"),
        "slap" => local("拍擊", "拍击"), "strike" => local("打擊", "打击"),
        "punch" if matches!(subject, "left hand" | "right hand") => local("拳擊", "拳击"),
        "kick" if matches!(subject, "left foot" | "right foot") => local("踢擊", "踢击"),
        _ => return None,
    };
    let component_text = match (action, component) {
        ("slap", Some("flat")) => Some("平面"),
        ("strike", Some("pommel")) => Some(local("柄頭", "柄头")),
        (_, None) => None,
        _ => return None,
    };
    let subject_text = known(subject)?;
    Some(match component_text {
        Some(part) => format!("{action_text}／{part}／{subject_text}"),
        None => format!("{action_text}／{subject_text}"),
    })
}

fn body_part(source: &str) -> bool {
    matches!(source, "upper body" | "lower body" | "head" | "neck"
        | "right upper arm" | "left upper arm" | "right lower arm" | "left lower arm"
        | "right hand" | "left hand" | "right upper leg" | "left upper leg"
        | "right lower leg" | "left lower leg" | "right foot" | "left foot")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn term(source: &str) -> Option<String> {
        match source {
            "iron scimitar" => Some("鐵彎刀".into()),
            "copper shield" => Some("銅盾".into()),
            "left hand" => Some("左手".into()),
            "right hand" => Some("右手".into()),
            "left foot" => Some("左腳".into()),
            "right foot" => Some("右腳".into()),
            "right lower leg" => Some("右小腿".into()),
            "head" => Some("頭部".into()),
            "unknown english" => Some("partly English".into()),
            "bad markup" => Some("[C:1:0:1]錯誤".into()),
            "invalid unicode" => Some("�".into()),
            "bad control" => Some("錯\n誤".into()),
            _ => None,
        }
    }

    #[test]
    fn observed_combat_combinations_translate_as_complete_labels() {
        for (source, expected) in [
            ("slash/iron scimitar", "斬擊／鐵彎刀"),
            ("stab/iron scimitar", "刺擊／鐵彎刀"),
            ("slap/flat/iron scimitar", "拍擊／平面／鐵彎刀"),
            ("strike/pommel/iron scimitar", "打擊／柄頭／鐵彎刀"),
            ("strike/copper shield", "打擊／銅盾"),
            ("punch/left hand", "拳擊／左手"),
            ("punch/right hand", "拳擊／右手"),
            ("kick/left foot", "踢擊／左腳"),
            ("kick/right foot", "踢擊／右腳"),
            ("Attack right lower leg:", "攻擊右小腿："),
            ("Attack right foot:", "攻擊右腳："),
        ] {
            assert_eq!(lookup(source, &term, false).as_deref(), Some(expected), "{source}");
        }
    }

    #[test]
    fn combat_simplified_keeps_the_resolved_dictionary_language() {
        let terms = |s: &str| match s {
            "iron scimitar" => Some("铁弯刀".into()),
            "right lower leg" => Some("右小腿".into()),
            _ => None,
        };
        assert_eq!(lookup("strike/pommel/iron scimitar", &terms, true).as_deref(), Some("打击／柄头／铁弯刀"));
        assert_eq!(lookup("Attack right lower leg:", &terms, true).as_deref(), Some("攻击右小腿："));
    }

    #[test]
    fn combat_unknown_or_malformed_components_fall_back_atomically() {
        for source in [
            "slash/unknown weapon", "punch/unknown body", "throw/iron scimitar",
            "slap/mystery/iron scimitar", "strike/flat/iron scimitar",
            "stab/pommel/iron scimitar", "slash/flat/iron scimitar",
            "slash//iron scimitar", "slash/iron scimitar/extra", "punch/left foot",
            "kick/left hand", "punch/iron scimitar", "kick/copper shield",
            "Attack unknown body:", "Attack copper shield:", "Attack head: trailing",
            "Attack head", "slash/iron scimitar. Extra prose", " slash/iron scimitar",
            "slash/iron scimitar ", "slash/unknown english", "slash/bad markup",
            "slash/invalid unicode", "slash/bad control", "slash/鐵彎刀",
            "slash/[iron scimitar]", "slash/{DFL0}", "slash/iron scimitar\0",
        ] {
            assert!(lookup(source, &term, false).is_none(), "{source:?}");
        }
        assert!(lookup(&format!("slash/{}", "a".repeat(4096)), &term, false).is_none());
        assert!(lookup("Attack head:", &|_| Some("頭".repeat(4096)), false).is_none());
    }
}
