#!/usr/bin/env python3
"""Bounded real-Caddy test; no Ruby, datastore, external upstream or TLS issuance.

Run: python3 scripts/tests/test_caddy_log_redaction.py
Requires the example's Caddy build (including transform-encoder).
"""

import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "etc/examples/Caddyfile-example"


def snippet(text, name):
    match = re.search(
        r"^\(" + re.escape(name) + r"\) \{\n.*?^\}",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError(f"Missing snippet: {name}")
    return match[0]


class CaddyLogRedactionTest(unittest.TestCase):
    def test_example_and_live_logs(self):
        caddy = shutil.which("caddy")
        self.assertIsNotNone(
            caddy, "Install Caddy with the example's transform-encoder plugin"
        )
        source = EXAMPLE.read_text()
        observed = []
        marker = "private-saml-log-marker"
        location = f"/auth/sso/saml/callback?saml_handle={marker}"

        class Upstream(BaseHTTPRequestHandler):
            def do_GET(self):
                observed.append((self.path, self.headers.get("Referer"), ""))
                self.send_response(303)
                self.send_header("Location", location)
                self.end_headers()

            def do_POST(self):
                body = self.rfile.read(
                    int(self.headers.get("Content-Length", 0))
                ).decode()
                observed.append((self.path, self.headers.get("Referer"), body))
                self.send_response(303)
                self.send_header("Location", location)
                self.end_headers()

            def log_message(self, *args):
                pass

        upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        thread = threading.Thread(target=upstream.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="caddy-log-test-") as temp:
                directory = Path(temp)
                env = {
                    "PATH": os.environ.get("PATH", ""),
                    "HOME": temp,
                    "XDG_DATA_HOME": temp,
                    "XDG_CONFIG_HOME": temp,
                    "DOMAIN": "localhost",
                }
                # Validate the complete example, not merely a hand-copied filter.
                validation = subprocess.run(
                    [
                        caddy,
                        "adapt",
                        "--config",
                        str(EXAMPLE),
                        "--adapter",
                        "caddyfile",
                        "--validate",
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=20,
                )
                self.assertEqual(
                    validation.returncode,
                    0,
                    validation.stderr + validation.stdout,
                )
                print(
                    subprocess.check_output(
                        [caddy, "version"], text=True, timeout=5
                    ).strip()
                )
                runtime_log = re.search(
                    r"^\tlog \{\n.*?^\t\}", source, re.MULTILINE | re.DOTALL
                )[0]
                # Exercise the same runtime encoder with verbose proxy capture.
                runtime_log = runtime_log.replace("level INFO", "level DEBUG")
                # Ephemeral loopback listener; release just before Caddy binds it.
                with socket.socket() as reserved:
                    reserved.bind(("127.0.0.1", 0))
                    port = reserved.getsockname()[1]
                config = directory / "Caddyfile"
                config.write_text(
                    snippet(source, "onetime-log-redaction")
                    + "\n{\n admin off\n auto_https off\n"
                    + runtime_log
                    + "\n}\n"
                    + snippet(source, "onetime-logging")
                    + "\n"
                    + f"http://127.0.0.1:{port} {{\n import onetime-logging\n"
                    + f" reverse_proxy 127.0.0.1:{upstream.server_port}\n}}\n"
                )
                log_path = directory / "logs"
                with log_path.open("w") as logs:
                    process = subprocess.Popen(
                        [
                            caddy,
                            "run",
                            "--config",
                            str(config),
                            "--adapter",
                            "caddyfile",
                        ],
                        env=env,
                        stdout=logs,
                        stderr=logs,
                    )
                    try:
                        deadline = time.monotonic() + 10
                        while True:
                            self.assertIsNone(
                                process.poll(), log_path.read_text()
                            )
                            try:
                                with socket.create_connection(
                                    ("127.0.0.1", port), timeout=0.2
                                ):
                                    break
                            except OSError:
                                if time.monotonic() >= deadline:
                                    self.fail(
                                        "Caddy did not start within 10 seconds"
                                    )
                                time.sleep(0.05)

                        def request(path, method="GET", body=None):
                            connection = http.client.HTTPConnection(
                                "127.0.0.1", port, timeout=3
                            )
                            try:
                                connection.request(
                                    method,
                                    path,
                                    body=body,
                                    headers={
                                        "Referer": location,
                                        "Content-Type": "application/x-www-form-urlencoded",
                                    },
                                )
                                response = connection.getresponse()
                                response.read()
                                return response.status, response.getheader(
                                    "Location"
                                )
                            finally:
                                connection.close()

                        paths = [
                            f"/auth/sso/saml/callback?saml_handle={marker}&SAMLResponse={marker}",
                            f"/auth/sso/renamed/callback?%73aml_handle={marker}&saml_handle={marker}",
                            f"/ordinary?bad=%ZZ&unknown={marker}",
                            f"/api/v3/secret?SAMLResponse={marker}",
                        ]
                        for path in paths:
                            self.assertEqual(request(path), (303, location))
                        body = f"SAMLResponse={marker}"
                        self.assertEqual(
                            request(paths[0], "POST", body), (303, location)
                        )
                        self.assertEqual(
                            [item[0] for item in observed], paths + [paths[0]]
                        )
                        self.assertTrue(
                            all(item[1] == location for item in observed)
                        )
                        self.assertEqual(observed[-1][2], body)
                        # An unavailable upstream exercises the runtime error logger,
                        # not just successful access-log serialization.
                        upstream.shutdown()
                        upstream.server_close()
                        self.assertEqual(request(paths[0])[0], 502)
                    finally:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait(timeout=5)
                output = log_path.read_text()
                self.assertNotIn(marker, output)
                records = [
                    json.loads(line)
                    for line in output.splitlines()
                    if line.startswith("{")
                ]
                access = [
                    record
                    for record in records
                    if record.get("logger", "").startswith("http.log.access")
                ]
                errors = [
                    record
                    for record in records
                    if record.get("logger", "").startswith("http.log.error")
                ]
                self.assertGreaterEqual(len(access), 6, output)
                self.assertTrue(errors, output)
                for record in access + errors:
                    self.assertNotIn("?", record["request"]["uri"])
                    self.assertNotIn("Referer", record["request"]["headers"])
                    self.assertNotIn("Location", record.get("resp_headers", {}))
                roundtrips = [
                    record
                    for record in records
                    if record.get("msg") == "upstream roundtrip"
                ]
                self.assertTrue(roundtrips, output)
                for record in roundtrips:
                    self.assertNotIn("Location", record.get("headers", {}))
                timeline = [
                    line
                    for line in output.splitlines()
                    if not line.startswith("{")
                ]
                self.assertTrue(
                    any("GET /api/v3/secret 303" in line for line in timeline),
                    output,
                )
                self.assertTrue(
                    all("?" not in line for line in timeline), output
                )
        finally:
            upstream.shutdown()
            upstream.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
