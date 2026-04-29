#!/usr/bin/env bash
# Run an oblivion-conflicts query (or any other .pas script) against
# a real MO2 modlist via USVFS. Defaults to Reborn; override the
# OBLIVION_CONFLICTS_* env vars below for any other modlist.
#
# Usage:
#   ./reborn-shortcut.sh list   --target=MOO.esp --out=/tmp/list.json
#   ./reborn-shortcut.sh record --formid=1E012345 --out=/tmp/rec.json
#   ./reborn-shortcut.sh between --a=MOO.esp --b=OOO.esp --out=/tmp/diff.json
#   ./reborn-shortcut.sh /full/path/to/custom.pas --foo=bar --out=/tmp/x.json
#
# Env var overrides (all optional; defaults match Reborn):
#   OBLIVION_CONFLICTS_MO2         path to ModOrganizer.exe
#   OBLIVION_CONFLICTS_EXE_TITLE   registered MO2 custom-exec title
#   OBLIVION_CONFLICTS_DATA        game data dir (-D: target)
#   OBLIVION_CONFLICTS_PROFILE     MO2 profile name (used for plugins.txt default)
#   OBLIVION_CONFLICTS_PLUGINS     plugins.txt path (-P: target)
#
# Why this script exists:
#   Plain xEdit can't see MO2-overlaid plugins; you must launch through MO2
#   so USVFS hooks the process. MO2 forwards trailing CLI args to the
#   launched executable via args.join(" ") with NO requoting (see MO2
#   processrunner.cpp:620), so any arg whose value contains spaces gets
#   mangled. The requote() helper below adds internal "..." quotes that
#   survive the join, get reconstructed by xEdit's CommandLineToArgvW.

set -euo pipefail

MO2="${OBLIVION_CONFLICTS_MO2:-D:/Modlists/Reborn/ModOrganizer.exe}"
EXE_TITLE="${OBLIVION_CONFLICTS_EXE_TITLE:-TES4Edit_patched}"
DATA="${OBLIVION_CONFLICTS_DATA:-D:/Modlists/Reborn/Stock Game/Data}"
PROFILE="${OBLIVION_CONFLICTS_PROFILE:-Reborn-Base}"
PLUGINS="${OBLIVION_CONFLICTS_PLUGINS:-D:/Modlists/Reborn/profiles/$PROFILE/plugins.txt}"
SCRIPTS_DIR="$(cd "$(dirname "$0")/../scripts" && pwd)"

if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  cat >&2 <<EOF
usage: $(basename "$0") <query | script.pas> [--key=value ...]

queries:
  list, record, between   resolves to scripts/query_<name>.pas
  /path/to/file.pas       absolute path to a custom Pascal script

env vars (all optional, defaults match Reborn):
  OBLIVION_CONFLICTS_MO2         current: $MO2
  OBLIVION_CONFLICTS_EXE_TITLE   current: $EXE_TITLE
  OBLIVION_CONFLICTS_DATA        current: $DATA
  OBLIVION_CONFLICTS_PROFILE     current: $PROFILE
  OBLIVION_CONFLICTS_PLUGINS     current: $PLUGINS
EOF
  exit 2
fi

QUERY="$1"; shift
case "$QUERY" in
  *.pas)         SCRIPT="$QUERY" ;;
  list|record|between) SCRIPT="$SCRIPTS_DIR/query_$QUERY.pas" ;;
  *)             SCRIPT="$SCRIPTS_DIR/query_$QUERY.pas" ;;
esac

if [[ ! -f "$SCRIPT" ]]; then
  echo "no such Pascal script: $SCRIPT" >&2
  exit 2
fi
if [[ ! -f "$MO2" ]]; then
  echo "ModOrganizer.exe not found at: $MO2" >&2
  exit 2
fi

# Wrap any arg whose value contains a space in internal "..." so MO2's
# args.join(" ") doesn't merge tokens. For --key=value args we quote
# only the value half so xEdit's parser sees --key=<original-value>.
requote() {
  local arg="$1"
  case "$arg" in
    *\ *)
      if [[ "$arg" == --*=* ]]; then
        local key="${arg%%=*}"
        local val="${arg#*=}"
        printf '%s="%s"' "$key" "$val"
      elif [[ "$arg" == -[A-Za-z]:* ]]; then
        # short-form -D:<path> / -P:<path> / -script:<path>
        local prefix="${arg%%:*}"
        local val="${arg#*:}"
        printf '%s:"%s"' "$prefix" "$val"
      else
        printf '"%s"' "$arg"
      fi
      ;;
    *) printf '%s' "$arg" ;;
  esac
}

XEDIT_ARGS=(
  -IKnowWhatImDoing
  -autoload
  -autoexit
  "$(requote "-D:$DATA")"
  "$(requote "-P:$PLUGINS")"
  "$(requote "-script:$SCRIPT")"
)
for u in "$@"; do
  XEDIT_ARGS+=("$(requote "$u")")
done

exec "$MO2" "$EXE_TITLE" "${XEDIT_ARGS[@]}"
