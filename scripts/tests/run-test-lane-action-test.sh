#!/usr/bin/env bash
# Tests for .github/actions/run-test-lane/action.yml: its shell, and the
# artifact names it gives every workflow row that calls it.
#
# actionlint checks workflow files, not the `run:` blocks of a composite
# action, so nothing else executes this shell before CI does. Each block is
# read out of the YAML and run the way Actions runs `shell: bash`
# (bash --noprofile --norc -eo pipefail).
#
# No Ruby, datastore, container or network. The lane runner is started only
# with --print-key, which derives a lane's addressing and exits; every other
# call goes to a stub. The step reader handles this action's indentation
# only; YAML syntax is not validated here.
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

python3 -I - "$REPO_ROOT" <<'PY'
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
bash = shutil.which("bash")
if bash is None:
    raise RuntimeError("LANE-ACTION-00: bash is required")
if shutil.which("jq") is None:
    raise RuntimeError("LANE-ACTION-00: jq is required (the job summary step uses it)")

ACTION_USE = "uses: ./.github/actions/run-test-lane"
action = (root / ".github/actions/run-test-lane/action.yml").read_text()
workflows = {path.name: path.read_text() for path in sorted((root / ".github/workflows").glob("*.yml"))}
failures = []


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def read_steps(text):
    """The composite's steps by name, in order, with the comments above each."""
    lines = text.splitlines()
    start = lines.index("  steps:") + 1
    found, name = {}, None
    for line in lines[start:]:
        match = re.match(r"^    - name: (.+)$", line)
        if match:
            name = match.group(1)
            check(name not in found, f"two steps are named {name}")
            found[name] = []
        elif name is not None:
            found[name].append(line)
    return {key: "\n".join(value) + "\n" for key, value in found.items()}


def run_block(step_text):
    lines = step_text.splitlines()
    check(lines.count("      run: |") == 1, "expected one run block in the step")
    body = []
    for line in lines[lines.index("      run: |") + 1:]:
        if line.strip() and not line.startswith("        "):
            break
        body.append(line[8:])
    return "\n".join(body).rstrip() + "\n"


steps = read_steps(action)
BASE_ENV = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/")}


def execute(step_name, cwd, env):
    """Run a step's shell as Actions does; return (status, stdout, stderr)."""
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as script:
        script.write(run_block(steps[step_name]))
    try:
        done = subprocess.run(
            [bash, "--noprofile", "--norc", "-e", "-o", "pipefail", script.name],
            cwd=cwd, env={**BASE_ENV, **env}, capture_output=True, text=True, timeout=60,
        )
    finally:
        os.unlink(script.name)
    return done.returncode, done.stdout, done.stderr


def outputs(path):
    return dict(line.split("=", 1) for line in Path(path).read_text().splitlines() if line)


def stub_runner(directory, body):
    """A tests/lanes/run that is not the lane runner."""
    runner = Path(directory) / "tests/lanes/run"
    runner.parent.mkdir(parents=True)
    runner.write_text("#!/usr/bin/env bash\n" + body)
    runner.chmod(0o755)


def unquote(value):
    return value.strip().strip("'\"")


def callers(text):
    """(lane, overlay) for every call of the action in one workflow file.

    A call whose inputs come from the matrix stands for every matrix row in
    the file that names a lane; anchors share one step list between jobs.
    """
    lines = text.splitlines()
    rows, uses_matrix = [], False
    for index, line in enumerate(lines):
        if line.strip() != ACTION_USE:
            continue
        indent = len(line) - len(line.lstrip())
        inputs, in_with = {}, False
        for following in lines[index + 1:]:
            if not following.strip():
                continue
            depth = len(following) - len(following.lstrip())
            if depth < indent:
                break
            if depth == indent:
                in_with = following.strip() == "with:"
            elif in_with and depth == indent + 2:
                key, _, value = following.strip().partition(":")
                inputs[key] = unquote(value)
        check("lane" in inputs, f"a call of the action passes no lane (line {index + 1})")
        if inputs["lane"] == "${{ matrix.lane }}":
            check(inputs.get("overlay") == "${{ matrix.overlay }}", "a matrix lane takes its overlay from the matrix")
            uses_matrix = True
        else:
            check("${{" not in inputs["lane"], f"unreadable lane input: {inputs['lane']}")
            rows.append((inputs["lane"], inputs.get("overlay", "")))
    if uses_matrix:
        matrix = re.findall(r"^ +- name: .+\n +lane: (\S+)\n +overlay: (\S+)$", text, re.M)
        check(matrix, "a matrix call of the action has no matrix rows naming a lane")
        rows.extend((unquote(lane), unquote(overlay)) for lane, overlay in matrix)
    return rows


