#!/usr/bin/env python3
"""Compare downloaded metrics.json artifacts, pairing unique source commits."""

import argparse
import json
import statistics
from pathlib import Path

MATCH_FIELDS = (
    "schema_version",
    "image",
    "expected_node",
    "expected_pnpm",
    "python",
    "workers",
    "typecheck_heap_mib",
    "cache_mode",
)


def compare(records):
    pairs = {}
    for row in records:
        provider = row.get("provider")
        if (
            provider not in {"gitlab", "circleci"}
            or row.get("cache_mode") != "cold"
            or row.get("working_tree_dirty") is not False
            or row.get("schema_version") != 1
        ):
            raise ValueError("Only clean hosted cold-cache results can be compared")
        key = (row["commit_sha"], provider)
        if key in pairs:
            raise ValueError(
                f"Duplicate {provider} result for {key[0]}; select one attempt explicitly"
            )
        pairs[key] = row
    rows, unpaired = [], []
    for sha in sorted({key[0] for key in pairs}):
        gl, cc = pairs.get((sha, "gitlab")), pairs.get((sha, "circleci"))
        if not gl or not cc:
            unpaired.append(sha)
            continue
        for field in MATCH_FIELDS:
            if gl.get(field) != cc.get(field) or gl.get(field) is None:
                raise ValueError(f"{sha}: mismatched or missing {field}")
        passed = gl["status"] == cc["status"] == "passed"
        if passed:
            for field in ("node", "pnpm"):
                if gl.get(field) != cc.get(field) or gl.get(field) != gl.get(
                    "expected_" + field
                ):
                    raise ValueError(f"{sha}: mismatched installed {field}")
            if not gl.get("test_inventory_sha256") or gl.get(
                "test_inventory_sha256"
            ) != cc.get("test_inventory_sha256"):
                raise ValueError(f"{sha}: test inventories differ or are missing")
            if not gl.get("tests") or gl["tests"] != cc.get("tests"):
                raise ValueError(f"{sha}: test counts differ or are missing")
        rows.append(
            {
                "commit_sha": sha,
                "both_passed": passed,
                "gitlab_status": gl["status"],
                "circleci_status": cc["status"],
                "gitlab_seconds": gl["seconds"],
                "circleci_seconds": cc["seconds"],
            }
        )
    passed = [r for r in rows if r["both_passed"]]
    summary = {}
    for provider in ("gitlab", "circleci"):
        values = sorted(r[provider + "_seconds"] for r in passed)
        if values:
            position = (len(values) - 1) * 0.95
            lower = int(position)
            p95 = values[lower] + (
                values[min(lower + 1, len(values) - 1)] - values[lower]
            ) * (position - lower)
            summary[provider] = {
                "p50_seconds": statistics.median(values),
                "p95_seconds": p95,
            }
    return {
        "paired_commits": len(rows),
        "paired_passes": len(passed),
        "failed_pairs": len(rows) - len(passed),
        "unpaired_commits": unpaired,
        "summary_passing_pairs_only": summary,
        "pairs": rows,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "paths",
        nargs="+",
        type=Path,
        help="Downloaded metrics files or artifact directories",
    )
    args = parser.parse_args()
    files = set()
    for path in args.paths:
        files.update(path.rglob("metrics.json") if path.is_dir() else [path])
    if not files:
        parser.error("No metrics.json files found")
    try:
        report = compare([json.loads(p.read_text()) for p in sorted(files)])
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    print(json.dumps(report, indent=2))
    return 0 if report["paired_commits"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
