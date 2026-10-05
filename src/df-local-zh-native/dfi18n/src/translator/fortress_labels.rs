//! Meanings proven by current native UI state, never persisted as global terms.
use crate::translation::{TranslationContext, TranslationResponse};

pub(super) fn translate(context:&TranslationContext,language:&str)->Option<TranslationResponse> {
    if context.original()!="Clear" {return None}
    let screen=match context {
        TranslationContext::addst{viewscreen,..} | TranslationContext::addst_flag{viewscreen,..}
        | TranslationContext::top_addst{viewscreen,..} | TranslationContext::addcoloredst{viewscreen,..}
        | TranslationContext::markup_text_box{viewscreen,..} | TranslationContext::dfhack{viewscreen,..}=>viewscreen,
    };
    schedule_label(context.original(),screen,language,crate::df::game::main_interface::squad_schedule_open())
        .map(|translated|TranslationResponse{translated:translated.into(),alignment:Default::default()})
}

fn schedule_label<'a>(source:&str,screen:&str,language:&str,open:bool)->Option<&'a str> {
    // The existing screen-change hook keeps dwarfmode/Default for native panel
    // transitions. The live global flag is essential: screen alone is ambiguous.
    if source=="Clear" && screen=="::t::dwarfmode/Default" && open
        && matches!(language,"zh-Hant"|"zh-Hans") {Some("清除")} else {None}
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn clear_schedule_orders_without_changing_adjectives_or_other_views() {
        for lang in ["zh-Hant","zh-Hans"] {
            assert_eq!(schedule_label("Clear","::t::dwarfmode/Default",lang,true),Some("清除"));
            assert_eq!(schedule_label("Clear","::t::dwarfmode/Default",lang,false),None);
            for source in ["clear","clear glass","Clear water","Clear "," Clear","[C:7:0:0]Clear"] {
                assert_eq!(schedule_label(source,"::t::dwarfmode/Default",lang,true),None);
            }
            for screen in ["title/Default","::t::dungeonmode/Default","::t::legends","", "::t::dwarfmode/Default/Other"] {
                assert_eq!(schedule_label("Clear",screen,lang,true),None);
            }
        }
        assert_eq!(schedule_label("Clear","::t::dwarfmode/Default","en",true),None);
    }
}
