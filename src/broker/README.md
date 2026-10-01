# Local Traditional Chinese translation broker

## Workshop packaging

`prepare-workshop-package.mjs` creates a clean DFHack Workshop package with
`scripts_modinstalled/`, local adapter data, broker source, and Steam metadata.
It excludes world exports, translation journals, provider settings, logs, saves,
and caches. Use `--adapter-only` for the public package: it omits `dfi18n-data`
and requires players to subscribe to the upstream Chinese data separately. A
full package includes upstream data only after redistribution is authorized;
`--allow-unverified-upstream` is only for a local test package.

The pinned GitHub data source `DFI18n/dfi18n-data-zh-hans` is tracked separately
in `LICENSE-STATUS.json`. It is CC BY-NC 4.0, with maintainer confirmation from
`anln666` for modification, Traditional/Simplified conversion, and redistribution
in free modules and cloud translation libraries. Attribution, change notices and
the non-commercial condition remain required. The official R2 package currently
contains only project-authored CC0 rows; it does not silently merge this source.

The public package requires DFHack 53.16-r1.1, DFI18n 0.2.4, and a local Node.js
runtime for the optional broker. The Workshop build carries the locked
production Node dependencies under `broker/node_modules`; it never contains a
Node.js executable, the RimWorld XML, or an API key. The player's provider
settings are discovered locally at startup.

The game invokes `hack/scripts/df-local-zh.lua` from its DFHack init file.
The bundled `df-broker-launch.dll` starts the scoped PowerShell launcher without
a visible console. The launcher checks the loopback service before starting
Node, and never terminates an unrelated port owner. No scheduled task is used.
The launcher assigns its PowerShell process to a Windows Job Object owned by
the game. Windows terminates that process and its descendants when the game
exits, including abnormal exit. A broker already running independently is not
adopted or terminated. The lifetime regression uses a separate native host and
a sleeping helper/grandchild, without loading saves or calling the AI provider.

## Configuration

The launcher discovers the existing RimWorld XML provider settings in the
player's local profile and passes that path only to the broker process.
Credentials are read at startup and are not copied into this directory.
Restart the local broker after changing providers. The API is loopback-only at
port 19753.
The broker also loads the reviewed CSV and accepted raw-material, raw-name,
and reaction-name CSVs at startup; these entries take precedence over older AI
journal entries.

`POST /v2/translate` accepts `{ "text": "..." }` and returns
`{ "translation": "..." }`. `/health` exposes counters and policy version.

## Dynamic text

The fortress report prefetcher handles both new report events and the report
backlog already present when a map is loaded. Backfill processes at most 32
reports every 20 UI frames. Identical text for an existing report ID is skipped;
changed text and IDs reused in another world can be queued again. This prefetch
does not establish rendered Chinese coverage.

Runtime alias filters preserve ordinary words such as `Laborer` and `Lithium`.
Only underscore-suffixed keys or six-character suffixes containing digits are
recognized as generated aliases. Bare letter-only keys remain ambiguous and
are handled conservatively as source text.

- Known entity names are protected slots, then restored from a fixed glossary.
- On world load, DFHack exports first names and native/English aliases for
  historical figures, sites, organizations, the world, named artifacts,
  book titles, and other named world layers. Region and layer links without a
  native name are still pinned by their Legends target ID when first seen.
- Unknown registered names are translated separately and cached before the
  sentence is translated. Both aliases then use the same canonical name. The
  selected spelling is pinned by world and entity ID in the durable journal.
- Numeric slots preserve original numbers and reuse a sentence pattern across
  years and counts. Explicit narrative dates restore the Chinese year unit.
- Accepted templates are persisted with fsync. Concurrent identical requests
  share a provider call. Policy changes invalidate incompatible cache rows.
- Compilation applies pinned names to known aliases and already-translated
  history sentences. Reviewed older spellings live in
  `canonical-name-variants.json`.
- Model output containing Latin prose or changed tokens/numbers is rejected.

An unregistered name is pinned by its Legends target type and ID the first time
it is seen. This covers display aliases that change between screens and survives
Broker restarts through the private translation journal. DFI18n still sends only
text, so a link that never reaches the structured Legends adapter cannot be
resolved by ID. Generated prose, written content, and other renderer paths need
their own live coverage.

## Tools

Run under this directory with Node 24:

```powershell
node --test test/*.test.mjs
node live-check.mjs
node prewarm.mjs data/unresolved.jsonl data/prewarmed.csv 100
node compose-legends.mjs 100
node scan-mods.mjs data/mod-inventory.jsonl <vanilla-data-directory> <player-mods-directory>
node audit-raw-coverage.mjs data/mod-inventory.jsonl <active-dfi18n-data> data/unmapped-raw.jsonl
node audit-raw-coverage.mjs data/mod-inventory.jsonl <active-dfi18n-data> data/case-variants.jsonl '' caseVariant
node review-case-variants.mjs data/case-variants.jsonl <active-dfi18n-data> data/case-variant-review.jsonl data/prewarmed-case-variants.csv
node generate-raw-states.mjs data/mod-inventory.jsonl <active-dfi18n-data> reviewed.csv data/raw-state-candidates.jsonl data/prewarmed-raw-states.csv
node generate-reaction-names.mjs data/mod-inventory.jsonl <plants/name.toml> reaction-plant-terms.csv data/reaction-name-candidates.jsonl data/prewarmed-reaction-names.csv
node compile-data.mjs <companion-data> <native-local-data> ../traditional-patch
```

