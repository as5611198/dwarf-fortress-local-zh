# Lua runtime journal framing

Continue A006/A028/A031 on candidate source; no installation/publishing or player-state mutation.

- [x] Reproduce >256 KiB response/failure loss, false overlong-line suffixes, UTF-8 boundaries and I/O recovery (old stress run stopped after verified excessive CPU).
- [x] Add bounded incremental byte framing (256 KiB reads, 8 MiB record ceiling aligned with Broker history), persistent discard state and reliable handle cleanup.
- [x] Retain a response batch until native import/verification succeeds; isolate world/language/retry generation resets.
- [x] Replace quadratic JSON string concatenation for this pipeline, validate Unicode escapes and preserve duplicate-key semantics.
- [x] Repair duplicate-translation verification and retire old short aliases when the translation changes.
- [x] Run new tests and existing runtime/display regression fixtures with bundled Lua; record source hashes and evidence.
- [x] Document remaining file-identity/generation/ack rotation, startup retry and full gameplay acceptance requirements.
