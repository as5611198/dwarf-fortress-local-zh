# Rust player runtime migration

The Steam player runtime is a bundled Windows Rust executable. Node remains a developer dependency only. Keep the loopback v2 API, Lua file protocol, settings v1, API profiles, policy df-zh-3 cache identities, language separation, and private world registry unchanged. Never run an embedded Node/JavaScript runtime.

Main-agent implementation sequence (no delegation):

- [x] Add a failing package contract requiring a native executable and no Node launcher/runtime dependencies.
- [x] Implement Rust settings/public snapshots, provider requests and bounded scheduling; support existing Google and OpenAI-compatible profiles and prompts.
- [x] Implement signed official packages, bounded HTTPS downloads, immutable records, rollback/revocation verification, background deduplication, and activation at a fresh service boundary.
- [x] Implement journal/file adapters, local world-name restoration, native prewarm and opt-in sanitized consensus outbox.
- [x] Replace launcher; build and test with isolated state and no Node in PATH. Compare JS compatibility vectors and verify public-cloud download/offline restart.
- [ ] Build 0.4.0, validate manifests, preserve private hashes, deploy with backups, publish GitHub/Steam, and verify a fresh Steam download.

New modules live in src/df-local-zh-native/broker-rust: common (atomic files and validation), settings, provider, official, shared, equipment, display, service, and main. Security checks stay deterministic. Network errors never include provider bodies, keys or URLs with credentials. HTTPS redirects are disabled. Cloud downloads never serialize private player state. Official snapshots stay pinned for a running service; downloaded updates show pending until the next game launch. The core DLL reuses the Rust signature verifier when loading the local official snapshot, including signed withdrawal handling.

Validation: Rust unit/integration tests, existing developer suites, package no-Node launch/HTTP/Lua settings fixture, clean signed-cloud download and offline reuse for both languages, package hash validation and Steam roundtrip. Title-screen load is distinct from gameplay acceptance.

## Validation of 0.4.0

- Static-CRT release EXE and DLL built successfully; Broker imports only Windows system DLLs. No Node.js/JavaScript engine is embedded.
- Rust workspace: 74 passed, 0 failed, 8 ignored (including the optional online test and existing native integration tests).
- Existing developer suite: 200 passed, 0 failed, 1 optional cloud test skipped. These legacy JS tests are compatibility evidence, not exhaustive Rust behavioral parity.
- Actual player EXE tests: 4/4 passed with PATH restricted to System32, including live signed download and offline reuse of both 502-entry language packages.
- Measured EXE startup: 286–344 ms while tests ran concurrently; minimal source startup/restart: 64/58 ms. HTTPS full download: Hant 1,259 ms, Hans 941 ms; verified offline load: 11 ms for Hant, 18 ms cumulative for both languages. These are observations on this machine/network, not guarantees.
- Native launcher test: starts bundled Rust without Node; Windows job shuts it down when its owning process exits.
- Actual DFHack title-screen smoke: core enabled, Health translated, installed-package script paths, no save loaded. Settings UI fixture passed with real DFHack widgets, including API/prompt drafts and 64/80-column bounds.
- Private API profiles, settings and world-name registry hashes unchanged. Original model cache byte prefix preserved; title-screen translation appended one new record.
- Deployment backup is outside the public repository in `_localization-work/public-release/backup-installed-rust-20261001225659`, containing the old installed package and private state. With the game closed, restore the old package folder to roll back; private state stays in place. Never publish that backup.

Remaining acceptance scope: interactive fortress/adventure gameplay and every Legends/third-party-mod screen have not been retested. Tests cover signature/hash/schema rejection, atomic replacement failure, verified previous-version fallback, deduplicated sync and deferred activation. Forced real-network disconnect and disk-full behavior have not been exercised against the public endpoint.

This repository is the authoritative 0.4.0 source. Earlier `_localization-work/broker` and `_localization-work/df-local-zh-native` development trees were left intact to preserve unrelated local changes; use the build commands in WORKSHOP-PUBLISHING.md, not the old Node deployment scripts.

Steam 0.4.0 update committed successfully to item 3811313433. Independent SteamCMD download returned 61,579,048 bytes; its manifest and all 818 file SHA256 values match the release. Downloaded-EXE tests passed 4/4, including clean cloud sync and offline restart with no Node in PATH. Final observed timings: startup 130–141 ms, Hant/Hans full downloads 1,245/873 ms, offline verified loads 6.75 ms Hant and 10.13 ms cumulative. This verifies the downloaded payload; Steam client subscription/auto-update has not been independently exercised.
