"""Exercise destination selection, delivery outcomes and bounded worker shutdown."""

import io
import json
import os
from pathlib import Path
from queue import Queue
import signal
import ssl
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import httpx
import pytest

from logship import cli, entries
from logship.sinks import configure, sink_for


@pytest.fixture
def http_capture(monkeypatch):
    requests = []
    responses = []
    real_client = httpx.Client
    def receive(request):
        requests.append(request)
        status = responses.pop(0) if responses else 202
        return httpx.Response(status, text="private-response-material")
    transport = httpx.MockTransport(receive)
    monkeypatch.setattr(cli.httpx, "Client", lambda *args, **kwargs: real_client(transport=transport))
    monkeypatch.setattr(cli.time, "sleep", lambda seconds: None)
    return requests, responses


@pytest.mark.parametrize("backend,status,env", [
    ("logtide", 200, {}),
    ("loki", 204, {}),
    ("datadog", 202, {"DD_API_KEY": "private-key"}),
])
def test_cli_selects_backend_and_ships_correlation_metadata(monkeypatch, http_capture, backend, status, env):
    requests, responses = http_capture
    responses.extend([status] * 4)
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    monkeypatch.delenv("LOGSHIP_BACKEND", raising=False)
    monkeypatch.setattr(sys, "stdin", io.StringIO('{"message":"hello","payload":{"request_id":"Request-ABC"}}\n'))
    with pytest.raises(SystemExit) as result:
        cli.app(["batch", "backend", "--backend", backend, "--url", "https://intake.example/ingest", "--mode", "metadata"])
    assert result.value.code == 0
    body = json.loads(requests[-1].content)
    if backend == "logtide":
        record = body["logs"][0]
    elif backend == "loki":
        record = json.loads(body["streams"][0]["values"][0][1])
    else:
        record = body[0]
    assert record["metadata"]["request_id"] == "Request-ABC"


def test_backend_and_destination_environment_options(monkeypatch, http_capture):
    requests, responses = http_capture
    responses.append(204)
    monkeypatch.setenv("LOGSHIP_BACKEND", "loki")
    monkeypatch.setenv("LOGSHIP_URL", "https://grafana.example/loki/api/v1/push")
    monkeypatch.setattr(sys, "stdin", io.StringIO("hello\n"))
    with pytest.raises(SystemExit) as result:
        cli.app(["batch", "backend", "--mode", "plain"])
    assert result.value.code == 0
    assert len(requests) == 1  # no provider-independent empty-batch probe
    assert str(requests[0].url) == "https://grafana.example/loki/api/v1/push"


def test_configuration_failure_never_consumes_input(monkeypatch):
    class Unreadable:
        def __iter__(self):
            raise AssertionError("configuration must fail before reading stdin")
    monkeypatch.delenv("DATADOG_URL", raising=False)
    monkeypatch.delenv("DD_API_KEY", raising=False)
    monkeypatch.setattr(sys, "stdin", Unreadable())
    with pytest.raises(SystemExit) as error:
        cli.batch("backend", opts=cli.Global(backend="datadog"))
    assert error.value.code == 2


def test_batch_returns_failure_and_still_attempts_later_batches(monkeypatch, http_capture):
    requests, responses = http_capture
    responses.extend([400, 202])
    monkeypatch.setenv("DD_API_KEY", "private-key")
    monkeypatch.setattr(cli, "BATCH_SIZE", 1)
    monkeypatch.setattr(sys, "stdin", io.StringIO("one\ntwo\n"))
    assert cli.batch("backend", opts=cli.Global(backend="datadog", url="https://intake.example/logs")) == 1
    assert len(requests) == 2


def test_rate_limit_retry_and_sanitized_diagnostics(monkeypatch, http_capture, caplog):
    requests, responses = http_capture
    responses.extend([429, 503, 202])
    sink = sink_for(configure("datadog", endpoint="https://intake.example/private-path", environ={"DD_API_KEY": "private-key"}))
    caplog.set_level("DEBUG", logger="logship")
    monkeypatch.setattr(cli._diag, "propagate", True)
    with httpx.Client() as client:
        assert cli._send_batch(client, [{"message": "private-log-payload"}], sink) is True
    assert len(requests) == 3
    assert "private-" not in caplog.text


