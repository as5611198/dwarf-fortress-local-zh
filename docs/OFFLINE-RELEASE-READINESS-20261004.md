# Offline release readiness, 2026-10-04

The active release target is at least 90% vanilla content available without AI,
then Steam item 3811313433 and the existing GitHub repository. That target has
**not been established**. No upload has occurred. Version 0.5.11 remains a local
candidate. The live checks below use separately hash-recorded package snapshots,
deploy to two local mod copies, and restore the player's original settings and
caches afterward. The latest promoted snapshot is the Legends commemorative candidate
recorded at the end of this document. Every historical gate retains its own manifest;
earlier save/reload evidence does not automatically apply to the latest snapshot.

Latest civic follow-up: the exact native comma-bearing popular-support and
four-role ruling paragraphs now render offline. Native and fresh Broker passed
386 bilingual checks, and the cold loaded DLL passed the same checks. Entity
35/36 source, word and link records were unchanged; the entity-36 coordinate
link opened correctly and the new sentences rendered in Chinese. All 10,839
protected original files and player state/cache/overlay were restored after
normal exit. Both distributions match manifest
`b48c60bbfebadd716d78b2158db4409731e293ecea071d2ec7243aa730d6712d`.
See `OFFLINE-LEGENDS-CIVIC-20261005.md` for snapshot-specific evidence and limits.
This is regression evidence, not an independent 90% acceptance score.

The festival candidate supersedes that civic snapshot. Native and fresh Broker
passed 460 bilingual checks. The loaded DLL passed the same checks; eight actual
visible festival paragraphs matched reviewed whole outputs, and a coordinate
site link opened native site 39. Original native words/links and all 10,839
protected original files were unchanged; settings/cache/overlay were restored
after normal exit. Both distributions match manifest
`f4c8cbea72d868ba48b8d3a6888cf3fd538dadf5eac3550dd56dbb7577458e96`.
See `OFFLINE-LEGENDS-FESTIVALS-20261005.md`. Commemorative stories and the overall
independent coverage/performance/save-reload gates remain outstanding.

The commemorative candidate supersedes the festival snapshot. Native and fresh
Broker passed 482 exact bilingual checks (390 accepted, 92 intentional rejected);
the loaded DLL passed the same checks with no additional worker submissions.
The actual standalone POSITION ascension story preserved both dates, the figure,
affiliation, title, venue and festival in complete Chinese. Eight festival
paragraphs still matched full reviewed outputs, and the site link opened native
site 39. Closing and reopening the entity tab recaptured the initial page rather
than retaining the later viewport. All 10,839 protected files and player
state/cache/overlay were restored after normal exit. Both distributions match
manifest `9a8176cd32e7a2b90643fedd6d53cfdadd2f381c31b89feb7645f6232ddff38e`.
See the commemorative follow-up in `OFFLINE-LEGENDS-FESTIVALS-20261005.md`.
An additional ceremony-feature story remains a retained development miss.
Independent coverage, large unpaused performance and newest-package fortress
save/reload remain incomplete; no release score or publication is established.

## Diagnostic evidence

`src/validation/build_vanilla_corpus.py` reads installed vanilla raw files as
CP437, preserves interior spaces and long descriptions, selects every supported
field on a line, and hashes all input files. Within each category it selects up
to 120 distinct strings in SHA-256 order. Categories can overlap. No dictionary
lookup is used for selection; these inspected samples are now development data,
not an untouched held-out set. Dynamic placeholder templates are excluded rather
than queried as if they were displayed English.

Two opt-in Rust diagnostics query the built package: a fresh temporary Broker
state with AI and cloud auto-download disabled, and the native `static_lookup`
path with installed dictionaries and rules loaded. Both cover the same 969
category/source pairs per language. Membership is checked with multiplicities;
misses remain in the denominator. Broker provider requests and native worker
submissions were both zero. A returned Chinese string is not proof of semantic
correctness or of correct rendering by an in-game adapter.

| Raw category | Samples per language | Traditional hits | Simplified hits |
|---|---:|---:|---:|
| Combat verbs | 28 | 28 | 28 |
| Creature descriptions | 120 | 120 | 120 |
| Creature/caste terms | 120 | 120 | 120 |
| Item terms | 120 | 114 | 114 |
| Material terms | 120 | 116 | 116 |
| Plant terms | 120 | 117 | 117 |
| Preference fragments | 120 | 92 | 92 |
| Other raw names | 120 | 108 | 108 |
| Literal text-set fragments | 101 | 30 | 30 |
| Total | 969 | 845 (87.20%) | 845 (87.20%) |

Native and Broker return counts match. All returned strings passed the limited
Chinese-without-Latin check. Contextual fragments may translate differently as
part of a complete sentence, and generated UI/personality/history/dialogue is
not represented. These percentages are **not whole-game coverage estimates**.
Removing low-scoring categories or claiming this sample as an independent
post-fix acceptance set would not establish the user's target.

This supersedes the initial 668/969 Traditional and 681/969 Simplified snapshot,
and the intermediate 778/969, 783/969 and 822/969 snapshots. The corpus and denominator
are unchanged. The preceding creature expansion also passed a full raw-field
population diagnostic: 951/951 DESCRIPTION values and 2,569/2,569 creature/caste
labels in each language, through both native static lookup and Broker. All
7,040 language/category/source results match between the two engines. Every
one of the 1,902 bilingual description outputs equals the generated CSV exactly.
Provider requests and native worker submissions remain zero.

The DESCRIPTION inventory includes a few non-creature raw descriptions, such
as noble role instructions. It does not include all generated creature prose,
game UI, history or dialogue. These exhaustive raw-field results therefore
also do not establish whole-game coverage. They are reviewed development data,
not an unseen benchmark. The generated dictionaries are build-time exact rows;
no additional per-frame parsing, I/O, API requests or regex scans are introduced.

The first draft extractor skipped invalid UTF-8 files, collapsed spaces, and
omitted descriptions over 240 characters. Its earlier results and the erroneous
631/720 and 644/720 commentary are invalid for acceptance. The exact-source run
supersedes those preliminary figures.

## Changes and validation

- Removed unfinished runtime journal rotation from the production Broker and
  Lua paths, including its unsafe display retry queue. Staging is test-only;
  the disconnected rotation prototype is retained for later work. Existing
  durable cache, startup compaction, history recovery and bounded readers remain.
- Added all 28 vanilla combat verb forms to local Traditional data. The package
  builder generates Simplified data using the existing conversion pipeline.
- Fixed and tested the diagnostic extractor; added native and Broker actual
  lookup diagnostics and a membership-checked summarizer.
- Broker regression: 87 unit plus 35 integration tests passed; 8 opt-in tests
  skipped in the ordinary run. Both raw diagnostics were then invoked explicitly.
- Lua source fixtures: 26 passed. Python validation/extraction tests: 15 passed.
- Packaged Broker personality regression: 310 bilingual lookups, zero misses and
  zero provider requests. Packaged diamond material/shape semantics passed.
  Latest Node offline-data/language/caste regression: 12 tests passed.
- Fresh release Broker/native build passed. Candidate package validation passed
  for 903 files. Native and Broker were rebuilt after the preference-context
  change; both actual packaged lookup paths and all four opt-in Broker package
  tests passed (the fourth was added and run separately after the other three).
  Packaging is not in-game, save/reload or publish acceptance.
- Added 951 complete exact DESCRIPTION translations per language (279 authored
  whole paragraphs plus bounded sentence/shape composition), and 395 exact raw
  label supplements for missing plurals and female/male castes. Existing reviewed
  terminology retains priority. Unknown clauses still reject the whole paragraph.
- Removed 94 generated-world race IDs from the release source race map; it now
  contains only the 967 creature IDs present in vanilla raws. Removed a private
  deity-name override from the race-map authoring tool. A regression requires all
  shipped race IDs and supplemental labels to belong to the vanilla inventory.
  This prevents these specific world aliases from entering new packages; it is
  not a claim that every historical artifact has received a privacy audit.

Private exact-source corpus, detailed outputs, evidence hashes and build logs
are under the game `_localization-work` directory:
`vanilla-corpus-exact-20261004.json`,
`vanilla-context-20261004-broker.json`,
`vanilla-context-20261004-native.json`, and
`vanilla-context-20261004-summary.json`.
The full raw population evidence is `creatures-population-20261004.json`,
`creatures-complete-native-20261004.json`, and
`creatures-complete-broker-20261004.json`. The current personality regression is
`creatures-complete-personality-20261004.json`.