The scanner writes ownership and file hashes for eligible raw display tokens.
It never rewrites raw IDs. The prewarmer produces supplemental CSV from accepted
translations. Recompile and deploy the independent patch to apply those entries.
The coverage audit distinguishes exact CSV keys, exact TOML rule keys, case
variants, and sources with no direct key. These are lexical matches, not a
measure of Chinese rendered on screen: some `english_name` rules deliberately
return the original English word, and context-specific rules may be unreachable
through DFI18n's generic `sync_translate` entry point. The case-variant review
records each candidate translation and its rule file. Only unique Chinese
candidates enter the global CSV; ambiguous creature/caste terms and generated
name words need context-specific treatment. Isolated raw words need review
against their token field and source file before adding AI output.
The raw-state generator reads the full scan inventory, so regenerating after
deployment keeps previously translated entries. It composes only venom, dairy,
and tree-wood terms with known names and records each basis in the JSONL output.
The reaction-name generator composes dye jobs from the existing plant names and
the reviewed plant-term CSV. Other audited raw names use reviewed-raw-names.csv.
Both name lists are included in the compiled canonical dictionary and in the
broker's startup dictionaries. Eight local Traditional Chinese TOML rule
overrides are retained under `../local-patch/dfi18n-data/rulesets/zh-Hant`.
The compiler merges their reviewed keys into the converted Workshop rules so
required references remain available. Compare staged and active hashes before
deploying a rule change.
`compose-legends.mjs` builds stable figure captions from world-pinned names and
fixed race/title terms. It resumes from `data/composed-legends.csv`, pins missing
figure names by ID through the loopback broker, and leaves original saves alone.
Prewarm output is resumable; move stale output aside after changing terminology.
The optional third argument limits newly attempted sources in one run. Existing
rows are checked against pinned names and glossary terms before being reused.

Build the startup bridge using an installed Windows C++ compiler:

```powershell
clang -shared -std=c++17 -O2 launcher.cpp -o df-broker-launch.dll
```

Close the game before rebuilding a loaded DLL. The startup bridge reads no game
memory, and its only exported entry starts the local helper process.

## Remaining Renderer Work

Structured Legends paragraphs now carry protected link tokens plus native
target types/IDs. Figure links and subject short references resolve through
world-specific canonical pins, including when two figures share a first name.
The overlay renders translated chunks with category colors and independent
scrolling. Native text scroll is temporarily moved offscreen; disabling the
overlay restores it. Click dispatch verifies current link identity and resolves
current native word coordinates, so a resized layout does not reuse stale
positions. During forwarding the overlay yields its own input handler so the
synthetic native click reaches Legends; a live type-6 target opened mode
6/index 89 after this fix. Automated coverage does not establish every live
hitbox, long-page scroll, or FPS target.

Some Legends list text is not submitted to the broker. First-seen cloud
translations remain asynchronous, and translated rich narratives have been
observed without original colored link spans. The public DFI18n develop source
does not match all cloud functions in Workshop 0.2.4. Therefore this adapter does
not establish zero English or complete interaction preservation. Fortress play,
thoughts, medical/combat reports, books, and mod interactions need live coverage.

## Runtime dictionary bridge

`df-local-zh-runtime.lua` can queue a missed source with `request(text)` and
retrieve its loaded dictionary key with `lookup(text)`. It writes single-line
requests to `data/runtime-requests.jsonl`. The broker translates requests only
for the currently exported world and appends validated results to
`data/runtime-responses.jsonl`. The game polls those results, loads one-row CSVs
through DFI18n's `load_simple_dict`, and uses world-scoped synthetic ASCII keys
for Unicode rendering. The two JSONL files stay local and contain no provider
credentials. On failure, the game can retry the source after 20 seconds.

The broker additionally persists sanitized failures in `runtime-failures.jsonl`
and backs retries off exponentially to five minutes. `/health.runtime` exposes
attempted, published, failed, cooldownSkipped, and unresolved counts. Results
that finish after the active world changes are not published for that world.
Resolved Lua lookups avoid repeated native queries on each polling frame.

Unknown native lookups use `async_translate`, since blocking misses were
measured at 0.427-1.167 seconds each. Short aliases may specify a maximum
display width without abbreviating the corresponding full detail caption.

Figure captions use `request(text, figure_id)` and
`short_lookup(text, expand, alignment, max_width, figure_id)`. These requests
bypass native Chinese results and carry the actual historical figure ID.
The queue uses a separate versioned caption identity, validates both aliases
against the current world's registry, and composes the role with the durable
figure name. Generic legacy response records cannot satisfy these requests.
An unregistered caption or role remains unresolved instead of accepting a
potentially inconsistent native translation.

Expandable Legends fields reserve Chinese display width and keep spacing
between groups. Centered header aliases include fitted dictionary variants for
the game's truncated tab captions. Alias numbers are allocated in persisted
blocks through `runtime-alias-counter.txt`: preserve this file alongside the
native render cache, since reusing a key can display its older translation.
The alias counter, journals, world names, and credentials are private runtime
state and must be excluded from any Workshop package. The latest live checks
are in `../STATUS.md`; this bridge does not establish complete localization.

The bridge was exercised in the live region2 game: `The Nightmares of Clinging`
was queued, resolved by the broker, loaded without a DFI18n reset, and returned
Traditional Chinese through the native lookup. The renderer still needs to collect and
draw rich-text spans. Direct UTF-8 passed to `dfhack_addstr_flag` rendered as
mojibake; it requires a loaded dictionary key. A one-line Legends overlay kept
the original link clickable but disturbed the next row, so that overlay was
removed. After a clean game restart, the startup hook automatically received
and loaded `The Threat of Toast` as Traditional Chinese, without a manual poll.
Full-page layout and first-display behavior remain unverified.
