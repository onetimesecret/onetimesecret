#!/usr/bin/env python3

# scripts/logtide-ship.py

"""logtide-ship - pipe stdin to LogTide"""

import json
import re
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from queue import Empty, Queue

import httpx
from cyclopts import App, Parameter

LOGTIDE_URL = "http://127.0.0.1:8080/api/v1/ingest"
API_KEY = "lp_b2d8d9a5aebf0566d7cdc52603a537bac511f9d8708bae0141b0ee28ea50851b"
BATCH_SIZE = 100
FLUSH_INTERVAL = 2.0

app = App(name="logtide-ship", help="Ship logs to LogTide.")


@Parameter(name="*")
@dataclass
class Global:
    verbose: bool = False
    """Echo lines to stdout as well."""


def detect_level(msg: str) -> str:
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


_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")


def _now() -> str:
    return (
        datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
    )


def _try_parse_json(line: str) -> dict | None:
    if not line.startswith("{"):
        return None
    try:
        return json.loads(line)
    except json.JSONDecodeError:
        return None


def _build_entry(line: str, service: str) -> dict:
    raw = _try_parse_json(line)
    if raw:
        return _build_entry_from_json(raw, service)
    return _build_entry_from_text(line, service)


def _build_entry_from_json(raw: dict, service: str) -> dict:
    metadata = {
        k: v
        for k, v in {
            "logger": raw.get("name"),
            "pid": raw.get("pid"),
            "thread": raw.get("thread"),
            "host": raw.get("host"),
        }.items()
        if v is not None
    }
    payload = raw.get("payload")
    if isinstance(payload, dict):
        metadata.update(payload)

    entry = {
        "time": raw.get("timestamp", _now()),
        "service": service,
        "level": raw.get("level", "info"),
        "message": raw.get("message", ""),
    }
    if metadata:
        entry["metadata"] = metadata
    return entry


def _build_entry_from_text(line: str, service: str) -> dict:
    line = _ANSI_RE.sub("", line)
    return {
        "time": _now(),
        "service": service,
        "level": detect_level(line),
        "message": line,
    }


def _send_batch(client: httpx.Client, batch: list[dict]) -> None:
    try:
        resp = client.post(
            LOGTIDE_URL,
            json={"logs": batch},
            headers={"X-API-Key": API_KEY},
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


def _shipper(queue: Queue, service: str):
    batch: list[dict] = []
    last_flush = time.monotonic()

    with httpx.Client() as client:
        while True:
            try:
                line = queue.get(timeout=0.5)
                if line is None:
                    break
                batch.append(_build_entry(line, service))
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
        target=_shipper, args=(queue, service), daemon=True
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

    batch = [_build_entry(line, service) for line in lines if line]

    if not batch:
        return

    with httpx.Client() as client:
        # Ship in chunks of BATCH_SIZE
        for i in range(0, len(batch), BATCH_SIZE):
            _send_batch(client, batch[i : i + BATCH_SIZE])


if __name__ == "__main__":
    app()
