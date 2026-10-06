#!/usr/bin/env bash
# Pure-text CI auth regression tests: no Ruby, datastore, browser, or network.
# The block reader intentionally handles only this workflow's indentation;
# YAML syntax validation remains actionlint's responsibility.
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
import tempfile

root = Path(sys.argv[1])
bash = shutil.which("bash")
if bash is None:
    raise RuntimeError("CI-AUTH-00: bash is required")
workflow = (root / ".github/workflows/ci.yml").read_text()
compute = root / ".github/scripts/compute-path-filter-outputs.sh"
selector = root / ".github/scripts/compute-auth-selection.sh"
failures = []


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def block(text, key, indent):
    """Read one indentation-delimited block, not arbitrary YAML."""
    lines = text.splitlines()
    pattern = re.compile(r"^" + " " * indent + re.escape(key) + r":(?:\s|$)")
    indexes = [i for i, line in enumerate(lines) if pattern.match(line)]
    check(len(indexes) == 1, f"expected one {key} block at indent {indent}")
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
    values = re.findall(r"^" + " " * indent + re.escape(key) + r": (.+)$", text, re.M)
    check(len(values) == 1, f"expected one {key} scalar at indent {indent}")
    return values[0]


def step(text, step_id):
    lines = text.splitlines()
    indexes = [i for i, line in enumerate(lines) if line == "        id: " + step_id]
    check(len(indexes) == 1, f"expected one step with id {step_id}")
    start = indexes[0]
    while start >= 0 and not lines[start].startswith("      - "):
        start -= 1
    check(start >= 0, f"missing step header for {step_id}")
    end = indexes[0] + 1
    while end < len(lines) and not lines[end].startswith("      - "):
        end += 1
    return "\n".join(lines[start:end]) + "\n"


def executable(text):
    return "\n".join(line.strip() for line in text.splitlines()
                     if line.strip() and not line.lstrip().startswith("#"))


def expression(value):
    return "${{ " + value + " }}"


def run(script, inputs):
    return subprocess.run(
        [bash, "--noprofile", "--norc", str(script)],
        env={"PATH": os.environ.get("PATH", os.defpath), **inputs},
        capture_output=True, text=True, timeout=5,
    )


def outputs(text):
    pairs = [line.split("=", 1) for line in text.splitlines()]
    check(all(len(pair) == 2 for pair in pairs), f"malformed outputs: {text!r}")
    check(len({pair[0] for pair in pairs}) == len(pairs), f"duplicate outputs: {text!r}")
    return dict(pairs)


def defaults():
    return {key: "false" for key in (
        "SKIP_CI", "RUN_ALL", "GA_WORKFLOWS", "FILTER_RUBY",
        "FILTER_TYPESCRIPT", "FILTER_FRONTEND", "FILTER_OCI", "FILTER_AUTH",
        "FILTER_BILLING",
    )}


def compute_cases():
    # Enumerate precedence and independent filters, in both output modes.
    keys = tuple(defaults())
    for values in itertools.product(("false", "true"), repeat=len(keys)):
        inputs = dict(zip(keys, values))
        if inputs["SKIP_CI"] == "true":
            expected = dict.fromkeys(("ruby", "typescript", "frontend", "oci", "auth",
                                      "billing", "ga_workflow_files"), "false")
        elif inputs["RUN_ALL"] == "true" or inputs["GA_WORKFLOWS"] == "true":
            expected = dict.fromkeys(("ruby", "typescript", "frontend", "oci", "auth",
                                      "billing", "ga_workflow_files"), "true")
        else:
            expected = {key: inputs["FILTER_" + key.upper()]
                        for key in ("ruby", "typescript", "frontend", "oci", "auth", "billing")}
            expected["ga_workflow_files"] = "false"
        for file_mode in (False, True):
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "output"
                if file_mode:
                    output.write_text("existing=kept\n")
                outcome = run(compute, {**inputs, "GITHUB_OUTPUT": str(output) if file_mode else ""})
                check(outcome.returncode == 0,
                      f"compute {inputs}, file={file_mode}: {outcome.stdout}{outcome.stderr}")
                actual = outputs(output.read_text() if file_mode else outcome.stdout)
                if file_mode:
                    check(outcome.stdout == "", "file mode must not duplicate outputs to stdout")
                    expected = {**expected, "existing": "kept"}
                check(actual == expected,
                      f"compute {inputs}, file={file_mode}: expected {expected}, got {actual}")
    print("  1024 compute/output-mode cases", flush=True)


