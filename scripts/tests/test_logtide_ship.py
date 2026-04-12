# scripts/tests/test_logtide_ship.py

"""Tests for scripts/logtide-ship.py.

Run from repo root:
    python3 -m pytest scripts/tests/test_logtide_ship.py -v

Requirements: pytest, httpx. cyclopts is only required to import the module
itself; if it's missing the entire module skips. respx is not used — we mock
httpx via httpx.MockTransport + monkeypatching httpx.Client.
"""

from __future__ import annotations

import importlib.util
import io
import json
import logging
import os
import queue as queue_mod
import re
import socket
import sys
import threading
import time
from pathlib import Path

import httpx
import pytest

# -- Module loader ------------------------------------------------------
# logtide-ship.py has a hyphen, so we can't `import` it normally.

_SCRIPT = Path(__file__).resolve().parents[1] / "logtide-ship.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("logtide_ship", _SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(mod)
    except ModuleNotFoundError as e:
        pytest.skip(f"logtide-ship dependency missing: {e}")
    return mod


ls = _load_module()


# -- Helpers ------------------------------------------------------------


ISO_Z_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")


class FakeTransport(httpx.BaseTransport):
    """Records requests and returns scripted responses."""

    def __init__(self, responses):
        # responses: list of (status_code, body_dict) or callables
        self.responses = list(responses)
        self.requests = []

    def handle_request(self, request):
        self.requests.append(request)
        if not self.responses:
            return httpx.Response(200, json={"ok": True})
        item = self.responses.pop(0)
        if callable(item):
            return item(request)
        status, body = item
        return httpx.Response(status, json=body)


@pytest.fixture
def diag_caplog(caplog):
    """Capture logtide-ship diag logger. _diag has propagate=False, so
    temporarily enable propagation for the duration of the test."""
    prev = ls._diag.propagate
    ls._diag.propagate = True
    caplog.set_level(logging.DEBUG, logger="logtide-ship")
    yield caplog
    ls._diag.propagate = prev


def _patched_client(monkeypatch, transport):
    """Force httpx.Client() calls to use our transport."""
    real_client = httpx.Client

    def factory(*args, **kwargs):
        kwargs["transport"] = transport
        return real_client(*args, **kwargs)

    monkeypatch.setattr(ls.httpx, "Client", factory)


# -- _mask_key ----------------------------------------------------------


class TestMaskKey:
    def test_empty(self):
        assert ls._mask_key("") == "***"

    def test_short(self):
        assert ls._mask_key("abcd") == "***"
        assert ls._mask_key("abcdefgh") == "***"  # boundary: len==8

    def test_long(self):
        masked = ls._mask_key("sk-abcdef1234567890xyz")
        assert masked == "sk-a***xyz"

    def test_never_contains_full_key(self):
        key = "supersecretapikey123456"
        masked = ls._mask_key(key)
        assert key not in masked
        assert "secret" not in masked


# -- detect_level -------------------------------------------------------


class TestDetectLevel:
    @pytest.mark.parametrize(
        "msg,expected",
        [
            ("something FATAL happened", "critical"),
            ("CRITical path", "critical"),
            ("ERROR: boom", "error"),
            ("a WARNing sign", "warn"),
            ("DEBUG trace", "debug"),
            ("all good", "info"),
            ("", "info"),
        ],
    )
    def test_levels(self, msg, expected):
        assert ls.detect_level(msg) == expected


# -- _now ---------------------------------------------------------------


class TestNow:
    def test_z_suffix(self):
        s = ls._now()
        assert ISO_Z_RE.match(s), s
        assert s.endswith("Z")
        assert "+00:00" not in s


# -- Caddy duration parser ---------------------------------------------


