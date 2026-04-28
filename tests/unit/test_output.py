import io
import json
from oblivion_conflicts.output import build_envelope, emit_json


def test_build_envelope_wraps_results_with_meta():
    results = [{"formid": "0x00012345", "edid": "Foo"}]
    envelope = build_envelope(
        command="list",
        args={"plugin": "MOO.esp"},
        load_order=["Oblivion.esm", "MOO.esp"],
        xedit_version="4.1.5f",
        duration_ms=1234,
        results=results,
    )
    assert envelope["meta"]["command"] == "list"
    assert envelope["meta"]["game"] == "tes4"
    assert envelope["meta"]["args"] == {"plugin": "MOO.esp"}
    assert envelope["meta"]["load_order"] == ["Oblivion.esm", "MOO.esp"]
    assert envelope["meta"]["xedit_version"] == "4.1.5f"
    assert envelope["meta"]["duration_ms"] == 1234
    assert "started_at" in envelope["meta"]
    assert "tool_version" in envelope["meta"]
    assert envelope["results"] == results


def test_emit_json_writes_compact_object_with_trailing_newline():
    buf = io.StringIO()
    emit_json({"meta": {}, "results": []}, stream=buf)
    out = buf.getvalue()
    assert out.endswith("\n")
    parsed = json.loads(out)
    assert parsed == {"meta": {}, "results": []}
