"""Normalize plain, SemanticLogger JSON, and Caddy input records."""

import json
import re
import socket
from datetime import datetime, timezone
from typing import Literal

from .diagnostics import _diag, _kv

LogMode = Literal["plain", "metadata", "json", "caddy"]


def detect_level(msg: str) -> str:
    """Guess LogTide level from message text. Used only for plain text input.

    Maps to LogTide's level values (matching the syslog integration):
    FATAL/CRIT -> critical, ERROR -> error, WARN -> warn, DEBUG -> debug,
    everything else -> info.
    """
    msg_upper = msg.upper()
    if any(x in msg_upper for x in ("FATAL", "CRIT")):
        return "critical"
    if "ERROR" in msg_upper:
        return "error"
    if "WARN" in msg_upper:
        return "warn"
    if "DEBUG" in msg_upper:
        return "debug"
    return "info"


# Matches ANSI color/style escape sequences (e.g. from SemanticLogger :color formatter)
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def _now() -> str:
    return (
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    )


def _try_parse_json(line: str) -> dict | None:
    """Fast-path JSON detection: skip lines that don't start with '{'.

    SemanticLogger JSON output always starts with '{'. Plain text, ANSI-colored
    output, and blank lines never do, so the startswith check avoids calling
    json.loads on every line.
    """
    if not line.startswith("{"):
        return None
    try:
        return json.loads(line)
    except json.JSONDecodeError as e:
        _diag.debug(
            "%s",
            _kv(
                event="json_parse_failed",
                error=str(e),
            ),
        )
        return None


# -- Entry builders ------------------------------------------------------
#
# Each mode has its own builder that maps source-specific fields to the
# LogTide ingest schema:
#
#   { time, service, hostname, level, message, metadata? }
#
# _build_entry() dispatches based on mode.  Non-JSON lines always fall
# through to the text path, so mixed-format streams (e.g. startup banners
# interspersed with JSON) are handled gracefully.


def _build_entry(line: str, service: str, mode: LogMode = "json") -> dict:
    """Dispatch to the appropriate entry builder based on mode."""
    if mode != "plain":
        raw = _try_parse_json(line)
        if raw:
            if mode == "caddy":
                return _build_entry_caddy(raw, service)
            if mode == "metadata":
                return _build_entry_metadata(raw, service)
            # mode == "json": send raw JSON as the message body
            return _build_entry_json(raw, service)
    return _build_entry_text(line, service)


def _build_entry_json(raw: dict, service: str) -> dict:
    """Send full JSON as message for LogTide pipeline parsing.

    The entire raw JSON object is re-serialized into ``message`` so that
    a LogTide pipeline step (e.g. a JSON parser) can extract and index
    every field server-side.  Top-level ``timestamp``, ``host``, and
    ``level`` are pulled out for LogTide's native fields.
    """
    return {
        "time": raw.get("timestamp", _now()),     # SemanticLogger: ISO 8601
        "service": service,
        "hostname": raw.get("host", _HOSTNAME),    # SemanticLogger host, or machine fallback
        "level": raw.get("level", "info"),
        "message": json.dumps(raw),                # full JSON for pipeline parsing
    }


def _fmt_bytes(n: int) -> str:
    """Format byte count for log messages."""
    if n < 1024:
        return f"{n}B"
    if n < 1024 * 1024:
        return f"{n / 1024:.1f}kB"
    return f"{n / (1024 * 1024):.1f}MB"


# Caddy doesn't include machine hostname in its JSON output (request.host
# is the HTTP Host header), so we resolve it once at import time.
_HOSTNAME = socket.gethostname()

# Caddy duration parsing.  With `duration_format string` in the Caddyfile,
# durations are Go time.Duration strings ("7.750ms", "250µs", "1.5s").
# With the default `duration_format number`, they're float seconds.
_GO_DURATION_RE = re.compile(r"^([\d.]+)(µs|us|ms|s|m|h)$")
_DURATION_MULTIPLIERS = {
    "h": 3600000,
    "m": 60000,
    "s": 1000,
    "ms": 1,
    "us": 0.001,
    "µs": 0.001,
}


def _parse_caddy_ts(ts: int | float) -> str:
    """Convert Caddy timestamp to ISO 8601.

    Handles both ``unix_seconds_float`` (default) and
    ``unix_milli_float`` (common in production configs).
    Values above 1e12 are treated as milliseconds.
    """
    if ts > 1e12:
        ts = ts / 1000
    return (
        datetime.fromtimestamp(ts, tz=timezone.utc)
        .strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3]
        + "Z"
    )


def _parse_caddy_duration_ms(val: str | int | float) -> float:
    """Parse Caddy duration to milliseconds.

    Handles float seconds (``duration_format number``) and Go duration
    strings like ``7.750292ms`` (``duration_format string``).
    """
    if isinstance(val, (int, float)):
        return round(val * 1000, 2)
    if isinstance(val, str):
        m = _GO_DURATION_RE.match(val)
        if m:
            return round(float(m.group(1)) * _DURATION_MULTIPLIERS[m.group(2)], 2)
    return 0


_REQUEST_ID_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,199}")


