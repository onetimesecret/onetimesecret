# Auth CI selection

Auth-specific configuration and browser tests run when a pull request changes
relevant code, or when a maintainer explicitly requests them. Core tests and
application integration coverage keep their existing path-based selection.

## What is selected

The shared [auth path filter](../../.github/auth-paths.yml) selects:

- The `full-mfa` and `full-saml-platform` Ruby configuration lanes.
- The `browser` lane, which exercises SAML callbacks in Chromium, Firefox, and
  WebKit. This is a separate CI job, not a prerequisite of Ruby unit tests.
- [Full-auth E2E](../../.github/workflows/e2e-full-auth.yml), including real
  verification email delivery.
- [Tenant Connect E2E](../../.github/workflows/e2e-tenant-connect.yml).

The six general full-mode Ruby integration rows remain selected on Ruby changes:
SQLite, PostgreSQL-specific tests, and database-agnostic tests on PostgreSQL,
each with billing off and on. These cover application behavior as well as auth;
this change does not make them optional. Simple-mode, disabled-mode, API,
Tryouts, RSpec unit, and Vitest coverage also remain in routine CI.

[Container E2E](../../.github/workflows/e2e.yml) keeps its existing selection
and both its simple and full-mode rows. Its full-mode workspace tests are not
the same suite as the specialized auth journeys.

## When auth runs

For pull requests, the detector evaluates the **whole PR diff**, not just the
latest commit. Auth runs if any path matches or the PR has the `ci:auth` label.
Adding or removing a label triggers a new selection; removing `ci:auth` does
not suppress tests selected by changed paths.

The filter deliberately treats shared backend, boot, configuration, session,
frontend infrastructure, test support, dependencies, and CI machinery as
relevant. Documentation-only changes and standalone billing or dashboard views
outside those shared paths do not select auth. See the filter itself for the
complete list; a directory's name alone does not determine selection.

Coverage configuration (`.simplecov`) selects the ordinary Ruby jobs, not
specialized auth coverage. The isolated admin entrypoint and route table also
do not select these customer-auth journeys; customer route tables do, because
they are registered in the same router as sign-in and verification routes.

In main CI, selecting auth also selects Ruby lint, core Ruby tests, and the
frontend build, so a label or browser-only change cannot leave auth jobs
without their prerequisites.

Auth runs regardless of paths on:

- Manual dispatch of any of the three workflows.
- Daily scheduled runs on the repository's default branch: main CI at 04:03,
  full-auth E2E at 04:23, and Tenant Connect at 04:43 UTC.
- Pushes of tags matching `v*`.
- Merge queue checks (`merge_group`).

Main CI also runs all its jobs on pushes to `main`. Its manual `run_all` input
selects every main-CI job; without it, auth still runs but unrelated jobs retain
path-based selection. The existing `[ci-all]` commit flag applies to main CI,
not the separate E2E workflows. `[ci-skip]` cannot produce a passing main-CI
verdict.

## Requesting a run

To force auth coverage for a PR, add the `ci:auth` label in GitHub. Create the
label in the repository if it does not exist. It is an additive override, not
an alternative to automatic detection.

For a branch or tag outside a PR, use **Run workflow** on the Actions page for
CI, E2E Full Auth, or E2E Tenant Connect. A manual run tests the selected ref;
it is not a substitute for the PR's required checks.

Each detector writes its decision and reason to the job summary. If auth was
expected but did not run, inspect detection, lint, build, and cancellation
results rather than treating the skipped test job as a pass.

## Required checks

Keep `ci-verdict` as the stable main-CI check. It now includes the standalone
SAML browser job and the auth-configuration matrix, and rejects missing or
malformed auth selection.

The specialized workflows expose stable verdicts:

| Workflow | Verdict check |
| --- | --- |
| E2E Full Auth | `auth-e2e-verdict` |
| E2E Tenant Connect | `tenant-connect-verdict` |

If these workflows are required by branch protection or a ruleset, require
the verdict checks instead of their individual conditional test jobs. The
verdicts run even when tests are intentionally unnecessary. Detection failure,
unexpected skipping, test failure, or cancellation does not pass.

This checkout changes workflow files only; it does not change GitHub rulesets
or create repository labels. Update required-check settings when adopting the
new verdicts. Label-triggered runs have separate concurrency groups so they do
not cancel in-flight code-change runs.

## Maintaining selection

The [shared detector](../../.github/actions/detect-auth-changes/action.yml)
and [selection script](../../.github/scripts/compute-auth-selection.sh) are
used by all three workflows. Update the shared filter when a new auth
dependency lives outside the existing shared paths. The selector's path
fixtures and verdict regression tests live under
[`scripts/tests/`](../../scripts/tests/), and run in the
[Static analysis workflow](../../.github/workflows/static-analysis.yml).

Local Ruby execution is unchanged. Use the
[lane runner](../../tests/lanes/README.md) when you need a targeted local
reproduction; CI selection does not require running every lane locally.
