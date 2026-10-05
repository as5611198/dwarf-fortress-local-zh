# Offline thoughts, needs and item descriptions — 0.5.5 local candidate

Extends the approved offline-first work in 0.5.3/0.5.4. No Steam or GitHub publication is part of this stage.

## Changes

- Adds 1,299 independently reviewed rows per language for needs, emotions, thought reasons, current-thought quotes, and selected events. Includes self-reflection, unmet needs, migrants, ambushes, sieges, calendar seasons and a finite set of fishing notices.
- Composes thoughts from known emotion/reason clauses, including remembering and dwelling upon. The shared Rust parser is bounded to 4,096 input bytes and 64 sentence segments; it uses direct dictionary lookups, without render-time file access, general grammar expansion or dictionary scans.
- Preserves semantic palette spans in the unit sheet. The whole thought is translated before wrapping; Chinese UTF-8 is not decoded again as CP437. Existing values/abilities can still use their independently translated color spans.
- Binds prayer/communion names only after matching a real deity reference on the current unit. The generic dictionary contains a typed DEITY_NAME slot, never a captured save's god name. Unknown canonical names remain literal if no trusted name translation is available.
- Composes basic item descriptions from existing equipment/material terms, including material and craftsmanship. Unknown sentences or materials reject the whole description instead of producing a partially translated result.
- Isolates emotion/reason keys from ordinary UI words such as content/free.
- Connects item composition to both the renderer and Lua's pure-local lookup, verified separately to avoid a broker-only pass.
- Fixes a broker/native inconsistency: the broker now loads reviewed conflict tails as well as sentences, values and abilities.

## Verification

- Red/green tests reproduced missing self-reflection needs, missing thought composition, missing item descriptions and lost emotion colors. Additional tests reject unknown clauses, malformed palette codes and malformed memory-word boundaries.
- Node: 208 passed, 1 skipped. Rust workspace: 145 passed, 13 ignored opt-in/environment-specific tests. Existing compiler deprecation/manifest warnings remain.
- Lua: thought palette composition, typed preference/deity identity, stable polling, original-source preservation, supplementary Unicode, value colors and literal renderer isolation passed.
- Packaged broker with temporary empty state, AI disabled and official downloads disabled: 122 bilingual queries passed; zero API requests. Includes this stage's captured sources, synthetic combinations, and prior personality regression pages. Maximum measured lookup: 3.46 ms on this machine; startup dictionary loading is separate.
- Native in-game pure-local lookup: 122 bilingual queries passed with AI disabled; maximum measured lookup was approximately 1 ms. Six paused-world render samples were 49–50 FPS. These timings are development observations, not an unpaused simulation benchmark.
- Visual checks with the unit adapter temporarily restricted to native.local_lookup confirmed thought emotion colors, needs including introspection/prayer, and a pig-tail trousers/material description. The normal adapter was restored afterward; AI remained disabled and the game remained paused. Unrecognized current-thought quotes can still remain English.
- Both local installation targets matched all 858 package files. The final ZIP was reopened and all 858 entries verified against their SHA-256 hashes. Archive SHA-256: `66cb77011efff18c6025c309a39976432931ee849e68eb62a0a8f2a411d180f5`.
- Save hash comparison found two changed files within the active region3 save after normal save/quit cycles, no added/missing files, and no changes in other saves. The original region3 backup is retained. Detailed results are in `_localization-work/offline-life-20261004/final-verification.json` and `save-verification.json` under the game directory.

## Scope and remaining work

These development samples were used to locate and repair omissions; they are regression evidence, not a blind coverage benchmark. This does not establish 90% coverage of all vanilla content.

Arbitrary world-history/event narratives, named participants in announcements, elaborate artifact engravings/decorations, unreviewed emotions/reasons, and other unknown descriptions still use the existing fallback. The initial embark narrative is outside this bounded event set. No new learned translations or player identities are shipped as dictionary data.

The real save is backed up before the normal save/quit/reload cycle. Player settings, API profiles and learned cache files are not deleted. The release archive contains only package-manifest files, excluding private captures and save backups.
