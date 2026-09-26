#!/usr/bin/env bash
#
# scripts/ci/ci-metrics-breakdown.sh
#
# The test-run half of the T5 CI Metrics report: what actually completed, how
# long each TEST STEP took, and how that compares with recent main.
#
# WHY THIS EXISTS
#
# The tier table in .github/actions/check-ci-metrics measures one thing: how
# long after the workflow started the last job of a tier finished. That is the
# critical path — queue wait, T0/T1, runner setup, bundle install, the tests,
# the uploads — and a 20s slower unit lane is invisible inside a 9-minute
# figure that swings by a minute with runner availability. The tier table also
# counts a job as done whether it passed or died in setup, and it checks a
# fixed budget, never a trend. This script answers the three questions the
# tier table cannot:
#
#   1. Did the tiers complete, and with which jobs failed or skipped?
#   2. How long did each test job wait for a runner, and how long did it run?
#      The jobs API carries created_at (queued: the moment its `needs`
#      finished), started_at (a runner picked it up) and completed_at, so
#      queue wait and runtime are separable — and a slow tier is then either
#      the code or the fleet, which call for different fixes.
#   3. How long did each test step run — the step's own start to finish, so
#      the unit lane is separated from the browser lane and from the setup
#      steps around them?
#   4. Is any test job or step slower than it was on main?
#
# INPUT
#
# Jobs listings from the GitHub API (`/repos/{owner}/{repo}/actions/runs/{id}/
# jobs?per_page=100`), saved to files: the current run first, then zero or more
# successful main runs as the baseline. Nothing here talks to the network, so
# scripts/tests/ci-metrics-breakdown-test.sh can drive it from fixtures.
#
# WHICH STEPS COUNT
#
# Steps of T2/T3 jobs whose name starts with "Run " and names a lane or tests:
# "Run unit lane", "Run browser lane", "Run lane" (the T3 matrix), "Run
# TypeScript tests with coverage". Diagnostic probes and setup steps are not
# test execution and are left out. A step's row is keyed by job name and step
# name, so a matrix row that gains or loses a lane shows as "new" or "not run"
# instead of silently moving the baseline.
#
# BASELINE AND FLAGS
#
# Baseline is the per-job and per-step median across the baseline runs (a
# single run is too noisy: runner variance on a 3-minute step is easily
# ±15%). A job's runtime or a step is flagged when it is both
# CI_METRICS_FLAG_PCT percent and CI_METRICS_FLAG_MIN seconds slower than its
# baseline — the second guard keeps 4s→6s from reading as +50%. Faster is
# reported, never flagged. Queue time is shown against its main median but
# never flagged: it is runner availability, not the change under test.
#
# USAGE
#
#   ci-metrics-breakdown.sh <current-jobs.json> [<baseline-jobs.json> ...]
#
# Prints GitHub-flavored markdown on stdout. Exit 0 whenever the input parses;
# the report is information, not a gate.
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <current-jobs.json> [<baseline-jobs.json> ...]" >&2
  exit 64
fi

FLAG_PCT="${CI_METRICS_FLAG_PCT:-25}"
FLAG_MIN="${CI_METRICS_FLAG_MIN:-15}"

