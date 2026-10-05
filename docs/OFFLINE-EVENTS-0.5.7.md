# Offline seasonal history and relationships — 0.5.7 local candidate

Continues the approved offline-first expansion. This increment targets Legends history and relationship metadata; no Steam or GitHub publication.

## Changes

- Recognizes all twelve native early/mid/late seasonal date forms without dropping the year or season. Unknown date phrases and oversized/non-numeric years reject the lookup.
- Adds childhood friendships, lovers and breakups, fey moods at a site, offerings, family heirlooms, ownership claims, lost/found artifacts, and deaths with a linked weapon and location. Native names and IDs remain literal links.
- Adds exact occupation/title structures for weaponsmith, hunter, woodcutter, dean, princess, king, queen, mayor and priest. The fixed role table avoids translating arbitrary names as job titles.
- Adds parents, eldest/second/youngest children, spouse/former spouse, three worship intensities, organization membership and bounded role tenure. Birth/death/tenure years retain their values; malformed and reversed ranges reject atomically.
- Keeps the existing 4,096-byte input and eight-link limits. No render-time I/O, dictionary/world scans, network calls, or new caches.

## Verification

New behavior was first reproduced with failing Rust tests, then passed against the implementation. Tests check both Chinese variants, reordered native link slots, twelve seasons, unknown roles, malformed years, inverted date ranges and unknown trailing clauses.

- Rust workspace: 152 passed, 13 ignored; existing compiler warnings remain.
- Node: 208 passed, 1 skipped.
- Empty-state packaged broker: 194 bilingual queries, zero misses, zero API requests. Maximum measured lookup 2.4941 ms, excluding startup.
- Package validator: version 0.5.7, 860 manifest entries plus the manifest; both local installation targets verify all 861 files. Deployment retained 166 player-state files unchanged.

- Deployed native lookup in paused `region3`, AI disabled: 194 bilingual checks, zero failures; six render-FPS samples were 49, 49, 50, 50, 50, 50. This is a short paused-screen check, not a long-running simulation benchmark.
- Lua regression fixtures passed: narrative layout, rich runtime, queue I/O and polling cost. Native identity/atomic-fallback assertions also passed against the deployed 0.5.7 DLL.
- Previously captured development pages: artifact paragraph matches increased from 3/9 to 7/9; historical figure matches increased from 6/54 to 44/54.
- Two pages selected after the implementation was frozen: artifact matches 9/16 and historical figure matches 22/28, with stable-screen samples of 50 FPS. Clicking the translated artifact creator link opened the original historical figure ID 2726. These are small samples from one test world, not a whole-game estimate.
- Save hash comparison: 10,839 files before and after; no additions or removals. Only the test world's DFHack lifecycle log and the two files written by the normal region3 save/quit changed (`world.sav`, `dfhack-entity-2190.dat`). A pre-save region3 backup is retained. No unexpected changes were found.
- Candidate ZIP: `df-local-zh-complete-0.5.7-offline-candidate.zip`; all 861 archive files hash-verified. SHA-256: `3c7c0b7b66658fa7aa14628afe05e610f4ffd62d9f5fc31ee85f39e7fe7fdf32`.

Private live validation, save backup and archive details are recorded in `_localization-work/offline-events-20261004` under the game directory.

## Coverage boundaries

The 0.5.6 artifact and figure captures are development data, not unseen samples. Their before/after comparison must not be presented as whole-game coverage. Native link labels still retain English names and embedded race/title text. Arbitrary named battles, competition paragraphs, figure introductions, ritual events and other unrecognized clauses still fall back to the original text when AI is off.

Identity-aware fortress report integration and further complex item-description expansion remain subsequent work. Ordinary report strings do not provide the same certified link slots as Legends paragraphs; this update does not infer names from their prose.

The existing rich Legends overlay preference is respected. It was temporarily enabled for live testing and restored to disabled afterward. The translated full-paragraph results above require this overlay; they do not describe the legacy display with the overlay disabled. Switching the overlay on an already open page can require closing and reopening that page. A save-file hash baseline and region3 backup are retained privately; saves, captures, keys and learned player translations are not included in the release archive.
