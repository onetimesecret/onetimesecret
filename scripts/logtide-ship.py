#!/usr/bin/env python3

# scripts/logtide-ship.py

"""logtide-ship - pipe stdin to LogTide

Reads log lines from stdin and ships them to a LogTide instance via the
HTTP ingest API (/api/v1/ingest). Supports two subcommands:

    follow  - read stdin continuously, ship in batches (for long-running pipes)
    batch   - read all of stdin, ship as a single batch (for one-shot imports)

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
import os
import re
import socket
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Literal

import httpx
from cyclopts import App, Parameter

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
    print(
        f"[logtide-ship {command}] service={service} mode={mode}"
        f" url={LOGTIDE_URL} key={_mask_key(LOGTIDE_API_KEY)}",
        file=sys.stderr,
    )

    if LOGTIDE_API_KEY == "CHANGEME":
        print(
            "[logtide-ship] WARNING: using default API key 'CHANGEME'"
            " — set LOGTIDE_API_KEY",
            file=sys.stderr,
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
            print(
                f"[logtide-ship] FATAL: authentication failed"
                f" ({resp.status_code}). Check LOGTIDE_API_KEY.",
                file=sys.stderr,
            )
            sys.exit(1)
        if resp.status_code >= 500:
            print(
                f"[logtide-ship] WARNING: server returned {resp.status_code}"
                " — will retry with real batches",
                file=sys.stderr,
            )
        else:
            print("[logtide-ship] preflight OK", file=sys.stderr)
    except httpx.ConnectError:
        print(
            f"[logtide-ship] WARNING: cannot reach {LOGTIDE_URL}"
            " — will retry when batches are ready",
            file=sys.stderr,
        )
    except httpx.HTTPError as e:
        print(
            f"[logtide-ship] WARNING: preflight failed: {e}"
            " — continuing anyway",
            file=sys.stderr,
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
    except json.JSONDecodeError:
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
_GO_DURATION_RE = re.compile(r"^([\d.]+)(µs|us|ms|s)$")
_DURATION_MULTIPLIERS = {"s": 1000, "ms": 1, "us": 0.001, "µs": 0.001}


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


def _send_batch(client: httpx.Client, batch: list[dict]) -> None:
    """POST a batch of log entries to the LogTide ingest API.

    Errors are logged to stderr rather than raised, so a transient LogTide
    outage doesn't kill the pipeline — lines continue to be read from stdin.
    """
    try:
        resp = client.post(
            LOGTIDE_URL,
            json={"logs": batch},
            headers={"X-API-Key": LOGTIDE_API_KEY},
            timeout=10,
        )
        if resp.status_code != 200:
            # Include the first entry for context — helps identify which
            # service/mode is producing entries the server rejects.
            print(
                f"[logtide-ship] {resp.status_code}: {resp.text}"
                f" (batch_size={len(batch)},"
                f" first={batch[0] if batch else 'empty'})",
                file=sys.stderr,
            )
        resp.raise_for_status()
    except httpx.HTTPError as e:
        print(f"[logtide-ship] send failed: {e}", file=sys.stderr)


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

    with httpx.Client() as client:
        while True:
            try:
                line = queue.get(timeout=0.5)
                if line is None:        # shutdown sentinel
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
            _send_batch(client, batch)


# -- Subcommands ---------------------------------------------------------


@app.command
def follow(service: str, *, opts: Global = Global()):
    """Read stdin continuously and ship lines to LogTide in batches.

    Use with long-running pipes (process managers, ``tail -f``).
    Lines are queued and shipped by a background thread so stdin is
    never blocked by HTTP latency.

    Parameters
    ----------
    service
        Service name attached to each log entry (e.g. "backend", "caddy-proxy").
    """
    _preflight("follow", service, opts.mode)

    queue: Queue = Queue()
    thread = threading.Thread(
        target=_shipper, args=(queue, service, opts.mode), daemon=True
    )
    thread.start()

    try:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if opts.verbose:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            if not line:
                continue
            queue.put(line)
    except KeyboardInterrupt:
        pass
    finally:
        queue.put(None)             # signal shipper to flush and exit
        thread.join(timeout=5)


@app.command
def batch(service: str, *, opts: Global = Global()):
    """Read all of stdin then ship to LogTide as a single batch.

    Use for one-shot imports (``cat logfile | logtide-ship batch ...``).
    Reads stdin to EOF before shipping, so do NOT use with ``tail -f``
    or other never-ending streams — use ``follow`` for those.

    Parameters
    ----------
    service
        Service name attached to each log entry (e.g. "backend", "caddy-proxy").
    """
    _preflight("batch", service, opts.mode)

    lines = sys.stdin.read().splitlines()   # blocks until EOF

    if opts.verbose:
        for line in lines:
            sys.stdout.write(line + "\n")
        sys.stdout.flush()

    batch = [_build_entry(line, service, opts.mode) for line in lines if line]

    if not batch:
        return

    with httpx.Client() as client:
        for i in range(0, len(batch), BATCH_SIZE):
            _send_batch(client, batch[i : i + BATCH_SIZE])


if __name__ == "__main__":
    app()
