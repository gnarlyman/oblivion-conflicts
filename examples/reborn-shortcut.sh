#!/usr/bin/env bash
# Wrapper that pre-fills -D: and -P: for Reborn's Stock Game data dir.
#
# Usage:
#   ./reborn-shortcut.sh list   --target=MOO.esp --out=/tmp/list.json
#   ./reborn-shortcut.sh record --formid=1E012345 --out=/tmp/rec.json
#   ./reborn-shortcut.sh between --a=MOO.esp --b=OOO.esp --out=/tmp/diff.json
#
# Override defaults via env vars:
#   XEDIT (or OBLIVION_CONFLICTS_XEDIT), DATA, PLUGINS, PROFILE

set -euo pipefail

XEDIT="${XEDIT:-${OBLIVION_CONFLICTS_XEDIT:-D:/Modlists/Reborn/mods/TES4Edit 4.1.5f/TES4Edit 4.1.5f/TES4Edit_patched.exe}}"
DATA="${DATA:-D:/Modlists/Reborn/Stock Game/Data}"
PROFILE="${PROFILE:-Reborn-Base}"
PLUGINS="${PLUGINS:-D:/Modlists/Reborn/profiles/$PROFILE/plugins.txt}"
SCRIPTS_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <list|between|record> [--script-arg=value ...]" >&2
  exit 2
fi

QUERY="$1"; shift
SCRIPT="$SCRIPTS_DIR/query_${QUERY}.pas"
if [[ ! -f "$SCRIPT" ]]; then
  echo "no such query script: $SCRIPT" >&2
  exit 2
fi

"$XEDIT" -IKnowWhatImDoing -autoload -autoexit \
  -D:"$DATA" -P:"$PLUGINS" \
  -script:"$SCRIPT" "$@"
