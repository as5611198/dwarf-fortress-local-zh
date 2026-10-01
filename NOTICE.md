# Source Provenance

Based on DFI18n, https://github.com/DFI18n/dfi18n, commit
083767ce8bea96440f00ebb71c1ac0dfaa4d56f0 (develop).
MIT copyright and license are retained in LICENSE.

The initial copy also retains the user's preexisting dense-row DFHack hook
changes from the local upstream checkout. That checkout remains unchanged.

Local native core changes implement synchronous exact dictionary/completed
cache lookup, bounded misses and integration with the local translation Broker.
This source fork is distinct from the opaque Workshop 0.2.4 DLL.

Chinese search uses pinyin 0.11 (MIT), https://github.com/mozillazg/rust-pinyin.
Dynamic script conversion uses ferrous-opencc 0.4 (Apache-2.0),
https://github.com/apoint123/ferrous-opencc, with embedded OpenCC dictionaries
(Apache-2.0), https://github.com/BYVoid/OpenCC. License texts are included in
third-party-licenses. The local Broker also retains opencc-js and its licenses.

The upstream DFI18n Simplified Chinese data repository is tracked separately in
`DFI18N-DATA-ZH-HANS-LICENSE.md` and `ATTRIBUTION.md`. It is CC BY-NC 4.0, with
permission from `anln666` for modification, Traditional/Simplified conversion,
and redistribution in free modules and cloud translation libraries. This does
not relicense the source or authorize commercial redistribution.
