#!/usr/bin/env python3
# tools/logship/src/logship/cli.py

"""Stdin log shipping through the managed bin/logship command.

`follow SERVICE` uses an in-memory queue and timer/size-based batches.
`batch SERVICE` streams a finite input synchronously. Both normalize plain,
JSON, SemanticLogger metadata or Caddy records, then use one selected adapter:
LogTide (default), Papertrail TLS syslog, Loki, or Datadog.

See tools/logship/README.md for destination configuration and delivery behavior.
"""

import math
import os
import re
import signal
import ssl
import sys
import threading
import time
from dataclasses import dataclass, field
from queue import Empty, Full, Queue
from typing import Annotated
from urllib.parse import urlparse

import httpx
from cyclopts import App, Parameter

# -- Diagnostic logging --------------------------------------------------
#
# stdlib logging -> stderr with a logfmt-style suffix of key=value pairs.
# Keeps diagnostics consistent (timestamp, level, subcommand context) while
# avoiding any new deps. Destination payloads are unaffected.

from .diagnostics import _diag, _kv
from .entries import LogMode, _build_entry
from .sinks import (
    Backend, ConfigurationError, DeliveryError, HttpSink, PapertrailSink,
    configure, sink_for,
)

Sink = HttpSink | PapertrailSink


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

app = App(name="logship", help="Ship stdin logs to LogTide, Papertrail, Loki, or Datadog.")


@Parameter(name="*")
@dataclass
class Global:
    verbose: bool = False
    """Echo lines to stdout as well."""

    mode: LogMode = "json"
    """How to handle JSON log lines.

    plain    -- treat all input as text (original behavior)
    metadata -- parse JSON, extract structured fields into metadata
    json     -- parse JSON, send the full object as the message
    caddy    -- parse Caddy structured JSON access logs
    """

    backend: Annotated[Backend, Parameter(env_var="LOGSHIP_BACKEND")] = "logtide"
    """Destination adapter; defaults to LogTide for existing invocations."""

    url: Annotated[str | None, Parameter(env_var="LOGSHIP_URL")] = None
    """Override the destination's full ingestion URL."""

    ca_file: Annotated[str | None, Parameter(env_var="LOGSHIP_CA_FILE")] = None
    """Optional CA bundle for HTTPS or TLS syslog certificate verification."""

    shutdown_timeout: float = 35.0
    """Maximum seconds to drain follow's worker after EOF or interruption."""


@dataclass
class ShippingState:
    failed: threading.Event = field(default_factory=threading.Event)
    crashed: threading.Event = field(default_factory=threading.Event)


def _configured_sink(opts: Global) -> Sink:
    try:
        if not math.isfinite(opts.shutdown_timeout) or opts.shutdown_timeout <= 0:
            raise ConfigurationError("shutdown timeout must be a finite positive number")
        env = dict(os.environ)
        env.update(LOGTIDE_URL=LOGTIDE_URL, LOGTIDE_API_KEY=LOGTIDE_API_KEY)
        config = configure(opts.backend, endpoint=opts.url, ca_file=opts.ca_file, environ=env)
        config.tls_context()
        return sink_for(config)
    except ConfigurationError as error:
        _diag.error("%s", _kv(event="invalid_configuration", reason=str(error)))
    except (OSError, ssl.SSLError) as error:
        _diag.error("%s", _kv(event="invalid_configuration", exc_type=type(error).__name__))
    raise SystemExit(2)


def _client(sink: Sink) -> httpx.Client:
    return httpx.Client(verify=sink.config.tls_context())


def _preflight(command: str, service: str, mode: LogMode, sink: Sink | None = None) -> None:
    """Validate locally; retain the existing LogTide empty-batch probe only."""
    _validate_service(service)
    if sink is None:
        _validate_url(LOGTIDE_URL)
        sink = _configured_sink(Global())
    config = sink.config
    key = config.headers.get("X-API-Key", "")
    _diag.info("%s", _kv(
        event="startup", subcommand=command, service=service, mode=mode,
        backend=config.backend, destination=config.destination,
        api_key_configured=key != "", api_key_is_default=key == "CHANGEME",
    ))
    if config.backend != "logtide":
        return
    if key == "CHANGEME":
        _diag.warning("%s", _kv(event="default_api_key", hint="set LOGTIDE_API_KEY"))
    try:
        with _client(sink) as client:
            response = client.post(config.endpoint, json={"logs": []}, headers=config.headers, timeout=5)
        if response.status_code in (401, 403):
            _diag.error("%s", _kv(event="preflight_auth_failed", status=response.status_code))
            raise SystemExit(1)
        if response.status_code >= 500:
            _diag.warning("%s", _kv(event="preflight_server_error", status=response.status_code))
        else:
            _diag.info("%s", _kv(event="preflight_ok", status=response.status_code))
    except httpx.ConnectError as error:
        _diag.warning("%s", _kv(event="preflight_unreachable", exc_type=type(error).__name__))
    except httpx.HTTPError as error:
        _diag.warning("%s", _kv(event="preflight_error", exc_type=type(error).__name__))


# -- Delivery and retries ------------------------------------------------


_SEND_RETRIES = 2
_SEND_BACKOFF = 0.5  # seconds, doubled each retry


def _is_retryable(error: Exception) -> bool:
    if isinstance(error, DeliveryError):
        return error.retryable
    cause: BaseException | None = error
    while cause is not None:
        if isinstance(cause, ssl.SSLCertVerificationError):
            return False
        cause = cause.__cause__
    if isinstance(error, (httpx.NetworkError, httpx.TimeoutException)):
        return True
    if isinstance(error, httpx.HTTPStatusError):
        return error.response.status_code == 429 or error.response.status_code >= 500
    return isinstance(error, OSError) and not isinstance(error, ssl.SSLError)