def invalid_auth():
    for override in ({}, {"SKIP_CI": "true"}, {"RUN_ALL": "true"}, {"GA_WORKFLOWS": "true"}):
        for bad in (None, "", "TRUE", "False", "1", "null", " true", "false ", "false\n", "$(exit 0)"):
            inputs = {**defaults(), **override}
            if bad is None:
                del inputs["FILTER_AUTH"]
            else:
                inputs["FILTER_AUTH"] = bad
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "output"
                output.write_text("existing=kept\n")
                outcome = run(compute, {**inputs, "GITHUB_OUTPUT": str(output)})
                check(outcome.returncode == 1 and "FILTER_AUTH must be true or false" in outcome.stderr,
                      f"invalid FILTER_AUTH={bad!r}, overrides={override}: {outcome}")
                check(output.read_text() == "existing=kept\n" and outcome.stdout == "",
                      "invalid selection must publish no partial outputs, even under overrides")


def selector_independence():
    for event, labels, paths, reason in (
        ("pull_request", '["ci:auth"]', "false", "label:ci:auth"),
        ("pull_request", "[]", "true", "paths"),
        ("schedule", "[]", "false", "event:schedule"),
        ("push", "[]", "false", "event:push"),
        ("merge_group", "[]", "false", "event:merge_group"),
        ("workflow_dispatch", "[]", "false", "event:workflow_dispatch"),
    ):
        selected = run(selector, {"EVENT_NAME": event, "LABELS_JSON": labels,
                                  "FILTER_AUTH": paths, "FORCE_AUTH": "false"})
        check(selected.returncode == 0, f"selector: {selected.stderr}")
        check(outputs(selected.stdout) == {"auth": "true", "reason": reason},
              f"selector {event}/{labels}/{paths}: {selected.stdout}")
        computed = run(compute, {**defaults(), "FILTER_AUTH": outputs(selected.stdout)["auth"],
                                 "GITHUB_OUTPUT": ""})
        check(computed.returncode == 0, f"selection: {computed.stderr}")
        check(outputs(computed.stdout) == {
            "ruby": "false", "auth": "true", "typescript": "false", "frontend": "false",
            "oci": "false", "billing": "false", "ga_workflow_files": "false",
        }, f"label/path/event auth is its own flag and must not turn on Ruby or any other filter: {computed.stdout}")
    computed = run(compute, {**defaults(), "FILTER_BILLING": "true", "GITHUB_OUTPUT": ""})
    check(computed.returncode == 0, f"billing selection: {computed.stderr}")
    check(outputs(computed.stdout) == {
        "ruby": "false", "auth": "false", "typescript": "false", "frontend": "false",
        "oci": "false", "billing": "true", "ga_workflow_files": "false",
    }, f"billing is its own flag and must not turn on Ruby, auth or any other filter: {computed.stdout}")
    inputs = defaults()
    del inputs["FILTER_BILLING"]
    computed = run(compute, {**inputs, "RUN_ALL": "true", "GITHUB_OUTPUT": ""})
    check(computed.returncode == 0 and outputs(computed.stdout)["billing"] == "true",
          "a run-all event skips the path filter, so billing has no input and must still be selected")


jobs = block(workflow, "jobs", 0)