## Complete preference and dialogue expansion

Added 145 context-specific preference reasons and two context-specific plant
subjects, plus 23 complete vanilla dialogue sentences. A preference's subject
and reason now check their typed dictionary namespace before the generic term
dictionary. Thus `ash for their autumn coloration` means the ash tree, not ash
residue; `chestnut for their chestnuts` distinguishes the tree from its nuts.
`wine` as a plant preference no longer implies that every plant makes grape wine.
These overrides do not change unrelated UI labels or ordinary standalone words.
Unknown clauses continue to fail atomically. The extra runtime work is bounded
exact dictionary lookup, with no new file reads, general regex scans or API calls.

The regression first reproduced the incorrect generic `spots` and `ash` results,
then passed after the context lookup changes. Latest Broker unit run: 88 passed,
4 opt-in tests ignored. Dedicated package semantics passed in both languages
with empty temporary player state and AI/cloud disabled. Node life-data tests
also passed after the final dictionary change.

A new diagnostic constructs complete preference sentences from actual vanilla
NAME/PREFSTRING associations: 1,155 distinct sentences per language. All 2,310
bilingual lookups per engine return Chinese, preserve the name placeholder and
match between native and Broker, with zero provider requests/worker submissions.
This is synthetic development data, not observed player UI or a whole-game
coverage denominator. The standalone raw preference-fragment score intentionally
remains 92/120 because contextual definitions are not installed as global labels.
Unexpanded advice/title/deity fragments likewise remain untranslated globally.

Evidence: `preferences-context-corpus-20261004.json`,
`preferences-context-final-20261004-native.json`,
`preferences-context-final-20261004-broker.json`,
`preferences-context-final-20261004-summary.json`, and
`preference-package-semantics.log`, all under private `_localization-work`.
The current 310-query personality regression is
`vanilla-context-20261004-personality.json`.

No game launch, save deployment, player-cache change or upload occurred during
the preference expansion itself. The following live check took place afterward.

## Live fortress check and observed label repair

Ran 0.5.11 with AI and official downloads disabled, clean player state, no learned
legacy cache, and an isolated copy of an existing fortress. The observed steady
render rate was 49-50 FPS while paused. Brief page-transition screenshots show
lower instantaneous rates; this is not an unpaused simulation benchmark or a
large-population/long-session performance acceptance test.

Saved screenshots cover the title/world/save menus, fortress overview, residents,
unit overview, traits, values, preferences, needs, health status, health
description, equipment, stocks and work details. Traits, values, needs and
equipment visibly translated offline. Values retained cyan/yellow emphasis.
Preferences initially appeared English, then translated locally while retaining
an English generated name; first-frame Chinese is not yet established.

Observed gaps remain: several residents' combined name/profession rows, some
unit overview fields, and most generated health/appearance prose. A standalone
physical-ability sentence resolves locally, but the observed health source
contains multiple paragraphs separated by `[B]`, interior palette changes and
unhandled appearance prose. The current health adapter flattens colors and does
not split that source into supported paragraphs. This finding is a reproduction
and code-path diagnosis, not a completed health-rendering fix.

Added 18 observed fixed labels in `src/data-patches/simple/zh-Hant/offline-ui-labels.csv`,
including stocks labels, save labels and work-details tabs. Both engines return
all 18 expected translations in both languages (72 checked outputs total), with
zero provider requests/native worker submissions. Resolved one Simplified synonym
difference by retaining the established workbook term for Standing orders.
The final 905-file package passed validation and was deployed with manifest-hash
verification to both local copies after game exit. This label patch has packaged
lookup verification, but has not yet received an in-game visual retest.

The game exited normally without saving the test clone. Restored and hash-checked
the original player-state directory and legacy cache. All 10,839 protected save
files are unchanged, with no missing files or additions outside the isolated
clone. The clone was moved outside the active save directory into a private audit
archive. The game and Broker were closed at completion of restoration/deployment.

Private evidence: `_localization-work/live-ui-0511-20261004/` contains screenshots,
page captures, restoration and deployment reports. The save-list capture's page
metadata was corrected after discovering its original world-list label; the
world-list screenshot has no paired source capture. Memory scans include hidden
buffers and must not be counted as visible-screen coverage. Label corpus/results
are `_localization-work/live-ui-labels-20261004-{native,broker,summary}.json` and
`live-ui-labels-corpus-20261004.json`. These observed/fixed samples are development
regressions, not independent coverage acceptance. Legends and adventure still
need current-candidate live coverage testing. No Steam or GitHub upload occurred.

## Health paragraph repair and appearance follow-up

The health adapter now matches each `[B]` paragraph to its native row group
before writing any aliases. Known race/ability paragraphs can translate while
an unsupported appearance paragraph remains original. It preserves semantic
palette changes, blank separators and native source strings. Only copied scalar
rows are cached; native line pointers are not retained across polling. Layout
mismatches and unsupported markup fail without display writes. Source fixtures
cover partial native rebuilds, pending aliases, inherited palettes, narrowing
and widening the box, stable alias reuse and restoration on exit.

Added a separate bounded appearance vocabulary and typed sentence grammar.
Body-specific predicates prevent eye descriptions from accepting hair styles.
The package builder imports existing reviewed color terms and emits Traditional
and Simplified rows. Runtime work uses fixed body inventories and exact map
lookups, not filesystem reads or dictionary-wide pattern scans. Unknown clauses
still reject the appearance paragraph atomically. This is not an exhaustive
inventory of every possible vanilla body/hairstyle combination.

A new clean offline run (`live-ui-0511-health-20261004`, run ID
`c77adac0-2dc6-4bbd-858b-ef14caf277b8`) loaded the isolated fortress clone.
Screenshots and paired source captures show the original miner's entire health
description in Chinese, including the red/green physical-ability contrast and
the ten-sentence appearance paragraph. A second resident's ability paragraph
also rendered Chinese independently of an unsupported appearance paragraph.
Both captured pages reported 50 FPS while paused, with AI and cloud downloads
disabled. This does not establish unpaused or long-session performance.

That second resident exposed missing ear-lobe and eyelash grammar. Added typed
`have`/`has` features, eyelashes, and the observed voice/shape/shaved-hair terms.
These final additions have packaged regression evidence but have not received
another in-game visual retest. The displayed first resident and independent
ability-paragraph behavior were verified before these additions.

Validation after the final addition:

- Nine Rust prose tests, five Node data tests and the three affected Lua fixtures
  passed. The new ear-feature test failed before implementing the grammar.
- The subsequent complete Broker regression passed 90 unit and 35 integration
  tests; ten opt-in tests were skipped by that ordinary invocation. All five
  package-specific opt-in tests were explicitly run as described below.
- Native package diagnostic and all five explicit Broker package tests passed.
  The full observed appearance paragraphs are checked against expected Chinese;
  gender/language variants and unsafe unknown/cross-body clauses are included.
- Nine diagnostic inputs per language produced 18 results per engine; the
  native and Broker outputs agree exactly. Each engine returns ten successful
  bilingual outputs and eight intentional rejections. Worker/API calls are zero.
  These are development regressions, not a 90% coverage sample.
- The final 907-file package passed validation and was copied to both local mod
  installations with every manifest hash verified. Latest manifest SHA-256:
  `eebde5c192c21eee628fa8a780f98bc7fd19004302ce6f1cf0a680d2852b76e3`.
- Removed three save-specific world-name rows from `visual-blocks.csv`; those
  strings are absent from the rebuilt release package. Other publication
  artifacts still require the complete release privacy check.

The game exited normally without saving. All 10,839 protected save files are
unchanged, with no missing files or additions outside the clone. Original player
settings/state and legacy cache were restored and hash-checked. The test clone
was archived outside the active save directory; game and Broker are closed.

The label retest visibly confirmed Dig, None, active/autosave labels and save
counts. World/Timeline prefixes, mood tooltips and the Squad prefix still showed
English despite some exact lookup tests passing. Investigate actual render
fragments/whitespace rather than treating those label tests as rendering proof.
Residents' combined name/profession rows also remain a visible gap.

Existing captured state does not contain the exact render requests for those
prefixes/tooltips, so whitespace is a hypothesis, not a confirmed cause. Next
live run should use the existing bounded `core_trace_enable`/`core_trace_read`
API (512 rows maximum), pair each trace with a screenshot and inspect the exact
strings before altering normalization. Disable tracing again after capture.

