# Offline current personality and value quotes

The resident overview chooses a random built-in quote when opened. The previous
candidate only carried a small hand-selected set, so a new choice could remain
English even when the resident's traits, values and preferences were Chinese.
The observed example was `"Yes, I want more.  Is that so bad?"`.

This change adds reviewed Traditional translations for 254 complete literals
from the installed 0.53.16 personality/value dialogue block. The source inventory
was frozen before authoring translations, independently of player caches or
dictionary hits. It retains exact interior spaces and even the original
`I'm feel like I'm about to snap.` spelling. Fifty incomplete or contextual
fragments in the same block are excluded. This bounded inventory does not cover
every quote elsewhere in the executable, such as all emotion variations or
dialogue assembled around names.

The source executable SHA-256 is
`205770918fd54c96cbbcf89223ebd449e2e113c7c873ed81177c4511a3450db7`;
the inspected byte interval is `[23476352, 23491512)`. No executable or
player-specific data is shipped with this inventory.

`offline-current-quotes.json` is authoring data. The existing package builder
emits exact quoted CSV keys with Traditional corner quotation marks, and uses
the existing phrase-aware OpenCC pipeline for Simplified Chinese. Existing
hand-polished quotes retain their wording; an overlapping practical-advice entry
was aligned with the existing life dictionary. There is no new runtime parser,
per-frame dictionary scan, I/O, network request or name stored in shipped data.

The failing builder fixture and packaged Broker test reproduced the missing
quote before the change. Nine relevant Node tests pass. Seven existing package
checks pass, including the quote population diagnostic; the dedicated semantic
test also passes separately with 14 bilingual checks and an unknown-tail refusal.
That fixture uses the package's correct Simplified `试着` spelling explicitly:
Rust's character-only conversion helper cannot reproduce OpenCC's phrase-aware
`試著` conversion and is not the expected-data authority for that example.

The actual native static lookup and an empty-state Broker each return all 508
bilingual quote outputs exactly, with zero worker/provider submissions. These
are integration regressions, not an independent whole-game coverage estimate.
The valid 913-file candidate manifest is
`70be54a778c644b18b7ee2f6e94caef530e5324a1fd680a83549b5499474b18a`.
Compared with the preceding resident candidate, only the two generated
personality dictionaries changed; the Native and Broker release binaries are
identical.

Cold-load checks with AI, cloud downloads and sharing disabled confirmed both
installed copies against the manifest, and the in-process release DLL passed
508 exact bilingual lookups. The same previously missed quote appeared during
normal reopening of the actual resident overview and rendered as
`「沒錯，我還想要更多。這有那麼糟嗎？」`. Its first recorded native selection and
settled selection were identical Chinese with the white palette preserved;
the screenshot also showed the correct complete quote at 50 graphics FPS.
This is a specific render-hook observation, not a guarantee about the very first
visible frame of every page or large-population performance.

The game was normally exited without saving the paused test clone. Both clones
and their source snapshots are unchanged and archived. Player settings, legacy
cache and overlay configuration were restored; all 10,839 protected original
save files are unchanged with no missing or extra files outside the clones.

Private evidence lives in `_localization-work`: the frozen source inventory,
254-source corpus, Native/Broker outputs, diagnostic summary, red/green logs,
and the `live-ui-0511-quotes-final-20261005` session. The whole-game 90% target
remains unestablished and nothing has been published for this candidate.