def test_exhausted_retries_report_failure(http_capture):
    requests, responses = http_capture
    responses.extend([503, 503, 503])
    sink = sink_for(configure("loki", environ={}))
    with httpx.Client() as client:
        assert cli._send_batch(client, [{"message": "hello"}], sink) is False
    assert len(requests) == 3


@pytest.mark.parametrize("error_type", [httpx.ConnectTimeout, httpx.ReadError, httpx.WriteError])
def test_transient_network_errors_are_retryable(error_type):
    assert cli._is_retryable(error_type("private endpoint details")) is True


def test_certificate_verification_failure_is_not_retryable():
    error = httpx.ConnectError("private endpoint details")
    error.__cause__ = ssl.SSLCertVerificationError("untrusted certificate")
    assert cli._is_retryable(error) is False


def test_dead_worker_and_full_queue_cannot_block_shutdown():
    queue = Queue(maxsize=1)
    queue.put("pending")
    worker = threading.Thread(target=lambda: None)
    worker.start()
    worker.join()
    state = cli.ShippingState()
    started = time.monotonic()
    cli._drain(queue, worker, state, timeout=0.02)
    assert time.monotonic() - started < 1
    assert state.failed.is_set()


def test_follow_reports_a_worker_crash(monkeypatch):
    def crash(queue, service, mode, sink, state):
        state.failed.set()
        state.crashed.set()
    monkeypatch.setattr(cli, "_shipper", crash)
    monkeypatch.setattr(sys, "stdin", io.StringIO("one\ntwo\n"))
    assert cli.follow("backend", opts=cli.Global(backend="loki")) == 1


def test_follow_reports_drain_timeout_and_cleans_up_test_worker(monkeypatch):
    release = threading.Event()
    stopped = threading.Event()
    def hang(*args):
        release.wait(timeout=5)
        stopped.set()
    monkeypatch.setattr(cli, "_shipper", hang)
    monkeypatch.setattr(sys, "stdin", io.StringIO("one\n"))
    try:
        assert cli.follow("backend", opts=cli.Global(backend="loki", shutdown_timeout=0.02)) == 1
    finally:
        release.set()
        assert stopped.wait(timeout=2)


def test_invalid_json_diagnostic_does_not_sample_input(monkeypatch, caplog):
    monkeypatch.setattr(cli._diag, "propagate", True)
    caplog.set_level("DEBUG", logger="logship")
    assert entries._try_parse_json('{"token":"private-input') is None
    assert "private-input" not in caplog.text


def test_sigterm_exits_cleanly_while_stdin_remains_open():
    received = []
    accepted = threading.Event()
    class Receiver(BaseHTTPRequestHandler):
        def do_POST(self):
            received.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
            self.send_response(204)
            self.end_headers()
            accepted.set()
        def log_message(self, *args):
            pass
    with ThreadingHTTPServer(("127.0.0.1", 0), Receiver) as server:
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        env = {key: os.environ[key] for key in ("PATH", "HOME") if key in os.environ}
        child = subprocess.Popen([
            sys.executable, "-m", "logship", "follow", "backend", "--backend", "loki",
            "--url", f"http://127.0.0.1:{server.server_port}/loki/api/v1/push",
            "--mode", "plain", "--shutdown-timeout", "2",
        ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            text=True, env=env, cwd=Path(__file__).resolve().parents[3])
        try:
            child.stdin.write("hello\n" * 100)
            child.stdin.flush()
            assert accepted.wait(timeout=8), "child did not ship its first full batch"
            child.send_signal(signal.SIGTERM)
            assert child.wait(timeout=5) == 0
            assert sum(len(stream["values"]) for body in received for stream in body["streams"]) == 100
        finally:
            if child.poll() is None:
                child.kill()
                child.wait(timeout=3)
            child.stdin.close()
            child.stderr.close()
            server.shutdown()
            worker.join(timeout=3)