Private evidence: `appearance-final-20261004-{native,broker,summary}.json`,
`appearance-corpus-20261004.json` and the new live run's `screens/`, paired page
JSON, `restoration-report.json`, and `final-package-deployment.json`.
No Steam or GitHub upload has occurred. Whole-game 90% remains unproven.

## Exact render fragments and bounded resident professions

The next clean-state audit (`live-ui-0511-labels-20261004`, run ID
`de813130-2217-48fe-8eb1-cd9e95b67cd3`) captured the native renderer's bounded
512-row trace together with screenshots. It confirms that `World: `, `Squad: `,
`Mood: ` and `Long-term mood: ` include a trailing space, and that `Content` is
submitted separately. Added those five exact reviewed entries, preserving source
spaces without global normalization or regex scanning. The existing `Folder: `
entry already rendered correctly; the trace's `local_lookup` enrichment excludes
unreviewed simple entries, so a missing enrichment is not a rendering failure or
a whole-dictionary miss. Trace capture is disabled immediately after collection.

Both packaged engines agree on all twelve bilingual outputs for six observed
fragments (including the existing folder label). Native worker submissions and
Broker API requests are zero. The Broker validator strips target-edge whitespace;
the final labels do not rely on target padding. Existing Simplified folder
terminology is retained. Screenshots verify Chinese mood/squad labels after the
data update, and the world prefix after a full game restart. The combined
`Timeline: <custom name>` line remains an observed gap; no user timeline literal
has been added to release dictionaries.

The final ear-lobe/eyelash appearance expansion was also visually verified on the
second resident: the entire description is Chinese with the original green
ability emphasis and paragraph breaks. Paired capture reports 49 FPS while
paused; screenshot reports 50. This closes the earlier visual-retest gap for that
specific paragraph, not every possible appearance combination.

The residents list sends combined native-name/profession strings; the existing
selected-unit header adapter did not run on this page. Added a separate temporary
binding map for the visible Residents tab. The Lua adapter indexes the native
scroll window directly, checks ancestor/row visibility and visits at most 32
units (64 native/English name variants). It never enumerates all units, retains
native pointers across polls, dispatches name translations, or changes save
fields. Custom profession strings are excluded and player nicknames remain
literal. Already-known canonical name translations may be reused. The map is
replaced on scrolling, cleared on exit/error and expires after five seconds;
language/world scoping and the selected-header eight-row limit remain enforced.

The fixture failed before implementation on a visible list with no open unit
sheet. It now verifies a 10,000-row backing list without scanning hidden rows,
scroll replacement, empty/hidden viewports, literal multibyte nicknames, custom
profession exclusion, fixed caps and error cleanup. Four affected Lua fixtures
passed. All 75 ordinary native tests passed; ten opt-in tests were excluded by
that invocation. The native packaged fragment diagnostic and all five Broker
package tests were explicitly run and passed separately. An initial full-test
command from the repository root selected stable Rust and failed on retour's
nightly features; rerunning from the native crate directory used the configured
toolchain and passed (`resident-native-regression-final-20261004.log`).

The 907-file package was rebuilt, validated and hash-verified at both installed
mod locations while the game and Broker were closed. Manifest SHA-256:
`19d565a439d0deb3e990873be62d6609c7080db525f1189967164f5ae37fb8fd`.
After restarting and loading the isolated clone, screenshots show all seven
visible residents with localized professions while preserving their colors.
The steady screenshot reports 50 FPS (paired capture 49); the opening transition
reports 38 FPS. This is a seven-resident paused test, not a large-population or
long-session performance benchmark. No first-render latency measurement was made.

Evidence lives under the private audit directory: `02-residents-trace.json`,
`03-unit-overview-trace.json`, `resident-widget-tree.txt`,
`resident-package-deployment.json`, and paired screenshots/page captures numbered
04 through 07. Packaged fragment evidence is
`live-ui-fragments-final-20261004-{native,broker}.json` under `_localization-work`.
These fixed reproduction samples are development evidence, not independent 90%
coverage acceptance. No Steam or GitHub publication has occurred.

This label/resident audit is now closed: the game exited normally without
saving and both game and Broker processes stopped. The restoration script
hash-verified the original player settings/state and legacy cache. All 10,839
protected save files are unchanged, with no missing files or additions outside
the clone. The clone was archived outside the active save tree; the audit's
`expected.json` now says `restored`. See its private `restoration-report.json`.

## Legends and adventure audit: release threshold remains unverified

The clean-state modes audit (`live-ui-0511-modes-20261004`, run ID
`5ec7651b-3bd0-4845-a9bd-9a83e473cc00`) used the unchanged 907-file candidate
above, with AI, official downloads and shared contributions disabled. Source
captures, bounded render traces and screenshots are private audit artifacts.

The first Legends observation inherited a locally disabled narrative overlay.
The shipped overlay defaults to enabled. After backing up the user's overlay
configuration and temporarily enabling that overlay, supported settlement,
artifact creation, offering, heirloom, loss and finding sentences rendered in
Chinese. The initial disabled-overlay result is not a fresh-install failure.
Other overlay preferences were retained, so this audit is not a complete test
of fresh-install defaults.

Visible gaps remain in common active-voice history events: becoming an enemy,
attacking, fighting and striking down another figure. Seasonal dates already
have parser support; the event clauses need work. Artifact decorations and
some naming/symbol-of-office events remain English. Linked figure labels can
retain descriptors such as dwarf, goblin or necromancer alongside proper names;
these descriptors must not be excluded as untranslated names. Some Legends
navigation instructions and site-type labels also remain English.

Adventure testing reached difficulty and race selection only. The four visible
race labels rendered Chinese, but the character-creation heading, selection
actions, most destiny explanations and difficulty labels remained English.
Exploration, conversation, combat and journal were not exercised. Steady
screenshots showed 50 FPS, which is not an unpaused simulation benchmark.

No whole-game coverage percentage is inferred from these partial observations.
Offscreen paragraphs in captures are not rendered evidence. The candidate has
real observed gaps as well as incomplete acceptance sampling; the raw corpus
and synthetic regression percentages cannot establish the requested 90% gate.
No Steam or GitHub publication occurred.

### 2026-10-05 combat controls and complete tooltips (audit restored)

The isolated combat audit used a cold-loaded saved adventurer with AI, official
downloads and shared contributions disabled, and empty audit translation state.
Inventory and combat preference pages exposed missing complete tutorials and
tooltips. A bounded adapter now joins the actual native hover-instruction rows,
looks up the complete source, and binds its translated layout to the existing
native rows. It rejects unsupported markup, mixed source text, overflow and
layout changes atomically. It retains English sources, original palettes and
native hotkeys. Script lookup is cached; no new per-frame I/O is introduced.

Nine complete combat preference tooltips and the main Strike tooltip were
visually checked. A subsequent UTF-8 wrapping fix keeps closing punctuation
with preceding text and prevents commas from beginning the next line. Screens
50-52 confirm the sentence/comma correction and zero bindings after leaving the
preference panel. The relevant source fixtures passed; this is observed
regression evidence, not independent coverage acceptance.

Added 25 reviewed fixed combat entries: target/aim headings, the observed
`Dodge (Adequate)` label, lowercase head/neck, six difficulty labels, four
contact-quality descriptions, six complete attack-modifier explanations and
independently drawn status components. No generated actor or material/weapon
combination is hardcoded into the fixed dictionary. The 50 bilingual outputs
per engine went from 48 missing outputs to zero misses and zero semantic or
Traditional expected-value mismatches. Both packaged lookup diagnostics ran;
the native diagnostic and all five Broker package tests passed. Native worker
submissions and Broker API requests were zero. Two exact engine differences
remain: native preserves the leading space in ` strike`, while Broker trims
outer request whitespace. These are explicitly retained boundary differences.

The final 912-file package passed the workshop validator and was hash-verified
at both local mod targets while game and Broker were stopped. Manifest SHA-256:
`f0d2eb554397e6b6c8f2153c72abe2a85efd03e38e7c7834ff462a4465b9177c`.
That exact package then received a cold restart and loaded the isolated clone.
Screens 67-72 show the target/aim headings, Dodge label, head/neck, six difficulty
labels, contact descriptions and all six complete modifier explanations in
Chinese. Native status colors and green shortcut letters remain; inspected
text fits its panel. Slow and the independently drawn strike status were
checked, but the final green Easier-plus-strike composition was not revisited.
Settled screenshots showed 50 FPS; paired final captures showed 49-50. This
does not establish unpaused large-world performance or first-frame timing.

