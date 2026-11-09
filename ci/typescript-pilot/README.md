# GitLab TypeScript CI

The root [GitLab configuration](../../.gitlab-ci.yml) runs TypeScript unit
tests and test type checking. It does not replace GitHub's full CI suite or
run Ruby tests, browser tests, builds, deployments, or publishing.

## Reused pilot

`run.py` and `toolchain.json` are copied unchanged from commit
`79124636a3` on `ci-pilot/typescript`. The runner and inventory tests are
retained; the cross-provider comparison tool and its tests, CircleCI
configuration, and experimental GitHub workflow are not included.

The runner installs checksum-verified Node and the pnpm version from
`package.json`, installs frozen dependencies, generates locales, runs all
Vitest projects with two workers, then runs `pnpm type-check:tests`.
Ordinary test failures do not suppress type checking, and either failure
fails the job. Locale-generation failures stop the workload.

The hosted job uses a fresh checkout without a dependency cache on
`saas-linux-medium-amd64`. It has a 20-minute job timeout; the runner gives
its subprocesses a shared 15-minute budget. The type checker receives a
3 GiB V8 old-space budget. Toolchain versions and budgets live in
[toolchain.json](toolchain.json); update the image there and in the root
YAML together.

## Pipeline triggers and reports

- Branch pushes run the job, including pushes to `main`.
- Merge-request events run the job.
- A branch push with an open MR is suppressed in favor of the MR pipeline.
- Tags, schedules, and manually started pipelines are excluded.

Unlike the original pilot, this is not limited to `ci-pilot/*` pushes.
The runner checks the checkout against `CI_COMMIT_SHA`; for merged-results
pipelines that identifies the synthetic merge commit, not the source head.
Do not interpret those results as source-head benchmark measurements.

GitLab uploads `tmp/typescript-pilot/results/` even after a job failure and
retains artifacts for 30 days. These include JUnit XML, Vitest JSON, and
phase metrics when produced. Bootstrap failures may have only metrics;
cancelled or forcibly terminated jobs may have incomplete reports.

## Validate locally

Run from the repository root. Follow [AGENTS.md](../../AGENTS.md) and enable
test mode through `bin/setup --test` before running tests. Local workload
validation requires installed dependencies, the exact Node and pnpm
versions expected by the runner, and Python 3.14.

```sh
python3.14 -m unittest discover -s ci/typescript-pilot -p 'test_*.py' -v
python3.14 ci/typescript-pilot/run.py --local
```

Local mode uses existing dependencies and records `provider=local` and
`cache_mode=local-existing`. It does not validate the Linux image or the
cold-install path.

With authenticated GitLab CLI access:

```sh
glab ci lint .gitlab-ci.yml --include-jobs -R https://gitlab.com/onetimesecret/onetimesecret
glab ci lint .gitlab-ci.yml --dry-run --ref main --include-jobs -R https://gitlab.com/onetimesecret/onetimesecret
```

CI Lint validates configuration; it does not execute the job. A hosted run
requires this change to be published to GitLab separately. This change
does not synchronize GitLab `main`, change project settings, or modify
merge requirements.
