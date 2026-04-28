from __future__ import annotations

import enum
import json
import sys
from dataclasses import dataclass, field
from typing import IO


class ErrorCode(enum.Enum):
    USER_ARG = ("user_arg", 1)
    XEDIT_FAIL = ("xedit_fail", 2)
    PLUGIN_NOT_LOADED = ("plugin_not_loaded", 3)

    def __init__(self, name: str, exit_code: int) -> None:
        self.code_name = name
        self.exit_code = exit_code


@dataclass
class ObcError(Exception):
    code: ErrorCode
    message: str
    details: dict = field(default_factory=dict)

    def __str__(self) -> str:
        return f"{self.code.code_name}: {self.message}"


def emit_error(err: ObcError, *, fmt: str = "json", stream: IO[str] | None = None) -> None:
    out = stream if stream is not None else sys.stderr
    if fmt == "json":
        payload = {
            "error": {
                "code": err.code.code_name,
                "message": err.message,
                "details": err.details,
            }
        }
        out.write(json.dumps(payload) + "\n")
    else:
        out.write(f"error: {err.code.code_name}: {err.message}\n")
        if err.details:
            out.write(f"  details: {err.details}\n")
