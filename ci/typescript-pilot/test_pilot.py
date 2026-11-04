"""Failure handling and comparison boundaries for the CI pilot tools."""

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


pilot, comparison = load("run"), load("compare")


class RunnerTests(unittest.TestCase):
    def test_failed_tests_still_run_typecheck(self):
        run = pilot.Run({})
        with patch.object(run, "phase", side_effect=[0, 1, 0]) as phase:
            self.assertEqual(run.workload(), 1)
        self.assertEqual(
            [c.args[0] for c in phase.call_args_list], ["locales", "tests", "typecheck"]
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


class ComparisonTests(unittest.TestCase):
    def records(self):
        base = dict(
            schema_version=1,
            commit_sha="a" * 40,
            image="pinned",
            node="26.4.0",
            pnpm="11.10.0",
            python="3.14.0",
            expected_node="26.4.0",
            expected_pnpm="11.10.0",
            workers=2,
            cache_mode="cold",
            working_tree_dirty=False,
            test_inventory_sha256="tests",
            tests={"numTotalTests": 2},
            status="passed",
        )
        return [
            {**base, "provider": "gitlab", "seconds": 100},
            {**base, "provider": "circleci", "seconds": 80},
        ]

    def test_pairs_matching_commits(self):
        result = comparison.compare(self.records())
        self.assertEqual(result["paired_passes"], 1)
        self.assertEqual(
            result["summary_passing_pairs_only"]["circleci"]["p50_seconds"], 80
        )

    def test_duplicate_reruns_require_explicit_selection(self):
        rows = self.records()
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            comparison.compare(rows + [rows[0]])

    def test_mismatched_test_inventory_is_rejected(self):
        rows = self.records()
        rows[1]["test_inventory_sha256"] = "other"
        with self.assertRaisesRegex(ValueError, "inventories"):
            comparison.compare(rows)

    def test_mismatched_toolchain_is_rejected(self):
        rows = self.records()
        rows[1]["node"] = "27.0.0"
        with self.assertRaisesRegex(ValueError, "node"):
            comparison.compare(rows)

    def test_failure_counts_are_retained_outside_timing_summary(self):
        rows = self.records()
        rows[1]["status"] = "failed"
        result = comparison.compare(rows)
        self.assertEqual(result["failed_pairs"], 1)
        self.assertEqual(result["summary_passing_pairs_only"], {})

    def test_bootstrap_failure_without_installed_versions_is_counted(self):
        rows = self.records()
        rows[1]["status"] = "failed"
        del rows[1]["node"]
        del rows[1]["pnpm"]
        self.assertEqual(comparison.compare(rows)["failed_pairs"], 1)

    def test_missing_provider_is_reported(self):
        result = comparison.compare(self.records()[:1])
        self.assertEqual(len(result["unpaired_commits"]), 1)
        self.assertEqual(result["paired_commits"], 0)

    def test_local_results_cannot_become_hosted_benchmarks(self):
        rows = self.records()
        rows[1]["cache_mode"] = "local-existing"
        with self.assertRaisesRegex(ValueError, "hosted"):
            comparison.compare(rows)


if __name__ == "__main__":
    unittest.main()