class TestCaddyDuration:
    @pytest.mark.parametrize(
        "val,expected",
        [
            ("100ms", 100.0),
            ("1.5s", 1500.0),
            ("2m", 120000.0),
            ("1h", 3600000.0),
            ("250µs", 0.25),
            ("250us", 0.25),
            ("7.750ms", 7.75),
        ],
    )
    def test_go_duration_strings(self, val, expected):
        assert ls._parse_caddy_duration_ms(val) == expected

    def test_float_seconds(self):
        # duration_format number → float seconds
        assert ls._parse_caddy_duration_ms(0.074) == 74.0
        assert ls._parse_caddy_duration_ms(1) == 1000.0

    def test_malformed_returns_zero(self):
        assert ls._parse_caddy_duration_ms("bogus") == 0
        assert ls._parse_caddy_duration_ms("5xyz") == 0
        assert ls._parse_caddy_duration_ms(None) == 0

    def test_composite_not_supported_returns_zero(self):
        # _GO_DURATION_RE is anchored and doesn't handle composite units.
        # Documenting actual behavior: "1m30s" does not match.
        assert ls._parse_caddy_duration_ms("1m30s") == 0


# -- Caddy timestamp parser --------------------------------------------


class TestCaddyTimestamp:
    def test_unix_seconds_float(self):
        # 2022-03-09 21:30:01.524 UTC-ish
        out = ls._parse_caddy_ts(1646861401.524)
        assert ISO_Z_RE.match(out)
        assert out.startswith("2022-03-09T")

    def test_unix_milli_float(self):
        # > 1e12 → treated as millis
        out = ls._parse_caddy_ts(1646861401524.0)
        assert ISO_Z_RE.match(out)
        assert out.startswith("2022-03-09T")

    def test_both_forms_equivalent(self):
        a = ls._parse_caddy_ts(1646861401.524)
        b = ls._parse_caddy_ts(1646861401524.0)
        assert a == b


# -- Entry builders ----------------------------------------------------


class TestBuildEntryText:
    def test_strips_ansi(self):
        line = "\x1b[31mERROR: boom\x1b[0m"
        e = ls._build_entry_text(line, "svc")
        assert e["message"] == "ERROR: boom"
        assert e["level"] == "error"
        assert e["service"] == "svc"
        assert e["hostname"] == ls._HOSTNAME
        assert ISO_Z_RE.match(e["time"])

    def test_level_guess_info(self):
        e = ls._build_entry_text("just a message", "svc")
        assert e["level"] == "info"


class TestBuildEntryJson:
    def test_full_json_as_message(self):
        raw = {
            "timestamp": "2024-01-02T03:04:05.678Z",
            "host": "box-1",
            "level": "warn",
            "message": "hi",
            "name": "Onetime::App",
        }
        e = ls._build_entry_json(raw, "backend")
        assert e["time"] == "2024-01-02T03:04:05.678Z"
        assert e["hostname"] == "box-1"
        assert e["level"] == "warn"
        assert json.loads(e["message"]) == raw

    def test_fallbacks(self):
        e = ls._build_entry_json({}, "svc")
        assert ISO_Z_RE.match(e["time"])
        assert e["hostname"] == ls._HOSTNAME
        assert e["level"] == "info"


class TestBuildEntryMetadata:
    def test_extracts_fields(self):
        raw = {
            "timestamp": "2024-01-02T03:04:05.678Z",
            "host": "box-1",
            "level": "error",
            "message": "boom",
            "name": "Onetime::Secret",
            "pid": 1234,
            "thread": "main",
            "payload": {"user_id": "u_1", "secret_id": "s_1"},
        }
        e = ls._build_entry_metadata(raw, "backend")
        assert e["message"] == "boom"
        assert e["metadata"]["logger"] == "Onetime::Secret"
        assert e["metadata"]["pid"] == 1234
        assert e["metadata"]["thread"] == "main"
        assert e["metadata"]["user_id"] == "u_1"
        assert e["metadata"]["secret_id"] == "s_1"

    def test_no_metadata_key_when_empty(self):
        raw = {"message": "hi"}
        e = ls._build_entry_metadata(raw, "svc")
        assert "metadata" not in e
        assert e["hostname"] == ls._HOSTNAME


