#!/usr/bin/env python3
"""Run the same cold-cache TypeScript workload across hosted CI providers."""

import argparse
import hashlib
import json
import os
import platform
import re
import signal
import subprocess
import sys
import tarfile
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PINS = json.loads(Path(__file__).with_name("toolchain.json").read_text())
RESULTS = ROOT / "tmp/typescript-pilot/results"
TOOLS = ROOT / "tmp/typescript-pilot/tools"


def now():
    return datetime.now(timezone.utc).isoformat()


def capture(command, env):
    return subprocess.check_output(
        command, cwd=ROOT, env=env, text=True, timeout=30
    ).strip()


def identity(env, local):
    if local:
        provider = "local"
    elif env.get("GITLAB_CI") == "true":
        provider = "gitlab"
    elif env.get("GITHUB_ACTIONS") == "true":
        provider = "github"
    else:
        provider = "circleci"
    sha = capture(["git", "rev-parse", "HEAD"], env)
    expected = env.get(
        {"gitlab": "CI_COMMIT_SHA", "github": "GITHUB_SHA"}.get(provider, "CIRCLE_SHA1")
    )
    if not local and (not expected or sha != expected):
        raise ValueError("Checkout SHA must match the provider's source commit SHA")
    github_url = (
        f"{env.get('GITHUB_SERVER_URL', 'https://github.com')}/"
        f"{env.get('GITHUB_REPOSITORY')}/actions/runs/{env.get('GITHUB_RUN_ID')}"
    )
    dirty = bool(capture(["git", "status", "--porcelain", "--untracked-files=no"], env))
    if not local and dirty:
        raise ValueError("Hosted benchmark requires an unmodified source checkout")
    return {
        "provider": provider,
        "commit_sha": sha,
        "working_tree_dirty": dirty,
        "job_id": env.get(
            {"gitlab": "CI_JOB_ID", "github": "GITHUB_JOB"}.get(
                provider, "CIRCLE_WORKFLOW_JOB_ID"
            )
        ),
        "job_url": github_url
        if provider == "github"
        else env.get("CI_JOB_URL" if provider == "gitlab" else "CIRCLE_BUILD_URL"),
        "pipeline_id": env.get("CI_PIPELINE_ID")
        if provider == "gitlab"
        else env.get("GITHUB_RUN_ID")
        if provider == "github"
        else None,
        "workflow_id": env.get("CIRCLE_WORKFLOW_ID")
        if provider == "circleci"
        else None,
        "run_attempt": env.get("GITHUB_RUN_ATTEMPT") if provider == "github" else None,
        "executor": env.get("PILOT_EXECUTOR", "local" if local else "docker"),
        "platform": platform.platform(),
        "architecture": platform.machine(),
        "visible_cpus": os.cpu_count(),
        "resource_class": env.get("PILOT_RESOURCE_CLASS", "local"),
        "cache_mode": "local-existing" if local else "cold",
        "workers": PINS["workers"],
        "image": PINS["image"],
        "python": platform.python_version(),
    }


def inventory_sha256(payload, root):
    """Hash test identities independently of the provider's checkout directory."""
    prefix = str(root) + "/"
    inventory = []
    for suite in payload.get("testResults", []):
        file = str(Path(suite["name"]).relative_to(root))
        for test in suite.get("assertionResults", []):
            title = test["fullName"].replace(prefix, "<checkout>/")
            inventory.append([file, title])
    return hashlib.sha256(json.dumps(sorted(inventory)).encode()).hexdigest()


class Run:
    def __init__(self, env):
        self.env = env
        self.started = time.monotonic()
        self.metrics = {
            "schema_version": 1,
            "started_at": now(),
            "phases": [],
            "typecheck_heap_mib": PINS["typecheck_heap_mib"],
        }

    def phase(self, name, command, *, env=None):
        start = time.monotonic()
        print(f"\n--- {name} ---", flush=True)
        code = 1
        try:
            remaining = PINS["deadline_seconds"] - (start - self.started)
            if remaining <= 0:
                code = 124
                return code
            with subprocess.Popen(
                command,
                cwd=ROOT,
                env=self.env if env is None else env,
                start_new_session=True,
            ) as process:
                try:
                    code = process.wait(timeout=remaining)
                except subprocess.TimeoutExpired:
                    print("Pilot's shared 15 minute deadline exceeded", file=sys.stderr)
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    code = 124
        finally:
            self.metrics["phases"].append(
                {
                    "name": name,
                    "seconds": round(time.monotonic() - start, 6),
                    "exit_code": code,
                }
            )
        return code

    def workload(self):
        if self.phase("locales", ["pnpm", "run", "locales:sync"]):
            return 1
        tests = self.phase(
            "tests",
            [
                "pnpm",
                "test:base",
                "run",
                "--printConsoleTrace",
                f"--maxWorkers={PINS['workers']}",
                "--retry=0",
                "--reporter=default",
                "--reporter=junit",
                "--reporter=json",
                f"--outputFile.junit={RESULTS / 'unit.xml'}",
                f"--outputFile.json={RESULTS / 'unit.json'}",
            ],
        )
        # Match Actions: failed tests must not suppress test type checking.
        typecheck_env = dict(
            self.env,
            NODE_OPTIONS=f"--max-old-space-size={PINS['typecheck_heap_mib']}",
        )
        types = self.phase("typecheck", ["pnpm", "type-check:tests"], env=typecheck_env)
        return int(bool(tests or types))

    def finish(self, code):
        report = RESULTS / "unit.json"
        try:
            if any(
                p["name"] == "tests" and p["exit_code"] == 0
                for p in self.metrics["phases"]
            ):
                if not report.exists() or not (RESULTS / "unit.xml").exists():
                    raise ValueError(
                        "Successful tests must produce JSON and JUnit reports"
                    )
            if report.exists():
                payload = json.loads(report.read_text())
                self.metrics["tests"] = {
                    key: payload.get(key)
                    for key in (
                        "numTotalTests",
                        "numPassedTests",
                        "numFailedTests",
                        "numPendingTests",
                        "numTodoTests",
                    )
                }
                self.metrics["test_inventory_sha256"] = inventory_sha256(payload, ROOT)
        except (OSError, ValueError, KeyError, TypeError) as error:
            self.metrics["report_error"] = str(error)
            code = 1
        self.metrics.update(
            finished_at=now(),
            seconds=round(time.monotonic() - self.started, 6),
            exit_code=code,
            status="passed" if code == 0 else "failed",
        )
        (RESULTS / "metrics.json").write_text(json.dumps(self.metrics, indent=2) + "\n")
        return code