def locate(lane, overlay, cwd=root):
    with tempfile.TemporaryDirectory() as scratch:
        output = Path(scratch) / "output"
        output.touch()
        status, stdout, stderr = execute(
            "Locate lane logs", cwd, {"LANE": lane, "OVERLAY": overlay, "GITHUB_OUTPUT": str(output)})
        return status, outputs(output), stdout + stderr


def case(name):
    def register(function):
        try:
            function()
            print(f"  ok    {name}")
        except Exception as error:  # noqa: BLE001 - report every case
            failures.append(name)
            print(f"  FAIL  {name}\n        {error}")
    return register


@case("every caller gets a unique log artifact that no download pattern matches")
def artifact_names():
    patterns = set()
    for text in workflows.values():
        patterns.update(unquote(value) for value in re.findall(r"^ +pattern: (.+)$", text, re.M))
    check("rspec-*-results" in patterns, f"the aggregate job's download pattern was not found in {sorted(patterns)}")
    calling = {name: callers(text) for name, text in workflows.items() if ACTION_USE in text}
    check("ci.yml" in calling and len(calling["ci.yml"]) >= 13, f"ci.yml callers not read: {calling.get('ci.yml')}")
    for workflow, rows in calling.items():
        check(len(set(rows)) == len(rows), f"{workflow}: a lane and overlay pair is run twice: {rows}")
        names = []
        for lane, overlay in rows:
            status, out, log = locate(lane, overlay)
            check(status == 0, f"{workflow}: locate failed for {lane}/{overlay or 'base'}: {log}")
            expected_dir = str(root / "tmp/lanes" / lane / (overlay or "base"))
            check(out.get("dir") == expected_dir, f"{workflow}: {lane}/{overlay}: dir {out.get('dir')} != {expected_dir}")
            name = out.get("name", "")
            check(name == f"lane-logs-{lane}-{overlay or 'base'}", f"{workflow}: unexpected artifact name {name}")
            check(re.fullmatch(r"[A-Za-z0-9._-]+", name), f"{workflow}: {name} has a character artifacts refuse")
            for pattern in patterns:
                check(not fnmatch.fnmatchcase(name, pattern), f"{workflow}: {name} matches download pattern {pattern}")
            check(expected_dir in log and name in log, f"{workflow}: the step does not print the path and artifact name")
            names.append(name)
        check(len(set(names)) == len(names), f"{workflow}: two rows share a log artifact name: {names}")


@case("locate fails when the runner fails or reports no path")
def locate_failures():
    for body, reason in (("echo 'error: no such lane' >&2\nexit 64\n", "runner exit"),
                         ("echo app_log=none\n", "no capture path"),
                         ("echo run_dir=tmp/lanes/x/base\n", "no app_log line")):
        with tempfile.TemporaryDirectory() as scratch:
            stub_runner(scratch, body)
            status, out, log = locate("unit", "", cwd=scratch)
            check(status != 0, f"{reason}: the step passed")
            check(out == {}, f"{reason}: outputs were written: {out}")


