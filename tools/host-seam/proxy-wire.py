#!/usr/bin/env python3
"""Opt-in real HTTP/1.1 proxy checks. No Rack simulation, datastore, or IdP."""

import argparse
import errno
import http.client
import json
import os
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

PUBLIC = "tenant.host-seam.example"
EVIL = "evil.attacker.example"
CARRIERS = (
    "X-Forwarded-Host",
    "Apx-Incoming-Host",
    "X-Original-Host",
    "Forwarded",
)


def report(finding, case, verdict, detail):
    print(
        json.dumps(dict(id=finding, case=case, verdict=verdict, detail=detail)),
        flush=True,
    )


def cases(host):
    yield "control", [("Host", host)]
    for carrier in CARRIERS:
        poison = f"host={EVIL};proto=http" if carrier == "Forwarded" else EVIL
        real = f"host={host}" if carrier == "Forwarded" else host
        yield carrier + "-single", [("Host", host), (carrier, poison)]
        for values, label in (
            ((poison, real), "evil-first"),
            ((real, poison), "evil-last"),
        ):
            # Separate physical field lines; do not collapse into a mapping.
            yield (
                carrier + "-duplicate-" + label,
                [("Host", host)] + [(carrier, value) for value in values],
            )
        yield (
            carrier + "-comma",
            [("Host", host), (carrier, f"{poison}, {real}")],
        )
    yield (
        "all-carriers",
        [("Host", host)]
        + [
            (name, f"host={EVIL}" if name == "Forwarded" else EVIL)
            for name in CARRIERS
        ],
    )
    yield "Host-duplicate-evil-last", [("Host", host), ("Host", EVIL)]
    yield "Host-duplicate-evil-first", [("Host", EVIL), ("Host", host)]


def request(url, headers, timeout, connect_host=None, cafile=None):
    target = urlsplit(url)
    port = target.port or (443 if target.scheme == "https" else 80)
    path = target.path or "/"
    if target.query:
        path += "?" + target.query
    wire = "GET " + path + " HTTP/1.1\r\n"
    wire += "".join(f"{name}: {value}\r\n" for name, value in headers)
    wire += "Connection: close\r\n\r\n"
    with socket.create_connection(
        (connect_host or target.hostname, port), timeout
    ) as raw:
        conn = raw
        if target.scheme == "https":
            conn = ssl.create_default_context(cafile=cafile).wrap_socket(
                raw, server_hostname=target.hostname
            )
        try:
            conn.sendall(wire.encode("ascii"))
            response = http.client.HTTPResponse(conn)
            response.begin()
            return response.status, response.getheaders(), response.read(65536)
        finally:
            if conn is not raw:
                conn.close()


