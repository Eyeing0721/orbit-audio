"""Isolated cancellable API task. Exactly the same dispatcher as the CLI."""
import json
import sys
import tempfile

from automation import execute
import project_io
from project_io import Paths

for stream in (sys.stdin, sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8")


def emit(event, **data):
    print(json.dumps(dict(event=event, **data), ensure_ascii=False, allow_nan=False), flush=True)


if __name__ == "__main__":
    try:
        envelope = json.loads(sys.stdin.readline())
        project_io.STAGING_DIRECTORY = envelope["stagingDirectory"]
        tempfile.tempdir = envelope["stagingDirectory"]
        result = execute(envelope["request"], Paths(envelope["workspace"]),
                         lambda value, message: emit("progress", value=value, message=message),
                         envelope["maxRenderSeconds"])
        emit("result", data=result)
    except Exception as exc:
        emit("error", code=getattr(exc, "code", "failed"), status=getattr(exc, "status", 400), message=str(exc))
        sys.exit(1)