Retained misses include actor headers, conflict confirmation, movement prose,
the `Attack <body part>:` heading, action/weapon and action/body combinations,
and the no-save exit warning. The complete exit-warning dictionary lookup
already succeeds; its visible dialog has zero `options.text` rows. Its native
source owner must be located before adding a safe adapter. No actual attack was
issued, so battle results and injury/status acceptance remain untested.

The game exited normally without resaving the clone. Player settings/state,
legacy cache and overlay configuration were hash-restored. All 10,839 protected
save files and the source archive are unchanged, with no missing files or added
files outside the clone. The clone is archived, the descriptor is `restored`,
and game and Broker are closed. Private evidence:
`live-ui-0511-combat-20261005/combat-live-summary.json`, its 148 hashed artifacts,
deployment/restoration reports, and `combat-menu-labels-summary-20261005.json`.
The summary records misnamed transitional captures so they cannot be mistaken
for successful page checks. Overall 90% remains unestablished; no upload occurred.

### 2026-10-05 appearance and tutorial follow-up (audit restored)

The isolated expansion audit reproduced a health-layout bug: consecutive `[B]`
markers created an empty paragraph, causing the adapter to reject the subsequent
complete appearance description. Empty prose chunks now leave their native blank
rows in place and allow each real paragraph to translate. Unsupported markup and
unproven layouts still retain the original display. A width-53 regression verified
two separator rows, bright palette 71, stable aliases and restoration of sources.

Added the reviewed rigid-anger mannerism and six overview labels, plus the complete
recenter/zoom tutorial prose and its labels. Broker validation now treats the exact
standalone `[Viewed]` badge as prose inside an intact bracket wrapper. Unknown
brackets, embedded format tokens and incomplete badge translations remain rejected.

The 910-file follow-up candidate had manifest SHA-256
`5fbcb15c8d5fe7d5ed2800d5b233bd34e9f47001d882b87f1fd22dc1b003c8eb`.
Recorded validation: 131 Broker and 78 native ordinary tests passed; ten native
opt-ins were excluded. All five Broker package tests and the native diagnostic
were then invoked explicitly. The 233-source bilingual regression returned all
466 outputs per engine, with exact engine parity and Traditional expected values,
zero worker submissions and zero API requests. This is development data.

Live screens 20-24 confirmed the six overview labels, complete female appearance,
rigid-anger sentence, green `[已閱]` badge and the first camera-pan tutorial, with
the original palettes and blank separators. Observed frame rates were 49-50 FPS.
The health description was initially mostly English, then became Chinese at the
next observation; instantaneous first-display behavior is not claimed. Later camera
recenter/zoom tutorial stages were not visually accepted: the native pan prerequisite
was not completed through the available UI automation. Their dictionary regressions
do not substitute for live checks. The generated conversation replies, actor headers,
mixed keyword hints and journal presence titles remain retained misses.

The game exited normally without resaving the clone. Settings/state, legacy cache
and overlay configuration were hash-restored. All 10,839 protected save files and
the source archive are unchanged. Private evidence:
`live-ui-0511-expansion-20261005/followup-live-summary.json`, its linked screenshots,
`restoration-report.json` and `adventure-followup-final-20261005-summary.json`.

### 2026-10-05 journal adapter (live regression verified, audit restored)

Event titles have two observed native drawing paths: a wrapped `p_list_box`, or
the single `p_list_name` field. A new adapter resolves the figure/site from actual
beast/group/harassment rumor IDs and requires the complete summary to match those identities before
binding either path. It translates only the reviewed placeholder template and
preserves name literals; no journal, search, map, link, world or save strings are
rewritten. Unsupported rumor types, missing identities, unexpected wraps and empty
native rows retain the original output. Work is limited to 64 entries around the
current viewport and 256 bindings per twenty-frame poll. The existing unit adapter
remains the sole native binding publisher and clears bindings when leaving the page.

Display width validation now counts ASCII as one cell and other Unicode scalars as
two, while rejecting control characters. This allows verified mixed name/prose rows
to fit without weakening ordinary untranslated-English rejection. Regression tests
cover both native paths, mismatched identities, unknown union variants, supplementary
Unicode, empty rows, a 600-entry scrolled journal, script lookup caching and cleanup.
Fresh native ordinary tests: 79 passed, ten opt-ins excluded. Four affected Lua source
fixtures passed. The native package diagnostic and all five Broker package opt-ins
passed on 234 bilingual sources (468 outputs per engine), with zero misses or engine
mismatches and no model requests. These remain regressions, not acceptance samples.

The isolated saved adventurer was reloaded with AI, official downloads and shared
contributions disabled. Actual presence and harassment titles rendered Chinese
while retaining the original actor/site literals and native colors. Pinning and
reordering the harassment entry kept the translation attached to that entry.
Map/recenter behavior remains unverified.

The adapter also handles the People, Sites, Entities and Bestiary lists. It joins
complete consecutive native paragraph rows, preserves blank separators and
splits the local translation at UTF-8 scalar boundaries into existing rows.
Unsupported markup, partial English, overflow and unknown sex suffixes retain
native output. Per box, work is bounded to 128 native rows and 16 rows per paragraph;
the existing 64-entry/256-binding limits remain. No source/save strings are rewritten.

Live Bestiary captures cover the first page, scroll 329 and scroll 659 (entries
660-671 of 671). Descriptions and encounter prose rendered Chinese. The tail
exposed two untranslated short titles: Wren and Wiwaxia. Available title width
now derives conservatively from existing body rows, reserving both counter
numbers and the slash/separation instead of using English name byte length.
The short CP437 Wren fixture failed before this fix and passed afterward. A
Lua-only deployment/reload outside the journal then visibly confirmed both
Chinese names, sex glyphs, native palette and red counters on the final page.
The final capture preserves their original English source strings and translated
bindings. Leaving the journal returned the native binding count to zero.

Observed People birth/encounter prose, Lair/Dark Pits site labels and Dwarven/Elven
entity labels also rendered Chinese. The artifact list was empty and establishes
no artifact-content acceptance. Retained misses include generated lord/owner/capital
clauses, species habitat clauses and the bottom pin/filter/line hints. Captures can
include offscreen rows; those are not visible acceptance units.

Final validation: five affected Lua fixtures passed. The preceding Bestiary package
passed the native diagnostic and all five Broker opt-ins on 514 bilingual sources
(1,028 outputs per engine), with zero misses/errors/engine differences, zero
Traditional expected-value mismatches, zero native worker submissions and zero
Broker API requests. Known unsupported habitat prose was explicitly retained
outside that regression corpus. These are development regressions, not independent
coverage evidence. All non-Lua files stayed hash-identical for the title follow-up.

The final 911-file package passed the workshop validator and matches both local
mod targets. Final manifest SHA-256:
`d5bf48cfd50b4bd8794b53bab78b91a3ed674ef33971a03959568fe7e6a62706`.
The cold restart used manifest
`f47f3bc634852b48196181aa565fd53d5dadf07171ec7f7ff0d98a4d085baf6e`;
the final title edit received Lua-only live reload, not a final-package cold restart.
Steady screenshots showed 49-51 FPS, generally 50. No first-frame Chinese,
unpaused large-world performance or exhaustive list coverage is established.

Native tracing was disabled and the game exited normally without resaving the
clone. Player settings/state, legacy cache and overlay settings were hash-restored.
All 10,839 protected save files and the source archive are unchanged, with no
missing files or additions outside the clone. The clone is archived and the audit
descriptor is `restored`. Private evidence:
`live-ui-0511-journal-20261005/journal-live-summary.json`, its 110 hashed screenshot/
source/trace files, deployment records and `restoration-report.json`.
Overall 90% coverage remains unestablished; no publication occurred.

## Active history and adventure setup follow-up

The subsequent isolated audit (`live-ui-0511-events-20261004`) used AI,
official downloads and shared contributions disabled. It temporarily enabled
the shipped narrative overlay while preserving the player's backed-up settings.

Added 11 complete history patterns covering enemy, attack, fight, kill, rout,
confrontation, devouring, cave and symbol-of-office statements. Patterns preserve
link roles and reject unsupported trailing clauses atomically. Added 28 reviewed
fixed UI entries, including four whole adventure destiny/difficulty explanations.
The adventure setup adapter joins bounded native rows before local lookup and
registers temporary source-checked display bindings; it does not modify source
strings or save fields. Bindings clear when leaving the supported page or on error.

