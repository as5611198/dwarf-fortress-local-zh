# Offline first translation, 0.5.3

Approved goal: common vanilla screens should display Chinese immediately with AI
disabled and no learned caches. 90% is a target to measure, not a whole-game claim.

Implementation:
1. Compile finite, root-reachable grammar alternatives into a bounded exact index
   during data loading. Reject dynamic replacers, recursive branches and ambiguous
   results; retain the original worker for everything outside that index.
2. Add independently authored personality sentences and value clauses. Compose
   only explicitly marked sentences/clauses, preserving original palette and
   paragraph boundaries. Unknown clauses fail the entire lookup.
3. Expose local-only lookup to Lua ahead of saved model/display responses, while
   keeping explicit user overrides first. Never run general grammar from this API.
4. Verify cold first lookups, unseen combinations, negative cases, UTF-8 and
   semantic colors. Use source-only historical captures as development evidence;
   report sample coverage honestly. Once a capture is used to add translations,
   it is development/regression data, not an independent held-out benchmark.
5. Run Rust/Node and Lua regressions, build a bilingual local 0.5.3 candidate,
   validate all manifest hashes, and test the deployed runtime if available.

Performance boundary: no render-time disk access, dictionary scans or unbounded
memoization. Compilation has operation/entry/string limits. Runtime work is bounded
by input length and direct hash lookup. No player cache, save or API key deletion.

No publishing is included in this approval. Existing cover and description edits
remain untouched.