def triggers():
    events = block(workflow, "on", 0)
    check(set(re.findall(r"^  ([a-z_]+):", events, re.M)) == {
        "push", "schedule", "merge_group", "pull_request", "workflow_dispatch",
    }, "CI must cover PR, dispatch, nightly, main/release push, and merge queue")
    push = block(events, "push", 2)
    check(block(push, "branches", 4).strip() == "- main", "main coverage baseline")
    check(block(push, "tags", 4).strip() == "- 'v*'", "release tags run CI")
    check(block(events, "schedule", 2).strip() == "- cron: '3 4 * * *'", "daily full coverage")
    check(scalar(block(events, "merge_group", 2), "types", 4) == "[checks_requested]",
          "merge queue must trigger checks")
    pr = block(events, "pull_request", 2)
    check(scalar(pr, "types", 4) == "[opened, synchronize, reopened]",
          "code changes trigger CI; a label event must not start a second full run")
    check(not re.search(r"\b(?:un)?labeled\b", executable(events)),
          "no label events: the selector reads the PR's labels live instead")
    check(not re.search(r"^ +paths(?:-ignore)?:", events, re.M), "required verdict must not be path-filtered")
    changes = block(jobs, "changes", 2)
    dispatch = re.findall(r'^ +DISPATCH_RUN_ALL="(.+)"$', changes, re.M)
    check(dispatch == [expression(
        "(github.event_name == 'workflow_dispatch' && inputs.run_all == true) || "
        "github.event_name == 'schedule' || github.event_name == 'push' || "
        "github.event_name == 'merge_group'"
    )], "nightly, main/release push, merge queue, and explicit dispatch force all CI lanes")
    check('./.github/scripts/detect-ci-flags.sh "$DISPATCH_RUN_ALL"' in changes,
          "the event override must reach CI flag detection")
    concurrency = block(workflow, "concurrency", 0)
    check(scalar(concurrency, "group", 2) == "ci-" + expression("github.workflow")
          + "-" + expression("github.ref"), "one concurrency group per ref")
    check(scalar(concurrency, "cancel-in-progress", 2) == "true", "a new push supersedes the run before it")


def shared_wiring():
    changes = block(jobs, "changes", 2)
    check(not re.search(r"^    if:", changes, re.M), "changes runs on every event")
    permissions = block(changes, "permissions", 4)
    for permission in ("contents", "pull-requests"):
        check(scalar(permissions, permission, 6) == "read", f"selector needs {permission}:read")
    check(scalar(block(changes, "outputs", 4), "auth", 6) == expression("steps.compute.outputs.auth"),
          "changes.auth must publish the final compute output, not bypass ci-skip")
    check(re.search(r"^        id: auth\n        uses: \./\.github/actions/detect-auth-changes\n"
                    r"        with:\n          force: \$\{\{ steps.check-flags.outputs.run_all \}\}$",
                    changes, re.M), "shared local auth selector receives the CI force flag")
    auth_step = step(changes, "auth")
    check(not re.search(r"^        (?:if|continue-on-error):", auth_step, re.M),
          "shared selector must run on every event without masking detection errors")
    check(changes.index("uses: actions/checkout@") < changes.index("id: auth") < changes.index("id: compute"),
          "checkout must precede the local selector and selector must precede compute")
    compute_step = step(changes, "compute")
    compute_env = block(compute_step, "env", 8)
    for key, value in {
        "SKIP_CI": "steps.check-flags.outputs.skip_ci", "RUN_ALL": "steps.check-flags.outputs.run_all",
        "GA_WORKFLOWS": "steps.filter.outputs.ga_workflow_files", "FILTER_AUTH": "steps.auth.outputs.auth",
        **{"FILTER_" + name.upper(): "steps.filter.outputs." + name
           for name in ("ruby", "typescript", "frontend", "oci", "billing")},
    }.items():
        check(scalar(compute_env, key, 10) == expression(value), f"compute receives {key}")
    check(scalar(compute_step, "run", 8) == "./.github/scripts/compute-path-filter-outputs.sh",
          "compute runs the tested script")


