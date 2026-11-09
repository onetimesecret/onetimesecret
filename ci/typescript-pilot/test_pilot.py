"""Failure handling and inventory boundaries for the CI pilot runner."""

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


def load(name):
    spec = importlib.util.spec_from_file_location(
        name, Path(__file__).with_name(name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


pilot = load("run")


class RunnerTests(unittest.TestCase):
    def test_failed_tests_still_run_typecheck(self):
        run = pilot.Run({})
        with patch.object(run, "phase", side_effect=[0, 1, 0]) as phase:
            self.assertEqual(run.workload(), 1)
        self.assertEqual(
            [c.args[0] for c in phase.call_args_list], ["locales", "tests", "typecheck"]
        )

    def test_heap_override_is_scoped_to_typecheck_and_recorded(self):
        original = {"NODE_OPTIONS": "--trace-warnings", "KEEP": "value"}
        run = pilot.Run(original.copy())
        with patch.object(run, "phase", side_effect=[0, 1, 0]) as phase:
            self.assertEqual(run.workload(), 1)
        self.assertNotIn("env", phase.call_args_list[1].kwargs)
        child_env = phase.call_args_list[2].kwargs["env"]
        self.assertEqual(child_env["NODE_OPTIONS"], "--max-old-space-size=3072")
        self.assertEqual(child_env["KEEP"], "value")
        self.assertEqual(run.env, original)
        self.assertEqual(run.metrics["typecheck_heap_mib"], 3072)

    def test_phase_passes_the_overridden_environment_to_child(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "child-env.json"
            run = pilot.Run(dict(os.environ))
            code = "import os,json,sys; open(sys.argv[1], 'w').write(json.dumps(os.environ.get('NODE_OPTIONS')))"
            self.assertEqual(
                run.phase(
                    "probe",
                    [sys.executable, "-c", code, str(output)],
                    env=dict(os.environ, NODE_OPTIONS="--max-old-space-size=3072"),
                ),
                0,
            )
            self.assertEqual(
                json.loads(output.read_text()), "--max-old-space-size=3072"
            )

    def test_typecheck_failure_fails_job(self):
        run = pilot.Run({})
        with patch.object(run, "phase", side_effect=[0, 0, 2]):
            self.assertEqual(run.workload(), 1)

    def test_locale_failure_stops_workload(self):
        run = pilot.Run({})
        with patch.object(run, "phase", return_value=1) as phase:
            self.assertEqual(run.workload(), 1)
        self.assertEqual(phase.call_count, 1)

    def test_mismatched_source_sha_is_rejected(self):
        with patch.object(pilot, "capture", return_value="actual"):
            with self.assertRaisesRegex(ValueError, "SHA"):
                pilot.identity({"GITLAB_CI": "true", "CI_COMMIT_SHA": "merged"}, False)

    def test_hosted_identity_uses_each_providers_native_commit_and_job(self):
        cases = [
            (
                "gitlab",
                {
                    "GITLAB_CI": "true",
                    "CI_COMMIT_SHA": "source",
                    "CI_JOB_ID": "gl-job",
                    "CI_JOB_URL": "https://gitlab.com/job",
                },
                "gl-job",
                "https://gitlab.com/job",
            ),
            (
                "circleci",
                {
                    "CIRCLE_SHA1": "source",
                    "CIRCLE_WORKFLOW_JOB_ID": "cc-job",
                    "CIRCLE_BUILD_URL": "https://app.circleci.com/job",
                },
                "cc-job",
                "https://app.circleci.com/job",
            ),
            (
                "github",
                {
                    "GITHUB_ACTIONS": "true",
                    "GITHUB_SHA": "source",
                    "GITHUB_JOB": "ts-job",
                    "GITHUB_REPOSITORY": "org/repo",
                    "GITHUB_RUN_ID": "123",
                    "GITHUB_RUN_ATTEMPT": "2",
                },
                "ts-job",
                "https://github.com/org/repo/actions/runs/123",
            ),
        ]
        for provider, env, job_id, url in cases:
            with (
                self.subTest(provider=provider),
                patch.object(pilot, "capture", side_effect=["source", ""]),
            ):
                result = pilot.identity(
                    dict(env, PILOT_RESOURCE_CLASS="large", PILOT_EXECUTOR="machine"),
                    False,
                )
            self.assertEqual(result["provider"], provider)
            self.assertEqual(result["commit_sha"], "source")
            self.assertEqual(result["job_id"], job_id)
            self.assertEqual(result["job_url"], url)
            self.assertEqual(result["resource_class"], "large")
            self.assertEqual(result["executor"], "machine")
            self.assertEqual(
                result["run_attempt"], "2" if provider == "github" else None
            )

    def test_github_rejects_wrong_source_sha_and_dirty_checkout(self):
        env = {"GITHUB_ACTIONS": "true", "GITHUB_SHA": "source"}
        with patch.object(pilot, "capture", return_value="different"):
            with self.assertRaisesRegex(ValueError, "SHA"):
                pilot.identity(env, False)
        with patch.object(pilot, "capture", side_effect=["source", " M tracked"]):
            with self.assertRaisesRegex(ValueError, "unmodified"):
                pilot.identity(env, False)

    def test_deadline_terminates_command_and_records_timeout(self):
        run = pilot.Run(dict(os.environ))
        with patch.dict(pilot.PINS, deadline_seconds=0.05):
            self.assertEqual(
                run.phase(
                    "sleep", [sys.executable, "-c", "import time; time.sleep(10)"]
                ),
                124,
            )
        self.assertEqual(run.metrics["phases"][0]["exit_code"], 124)

    def test_bad_report_keeps_failure_metrics(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(pilot, "RESULTS", Path(directory)),
        ):
            (Path(directory) / "unit.json").write_text("{")
            self.assertEqual(pilot.Run({}).finish(0), 1)
            result = json.loads((Path(directory) / "metrics.json").read_text())
            self.assertEqual(result["status"], "failed")
            self.assertIn("report_error", result)

    def test_success_without_reports_is_rejected(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            patch.object(pilot, "RESULTS", Path(directory)),
        ):
            run = pilot.Run({})
            run.metrics["phases"] = [{"name": "tests", "exit_code": 0}]
            self.assertEqual(run.finish(0), 1)


class InventoryTests(unittest.TestCase):
    def report(self, root):
        return {
            "testResults": [
                {
                    "name": str(root / "src/tests/admin-isolation.spec.ts"),
                    "assertionResults": [
                        {
                            "fullName": f"admin import isolation {root}/src/apps/admin/Example.vue has ZERO import edge"
                        },
                        {"fullName": "preserves /external/path and relative/path"},
                    ],
                }
            ]
        }

    def test_finish_normalizes_checkout_paths_in_parameterized_titles(self):
        hashes = []
        for root in (
            Path("/builds/onetimesecret/onetimesecret"),
            Path("/root/project"),
        ):
            with (
                self.subTest(root=root),
                tempfile.TemporaryDirectory() as directory,
                patch.object(pilot, "ROOT", root),
                patch.object(pilot, "RESULTS", Path(directory)),
            ):
                (Path(directory) / "unit.json").write_text(
                    json.dumps(self.report(root))
                )
                self.assertEqual(pilot.Run({}).finish(0), 0)
                metrics = json.loads((Path(directory) / "metrics.json").read_text())
                self.assertEqual(metrics["status"], "passed")
                hashes.append(metrics["test_inventory_sha256"])
        self.assertEqual(hashes[0], hashes[1])

    def test_workspace_checkout_preserves_relative_and_other_absolute_paths(self):
        hashes = []
        for root in (Path("/root/project"), Path("/workspace"), Path("/app[ci].v1+")):
            with self.subTest(root=root):
                report = self.report(root)
                report["testResults"][0]["assertionResults"].extend(
                    {"fullName": title}
                    for title in (
                        "readers src/apps/workspace/account/RecoveryCodes.vue calls useUnrecoverableContent",
                        "preserves /other/workspace/file.ts and relative/workspace/file.ts",
                        f"{root}/src/Example.vue",
                        f'quoted "{root}/src/Example.vue"',
                        f"parenthesized ({root}/src/Example.vue)",
                    )
                )
                hashes.append(pilot.inventory_sha256(report, root))
        self.assertEqual(len(set(hashes)), 1)

    def test_real_inventory_changes_remain_distinct(self):
        root = Path("/root/project")
        expected = pilot.inventory_sha256(self.report(root), root)
        for change in ("file", "title", "duplicate"):
            with self.subTest(change=change):
                report = self.report(root)
                suite = report["testResults"][0]
                if change == "file":
                    suite["name"] = str(root / "src/tests/other.spec.ts")
                elif change == "title":
                    suite["assertionResults"][0]["fullName"] += " changed"
                else:
                    suite["assertionResults"].append(suite["assertionResults"][0])
                self.assertNotEqual(pilot.inventory_sha256(report, root), expected)

    def test_checkout_prefix_requires_a_directory_boundary(self):
        hashes = []
        for root in (Path("/builds/app"), Path("/root/project")):
            report = self.report(root)
            report["testResults"][0]["assertionResults"][0]["fullName"] = (
                f"outside checkout {root}-sibling/src/Example.vue"
            )
            hashes.append(pilot.inventory_sha256(report, root))
        self.assertNotEqual(hashes[0], hashes[1])

    def test_suite_outside_checkout_is_rejected(self):
        with self.assertRaises(ValueError):
            pilot.inventory_sha256(
                self.report(Path("/elsewhere")), Path("/root/project")
            )


if __name__ == "__main__":
    unittest.main()