Recorded regression results: 91 Broker unit tests and 35 integration tests passed;
10 opt-in tests were excluded from that ordinary invocation. The packaged
diagnostic subsequently ran the native lookup diagnostic and all five Broker
package tests. Its 562 outputs per engine had zero engine mismatches, zero native
worker submissions and zero Broker API requests. The new adventure setup Lua
fixture and four affected display fixtures passed. These are development
regressions, not whole-game coverage measurements.

The latest 907-file 0.5.11 package was deployed and hash-verified at both local
mod locations while the game and Broker were closed. Manifest SHA-256:
`e1abbd721fcedb203a1a84b6ec6f048a20deede0789b50fdc91ecbbf7e92fb56`.
Live screenshots show the new supported history events in Chinese with colored
links retained; clicking a translated attack's link opened the correct figure.
All four adventure destiny/difficulty explanation boxes rendered Chinese,
including the red warning. Native bindings cleared on advancing to race selection.
Observed steady screenshots showed 50 FPS; this is not a long-session or unpaused
simulation benchmark.

Remaining visible gaps include history journeys, military commands, festivals,
theft/injury prose and adventure civilization/background text. A navigation
`Back` was translated as the anatomical term; its fix must be contextual rather
than changing the global anatomy translation. Adventure exploration, conversation,
combat and journal remain untested. Neither 90% overall coverage nor immediate
Chinese on every first display is established. No Steam/GitHub upload occurred.

This audit is now closed. The final background screenshot/source/trace are saved,
native tracing was disabled, and the game exited normally without saving an
adventurer. After both processes exited, restoration hash-verified player state,
legacy cache and overlay settings. All 10,839 protected save files are unchanged,
with no missing files or additions outside the clone. The clone is archived and
the audit descriptor says `restored`. Private evidence includes pages 01-08,
`adventure-package-deployment.json` and `restoration-report.json` in the audit
directory, plus `adventure-setup-final-20261004-summary.json` in `_localization-work`.

## Release work still required

### 2026-10-05 candidate follow-up (live acceptance in progress)

Added bounded, screen-specific adventure navigation and species/sex labels;
verified-name background templates; independent appearance/personality/culture
paragraph adapters; reviewed creation labels and observed appearance clauses.
Background identities are resolved from the selected site's actual assignments,
not from arbitrary English captures. Native source strings and save fields remain
unchanged. Paragraph bindings preserve native colors and blank separators.

The packaged diagnostic exposed two additional issues: a literal `100 pts` row
did not cover changed points, and Broker community dictionaries could overwrite
reviewed translations (observed on Simplified `Excitement`). Points now use the
existing explicit `{{count}}` template; Broker CSV merge priority now matches
the native reviewed-entry policy. The new Broker regression failed with the old
community translation before the fix and passed afterward. Later reviewed
corrections and ordinary unreviewed additions are also tested.

Current validation: six affected Lua fixtures passed; 92 Broker unit tests and
35 integration tests passed (ten opt-in tests excluded from that ordinary run).
The packaged native numeric test passed, and the native corpus diagnostic plus
all five Broker package tests were then explicitly executed. Across 115 sources
in two languages, 230 outputs per engine have zero misses, zero engine mismatches,
zero Traditional expected-value mismatches, zero native worker submissions and
zero Broker API requests. These are development regressions, not coverage data.

The rebuilt 908-file package passed the workshop validator and was hash-verified
at both local mod locations with game and Broker stopped. Manifest SHA-256:
`da459ad97d41e12602e00cb8008d764d48fbf10697bf448bcb46eb8da947c5c0`.
The isolated audit's earlier state/cache were archived before this restart;
AI, cloud downloads and contributions remain disabled. Player originals remain
backed up pending audit restoration. See private
`adventure-background-final-20261005-summary.json`, regression logs, and
`live-ui-0511-adventure-20261004/adventure-final-package-deployment.json`.

The acceptance plan now explicitly applies the user's 90% target to the declared
overall equal-mode/equal-category benchmark, not separately to each category.
This clarification precedes computation of the overall score. All categories and
misses remain reportable. No Steam/GitHub publication has occurred.

1. Expand contextual preferences and adventure dialogue, testing complete
   displayed strings as well as fragments. The present creature raw inventory
   is covered, but dynamic combinations and actual rendering still need testing.
2. Collect independent, source-preserving in-game samples across fortress,
   Legends and adventure with a declared weighting/denominator; retain misses
   and verify meanings, palette, links and cold first-display behavior.
3. Run current-candidate loaded-save/performance and save-integrity acceptance.
4. Only after the agreed coverage gate passes, finalize version/changelog,
   manifests/archives and publish Steam and GitHub files. Preserve player data
   and the user's GitHub cover/description exclusion.

### 2026-10-05 adventure gameplay follow-up (audit restored)

The verified-name display bridge was exercised in game with both hearthperson
and miner backgrounds. Chinese surrounding prose rendered with original leader
and site names intact; source background strings remained English. This was the
908-file candidate with manifest
`22dee75d50951d55b127955d0e51d9679bfe123004bb7172a0633b313804a591`.
Screens 16-17 retain the evidence. An independently generated female character
still exposed an untranslated appearance paragraph and five missing need labels.

Actual adventure gameplay was then sampled (screens/traces 21-33). The intro,
camera/movement/status tutorials, dialogue choices and journal exposed many
missing fixed strings. Generated greetings, actor headers, journal dates and
event summaries also remained English. Help prose and dialogue keyword hints
are drawn in fragments; global word substitutions are not valid complete-text
translation evidence. The existing keyword hints can mix Chinese and English.

Added 85 reviewed fixed entries in
`src/data-patches/simple/zh-Hant/offline-adventure-ui.csv`; packaging generates
the Simplified counterpart. These cover observed tutorial paragraphs, dialogue
choices, journal headings and missing creation/need labels. Source whitespace,
paragraph markers, key references and color markers are preserved. No generated
world names or arbitrary word fragments were added as fixed translations.

Before packaging the additions, the 85-source/two-language corpus had 136 missing
outputs out of 170 in each engine. After packaging, all 170 outputs per engine
were present, Traditional targets matched exactly, and native/Broker outputs
matched, with zero worker submissions or API requests. The packaged native
diagnostic and all five Broker package tests passed. Workshop validation passed
for 910 files. Manifest SHA-256:
`d8d7454b804b2e004ee5f289a576e6cdd08f64c3a5bfdee88f91fec3d2b1c5ee`.
Both local mod locations were hash-verified while game and Broker were closed.
Private regression artifacts: `adventure-ui-corpus-20261005.json`,
`adventure-ui-before-20261005-{native,broker}.json`,
`adventure-ui-after-20261005-{native,broker,summary}.json` in `_localization-work`.
This is a regression corpus, not an independent coverage denominator.

Ramul Tiskonli was saved only to the isolated adventure clone and successfully
reloaded after restarting the game with empty audit translation state and AI,
cloud downloads and contributions disabled. Screens 34-38 show Chinese help
headings, the camera introduction, complete conversation popup and journal popup,
tabs and common-knowledge text. Text and paragraph breaks fit the inspected
panels. Settled screenshots showed about 49-50 FPS (one at 51); the initial load
transition briefly displayed 1 FPS. No large-world/unpaused or first-frame timing
claim follows from this. All dialogue choices were not visually rechecked on
this package, and all 85 entries are not claimed as visually accepted.

Independent retained misses include later camera tutorial stages, additional
popup headings/tooltips, journal date/event prose, generated dialogue replies
and the female appearance paragraph. Combat/status and the remaining acceptance
categories still need representative samples. No overall 90% score is established.

The game exited normally after the reload inspection without resaving the clone.
Player settings/state, legacy cache and overlay settings were restored with hash
verification. All 10,839 original save files are unchanged, with no missing files
or additions outside the clone. The saved test adventurer is preserved in the
audit archive and the audit descriptor is `restored`. See
`live-ui-0511-adventure-20261004/adventure-ui-live-summary.json`,
`adventure-ui-label-package-deployment.json` and `restoration-report.json`.
No Steam or GitHub publication occurred.

### 2026-10-05 complete combat compositions (audit restored)