class TestBuildEntryCaddy:
    @pytest.fixture
    def sample(self):
        return {
            "level": "info",
            "ts": 1646861401.524,
            "logger": "http.log.access.log0",
            "status": 200,
            "size": 14131,
            "duration": "7.750ms",
            "request": {
                "remote_ip": "10.0.0.1",
                "client_ip": "203.0.113.7",
                "proto": "HTTP/2.0",
                "method": "GET",
                "host": "example.com",
                "uri": "/api/users",
                "headers": {"User-Agent": ["Mozilla/5.0"]},
                "tls": {"proto": "h2"},
            },
        }

    def test_message_format(self, sample):
        e = ls._build_entry_caddy(sample, "caddy")
        assert e["message"] == "GET /api/users 200 13.8kB 7.75ms"
        assert ISO_Z_RE.match(e["time"])
        assert e["hostname"] == ls._HOSTNAME  # Caddy doesn't ship host

    def test_metadata_populated(self, sample):
        e = ls._build_entry_caddy(sample, "caddy")
        md = e["metadata"]
        assert md["remote_ip"] == "10.0.0.1"
        assert md["client_ip"] == "203.0.113.7"
        assert md["status"] == 200
        assert md["size"] == 14131
        assert md["duration_ms"] == 7.75
        assert md["host"] == "example.com"
        assert md["proto"] == "HTTP/2.0"
        assert md["logger"] == "http.log.access.log0"
        assert md["tls_proto"] == "h2"
        assert md["user_agent"] == "Mozilla/5.0"

    def test_client_ip_equals_remote_ip_omitted(self, sample):
        sample["request"]["client_ip"] = sample["request"]["remote_ip"]
        e = ls._build_entry_caddy(sample, "caddy")
        assert "client_ip" not in e["metadata"]

    def test_unix_milli_timestamp(self, sample):
        sample["ts"] = 1646861401524.0
        e = ls._build_entry_caddy(sample, "caddy")
        assert e["time"].startswith("2022-03-09T")

    def test_float_duration_seconds(self, sample):
        sample["duration"] = 0.0775  # 77.5ms in float-seconds form
        e = ls._build_entry_caddy(sample, "caddy")
        assert e["metadata"]["duration_ms"] == 77.5

    def test_missing_ts_uses_now(self, sample):
        del sample["ts"]
        e = ls._build_entry_caddy(sample, "caddy")
        assert ISO_Z_RE.match(e["time"])


# -- _build_entry dispatch ---------------------------------------------


class TestBuildEntryDispatch:
    def test_plain_mode_ignores_json(self):
        line = '{"level":"warn","message":"hi"}'
        e = ls._build_entry(line, "svc", mode="plain")
        # plain always goes text path; raw line becomes the message
        assert e["message"] == line
        assert e["level"] == "warn"  # detect_level picks it up

    def test_non_json_line_in_json_mode_falls_through(self):
        e = ls._build_entry("plain startup banner", "svc", mode="json")
        assert e["message"] == "plain startup banner"

    def test_ansi_colored_line_in_metadata_mode(self):
        # ANSI-colored text doesn't start with '{' → text path
        line = "\x1b[31mERROR: boom\x1b[0m"
        e = ls._build_entry(line, "svc", mode="metadata")
        assert e["message"] == "ERROR: boom"
        assert e["level"] == "error"

    def test_semantic_logger_json_metadata_mode(self):
        raw = {
            "timestamp": "2024-01-02T03:04:05.678Z",
            "host": "h",
            "level": "info",
            "message": "m",
            "name": "L",
        }
        line = json.dumps(raw)
        e = ls._build_entry(line, "svc", mode="metadata")
        assert e["message"] == "m"
        assert e["metadata"]["logger"] == "L"

    def test_caddy_mode_routes_to_caddy_builder(self):
        raw = {"ts": 1646861401.5, "request": {"method": "GET", "uri": "/"}, "status": 200}
        line = json.dumps(raw)
        e = ls._build_entry(line, "svc", mode="caddy")
        assert "GET /" in e["message"]
        assert e["time"].startswith("2022-")


# -- _send_batch retry behavior ----------------------------------------


