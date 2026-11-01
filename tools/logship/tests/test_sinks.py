"""Destination wire contracts against mock HTTP and temporary TLS listeners."""

import json
import socket
import ssl
import threading

import httpx
import pytest
import trustme

from logship.sinks import (
    ConfigurationError, DeliveryError, HttpSink, PapertrailSink,
    SinkConfig, _nanoseconds, configure, sink_for,
)


@pytest.fixture
def entry():
    return {
        "time": "2026-10-25T19:00:13.755Z", "hostname": "web-1",
        "service": "backend", "level": "warn", "message": "request failed",
        "metadata": {"request_id": "Request-ABC", "status": 503},
    }


@pytest.mark.parametrize("url", [
    "ftp://example.test/ingest", "https://", "https://example.test:bad/",
    "https://user:private@example.test/ingest", "https://example.test/?key=private",
    "https://example.test/#private", "https://example.test/with space",
    "https://example.test/\nprivate",
])
def test_rejects_invalid_destination_without_echoing_its_value(url):
    with pytest.raises(ConfigurationError) as error:
        configure("logtide", endpoint=url, environ={})
    assert "private" not in str(error.value)


def test_logtide_preserves_environment_and_local_default():
    config = configure("logtide", environ={"LOGTIDE_API_KEY": "private"})
    assert config.endpoint == "http://127.0.0.1:8080/api/v1/ingest"
    assert config.headers == {"X-API-Key": "private"}
    assert "private" not in repr(config)


def test_explicit_destination_overrides_provider_environment():
    config = configure("loki", endpoint="https://logs.example/loki/api/v1/push", environ={
        "LOKI_URL": "https://old.example/push", "LOKI_TOKEN": "private",
        "LOKI_TENANT_ID": "tenant-1",
    })
    assert config.endpoint == "https://logs.example/loki/api/v1/push"
    assert config.headers == {"Authorization": "Bearer private", "X-Scope-OrgID": "tenant-1"}
    assert config.destination == "logs.example"
    assert "private" not in repr(config)


def test_loki_cloud_basic_auth():
    config = configure("loki", environ={"LOKI_USERNAME": "123", "LOKI_PASSWORD": "private"})
    assert config.auth == ("123", "private")


@pytest.mark.parametrize("env", [
    {"LOKI_USERNAME": "123"}, {"LOKI_PASSWORD": "private"},
    {"LOKI_USERNAME": "123", "LOKI_PASSWORD": "private", "LOKI_TOKEN": "private"},
    {"LOKI_TOKEN": "private\r\nheader"}, {"LOKI_TENANT_ID": "bad\nheader"},
])
def test_rejects_incomplete_or_ambiguous_loki_auth(env):
    with pytest.raises(ConfigurationError):
        configure("loki", environ=env)


def test_datadog_requires_explicit_region_and_credentials():
    with pytest.raises(ConfigurationError, match="DATADOG_URL"):
        configure("datadog", environ={"DD_API_KEY": "private"})
    with pytest.raises(ConfigurationError, match="DD_API_KEY"):
        configure("datadog", environ={"DATADOG_URL": "https://intake.example/api/v2/logs"})
    with pytest.raises(ConfigurationError, match="HTTPS"):
        configure("datadog", endpoint="http://intake.example/api/v2/logs", environ={"DD_API_KEY": "private"})


@pytest.mark.parametrize("url", ["udp://logs.example:123", "tcp://logs.example:123",
    "tls://logs.example", "tls://logs.example:0", "tls://logs.example:65536", "tls://logs.example:123/path"])
def test_papertrail_requires_assigned_tls_destination(url):
    with pytest.raises(ConfigurationError):
        configure("papertrail", endpoint=url, environ={})


def test_papertrail_host_and_port_and_verified_context():
    config = configure("papertrail", environ={"PAPERTRAIL_HOST": "logs1.papertrailapp.com", "PAPERTRAIL_PORT": "12345"})
    assert config.endpoint == "tls://logs1.papertrailapp.com:12345"
    context = config.tls_context()
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.minimum_version >= ssl.TLSVersion.TLSv1_2


def test_missing_papertrail_destination_and_ca_file_fail_locally():
    with pytest.raises(ConfigurationError):
        configure("papertrail", environ={})
    with pytest.raises(ConfigurationError, match="CA file"):
        configure("loki", ca_file="/no/such/logship-ca.pem", environ={})


