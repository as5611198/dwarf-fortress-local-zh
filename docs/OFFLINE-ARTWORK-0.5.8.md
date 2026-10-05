# Offline artwork and artifact locations — 0.5.8 local candidate

Continues the offline-first objective. This increment extends the existing shared Rust item/history composers. It does not constitute completion of the overall mod improvement goal or a 90% vanilla coverage claim. No Steam or GitHub publication is included.

## Behavior

- Standalone `On the item is an image of ...` paragraphs now enter the local composer. Previously only item paragraphs starting with `This is a/an ...` were accepted.
- Image subjects can combine literal native identity slots with known dictionary nouns, including English articles. Material names use the existing reviewed material/species dictionaries. No arbitrary proper names are inferred from prose.
- Adds the observed surrounding scene and artwork depicting appointment/election to a known office. Person, organization, office and year remain distinct. Original link IDs and labels remain attached through the existing rich narrative adapter.
- Adds remote ownership claims and artifact storage inside a named building within a named site, preserving distance and both place references.
- The whole paragraph must be recognized. Unknown clauses, unknown terms/offices, malformed years and malformed/duplicate native slots reject the local result atomically.
- Retains bounds of 4,096 input bytes, 32 sentences, eight identity occurrences and bounded output. There are no new caches, I/O, network calls or world scans in this parser.

## Verification

- New item tests were observed failing for the missing standalone/artwork composition, then passed. The history test likewise failed before implementing the new templates. Tests cover both Chinese variants, identity order, material/subject lists, malformed slots, negative/oversized dates and unknown trailing clauses.
- Rust workspace: 156 passed, zero failed, 13 ignored. Node: 208 passed, zero failed, one skipped. Existing compiler warnings remain.
- Empty temporary player state, AI disabled: 210 bilingual broker lookups, zero misses, zero API requests. Maximum measured lookup 2.4686 ms, excluding initialization. This is a development/regression corpus, not a coverage benchmark.
- Release build and package validator passed. Both installed targets verified 861 files against the manifest; all 166 player-state files were unchanged during deployment.
- Deployed native/Lua integration passed exact artwork translation, literal supplementary Unicode identity labels, location order, and atomic fallback checks.
- Lua fixtures passed: narrative layout, rich runtime, fortress reports, queue I/O and polling cost. No report behavior was changed in this increment.
- Live Legends test, AI disabled: the artifact `The Tenderness of Packs` increased from 9/16 to 16/16 complete local paragraph matches. Its captured source was used for development; it is not an unseen benchmark. Clicking the artwork's Lolor Ageclasps link opened historical figure ID 1415.
- Two other artifact pages were selected after freezing/building the implementation: `Flaxmires` had 11/21 complete local paragraph matches; `The Frosty Keeper` had 5/6. Their settled screen samples were 49 and 50 FPS; the development page was 50 FPS. Initial page-opening screenshots briefly showed lower FPS and are not included in those settled-screen samples.
- Full-paragraph display requires the rich Legends overlay. It was temporarily enabled for testing and restored to the existing disabled preference afterward. Literal names and embedded English race/title labels are still retained.
- After returning to the original paused `region3`, the deployed native runtime passed all 210 bilingual corpus checks with AI disabled. Six render samples were 49, 50, 50, 50, 50, 49 FPS. This is not an unpaused simulation or soak benchmark.
- Save verification hashed 10,839 files before/after: no additions or removals. Only the normal region3 save/quit writes (`world.sav`, `dfhack-entity-2190.dat`) and the test world's DFHack lifecycle log changed. No unexpected changes were found; the full pre-save region3 backup remains private.
- Candidate ZIP verified all 861 entries. SHA-256: `61179f270c98ea8e1d25beca4f517c63e871b878b558fccbbb41a214bc84a701`.

## Remaining work and evidence

- New page misses include looting after defeating/murdering an owner, kill headings and birth/death metadata without a relationship. Named battles, complex intrigues and arbitrary image scenes remain unsupported.
- Fortress report identity integration remains incomplete. A read-only inspection of the three existing `region3` reports found text, type, positions, flags and activity/speaker fields, but no Legends-style certified link slots. Two static report strings already resolve locally; the named embark narrative does not. A safe adapter needs explicit identity provenance, world/language isolation and preserved colors without writing translated text to saved reports.
- With the rich overlay disabled, the legacy display can still show pending name placeholders while AI is off. The current parser improvements do not fix that display path; it needs a separate reproduction and regression test.
- Broader vanilla coverage must be measured with AI and learned caches absent across representative fortress, Legends and adventure screens. These few artifact pages cannot establish the overall target.

Private captures, logs, save backup and final packaging evidence are stored under the game directory at `_localization-work/offline-artwork-20261004`. Saves, API keys, captures and learned translations are excluded from the release package.
