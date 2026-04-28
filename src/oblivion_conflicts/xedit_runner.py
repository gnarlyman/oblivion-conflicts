from __future__ import annotations

import json
from pathlib import Path


def _fwd(p: Path | str) -> str:
    """Convert a path to forward-slash form (xEdit accepts both, FS forms more reliable)."""
    return str(p).replace("\\", "/")


def build_xedit_argv(
    *,
    xedit_path: Path,
    game_data: Path,
    load_list_file: Path,
    script_path: Path,
) -> list[str]:
    """Construct the argv for invoking xEdit headless against a load list + script."""
    return [
        _fwd(xedit_path),
        "-tes4",
        "-nobuildrefs",
        "-IKnowWhatImDoing",
        f"-D:{_fwd(game_data)}",
        f"-PSEUDO:{_fwd(load_list_file)}",
        f"-script:{_fwd(script_path)}",
    ]


def write_load_list(path: Path, plugins: list[str]) -> None:
    """Write one plugin filename per line, in load order, no trailing blank."""
    Path(path).write_text("\n".join(plugins) + "\n", encoding="utf-8")


def write_args_sidecar(path: Path, args: dict) -> None:
    """Write the JSON args file the Pascal script will read."""
    Path(path).write_text(json.dumps(args), encoding="utf-8")