Added a shared bounded combat grammar in `broker-rust/src/offline_combat.rs`.
It composes complete weapon/action and unarmed/body labels from local dictionary
terms, and translates sixteen explicit human body-target headings. Unknown
components, malformed action relationships, controls, markup and partly English
dictionary targets fall back atomically. Sources are limited to 256 ASCII bytes
and at most three slash components. Native static lookup returns supported
labels on the first hook without submitting a translation worker.

The red/green tests and ordinary unit suites passed: 101 Broker and 80 native
unit tests, with the existing opt-ins excluded from those ordinary counts.
Packaged diagnostics tested 28 complete sources, producing 56 bilingual outputs
per engine with zero misses, exact engine differences, Traditional expected
mismatches, native worker submissions or Broker API requests. Five existing
Broker package tests passed; the new combat package test passed separately after
correcting its fixture to the established glossary (scimitar: 短彎刀, shield:
尖盾, war hammer: 戰錘). Production glossary terms were preserved.

The 912-file package passed workshop validation and was hash-verified at both
local mod locations while game and Broker were stopped. Manifest SHA-256:
`3acfed8764f0d0001ca04298e4451eae90d36f051a25a9e58502a02432173247`.
On a cold start with AI, cloud download and contributions disabled, screens 04-05
show the right-hand target heading, five complete weapon labels, left/right hand
punches and left/right foot kicks in Chinese. Purple actions, green difficulty
and u-z hotkeys, yellow Slow and six complete modifier descriptions retain their
palette and fit the panel. The separately drawn Easier and leading-space strike
components were also visually verified on this package. These are regressions,
not independent coverage samples.

The adventurer was saved only to
`region2-offline-combat-composition-20261005`; a post-save hash check found changes
only in that clone's `world.sav` and two DFHack state files. The same package was
cold restarted and the saved clone reloaded successfully (screens 09-12). Settled
screenshots showed 50 FPS and reload metadata recorded 49 FPS. A reload transition
showed 5 FPS; this is not a first-frame or unpaused large-population benchmark.
No actual attack was issued, and actual battle outcomes/injury status and other
Dodge skill grades remain unverified.

After normal exit without resaving, player state/settings, legacy cache and
overlay settings were restored and hash-checked. All 10,839 protected original
save files and the source archive remain unchanged, with no missing files or
additions outside the clone. The saved clone is archived and the descriptor is
`restored`. Evidence: private
`live-ui-0511-combat-composition-20261005/combat-composition-live-summary.json`,
`saved-clone-check.json`, `restoration-report.json` and hashed screenshots/traces.
Screen 03 and its JSON describe different movement states and are metadata-only
evidence, not a simultaneous source/display pair.

Retained gaps include generated actor headers, conflict sentences, fragmented
movement status, the native unsaved-progress warning, timeline-folder selection
sentences, generated conversations and remaining Legends history. The independent
three-mode acceptance denominator and overall 90% coverage are still incomplete.
No Steam or GitHub publication occurred.

### 2026-10-05 scoped movement and Dodge grades (audit restored)

Native adventure drawing splits `Moving east` into independent `Moving`, space
and `east` fields. Added `translator/dungeon_labels.rs` and called its contextual
lookup from both `translate()` and `known()` before cache/worker dispatch. It
accepts only the observed `::t::dungeonmode/Default` context, two Chinese language
tags, `Moving` and eight exact direction fields. Different screens, prose, names,
controls, markup, case changes and extra whitespace fall back unchanged. These
contextual translations are not added to a global or persistent dictionary.
The path introduces no I/O, regular expressions or game-data writes.

Added fifteen reviewed complete Dodge skill labels to `offline-adventure-ui.csv`,
alongside the existing `Dodge (Adequate)` entry. Packaged lookup diagnostics
verified sixteen complete sources and 32 bilingual outputs per engine with zero
misses, engine differences, expected-target differences, native workers or Broker
API requests. Grade wording follows the shipped skill glossary. These are lookup
regressions; this run did not visually inspect all grades or establish support
for `Legendary +n` variants.

The contextual red/green tests passed, and the final native ordinary suite passed
82 tests with zero failures (ten opt-in tests excluded). The fresh release DLL
hash matches the packaged DLL. Workshop validation passed for 912 files, and both
local mod locations were verified against every manifest file after restoration.
Current manifest SHA-256:
`ea5024d510e7d82299dbfc330e29af296687fb9323879a27673ce85bb37e0ac8`.

This package cold-loaded a copy of the previously saved adventurer with AI, cloud
download and shared contributions disabled. Screens 04-05 show `移動中` and
`東方` at their native drawing positions. The no-popup screenshot and capture
both record 50 FPS. Only east was visually accepted; the other seven directions
have unit-test evidence. This is not a long-duration, first-frame or unpaused
large-population performance result. The trace helper's `local_lookup` lacks
viewscreen context, so a nil result for these fields does not test the contextual
render hook. The screenshots establish their inspected display.

No movement, attack or save was performed in this run. The current manifest has
cold-load evidence only; the complete clone save/reload gate recorded above
belongs to the earlier `3acfed...` manifest. After returning to the title and
normal exit, player state/settings, legacy cache and overlay settings were
restored and hash-verified. All 10,839 protected original save files and the source
archive remain unchanged, with no missing files or additions outside the clone.
The test clone is archived and the descriptor is `restored`. Private evidence:
`live-ui-0511-movement-20261005/movement-live-summary.json` (26 hashed artifacts),
`restoration-report.json`, `movement-deployment-20261005.json`, the Dodge packaged
diagnostics and final native/package logs.

Remaining gaps include generated actor headers and conflict sentences, the native
unsaved-progress warning, timeline selection sentences, generated conversations,
Legends history, actual combat outcomes/injury status and representative coverage
sampling. These regressions are not the independent acceptance denominator.
Overall 90% offline coverage is still unestablished. No Steam or GitHub publication
occurred.

### 2026-10-05 observed actor-header follow-up (audit restored)

Extended the same bounded native adventure context to the two complete observed
actor-header formats: `The human mason {First} {Surname}` and
`The human planter {First} {Surname}`. Role terms come from installed local
dictionary/finite rules, while the name remains literal. Sources are limited to
512 bytes and exactly two capitalized ASCII name words. Unknown roles/species,
other name formats, controls, markup and unsafe or partly English dictionary
targets fall back atomically. This deliberately does not claim general actor
header support or translate arbitrary prose by word substitution. There is no
new I/O, regex, persistent cache or game-data mutation in the render path.

The expected failure was recorded before implementation; the final native suite
passed 84 ordinary tests with zero failures (eleven opt-ins excluded). The new
packaged contextual test passed for three complete sources and six bilingual
outputs, including an independent name pair. It also verifies that these
contextual meanings do not enter static lookup. Its initial Simplified Planter
expectation was corrected to the shipped community glossary's `种植者`;
production terminology was preserved. Fresh release build and 912-file workshop
validation passed. Both local mod copies were hash-verified against the manifest.
Latest manifest SHA-256:
`903d403c1ed94723549545ec0e43f51c491ba2251d828a2382494ee4ae1791ba`.

On a cold start with empty audit cache and AI/cloud download/contributions
disabled, the saved adventurer clone loaded successfully. Screen 07 and its
22-row native source trace show `人類石匠 Inspuz Uromarad` and
`人類播種者 Itlud Gomnifih`, retaining literal names, green a/b hotkeys and the
Chinese movement fields. The stable screenshot shows 50 FPS and its metadata
records 49 FPS; inspected screenshots were 49-50 FPS. This is page-level
regression evidence, not first-frame, long-duration or large-population unpaused
performance acceptance. Contextless trace `local_lookup` cannot assess the
contextual translation; the inspected native display establishes the result.
Injected A/Escape keys produced no observed transitions in this session; toolbar
actions used mouse controls. Keyboard shortcut acceptance is not established by
the visible hotkey labels or these mouse interactions.

While locating controls, weapons were accidentally sheathed and a submissive
posture was selected in the clone. These actions and their untranslated complete
report sentences remain in the private evidence. No attack or save was issued.
The clone exited without saving, followed by normal game exit. Hash comparison
shows the entire archived clone, including `world.sav`, unchanged from its source.
All 10,839 protected original save files remain unchanged, with no missing files
or additions outside the clone. Player state/settings, legacy cache and overlay
settings were restored and verified; the descriptor is `restored`.

