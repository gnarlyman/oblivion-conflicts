# oblivion-conflicts

Headless Oblivion (TES4) plugin-conflict reporting. Drives a patched xEdit binary (built from a fork of TES5Edit) to emit conflict information as machine-readable JSON. No GUI, no Python wrapper.

The patched binary lives at [gnarlyman/TES5Edit](https://github.com/gnarlyman/TES5Edit), branch `feat/tmconflicts`. Two patches over upstream xEdit 4.1.5f:
- A new `-conflicts` CLI tool mode that walks the entire load order and writes a JSON conflict matrix in one launch (~30 s for a 51-plugin modlist).
- A small fix that lets `-autoload -autoexit` honour `-script:` so per-plugin Pascal queries can run headless.

## Status

v0.2 — built-in `-conflicts` sweep + three Pascal scripts for targeted questions:

| Query | What it answers |
|---|---|
| `-conflicts` (CLI mode) | One launch → every conflict-bearing record across the load order. The basis for cache-driven workflows. |
| `query_list`    | Which records does plugin X define-or-override that someone else also touches, and how serious is each conflict? |
| `query_between` | What records do plugins A and B both touch, and which subrecords disagree? |
| `query_record`  | Show the full chain and per-subrecord values for one or more FormIDs. |

## Requirements

- `TES4Edit_patched.exe` (the patched-headless variant).
- A working Oblivion data dir (`-D:`) and a `plugins.txt` (`-P:`).
- For tests: bash (Git Bash on Windows works), python (used to normalise JSON for diff).

## Usage

```bash
# Pascal-script queries (list, record, between):
TES4Edit_patched.exe -IKnowWhatImDoing -autoload -autoexit \
  -D:"<DataDir>" \
  -P:"<plugins.txt>" \
  -script:scripts/query_<name>.pas \
  --<arg>=<value> ... \
  --out=<output.json>

# Built-in -conflicts CLI mode (whole-modlist sweep):
TES4Edit_patched.exe -conflicts -IKnowWhatImDoing -autoload -autoexit \
  -D:"<DataDir>" \
  -P:"<plugins.txt>" \
  -out:<output.json>
```

### `-conflicts -out:<path>`

Walks the entire loaded load order, emits one entry per main record whose conflict status is `caOverride` or higher (skips `caOnlyOne` and `caNoConflict`). Conflict status computed via `ConflictLevelForMainRecord` per record (the cached `mrConflictAll` field is only populated by GUI nav-tree paths and is empty in headless).

Per-record fields: `fid` (load-order FormID hex), `sig` (4-char signature), `edid`, `status` (`caOverride`/`caConflict`/`caConflictCritical`/...), `winner` (filename of winning override), `chain` (master + every override; each entry has `plugin` and `summary` — `summary` is currently empty, populated in a future revision).

Designed for sweep-once-per-modlist workflows: query the resulting JSON via `jq` instead of relaunching xEdit per question. Reborn-Base perf: 51 plugins, 97k records, ~30 s wall clock, 21 MB cache.

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

## Reborn shortcut (run against a real MO2 modlist)

`examples/reborn-shortcut.sh` launches the patched xEdit through MO2 so USVFS overlay is active and xEdit sees every modlist plugin (not just what's in the bare game data dir).

**One-time setup:** in MO2, register the patched binary as a custom executable (Tools → Modify Executables → Add):
- Title: `TES4Edit_patched`
- Binary: `<your install>/mods/.../TES4Edit_patched.exe`
- Arguments / Working directory: leave blank (the wrapper supplies them)

**Usage:**
```bash
./examples/reborn-shortcut.sh conflicts --out=cache/sweep.json
./examples/reborn-shortcut.sh list   --target="Maskar's Oblivion Overhaul.esp" --out=/tmp/moo.json
./examples/reborn-shortcut.sh record --formid=1E012345 --out=/tmp/rec.json
./examples/reborn-shortcut.sh between --a=MOO.esp --b=OOO.esp --out=/tmp/diff.json
./examples/reborn-shortcut.sh /full/path/to/custom.pas --foo=bar --out=/tmp/x.json
```

The first argument is either a query shortcut (`conflicts` / `list` / `record` / `between`) or an absolute path to any `.pas` script. `conflicts` invokes the built-in `-conflicts` CLI mode; the others run a Pascal script via `-script:`. Remaining args go through to xEdit (the wrapper translates `--out=path` → `-out:path` for the conflicts mode since the CLI flag uses single-colon syntax).

**Env-var overrides (defaults match Reborn):** `OBLIVION_CONFLICTS_MO2`, `OBLIVION_CONFLICTS_EXE_TITLE`, `OBLIVION_CONFLICTS_DATA`, `OBLIVION_CONFLICTS_PROFILE`, `OBLIVION_CONFLICTS_PLUGINS`. Run `./examples/reborn-shortcut.sh --help` to see the resolved values.

The wrapper auto-applies an internal-quoting trick to args containing spaces because MO2 forwards trailing CLI args via `args.join(" ")` with no requoting (see `processrunner.cpp:620` in MO2 source). Callers don't need to know — pass args naturally.

## Querying the sweep cache

The `-conflicts` sweep writes one JSON file. `jq` answers most questions directly — no CLI tool needed.

**What does plugin X override?**

```bash
jq '.results[] | select(.winner == "APW - Conflict Resolution.esp")' cache/sweep.json
```

**Grouped by overridden plugin (with category counts):**

```bash
jq '[.results[] | select(.winner == "APW - Conflict Resolution.esp")]
    | group_by(.chain[-2].plugin)
    | map({plugin: .[0].chain[-2].plugin,
           count: length,
           sigs: ([.[].sig] | unique)})' cache/sweep.json
```

**Who overrides records in plugin X?**

```bash
jq '.results[] | select(any(.chain[]; .plugin == "PSMainQuestDelayer.esp")
                        and .winner != "PSMainQuestDelayer.esp")' cache/sweep.json
```

**Category roll-up of one plugin's overrides:**

```bash
jq '[.results[] | select(.winner == "APW - Conflict Resolution.esp")]
    | group_by(.sig)
    | map({sig: .[0].sig, count: length})' cache/sweep.json
```

**The high-stakes records (caConflict + caConflictCritical):**

```bash
jq '.results[] | select(.status == "caConflict" or .status == "caConflictCritical")' cache/sweep.json
```

For per-subrecord drill-down on a specific record (since the sweep only emits record-level status), use `query_record`:

```bash
./examples/reborn-shortcut.sh record --formid=1E012345 --out=/tmp/r.json
```

## Tests

```bash
export OBLIVION_CONFLICTS_XEDIT="..."   # path to TES4Edit_patched.exe
./tests/run_tests.sh
```

See `tests/README.md` for the snapshot-update workflow.

## License

MPL-2.0. Matches xEdit's licence so the scripts can adapt code from xEdit's bundled `Edit Scripts/` if needed.