def prerequisites_and_gates():
    for job_id in ("ruby-lint", "ruby-unit"):
        job = block(jobs, job_id, 2)
        check("needs.changes.outputs.ruby == 'true'" in job, f"Ruby changes select {job_id}")
        check("needs.changes.outputs.auth" not in job, f"auth selection alone must not run {job_id}")
    check(scalar(block(jobs, "build-assets", 2), "if", 4) ==
          "needs.changes.outputs.frontend == 'true' || needs.changes.outputs.ruby == 'true' "
          "|| needs.changes.outputs.auth == 'true' || needs.changes.outputs.billing == 'true'",
          "auth-only and billing-only selection still get the frontend build their jobs download")
    browser = block(jobs, "ruby-auth-browser", 2)
    integration = block(jobs, "ruby-integration-auth", 2)
    for job_id, job in (("ruby-auth-browser", browser), ("ruby-integration-auth", integration)):
        check(scalar(job, "needs", 4) == "[changes, ruby-lint, build-assets]",
              f"{job_id}: same lint/assets prerequisites; no unit or unrelated auth dependency")
        check(not re.search(r"^    continue-on-error:", job, re.M), f"{job_id} remains blocking")
    check(scalar(browser, "if", 4) == "&if-auth-tests |", "browser defines the shared auth gate")
    check(scalar(integration, "if", 4) == "*if-auth-tests", "configuration jobs use the same auth gate")
    check(" ".join(block(browser, "if", 4).split()) == (
        "always() && needs.changes.outputs.auth == 'true' && "
        "(needs.ruby-lint.result == 'success' || needs.ruby-lint.result == 'skipped') && "
        "(needs.build-assets.result == 'success' || needs.build-assets.result == 'skipped') && "
        "!contains(needs.*.result, 'cancelled')"
    ), "auth jobs run independently of Ruby output, accept successful/skipped prerequisites, reject failure/cancel")
    billing = block(jobs, "ruby-integration-billing", 2)
    check(scalar(billing, "needs", 4) == "[changes, ruby-lint, build-assets]",
          "ruby-integration-billing: same lint/assets prerequisites as the other full-mode jobs")
    check(not re.search(r"^    continue-on-error:", billing, re.M), "ruby-integration-billing remains blocking")
    check(" ".join(block(billing, "if", 4).split()) == (
        "always() && needs.changes.outputs.billing == 'true' && "
        "(needs.ruby-lint.result == 'success' || needs.ruby-lint.result == 'skipped') && "
        "(needs.build-assets.result == 'success' || needs.build-assets.result == 'skipped') && "
        "!contains(needs.*.result, 'cancelled')"
    ), "billing rows run on the billing flag alone, not on Ruby or auth selection")
    changes = block(jobs, "changes", 2)
    check(scalar(block(changes, "outputs", 4), "billing", 6) == expression("steps.compute.outputs.billing"),
          "changes publishes the billing flag")
    names = re.findall(r"^              - '\{apps,lib,etc,spec,try\}/\*\*/\*(\{[^}]+\})\*(/\*\*)?'$", changes, re.M)
    check([suffix for _, suffix in names] == ["", "/**"] and names[0][0] == names[1][0],
          f"the billing filter's file and directory lines must carry the same name list: {names}")
    for path in ("apps/web/billing/**", "tests/lanes/overlays/**"):
        check(f"              - '{path}'" in changes, f"billing filter lists {path}")
    simple = block(jobs, "ruby-integration-simple", 2)
    check(scalar(simple, "if", 4) == "&if-ruby-integration |", "general Ruby gate remains shared")
    check("needs.changes.outputs.ruby == 'true'" in block(simple, "if", 4)
          and "outputs.auth" not in block(simple, "if", 4)
          and "outputs.billing" not in block(simple, "if", 4), "general integration stays selected for ordinary Ruby")
    for job_id in ("ruby-integration-api", "ruby-integration-full", "ruby-integration-disabled"):
        check(scalar(block(jobs, job_id, 2), "if", 4) == "*if-ruby-integration",
              f"{job_id} retains the general Ruby gate")


