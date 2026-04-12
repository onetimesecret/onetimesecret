#!/usr/bin/env python3
# scripts/logtide-ship.py

"""logtide-ship - pipe stdin to LogTide

Reads log lines from stdin and ships them to a LogTide instance via the
HTTP ingest API (/api/v1/ingest). Supports two subcommands:

    follow  - read stdin continuously, ship in batches (for long-running pipes)
    batch   - read stdin to EOF, ship in batches (for one-shot imports)

Four modes control how JSON log lines are handled:

    plain    - All input treated as text. ANSI codes stripped, log level
               guessed from message content. No JSON parsing. This is the
               original behavior and works with any log formatter.

    metadata - JSON lines are parsed. Level, timestamp, and hostname are
               extracted into top-level LogTide fields. Structured fields
               (logger name, pid, thread, SemanticLogger payload) are placed
               in the LogTide `metadata` dict. Human-readable message is
               preserved. Best when LogTide supports metadata queries.

    json     - JSON lines are parsed. Level, timestamp, and hostname are
               extracted into top-level fields. The full raw JSON is sent as
               the LogTide `message`, allowing a LogTide pipeline with a JSON
               parser step to extract and index all fields server-side.

    caddy    - Caddy structured JSON access logs are parsed. Timestamps
               (Unix epoch floats) are converted to ISO 8601. A readable
               message is built from method, URI, status, size, and duration.
               Request details (remote_ip, proto, TLS, user_agent) go into
               LogTide `metadata`. Machine hostname is used since Caddy
               doesn't include it in log output.

Plain text lines always use the text path regardless of mode.

Usage:
    # Follow a process manager (default --mode json)
    LOG_FORMATTER=json bin/backend | python3 scripts/logtide-ship.py follow backend

    # Batch-ship an existing log file with text-mode fallback
    cat /var/log/app.log | python3 scripts/logtide-ship.py batch backend --mode plain

    # Use metadata mode for structured fields without pipeline parsing
    LOG_FORMATTER=json bin/backend | python3 scripts/logtide-ship.py follow backend --mode metadata

    # Follow Caddy access logs
    tail -f /var/log/caddy/access.log | python3 scripts/logtide-ship.py follow caddy-proxy --mode caddy
"""

import json
import logging
import os
import re
import socket
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Any, Literal
from urllib.parse import urlparse

import httpx
from cyclopts import App, Parameter

# -- Diagnostic logging --------------------------------------------------
#
# stdlib logging -> stderr with a logfmt-style suffix of key=value pairs.
# Keeps diagnostics consistent (timestamp, level, subcommand context) while
# avoiding any new deps. Payloads shipped to LogTide are unaffected.

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


_SERVICE_RE = re.compile(r"[\x00-\x1f\x7f]")


def _validate_service(service: str) -> None:
    """Reject empty/oversized/control-char service names with a clear error."""
    if not service or not service.strip():
        _diag.error("%s", _kv(event="invalid_service", reason="empty"))
        sys.exit(2)
    if len(service) > 128:
        _diag.error(
            "%s", _kv(event="invalid_service", reason="too_long", length=len(service))
        )
        sys.exit(2)
    if _SERVICE_RE.search(service):
        _diag.error("%s", _kv(event="invalid_service", reason="control_chars"))
        sys.exit(2)


