from __future__ import annotations

import json
import sys
from typing import IO

from oblivion_conflicts import __version__


def build_envelope(
    *,
    command: str,
    args: dict,
    load_order: list[str],
    xedit_version: str,
    started_at: str,
    duration_ms: int,
    results: list,
) -> dict:
    return {
        "meta": {
            "tool_version": __version__,
            "xedit_version": xedit_version,
            "game": "tes4",
            "command": command,
            "args": args,
            "load_order": load_order,
            "started_at": started_at,
            "duration_ms": duration_ms,
        },
        "results": results,
    }


def emit_json(envelope: dict, *, stream: IO[str] | None = None) -> None:
    out = stream if stream is not None else sys.stdout
    out.write(json.dumps(envelope, separators=(",", ":")) + "\n")


def emit_human(envelope: dict, *, stream: IO[str] | None = None) -> None:
    """Plain tabular fallback. Best-effort; JSON is the contract."""
    out = stream if stream is not None else sys.stdout
    cmd = envelope["meta"]["command"]
    results = envelope["results"]
    out.write(f"# command: {cmd}\n")
    out.write(f"# results: {len(results)}\n")
    for r in results:
        out.write(json.dumps(r, separators=(",", ":")) + "\n")
