# Legends text, trade and caption repair

This continues the original-world development audit. It does not contribute
independent samples to the overall vanilla 90% release gate.

Native link type `-1` contains a non-clickable related figure label. Capture now
creates a local-only `{{DFTn}}` slot for this exact native span, with its original
Unicode text and palette. A trailing comma belongs to the sentence template.
The original source, native word records and native link records remain intact.
Local restoration must exactly equal the captured source before lookup. DFT is
forbidden in ordinary rich requests and response journals; it never invents a
click identity. At most eight local literals and 64 native links are accepted.

The shared history composer supports complete trade outcomes (`did poorly`,
`broke even`) and `devoured a/an <animal> of <entity> in <site>`. All goods and
animal terms must have complete reviewed translations. Unknown terms and
trailing prose reject the entire paragraph. Native and Broker material loaders
also include the root material-state ruleset, fixing the observed birch/alder
bed lookup. Canonical wording remains 樺樹, 榿樹 and 雪怪.

The generated creature dictionary retains 951 descriptions per language and
adds 2,539 typed `DFL_LEGENDS_RACE:` labels. Figure captions use this namespace
only, preserving literal names and link identity. They do not consult learned
translations or generic nouns. Unknown procedural labels remain unsupported.

## Regression and cold UI evidence

The first candidate contains 913 manifest-verified files. Its manifest SHA-256
is `cbcf67764f5cee0ba23bc29ca5755cf62dcefec41b3344a291876051a8b1cba6`.
Native DLL SHA-256 is
`957e44f5ac0bc9b8d21c554835b2780b3befc706c886353d732768e2f266be98`;
Broker EXE SHA-256 is
`3647b61413c23de5871e55d8f3fd53cd1d98108e6922d7f90787475555d6510e`.
Both binaries use static CRT builds with no Visual C++ runtime DLL imports.

Six source Lua fixtures pass. The ordinary Rust workspace suite passes after
the material repair (91 Native and 109 Broker unit tests, plus other workspace
and integration suites; opt-in tests are separate). Relevant Node tests pass.
Packaged Native and an empty-state Broker each pass 50 exact bilingual local
lookups, with zero worker/provider submissions. Package validation passes.

Cold UI verification entered Legends through the original world/mode menus,
using an isolated world clone, fresh cache/state, and disabled AI, cloud
download and contributions. The loaded DLL passed all 50 bilingual checks;
ready/pending/submission counters remained `[0,0,268]`. Both trade outcome
sentences, yeti/goblin descriptions, devoured-animal sentences and the formerly
unsupported only-daughter label rendered in Chinese. The daughter's literal
name retained palette 7 and had no click target. All 330 native word records
and 56 native link records matched the preceding cold regression exactly.

An actual coordinate click on the translated paragraph opened entity 35,
The Steamy Kingdoms. This run establishes coordinate-click behavior, in addition
to the earlier native dispatch regression. Settled graphics FPS was 50;
transition captures were lower. Initial captures and settled screenshots do
not establish first-visible-frame or large-population/unpaused performance.

The game exited normally. All 10,839 protected original save files were
unchanged, both unchanged clones were archived, and original player settings,
legacy cache and overlay configuration were restored. Private evidence is in
`live-ui-0511-legends-text-trade-20261005`, including `COLD-LIVE-RESULT.json`,
`LINK-TARGET.json`, screenshots and `restoration-report.json`.

## Follow-up boundary defects

The cold run also reproduced `the badger brute The Last Poison` becoming
`獾獾 brute The Last Poison`. Typed caption matching now requires a complete
race before an uppercase or Unicode proper-name suffix; it cannot shorten an
unknown lowercase caste descriptor to a known animal. A failing fixture
reproduced this defect before the fix. Known multiword races and literal Unicode
names remain supported.

Malformed rich response records previously replaced valid cached paragraphs,
allowing an injected DFT or out-of-range/duplicate DFL token to reach renderer
assertions. Response import now validates complete canonical placeholder sets,
UTF-8, bounded text, finite source targets and literal link labels, and uses the
existing throttled journal warning when rejecting a row. Later valid records
still restore. Local DFT slots remain outside the network protocol.

Terminal rich failures also bypassed the failure map and stayed pending.
Paragraph lookup now returns the recorded failure, clears its pending timestamp,
and permits immediate retry after the provider generation changes. The reader
shows native source spans using its existing bounded retry path. Both response
and terminal-state failures were reproduced by failing tests before repair.

The response fixture exposed locale-sensitive `%c` matching a UTF-8 punctuation
byte in the bundled Lua runtime. These narrative boundaries now test explicit
ASCII control bytes, preserving Chinese punctuation and supplementary characters
while rejecting actual controls and markup. Six fixtures pass against the
repacked scripts; thirteen relevant Node tests and package validation pass.

The safety-repacked candidate uses unchanged binaries and dictionaries. Its
913-file manifest is `78668c53096c90133c34a6c3780b2f11e202cf63def9f04d0750365db24aceda`.
Fresh-state cold verification passed all 50 exact bilingual checks through the
actually loaded DLL, with counters unchanged at `[0,0,652]`. All 330 native words
and 56 links still equal the frozen regression. The unknown badger-brute caption
remained fully English; supported trade, daughter, goblin and yeti prose rendered
Chinese at 49–50 settled graphics FPS. A refreshed coordinate click opened the
correct entity 35. The initial hover-only click is not counted as acceptance.

Normal exit and restoration completed: all 10,839 original save files unchanged,
both unchanged clones archived, player state/cache/overlay restored. Evidence is
in `live-ui-0511-legends-text-trade-safe-20261005`, including `LINK-TARGET.json`
and `restoration-report.json`. The later biography candidate includes these
safety repairs and has been hash-verified and promoted to both distribution
directories; see `OFFLINE-LEGENDS-BIOGRAPHY-20261005.md` for its final manifest.
Original
baseline misses remain frozen. Biographies with unlinked names, unlinked battle
titles, procedural race labels, theft/injury narratives and substantial entity
histories remain gaps. No whole-game 90% coverage, commit, GitHub push or Steam
upload is claimed.
