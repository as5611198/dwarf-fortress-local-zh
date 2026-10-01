# Attribution

## DFI18n native engine

DFI18n is used under the MIT license. Source: https://github.com/DFI18n/dfi18n
at commit `083767ce8bea96440f00ebb71c1ac0dfaa4d56f0`.

## Bundled Simplified Chinese data and Traditional conversion

The upstream data repository is https://github.com/DFI18n/dfi18n-data-zh-hans
at commit `2ed0ac42a43375ce1d3d3fcd1403f825be58b3e6`, licensed under
[CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).
Copyright belongs to 矮人要塞中文維基翻譯組翻譯人員. Additional attribution:
WAN1694 and anln666.

This project records permission from `anln666` to modify, perform
Traditional/Simplified conversion, and redistribute the source in free modules
and cloud translation libraries. Changes must be identified and the
non-commercial condition remains in force.

Release 0.3.1 bundles the pinned GitHub data and its Noto font (OFL), not a
copy of a player's installed Workshop package. Changes: OpenCC CN-to-TW
conversion, local terminology/UI corrections, bilingual static dictionaries,
and an independent native loader. Original Simplified data is retained where
no local rule override applies; local overrides are converted to Simplified.
Conversion alone is not proof of terminology or semantic review.

The official R2 library currently published by this project is a separate
project-authored CC0 corpus. It does not silently include unreviewed upstream
data, player cache rows, world names or private runtime state.
