from __future__ import annotations

import argparse
import sys

from oblivion_conflicts.errors import ErrorCode, ObcError, emit_error


def _common_parent() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--xedit-path", required=False,
                   help="Path to TES4Edit.exe; falls back to OBLIVION_CONFLICTS_XEDIT env.")
    p.add_argument("--game-data", required=True,
                   help="Path to Oblivion Data/ directory.")
    src = p.add_argument_group("plugin source (exactly one)")
    src.add_argument("--mo2-profile", default=None,
                     help="MO2 profile dir; reads plugins.txt + loadorder.txt.")
    src.add_argument("--plugins", nargs="+", default=None,
                     help="Explicit plugin filenames in load order.")
    src.add_argument("--plugins-file", default=None,
                     help="File with one plugin per line, in load order.")
    p.add_argument("--format", choices=["json", "human"], default="json")
    p.add_argument("--quiet", action="store_true",
                   help="Suppress xEdit progress on stderr.")
    return p


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="obc")
    sub = parser.add_subparsers(dest="command", required=True)

    common = _common_parent()

    p_list = sub.add_parser("list", parents=[common],
                            help="Conflicting FormIDs in <plugin> (overview).")
    p_list.add_argument("plugin")

    p_between = sub.add_parser("between", parents=[common],
                               help="FormIDs both <a> and <b> touch (overview).")
    p_between.add_argument("plugin_a")
    p_between.add_argument("plugin_b")

    p_winners = sub.add_parser("winners", parents=[common],
                               help="Winner per FormID for <plugin>.")
    p_winners.add_argument("plugin")

    p_record = sub.add_parser("record", parents=[common],
                              help="Full field-level dump for one or more FormIDs.")
    p_record.add_argument("formids", nargs="+",
                          help="Load-order FormIDs (e.g. 0x1E012345).")

    return parser.parse_args(argv)


def _validate_source(args: argparse.Namespace) -> None:
    sources = [args.mo2_profile, args.plugins, args.plugins_file]
    given = [s for s in sources if s is not None]
    if len(given) == 0:
        raise ObcError(
            ErrorCode.USER_ARG,
            "exactly one of --mo2-profile / --plugins / --plugins-file is required",
        )
    if len(given) > 1:
        raise ObcError(
            ErrorCode.USER_ARG,
            "only one of --mo2-profile / --plugins / --plugins-file may be given",
        )


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:]) if argv is None else argv
    try:
        args = parse_args(argv)
        _validate_source(args)
    except ObcError as e:
        emit_error(e, fmt=args.format)
        return e.code.exit_code
    except SystemExit as e:
        # argparse error path — already wrote to stderr
        return e.code if isinstance(e.code, int) else 2

    # Dispatch placeholder — real handlers wire xEdit in Task 13+
    raise NotImplementedError(f"command not yet wired: {args.command}")