class Capture(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(list(self.headers.raw_items())).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def values(headers, name):
    return [value for key, value in headers if key.lower() == name.lower()]


def check(
    url,
    host,
    timeout,
    capture=False,
    connect_host=None,
    cafile=None,
    strategy=None,
):
    failed = False
    for name, headers in cases(host if capture else urlsplit(url).netloc):
        finding = "HS-PROXY-002" if "duplicate" in name else "HS-PROXY-001"
        try:
            status, response, body = request(
                url, headers, timeout, connect_host, cafile
            )
            if name.startswith("Host-duplicate"):
                ok = status in (400, 421)
                detail = f"ambiguous Host rejection status={status}; expected 400 or 421"
            elif capture:
                upstream = json.loads(body) if status == 200 else []
                ok = (
                    status == 200
                    and values(upstream, "Host") == ["origin-target.internal"]
                    and values(upstream, "X-Forwarded-Host") == [host]
                    and all(not values(upstream, key) for key in CARRIERS[1:])
                )
                detail = dict(status=status, upstream=upstream)
            else:
                display = values(response, "O-Display-Domain")
                actual = values(response, "O-Domain-Strategy")
                ok = status < 400 and display == [host] and actual == [strategy]
                detail = dict(status=status, display=display, strategy=actual)
            report(finding, name, "PASS" if ok else "FAIL", detail)
            failed |= not ok
            if name == "control" and not ok:
                report(
                    finding,
                    "precondition",
                    "UNTESTABLE",
                    "control failed; remaining cases skipped",
                )
                return 2
        except (OSError, ValueError, http.client.HTTPException) as error:
            report(finding, name, "UNTESTABLE", str(error))
            return 2
    return 1 if failed else 0


def fixture(args):
    capture = ThreadingHTTPServer(("127.0.0.1", 0), Capture)
    capture.daemon_threads = True
    thread = threading.Thread(target=capture.serve_forever, daemon=True)
    thread.start()
    # Caddy cannot inherit this reservation; a bind race is a setup failure.
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update(
        HOST_SEAM_PROXY_PORT=str(port),
        HOST_SEAM_CAPTURE_PORT=str(capture.server_port),
    )
    config = Path(__file__).with_name("proxy-wire.caddy")
    process = None
    try:
        with tempfile.TemporaryDirectory(prefix="host-seam-wire-") as work:
            env.update(XDG_CONFIG_HOME=work, XDG_DATA_HOME=work)
            with open(Path(work) / "caddy.log", "w+") as log:
                process = subprocess.Popen(
                    [
                        args.caddy,
                        "run",
                        "--config",
                        str(config.resolve()),
                        "--adapter",
                        "caddyfile",
                    ],
                    cwd=work,
                    env=env,
                    stdout=log,
                    stderr=log,
                )
                ready = False
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline and process.poll() is None:
                    try:
                        with socket.create_connection(("127.0.0.1", port), 0.2):
                            ready = True
                            break
                    except OSError:
                        time.sleep(0.1)
                if not ready:
                    log.seek(0)
                    report(
                        "HS-PROXY-001", "fixture-boot", "UNTESTABLE", log.read()
                    )
                    return 2
                return check(
                    f"http://127.0.0.1:{port}/",
                    PUBLIC,
                    args.timeout,
                    capture=True,
                )
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        capture.shutdown()
        capture.server_close()


def origin(args):
    try:
        with socket.create_connection((args.address, args.port), args.timeout):
            report(
                "HS-PROXY-003",
                "direct-origin",
                "FAIL",
                "TCP reachable from this vantage; no HTTP sent",
            )
            return 1
    except OSError as error:
        # DNS errors and timeouts are not proof of an enforced network boundary.
        if error.errno == errno.ECONNREFUSED:
            report(
                "HS-PROXY-003",
                "direct-origin",
                "PASS",
                "TCP refused from this vantage only",
            )
            return 0
        report("HS-PROXY-003", "direct-origin", "UNTESTABLE", str(error))
        return 2


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=5)
    modes = parser.add_subparsers(dest="mode", required=True)
    local = modes.add_parser(
        "fixture",
        help="CI only: start disposable loopback Caddy and header capture",
    )
    local.add_argument(
        "--caddy",
        required=True,
        help="path to an already-installed Caddy binary",
    )
    staging = modes.add_parser(
        "staging",
        help="GET-only raw HTTP/1.1 check against an authorized ingress",
    )
    staging.add_argument(
        "--url",
        required=True,
        help="existing dynamic URL emitting O-* domain headers",
    )
    staging.add_argument(
        "--strategy", required=True, choices=("canonical", "custom")
    )
    staging.add_argument(
        "--connect-address",
        help="optional approved ingress IP; URL retains TLS SNI and Host",
    )
    staging.add_argument(
        "--ca-file", help="CA bundle; TLS verification is never disabled"
    )
    direct = modes.add_parser(
        "origin", help="TCP-only reachability check from an untrusted vantage"
    )
    direct.add_argument("--address", required=True)
    direct.add_argument("--port", required=True, type=int)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        if args.mode == "fixture":
            return fixture(args)
        if args.mode == "origin":
            if not 1 <= args.port <= 65535:
                parser.error("--port must be between 1 and 65535")
            return origin(args)
        target = urlsplit(args.url)
        if (
            target.scheme not in ("http", "https")
            or not target.hostname
            or target.username
            or target.password
            or target.fragment
        ):
            parser.error(
                "--url must be an HTTP(S) URL without credentials or fragment"
            )
        if any(char in args.url for char in "\r\n"):
            parser.error("--url must not contain CR or LF")
        return check(
            args.url,
            target.hostname,
            args.timeout,
            connect_host=args.connect_address,
            cafile=args.ca_file,
            strategy=args.strategy,
        )
    except (OSError, ValueError) as error:
        report("HS-PROXY-001", "setup", "UNTESTABLE", str(error))
        return 2


if __name__ == "__main__":
    sys.exit(main())
