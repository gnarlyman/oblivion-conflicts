#!/usr/bin/env bash
# run_tests.sh - snapshot tests for the oblivion-conflicts query scripts.
#
# Usage:
#   OBLIVION_CONFLICTS_XEDIT="/path/to/TES4Edit_patched.exe" ./tests/run_tests.sh
#
# Set UPDATE_SNAPSHOTS=1 to overwrite the expected files instead of diffing.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="$REPO_ROOT/tests/fixtures/data"
PLUGINS="$REPO_ROOT/tests/fixtures/loadorder.txt"
SCRIPTS_DIR="$REPO_ROOT/scripts"
EXPECTED_DIR="$REPO_ROOT/tests/fixtures/expected"
TMP_DIR="$REPO_ROOT/tests/.tmp"

if [[ -z "${OBLIVION_CONFLICTS_XEDIT:-}" ]]; then
  echo "ERROR: OBLIVION_CONFLICTS_XEDIT env var must point at TES4Edit_patched.exe" >&2
  exit 2
fi
if [[ ! -f "$OBLIVION_CONFLICTS_XEDIT" ]]; then
  echo "ERROR: $OBLIVION_CONFLICTS_XEDIT does not exist" >&2
  exit 2
fi
if ! command -v python >/dev/null 2>&1; then
  echo "ERROR: python is required for snapshot normalisation" >&2
  exit 2
fi

mkdir -p "$TMP_DIR"

UPDATE="${UPDATE_SNAPSHOTS:-0}"
FAILED=0

normalise_to() {
  local input="$1" output="$2"
  python - "$input" "$output" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src))
meta = data.get('meta', {})
for k in ('started_at', 'duration_ms', 'tool_version'):
    meta.pop(k, None)
args = meta.get('args', {})
args.pop('out', None)
json.dump(data, open(dst, 'w'), indent=2, sort_keys=True)
PY
}

run_one() {
  local name="$1"; shift
  local script="$1"; shift

  local actual="$TMP_DIR/${name}.json"
  local expected="$EXPECTED_DIR/${name}.json"
  local normalised="$TMP_DIR/${name}.normalised.json"

  echo "=== $name ==="
  rm -f "$actual" "$normalised"

  "$OBLIVION_CONFLICTS_XEDIT" -IKnowWhatImDoing -autoload -autoexit \
    -D:"$DATA_DIR" \
    -P:"$PLUGINS" \
    -script:"$SCRIPTS_DIR/$script" \
    --out="$actual" \
    "$@"

  if [[ ! -s "$actual" ]]; then
    echo "FAIL: $name produced no output" >&2
    FAILED=1
    return
  fi

  normalise_to "$actual" "$normalised"

  if [[ "$UPDATE" = "1" ]]; then
    cp "$normalised" "$expected"
    echo "  updated: $expected"
    return
  fi

  if [[ ! -f "$expected" ]]; then
    echo "FAIL: no expected snapshot at $expected (run with UPDATE_SNAPSHOTS=1)" >&2
    FAILED=1
    return
  fi

  if diff -u "$expected" "$normalised"; then
    echo "  ok"
  else
    echo "FAIL: $name diverges from $expected" >&2
    FAILED=1
  fi
}

run_one query_list query_list.pas --target=OverrideA.esp
run_one query_record query_record.pas --formid=00001001 --formid=00001002

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED" >&2
  exit 1
fi
echo "All snapshot tests passed."
