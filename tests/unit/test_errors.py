import io
import json
from oblivion_conflicts.errors import ObcError, ErrorCode, emit_error


def test_obcerror_carries_code_message_details():
    err = ObcError(ErrorCode.PLUGIN_NOT_LOADED, "MOO.esp not loaded", {"plugin": "MOO.esp"})
    assert err.code == ErrorCode.PLUGIN_NOT_LOADED
    assert err.message == "MOO.esp not loaded"
    assert err.details == {"plugin": "MOO.esp"}


def test_emit_error_json_writes_single_object_to_stream():
    err = ObcError(ErrorCode.USER_ARG, "bad arg")
    buf = io.StringIO()
    emit_error(err, fmt="json", stream=buf)
    out = buf.getvalue().strip()
    parsed = json.loads(out)
    assert parsed == {"error": {"code": "user_arg", "message": "bad arg", "details": {}}}


def test_emit_error_human_writes_plain_text():
    err = ObcError(ErrorCode.XEDIT_FAIL, "xEdit returned 1")
    buf = io.StringIO()
    emit_error(err, fmt="human", stream=buf)
    assert "xedit_fail" in buf.getvalue()
    assert "xEdit returned 1" in buf.getvalue()


def test_error_code_to_exit_code():
    assert ErrorCode.USER_ARG.exit_code == 1
    assert ErrorCode.XEDIT_FAIL.exit_code == 2
    assert ErrorCode.PLUGIN_NOT_LOADED.exit_code == 3
