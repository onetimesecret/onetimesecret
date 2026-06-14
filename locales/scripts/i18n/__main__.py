"""Zero-install launcher.

Lets ``python3 locales/scripts/i18n <args>`` run from the repo root with no
install: it puts ``locales/scripts`` on ``sys.path`` so the ``i18n`` package
is importable, then dispatches to the CLI.
"""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))  # -> locales/scripts

from i18n.cli import main

raise SystemExit(main())
