# Journal reader hardening

Scope: candidate source only; preserve player state and existing distribution. No rotation or publishing in this change.

- [x] Reproduce request-reader loss after larger atomic replacement, oversized-line suffix acceptance and swallowed I/O errors.
- [x] Bound request reads, preserve UTF-8 fragments/discard state, track file identity, surface errors and align record size with legal Legends requests.
- [x] Verify request regression tests and the real offline 64-link request pipeline.
- [x] Reproduce startup replay stopping at invalid UTF-8 before healthy completed rows.
- [x] Share bounded byte framing with response/failure snapshot replay; yield between chunks and report rejected rows/I/O errors.
- [x] Verify malformed/oversized/incomplete records, snapshot end and scheduling boundaries, then rerun Broker release tests/build.
- [x] Record evidence and remaining rotation/UI reader limitations in the audit.
