#!/usr/bin/env python3

# scripts/logtide-ship.py

"""logtide-ship - pipe stdin to LogTide

Reads log lines from stdin and ships them to a LogTide instance via the
HTTP ingest API (/api/v1/ingest). Supports two subcommands:

    stream  - read stdin continuously, ship in batches (for long-running pipes)
    ingest  - read all of stdin, ship as a single batch (for one-shot imports)

Three modes control how JSON log lines (e.g. from SemanticLogger with
LOG_FORMATTER=json) are handled:

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

Plain text lines always use the text path regardless of mode.

Usage:
    # Stream from a process manager (default --mode json)
    LOG_FORMATTER=json bin/backend | python3 scripts/logtide-ship.py stream backend

    # Ship existing log file with text-mode fallback
    cat /var/log/app.log | python3 scripts/logtide-ship.py ingest backend --mode plain

    # Use metadata mode for structured fields without pipeline parsing
    LOG_FORMATTER=json bin/backend | python3 scripts/logtide-ship.py stream backend --mode metadata
"""

import json
import os
import re
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from queue import Empty, Queue
from typing import Literal

import httpx
from cyclopts import App, Parameter

# LogTide ingest endpoint and credentials (env vars take precedence)
LOGTIDE_URL = os.environ.get("LOGTIDE_URL", "http://127.0.0.1:8080/api/v1/ingest")
LOGTIDE_API_KEY = os.environ.get("LOGTIDE_API_KEY", "CHANGEME")

# Batching: flush when batch reaches this size or after this many seconds of
# inactivity, whichever comes first. Keeps latency bounded while avoiding
# per-line HTTP overhead.
BATCH_SIZE = 100
FLUSH_INTERVAL = 2.0

app = App(name="logtide-ship", help="Ship logs to LogTide.")


LogMode = Literal["plain", "metadata", "json"]


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
    """


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


def _build_entry(line: str, service: str, mode: LogMode = "json") -> dict:
    """Dispatch to the appropriate entry builder based on mode.

    For non-plain modes, attempts JSON parsing first. Falls through to
    the text path if the line isn't valid JSON (e.g. plain text output,
    startup banners, non-SemanticLogger lines mixed into the stream).
    """
    if mode != "plain":
        raw = _try_parse_json(line)
        if raw:
            if mode == "metadata":
                return _build_entry_metadata(raw, service)
            return _build_entry_json(raw, service)
    return _build_entry_text(line, service)


def _build_entry_json(raw: dict, service: str) -> dict:
    """Send full JSON as message for LogTide pipeline parsing."""
    return {
        "time": raw.get("timestamp", _now()),
        "service": service,
        "hostname": raw.get("host", ""),
        "level": raw.get("level", "info"),
        "message": json.dumps(raw),
    }


def _build_entry_metadata(raw: dict, service: str) -> dict:
    """Extract structured fields into metadata dict."""
    metadata = {
        k: v
        for k, v in {
            "logger": raw.get("name"),
            "pid": raw.get("pid"),
            "thread": raw.get("thread"),
        }.items()
        if v is not None
    }
    payload = raw.get("payload")
    if isinstance(payload, dict):
        metadata.update(payload)

    entry = {
        "time": raw.get("timestamp", _now()),
        "service": service,
        "hostname": raw.get("host", ""),
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
        "level": detect_level(line),
        "message": line,
    }


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
            print(
                f"[logtide-ship] {resp.status_code}: {resp.text} (batch_size={len(batch)}, first={batch[0] if batch else 'empty'})",
                file=sys.stderr,
            )
        resp.raise_for_status()
    except httpx.HTTPError as e:
        print(f"[logtide-ship] send failed: {e}", file=sys.stderr)


def _shipper(queue: Queue, service: str, mode: LogMode):
    """Background thread that drains the queue and ships batches to LogTide.

    Runs in a loop reading lines from the queue, building entries, and
    flushing when the batch is full or the flush interval elapses. Sending
    None into the queue signals shutdown; any remaining entries are flushed
    before the thread exits.
    """
    batch: list[dict] = []
    last_flush = time.monotonic()

    with httpx.Client() as client:
        while True:
            try:
                line = queue.get(timeout=0.5)
                if line is None:
                    break
                batch.append(_build_entry(line, service, mode))
            except Empty:
                pass

            now = time.monotonic()
            if len(batch) >= BATCH_SIZE or (
                batch and now - last_flush > FLUSH_INTERVAL
            ):
                _send_batch(client, batch)
                batch = []
                last_flush = now

        if batch:
            _send_batch(client, batch)


@app.command
def stream(service: str, *, opts: Global = Global()):
    """Read stdin continuously and ship lines to LogTide in batches.

    Parameters
    ----------
    service
        Service name attached to each log entry.
    """
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
        queue.put(None)
        thread.join(timeout=5)


@app.command
def ingest(service: str, *, opts: Global = Global()):
    """Read all of stdin then ship to LogTide as a single batch.

    Parameters
    ----------
    service
        Service name attached to each log entry.
    """
    lines = sys.stdin.read().splitlines()

    if opts.verbose:
        for line in lines:
            sys.stdout.write(line + "\n")
        sys.stdout.flush()

    batch = [_build_entry(line, service, opts.mode) for line in lines if line]

    if not batch:
        return

    with httpx.Client() as client:
        # Ship in chunks of BATCH_SIZE
        for i in range(0, len(batch), BATCH_SIZE):
            _send_batch(client, batch[i : i + BATCH_SIZE])


if __name__ == "__main__":
    app()