def matrix(job_id):
    job = block(jobs, job_id, 2)
    strategy = block(job, "strategy", 4)
    check(scalar(strategy, "fail-fast", 6) == "false", f"{job_id}: every matrix row runs")
    include = block(block(strategy, "matrix", 6), "include", 8)
    rows = []
    for line in include.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"          - name: '([^']+)'", line)
        if match:
            rows.append({"name": match[1]})
            continue
        match = re.fullmatch(r"            (lane|overlay|services|results-file): (?:'([^']*)'|([a-z0-9-]+))", line)
        check(match is not None and bool(rows), f"unsupported {job_id} matrix line: {line}")
        key, quoted, bare = match.groups()
        check(key not in rows[-1], f"duplicate matrix key: {line}")
        rows[-1][key] = quoted if quoted is not None else bare
    check(all(set(row) == {"name", "lane", "overlay", "services", "results-file"} for row in rows),
          f"{job_id}: every matrix row must specify the original five fields")
    return [tuple(row[key] for key in ("name", "lane", "overlay", "services", "results-file")) for row in rows]


def matrix_coverage():
    # Frozen copy of the eight full-mode cases; not derived from the changed
    # workflow or git HEAD. Every Ruby change runs the whole suite once, on
    # SQLite, and the PG-only specs, both with billing off. Auth selection
    # adds the second pass of the whole suite on PostgreSQL and the two
    # feature-specific boots. Billing selection adds the three lanes again
    # with the billing overlay.
    general = [
        ("SQLite, billing: off", "full-sqlite", "", "valkey rabbitmq", "rspec_full_sqlite_billing_off_results.json"),
        ("PG, billing: off", "full-pg", "", "valkey rabbitmq postgres", "rspec_full_postgres_billing_off_results.json"),
    ]
    auth = [
        ("PG agnostic, billing: off", "full-pg-agnostic", "", "valkey rabbitmq postgres", "rspec_full_pg_agnostic_billing_off_results.json"),
        ("SQLite, MFA", "full-mfa", "", "valkey rabbitmq", "rspec_full_mfa_results.json"),
        ("SQLite, platform SAML", "full-saml-platform", "", "valkey rabbitmq", "rspec_full_saml_platform_results.json"),
    ]
    billing = [
        ("SQLite", "full-sqlite", "billing", "valkey rabbitmq", "rspec_full_sqlite_billing_on_results.json"),
        ("PG", "full-pg", "billing", "valkey rabbitmq postgres", "rspec_full_postgres_billing_on_results.json"),
        ("PG agnostic", "full-pg-agnostic", "billing", "valkey rabbitmq postgres", "rspec_full_pg_agnostic_billing_on_results.json"),
    ]
    actual_general, actual_auth = matrix("ruby-integration-full"), matrix("ruby-integration-auth")
    actual_billing = matrix("ruby-integration-billing")
    check(actual_general == general, f"the two full rows every Ruby change runs changed: {actual_general}")
    check(actual_auth == auth, f"the three auth-selected rows changed: {actual_auth}")
    check(actual_billing == billing, f"the three billing-selected rows changed: {actual_billing}")
    check(all(row[2] == "" for row in actual_general + actual_auth),
          "billing-on rows belong to ruby-integration-billing only")
    # Lane, overlay and results file identify a case; the display name may differ per job.
    check(len({row[1:] for row in actual_general + actual_auth + actual_billing}) == 8,
          "matrix split must neither drop nor duplicate an old case")
    check(scalar(block(jobs, "ruby-integration-billing", 2), "steps", 4) == "*full-integration-steps",
          "billing rows run the same steps, not a divergent copy")
    full = block(jobs, "ruby-integration-full", 2)
    check(scalar(full, "steps", 4) == "&full-integration-steps", "full job defines shared steps")
    check(scalar(block(jobs, "ruby-integration-auth", 2), "steps", 4) == "*full-integration-steps",
          "auth configuration runs the same steps, not a divergent copy")
    steps = block(full, "steps", 4)
    check("- *checkout-step" in steps and "uses: ./.github/actions/setup-ruby-test-env" in steps,
          "matrix steps retain checkout and Ruby environment")
    check(scalar(block(steps, "env", 8), "SERVICES", 10) == expression("matrix.services")
          and "run: docker compose -f compose.test.yml up --wait -d $SERVICES" in steps,
          "every matrix row starts its original services")
    for setup in ("uses: actions/setup-python@", "uses: actions/setup-node@", "uses: pnpm/action-setup@",
                  "node-version-file: '.node-version'"):
        check(setup in steps, f"shared matrix setup retains {setup}")
    check("uses: ./.github/actions/run-test-lane" in steps, "matrix uses the lane runner")
    for field in ("lane", "overlay", "results-file"):
        check(scalar(steps, field, 10) == expression("matrix." + field), f"matrix passes {field} to the lane")


