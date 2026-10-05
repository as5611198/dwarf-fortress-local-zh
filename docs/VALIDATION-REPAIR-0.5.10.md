# 0.5.10 acceptance evidence correction

The previous candidate ZIP passed file integrity checks, but the first live
report was not valid evidence of loaded-fortress performance. Its Lua probe
called local lookup from any screen, did not require a loaded world/map, and
sampled FPS on the title/save menu. The `world` field was absent. The finalizer
checked only version, AI setting, count and failures. A separate local copy of
the finalizer removed the save-integrity assertion after two region4 files
differed. Those differences were not explained or restored; permitting them
did not establish save integrity.

## Repair

- `src/validation/offline-live-probe.lua` now writes a running record first,
  requires the designated save with both world and map loaded in dwarfmode,
  checks AI is disabled, and repeats the context check at every FPS sample.
  It restores the original native language even when translation checks fail.
- `src/validation/verify_offline_probe.py` checks a per-run ID, start/finish
  time, terminal status, full bilingual corpus membership with multiplicities,
  nonempty Chinese results, negative controls and at least six time-advancing
  in-world FPS samples. Protected-save changes, additions and missing files
  all fail acceptance; there is no reviewed-save bypass.
- Eight Python regression tests first failed against the old permissive
  acceptance conditions, then passed with the strict validator. A real menu
  invocation was rejected with `World and map must be loaded` before lookup.
- The old local `finalize-reviewed-save.py` entry point is disabled. Its source
  and reports are retained under the private verification evidence directory.
  The previous final-verification report is marked invalidated for acceptance.

## Fresh run

An exact copy of region3 was made as `region3-offline-audit-20261004` before
launch. Original region3 and region4 were backed up with byte/hash verification.
The probe observed `worldLoaded=true`, `mapLoaded=true`, `dwarfmode/Default`,
and AI disabled on the isolated fortress. DFHack reports a virtual game/save
path even when the physical save is in AppData; the probe records both the
reported path and save folder identity, while the run descriptor records the
physical backup/clone path.

- Installed version: 0.5.10; 310 bilingual local lookups, no missing result;
  two unsupported-prose negative controls passed.
- Six paused-fortress FPS observations over five seconds: 50, 50, 50, 50, 49, 50.
- Normal game menu quit without saving, followed by normal application exit.
  No process termination was used in this run.
- All 10,839 pre-existing save files matched this run's baseline. Only the
  intentionally created isolated copy was added; it was archived out of the
  save root after game exit. All original saves remain present.
- Both installed package copies and the previous ZIP match the 865 package
  files, including manifest. ZIP SHA-256 remains
  `e980bc2d48d8fdb7ac3c69c13669ded8b9e542d25772977fbe9a88ea659ad633`.

Private evidence is under the game directory
`_localization-work/verification-repair-20261004/`. It includes saves and captured
player data and must not be published as a directory/archive.

## Repeating the checks

Run from repository root:

```powershell
python -m unittest discover -s src/validation -v
python src/validation/verify_offline_probe.py <private-run-directory>
```

The run directory must contain `expected.json` with a unique runId, version,
startedAt and expected save folder in world; `audit-corpus.json` containing
page objects with source arrays; a fresh `live-probe.json`; and a freshly hashed
`save-verification.json` with baselineRunId, protectedFiles, changed, missing,
added and unexpected. The validator checks evidence consistency; the caller
must create real baselines before launch and compute actual file differences
after quitting. Never hand-author empty save-difference arrays.

Invoke the saved Lua probe via `loadfile(path)(run_directory)` from DFHack only
after independently confirming the correct isolated fortress. Check its JSON
terminal state; dfhack-run exit code alone does not establish success.

## Remaining limits

This establishes a short paused-fortress regression, not whole-game 90%
coverage, an unpaused soak, or semantic correctness of every returned Chinese
sentence. No payload change or external publication was performed in this step.
The earlier region4 world.sav and performance-counter differences still lack
a matching earlier backup and remain unresolved historical evidence. This
new clean run does not retroactively prove that earlier run preserved saves.

Next work: audit semantic output (the captured item encrustation example
currently renders diamonds as the geometric shape), collect independent
coverage samples, and address remaining lifecycle/long-session audit items.