# One jq program over all inputs: the first document is the current run, the
# rest are baseline runs. Everything else is formatting.
jq -s -r --argjson flag_pct "$FLAG_PCT" --argjson flag_min "$FLAG_MIN" '
  def seconds($a; $b):
    if ($a // null) == null or ($b // null) == null then null
    else (($b | fromdateiso8601) - ($a | fromdateiso8601)) end;

  def fmt($s):
    if $s == null then "—"
    elif $s >= 60 then "\($s / 60 | floor)m \($s % 60)s"
    else "\($s)s" end;

  def median:
    sort | if length == 0 then null
           elif length % 2 == 1 then .[length / 2 | floor]
           else ((.[length / 2 - 1] + .[length / 2]) / 2 | round) end;

  def tier($job): ($job.name | capture("^(?<t>T[0-9]) · ") | .t) // null;

  # The test steps of one jobs listing: [{key, job, step, conclusion, secs}].
  def test_steps:
    [ .jobs[]
      | select(tier(.) as $t | $t == "T2" or $t == "T3")
      | .name as $job
      | .conclusion as $job_conclusion
      | .steps[]
      | select(.name | test("^Run .*(lane|tests)"; "i"))
      | { key: "\($job) :: \(.name)",
          job: ($job | sub("^T[0-9] · "; "")),
          step: (.name | sub("^Run "; "")),
          conclusion: (.conclusion // $job_conclusion // "unknown"),
          secs: seconds(.started_at; .completed_at) }
    ];

  # The test-tier jobs of one listing: [{key, job, conclusion, queued, ran,
  # released}], released being seconds after the first job of the run was
  # created (the run start, as the jobs listing sees it). No apostrophes in
  # here: this whole program sits inside single quotes.
  def test_jobs:
    ([ .jobs[].created_at | select(. != null) ] | min) as $run_start
    | [ .jobs[]
        | select(tier(.) as $t | $t == "T2" or $t == "T3" or $t == "T4")
        | { key: .name,
            job: (.name | sub("^T[0-9] · "; "")),
            tier: tier(.),
            conclusion: (.conclusion // "in_progress"),
            queued: seconds(.created_at; .started_at),
            ran: seconds(.started_at; .completed_at),
            released: seconds($run_start; .created_at) }
      ];

  def pct($now; $then):
    if $now == null or $then == null or $then == 0 then ""
    else ((($now - $then) * 100 / $then) | round) end;

  def delta($p): if $p == "" then "" elif $p > 0 then "+\($p)%" else "\($p)%" end;

  def slower($now; $then; $p):
    $p != "" and $p >= $flag_pct and ($now - $then) >= $flag_min;

  .[0] as $cur
  | .[1:] as $bases
  | ($cur | test_jobs | sort_by(.key)) as $jobs
  | ([ $bases[] | test_jobs[] | select(.conclusion == "success") ]
     | group_by(.key)
     | map({ (.[0].key): { ran: (map(.ran | select(. != null)) | median),
                            queued: (map(.queued | select(. != null)) | median) } })
     | add // {}) as $base_jobs
  | ($cur | test_steps | sort_by(.key)) as $steps
  | ([ $bases[] | test_steps[] | select(.conclusion == "success" and .secs != null) ]
     | group_by(.key)
     | map({ (.[0].key): { job: .[0].job, step: .[0].step, secs: (map(.secs) | median) } })
     | add // {}) as $base

  # ── Completion, per tier ─────────────────────────────────────────────
  | "### Completion",
    "",
    "| Tier | State | Jobs |",
    "|------|-------|------|",
    ( ["T1", "T2", "T3", "T4"][] as $t
      | [ $cur.jobs[] | select(tier(.) == $t) ] as $jobs
      | ($jobs | map(.conclusion // "in_progress")) as $c
      | ($c | map(select(. == "success")) | length) as $ok
      | ($c | map(select(. == "skipped")) | length) as $skipped
      | ($c | length) as $n
      | ( if $n == 0 then "❓ no jobs"
          elif $ok == $n then "✅ success"
          elif $skipped == $n then "⏭️ skipped"
          else "⚠️ partial" end ) as $state
      | ( [ ($ok | select(. > 0) | "\(.) succeeded"),
            ($skipped | select(. > 0) | "\(.) skipped"),
            ( [ $jobs[] | select((.conclusion // "in_progress") | IN("success", "skipped") | not)
                | "\(.conclusion // "in_progress"): \(.name | sub("^T[0-9] · "; ""))" ]
              | select(length > 0) | join(", ") )
          ] | join(", ") ) as $detail
      | "| \($t) | \($state) | \($detail) |" ),
    "",

  # ── Jobs: queue wait and runtime, this run against the baseline ─────
    "### Jobs",
    "",
    "| Job | Result | Queued | Ran | Ran on main | Δ | |",
    "|-----|--------|-------:|----:|------------:|--:|---|",
    ( $jobs[]
      | $base_jobs[.key] as $b
      | ( if .conclusion != "success" then "" else pct(.ran; $b.ran) end ) as $p
      | ( if $b == null then (if ($bases | length) == 0 then "" else "🆕 new" end)
          elif .conclusion == "skipped" then "⏭️ skipped"
          elif .conclusion != "success" then "❌"
          elif slower(.ran; $b.ran; $p) then "⚠️ slower"
          else "" end ) as $flag
      | "| \(.job) | \(.conclusion) | \(if .conclusion == "skipped" then "—" else fmt(.queued) end) | " +
        "\(if .conclusion == "skipped" then "—" else fmt(.ran) end) | \(if $b == null then "—" else fmt($b.ran) end) | " +
        "\(delta($p)) | \($flag) |" ),
    "",
    ( [ $jobs[] | select(.tier != "T4" and .conclusion != "skipped" and .queued != null) ] as $tj
      | if ($tj | length) == 0 then "_No T2/T3 job ran, so nothing queued._"
        else
          ($tj | min_by(.released)) as $first
          | ($tj | max_by(.queued)) as $longest
          | ([ $base_jobs | to_entries[] | .value.queued | select(. != null) ] | median) as $main_q
          | "Queue: the T2/T3 jobs were released \(fmt($first.released)) after the workflow started (T0/T1 done) " +
            "and waited up to \(fmt($longest.queued)) for a runner (longest: \($longest.job)" +
            (if $main_q == null then "" else "; median wait on main \(fmt($main_q))" end) + "). " +
            "Queue time is runner availability, not the change under test, and is never flagged."
        end ),
    "",

  # ── Test steps, this run against the baseline ────────────────────────
    "### Test steps",
    "",
    "| Step | This run | Baseline | Δ | |",
    "|------|---------:|---------:|--:|---|",
    ( $steps[]
      | $base[.key] as $b
      | ( if .conclusion != "success" then "\(.conclusion)"
          else fmt(.secs) end ) as $this
      | ( if $b == null then "—" else fmt($b.secs) end ) as $baseline
      | ( if $b == null or .conclusion != "success" then "" else pct(.secs; $b.secs) end ) as $pct
      | ( if $b == null then (if ($bases | length) == 0 then "" else "🆕 new" end)
          elif .conclusion != "success" then "❌"
          elif slower(.secs; $b.secs; $pct) then "⚠️ slower"
          else "" end ) as $flag
      | "| \(.job) · \(.step) | \($this) | \($baseline) | \(delta($pct)) | \($flag) |" ),
    ( $base | to_entries[]
      | select(.key as $k | ($steps | map(.key) | index($k)) == null)
      | "| \(.value.job) · \(.value.step) | not run | \(fmt(.value.secs)) |  | ⏭️ not in this run |" ),
    "",
    ( if ($bases | length) == 0 then
        "_No baseline: no successful `main` run of this workflow was available to compare against._"
      else
        "Baseline: median of \($bases | length) successful `main` run(s) — " +
        ( [ $bases[] | .jobs[0] | select(. != null)
            | "[\(.run_id)](\(.run_url | sub("api.github.com/repos"; "github.com")))\(if .head_sha then " `\(.head_sha[0:8])`" else "" end)" ]
          | join(", ") ) + "."
      end ),
    "",
    "Job time is the job'"'"'s own start to finish (setup, tests, uploads); step time is the step'"'"'s " +
    "own start to finish — test execution alone. Neither includes queue. " +
    "⚠️ marks a job or step at least \($flag_pct)% and \($flag_min)s slower than its main median."
' "$@"
