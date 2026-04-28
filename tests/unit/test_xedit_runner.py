from pathlib import Path
from oblivion_conflicts.xedit_runner import build_xedit_argv


def test_build_argv_basic(tmp_path: Path):
    argv = build_xedit_argv(
        xedit_path=Path("C:/x/TES4Edit.exe"),
        game_data=Path("D:/Game/Data"),
        load_list_file=tmp_path / "load.txt",
        script_path=Path("scripts/query_list.pas"),
    )
    # First arg = exe; others are flags. Order doesn't matter for xEdit
    # except -script: comes last per convention. Verify all expected flags present.
    assert argv[0] == "C:/x/TES4Edit.exe"
    assert "-tes4" in argv
    assert "-nobuildrefs" in argv
    assert "-IKnowWhatImDoing" in argv
    assert any(a.startswith("-D:") and a.endswith("D:/Game/Data") for a in argv)
    assert any(a.startswith("-PSEUDO:") and a.endswith(str(tmp_path / "load.txt").replace("\\", "/")) for a in argv)
    assert any(a.startswith("-script:") and a.endswith("scripts/query_list.pas") for a in argv)


def test_build_argv_quotes_paths_with_spaces(tmp_path: Path):
    # Paths with spaces should appear verbatim in argv (subprocess handles quoting)
    argv = build_xedit_argv(
        xedit_path=Path("C:/Program Files/x/TES4Edit.exe"),
        game_data=Path("D:/Modlists/Reborn/Stock Game/Data"),
        load_list_file=tmp_path / "load.txt",
        script_path=Path("s.pas"),
    )
    assert argv[0] == "C:/Program Files/x/TES4Edit.exe"
    data_arg = next(a for a in argv if a.startswith("-D:"))
    assert "D:/Modlists/Reborn/Stock Game/Data" in data_arg


def test_build_argv_uses_forward_slashes_for_xedit_compat(tmp_path: Path):
    # xEdit accepts forward slashes on Windows; we normalize.
    argv = build_xedit_argv(
        xedit_path=Path(r"C:\x\TES4Edit.exe"),
        game_data=Path(r"D:\Game\Data"),
        load_list_file=tmp_path / "load.txt",
        script_path=Path(r"scripts\query_list.pas"),
    )
    for a in argv[1:]:
        assert "\\" not in a, f"backslash in arg: {a}"


def test_write_load_list_file_writes_one_per_line(tmp_path: Path):
    from oblivion_conflicts.xedit_runner import write_load_list
    out = tmp_path / "load.txt"
    write_load_list(out, ["Oblivion.esm", "MOO.esp"])
    assert out.read_text(encoding="utf-8") == "Oblivion.esm\nMOO.esp\n"


def test_write_args_sidecar_writes_json(tmp_path: Path):
    from oblivion_conflicts.xedit_runner import write_args_sidecar
    out = tmp_path / "args.json"
    write_args_sidecar(out, {"command": "list", "target": "MOO.esp", "output": "out.json"})
    import json
    assert json.loads(out.read_text(encoding="utf-8")) == {
        "command": "list", "target": "MOO.esp", "output": "out.json",
    }