Evidence: private `live-ui-0511-actor-headers-20261005/actor-headers-live-summary.json`
(24 hashed artifacts), restoration/deployment reports and red/green, packaged,
build and package logs. Screen 06 JSON was captured after its popup closed; use
screen 07 for the inspected stable page. The latest manifest has cold-load
evidence only, not a complete save/reload gate. Other actor formats, generated
conflict/conversation/report sentences, Legends history and the independent
coverage denominator remain incomplete. Overall 90% is still unestablished.
No Steam or GitHub publication occurred.

### 2026-10-05 fortress hints, stocks, labor and kitchen gates

Four separately restored sessions retain their original package manifests.
They are regression evidence, not independent coverage samples:

| Gate | Manifest prefix | Evidence |
|---|---|---|
| Fortress hints and save/reload | `bdfc3872` | 71 reviewed sources, 284 bilingual Native/Broker exact checks, zero worker/API submissions; construction, workshops, labor and announcements inspected |
| Stock counts | `7afacb45` | 21 sources, 84 exact checks, six distinct drink count rows and three category labels visually accepted |
| Native labor professions | `721a4feb` | Five complete resident/profession rows; colors/icons retained on initial view, return from kitchen and cold reload |
| Kitchen labels | `d200647e` | Nine complete labels, 36 packaged exact checks, 18 actual release-DLL bilingual queries, stable kitchen screenshot/trace |

The first gate and labor gate each saved and cold-reloaded an isolated fortress.
The complete captured structures match for seven citizens' names, nicknames,
professions and custom professions, plus 202 squads across the entire world.
These are not 202 player squads and do not establish binary save equivalence.
Kitchen was not saved; its manifest differs from the labor gate only in the two
language copies of `offline-ui-labels.csv`, as recorded in `manifest-difference.json`.

The stock fix shares the existing bounded stack-count splitter with the Native
lookup path. `EquipmentTranslator` receives the count-stripped item source before
lookup and restores the numeric suffix and item markers. Malformed counts reject
atomically. Labor uses the existing bounded native-row adapter for up to 32
visible rows; it handles scrolling, hidden parents, custom professions, missing
or rebuilt lists and cleanup after errors. No world identity or profession field
is overwritten. The ordinary suites at the labor snapshot passed 90 Native and
102 Broker tests, with 11 and 5 opt-in tests excluded respectively.

Kitchen uses nine exact reviewed rows, including a leading-space filter label,
capitalized seed/spawn names and the turtle's female symbol. No global lowercase
fallback or additional render parsing was added. The two language CSVs are the
only data changes between labor and kitchen. Both snapshots contain 913 files.

Stable paused seven-citizen labor captures record 49-50 graphics FPS. Kitchen
records 49 FPS in the trace and 50 FPS in the screenshot. These do not establish
first-visible-frame latency, long-duration behavior or unpaused performance in a
large population. All four sessions restored and hash-verified 10,839 protected
original save files, player state/settings, legacy cache and overlay settings.

Private summaries: `live-ui-0511-release-gate-20261005/release-gate-live-summary.json`,
`live-ui-0511-stock-followup-20261005/stock-live-summary.json`,
`live-ui-0511-labor-final-20261005/labor-live-summary.json` and
`live-ui-0511-kitchen-final-20261005/kitchen-live-summary.json`. Earlier artifacts
13/14 and `stocks-drinks-render.json` precede selecting Drinks; the accepted
drink evidence is screenshot 16 with `stocks-drinks-selected-render.json`.

The kitchen session also inspected the middle resident. It retained misses in
overview summaries, one current thought, poetry preferences, an English-form
deity prayer and three clauses that blocked the full appearance paragraph.
Some ordinary need rows first appeared in English and subsequently became
Chinese with AI disabled. Stable output must not be reported as first-frame
translation. DFHack labor hints remain outside the vanilla benchmark.

### 2026-10-05 resident follow-up (live verification completed)

Candidate manifest `c49735084471823be698f97a00db9b7c0183b2a7a485d486d7fd3b2be71dfef1`
contains 913 files. Native DLL SHA-256 is
`1e1bbaed22239a9e8eaf685be0a9e7b5cd6dd4e1b47409f7f962450cace20d97`;
Broker EXE SHA-256 is
`5ef6e83892f9b7684fed0fac68d18f7baa1ffe2c06ab3e66c6fcc86911864fbd`.

The preference masker and bounded parser now support `the words of` alongside
music/dance forms. Only form names supplied by the unit's actual preferences
receive typed placeholders; arbitrary names remain rejected. Prayer needs bind
both native and English spellings from the same referenced historical figure.
The input cap permits two spellings for at most 64 references, retaining bounded
work. This fixes the observed `Pointycrest`/native-surname mismatch without adding
world-specific identities to shipped data or writing save fields.

Added five reviewed overview summaries, one quoted current thought, warthog hoof
and the blue peafowl preference reason. Appearance vocabulary adds long
moustache, clean-shaven sideburns and slightly wide-set eyes. These build-time
entries preserve the existing atomic fallback for unknown clauses.

Expected failures were reproduced before the parser/data fixes. Lua preference
fixtures pass typed-slot restoration, source preservation, poetry and alternate
deity spelling. The ordinary suites pass 90 Native and 103 Broker tests (11/5
opt-ins excluded), six relevant Node tests and five package integration tests.
The separately required personality corpus test was not included in that five;
its earlier gate remains tied to its historical snapshot. The new 22-source
diagnostic checks all 88 exact bilingual Native/Broker outputs against reviewed
targets, with zero provider/worker submissions. Release build and package
validation pass. A test expectation was corrected to the existing reviewed
emerald color term; production color terminology was retained.

Actual release-DLL rendering for this manifest was completed in an isolated
seven-citizen fortress. The initially selected resident's summaries, preferences,
needs/prayer, appearance, traits and values settled in Chinese with essential
semantic colors preserved. An additional resident retained five English overview
summaries, a complete preference paragraph and a compound appearance paragraph.
The random current quote also produced an unsupported sentence. The frozen
pre-repair ledger retains all eight misses among 36 recorded development units;
its incomplete inventory and uncertified independence mean it contributes zero
holdout units to the overall acceptance gate.

### 2026-10-05 resident material/appearance repair and cold reload

Candidate manifest
`a63435d5fb83c5175c61e3a5477d409f7d9414fd75382e21900fd6954640c349`
contains 913 files. Native DLL SHA-256 is
`9cc68e70f5ecaf349bd666a2f5e14388a93f9a9f7a10f4b533207a3c74f63369`;
Broker EXE SHA-256 is
`034fccdb0edbc684872e28e7a6d4ccca3b51eb4bcef6c64ac68b5b71b461469e`.
The original descriptor and frozen baseline above retain their original hashes.

The bounded appearance parser now composes two reviewed `has` clauses joined by
`, and`, requiring the same pronoun and rejecting unknown or additional clauses.
New exact appearance vocabulary covers medium-length sideburns/moustache,
very splayed ears and slightly wide-set narrow eyes. Preference items check
their typed namespace before generic terms: metal gold remains distinct from
the color gold. Reviewed black-cap wood, silvery gibbon leather and cotton
fabric entries complete the observed paragraph. Five overview summaries and
one current quote have exact reviewed translations. No world identities are
added to shipped dictionaries.

Red/green parser and packaged regressions reproduce the original misses.
Ordinary suites passed 105 Broker and 90 Native tests (5/11 opt-ins excluded),
39 relevant parser tests, eight relevant Node tests and six packaged integration
tests. The packaged complete paragraphs and summaries have 16 exact bilingual
Native checks with zero worker submissions; the loaded release DLL also passed
16 in-process bilingual checks. Release build and 913-file package validation
passed.

Cold reload used fresh audit state and cache, with AI, cloud downloads and
sharing disabled. Both installed copies and the actually loaded DLL matched
this snapshot. The second resident's five summaries, complete three-sentence
preference paragraph and fourteen-sentence appearance paragraph rendered in
Chinese. Its traits and values retained green/red and gray/cyan/yellow colors.
The first resident's complete preferences, needs/prayer and ten-sentence
appearance paragraph also rendered in Chinese. Proper identity and form names
remained literal; surrounding prose translated. The new randomly chosen quote
`"Yes, I want more.  Is that so bad?"` remained English and is retained as a miss.
Some thought and need rows initially appeared in English before settling in
Chinese. Screenshots are stable observations, not evidence of the first visible
frame. Graphics FPS was 49–50 in the paused seven-citizen test; this does not
establish large-population or unpaused performance.