class TestSendBatch:
    def test_success_no_retry(self, monkeypatch):
        t = FakeTransport([(200, {"ok": True})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "hi"}])
        assert len(t.requests) == 1

    def test_retries_on_500_then_succeeds(self, monkeypatch):
        monkeypatch.setattr(ls.time, "sleep", lambda _s: None)
        t = FakeTransport([(500, {"err": "boom"}), (200, {"ok": True})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "hi"}])
        assert len(t.requests) == 2

    def test_retries_exhausted_on_503(self, monkeypatch, capsys):
        monkeypatch.setattr(ls.time, "sleep", lambda _s: None)
        # 3 attempts total (1 initial + 2 retries) all 503
        t = FakeTransport([(503, {}), (503, {}), (503, {})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "hi"}])
        assert len(t.requests) == 3

    def test_no_retry_on_401(self, monkeypatch):
        monkeypatch.setattr(ls.time, "sleep", lambda _s: None)
        t = FakeTransport([(401, {"err": "auth"}), (200, {"ok": True})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "hi"}])
        # _send_batch swallows the HTTPStatusError but doesn't retry 4xx
        assert len(t.requests) == 1

    def test_sends_correct_headers_and_body(self, monkeypatch):
        monkeypatch.setattr(ls, "LOGTIDE_API_KEY", "key-xyz")
        monkeypatch.setattr(ls, "LOGTIDE_URL", "http://test.local/ingest")
        t = FakeTransport([(200, {"ok": True})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "a"}, {"message": "b"}])
        req = t.requests[0]
        assert req.headers["X-API-Key"] == "key-xyz"
        body = json.loads(req.content)
        assert body == {"logs": [{"message": "a"}, {"message": "b"}]}


# -- _preflight --------------------------------------------------------


class TestPreflight:
    def test_exits_on_401(self, monkeypatch):
        t = FakeTransport([(401, {"err": "nope"})])
        _patched_client(monkeypatch, t)
        with pytest.raises(SystemExit) as exc:
            ls._preflight("follow", "svc", "json")
        assert exc.value.code == 1

    def test_exits_on_403(self, monkeypatch):
        t = FakeTransport([(403, {})])
        _patched_client(monkeypatch, t)
        with pytest.raises(SystemExit):
            ls._preflight("follow", "svc", "json")

    def test_success_on_200(self, monkeypatch, diag_caplog):
        t = FakeTransport([(200, {"ok": True})])
        _patched_client(monkeypatch, t)
        ls._preflight("follow", "svc", "json")
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=preflight_ok" in msgs
        assert "status=200" in msgs

    def test_success_on_400_empty_logs_rejected(self, monkeypatch, diag_caplog):
        # Some servers reject {"logs":[]} with 400 — still treated as auth OK
        t = FakeTransport([(400, {"err": "empty"})])
        _patched_client(monkeypatch, t)
        ls._preflight("follow", "svc", "json")
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=preflight_ok" in msgs
        assert "status=400" in msgs

    def test_connection_error_warns_but_continues(self, monkeypatch, diag_caplog):
        def boom(_req):
            raise httpx.ConnectError("refused")

        t = FakeTransport([boom])
        _patched_client(monkeypatch, t)
        ls._preflight("follow", "svc", "json")  # must not raise
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=preflight_unreachable" in msgs
        assert "refused" in msgs

    def test_5xx_warns_but_continues(self, monkeypatch, diag_caplog):
        t = FakeTransport([(503, {})])
        _patched_client(monkeypatch, t)
        ls._preflight("follow", "svc", "json")
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=preflight_server_error" in msgs
        assert "status=503" in msgs

    def test_banner_masks_key(self, monkeypatch, diag_caplog, capfd):
        monkeypatch.setattr(ls, "LOGTIDE_API_KEY", "supersecretapikey123456")
        t = FakeTransport([(200, {"ok": True})])
        _patched_client(monkeypatch, t)
        ls._preflight("follow", "svc", "json")
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        # Full secret must not appear in logged messages
        assert "supersecretapikey123456" not in msgs
        assert "supe***456" in msgs
        # Also verify it never hits the raw stderr stream
        err = capfd.readouterr().err
        assert "supersecretapikey123456" not in err

    def test_auth_failure_emits_event(self, monkeypatch, diag_caplog):
        t = FakeTransport([(401, {"err": "nope"})])
        _patched_client(monkeypatch, t)
        with pytest.raises(SystemExit):
            ls._preflight("follow", "svc", "json")
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=preflight_auth_failed" in msgs
        assert "status=401" in msgs