def _send_batch(client: httpx.Client, batch: list[dict], sink: Sink | None = None) -> bool:
    sink = sink or sink_for(configure("logtide", endpoint=LOGTIDE_URL, environ={"LOGTIDE_API_KEY": LOGTIDE_API_KEY}))
    delay = _SEND_BACKOFF
    for attempt in range(_SEND_RETRIES + 1):
        try:
            sink.send(client, batch)
            return True
        except (DeliveryError, httpx.HTTPError, OSError) as error:
            status = error.status if isinstance(error, DeliveryError) else getattr(getattr(error, "response", None), "status_code", None)
            if _is_retryable(error) and attempt < _SEND_RETRIES:
                _diag.warning("%s", _kv(
                    event="send_retry", backend=sink.config.backend, attempt=attempt + 1,
                    max_attempts=_SEND_RETRIES + 1, batch_size=len(batch), status=status,
                    backoff=delay, exc_type=type(error).__name__,
                ))
                time.sleep(delay)
                delay *= 2
                continue
            _diag.error("%s", _kv(
                event="send_failed", backend=sink.config.backend, attempt=attempt + 1,
                batch_size=len(batch), status=status, exc_type=type(error).__name__,
            ))
            return False
    return False


def _shipper(queue: Queue, service: str, mode: LogMode, sink: Sink | None = None, state: ShippingState | None = None):
    state = state or ShippingState()
    sink = sink or _configured_sink(Global(mode=mode))
    pending: list[dict] = []
    last_flush = time.monotonic()
    reason = "shutdown_sentinel"
    try:
        with _client(sink) as client:
            while True:
                try:
                    line = queue.get(timeout=0.5)
                    if line is None:
                        break
                    pending.append(_build_entry(line, service, mode))
                except Empty:
                    pass
                now = time.monotonic()
                if len(pending) >= BATCH_SIZE or (pending and now - last_flush > FLUSH_INTERVAL):
                    if not _send_batch(client, pending, sink):
                        state.failed.set()
                    pending = []
                    last_flush = now
            if pending and not _send_batch(client, pending, sink):
                state.failed.set()
    except Exception as error:
        state.failed.set()
        state.crashed.set()
        reason = "exception"
        _diag.error("%s", _kv(event="shipper_crash", exc_type=type(error).__name__))
    finally:
        _diag.info("%s", _kv(event="shipper_exit", reason=reason))


def _drain(queue: Queue, thread: threading.Thread, state: ShippingState, timeout: float) -> None:
    deadline = time.monotonic() + timeout
    while True:
        try:
            queue.put(None, timeout=min(0.1, max(0, deadline - time.monotonic())))
            break
        except Full:
            if not thread.is_alive() or time.monotonic() >= deadline:
                state.failed.set()
                break
    thread.join(timeout=max(0, deadline - time.monotonic()))
    if thread.is_alive():
        state.failed.set()
        _diag.error("%s", _kv(event="shipper_join_timeout", seconds=timeout))


# -- Subcommands ---------------------------------------------------------


@app.command
def follow(service: str, *, opts: Global = Global()) -> int:
    """Read stdin continuously and ship to the selected destination in batches.

    Use with long-running pipes (process managers, ``tail -f``).
    Lines are queued and shipped by a background thread so stdin is
    never blocked by destination latency.

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
    sink = _configured_sink(opts)
    _preflight("follow", service, opts.mode, sink)
    state = ShippingState()

    queue: Queue = Queue(maxsize=_QUEUE_MAXSIZE)
    thread = threading.Thread(
        target=_shipper, args=(queue, service, opts.mode, sink, state), daemon=True
    )
    thread.start()

    stop_reason = "eof"
    backpressure_logged = False
    dropped = 0                 # running total for current saturation episode
    last_reported = 0           # last value of `dropped` we emitted
    try:
        for line in sys.stdin:
            if state.crashed.is_set():
                stop_reason = "shipper_crash"
                break
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
            except Full:
                state.failed.set()
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
                except (Empty, Full):
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
            _kv(event="reader_crash", exc_type=type(e).__name__),
        )
        raise
    finally:
        _diag.info(
            "%s", _kv(event="reader_exit", reason=stop_reason)
        )
        _drain(queue, thread, state, opts.shutdown_timeout)
    return int(state.failed.is_set())


@app.command
def batch(service: str, *, opts: Global = Global()) -> int:
    """Read stdin to EOF and ship to the selected destination in batches.

    Use for one-shot imports (``cat logfile | bin/logship batch ...``).
    Reads synchronously (no background thread) and ships each batch as
    it fills, so memory stays bounded. Do NOT use with ``tail -f`` or
    other never-ending streams — use ``follow`` for those.

    Parameters
    ----------
    service
        Service name attached to each log entry (e.g. "backend", "caddy-proxy").
    """
    sink = _configured_sink(opts)
    _preflight("batch", service, opts.mode, sink)
    failed = False

    entries: list[dict] = []

    with _client(sink) as client:
        for line in sys.stdin:
            line = line.rstrip("\n")
            if opts.verbose:
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            if not line:
                continue
            entries.append(_build_entry(line, service, opts.mode))
            if len(entries) >= BATCH_SIZE:
                failed = not _send_batch(client, entries, sink) or failed
                entries = []

        if entries:
            failed = not _send_batch(client, entries, sink) or failed

    return int(failed)


def _interrupt(_signum, _frame):
    raise KeyboardInterrupt


def main():
    previous = signal.signal(signal.SIGTERM, _interrupt)
    try:
        return app()
    except KeyboardInterrupt:
        return 130
    finally:
        signal.signal(signal.SIGTERM, previous)


if __name__ == "__main__":
    raise SystemExit(main())
