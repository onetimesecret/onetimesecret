#!/usr/bin/env python3
# tools/logship/src/logship/cli.py

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
               Request details (request_id, remote_ip, proto, TLS, user_agent)
               go into LogTide `metadata`. Machine hostname is used since Caddy
               doesn't include it in log output.

Plain text lines always use the text path regardless of mode.

Usage:
    # Follow a process manager (default --mode json)
    LOG_FORMATTER=json bin/backend | bin/logship follow backend

    # Batch-ship an existing log file with text-mode fallback
    cat /var/log/app.log | bin/logship batch backend --mode plain

    # Use metadata mode for structured fields without pipeline parsing
    LOG_FORMATTER=json bin/backend | bin/logship follow backend --mode metadata

    # Follow Caddy access logs
    tail -f /var/log/caddy/access.log | bin/logship follow caddy-proxy --mode caddy
"""

import os
import re
import sys
import threading
import time
from dataclasses import dataclass
from queue import Empty, Queue
from urllib.parse import urlparse

import httpx
from cyclopts import App, Parameter

# -- Diagnostic logging --------------------------------------------------
#
# stdlib logging -> stderr with a logfmt-style suffix of key=value pairs.
# Keeps diagnostics consistent (timestamp, level, subcommand context) while
# avoiding any new deps. Payloads shipped to LogTide are unaffected.

from .diagnostics import _diag, _kv, _snippet
from .entries import LogMode, _build_entry


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


def _preflight(command: str, service: str, mode: LogMode) -> None:
    """Print startup banner and verify LogTide connectivity and auth.

    Sends an empty batch to the ingest endpoint. Exits on auth failure
    (no point reading stdin if every batch will be rejected). Warns on
    connection errors but continues (server may come up later).
    """
    _validate_service(service)
    _validate_url(LOGTIDE_URL)

    # Log boolean flags about the key rather than any derived form of it,
    # to avoid CodeQL clear-text-logging flags on masked-secret output.
    _diag.info(
        "%s",
        _kv(
            event="startup",
            subcommand=command,
            service=service,
            mode=mode,
            url=LOGTIDE_URL,
            api_key_configured=LOGTIDE_API_KEY != "",
            api_key_is_default=LOGTIDE_API_KEY == "CHANGEME",
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


def main():
    app()


if __name__ == "__main__":
    main()
