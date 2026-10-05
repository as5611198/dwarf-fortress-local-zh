# Shortcut audit and 0.5.0 release plan

**Goal:** Remove conflicting module shortcuts and publish version 0.5.0 to existing Steam item 3811313433 with the user's latest local description and cover.

**Architecture:** Compare Lua actions with native interface.txt and live DFHack bindings, including screen scope and text-input interception. Change only conflicting controls. Build a standalone package from repository sources and verified native binaries, then verify the uploaded content by downloading it again.

**Tech Stack:** Lua/DFHack, Rust native runtime, Node package builder, SteamCMD.

**Spec:** User request in this conversation, including the correction that description/cover changes are local and must be uploaded.

## Constraints

- Main agent only; no subagents. Preserve unrelated changes and private player state.
- Public version 0.5.0; update existing Workshop item, never create another.
- Use latest local bilingual description and dwarf-on-right cover; do not restore old metadata.
- Credentials remain private; use existing authenticated Steam tooling if available.

## Tasks

- [x] Inventory shortcuts in scripts and native input hooks, compare native and DFHack bindings, record scope and input precedence.
- [x] Replace confirmed global collisions; verify focused text input and buttons, Enter/newline behavior, history pagination and journal refresh without modifying a player's save.
- [x] Build source-only 0.5.0 package, verify manifest, binary provenance, secrets exclusion, latest cover and description, and relevant regression suites.
- [x] Create ZIP and SHA256, upload existing Steam item with prepared metadata, independently download and compare payload hashes and public metadata.
- [x] Record evidence and remaining manual gameplay limitations; report the published result.

## Completed evidence

- Final 0.5.0 has 847 payload files; Steam roundtrip matches every hash and manifest. Local Traditional description and dwarf-on-right preview are published and verified.
- GitHub v0.5.0 is published at commit dd7549a1bc3b87218fec0d0ae12b4f10f3973713. ZIP and checksum match server SHA256; main and tag both match the release commit.
- CI run 37088714062 completed successfully for broker and native jobs. Node 201 passed / 1 skipped; Lua 33 passed. Local native core 67 passed / 5 ignored.
- First CI run exposed missing SDL runtime path; workflow fixed using already-bundled DLLs. Next run exposed response/acknowledgement mailbox race; deterministic Lua regression reproduced it and final Lua/client protocol waits for both reply and cleanup before resubmitting.
- Installed 0.5.0 updated without binary replacement or save changes. Isolated tests do not substitute for all physical keyboard/IME/DPI combinations or extended gameplay acceptance.
- Detailed local release evidence: `_localization-work/release-0.5.0-20261003/release-verification.json`. Public shortcut report: `docs/SHORTCUT-AUDIT-0.5.0.md`.
