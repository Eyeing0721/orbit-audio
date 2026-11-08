"""Launch ORBIT's existing CLI without shell quoting or alternative audio DSP."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def resolve_home(value=None):
    supplied = value or os.environ.get("ORBIT_HOME")
    if supplied:
        candidates = [Path(supplied).expanduser().resolve()]
    else:
        current = Path.cwd().resolve()
        candidates = [current, *list(current.parents)[:2]]
    for candidate in candidates:
        engines = [folder for folder in (candidate, candidate / "app")
                   if (folder / "backend" / "cli.py").is_file()]
        if len(engines) > 1:
            raise ValueError("Multiple ORBIT engines found; specify the exact engine directory")
        if engines:
            return engines[0]
    raise ValueError("ORBIT not found; provide --orbit-home or ORBIT_HOME")


def resolve_python(home, value=None):
    supplied = value or os.environ.get("ORBIT_PYTHON")
    if supplied:
        local = Path(supplied).expanduser()
        executable = str(local.resolve()) if local.is_file() else shutil.which(supplied)
        if not executable:
            raise ValueError("The requested Python interpreter was not found")
        return executable
    for relative in ("runtime/Scripts/python.exe", "runtime/bin/python"):
        candidate = home / relative
        if candidate.is_file():
            return str(candidate)
    return sys.executable


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument("--orbit-home", help="ORBIT source root, portable-package root, or app directory")
    parser.add_argument("--python", help="Python executable; not a shell command")
    parser.add_argument("cli_args", nargs=argparse.REMAINDER, help="ORBIT command; use -- before top-level ORBIT flags")
    args = parser.parse_args(argv)
    cli_args = args.cli_args
    if cli_args and cli_args[0] == "--":
        cli_args = cli_args[1:]
    if not cli_args:
        parser.print_help(sys.stderr)
        return 2
    try:
        home = resolve_home(args.orbit_home)
        python = resolve_python(home, args.python)
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", PYTHONIOENCODING="utf-8")
        env.setdefault("PYTHONDONTWRITEBYTECODE", "1")
        # Preserve caller cwd and stdin/stdout/stderr, including run - and progress.
        return subprocess.call([python, "-u", str(home / "backend" / "cli.py"), *cli_args], env=env)
    except KeyboardInterrupt:
        return 130
    except (ValueError, OSError) as error:
        print(json.dumps({"ok": False, "error": {"code": "skill_launcher", "message": str(error)}}),
              file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
