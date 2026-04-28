from __future__ import annotations

from pathlib import Path

from oblivion_conflicts.errors import ErrorCode, ObcError


def _read_lines(path: Path) -> list[str]:
    """Return lines from a UTF-8 (with optional BOM) text file, CR stripped.

    Blank lines are included; callers are responsible for filtering.
    """
    text = path.read_text(encoding="utf-8")
    if text.startswith("﻿"):
        text = text[1:]
    return [line.rstrip("\r") for line in text.split("\n")]


def resolve_from_mo2_profile(profile_dir: Path) -> list[str]:
    """Resolve a load order from an MO2 profile directory.

    Returns plugin filenames in load order, filtered to those marked active
    in plugins.txt (lines prefixed with '*').
    """
    profile_dir = Path(profile_dir)
    loadorder_path = profile_dir / "loadorder.txt"
    plugins_path = profile_dir / "plugins.txt"

    if not loadorder_path.is_file():
        raise ObcError(
            ErrorCode.USER_ARG,
            f"loadorder.txt not found in profile: {profile_dir}",
            {"profile": str(profile_dir), "expected": str(loadorder_path)},
        )
    if not plugins_path.is_file():
        raise ObcError(
            ErrorCode.USER_ARG,
            f"plugins.txt not found in profile: {profile_dir}",
            {"profile": str(profile_dir), "expected": str(plugins_path)},
        )

    enabled_lower: set[str] = set()
    for line in _read_lines(plugins_path):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("*"):
            enabled_lower.add(s[1:].strip().lower())

    ordered: list[str] = []
    for line in _read_lines(loadorder_path):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        if s.lower() in enabled_lower:
            ordered.append(s)
    return ordered
