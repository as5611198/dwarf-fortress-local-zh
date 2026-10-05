# Startup history recovery

Candidate source only; no publishing, player-state changes, or journal rotation in this patch.

- [x] Reproduce response/failure history being ignored after transient Windows sharing violations.
- [x] Load bounded history in a supervised task, commit only a complete snapshot, gate runtime dispatch until recovery, and keep settings/status service responsive.
- [x] Retry I/O/task failures with capped backoff, watch progress rather than total duration, and abort owned work on shutdown.
- [x] Filter recovered history against current world/language/retry generation and replay requests after recovery.
- [x] Display loading/retrying states in the existing status panel without changing row geometry.
- [x] Verify recovery, fault handling, cancellation, status UI, Broker release tests/build, and record remaining rotation/acceptance work.