def browser_extraction():
    unit = block(jobs, "ruby-unit", 2)
    browser = block(jobs, "ruby-auth-browser", 2)
    check(re.findall(r"^          lane: (.+)$", unit, re.M) == ["unit"], "unit job runs only the unit lane")
    check("results-file: 'rspec_unit_results.json'" in unit, "unit artifact filename retained")
    check(not re.search(r"playwright|lane: browser|tests/browser", executable(unit), re.I),
          "ordinary Ruby unit job must not install or execute browsers")
    check("file: coverage/coverage.xml" in unit and 'run: echo "COVERAGE=true" >> "$GITHUB_ENV"' in unit,
          "unit coverage remains scoped to units")
    check(re.findall(r"^          lane: (.+)$", browser, re.M) == ["browser"], "auth browser job runs the original browser lane")
    check("results-file: 'rspec_browser_results.json'" in browser, "browser artifact filename retained")
    install = "run: pnpm exec playwright install --with-deps chromium firefox webkit"
    check(browser.count(install) == 1 and browser.index(install) < browser.index("lane: browser"),
          "all three original engines install before the browser lane")
    for prerequisite in ("- *checkout-step", "- *start-core-services", "uses: ./.github/actions/setup-ruby-test-env",
                         "uses: actions/setup-python@", "uses: ./.github/actions/setup-node-env",
                         "uses: ./.github/actions/run-test-lane"):
        check(prerequisite in browser, f"browser retains setup: {prerequisite}")
    check("COVERAGE=true" not in browser, "browser extraction must not contaminate unit coverage")


