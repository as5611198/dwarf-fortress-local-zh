# Legends relationship and occupation repair

The original Legends entry reproduced a permanent pending paragraph with AI,
cloud downloads and contributions disabled. The native text box used link type
`-1` for a non-clickable child label. Capture incorrectly submitted that label
as a clickable DFL token. The protocol correctly rejected it, but the reader
ignored the terminal status and continued displaying pending text.

Capture now protects only supported native targets (integer type 0–11 and a
nonnegative finite integer ID). Unsupported records remain literal text. It also
retains original Unicode/color spans with only valid click identities. Terminal
rejection displays those spans; transient queue-write failure displays them and
retries with a one-second delay. AI-disabled original responses explicitly use
the native spans. This preserves colors instead of recoloring source prose as a
translation. Language/API changes invalidate both rendered parts and retry state.
The protocol validator remains strict and no native target or text is fabricated.

The shared bounded history composer now covers observed merchant/tavern-keeper
appointments, master-of-beasts appointments, venue/site work, faithful worship,
spouse/wife/husband/lover metadata, only children, site occupations and active
office ranges (`N to present` and `N to M`). Existing hyphenated ranges remain
supported. Unknown roles, malformed/backward ranges and unknown trailing prose
still reject the entire sentence. Wording follows the existing profession terms.

## Validation

- Both pending and color regressions failed before their fixes. Five source Lua
  fixtures pass: narrative layout, legacy Legends restoration, rich runtime,
  queue I/O recovery and poll cost. They exercise Unicode, original colors,
  real/stale click identity, wrapping, terminal rejection and transient retry.
- Eleven history tests pass, including 16 complete bilingual expected outputs
  and negative boundary cases. The Rust workspace also passed before the final
  profession-wording alignment; its ordinary run excludes opt-in package tests.
- New packaged Native and an empty-state Broker each pass 32 exact bilingual
  relationship/occupation checks, with zero worker/provider submissions.
- The hot-loaded source regression shows the formerly pending child label as
  readable source. All 330 native words and 56 link records match the pre-repair
  snapshot exactly. That hot reload is diagnostic/regression evidence only.
- That baseline session was normally exited and restored: all 10,839 protected
  original save files and both clones are unchanged, and player settings/cache/
  overlay configuration are restored.

## Candidate and coverage limits

The new private 0.5.11 candidate has 913 manifest-verified files. Compared with
the previous quote candidate, five files changed: Native/Broker binaries,
narrative/runtime scripts, and the packaged narrative-layout fixture. Both
binaries use static CRT builds; their imports require no Visual C++ runtime DLL.
The manifest SHA-256 is
`e9c4cf4cde7f5fb1b250f77df4bb2ed71496fe450b638a14bc10f231785eb7b5`.

The original-world baseline freezes 37 capture/instruction artifacts and 192
visible observations (59 distinct sources). It is incomplete development data:
prior-source overlap is not fully audited and true first-visible-frame evidence
is absent. Fixed observations become regressions and do not establish 90%
whole-game coverage. Biographies with unlinked names, trade outcomes, battle
names and some generated linked captions remain recorded misses. A literal
unsupported relationship remains readable English until its non-clickable span
has a safe local translation path; it is not counted as translated.

Cold-load verification used the new package with fresh player state and all
online translation disabled. The loaded DLL passed the same 32 exact bilingual
checks; Native ready/pending/submission counters remained `[0,0,214]`. Merchant,
master-of-beasts, spouse, wife, lover, active office range, tavern-keeper, venue
work and Related Sites were observed in Chinese. The previously pending child
was readable original English with no fabricated target. All 330 native words
and 56 link records matched the baseline. Valid native dispatch opened entity
35 (The Steamy Kingdoms); the first coordinate click was ineffective, so this
establishes dispatch behavior rather than direct coordinate-click acceptance.

Settled graphics FPS was 49–50. Initial page-transition captures were lower;
this does not establish first-frame or large-population/unpaused performance.
The game was normally exited, both unchanged clones were archived and all
10,839 protected original files, settings, caches and overlay settings were
restored. Evidence is in private `live-ui-0511-legends-repair-20261005`.
No commit, GitHub push or Steam upload has been performed for this candidate.