def _validate_url(url: str) -> None:
    """Reject obviously malformed LOGTIDE_URL values."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        _diag.error(
            "%s",
            _kv(event="invalid_url", reason="bad_scheme", scheme=parsed.scheme or ""),
        )
        sys.exit(2)
    if not parsed.netloc or not parsed.hostname:
        _diag.error("%s", _kv(event="invalid_url", reason="missing_host", url=url))
        sys.exit(2)

# -- Configuration -------------------------------------------------------
#
# LOGTIDE_URL     Full URL to the LogTide ingest endpoint.  The /api/v1/ingest
#                 path accepts POST {"logs": [...]}.  Override via env var to
#                 point at a remote instance.
# LOGTIDE_API_KEY Passed as X-API-Key header.  The default "CHANGEME" is
#                 intentionally invalid — preflight will catch it and exit.
LOGTIDE_URL = os.environ.get("LOGTIDE_URL", "http://127.0.0.1:8080/api/v1/ingest")
LOGTIDE_API_KEY = os.environ.get("LOGTIDE_API_KEY", "CHANGEME")

# Batching: flush when batch reaches this size or after this many seconds of
# inactivity, whichever comes first. Keeps latency bounded while avoiding
# per-line HTTP overhead.
BATCH_SIZE = 100
FLUSH_INTERVAL = 2.0

# Queue saturation reporting: emit queue_dropped every Nth drop to avoid flooding.
_DROP_REPORT_INTERVAL = 1000
_QUEUE_RECOVERY_THRESHOLD = 5_000
_QUEUE_MAXSIZE = 10_000

app = App(name="logtide-ship", help="Ship logs to LogTide.")


LogMode = Literal["plain", "metadata", "json", "caddy"]


@Parameter(name="*")
@dataclass
class Global:
    verbose: bool = False
    """Echo lines to stdout as well."""

    mode: LogMode = "json"
    """How to handle JSON log lines.

    plain    -- treat all input as text (original behavior)
    metadata -- parse JSON, extract structured fields into metadata
    json     -- parse JSON, send full JSON as message for LogTide pipeline parsing
    caddy    -- parse Caddy structured JSON access logs
    """


def _mask_key(key: str) -> str:
    """Mask API key for display, showing first 4 and last 3 characters."""
    if len(key) <= 8:
        return "***"
    return f"{key[:4]}***{key[-3:]}"


def _preflight(command: str, service: str, mode: LogMode) -> None:
    """Print startup banner and verify LogTide connectivity and auth.

    Sends an empty batch to the ingest endpoint. Exits on auth failure
    (no point reading stdin if every batch will be rejected). Warns on
    connection errors but continues (server may come up later).
    """
    _validate_service(service)
    _validate_url(LOGTIDE_URL)

    # Hoist masked key to a local to avoid CodeQL clear-text-logging false positive.
    masked_key = _mask_key(LOGTIDE_API_KEY)
    _diag.info(
        "%s",
        _kv(
            event="startup",
            subcommand=command,
            service=service,
            mode=mode,
            url=LOGTIDE_URL,
            key=masked_key,
        ),
    )

    if LOGTIDE_API_KEY == "CHANGEME":
        _diag.warning(
            "%s",
            _kv(
                event="default_api_key",
                subcommand=command,
                hint="set LOGTIDE_API_KEY",
            ),
        )

    # Probe with an empty batch.  We only care about the status code:
    #   200/400 → connected and authed (400 = server dislikes empty logs, fine)
    #   401/403 → bad key, no point reading stdin — exit immediately
    #   5xx     → server-side issue, warn but continue (may recover)
    #   ConnectError → server unreachable, warn but continue (may start later)
    try:
        with httpx.Client() as client:
            resp = client.post(
                LOGTIDE_URL,
                json={"logs": []},
                headers={"X-API-Key": LOGTIDE_API_KEY},
                timeout=5,
            )
        if resp.status_code in (401, 403):
            _diag.error(
                "%s",
                _kv(
                    event="preflight_auth_failed",
                    subcommand=command,
                    status=resp.status_code,
                    body=_snippet(resp.text),
                    hint="check LOGTIDE_API_KEY",
                ),
            )
            sys.exit(1)
        if resp.status_code >= 500:
            _diag.warning(
                "%s",
                _kv(
                    event="preflight_server_error",
                    subcommand=command,
                    status=resp.status_code,
                    body=_snippet(resp.text),
                ),
            )
        else:
            _diag.info(
                "%s",
                _kv(
                    event="preflight_ok",
                    subcommand=command,
                    status=resp.status_code,
                ),
            )
    except httpx.ConnectError as e:
        _diag.warning(
            "%s",
            _kv(
                event="preflight_unreachable",
                subcommand=command,
                url=LOGTIDE_URL,
                error=str(e),
            ),
        )
    except httpx.HTTPError as e:
        _diag.warning(
            "%s",
            _kv(
                event="preflight_error",
                subcommand=command,
                error=str(e),
            ),
        )


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
                line=_snippet(line, 120),
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


# -- HTTP transport ------------------------------------------------------


_SEND_RETRIES = 2
_SEND_BACKOFF = 0.5  # seconds, doubled each retry


def _is_retryable(exc: Exception) -> bool:
    """True for transient failures worth retrying (connection errors, 5xx)."""
    if isinstance(exc, (httpx.ConnectError, httpx.ReadTimeout, httpx.WriteTimeout)):
        return True
    if isinstance(exc, httpx.HTTPStatusError) and exc.response.status_code >= 500:
        return True
    return False


def _send_batch(client: httpx.Client, batch: list[dict]) -> None:
    """POST a batch of log entries to the LogTide ingest API.

    Retries up to _SEND_RETRIES times on transient failures (connection
    errors, 5xx). Non-retryable errors are logged and swallowed so a
    LogTide outage doesn't kill the pipeline.
    """
    delay = _SEND_BACKOFF
    for attempt in range(_SEND_RETRIES + 1):
        try:
            resp = client.post(
                LOGTIDE_URL,
                json={"logs": batch},
                headers={"X-API-Key": LOGTIDE_API_KEY},
                timeout=10,
            )
            if resp.status_code != 200:
                _diag.warning(
                    "%s",
                    _kv(
                        event="send_non_200",
                        status=resp.status_code,
                        attempt=attempt + 1,
                        batch_size=len(batch),
                        body=_snippet(resp.text),
                    ),
                )
            resp.raise_for_status()
            return
        except httpx.HTTPError as e:
            if _is_retryable(e) and attempt < _SEND_RETRIES:
                status = getattr(getattr(e, "response", None), "status_code", None)
                _diag.warning(
                    "%s",
                    _kv(
                        event="send_retry",
                        attempt=attempt + 1,
                        max_attempts=_SEND_RETRIES + 1,
                        batch_size=len(batch),
                        status=status,
                        backoff=delay,
                        error=str(e),
                    ),
                )
                time.sleep(delay)
                delay *= 2
                continue
            status = getattr(getattr(e, "response", None), "status_code", None)
            _diag.error(
                "%s",
                _kv(
                    event="send_failed",
                    attempt=attempt + 1,
                    batch_size=len(batch),
                    status=status,
                    error=str(e),
                ),
            )
            return


def _shipper(queue: Queue, service: str, mode: LogMode):
    """Background thread that drains the queue and ships batches to LogTide.

    Runs in a daemon thread started by the ``follow`` command.  The main
    thread reads stdin and pushes raw lines into the queue; this thread
    builds LogTide entries and flushes them in batches.

    Shutdown protocol: the main thread pushes ``None`` into the queue
    (on EOF or KeyboardInterrupt).  Any remaining entries are flushed
    before the thread exits.
    """
    batch: list[dict] = []
    last_flush = time.monotonic()
    exit_reason = "unknown"

    try:
        with httpx.Client() as client:
            while True:
                try:
                    line = queue.get(timeout=0.5)
                    if line is None:        # shutdown sentinel
                        exit_reason = "shutdown_sentinel"
                        break
                    batch.append(_build_entry(line, service, mode))
                except Empty:
                    pass                    # no new lines — check flush timer

                # Flush on batch-full or time-elapsed, whichever comes first
                now = time.monotonic()
                if len(batch) >= BATCH_SIZE or (
                    batch and now - last_flush > FLUSH_INTERVAL
                ):
                    _send_batch(client, batch)
                    batch = []
                    last_flush = now

            # Drain remainder after shutdown sentinel
            if batch:
                _diag.debug(
                    "%s", _kv(event="shipper_drain", remaining=len(batch))
                )
                _send_batch(client, batch)
    except Exception as e:
        exit_reason = f"exception:{type(e).__name__}"
        _diag.error(
            "%s",
            _kv(event="shipper_crash", error=str(e), exc_type=type(e).__name__),
        )
        raise
    finally:
        _diag.info(
            "%s", _kv(event="shipper_exit", reason=exit_reason)
        )


# -- Subcommands ---------------------------------------------------------


@app.command
def follow(service: str, *, opts: Global = Global()):
    """Read stdin continuously and ship lines to LogTide in batches.

    Use with long-running pipes (process managers, ``tail -f``).
    Lines are queued and shipped by a background thread so stdin is
    never blocked by HTTP latency.

    Backpressure: the producer never blocks. When the queue is full,
    the oldest queued line is evicted (drop-oldest) and the incoming
    line takes its place. A ``queue_full`` warning is emitted once at
    the start of a saturation episode; ``queue_dropped`` fires every
    ``_DROP_REPORT_INTERVAL`` drops with the running total; when the
    queue drains below ``_QUEUE_RECOVERY_THRESHOLD`` a
    ``queue_recovered`` event reports the total drops for the episode.

    Parameters
    ----------
    service
        Service name attached to each log entry (e.g. "backend", "caddy-proxy").
    """
    _preflight("follow", service, opts.mode)

    queue: Queue = Queue(maxsize=_QUEUE_MAXSIZE)
    thread = threading.Thread(
        target=_shipper, args=(queue, service, opts.mode), daemon=True
    )
    thread.start()

    stop_reason = "eof"
    backpressure_logged = False
    dropped = 0                 # running total for current saturation episode
    last_reported = 0           # last value of `dropped` we emitted
    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if opts.verbose:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            if not line:
                continue
            # Non-blocking drop-oldest: on Full, evict the head and retry.
            # If the retry still fails (racy shipper enqueue), drop the new line.
            try:
                queue.put_nowait(line)
            except Exception:
                if not backpressure_logged:
                    _diag.warning(
                        "%s",
                        _kv(
                            event="queue_full",
                            qsize=queue.qsize(),
                            maxsize=_QUEUE_MAXSIZE,
                            action="drop_oldest",
                        ),
                    )
                    backpressure_logged = True
                try:
                    queue.get_nowait()          # evict oldest
                    queue.put_nowait(line)
                except Exception:
                    pass                        # lost the race; drop incoming
                dropped += 1
                if dropped - last_reported >= _DROP_REPORT_INTERVAL:
                    _diag.warning(
                        "%s",
                        _kv(
                            event="queue_dropped",
                            count=dropped,
                            qsize=queue.qsize(),
                        ),
                    )
                    last_reported = dropped
            else:
                if backpressure_logged and queue.qsize() < _QUEUE_RECOVERY_THRESHOLD:
                    _diag.info(
                        "%s",
                        _kv(
                            event="queue_recovered",
                            qsize=queue.qsize(),
                            dropped_total=dropped,
                        ),
                    )
                    backpressure_logged = False
                    dropped = 0
                    last_reported = 0
    except KeyboardInterrupt:
        stop_reason = "keyboard_interrupt"
    except Exception as e:
        stop_reason = f"exception:{type(e).__name__}"
        _diag.error(
            "%s",
            _kv(event="reader_crash", error=str(e), exc_type=type(e).__name__),
        )
        raise
    finally:
        _diag.info(
            "%s", _kv(event="reader_exit", reason=stop_reason)
        )
        queue.put(None)             # signal shipper to flush and exit
        thread.join(timeout=5)
        if thread.is_alive():
            _diag.warning(
                "%s", _kv(event="shipper_join_timeout", seconds=5)
            )


@app.command
def batch(service: str, *, opts: Global = Global()):
    """Read stdin to EOF and ship to LogTide in batches.

    Use for one-shot imports (``cat logfile | logtide-ship batch ...``).
    Reads synchronously (no background thread) and ships each batch as
    it fills, so memory stays bounded. Do NOT use with ``tail -f`` or
    other never-ending streams — use ``follow`` for those.

    Parameters
    ----------
    service
        Service name attached to each log entry (e.g. "backend", "caddy-proxy").
    """
    _preflight("batch", service, opts.mode)

    entries: list[dict] = []

    with httpx.Client() as client:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if opts.verbose:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            if not line:
                continue
            entries.append(_build_entry(line, service, opts.mode))
            if len(entries) >= BATCH_SIZE:
                _send_batch(client, entries)
                entries = []

        if entries:
            _send_batch(client, entries)


if __name__ == "__main__":
    app()
