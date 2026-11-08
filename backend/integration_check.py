"""Compatibility entry point for the synthetic CLI/API integration check."""
import runpy
from pathlib import Path

if __name__ == '__main__':
    runpy.run_path(str(Path(__file__).with_name('integration_automation.py')), run_name='__main__')