@case("the lane runs with the capture profile and its exit status is the step's")
def run_lane():
    record = 'printf "%s\\n" "$@" > args\nprintf "%s" "${RSPEC_OUTPUT_FILE-unset}" > results\nexit "${STUB_RC:-0}"\n'
    profile = ["--capture-logs", "--log-console", "off", "--quiet"]
    for lane, overlay, results, expected_args, expected_results, rc in (
        ("unit", "", "rspec_unit_results.json", ["unit", *profile], "tmp/rspec_unit_results.json", 0),
        ("full-pg", "billing", "", ["full-pg", *profile, "--overlay", "billing"], "unset", 0),
        ("simple", "", "rspec_simple_results.json", ["simple", *profile], "tmp/rspec_simple_results.json", 7),
    ):
        with tempfile.TemporaryDirectory() as scratch:
            stub_runner(scratch, record)
            output = Path(scratch) / "output"
            output.touch()
            status, _, log = execute("Run lane", scratch, {
                "LANE": lane, "OVERLAY": overlay, "RESULTS_FILE": results, "STUB_RC": str(rc),
                "GITHUB_OUTPUT": str(output)})
            check(status == rc, f"{lane}: exit {status}, expected {rc}: {log}")
            # The elapsed time is for the summary, on a red lane as on a green one.
            check(re.fullmatch(r"\d+", outputs(output).get("seconds", "")),
                  f"{lane}: no elapsed seconds in the step outputs (exit {rc}): {outputs(output)}")
            check((Path(scratch) / "args").read_text().split("\n")[:-1] == expected_args, f"{lane}: runner arguments changed")
            check((Path(scratch) / "results").read_text() == expected_results, f"{lane}: RSPEC_OUTPUT_FILE changed")
            check((Path(scratch) / "tmp").is_dir(), f"{lane}: tmp/ was not created for the results file")
    check("LANES_NO_AUTOSTART: '1'" in steps["Run lane"], "CI owns the service lifecycle")
    check("      id: run-lane" in steps["Run lane"]
          and "LANE_SECONDS: ${{ steps.run-lane.outputs.seconds }}" in steps["Generate job summary"],
          "the summary no longer receives the lane's elapsed seconds")


@case("logs upload on every outcome, apart from the results, without mail.log")
def upload_step():
    order = list(steps)
    check(order.index("Locate lane logs") < order.index("Run lane") < order.index("Upload lane logs")
          < order.index("Generate job summary"), f"step order changed: {order}")
    check("if:" not in steps["Locate lane logs"], "the path is located before the lane, unconditionally")
    upload = "\n".join(line for line in steps["Upload lane logs"].splitlines() if not line.lstrip().startswith("#"))
    for expected in ("      id: lane-logs-upload",
                     "      if: always() && steps.lane-logs.outputs.name != ''",
                     "      uses: actions/upload-artifact@",
                     "        name: ${{ steps.lane-logs.outputs.name }}",
                     "          ${{ steps.lane-logs.outputs.dir }}/app.log",
                     "          ${{ steps.lane-logs.outputs.dir }}/last.log",
                     "        retention-days: 3",
                     "        if-no-files-found: ignore"):
        check(expected in upload, f"log upload lost: {expected.strip()}")
    check("mail.log" not in upload, "mail.log is raw email content and is not uploaded")
    check(len(re.findall(r"^          \S", upload, re.M)) == 2, "the log upload names exactly two files")
    results = steps["Upload RSpec results"]
    check("      if: always() && steps.results-artifact.outputs.name != ''" in results
          and "        path: ${{ steps.results-artifact.outputs.glob }}" in results,
          "the RSpec results upload changed")
    # The aggregation script takes these names from a merged download.
    for name in ("app.log", "last.log"):
        check(not fnmatch.fnmatchcase(name, "rspec_*.json") and not fnmatch.fnmatchcase(name, "*_results.json"),
              f"{name} would be aggregated as RSpec results")


