# Translation journal compaction plan

Goal: safely reclaim superseded valid translations while preserving every effective cached value and opaque bytes.

Scope: startup maintenance of `translations.jsonl`; runtime request/response/UI journals still need a generation/ack protocol and are not modified by this step. Main agent executes; no publishing, installation or player-state mutation during validation.

- [x] Regression: a journal above the startup threshold with many revisions of one valid key should shrink, retain the latest valid value, reopen offline, and accept later appends. Observe failure first.
- [x] Add `journal_compaction.rs`: freshly scan the authoritative journal into file-backed temporary SQLite offset tables, retaining last validated row per key and every opaque/invalid row. Preserve original retained-byte order; no reliance on potentially stale derived index contents.
- [x] For >=16 MiB journals, check on startup if no previous maintenance watermark, source shrank, same size with changed digest, or at least 8 MiB growth. Replace only if >=1 MiB and >=25% reclaimable. Persist the check watermark to avoid repeated expensive no-benefit scans on each restart.
- [x] Stage to a unique sibling temp file; compare source digest and metadata, sync staged output, then atomically replace. Failures before replace preserve the original. Fingerprint mismatch on restart rebuilds derived cache; cleanup owned temp artifacts. Log maintenance errors and re-synchronize so a failure never becomes an AI miss.
- [x] Tests: latest valid/key/language semantics; invalid/unknown/oversized/truncated lines retained byte-for-byte; untouched journal when no saving; injected replace failure; stale-source rejection; index failure after successful replacement/reopen; unchanged startup skips maintenance.
- [x] Run final Broker tests and explicit release benchmark with static CRT using short target path `_localization-work/rust-durable`; build and update evidence/docs. Keep remaining A028 journals and other audit items open.
