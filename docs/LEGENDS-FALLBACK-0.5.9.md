# Legends fallback and pending-state accuracy — 0.5.9 local candidate

This increment repairs display fallback while continuing the offline-first work. It adds no new translation templates and makes no claim of 90% vanilla coverage. Steam and GitHub publication are outside this increment.

## Root causes and changes

- Legacy Legends detail and list readers treated every missing alias as an active AI job. Disabled AI, failed jobs, render warm-up and an alias too wide for the screen could therefore show an indefinite `翻譯中` label. Names now retain their original readable text until a translation is ready.
- `request` returned `pending` before checking whether AI/background work was disabled. The setting check now takes priority after available translations have been checked, so existing translations remain usable.
- `lookup` lost secondary return values through a Lua `or` expression, and `short_lookup` discarded request state. Both now propagate status. Embark/text-viewer overlays pass that status to the pending-label function, which accepts only queued/pending jobs while AI is enabled.
- Legacy detail replacement blanked the remaining words of a name. The reader now snapshots the exact native strings and coordinates, restores only spans it still owns, and leaves native link IDs and colors untouched. A rich-reader capture restores legacy spans first, including when its render callback runs before the legacy polling timer.
- Snapshot retention follows open Legends tabs. Full span validation and rewriting retain the existing throttled cadence; mode/width changes refresh immediately. No new disk I/O or network operation is introduced into this fallback path.

## Verification

- Observed failing regressions before production changes: AI disabled after a queued job, status loss through both lookup layers, false waiting-label publication, and replacement of an unavailable native name.
- Seven Lua fixture suites pass: queue I/O, Legends fallback, narrative layout, rich runtime, text-viewer colors, polling cost and fortress reports. New assertions cover original words/coordinates, native identity/color, oversized translations, stale native regeneration, world changes, rich capture after legacy aliases, and genuine queued-job labels.
- Rust workspace: 156 passed, zero failed, 13 ignored. Node: 208 passed, zero failed, one skipped. Existing compiler warnings remain.
- Release build and package validator pass. Installed and Workshop-local copies verify 864 files including the manifest. All 166 player-state files were unchanged by deployment.
- Live AI-off checks passed on the artifact list, `The Tenderness of Packs`, and Lolor Ageclasps (historical figure 1415). Seven captured states contain zero pending placeholders. The figure's legacy page contained one real translated alias; switching to the rich reader restored it to native text before capture. Reopening the figure page preserved readable names and native colors. Settled captures were 49–50 FPS.
- Clicking Lolor's identity in the Chinese artwork paragraph opened historical figure 1415. The rich overlay was restored to its original disabled preference after testing. AI remained disabled throughout the live UI checks; toggling AI with a pending job was covered by controlled fixtures without sending player text to an API.
- Deployed native integration passed exact artwork, supplementary Unicode literal identities, location ordering and atomic fallback. The original `region3` save reloaded successfully and remains paused. Final bilingual corpus/FPS and ZIP evidence are in the private `final-verification.json`.
- In reloaded `region3`, all 210 bilingual regression queries passed with AI disabled. Six paused render samples were 50, 50, 49, 50, 50, 50 FPS. This is a short paused smoke check, not unpaused/soak evidence or a coverage benchmark.
- Save comparison hashed 10,839 files before/after, with no additions or removals. Only region3's normal `world.sav` and `dfhack-entity-2190.dat` save writes and the test world's `events-dfhack.log` changed. Full pre-save region3 backup remains private.
- Candidate ZIP verifies all 864 entries. SHA-256: `eb4704c053b6c1f227aa532cde9778747239179d2a48efb822020f3c3101645b`.

## Remaining scope

Offline report identities, unsupported event/artwork grammar, literal proper names and broader fortress/adventure coverage still need work. AI-off fallback intentionally keeps unknown text readable; it does not translate that text. Runtime-state fixtures are not an API provider reliability test or a whole-game performance benchmark.

Private save backups, deployment records, logs and candidate archive are under `_localization-work/legends-fallback-20261004`, outside the public repository.
