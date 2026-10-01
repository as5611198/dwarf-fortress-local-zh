# Local Traditional Chinese: Owned Core

Local build 0.3.0 for Dwarf Fortress 53.16 / DFHack 53.16-r1.1 on Windows.
DFHack is required. The DFI18n engine and Chinese Workshop subscriptions are
not runtime dependencies: this package includes its own native DLL, loader,
Traditional Chinese assets, adapter scripts and localhost Broker.

Exact dictionary and completed memory cache hits return synchronously.
Only misses enter the bounded queue (64 keys, two workers by default).
Completed translations retain formatting, palette tags, alignment, language
and world scope. Legacy CSV records migrate to the private JSONL journal.
Private state remains in `dfhack-config/mods/df-local-zh-complete/data`.
API credentials remain in `api-profiles.private.json` in the private mod state
directory, outside this package. Existing API settings are imported once.

Start with `df-local-zh` in `dfhack-config/init/dfhack.init`.
Never reset or hot-replace an attached native renderer. Restart the game to
activate a native core update. The `df-local-zh-test` command runs automated
injection tests and records results without requiring manual panel navigation.

Chinese search uses our native bounded-string Hook and an SDL UTF-8/IME/clipboard
input bridge. Matching reads local dictionary/rule literals and completed cache;
it never runs translation rules, contacts AI or submits work. English search is
retained. Common Traditional variant forms such as 岩/巖 are equivalent.

The focused native FILTER textbox is supported on every viewscreen. Legacy
bindings cover Stocks, trade/haul/display assignment, construction materials,
job details, custom stockpile filters, workshop job lists, work-order creation,
justice counterintelligence, arena filters, embark item selection and native
Legends page filters.
DFHack FilteredList and search/filter EditFields use the shared local matcher and
UTF-8-safe editing. Third-party filters with their own comparison implementation
may require an additional adapter.

`df-local-zh-search-test` automatically tests real Stocks with temporary iron
goblet/granite items (removed afterwards), a native unit-list filter and a real
DFHack FilteredList. Results go to the private data directory. It requires a
loaded, paused fortress and neither saves the game nor needs manual navigation.
Callbacks and next-frame readiness checks complete the run; a short frame
deadline detects failures. Tests retain original item/unit/choice identities.
The test injector sends both key press and release events. Completion restores
the paused default fortress view after DFHack dialogs have actually closed.

Automated verification on 53.16 passes 26 native/rules tests and 24 fortress
injection checks. Live search checks cover Stocks, a native unit-list textbox
and nine DFHack Chinese/English/IME/editing cases. Three thousand local matcher
calls take about 3-4 ms and submit no translation work. This timing excludes SDL
delivery and game frame scheduling. Individual legacy panels and third-party
private filters are not all covered by live tests. Adventure-specific legacy
filters are outside the current fortress verification.

## Native Bulk Cache Loading

The DLL reads `native-prewarm*.json` on its own background thread. Lua only
passes the current world, language and user pause state and reads a small status
record. Imports no longer use the model scheduler or per-row Lua publication.
No provider calls or per-row persistence happen during loading. File changes
are checked once per second; a context change wakes the worker immediately.
Validated rows publish as immutable world/language snapshots. Reviewed local
dictionaries retain priority, late model results supersede their preload
baseline, and paused or cancelled work cannot publish. Search uses the same
baseline priority, with bounded batches that do not hold the dictionary lock.

Broker exports a separate compact `native-prewarm-unit*.json` for Lua display
aliases and previously viewed prose, avoiding bulk JSON parsing on restart.
Older Broker exports retain a compatibility fallback. Invalid individual rows
are counted and sampled in native status instead of blocking valid rows.
`native_prewarm_request` and `native_prewarm_status` are Lua-callable DLL exports.
A restart is required when deploying this DLL change.

## Settings And Languages

The Settings screen on the title menu and inside a fortress has a Mod Settings
entry. `df-local-zh-settings-ui` opens the same panel from the DFHack console.
The panel covers language/display, API profiles, translation processing and an
inactive cloud text synchronization page. Cloud hot updates are excluded.
Global defaults and per-save overrides are stored locally in `settings.json`;
overrides are keyed by save folder and contain an API profile ID, never a key.
Apply saves and updates the running native core and Broker without resetting
the renderer. Cancel discards the current draft. Inherit Global removes the
selected save's overrides. API keys are masked, support paste, and are absent
from public snapshots, rendered text and completion logs.