# -- follow / batch subcommands ----------------------------------------


class TestFollow:
    def test_skips_empty_lines_and_ships(self, monkeypatch):
        monkeypatch.setattr(ls.time, "sleep", lambda _s: None)
        t = FakeTransport([(200, {"ok": True})] * 10)
        _patched_client(monkeypatch, t)
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)

        input_lines = "line one\n\n   \nline two\n"
        monkeypatch.setattr(sys, "stdin", io.StringIO(input_lines))
        # shorten flush interval so test isn't slow
        monkeypatch.setattr(ls, "FLUSH_INTERVAL", 0.05)
        monkeypatch.setattr(ls, "BATCH_SIZE", 100)

        ls.follow("svc", opts=ls.Global(mode="plain"))

        # All batches together should contain both non-empty lines; blank
        # lines should never be queued/shipped.
        all_logs = []
        for req in t.requests:
            body = json.loads(req.content)
            all_logs.extend(body.get("logs", []))
        messages = [e["message"] for e in all_logs]
        assert "line one" in messages
        assert "line two" in messages
        assert "   " in messages  # whitespace-only is non-empty, not skipped
        assert "" not in messages

    def test_bounded_queue_constant(self):
        # Document the maxsize contract — producer now uses drop-oldest
        # when full, rather than blocking.
        assert ls._QUEUE_MAXSIZE == 10_000
        assert ls._QUEUE_RECOVERY_THRESHOLD == 5_000
        assert ls._DROP_REPORT_INTERVAL == 1000


class TestBatch:
    def test_streams_stdin(self, monkeypatch):
        """`batch` must iterate stdin, not call sys.stdin.read()."""
        t = FakeTransport([(200, {"ok": True})] * 5)
        _patched_client(monkeypatch, t)
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)

        class TrackingStdin(io.StringIO):
            read_called = False

            def read(self, *a, **k):
                TrackingStdin.read_called = True
                return super().read(*a, **k)

        stdin = TrackingStdin("a\nb\n\nc\n")
        monkeypatch.setattr(sys, "stdin", stdin)

        ls.batch("svc", opts=ls.Global(mode="plain"))

        assert TrackingStdin.read_called is False
        all_logs = []
        for req in t.requests:
            all_logs.extend(json.loads(req.content)["logs"])
        messages = [e["message"] for e in all_logs]
        assert messages == ["a", "b", "c"]

    def test_flushes_on_batch_size(self, monkeypatch):
        t = FakeTransport([(200, {"ok": True})] * 10)
        _patched_client(monkeypatch, t)
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)
        monkeypatch.setattr(ls, "BATCH_SIZE", 3)

        stdin = io.StringIO("\n".join(f"line{i}" for i in range(7)) + "\n")
        monkeypatch.setattr(sys, "stdin", stdin)
        ls.batch("svc", opts=ls.Global(mode="plain"))

        # 7 lines, batch size 3 → 3 batches (3, 3, 1)
        batch_sizes = [len(json.loads(r.content)["logs"]) for r in t.requests]
        assert batch_sizes == [3, 3, 1]

    def test_hostname_fallback(self, monkeypatch):
        """When source lacks host field, machine hostname is used."""
        t = FakeTransport([(200, {"ok": True})])
        _patched_client(monkeypatch, t)
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)

        raw = {"timestamp": "2024-01-01T00:00:00.000Z", "level": "info", "message": "x"}
        stdin = io.StringIO(json.dumps(raw) + "\n")
        monkeypatch.setattr(sys, "stdin", stdin)

        ls.batch("svc", opts=ls.Global(mode="metadata"))

        logs = json.loads(t.requests[0].content)["logs"]
        assert logs[0]["hostname"] == socket.gethostname()


