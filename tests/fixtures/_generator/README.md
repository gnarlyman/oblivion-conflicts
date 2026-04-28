# Fixture generator

This directory contains `generate_fixtures.pas`, which builds the three fixture plugins used by the test suite (`Master.esm`, `OverrideA.esp`, `OverrideB.esp`).

## When to re-run

Only re-run if:
- You're setting up a fresh repo and `tests/fixtures/data/*.esp` is empty
- You've changed the schema of records you're testing against and need new fixtures
- Existing fixtures got corrupted or deleted

The generated `.esp/.esm` files ARE committed to the repo so the test suite runs from a fresh clone without re-running this script.

## How to run

1. Launch TES4Edit (e.g., `D:\Modlists\Reborn\mods\TES4Edit 4.1.5f\TES4Edit 4.1.5f\TES4Edit.exe`).
2. In xEdit's load dialog, **uncheck everything** (or click Cancel — xEdit will start with no plugins loaded). If xEdit refuses to start with zero plugins, check just `Oblivion.esm` and proceed; we'll work in a separate empty namespace.
3. Menu: **Other → Run script...** → select this file (`generate_fixtures.pas`).
4. Wait for the "Done" message in xEdit's message log.
5. Menu: **File → Save** (or close xEdit and accept the save prompts for all three new files).
6. xEdit saves the new files to its configured Data directory (the same one you launched against). Find them and **move/copy** them to `tests/fixtures/data/` in this repo.
7. Verify with: `ls tests/fixtures/data/` should show `Master.esm`, `OverrideA.esp`, `OverrideB.esp`.

## What it builds

- **Master.esm** — root master with 4 records:
  - `TestSword` (WEAP, FormID 0x001001) — base stats
  - `TestArmor` (ARMO, FormID 0x001002) — base stats
  - `TestChest` (CONT, FormID 0x001003) — 1 inventory entry (TestSword)
  - `TestDagger` (WEAP, FormID 0x001004) — to be deleted by OverrideA

- **OverrideA.esp** — depends on Master.esm. Overrides:
  - TestSword: DATA changes (Damage 5→7, Value 10→15)
  - TestArmor: DATA change (Armor 15→20)
  - TestDagger: marked deleted

- **OverrideB.esp** — depends on Master.esm. Overrides + injects:
  - TestSword: DATA changes (Damage 5→6, Speed 1.0→1.2) — different fields than A → 3-way conflict
  - TestChest: adds a second CNTO entry (TestArmor x2) — repeating subrecord case
  - TestInjected (WEAP, FormID 0x001099, master byte = 00) — injected record (master byte points at Master.esm but Master doesn't have this record)

## If the script fails

The script uses xEdit script APIs (`AddNewFileName`, `wbCopyElementToFile`, `SetLoadOrderFormID`, etc.) whose exact signatures vary between xEdit versions. If the script errors out, capture the error message from xEdit's log and report it — we may need to adjust the script for your xEdit version.
