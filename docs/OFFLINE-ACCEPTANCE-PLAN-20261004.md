# Vanilla offline acceptance sample

This plan is recorded before inspecting the new modes audit. The target remains
at least 90% vanilla content usable in Chinese without AI, followed by Steam and
GitHub publication. The previous raw/dictionary regressions are not the coverage
denominator. A sample supports a scoped coverage estimate, not an exhaustive
claim about every possible generated sentence.

## Sampling and scoring

- Use a fixed, hash-recorded 0.5.11 candidate, no AI, no downloaded translations, and no
  learned player cache. Record package hash, settings, game version and world.
- Cover all three modes. Within fortress, include construction/jobs, stocks and
  trade, residents/personality/health, military, and announcements. Within Legends,
  include navigation, figures, sites/entities, artifacts, and events. Within
  adventure, include creation, exploration, conversation, combat/status, and
  journal. Missing categories remain incomplete, never silently excluded.
- Capture original complete text and its displayed translation, including links,
  palette and line breaks. Native trace fragments supplement complete-source
  captures; neither memory CJK counts nor local-only lookup alone prove rendering.
- Choose visible pages without consulting their translation results. For lists,
  select the first available entry then a middle and final entry when practical;
  record unavailable pages. Retain every captured miss. New fixes turn affected
  examples into regression data, requiring additional independent samples.
- Count distinct complete linguistic units per category. Repeated navigation
  labels do not dominate long generated prose. Exclude only numbers, input-key
  glyphs, and player-authored literals; record exclusions. Generated proper names
  are reported separately and do not excuse untranslated surrounding prose.
- A success requires correct Chinese meaning and preserved essential UI behavior,
  not merely one CJK character. Partial, incorrect, pending or unverified output
  is a miss. Record first-display and settled behavior separately.
- Report each category and mode independently, plus an equal-mode/equal-category
  summary explicitly labeled as this representative UI benchmark. Do not call it
  an exhaustive whole-game percentage or change weights after observing results.
- Collect at least 30 distinct assessable units per available category before a
  release decision, using additional independent pages/worlds as necessary. A
  category below 90% remains reported, but is not an independent release veto:
  the user's threshold is 90% overall under the declared equal weights. This
  clarification is recorded before computing the overall acceptance score. A sampled
  90% point estimate with substantial uncertainty is insufficient for a broad
  marketing claim; report counts and limitations with the release evidence.

## Other release gates

Verify cold startup, colors/links, large-population unpaused performance, and
save/reload in isolated copies. Restore player settings/cache and hash-check
protected saves after each session. Review the actual release file list for
private state and unfinished experiments. Finalize changelog/archive/manifests,
then publish Steam and GitHub, preserving the requested GitHub exclusion of
cover and description changes.

## Current audit

`live-ui-0511-modes-20261004` begins with Legends and adventure to fill previously
missing mode evidence. It is a partial audit until all categories above have
evidence. No score is assumed from the candidate's existing regression tests.
