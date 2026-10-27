"""Local stderr diagnostics shared by normalization and shipping."""

import logging
import os
import re
import sys
from typing import Any

_LOG_LEVEL = os.environ.get("LOGTIDE_SHIP_LOG_LEVEL", "INFO").upper()

_diag = logging.getLogger("logtide-ship")
if not _diag.handlers:
    _handler = logging.StreamHandler(sys.stderr)
    _handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s logtide-ship %(message)s")
    )
    _diag.addHandler(_handler)
    _diag.propagate = False
try:
    _diag.setLevel(getattr(logging, _LOG_LEVEL, logging.INFO))
except Exception:
    _diag.setLevel(logging.INFO)


# Control chars (0x00-0x1f, 0x7f) corrupt logfmt lines; escape them explicitly.
_CTRL_ESCAPES = {"\n": "\\n", "\r": "\\r", "\t": "\\t"}
_CTRL_RE = re.compile(r"[\x00-\x1f\x7f]")


def _escape_ctrl(match: re.Match) -> str:
    c = match.group(0)
    return _CTRL_ESCAPES.get(c, f"\\x{ord(c):02x}")


def _kv(**fields: Any) -> str:
    """Format key=value pairs for logfmt-style diagnostic lines."""
    parts = []
    for k, v in fields.items():
        if v is None:
            continue
        s = str(v)
        has_ctrl = bool(_CTRL_RE.search(s))
        needs_quote = has_ctrl or any(c in s for c in (" ", '"', "="))
        if needs_quote:
            s = s.replace("\\", "\\\\").replace('"', '\\"')
            if has_ctrl:
                s = _CTRL_RE.sub(_escape_ctrl, s)
            s = '"' + s + '"'
        parts.append(f"{k}={s}")
    return " ".join(parts)


def _snippet(text: str, limit: int = 200) -> str:
    """Truncate arbitrary text for safe inclusion in a single log line."""
    text = text.replace("\n", "\\n").replace("\r", "\\r")
    if len(text) > limit:
        return text[:limit] + "...<truncated>"
    return text
