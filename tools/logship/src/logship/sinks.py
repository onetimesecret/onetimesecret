"""Destination configuration and wire formats; no stdin or queue ownership."""

from dataclasses import dataclass, field
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import socket
import ssl
from typing import Literal, Mapping
from urllib.parse import urlsplit

import httpx

Backend = Literal["logtide", "papertrail", "loki", "datadog"]
BACKENDS = ("logtide", "papertrail", "loki", "datadog")


class ConfigurationError(ValueError):
    """A local configuration error, with no credential values in its message."""


class DeliveryError(Exception):
    def __init__(self, status: int, retryable: bool = False):
        super().__init__(f"destination rejected batch (status {status})")
        self.status = status
        self.retryable = retryable


def validate_endpoint(endpoint: str, *, tls_syslog: bool = False) -> None:
    try:
        parsed = urlsplit(endpoint)
        port = parsed.port
    except ValueError:
        raise ConfigurationError("destination URL has an invalid host or port") from None
    schemes = ("tls",) if tls_syslog else ("http", "https")
    if parsed.scheme not in schemes or not parsed.hostname:
        raise ConfigurationError("destination URL has an unsupported scheme or missing host")
    if parsed.username is not None or parsed.password is not None:
        raise ConfigurationError("put credentials in destination environment variables, not URLs")
    if parsed.query or parsed.fragment or re.search(r"[\s\x00-\x1f\x7f]", endpoint):
        raise ConfigurationError("destination URL cannot contain queries, fragments or whitespace")
    if tls_syslog and (port is None or port < 1 or parsed.path not in ("", "/")):
        raise ConfigurationError("Papertrail requires tls://host:port with no path")


@dataclass(frozen=True)
class SinkConfig:
    backend: Backend
    endpoint: str
    headers: dict[str, str] = field(default_factory=dict, repr=False)
    auth: tuple[str, str] | None = field(default=None, repr=False)
    ca_file: str | None = None

    def tls_context(self) -> ssl.SSLContext:
        context = ssl.create_default_context(cafile=self.ca_file)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        return context

    @property
    def destination(self) -> str:
        """A diagnostic label without a URL path or credentials."""
        parsed = urlsplit(self.endpoint)
        return f"{parsed.hostname}:{parsed.port}" if parsed.port else str(parsed.hostname)


def configure(
    backend: Backend,
    *,
    endpoint: str | None = None,
    ca_file: str | None = None,
    environ: Mapping[str, str] | None = None,
) -> SinkConfig:
    env = os.environ if environ is None else environ
    if backend not in BACKENDS:
        raise ConfigurationError("unknown backend; choose logtide, papertrail, loki or datadog")
    headers: dict[str, str] = {}
    auth = None
    if backend == "logtide":
        endpoint = endpoint or env.get("LOGTIDE_URL", "http://127.0.0.1:8080/api/v1/ingest")
        headers["X-API-Key"] = env.get("LOGTIDE_API_KEY", "CHANGEME")
    elif backend == "papertrail":
        endpoint = endpoint or env.get("PAPERTRAIL_URL")
        if not endpoint:
            host, port = env.get("PAPERTRAIL_HOST"), env.get("PAPERTRAIL_PORT")
            if not host or not port:
                raise ConfigurationError("set PAPERTRAIL_HOST and PAPERTRAIL_PORT, or PAPERTRAIL_URL")
            endpoint = f"tls://{host}:{port}"
    elif backend == "loki":
        endpoint = endpoint or env.get("LOKI_URL", "http://127.0.0.1:3100/loki/api/v1/push")
        username, password = env.get("LOKI_USERNAME"), env.get("LOKI_PASSWORD")
        token = env.get("LOKI_TOKEN")
        if bool(username) != bool(password):
            raise ConfigurationError("set both LOKI_USERNAME and LOKI_PASSWORD for basic auth")
        if token and username:
            raise ConfigurationError("choose Loki basic auth or LOKI_TOKEN, not both")
        if username and password:
            auth = (username, password)
        elif token:
            headers["Authorization"] = f"Bearer {token}"
        if tenant := env.get("LOKI_TENANT_ID"):
            headers["X-Scope-OrgID"] = tenant
    else:
        # The operator chooses the regional intake; no implicit cross-region default.
        endpoint = endpoint or env.get("DATADOG_URL")
        if not endpoint:
            raise ConfigurationError("set DATADOG_URL to your regional /api/v2/logs intake")
        key = env.get("DD_API_KEY")
        if not key:
            raise ConfigurationError("set DD_API_KEY for Datadog")
        headers["DD-API-KEY"] = key
    validate_endpoint(endpoint, tls_syslog=backend == "papertrail")
    if backend == "datadog" and urlsplit(endpoint).scheme != "https":
        raise ConfigurationError("Datadog requires an HTTPS intake URL")
    if ca_file and not Path(ca_file).is_file():
        raise ConfigurationError("CA file does not exist or is not a regular file")
    for value in [*headers.values(), *(auth or ())]:
        if re.search(r"[\x00-\x1f\x7f]", value):
            raise ConfigurationError("destination credentials and tenant IDs cannot contain controls")
    return SinkConfig(backend, endpoint, headers, auth, ca_file)


