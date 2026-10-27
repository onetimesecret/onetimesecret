#!/usr/bin/env python3
"""Compatibility entry point; new callers use bin/logship (ADR-042)."""

import os
from pathlib import Path
import sys

if __name__ == "__main__":
    command = Path(__file__).resolve().parents[1] / "bin" / "logship"
    os.execv(command, [str(command), *sys.argv[1:]])