@pytest.mark.parametrize("backend,status,env", [
    ("logtide", 200, {"LOGTIDE_API_KEY": "private"}),
    ("loki", 204, {"LOKI_USERNAME": "123", "LOKI_PASSWORD": "private"}),
    ("datadog", 202, {"DD_API_KEY": "private"}),
])
def test_http_auth_wire_formats_and_request_id_survive(entry, backend, status, env):
    captured = []
    def receive(request):
        captured.append(request)
        return httpx.Response(status)
    config = configure(backend, endpoint="https://intake.example/ingest", environ=env)
    sink = sink_for(config)
    with httpx.Client(transport=httpx.MockTransport(receive)) as client:
        sink.send(client, [entry])
    request = captured[0]
    body = json.loads(request.content)
    if backend == "logtide":
        assert request.headers["x-api-key"] == "private"
        assert body == {"logs": [entry]}
    elif backend == "loki":
        assert request.headers["authorization"].startswith("Basic ")
        stream = body["streams"][0]
        assert stream["stream"] == {"service": "backend", "host": "web-1"}
        timestamp, line = stream["values"][0]
        assert timestamp == "1792954813755000000"
        assert json.loads(line) == entry
        assert "Request-ABC" not in json.dumps(stream["stream"])
    else:
        assert request.headers["dd-api-key"] == "private"
        assert body[0]["timestamp"] == 1792954813755
        assert body[0]["status"] == "warn"
        assert body[0]["metadata"] == entry["metadata"]


def test_loki_groups_records_and_sorts_within_each_stream(entry):
    sink = HttpSink(configure("loki", environ={}))
    later = {**entry, "time": "2026-10-25T19:00:14Z"}
    other = {**entry, "service": "caddy"}
    streams = sink.payload([later, entry, other])["streams"]
    assert len(streams) == 2
    assert [row[0] for row in streams[0]["values"]] == ["1792954813755000000", "1792954814000000000"]


def test_timestamp_conversion_uses_integer_precision():
    assert _nanoseconds("1970-01-01T00:00:00.000001Z") == "1000"
    assert _nanoseconds("2026-10-25T12:00:13.755-07:00") == "1792954813755000000"


@pytest.mark.parametrize("backend,status,retryable", [
    ("logtide", 401, False), ("logtide", 429, True), ("datadog", 503, True),
    ("loki", 260, False), ("loki", 302, False),
])
def test_rejections_are_explicit_and_do_not_include_response_body(entry, backend, status, retryable):
    config = SinkConfig(backend, "https://intake.example/ingest")
    with httpx.Client(transport=httpx.MockTransport(lambda request: httpx.Response(status, text="private"))) as client:
        with pytest.raises(DeliveryError) as error:
            HttpSink(config).send(client, [entry])
    assert error.value.status == status
    assert error.value.retryable is retryable
    assert "private" not in str(error.value)


def test_papertrail_frame_preserves_metadata_and_escapes_line_boundaries(entry):
    entry = {**entry, "hostname": "bad\nhost", "service": "a service", "message": "one\r\ntwo"}
    frame = PapertrailSink(SinkConfig("papertrail", "tls://localhost:12345")).frame(entry)
    assert frame.startswith(b"<12>1 2026-10-25T19:00:13.755Z bad_host a_service - - - ")
    assert frame.count(b"\n") == 1
    assert b"\r" not in frame
    assert json.loads(frame.split(b" - - - ", 1)[1]) == entry


def test_real_papertrail_tls_transport(entry, tmp_path):
    ca = trustme.CA()
    certificate = ca.issue_cert("localhost")
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    certificate.configure_cert(context)
    ca_path = tmp_path / "ca.pem"
    ca.cert_pem.write_to_path(ca_path)
    received = []
    errors = []
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(5)
        def serve():
            try:
                raw, _ = listener.accept()
                with context.wrap_socket(raw, server_side=True) as connection:
                    connection.settimeout(5)
                    chunks = []
                    while chunk := connection.recv(65536):
                        chunks.append(chunk)
                    received.append(b"".join(chunks))
                    connection.unwrap().close()
            except Exception as error:
                errors.append(error)
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        config = configure("papertrail", endpoint=f"tls://localhost:{listener.getsockname()[1]}", ca_file=str(ca_path), environ={})
        PapertrailSink(config).send(None, [entry, entry])
        thread.join(timeout=6)
        assert not thread.is_alive()
    assert not errors
    frames = received[0].splitlines()
    assert len(frames) == 2
    assert all(json.loads(frame.split(b" - - - ", 1)[1])["metadata"]["request_id"] == "Request-ABC" for frame in frames)


@pytest.mark.parametrize("trust_ca", [False, True])
def test_papertrail_rejects_untrusted_certificates_and_hostname_mismatch(entry, tmp_path, trust_ca):
    ca = trustme.CA()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ca.issue_cert("localhost").configure_cert(context)
    ca_path = tmp_path / "ca.pem"
    ca.cert_pem.write_to_path(ca_path)
    received = []
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(5)
        def serve():
            raw, _ = listener.accept()
            try:
                with context.wrap_socket(raw, server_side=True) as connection:
                    received.append(connection.recv(65536))
            except ssl.SSLError:
                raw.close()
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        host = "127.0.0.1" if trust_ca else "localhost"
        config = configure("papertrail", endpoint=f"tls://{host}:{listener.getsockname()[1]}", ca_file=str(ca_path) if trust_ca else None, environ={})
        with pytest.raises(ssl.SSLCertVerificationError):
            PapertrailSink(config).send(None, [entry])
        thread.join(timeout=6)
        assert not thread.is_alive()
    assert received == []
