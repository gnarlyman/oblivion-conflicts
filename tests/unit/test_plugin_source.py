from pathlib import Path
import pytest
from oblivion_conflicts.errors import ObcError, ErrorCode
from oblivion_conflicts.plugin_source import resolve_from_mo2_profile


def write(p: Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def test_resolve_mo2_profile_reads_loadorder_in_order(tmp_path: Path):
    profile = tmp_path / "Reborn-Base"
    write(profile / "loadorder.txt", "Oblivion.esm\nDLCShiveringIsles.esp\nMOO.esp\n")
    write(profile / "plugins.txt", "*Oblivion.esm\n*DLCShiveringIsles.esp\n*MOO.esp\n")
    result = resolve_from_mo2_profile(profile)
    assert result == ["Oblivion.esm", "DLCShiveringIsles.esp", "MOO.esp"]


def test_resolve_mo2_profile_excludes_unchecked_plugins(tmp_path: Path):
    profile = tmp_path / "p"
    write(profile / "loadorder.txt", "Oblivion.esm\nUnchecked.esp\nMOO.esp\n")
    # plugins.txt: prefix "*" means enabled. No prefix = disabled.
    write(profile / "plugins.txt", "*Oblivion.esm\nUnchecked.esp\n*MOO.esp\n")
    result = resolve_from_mo2_profile(profile)
    assert result == ["Oblivion.esm", "MOO.esp"]


def test_resolve_mo2_profile_handles_bom_and_blank_lines(tmp_path: Path):
    profile = tmp_path / "p"
    write(profile / "loadorder.txt", "﻿Oblivion.esm\n\nMOO.esp\n")
    write(profile / "plugins.txt", "﻿*Oblivion.esm\n\n*MOO.esp\n")
    result = resolve_from_mo2_profile(profile)
    assert result == ["Oblivion.esm", "MOO.esp"]


def test_resolve_mo2_profile_missing_loadorder_raises(tmp_path: Path):
    profile = tmp_path / "p"
    profile.mkdir()
    write(profile / "plugins.txt", "*Oblivion.esm\n")
    with pytest.raises(ObcError) as ei:
        resolve_from_mo2_profile(profile)
    assert ei.value.code == ErrorCode.USER_ARG
    assert "loadorder.txt" in ei.value.message


def test_resolve_mo2_profile_missing_plugins_raises(tmp_path: Path):
    profile = tmp_path / "p"
    write(profile / "loadorder.txt", "Oblivion.esm\n")
    with pytest.raises(ObcError) as ei:
        resolve_from_mo2_profile(profile)
    assert ei.value.code == ErrorCode.USER_ARG
    assert "plugins.txt" in ei.value.message


def test_resolve_mo2_profile_handles_crlf(tmp_path: Path):
    profile = tmp_path / "p"
    profile.mkdir()
    # Pin exact CRLF bytes (write_text would re-translate on Windows)
    (profile / "loadorder.txt").write_bytes(
        "﻿Oblivion.esm\r\nMOO.esp\r\n".encode("utf-8")
    )
    (profile / "plugins.txt").write_bytes(
        "﻿*Oblivion.esm\r\n*MOO.esp\r\n".encode("utf-8")
    )
    assert resolve_from_mo2_profile(profile) == ["Oblivion.esm", "MOO.esp"]


def test_resolve_mo2_profile_filename_case_mismatch_still_resolves(tmp_path: Path):
    profile = tmp_path / "p"
    write(profile / "loadorder.txt", "Oblivion.esm\nMOO.esp\n")
    # plugins.txt uses different casing — the active set should still match
    write(profile / "plugins.txt", "*oblivion.esm\n*moo.esp\n")
    # Output uses casing from loadorder.txt (the authoritative source)
    assert resolve_from_mo2_profile(profile) == ["Oblivion.esm", "MOO.esp"]