def _timestamp(value: object) -> datetime:
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        return parsed.replace(tzinfo=timezone.utc) if parsed.tzinfo is None else parsed.astimezone(timezone.utc)
    except (TypeError, ValueError):
        return datetime.now(timezone.utc)


def _nanoseconds(value: object) -> str:
    delta = _timestamp(value) - datetime(1970, 1, 1, tzinfo=timezone.utc)
    return str((delta.days * 86400 + delta.seconds) * 1_000_000_000 + delta.microseconds * 1000)


def _level(value: object) -> str:
    level = str(value).lower()
    return {"warning": "warn", "fatal": "critical", "trace": "debug"}.get(level, level)


class HttpSink:
    def __init__(self, config: SinkConfig):
        self.config = config

    def payload(self, entries: list[dict]) -> dict | list:
        if self.config.backend == "logtide":
            return {"logs": entries}
        if self.config.backend == "datadog":
            return [{
                "timestamp": int(_nanoseconds(entry.get("time"))) // 1_000_000,
                "hostname": entry.get("hostname", "unknown"),
                "service": entry.get("service", "unknown"),
                "status": _level(entry.get("level", "info")),
                "message": entry.get("message", ""),
                "ddsource": "logship",
                "metadata": entry.get("metadata", {}),
            } for entry in entries]
        streams: dict[tuple[str, str], dict] = {}
        for entry in entries:
            key = (str(entry.get("service", "unknown")), str(entry.get("hostname", "unknown")))
            stream = streams.setdefault(key, {
                "stream": {"service": key[0], "host": key[1]}, "values": [],
            })
            # Retain the complete record, including request IDs, without adding
            # per-request stream labels or requiring Loki 3 structured metadata.
            stream["values"].append([
                _nanoseconds(entry.get("time")),
                json.dumps(entry, separators=(",", ":"), ensure_ascii=True),
            ])
        for stream in streams.values():
            stream["values"].sort(key=lambda row: int(row[0]))
        return {"streams": list(streams.values())}

    def send(self, client: httpx.Client, entries: list[dict]) -> None:
        response = client.post(
            self.config.endpoint, json=self.payload(entries),
            headers=self.config.headers, auth=self.config.auth, timeout=10,
        )
        expected = {"logtide": (200, 202), "loki": (204,), "datadog": (202,)}
        if response.status_code not in expected[self.config.backend]:
            # Loki can return 260 when ingestion is blocked: arbitrary 2xx is
            # not a sufficient acknowledgement for these provider protocols.
            raise DeliveryError(response.status_code, response.status_code == 429 or response.status_code >= 500)


def _syslog_field(value: object, limit: int) -> str:
    return re.sub(r"[^!-~]", "_", str(value))[:limit] or "-"


class PapertrailSink:
    def __init__(self, config: SinkConfig):
        self.config = config

    def frame(self, entry: dict) -> bytes:
        severity = {"critical": 2, "error": 3, "warn": 4, "notice": 5, "info": 6, "debug": 7}
        priority = 8 + severity.get(_level(entry.get("level", "info")), 6)
        timestamp = _timestamp(entry.get("time")).isoformat(timespec="milliseconds").replace("+00:00", "Z")
        host = _syslog_field(entry.get("hostname", "unknown"), 255)
        service = _syslog_field(entry.get("service", "unknown"), 48)
        # JSON escapes embedded CR/LF and preserves metadata in one syslog record.
        message = json.dumps(entry, separators=(",", ":"), ensure_ascii=True)
        return f"<{priority}>1 {timestamp} {host} {service} - - - {message}\n".encode("utf-8")

    def send(self, _client: httpx.Client, entries: list[dict]) -> None:
        parsed = urlsplit(self.config.endpoint)
        frames = b"".join(self.frame(entry) for entry in entries)
        if not frames:
            return
        context = self.config.tls_context()
        with socket.create_connection((parsed.hostname, parsed.port), timeout=10) as raw:
            with context.wrap_socket(raw, server_hostname=parsed.hostname) as connection:
                connection.settimeout(10)
                connection.sendall(frames)
                # Complete TLS close_notify before closing TCP. An immediate
                # close can race TLS 1.3 post-handshake tickets and reset the
                # receiver before it reads the application records.
                connection.unwrap().close()


def sink_for(config: SinkConfig) -> HttpSink | PapertrailSink:
    return PapertrailSink(config) if config.backend == "papertrail" else HttpSink(config)
