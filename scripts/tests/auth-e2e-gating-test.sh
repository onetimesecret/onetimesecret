#!/usr/bin/env bash
# Pin auth E2E workflow wiring and execute the actual inline verdict scripts.
# This uses Python's standard library only; actionlint validates YAML syntax.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

python3 -I - "$REPO_ROOT" <<'PY'
import itertools
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
bash = shutil.which("bash")
if bash is None:
    raise RuntimeError("bash is required to exercise workflow verdicts")


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def block(text, key, indent):
    """Read one indentation-delimited block, not a general YAML parser."""
    lines = text.splitlines()
    prefix = " " * indent + key + ":"
    indexes = [i for i, line in enumerate(lines) if line.startswith(prefix)]
    check(len(indexes) == 1, f"expected exactly one {key} block at indent {indent}")
    start = indexes[0] + 1
    end = start
    while end < len(lines):
        line = lines[end]
        if line.strip() and not line.lstrip().startswith("#"):
            if len(line) - len(line.lstrip()) <= indent:
                break
        end += 1
    return "\n".join(lines[start:end]) + "\n"


def scalar(text, key, indent):
    matches = re.findall(r"^" + " " * indent + re.escape(key) + r": (.+)$", text, re.M)
    check(len(matches) == 1, f"expected exactly one {key} scalar at indent {indent}")
    return matches[0]


checkout = "actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803"
concurrency_group = "${{ github.workflow }}-${{ github.ref }}"
workflows = [
    ("e2e-full-auth.yml", "e2e-full-auth", "auth-e2e-verdict", "23 4 * * *",
     "signup → verify email → signin (real SMTP)"),
    ("e2e-tenant-connect.yml", "e2e-tenant-connect", "tenant-connect-verdict", "43 4 * * *",
     "custom host → /reauth → Connect callback (armed test process)"),
]

for filename, test_id, verdict_id, cron, test_name in workflows:
    text = (root / ".github/workflows" / filename).read_text()
    events = block(text, "on", 0)
    check(set(re.findall(r"^  ([a-z_]+):", events, re.M)) == {
        "workflow_dispatch", "pull_request", "schedule", "push", "merge_group"
    }, f"{filename}: required event coverage")
    check(not re.search(r"^ +(?:paths|paths-ignore|branches|branches-ignore):", events, re.M),
          f"{filename}: PR verdict must not be workflow-filtered")
    check(not block(events, "workflow_dispatch", 2).strip(),
          f"{filename}: manual dispatch remains unchanged")
    check(scalar(block(events, "pull_request", 2), "types", 4)
          == "[opened, synchronize, reopened]",
          f"{filename}: PR updates trigger detection; a label event must not start a run")
    check(not re.search(r"\b(?:un)?labeled\b",
                        "\n".join(line for line in events.splitlines()
                                  if not line.lstrip().startswith("#"))),
          f"{filename}: no label events: the detector reads the PR's labels live")
    check(block(events, "schedule", 2).strip() == f"- cron: '{cron}'",
          f"{filename}: staggered daily full coverage")
    check(scalar(block(events, "push", 2), "tags", 4) == "['v*']",
          f"{filename}: release tags get full coverage")
    check(scalar(block(events, "merge_group", 2), "types", 4) == "[checks_requested]",
          f"{filename}: merge queue gets a verdict")
    concurrency = block(text, "concurrency", 0)
    check(scalar(concurrency, "group", 2) == concurrency_group,
          f"{filename}: one concurrency group per ref")
    check(scalar(concurrency, "cancel-in-progress", 2) == "true",
          f"{filename}: a new push supersedes the run before it")

    jobs = block(text, "jobs", 0)
    check(set(re.findall(r"^  ([a-z0-9-]+):", jobs, re.M))
          == {"changes", test_id, verdict_id}, f"{filename}: stable job IDs")
    detection = block(jobs, "changes", 2)
    check(not re.search(r"^    if:", detection, re.M),
          f"{filename}: detection runs for every event")
    permissions = block(detection, "permissions", 4)
    for permission in ("contents", "pull-requests"):
        check(scalar(permissions, permission, 6) == "read",
              f"{filename}: detector has {permission}:read")
    outputs = block(detection, "outputs", 4)
    for output in ("auth", "reason"):
        check(scalar(outputs, output, 6) == "${{ steps.detect.outputs." + output + " }}",
              f"{filename}: detector publishes {output}")
    steps = block(detection, "steps", 4)
    check(checkout in steps and steps.index(checkout) < steps.index("./.github/actions/detect-auth-changes"),
          f"{filename}: pinned checkout precedes local action")
    check(scalar(steps, "id", 8) == "detect"
          and re.search(r"^        id: detect\n        uses: \./\.github/actions/detect-auth-changes$",
                        steps, re.M),
          f"{filename}: shared selector owns auth selection")

    tests = block(jobs, test_id, 2)
    check(scalar(tests, "name", 4) == test_name, f"{filename}: test check name retained")
    check(scalar(tests, "needs", 4) == "changes", f"{filename}: tests need detection")
    check(scalar(tests, "if", 4) == "needs.changes.outputs.auth == 'true'",
          f"{filename}: only selected tests run")
    verdict = block(jobs, verdict_id, 2)
    check(not re.search(r"^    name:", verdict, re.M),
          f"{filename}: verdict check name stays equal to its stable ID")
    check(scalar(verdict, "needs", 4) == f"[changes, {test_id}]",
          f"{filename}: verdict waits for detection and tests")
    check(scalar(verdict, "if", 4) == "always()", f"{filename}: verdict is never conditionally skipped")
    env = block(verdict, "env", 8)
    for key, expression in {
        "CHANGES_RESULT": "needs.changes.result",
        "AUTH_CHANGED": "needs.changes.outputs.auth",
        "TEST_RESULT": f"needs.{test_id}.result",
    }.items():
        check(scalar(env, key, 10) == "${{ " + expression + " }}",
              f"{filename}: {key} reaches verdict safely via env")
    check(scalar(verdict, "run", 8) == "|", f"{filename}: inline shell verdict")
    script = "\n".join(line[10:] if line.strip() else ""
                       for line in block(verdict, "run", 8).splitlines())
    check(bool(script.strip()) and "${{" not in script,
          f"{filename}: executable verdict has no expression interpolation")
    print(f"PASS {filename}: workflow wiring", flush=True)

    results = ("success", "failure", "cancelled", "skipped", "", "unknown")
    flags = ("true", "false", "", "TRUE", "false ", "$(exit 0)")
    cases = 0
    for detection_result, auth, test_result in itertools.product(results, flags, results):
        expected = 0 if detection_result == "success" and (
            (auth == "true" and test_result == "success")
            or (auth == "false" and test_result == "skipped")
        ) else 1
        outcome = subprocess.run(
            [bash, "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", script],
            env={"PATH": os.environ.get("PATH", os.defpath),
                 "CHANGES_RESULT": detection_result, "AUTH_CHANGED": auth,
                 "TEST_RESULT": test_result},
            capture_output=True, text=True, timeout=5,
        )
        check(outcome.returncode == expected,
              f"{filename}: detection={detection_result!r}, auth={auth!r}, "
              f"tests={test_result!r}: expected {expected}, got {outcome.returncode}\n"
              + outcome.stdout + outcome.stderr)
        cases += 1
    print(f"PASS {verdict_id}: {cases} verdict cases", flush=True)
PY