def _caddy_request_id(raw: dict) -> str | None:
    """Read only the explicit log field or IDs actually returned in a response.

    Incoming request headers can contain a caller's unrelated request ID.
    Caddy's response headers use arrays, so accept only a single token value.
    """
    request_id = raw.get("request_id")
    if isinstance(request_id, str) and _REQUEST_ID_RE.fullmatch(request_id):
        return request_id

    headers = raw.get("resp_headers")
    if not isinstance(headers, dict):
        return None
    for header_name in ("x-request-id", "o-request-id"):
        values = [
            value for key, value in headers.items()
            if isinstance(key, str) and key.lower() == header_name
        ]
        if len(values) != 1:
            continue
        value = values[0]
        if isinstance(value, list):
            value = value[0] if len(value) == 1 else None
        if isinstance(value, str) and _REQUEST_ID_RE.fullmatch(value):
            return value
    return None


def _build_entry_caddy(raw: dict, service: str) -> dict:
    """Build entry from Caddy structured JSON access log.

    Caddy logs use Unix epoch floats for timestamps and nest request
    details under a ``request`` key. This builder extracts a readable
    message (method, URI, status, size, duration) and populates metadata
    with the structured fields LogTide can query.

    Handles both default Caddy config and common overrides:
    - ``time_format``: ``unix_seconds_float`` (default) or ``unix_milli_float``
    - ``duration_format``: ``number`` (float seconds) or ``string`` (Go duration)
    """
    # -- Timestamp -----------------------------------------------------------
    # Caddy's `ts` field format depends on the Caddyfile `time_format`:
    #   unix_seconds_float (default) → 1646861401.524  (seconds)
    #   unix_milli_float             → 1775975893020.3 (milliseconds)
    # _parse_caddy_ts auto-detects based on magnitude (> 1e12 = millis).
    ts = raw.get("ts")
    if isinstance(ts, (int, float)):
        time_str = _parse_caddy_ts(ts)
    else:
        time_str = _now()

    # -- Human-readable message ----------------------------------------------
    # Condenses the request into a single line:  "GET /api/users 200 13.8kB 74.01ms"
    req = raw.get("request", {})
    method = req.get("method", "")
    uri = req.get("uri", "")
    status = raw.get("status", 0)
    size = raw.get("size", 0)             # response body bytes
    duration_ms = _parse_caddy_duration_ms(raw.get("duration", 0))

    message = f"{method} {uri} {status} {_fmt_bytes(size)} {duration_ms}ms"

    # -- Metadata ------------------------------------------------------------
    # Structured fields that LogTide can query/filter on.  Only included
    # when present to keep payloads lean.
    metadata: dict = {}
    if request_id := _caddy_request_id(raw):
        metadata["request_id"] = request_id
    if req.get("remote_ip"):
        metadata["remote_ip"] = req["remote_ip"]
    # client_ip differs from remote_ip when behind a proxy (X-Forwarded-For)
    if req.get("client_ip") and req["client_ip"] != req.get("remote_ip"):
        metadata["client_ip"] = req["client_ip"]
    if status:
        metadata["status"] = status
    if size:
        metadata["size"] = size
    if duration_ms:
        metadata["duration_ms"] = duration_ms
    if req.get("host"):
        metadata["host"] = req["host"]    # HTTP Host header, not machine hostname
    if req.get("proto"):
        metadata["proto"] = req["proto"]  # e.g. "HTTP/2.0", "HTTP/3.0"
    if raw.get("logger"):
        metadata["logger"] = raw["logger"]  # e.g. "http.log.access.log0"

    # TLS negotiated protocol (h2, h3, http/1.1)
    tls = req.get("tls")
    if isinstance(tls, dict) and tls.get("proto"):
        metadata["tls_proto"] = tls["proto"]

    # Caddy stores header values as arrays (HTTP allows repeated headers)
    headers = req.get("headers", {})
    ua = headers.get("User-Agent")
    if isinstance(ua, list) and ua:
        metadata["user_agent"] = ua[0]

    entry = {
        "time": time_str,
        "service": service,
        "hostname": _HOSTNAME,            # machine hostname (not in Caddy output)
        "level": raw.get("level", "info"),
        "message": message,
    }
    if metadata:
        entry["metadata"] = metadata
    return entry


def _build_entry_metadata(raw: dict, service: str) -> dict:
    """Extract structured fields into metadata dict.

    SemanticLogger JSON fields → LogTide mapping:
      timestamp → time     (ISO 8601)
      host      → hostname (machine hostname)
      level     → level    (info/warn/error/debug/critical)
      message   → message  (human-readable text)
      name      → metadata.logger   (Ruby class/module name)
      pid       → metadata.pid
      thread    → metadata.thread
      payload   → metadata.*        (app-specific key/value pairs, merged in)
    """
    metadata = {
        k: v
        for k, v in {
            "logger": raw.get("name"),
            "pid": raw.get("pid"),
            "thread": raw.get("thread"),
        }.items()
        if v is not None
    }
    # SemanticLogger's payload is an arbitrary dict of app-specific data
    payload = raw.get("payload")
    if isinstance(payload, dict):
        metadata.update(payload)

    entry = {
        "time": raw.get("timestamp", _now()),
        "service": service,
        "hostname": raw.get("host", _HOSTNAME),
        "level": raw.get("level", "info"),
        "message": raw.get("message", ""),
    }
    if metadata:
        entry["metadata"] = metadata
    return entry


def _build_entry_text(line: str, service: str) -> dict:
    """Strip ANSI, guess level from text content."""
    line = _ANSI_RE.sub("", line)
    return {
        "time": _now(),
        "service": service,
        "hostname": _HOSTNAME,
        "level": detect_level(line),
        "message": line,
    }