Both Traditional and Simplified include the complete existing curated base
dictionaries/rules. Simplified workbook translations keep their source text.
OpenCC converts dynamic Chinese and validated Traditional cache rows locally.
Chinese search accepts both writing systems, full mainland Pinyin, initials,
spaces and tone marks/numbers. Pinyin can be disabled independently. Query and
localized text caches are bounded and invalidated when dictionary entries change.

The supplied community workbook now has separate Traditional and Simplified
literal supplements. Traditional entries supplement existing reviewed data;
Simplified entries reuse the source workbook, with reviewed corrections applied
to known errors. They are selected by language in both the native core and Broker.
English identity values do not count as existing Chinese translations. Exact
case/whitespace variants are imported, previous supplements are retained on
rebuild, and adjective/noun meanings have separate english_name rule groups.
Fully specified examples are exact-only dictionary entries. Thirty-six finite
alternative templates expand to 131 concrete entries per language. Unbound
templates and save identifiers remain documented exceptions. Eight source typos
are traced to their already translated canonical game strings.
The Simplified supplement is combined with a generated Simplified base package.
`df-local-zh-workbook-test` checks every supplemental source against the real
native dictionary and repaint path in both languages, checks worker submissions,
then restores Traditional Chinese before returning. No AI or UI navigation is
required for this test.

## Provenance And Distribution

The Shared Contributions settings page is opt-in and defaults off. Applying it
consents to CC0 sharing of new, filtered generic AI translation results; old
caches are never scanned for upload. Private names, save state, API keys and
settings are excluded by a conservative boundary. Safe templates keep names
local. This filter is not proof that all private names can be detected.

The dedicated DF Worker collects three device and network signals for identical
Chinese and performs independent Workers AI review of Dwarf Fortress semantics.
AI-reviewed entries are explicitly marked and cannot override built-in or user
corrections. Signals are not verified people, and AI can misjudge meaning.
Disabling sharing stops future uploads; clearing pending submissions keeps local
AI and official libraries. Official downloads remain usable offline without API.
Updates during gameplay stay pending until the game closes and Broker restarts.
The automatic publisher has a separate signing key; older clients need this
Broker update to trust automatic versions. No DLL update is required.

Creature singular/plural rules and race-map labels are compiled into 4,976 exact
entries per language, retaining validated workbook spellings. Unit names consult
local species entries synchronously; only unknown names use asynchronous routing.
Creature context resolves pike as a fish while equipment keeps its weapon meaning.
`df-local-zh-creature-test` checks both native dictionaries and repaint paths with
zero worker submissions, plus immediate unit-name samples. Personal-name world
isolation is regression tested. Nonliteral templates remain audited exceptions;
their substituted names are not guessed or inserted into the global dictionary.

Arena corrections use reviewed static entries for eye tooth/teeth (犬齒), dragon
(巨龍), Needs setting (需要復位), and all eight artery/nerve/ligament/tendon
clause combinations. Numbered species names derive only from tagged creature
labels. Equipment lookups preserve balanced ownership, wear and quality markers.
`df-local-zh-arena-corrections-test` verifies both languages on the actual native
lookup and first repaint paths, with zero additional worker submissions.

Native source is based on DFI18n commit
083767ce8bea96440f00ebb71c1ac0dfaa4d56f0; MIT license and attribution are retained.
The complete buildable native source is included in `native-source`.
Fonts retain their OFL notice. The separate DFI18n Simplified Chinese data
repository is recorded in `DFI18N-DATA-ZH-HANS-LICENSE.md` and `ATTRIBUTION.md`:
it is CC BY-NC 4.0, and `anln666` confirmed permission to modify it, convert
between Traditional and Simplified Chinese, and redistribute it in free modules
and cloud translation libraries. Attribution, change notices and the
non-commercial condition remain required.
The current official R2 release contains project-authored CC0 rows only; it
does not silently bundle unreviewed upstream data or model cache rows.

Tests verify direct calls and persistence. They do not certify that every game
screen contains zero English or that every native visual layout is correct.