def bootstrap(run, package_manager):
    if platform.system() != "Linux" or platform.machine() != "x86_64":
        raise ValueError("Hosted pilot requires Linux amd64")
    if platform.python_version() != PINS["python"]:
        raise ValueError("Python version differs from the pinned pilot image")
    if (ROOT / "node_modules").exists() or TOOLS.exists():
        raise ValueError(
            "Cold pilot requires a fresh checkout without node_modules or tools"
        )
    TOOLS.mkdir(parents=True)
    filename = f"node-v{PINS['node']}-linux-x64.tar.xz"
    start = time.monotonic()
    with urllib.request.urlopen(
        f"https://nodejs.org/dist/v{PINS['node']}/{filename}", timeout=60
    ) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != PINS["node_linux_x64_sha256"]:
        raise ValueError("Node archive checksum mismatch")
    archive = TOOLS / filename
    archive.write_bytes(data)
    with tarfile.open(archive) as source:
        source.extractall(TOOLS, filter="data")
    run.metrics["phases"].append(
        {
            "name": "node_download",
            "seconds": round(time.monotonic() - start, 6),
            "exit_code": 0,
        }
    )
    node_bin = TOOLS / filename.removesuffix(".tar.xz") / "bin"
    pnpm_prefix = TOOLS / "pnpm"
    run.env["PATH"] = f"{node_bin}:{pnpm_prefix / 'bin'}:" + run.env["PATH"]
    run.env["npm_config_cache"] = str(TOOLS / "npm-cache")
    run.env["pnpm_config_store_dir"] = str(TOOLS / "pnpm-store")
    return run.phase(
        "pnpm_setup",
        [
            "npm",
            "install",
            "--global",
            "--prefix",
            str(pnpm_prefix),
            "--ignore-scripts",
            "--no-audit",
            "--no-fund",
            package_manager,
        ],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--local",
        action="store_true",
        help="Validate installed tools/dependencies; not a hosted benchmark",
    )
    args = parser.parse_args()
    env = dict(
        os.environ, CI="true", NODE_ENV="test", BILLING_ENABLED="false", TZ="UTC"
    )
    run = Run(env)
    RESULTS.mkdir(parents=True, exist_ok=True)
    # Avoid ingesting stale results after an interrupted/failed invocation.
    for name in ("metrics.json", "unit.json", "unit.xml"):
        (RESULTS / name).unlink(missing_ok=True)
    code = 1
    try:
        if args.local and not (ROOT / ".test-mode").exists():
            raise ValueError("Enable local test mode with bin/setup --test first")
        run.metrics.update(identity(env, args.local))
        package_manager = json.loads((ROOT / "package.json").read_text())[
            "packageManager"
        ]
        if not re.fullmatch(r"pnpm@\d+\.\d+\.\d+", package_manager):
            raise ValueError("packageManager must pin an exact pnpm version")
        if (ROOT / ".node-version").read_text().strip() != PINS["node"].split(".")[0]:
            raise ValueError("Pilot Node pin no longer matches .node-version")
        run.metrics.update(
            expected_node=PINS["node"],
            expected_pnpm=package_manager.removeprefix("pnpm@"),
        )
        if not args.local and bootstrap(run, package_manager):
            return 1
        node = capture(["node", "--version"], env).removeprefix("v")
        pnpm = capture(["pnpm", "--version"], env)
        run.metrics.update(node=node, pnpm=pnpm)
        if node != PINS["node"] or pnpm != package_manager.removeprefix("pnpm@"):
            raise ValueError("Installed Node/pnpm do not match the pilot pins")
        if not args.local and run.phase(
            "install",
            [
                "pnpm",
                "install",
                "--frozen-lockfile",
                "--prod=false",
                "--store-dir",
                str(TOOLS / "pnpm-store"),
            ],
        ):
            return 1
        code = run.workload()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        run.metrics["error"] = str(error)
        print(f"Pilot failed: {error}", file=sys.stderr)
    finally:
        code = run.finish(code)
    return code


if __name__ == "__main__":
    sys.exit(main())
