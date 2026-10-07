# Auth and billing CI selection

The slow, auth-specific parts of CI run on a pull request only when the PR
touches auth code or carries the `ci:auth` label. Billing integration
coverage runs nightly only. Everything else runs on `main`, nightly, on
release tags, and in the merge queue.

## What is selected

The [auth path list](../../.github/auth-paths.yml) and the `ci:auth` label
select these jobs:

- The `full-pg-agnostic` lane. It runs the database-agnostic full-mode suite
  a second time, against PostgreSQL, and is the slowest row in the Ruby
  matrix.
- The `full-mfa` and `full-saml-platform` configuration lanes.
- The `browser` lane, which exercises SAML callbacks in Chromium, Firefox, and
  WebKit.
- [Full-auth E2E](../../.github/workflows/e2e-full-auth.yml), including real
  verification email delivery.
- [Tenant Connect E2E](../../.github/workflows/e2e-tenant-connect.yml).

## What every Ruby change still runs

Full authentication mode is tested on every Ruby change. Two full-mode rows
are not selected by auth or billing: the whole full-mode suite once, on
SQLite, and the PostgreSQL-only specs, both with billing off. The unit,
simple-mode, disabled-mode and API lanes, Tryouts, and Vitest keep their
existing path-based selection. Billing's own specs and tryouts are the
`billing` lane (ruby-billing), gated like the unit lane, so they run on every
Ruby change too.

[Container E2E](../../.github/workflows/e2e.yml) keeps its own selection and
both its simple and full-mode rows.

## Billing integration (nightly only)

Two jobs cover billing integration, and both run only on the nightly
schedule:

- `ruby-integration-billing` repeats the three full-mode lanes
  (`full-sqlite`, `full-pg`, `full-pg-agnostic`) with the billing overlay,
  which sets `BILLING_ENABLED=true`. They run the same specs as the
  billing-off rows.
- `ruby-billing-integration` runs the `billing-integration` lane: the
  mode-less specs directly under `apps/web/billing/spec/integration/` and the
  `try/integration/billing` tryouts.

No path selects them. A pull request skips both whatever it touches, and so
do a push to `main`, a tag push, a merge-queue check and the `[ci-all]`
commit flag. The `changes` job publishes the selection as
`billing_integration`, true on the `schedule` event or a manual dispatch with
`run_all` ticked, and false otherwise; `[ci-skip]` turns it off too. The
`ci-verdict` check expects both jobs skipped on every other event and
requires them to pass on the nightly.

To run them against a branch before the nightly does, use **Run workflow**
with `run_all` ticked, or run the lanes locally: `tests/lanes/run
billing-integration` and `tests/lanes/run full-sqlite --overlay billing`.

Billing's unit tests are not affected: the `billing` lane (ruby-billing) runs
on every Ruby change.

## When auth runs on a pull request

The detector evaluates the **whole PR diff**, not just the latest commit. Auth
runs if any changed path matches the list, or the PR has the `ci:auth` label.

The list is narrow on purpose. It names the code that implements sign-in,
sessions, SSO, MFA, invitations and tenant identity, anything in application
code named for one of those concepts, and the tests and configuration that
only the selected jobs run. Shared backend and frontend code, dependencies
other than gems, translations, and documentation do not select auth. A change
to shared code can therefore break an auth-only job without that job running
on its PR. The run on `main` after merge, or the nightly run, is where that
shows up.

Auth selection is a flag of its own in main CI. It adds the auth jobs and the
frontend build they download. It does not turn on Ruby lint or the ordinary
Ruby test jobs; those follow the Ruby path filter as before.

## When everything runs

Auth runs regardless of paths on:

- Every push to `main`, in all three workflows.
- Pushes of tags matching `v*`.
- Daily scheduled runs on the default branch: main CI at 04:03, full-auth E2E
  at 04:23, and Tenant Connect at 04:43 UTC.
- Merge queue checks (`merge_group`).
- Manual dispatch of any of the three workflows.

Main CI runs all of its jobs, not only the auth ones, on pushes to `main`,
tags, scheduled runs and merge-queue checks, with one exception: the two
billing integration jobs run on the scheduled run alone (see "Billing
integration" above). Its manual `run_all` input selects every main-CI job,
the billing integration jobs included; without it, a dispatch still runs
auth but the other jobs keep path-based selection. The `[ci-all]` commit
flag applies to main CI, not the separate E2E workflows, and does not select
the billing integration jobs. `[ci-skip]` cannot produce a passing main-CI
verdict.

### Before a release

Check that the commit you are about to tag is green in **CI**, **E2E Full
Auth** and **E2E Tenant Connect**. A push to `main` starts all three for that
commit, but not the billing integration jobs: those need the nightly run that
followed the push, or a **Run workflow** dispatch with `run_all` ticked. A
run is cancelled when another push to `main` lands behind it, so look at the
commit's checks instead of assuming. For a commit without them, or any other
ref such as a release branch, use **Run workflow** on the Actions page for
each of the three, with `run_all` ticked for CI. The tag push then runs all
three again.

## Requesting a run on a pull request

Add the `ci:auth` label, then start a run: push a commit, or use **Re-run all
jobs** on the CI, E2E Full Auth and E2E Tenant Connect runs. **Re-run failed
jobs** is not enough, because it does not repeat the detection job.

Adding or removing a label does not start a run by itself. The workflows do
not listen for label events; the detector asks the GitHub API for the PR's
current labels each time it runs. That keeps unrelated labels from starting a
second full CI run on the same commit. Removing `ci:auth` does not suppress
tests selected by changed paths.

Create the label in the repository if it does not exist.

Each detector writes its decision and reason to the job summary. If auth was
expected but did not run, inspect detection, lint, build, and cancellation
results rather than treating the skipped test job as a pass.

## Required checks

Keep `ci-verdict` as the stable main-CI check. It covers the SAML browser job,
the auth-selected matrix and the nightly-only billing integration jobs, and
rejects a missing or malformed auth selection.

The specialized workflows expose stable verdicts:

| Workflow | Verdict check |
| --- | --- |
| E2E Full Auth | `auth-e2e-verdict` |
| E2E Tenant Connect | `tenant-connect-verdict` |

If these workflows are required by branch protection or a ruleset, require
the verdict checks instead of their individual conditional test jobs. The
verdicts run even when tests are intentionally unnecessary. Detection failure,
unexpected skipping, test failure, or cancellation does not pass.

The workflow files do not change GitHub rulesets or create repository labels.
Update required-check settings when adopting the new verdicts.

## Maintaining selection

The [shared detector](../../.github/actions/detect-auth-changes/action.yml),
the [label reader](../../.github/scripts/read-pr-labels.sh) and the
[selection script](../../.github/scripts/compute-auth-selection.sh) are used
by all three workflows.

Add a path to the list when new auth code lives outside the listed
directories and is not named for an auth concept. Do not add shared code to
make a one-off PR run auth; label that PR instead. The list accepts `*`, `**`,
`{a,b}` and two-letter classes such as `[Aa]`, and nothing else.

The selector's path fixtures and the verdict regression tests live under
[`scripts/tests/`](../../scripts/tests/), and run in the
[Static analysis workflow](../../.github/workflows/static-analysis.yml).

Local Ruby execution is unchanged. Use the
[lane runner](../../tests/lanes/README.md) when you need a targeted local
reproduction; CI selection does not require running every lane locally.