Normal save in the first phase and cold reload in the second preserved all seven
citizen identity/profession records and all 202 world squad records exactly.
These are world squads, not 202 player squads. The game was normally exited;
player settings, legacy cache and overlay configuration were restored. All
10,839 protected original save files were unchanged, with zero missing or added
files outside the clones. Both clones were archived; the source snapshots were
unchanged. Two files changed in the normally saved fortress clone.

Evidence is under private `live-ui-0511-resident-final-20261005`:
`resident-pre-repair-ledger.json`, `pre-repair-evidence-hashes.json`,
`resident-live-summary.json`, both package manifests, ten reload screenshots
and render traces, identity snapshots and `restoration-report.json`.
This is repair/regression evidence and adds zero certified holdout units.
The independent acceptance denominator, three-mode 90% overall target,
first-display behavior and large-population performance remain unestablished.
No Steam or GitHub publication has occurred.

### 2026-10-05 complete personality/value current-quote inventory

The latest manifest is
`70be54a778c644b18b7ee2f6e94caef530e5324a1fd680a83549b5499474b18a`
(913 files). Only the two generated personality dictionaries changed from the
preceding resident snapshot. Native and Broker binaries are unchanged.

Added reviewed translations for all 254 complete literals in a frozen
personality/value dialogue block from the installed 0.53.16 executable.
Fifty incomplete or contextual fragments in that block are excluded; other
emotion/dialogue blocks remain outside this inventory. These are exact
build-time quote entries, with existing reviewed wording preserved, rather
than new runtime parsing or per-frame scans.

Nine relevant Node tests pass. Seven other package checks and the separately
rerun dedicated quote semantics test pass. Native and empty-state Broker each
pass all 508 exact bilingual quote lookups with zero worker/provider submissions.
Both local installs match the manifest and the loaded release DLL passes the
same 508 bilingual lookups. Normal reopening of the actual resident overview
selected the previously missed `"Yes, I want more.  Is that so bad?"` and displayed
the complete correct Chinese quote at 50 graphics FPS; its first recorded
native selection was already Chinese and retained its white palette.

The game was normally exited and original settings/cache/overlay restored.
All 10,839 protected original save files were unchanged, and both unchanged
test clones were archived. See `OFFLINE-CURRENT-QUOTES-20261005.md` and the
private `live-ui-0511-quotes-final-20261005` evidence. This quote population is
development/regression evidence, not a whole-game denominator. The overall
90% acceptance and outstanding mode/performance checks remain incomplete.
No Steam or GitHub upload has occurred.

### 2026-10-05 Legends text/trade boundaries and verified biographies

The safety text/trade session was normally exited and restored. Its loaded DLL
passed 50 exact bilingual lookups with unchanged counters `[0,0,652]`, identical
330 native words/56 links, and correct entity-35 coordinate click behavior.
Unknown procedural race captions remain complete English. Malformed response
journals cannot replace valid rich paragraphs, and terminal failures expose
native spans and permit retry. Explicit ASCII control checks preserve Unicode
punctuation in the bundled Lua runtime.

The subsequent biography candidate, still 0.5.11, has 913 verified files and
manifest `06e85907015159b342ea8e4eeccb9a1bae0a0698696490d0c0ada225738e228d`.
Native DLL: `e88a15eafe2b3825cee9bc7cab9a090c1f8373e186679434297b98fe3c9e4b84`.
Broker EXE: `d2a830e3ff58075cf44ea048aed2f3ee4cff4d1fe54273b6cc9881c40187a084`.
Both are portable static CRT builds. Figure aliases are read once per capture;
only an exact authoritative unlinked prefix receives a local DFT text slot.
Reviewed typed race/birth/family/unique-kind grammar preserves all native data,
colors and parent links; unknown or malformed prose rejects atomically.

The ordinary workspace passed 110 Broker and 91 Native unit tests plus the
other suites, with opt-ins separate. Eight Node tests and six packaged Lua
fixtures passed. Packaged Native and empty-state Broker each passed 74 exact
bilingual checks (64 translations and 10 rejections), with zero worker/provider
submissions. Package validation and all manifest file hashes passed.

Cold reload used fresh audit state/cache and disabled AI/downloads/contributions.
The loaded DLL and installed manifest matched this snapshot. Complete dragon
and human introductions rendered Chinese at 50 settled graphics FPS. Clicking
the parent link actually opened historical figure 527; her youngest-daughter
introduction also rendered Chinese. Loaded Native passed all 74 checks with
counters unchanged at `[0,0,521]`; all 330 words/56 links remained identical.
Transition captures were lower FPS and do not establish first-frame behavior.

Both sessions restored all 10,839 protected original files, settings/cache/overlay,
and archived unchanged clones after normal game exit. The biography candidate
has been promoted to both local distribution directories with complete file/hash
equality, preserving previous directories in a private backup. See the text/trade
and biography documents and private `live-ui-0511-legends-biography-20261005`.

These remain development/regression samples, adding zero certified holdout units.
No overall 90% score, large-population unpaused test or newest-package fortress
save/reload proof is established. Substantial entity histories, unlinked battle
names, generated races and theft/injury prose remain gaps. No commit, GitHub push
or Steam publication occurred.

### 2026-10-05 Legends civic events (final cold validation restored)

The 913-file final candidate has manifest
`d78beec735588fab343792d146126e75261b3e65ce777e6ae1c14dcf4ea5f31a`.
Packaged Native and fresh Broker each passed 324 exact bilingual checks,
including deliberate complete-paragraph rejections. The loaded DLL passed the
same checks with counters unchanged at `[0,0,161]`. All 687 frozen entity-35
sources, 20,241 native words and 1,493 native links remained identical. Founder,
building, appointment methods, peace, commander roles and sentence-initial
typed goblin captions rendered Chinese with native colors. A real coordinate
click opened entity 36. Settled entity-35 graphics FPS was 49, with an observed
transition capture at 21; no first-frame or unpaused performance claim follows.

The entity-36 capture retained a miss in the actual comma-bearing popular-support
form, which earlier no-comma fixtures did not exercise, plus ruling, entity/world
introductions and festivals. These are recorded gaps in this snapshot.

Normal game exit, unchanged archived clones and restoration of settings/cache/
overlay completed. All 10,839 protected original files matched their hashes.
Both distribution directories now equal this candidate; previous copies are
preserved. See `OFFLINE-LEGENDS-CIVIC-20261005.md` and private
`live-ui-0511-legends-civic-final-20261005`. Development regressions add zero
independent holdout units. Overall 90%, large unpaused performance and the
latest-package fortress save/reload gate remain incomplete. No upload occurred.

### 2026-10-05 authorized 0.5.11 publication before overall coverage acceptance

The release now includes the complete festival/ascension-story repair, including
the actual ceremony-feature miss, plus closed-tab cache pruning. The final
Steam manifest is
`fc5b9525b046c76d06bd6553cd6bf63b3ba900a83e719dc34252f140793d070c`
(914 listed files). GitHub retains its existing preview with manifest
`ba97ac92e1c21b3627293a6e006014f8e886872f5bb4cb0e35f4e9d9599f3cd6`.

Final packaged Native, fresh Broker and loaded game DLL each passed 504 exact
bilingual regressions with zero AI submissions. Ordinary Rust workspace tests
passed, including 119 Broker and 91 Native unit tests; environment-specific
opt-ins remain separate. Node: 220 passed, zero failed, one live-cloud skipped.
Python validation tooling: 22 passed. Package hashes, structure, licenses,
static CRT dependencies, relevant Lua fixtures and both ZIPs were verified.

The final AI-disabled cold Legends session preserved 687 original paragraphs,
20,241 word records and 1,493 link records, displayed the full ceremony-feature
story and eight festival outputs, and opened native site 39 through the actual
Godseas link. Stable observed screenshots were 50 graphics FPS. Normal exit and
restoration verified all 10,839 protected original files unchanged plus restored
settings/cache/overlay; both unchanged test clones were archived.

Steam upload succeeded. Independent SteamCMD re-download matched every one of
915 files and the manifest, with public cover/description/title/tags/visibility
unchanged. The user requested publication of this verified scope now; this
does not establish the original independent 90% coverage acceptance. No new
certified holdout units or overall coverage percentage are claimed. Unsupported
roads/bridges/unlinked actors, complex plots, dynamic dialogue/combat and large
unpaused or long-running performance remain work. Earlier fortress save/reload
evidence belongs to earlier candidate binaries, not this final binary pair.
See `RELEASE-0.5.11.md` and `OFFLINE-LEGENDS-FESTIVALS-20261005.md`.