# -- _validate_service -------------------------------------------------


class TestValidateService:
    def test_happy_path(self):
        ls._validate_service("backend")  # no raise

    def test_empty_exits(self, diag_caplog):
        with pytest.raises(SystemExit) as exc:
            ls._validate_service("")
        assert exc.value.code == 2
        assert any(
            "event=invalid_service" in r.getMessage() and "reason=empty" in r.getMessage()
            for r in diag_caplog.records
        )

    def test_whitespace_only_exits(self):
        with pytest.raises(SystemExit):
            ls._validate_service("   ")

    def test_too_long_exits(self, diag_caplog):
        with pytest.raises(SystemExit):
            ls._validate_service("x" * 129)
        assert any("reason=too_long" in r.getMessage() for r in diag_caplog.records)

    def test_boundary_128_ok(self):
        ls._validate_service("x" * 128)

    def test_control_char_exits(self, diag_caplog):
        with pytest.raises(SystemExit):
            ls._validate_service("bad\x00name")
        assert any("reason=control_chars" in r.getMessage() for r in diag_caplog.records)

    def test_newline_rejected(self):
        with pytest.raises(SystemExit):
            ls._validate_service("bad\nname")


# -- _validate_url -----------------------------------------------------


class TestValidateUrl:
    def test_happy_http(self):
        ls._validate_url("http://x")

    def test_happy_https_with_port_and_path(self):
        ls._validate_url("https://x:8080/path")

    def test_bare_token_exits(self, diag_caplog):
        with pytest.raises(SystemExit) as exc:
            ls._validate_url("foo")
        assert exc.value.code == 2
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=invalid_url" in msgs

    def test_ftp_scheme_exits(self, diag_caplog):
        with pytest.raises(SystemExit):
            ls._validate_url("ftp://x")
        assert any("reason=bad_scheme" in r.getMessage() for r in diag_caplog.records)

    def test_missing_host_exits(self, diag_caplog):
        with pytest.raises(SystemExit):
            ls._validate_url("http://")
        assert any("reason=missing_host" in r.getMessage() for r in diag_caplog.records)

    def test_preflight_invokes_url_validation(self, monkeypatch, diag_caplog):
        monkeypatch.setattr(ls, "LOGTIDE_URL", "ftp://nope")
        with pytest.raises(SystemExit):
            ls._preflight("follow", "svc", "json")
        assert any("event=invalid_url" in r.getMessage() for r in diag_caplog.records)


# -- _kv logfmt helper --------------------------------------------------


class TestKvHelper:
    def test_plain_values(self):
        assert ls._kv(a="1", b="2") == "a=1 b=2"

    def test_none_skipped(self):
        assert ls._kv(a="1", b=None, c="3") == "a=1 c=3"

    def test_quotes_spaces(self):
        assert ls._kv(msg="hello world") == 'msg="hello world"'

    def test_quotes_equals(self):
        assert ls._kv(x="a=b") == 'x="a=b"'

    def test_escapes_embedded_quote(self):
        out = ls._kv(x='say "hi"')
        assert out == 'x="say \\"hi\\""'

    def test_newline_passthrough(self):
        # _kv now escapes control chars including \n and quotes the value.
        out = ls._kv(x="line1\nline2")
        assert out == 'x="line1\\nline2"'
        # No actual newline survives into the logfmt output.
        assert "\n" not in out

    def test_control_char_newline_escaped(self):
        out = ls._kv(x="a\nb")
        assert out == 'x="a\\nb"'

    def test_control_char_cr_escaped(self):
        out = ls._kv(x="a\rb")
        assert out == 'x="a\\rb"'

    def test_control_char_tab_escaped(self):
        out = ls._kv(x="a\tb")
        assert out == 'x="a\\tb"'

    def test_raw_low_control_char_hex_escaped(self):
        out = ls._kv(x="a\x01b")
        assert out == 'x="a\\x01b"'

    def test_del_char_hex_escaped(self):
        out = ls._kv(x="a\x7fb")
        assert out == 'x="a\\x7fb"'

    def test_no_double_escape_literal_backslash_n(self):
        # Python source "foo\\n" is 4 chars: f, o, o, backslash, n (actually
        # 5 with the 'n'). There is no control char and no space/quote/=,
        # so _kv neither quotes nor backslash-doubles. Output stays literal.
        out = ls._kv(x="foo\\n")
        assert out == "x=foo\\n"
        # And specifically: no real newline character survived.
        assert "\n" not in out

    def test_no_double_escape_when_control_and_backslash_coexist(self):
        # Literal backslash+'n' AND a real newline in same value.
        # Doubling runs first: "\\" -> "\\\\"; then ctrl escape turns \n into "\\n".
        out = ls._kv(x="foo\\n\nbar")
        assert out == 'x="foo\\\\n\\nbar"'

    def test_space_regression_not_hex_escaped(self):
        # Regression: space must NOT be treated as a control char.
        assert ls._kv(msg="foo bar") == 'msg="foo bar"'
        assert "\\x20" not in ls._kv(msg="foo bar")


