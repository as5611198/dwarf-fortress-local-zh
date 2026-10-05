# Offline history and decorated items — 0.5.6 local candidate

Continues the approved offline-first work. This stage is a local candidate; no Steam or GitHub publication.

## Changes

- Adds bounded, bilingual history composition for native linked identities: creation/storage/theft, births, marriages/divorces, deaths, migration, organizations, abductions and imprisonment. Exact supported event structures retain every link once even when Chinese changes the word order. Years and optional native sentence punctuation are preserved semantically. Arbitrary names are never inferred from prose.
- Connects the shared Rust parser to both broker and native local lookup. The Legends paragraph entry point now tries local data before learned responses or queue writes. Link labels are retained literally from the native links; this is sentence localization, not a claim that all personal names are translated.
- Adds legendary item headers, both craftsmanship spellings, gem encrustation, studs, decoration, bands, hanging rings, spikes, size and spatter clauses, plus simple images whose subjects/materials already have complete local terms. Unsupported clauses reject the entire lookup.
- With AI disabled, unresolved Legends paragraphs display the original text and native links instead of waiting indefinitely. Changing AI state or language invalidates prepared paragraph layout.
- Input bounds remain 4,096 bytes for composition; item paragraphs allow at most 32 sentences. Runtime work uses bounded parsing and direct term lookup. No world-wide name scans, new background jobs, file reads or unbounded caches are added to the local translation path.

## Verification

- Red/green tests reproduced missing history/item composition and the AI-disabled pending fallback. Negative tests cover unknown clauses, forged/intermediate placeholders, duplicate or malformed link tokens, and overlong inputs.
- Rust workspace: 149 passed, 13 ignored. The first test launch lacked the game's DLL paths; the full rerun with those paths passed. Existing compiler warnings remain.
- Node: 208 passed, 1 skipped. One pre-existing multi-API integration test failed during the first concurrent run, passed in isolation, and passed in the final full rerun; no assertion was relaxed.
- Lua fixtures: native link identity/reordering, Unicode literal labels, layout/wrapping/click identity, language/API mode refresh, queue I/O recovery and poll cost passed.
- Empty-state packaged broker: final rebuilt package passed 154 bilingual regression queries, zero misses and zero API requests; measured maximum lookup 3.342 ms, excluding startup. Final deployed native and archive details are recorded under `_localization-work/offline-history-20261004`.
- Native Legends UI: observed translated creation/storage and membership/settlement/marriage/divorce paragraphs with AI disabled. Clicking the reordered creator link opened historical figure 2766, matching the original native link ID. Captured steady render FPS was 49 on both inspected detail pages. An actual `created in ... by ...` ordering gap was reproduced by a failing bilingual unit assertion and fixed before rebuilding and rerunning the full Rust suite.
- The existing player had explicitly disabled `df-local-zh-narrative-overlay.narratives`. It was enabled temporarily for this UI test and restored to disabled afterward. New installations default to enabled; existing disabled preferences are respected. Enable it before opening a detail tab to use rich offline Legends paragraphs. If toggled on while an old detail tab is open, close/reopen that tab to discard old runtime name placeholders.

## Coverage limitations

The development suite combines prior personality/life regressions, observed historical paragraphs and synthetic combinations. It is not a representative whole-game benchmark.

Five additional historical capture strings were held out from implementation. Only one of five translated in each language. The four misses were an unsupported multi-sentence ritual history, two truncated descriptions, and a long named corpse/spatter paragraph exceeding the supported sentence structure/budget. The probe deliberately reused the all-hit audit harness and therefore exited with an unmet-coverage assertion; its zero-API result and misses are retained in `held-out-result.json`. These samples are now known and must not be reused as unseen evidence in future work.

Raw named fortress announcements do not automatically carry Legends link tokens, so their separate report adapter still needs identity-aware expansion. Arbitrary engraved scenes, written inscriptions and complex historical relations also remain outside this bounded grammar. No 90% vanilla coverage claim is supported.

The final live artifact page had 3 of 9 complete paragraphs recognized locally; the linked figure page had 6 of 54. These include headings and complex unsupported paragraphs and are observations of two selected pages, not whole-game coverage. Seasonal dates (for example `In the early spring of 73`) remain unsupported even for otherwise recognized events. Unknown native names are preserved in English, including race/title text embedded in a native link label.

The existing player state, learned cache and API profiles are retained. A backup of region3 and save-file hash baseline were taken before the normal save/reload cycle. Private captures and saves are excluded from the release archive.

## Final local candidate

- Both local installation targets match all 861 packaged files; deployment retained 166 player-state files unchanged.
- Final native DLL in paused region3: 154 bilingual lookups passed, zero failures, AI disabled, six render FPS samples all 49. Maximum measured lookup was approximately 1 ms at the timer's resolution. This is a short paused-save regression, not a long-running simulation benchmark.
- The save-file baseline had 10,839 files. No files were added or removed. The normal save changed only region3 `world.sav` and `dfhack-entity-2190.dat`; Legends browsing appended only `events-dfhack.log` in region1 and region1-localization-test. The verifier initially rejected those logs, then allowed only these two exact diagnostic paths after their lifecycle entries were inspected. Other save files retain their baseline SHA-256.
- Archive: `df-local-zh-complete-0.5.6-offline-candidate.zip`, 861 entries, every entry checked against the package SHA-256 manifest. SHA-256: `b50c6cbf77a7569143a184292ef30ff1bb9b219cb8ea623b8b455248430ab84e`.
- Game left in the player's paused region3 with AI still disabled. No external publication was performed.
