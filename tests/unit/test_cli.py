import io
import json
import pytest
from oblivion_conflicts.cli import main, parse_args


def test_parse_args_list_minimal():
    args = parse_args([
        "list", "MOO.esp",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
        "--plugins", "Oblivion.esm", "MOO.esp",
    ])
    assert args.command == "list"
    assert args.plugin == "MOO.esp"
    assert args.plugins == ["Oblivion.esm", "MOO.esp"]
    assert args.format == "json"


def test_parse_args_record_takes_multiple_formids():
    args = parse_args([
        "record", "0x00012345", "0xFE000ABC",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
        "--plugins-file", "list.txt",
    ])
    assert args.command == "record"
    assert args.formids == ["0x00012345", "0xFE000ABC"]
    assert args.plugins_file == "list.txt"


def test_parse_args_between_takes_two_plugins():
    args = parse_args([
        "between", "MOO.esp", "OOO.esp",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
        "--plugins", "Oblivion.esm", "MOO.esp", "OOO.esp",
    ])
    assert args.command == "between"
    assert args.plugin_a == "MOO.esp"
    assert args.plugin_b == "OOO.esp"


def test_main_validates_exactly_one_source(capsys):
    # No source given
    rc = main([
        "list", "MOO.esp",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
    ])
    assert rc == 1
    err = capsys.readouterr().err
    assert "user_arg" in err


def test_main_validates_only_one_source(capsys):
    # Two sources given
    rc = main([
        "list", "MOO.esp",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
        "--plugins", "MOO.esp",
        "--plugins-file", "list.txt",
    ])
    assert rc == 1
    err = capsys.readouterr().err
    assert "user_arg" in err


def test_main_validation_error_uses_human_format_when_requested(capsys):
    rc = main([
        "list", "MOO.esp",
        "--xedit-path", "C:/x/TES4Edit.exe",
        "--game-data", "D:/Game/Data",
        "--format", "human",
        # no source given → validation error
    ])
    assert rc == 1
    err = capsys.readouterr().err
    # Human format starts with "error:"; JSON format starts with "{"
    assert err.startswith("error:")
    assert "user_arg" in err