@case("the summary totals every results file and says where the logs are")
def summary():
    with tempfile.TemporaryDirectory() as scratch:
        tmp = Path(scratch) / "tmp"
        tmp.mkdir()
        for suffix, examples, failed in (("_root_fast", 3, 1), ("_apps_fast", 2, 0)):
            (tmp / f"rspec_x_results{suffix}.json").write_text(
                json.dumps({"summary": {"example_count": examples, "failure_count": failed}}))
        (tmp / "rspec_x_results_apps_config_ru.json").touch()
        (tmp / "rspec_other_results.json").write_text(json.dumps({"summary": {"example_count": 100, "failure_count": 9}}))
        page = Path(scratch) / "summary"
        logs = Path(scratch) / "lanes/full-pg/billing"
        logs.mkdir(parents=True)
        (logs / "last.log").write_text("x" * 120)
        (logs / "app.log").write_text("y" * 4567)
        (logs / "mail.log").write_text("")
        env = {"LANE": "full-pg", "OVERLAY": "billing", "RESULTS_FILE": "rspec_x_results.json",
               "LOG_ARTIFACT": "lane-logs-full-pg-billing", "LOG_ARTIFACT_URL": "https://example.test/artifacts/1",
               "LOG_DIR": str(logs), "LANE_SECONDS": "83", "GITHUB_STEP_SUMMARY": str(page)}
        status, _, log = execute("Generate job summary", scratch, env)
        check(status == 0, f"summary step failed: {log}")
        text = page.read_text()
        for expected in ("| lane | `full-pg` |", "| overlay | `billing` |", "- Total: 5", "- Failures: 1",
                         "- No results in `tmp/rspec_x_results_apps_config_ru.json`",
                         "[`lane-logs-full-pg-billing`](https://example.test/artifacts/1)",
                         f"- On the runner: `{logs}`",
                         # The measured size of the console output and of each
                         # captured file, and the lane's elapsed time.
                         "- `last.log` (console output): 120 bytes",
                         "- `app.log` (application log): 4567 bytes",
                         "- `mail.log` (delivered emails, not uploaded): 0 bytes",
                         "- Lane run: 83s"):
            check(expected in text, f"summary lost: {expected}\n{text}")

        # A lane that died before any results or logs, with no results file asked for.
        page.write_text("")
        status, _, log = execute("Generate job summary", scratch, {
            **env, "OVERLAY": "", "RESULTS_FILE": "", "LOG_ARTIFACT_URL": "",
            "LOG_DIR": str(Path(scratch) / "no-such-directory"), "LANE_SECONDS": ""})
        check(status == 0, f"summary step failed without results: {log}")
        text = page.read_text()
        check("bytes" not in text and "Lane run" not in text, f"sizes or a time were reported for a run that left none:\n{text}")
        check("### RSpec" not in text and "overlay" not in text, f"empty inputs were reported:\n{text}")
        check("`lane-logs-full-pg-billing` was not uploaded" in text, f"a missing artifact is not reported:\n{text}")

        # Every results file empty: no total, each file named.
        page.write_text("")
        for path in tmp.glob("rspec_x_results_*.json"):
            path.write_text("")
        status, _, log = execute("Generate job summary", scratch, env)
        check(status == 0, f"summary step failed with empty results: {log}")
        text = page.read_text()
        check("- Total:" not in text and text.count("- No results in") == 3, f"empty results misreported:\n{text}")

        # A results file cut off mid-write is not empty and is not JSON: the
        # files that can be read are still totalled, and it is named.
        page.write_text("")
        (tmp / "rspec_x_results_root_fast.json").write_text(
            json.dumps({"summary": {"example_count": 3, "failure_count": 1}}))
        (tmp / "rspec_x_results_apps_fast.json").write_text('{"summary": {"example_count": 2, "failu')
        status, _, log = execute("Generate job summary", scratch, env)
        check(status == 0, f"summary step failed with a cut-off results file: {log}")
        text = page.read_text()
        check("- Total: 3\n" in text and "- Failures: 1\n" in text, f"readable results lost beside a cut-off file:\n{text}")
        check("- No results in `tmp/rspec_x_results_apps_fast.json`" in text and text.count("- No results in") == 2,
              f"a cut-off results file is not named:\n{text}")


@case("only the fresh-clone job calls the runner without the action")
def direct_callers():
    # fresh-clone.yml runs the documented contributor commands as written
    # (CONTRIBUTING.md, "Run what CI runs"). Any other workflow that runs a
    # lane goes through the action, which is where the log profile and the
    # log artifact are.
    for name, text in workflows.items():
        direct = [line.strip() for line in text.splitlines()
                  if "tests/lanes/run " in line and not line.lstrip().startswith("#")]
        if name == "fresh-clone.yml":
            check(direct == ["run: tests/lanes/run unit", "run: tests/lanes/run billing", "run: tests/lanes/run browser"],
                  f"fresh-clone.yml no longer runs the documented commands: {direct}")
        else:
            check(direct == [], f"{name} calls tests/lanes/run directly: {direct}")


if failures:
    print(f"FAIL: {len(failures)} case(s)")
    sys.exit(1)
print("PASS: run-test-lane action")
PY
