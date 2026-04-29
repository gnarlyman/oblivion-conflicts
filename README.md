# oblivion-conflicts

Pascal scripts that drive the patched headless `TES4Edit_patched.exe` to emit Oblivion (TES4) plugin-conflict information as machine-readable JSON. Three queries, no Python wrapper, no GUI.

The patched binary is a 4-line Delphi patch over upstream xEdit 4.1.5f that makes `-autoload -autoexit` honour `-script:` instead of the GUI ignoring it. See the parent project Reborn (`D:/Modlists/Reborn/`) for the patched-binary build instructions.

## Status

v0.1 — three queries working against the fixture corpus and a real Reborn load order:

| Query | What it answers |
|---|---|
| `query_list`    | Which records does plugin X define-or-override that someone else also touches, and how serious is each conflict? |
| `query_between` | What records do plugins A and B both touch, and which subrecords disagree? |
| `query_record`  | Show the full chain and per-subrecord values for one or more FormIDs. |

## Requirements

- `TES4Edit_patched.exe` (the patched-headless variant).
- A working Oblivion data dir (`-D:`) and a `plugins.txt` (`-P:`).
- For tests: bash (Git Bash on Windows works), python (used to normalise JSON for diff).

## Usage

```bash
TES4Edit_patched.exe -IKnowWhatImDoing -autoload -autoexit \
  -D:"<DataDir>" \
  -P:"<plugins.txt>" \
  -script:scripts/query_<name>.pas \
  --<arg>=<value> ... \
  --out=<output.json>
```

### `query_list --target=<plugin> --out=<path>`

Lists every record the target plugin touches that has at least one other plugin overriding it. Output: array of records with `chain`, `winner_plugin`, `conflict_status`, etc. Filters out `caOnlyOne` records (records nobody else touches).

### `query_between --a=<plugin> --b=<plugin> --out=<path>`

Lists every record both plugins **directly override** (records inherited from a shared master are excluded). Each entry includes per-subrecord conflict status and short summary strings for each side.

### `query_record --formid=<hex> [--formid=<hex> ...] --out=<path>`

Full per-FormID detail: chain, deleted flag, conflict status, every subrecord's value across every chain link.

FormIDs accept both `1E012345` and `0x1E012345` (any case).

## Output schema

All queries share an envelope:

```json
{
  "meta": {
    "tool_version": "0.1.0",
    "xedit_version": "<packed-int>",
    "query": "list",
    "args": { "target": "...", "out": "..." },
    "load_order": ["Master.esm", "..."],
    "started_at": "2026-04-29T10:30:00Z",
    "duration_ms": 12483
  },
  "results": [ ... ]
}
```

On error: `"error": {"code": "...", "message": "..."}` instead of `"results"`. Error codes: `missing_arg`, `bad_arg`, `plugin_not_loaded`, `formid_not_found_any`, `xedit_internal`.

`xedit_version` is `wbVersionNumber`, which the script adapter exposes as a packed integer rather than the display string `4.1.5f`.

## Caveats

- **`ConflictAllForElements` is unreachable from headless JvInterpreter scripts.** Per-subrecord `conflict_status` in `query_between` and `query_record` comes from a local `GetEditValue` comparison: 0 entries → `caUnknown`, 1 → `caOnlyOne` (or `caOverride` for the asymmetric two-way case in `query_between`), multiple all-same → `caNoConflict`, multiple differ → `caConflict`. The overall record-level `conflict_status` still uses the authoritative `ConflictAllForMainRecord`.
- **Struct subrecords (DATA, BMDT, etc.) report empty `edit_value` at the struct level** — JvInterpreter's `GetEditValue` returns empty for compound elements. This means struct-level conflicts are masked by the local approximation. For per-field detail, walk subrecord paths externally; v1 emits the struct-level only.
- **`GetSummary` may return empty strings** under the patched binary. Both `a_summary` and `b_summary` are wrapped in try/except with empty fallback.
- **`load_order` may include `Oblivion.exe`** when running against a real game data dir — xEdit treats the engine as a synthetic plugin. Fixture tests don't trigger this.

## Reborn shortcut

```bash
export OBLIVION_CONFLICTS_XEDIT="D:/Modlists/Reborn/mods/TES4Edit 4.1.5f/TES4Edit 4.1.5f/TES4Edit_patched.exe"
./examples/reborn-shortcut.sh list   --target=MOO.esp --out=/tmp/list.json
./examples/reborn-shortcut.sh record --formid=1E012345 --out=/tmp/rec.json
./examples/reborn-shortcut.sh between --a=MOO.esp --b=OOO.esp --out=/tmp/diff.json
```

## Tests

```bash
export OBLIVION_CONFLICTS_XEDIT="..."   # path to TES4Edit_patched.exe
./tests/run_tests.sh
```

See `tests/README.md` for the snapshot-update workflow.

## License

MPL-2.0. Matches xEdit's licence so the scripts can adapt code from xEdit's bundled `Edit Scripts/` if needed.