def lane_tasks():
    # Read contracts only; never execute the lane runner or Ruby tasks.
    for lane, task in {
        "full-sqlite": "spec:integration:full", "full-pg": "spec:integration:full:postgres",
        "full-pg-agnostic": "spec:integration:full:agnostic_on_pg", "full-mfa": "spec:integration:full:mfa",
        "full-saml-platform": "spec:integration:full:saml_platform", "api": "spec:api",
        "disabled": "spec:integration:disabled",
    }.items():
        actual = executable((root / "tests/lanes" / lane / "tasks").read_text())
        check(actual == "bundle exec rake " + task, f"{lane}: lane tasks changed: {actual}")
    for lane, tasks in (("unit", ("try:unit", "spec:fast")),
                        ("simple", ("try:integration:simple", "spec:integration:simple"))):
        actual = executable((root / "tests/lanes" / lane / "tasks").read_text())
        expected = '\n'.join([
            "failed=()", *(f"bundle exec rake {task} || failed+=({task})" for task in tasks),
            'if (( ${#failed[@]} > 0 )); then',
            f'echo "[lane:{lane}] FAILED leg(s): ${{failed[*]}} — every leg ran; each leg\'s results are above" >&2',
            "exit 1", "fi",
        ])
        check(actual == expected, f"{lane}: existing independent task legs changed: {actual}")
    browser = executable((root / "tests/lanes/browser/tasks").read_text())
    expected_browser = '''missing="$(node --input-type=module -e '
import { chromium, firefox, webkit } from "@playwright/test";
import { existsSync } from "node:fs";
const engines = { chromium, firefox, webkit };
console.log(Object.keys(engines).filter((n) => !existsSync(engines[n].executablePath())).join(" "));
')" || { echo "[lane:browser] error: node could not load @playwright/test (run: pnpm install)" >&2; exit 69; }
if [[ -n "${missing}" ]]; then
echo "[lane:browser] error: Playwright browser(s) not installed: ${missing}" >&2
echo "  install them with: pnpm exec playwright install chromium firefox webkit" >&2
echo "  (bin/setup --test does this; on Linux the OS packages come from" >&2
echo "  pnpm exec playwright install-deps, which uses sudo/apt)" >&2
exit 69
fi
rspec_args=(tests/browser --format progress)
if [[ -n "${RSPEC_OUTPUT_FILE:-}" ]]; then
rspec_args+=(--format json --out "${RSPEC_OUTPUT_FILE}")
fi
bundle exec rspec "${rspec_args[@]}"'''
    check(browser == expected_browser, "browser lane's engine preflight, test scope, and JSON reporting stay unchanged")


def reporting():
    for report_id in ("aggregate-test-results", "ci-verdict", "ci-metrics"):
        report = block(jobs, report_id, 2)
        needs = block(report, "needs", 4)
        for job_id in ("ruby-auth-browser", "ruby-integration-auth", "ruby-integration-billing"):
            check(len(re.findall(r"^      - " + job_id + r"$", needs, re.M)) == 1,
                  f"{report_id} must wait for {job_id} exactly once")
        check(scalar(report, "if", 4) == "always()", f"{report_id} runs even on skipped/failed auth")
    verdict_env = block(block(jobs, "ci-verdict", 2), "env", 8)
    check(scalar(verdict_env, "AUTH", 10) == expression("needs.changes.outputs.auth"), "verdict receives required auth selection")
    check(scalar(verdict_env, "BILLING", 10) == expression("needs.changes.outputs.billing"),
          "verdict receives the billing selection; without it a skipped billing job reads as unselected")
    for job_id in ("ruby-auth-browser", "ruby-integration-auth", "ruby-integration-billing"):
        variable = "RESULT_" + job_id.upper().replace("-", "_")
        check(scalar(verdict_env, variable, 10) == expression(f"needs.{job_id}.result"),
              f"verdict receives {job_id}'s result")
        check(expression(f"needs.{job_id}.result") in block(jobs, "ci-metrics", 2),
              f"metrics reports {job_id}'s result")
    check("pattern: 'rspec-*-results'" in block(jobs, "aggregate-test-results", 2),
          "aggregate includes lane artifacts from both auth jobs")


for stable_id, test in (
    ("CI-AUTH-01", compute_cases),
    ("CI-AUTH-02", invalid_auth),
    ("CI-AUTH-03", selector_independence),
    ("CI-AUTH-04", triggers),
    ("CI-AUTH-05", shared_wiring),
    ("CI-AUTH-06", prerequisites_and_gates),
    ("CI-AUTH-07", matrix_coverage),
    ("CI-AUTH-08", browser_extraction),
    ("CI-AUTH-09", lane_tasks),
    ("CI-AUTH-10", reporting),
):
    try:
        test()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        failures.append(stable_id)
        print(f"FAIL {stable_id} {test.__name__}: {error}", flush=True)
    else:
        print(f"PASS {stable_id} {test.__name__}", flush=True)

if failures:
    print("Parent fix required: " + ", ".join(failures), flush=True)
    sys.exit(1)
PY