# -- follow queue_full backpressure ------------------------------------


class TestFollowDropOldest:
    """Follow's producer must never block. When the queue saturates it
    evicts the oldest line (drop-oldest) and keeps accepting new input.
    """

    def _install_nondraining_shipper(self, monkeypatch):
        """Install a _shipper stub that leaves whatever is in the queue
        alone until it sees the shutdown sentinel — so drop-oldest is
        the only way the queue can make room."""
        def fake_shipper(q, *a, **k):
            # Wait for shutdown sentinel only. Don't drain data items.
            while True:
                item = q.get()
                if item is None:
                    return
                # Put it back — we want to observe retained items.
                # But we can't easily "peek", so instead: drain *after*
                # sentinel seen. Store items on the function itself.
        # Simpler: no-op shipper that just blocks on sentinel.
        def noop_shipper(q, *a, **k):
            while q.get() is not None:
                pass
        monkeypatch.setattr(ls, "_shipper", noop_shipper)

    def test_drop_oldest_keeps_newest(self, monkeypatch, diag_caplog):
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)
        monkeypatch.setattr(ls, "_QUEUE_MAXSIZE", 4)
        monkeypatch.setattr(ls, "_DROP_REPORT_INTERVAL", 2)
        # Disable recovery entirely for this test (threshold=0 means qsize
        # can never go below it, so queue_recovered never fires).
        monkeypatch.setattr(ls, "_QUEUE_RECOVERY_THRESHOLD", 0)

        observed = {}

        # Queue subclass that:
        #  - still honors maxsize (so drop-oldest fires)
        #  - lets the shutdown sentinel (None) bypass the bound so the
        #    main thread's `queue.put(None)` never blocks
        #  - captures a snapshot of retained data items when the sentinel
        #    is observed, so we can verify newest-retained semantics
        class SnapshotQueue(queue_mod.Queue):
            def put(self, item, block=True, timeout=None):
                if item is None:
                    with self.mutex:
                        observed["snapshot"] = [
                            x for x in list(self.queue) if x is not None
                        ]
                    return  # swallow sentinel — shipper stub will just exit
                return super().put(item, block=block, timeout=timeout)

        monkeypatch.setattr(ls, "Queue", SnapshotQueue)

        # Non-draining shipper: exits immediately. The queue will be
        # abandoned (daemon thread dies with test), but the snapshot
        # captured in SnapshotQueue.put is what we assert against.
        def nondraining_shipper(q, *a, **k):
            return

        monkeypatch.setattr(ls, "_shipper", nondraining_shipper)

        # Feed 4 (maxsize) + 3 (overflow).
        n_max, overflow = 4, 3
        lines = [f"line{i}" for i in range(n_max + overflow)]
        stdin = io.StringIO("\n".join(lines) + "\n")
        monkeypatch.setattr(sys, "stdin", stdin)

        ls.follow("svc", opts=ls.Global(mode="plain"))

        snapshot = observed.get("snapshot", [])
        # Queue held maxsize data items; the oldest `overflow` were evicted.
        assert len(snapshot) == n_max
        assert snapshot == lines[overflow:], (
            f"expected newest items retained, got {snapshot}"
        )

        msgs = [r.getMessage() for r in diag_caplog.records]
        full = [m for m in msgs if "event=queue_full" in m]
        dropped_events = [m for m in msgs if "event=queue_dropped" in m]

        # queue_full fires exactly once per saturation episode.
        assert len(full) == 1, full
        assert "action=drop_oldest" in full[0]
        # With _DROP_REPORT_INTERVAL=2 and 3 drops, queue_dropped fires
        # at count=2 (count=3 is below the next threshold).
        assert len(dropped_events) == 1
        assert "count=2" in dropped_events[0]

    def test_queue_recovered_resets_counters(self, monkeypatch, diag_caplog):
        """After saturation, once qsize drops below the recovery threshold
        and a new line is enqueued, queue_recovered reports dropped_total
        and the warn-once flag resets."""
        monkeypatch.setattr(ls, "_preflight", lambda *a, **k: None)
        monkeypatch.setattr(ls, "_QUEUE_MAXSIZE", 3)
        monkeypatch.setattr(ls, "_DROP_REPORT_INTERVAL", 1000)
        monkeypatch.setattr(ls, "_QUEUE_RECOVERY_THRESHOLD", 2)

        drain_event = threading.Event()

        class RecoveryQueue(queue_mod.Queue):
            """Queue that lets the shutdown sentinel bypass maxsize and
            drains all data items when the test signals it's time."""

            def put(self, item, block=True, timeout=None):
                if item is None:
                    return  # swallow sentinel; shipper stub exits on its own
                return super().put(item, block=block, timeout=timeout)

        monkeypatch.setattr(ls, "Queue", RecoveryQueue)

        def draining_shipper(q, *a, **k):
            drain_event.wait(timeout=5)
            # Drain everything so qsize drops to 0 (below threshold=2).
            while True:
                try:
                    q.get_nowait()
                except queue_mod.Empty:
                    return

        monkeypatch.setattr(ls, "_shipper", draining_shipper)

        # Stdin: yield 5 lines (3 fit, 2 dropped), then signal drain,
        # then yield one more line that should trigger recovery.
        class StagedStdin:
            def __init__(self):
                self.phase = 0

            def __iter__(self):
                return self

            def __next__(self):
                if self.phase < 5:
                    self.phase += 1
                    return f"burst{self.phase}\n"
                if self.phase == 5:
                    drain_event.set()
                    # Give shipper a beat to drain before the next put.
                    time.sleep(0.1)
                    self.phase = 6
                    return "post_recovery\n"
                raise StopIteration

        monkeypatch.setattr(sys, "stdin", StagedStdin())

        ls.follow("svc", opts=ls.Global(mode="plain"))

        msgs = [r.getMessage() for r in diag_caplog.records]
        full = [m for m in msgs if "event=queue_full" in m]
        recovered = [m for m in msgs if "event=queue_recovered" in m]
        assert len(full) == 1, full
        assert len(recovered) == 1, recovered
        # 5 lines, maxsize 3 → 2 drops before recovery.
        assert "dropped_total=2" in recovered[0]


# -- send_retry structured event ---------------------------------------


class TestSendRetryEvent:
    def test_retry_event_logged(self, monkeypatch, diag_caplog):
        monkeypatch.setattr(ls.time, "sleep", lambda _s: None)
        t = FakeTransport([(500, {"err": "x"}), (200, {"ok": True})])
        _patched_client(monkeypatch, t)
        with httpx.Client() as c:
            ls._send_batch(c, [{"message": "hi"}])
        msgs = " ".join(r.getMessage() for r in diag_caplog.records)
        assert "event=send_retry" in msgs
        assert "status=500" in msgs
