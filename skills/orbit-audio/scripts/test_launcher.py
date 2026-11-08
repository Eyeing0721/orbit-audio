"""Deterministic launcher tests; fixtures never contain user audio."""
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from orbit import resolve_home, resolve_python


class LauncherTests(unittest.TestCase):
    def engine(self, folder):
        (folder / "backend").mkdir(parents=True)
        (folder / "backend" / "cli.py").write_text("# fixture", encoding="utf-8")
        return folder.resolve()

    def test_source_and_portable_roots(self):
        with tempfile.TemporaryDirectory(prefix="orbit-launcher-") as temp:
            folder = Path(temp)
            source = self.engine(folder / "source with spaces")
            app = self.engine(folder / "portable" / "app")
            self.assertEqual(resolve_home(str(source)), source)
            self.assertEqual(resolve_home(str(folder / "portable")), app)

    def test_explicit_missing_home_does_not_fall_back(self):
        with tempfile.TemporaryDirectory(prefix="orbit-launcher-") as temp:
            self.engine(Path(temp) / "valid")
            with patch.dict(os.environ, {"ORBIT_HOME": str(Path(temp) / "valid")}):
                with self.assertRaises(ValueError):
                    resolve_home(str(Path(temp) / "missing"))

    def test_ambiguous_engine_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="orbit-launcher-") as temp:
            folder = Path(temp)
            self.engine(folder)
            self.engine(folder / "app")
            with self.assertRaises(ValueError):
                resolve_home(str(folder))

    def test_environment_home(self):
        with tempfile.TemporaryDirectory(prefix="orbit-launcher-") as temp:
            home = self.engine(Path(temp) / "engine")
            with patch.dict(os.environ, {"ORBIT_HOME": str(home)}):
                self.assertEqual(resolve_home(), home)

    def test_explicit_python_and_local_runtime_precedence(self):
        with tempfile.TemporaryDirectory(prefix="orbit-launcher-") as temp:
            home = self.engine(Path(temp) / "engine")
            runtime = home / "runtime" / "Scripts" / "python.exe"
            runtime.parent.mkdir(parents=True)
            runtime.write_bytes(b"fixture")
            explicit = Path(temp) / "interpreter with spaces.exe"
            explicit.write_bytes(b"fixture")
            with patch.dict(os.environ, {}, clear=True):
                self.assertEqual(resolve_python(home), str(runtime))
                self.assertEqual(resolve_python(home, str(explicit)), str(explicit.resolve()))
                with self.assertRaises(ValueError):
                    resolve_python(home, "unavailable-orbit-python-command")


if __name__ == "__main__":
    unittest.main()
