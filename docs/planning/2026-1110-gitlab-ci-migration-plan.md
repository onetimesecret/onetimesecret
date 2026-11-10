# GitLab CI/CD migration plan

**Status (2026-11-10):** proposal. Nothing in this document is implemented.

**Evidence base:** `develop` at b8a13618 (2026-11-09) for the GitHub side,
`main` at 82cd4348 for the GitLab pilot, GitHub Actions run history read on
2026-11-10, and GitLab documentation retrieved on 2026-11-10 (GitLab 19.5).
Appendix B lists the GitLab facts this plan depends on and which of them were
not confirmed.

**Scope:** the 29 workflows in `.github/workflows/`, the composite actions and
scripts they call, and the repository automation configured under `.github/`.
Moving issues, pull request history and product links is adjacent work (§10).

**How statements are marked:** text in double quotes is exact wording from the
named file. "Proposal" marks a design choice made here. "Inferred" marks a
finding that was reasoned from the files and not observed; verify it on the
current baseline before applying a fix (AGENTS.md, "Security-posture
decisions").

Delete this document once Phase 6 is complete.

## 1. Summary

1. **One pipeline replaces 29 workflows.** A single GitLab pipeline definition,
   split across about ten include files, with pipeline types chosen by
   `workflow:rules` (merge request, merge train, `main`, tag, nightly, weekly,
   manual).
2. **Consolidate first, migrate second.** The CI logic in `.github/scripts/`
   and the shell embedded in composite actions moves into tool packages under
   `tools/` behind `bin/` entry points (ADR-042) while GitHub Actions is still
   the gate. The GitLab YAML then calls only `bin/` commands and
   `tests/lanes/run`.
3. **Lanes do not change.** The lane spec requires loopback test endpoints, so
   GitLab's `services:` hostnames cannot serve them. Each job that needs
   services runs a Docker daemon inside the job and uses `compose.test.yml`
   as it is.
4. **The pipeline status is the gate.** GitLab decides mergeability per
   pipeline, and a job excluded by `rules` does not exist. The four verdict
   jobs, the four change-detection jobs and seven of the eighteen
   `.github/scripts/` files are deleted and not ported.
5. **Build once per pipeline.** The frontend and the OCI image are each built
   once and reused. Today the `main` image is built from scratch in five
   places, and publishing does not wait for any boot test. The publish job
   promotes the digest that was tested.
6. **New capabilities worth adopting:** native arm64 builds, merge trains,
   keyless image signing with SBOM and provenance, GitLab's SAST, secret
   detection and container scanning, and test reports in the merge request.
7. **Compute is the main cost question.** GitHub Actions is free for this
   public repository. GitLab hosted runners are metered, and the current run
   volume is above the Premium quota on main CI alone (§4.12).
8. **Some things are lost:** job summaries, tmate debug sessions, the path
   labeler, and, until it is ported, the CI metrics comment. macOS jobs need a
   decision.
9. **Seven phases.** GitHub stays the gate until Phase 5 and can be restored
   until Phase 6.

## 2. Where things stand

### 2.1 GitHub Actions today

| Item | Count |
|---|---|
| Workflows | 29 files, 8,550 lines |
| Local composite actions | 10 files, 2,127 lines (1 has no caller) |
| `.github/scripts/` | 18 files, 2,669 lines |
| Third-party actions in live use | 21, all pinned by SHA |
| Repository secrets referenced | 20 (Docker Hub 2, custom registry 3, Sentry 5, Bump.sh 8, Claude 1, translation webhook 1) |
| Repository variables referenced | 4 |
| Scheduled triggers | 6 nightly, 8 weekly, 1 daily housekeeping |

Facts that shape the design:

- No test job needs a secret. `ci.yml`, the e2e, visual, migration and Ruby
  preview workflows use only the run's own token; application secrets are
  generated in the job.
- Ruby tests enter through `tests/lanes/run`, and services come from
  `compose.test.yml` on `127.0.0.1` ports. The three e2e workflows and
  `bin/visual` boot the app natively on the runner and also assume loopback.
- The image workflow builds three variants (`main`, `-s6`, `-lite`) for
  `linux/amd64` and `linux/arm64` with QEMU on one runner, and pushes to GHCR
  and Docker Hub, or to one custom registry. There is no layer cache, signing,
  SBOM or image scan.
- Reviewers on pull requests: Renovate, Dependabot security updates, Greptile,
  Codex and Claude.
- `tools/testsuite/` tests the CI scripts offline. 14 of its 15 suites read
  files under `.github/` as text.

### 2.2 GitLab today

- The project exists at `gitlab.com/onetimesecret/onetimesecret`.
- `main` has a pilot that `develop` lacks: `.gitlab-ci.yml` (one job,
  TypeScript unit tests and test type checking, `saas-linux-medium-amd64`) and
  `ci/typescript-pilot/` (#4932).
- `main` also has `.agents/skills/merge/SKILL.md` (#4940), which merges through
  GitLab merge requests with merge commits and treats `main` as protected.
- Branch `ci-pilot/typescript` compared GitLab, CircleCI and GitHub runners for
  the same workload.

### 2.3 Measured load

Read from the GitHub Actions API on 2026-11-10:

- All workflows: 1,000 runs between 2026-11-08 04:49 and 2026-11-10 04:45 UTC,
  about 500 runs a day.
- `ci.yml`: 300 runs between 2026-10-24 and 2026-11-10, about 18 a day.
- One pull request's main CI run (#4939, auth paths touched, no TypeScript):
  12 test jobs summing to 34 minutes of job time; with lint and build, about
  39 (estimated). The `main` medians in that PR's CI metrics comment sum to
  about 40 minutes for 13 jobs, not counting lint, build and the smoke test.
- Wall time for that run was about 12 minutes. The promotion PR (#4927) took
  27 minutes.

## 3. Constraints the design must respect

**C1. Loopback test endpoints.** The lane spec
(`docs/specs/testing-lanes/testing-lanes.md`) says of itself: "This document
records the design decisions and invariants that must remain true when
changing the lane runner, lane definitions, compose topology, or CI
integration." The file has no status field; this plan treats it as governing
for lanes. Its first safety invariant: "Test endpoints are loopback-only and
use the test-port scheme below; the runner-only RabbitMQ management endpoint
is its documented exception." The mechanism is in `spec/config.test.yaml`:
"Host and port are hardcoded on purpose (#2128): a test boot can only ever
reach the isolated test valkey on 2163, never a dev/prod service, and no env
var can redirect it."

**C2. One source for lane needs.** Same spec: "`tests/lanes/` and the root
`compose.test.yml` are the single source of truth for what a lane needs. CI
and local execution enter through `tests/lanes/run`." Also: "Port mappings
belong only in `compose.test.yml`; lane environment files carry matching
`21xx` service URLs."

**C3. CI decides policy, lanes decide workload.** Same spec, invariant 5: "CI
policy is not lane policy. Lanes define the environment and workload;
workflows decide whether a failure blocks, how work is parallelized, and how
results are reported."

**C4. Tooling lives in tool packages.** ADR-042 (accepted): "Application-coupled
tooling that has shared logic, dependencies, or tests is a **tool package**.
Tool packages live under `tools/<domain>/`; contributors use them through a
small, language-agnostic root command in `bin/<domain>`." And: "Contributors
and CI call the root command rather than a package-private path." Its
migration rule: "A migration moves one domain at a time, preserves its
behavior and tests, moves callers to `bin/<domain>`, and removes a legacy
wrapper only after repository callers no longer require it." It also permits
exceptions: "Small shell adapters, CI glue, and compatibility wrappers may
remain in `scripts/` when introducing a package would not improve their
maintenance."

**C5. Release notes.** ADR-009 (accepted): "Scriv owns the narrative; Release
Drafter owns the inventory." No workflow runs Release Drafter today, and it
is a GitHub Action. The ADR needs an amendment before its config is removed
(D7).

**C6. Selection policy.** `docs/development/auth-ci.md` describes which jobs
run on which event. It is a development guide, not an ADR. This plan keeps
the behavior it describes and rewrites the guide at cutover.

**C7. Access changes need approval.** AGENTS.md: "Changes that widen access,
including on error paths, require explicit operator approval." §4.11 lists
the changes in this plan that fall under that rule.

## 4. Target design

Everything in this section is a proposal.

### 4.1 Pipeline types

| Type | Selected by | Replaces | Runs |
|---|---|---|---|
| Merge request | `$CI_PIPELINE_SOURCE == "merge_request_event"` | `pull_request` in 21 workflows | always-on checks, plus jobs selected by path or label |
| Merge train | `$CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"` | `merge_group` | everything except billing |
| `main` | push to `main` | `push: main` | everything except billing; API docs deploy |
| Tag | `$CI_COMMIT_TAG` matching `v*` | tag triggers in 4 workflows | everything including billing; build, validate, publish, release |
| Nightly | schedule with `SCHEDULE=nightly` | 6 crons between 03:00 and 04:43 UTC | everything including billing, Ruby preview, migrations, nightly image |
| Weekly | schedule with `SCHEDULE=weekly` | 7 Monday crons | install and boot lanes, published-image smoke, full register scan |
| Manual | web or API, with `spec:inputs` | `workflow_dispatch` in 27 workflows | inputs `run_all`, `publish`, `platforms`, `version_tag` |
| Triage | schedule with `SCHEDULE=triage` | stale and lock crons | `gitlab-triage` |

`workflow:rules` sets `RUN_ALL` and `NIGHTLY` per type, so jobs test one
variable and not the event. The duplicate-pipeline guard from the pilot
(`$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS` with `when: never`) stays.
Pipeline inputs must each have a default, because merge request pipelines
cannot set them.

A nightly schedule on `develop` is worth adding. Today `develop` is tested
only through pull requests that target it, and a change to shared code can
break an auth-only job that was not selected on its PR.

### 4.2 File layout

```text
.gitlab-ci.yml          inputs, workflow rules, stages, defaults, includes,
                        and the signing job (id_tokens)
.gitlab/ci/
  rules.yml             path lists and rule fragments
  base.yml              job templates: toolchain image, caches, services, lane
  lint.yml              linters, hygiene, guards, audits, tooling tests
  frontend.yml          build, Vitest, type checks, i18n
  ruby.yml              lanes, migrations, Ruby preview
  images.yml            toolchain image, OCI build, container validation
  e2e.yml               container e2e, full-auth, tenant-connect, visual
  smoke.yml             install and boot lanes
  release.yml           publish, Sentry, release, visual archive, API docs
  automation.yml        triage and review jobs
.gitlab/issue_templates/, .gitlab/merge_request_templates/
docker/ci/toolchain.dockerfile
tools/<domain>/ and bin/<domain>      (§5)
```

One rule for the YAML: a `script:` entry is one command that calls a `bin/`
entry point, `tests/lanes/run`, or a package manager. Shell written inside
YAML cannot be checked by shellcheck or tested by `bin/testsuite`.

Stages follow the existing tiers (lint and build, test, image, e2e, publish,
report) and jobs use `needs` so that tests start when lint and build finish,
as they do now.

### 4.3 Execution environment

**Toolchain image.** One image built from `docker/ci/toolchain.dockerfile`
replaces `setup-ruby`, `setup-node`, `pnpm/action-setup`, `setup-python` and
the per-job `apt` and `pip` installs. Contents: Ruby from `.ruby-version`,
Node from `.node-version`, pnpm from `package.json`, Python, uv, bash 5, jq,
the Docker engine and CLI with compose and buildx, a PostgreSQL client,
shellcheck and pre-commit. Two variants: one adds the Playwright browsers
(tag tied to `@playwright/test`), one swaps in the Ruby preview version.
The image is stored in the project registry and referenced by digest from one
variable in `base.yml`. A guard job compares the pin files with the image and
fails on drift, which extends what `scripts/check-version-pins.sh` does now.

**Services on loopback.** `bin/ci services up <names>` starts a Docker daemon
inside the job container when none is reachable, then runs
`docker compose -f compose.test.yml up --wait -d <names>`. Published ports
are then on the job's own `127.0.0.1`, bind mounts resolve in the job's own
filesystem, and `LANES_NO_AUTOSTART=1` works as it does today. GitLab's hosted
Linux runners support this: "Runners with any of the
saas-linux-<size>-<architecture> tags are configured to run in privileged mode
to support Docker-in-Docker." The same command serves the native e2e jobs,
`bin/visual`, the compose smoke jobs and the devcontainer job.

Alternatives considered:

- `services:` with hostnames. Rejected: it breaks C1 and moves image tags and
  service configuration out of `compose.test.yml`, which breaks C2.
- A `docker:dind` service with the test process in a second container on the
  daemon's host network. Works, but adds a container hop and a shared-volume
  dependency. It is the fallback if the in-job daemon fails spike S1.
- A self-hosted runner with the `instance` executor needs neither, because
  jobs run on the VM as they do on GitHub (D1).

**Caches and artifacts.** Bundler cache keyed on `Gemfile.lock`, pnpm store
keyed on `pnpm-lock.yaml`, pre-commit environments, and a registry layer cache
for image builds. Consumers use `policy: pull`. The frontend build, lane logs,
RSpec results and reports stay artifacts with the retention they have now.
Both caches are disabled today with `DEBUG` comments
(`.github/actions/setup-node-env/action.yml:75`, `ci.yml:354`); find out why
before turning them on.

**Cancellation.** `interruptible: true` by default with
`workflow:auto_cancel:on_new_commit: interruptible` replaces the concurrency
groups. Schedule, tag and publish pipelines set `auto_cancel` to `none`. This
removes a current defect (inferred): a push to `main` cancels the nightly run
in the same concurrency group, and the nightly is the only scheduled run with
billing coverage.

**Runner tags** come from variables, so the fleet can change without editing
jobs (D1).

### 4.4 Selection

| Today | GitLab |
|---|---|
| `changes` job with `dorny/paths-filter` (`ruby`, `typescript`, `frontend`, `oci`, `harness`) | `rules:changes` fragments in `rules.yml`, shared with `!reference` |
| `.github/auth-paths.yml` (47 patterns) and the `ci:auth` label read through the API | `rules:changes` plus `$CI_MERGE_REQUEST_LABELS =~ /ci:auth/` |
| `run_all` on push, schedule, merge queue and dispatch | `RUN_ALL` from `workflow:rules:variables` |
| `billing_nightly` | `NIGHTLY`, set for schedule, tag and manual `run_all` |
| `[ci-all]` commit flag | label `ci:all` |
| `[ci-skip]` commit flag, which must not produce a passing verdict | GitLab's own skip, with "Skipped pipelines are considered successful" off |
| A change under `.github/workflows/**` or `.github/actions/**` forces everything | A change to `.gitlab-ci.yml`, `.gitlab/ci/**`, `docker/ci/**` or `tools/ci/**` forces everything |

- In a merge request pipeline `rules:changes` compares against the target
  branch, which matches the documented policy that the detector evaluates the
  whole diff. `compare_to` is avoided; GitLab's docs call it unreliable with
  merged results pipelines and in forks.
- Labels are read when the pipeline is created, as now: adding `ci:auth`
  needs a new pipeline.
- The commit flags are replaced by labels because they appear not to work on
  pull requests today (inferred: the detector reads the message of the
  synthetic merge commit).
- Deleted: `detect-ci-flags.sh`, `compute-path-filter-outputs.sh`,
  `compute-auth-selection.sh`, `read-pr-labels.sh`, the `detect-auth-changes`
  action, and the `changes` jobs in `ci.yml`, `e2e.yml`, `e2e-full-auth.yml`
  and `e2e-tenant-connect.yml`.

Testing: the selection scripts have offline suites today. Selection written as
`rules` needs tests that assert the resolved job list for fixture scenarios
(docs-only change, auth path, label, tag, schedule). GitLab's own lint
simulation only models a push to the default branch, so this needs a
third-party evaluator (spike S3). Until S3 passes, selection has less test
coverage than it has now (R2).

### 4.5 Gate

- Project settings: "Pipelines must succeed" on, "Skipped pipelines are
  considered successful" off.
- Every merge request pipeline has always-on jobs (lint, guards), because the
  setting "requires the existence of a successful pipeline, not the absence of
  failed pipelines."
- A job that depends on a job that may be absent uses `needs: optional: true`.
- `allow_failure` is used only for the Ruby preview jobs and for scanners
  during their baseline period.
- With Premium: merged results pipelines and merge trains on `main` and
  `develop` replace the merge queue (D5).
- Deleted: `ci-verdict` and `ci-verdict.sh` with its suite, the three e2e
  verdict jobs, the `always() && (success || skipped)` conditions on every
  downstream job, and the sparse checkouts in tail jobs. They exist because,
  in the words of `ci-verdict.sh`, "A required status check sees only one
  job's conclusion, and GitHub counts a skipped job as passing."

### 4.6 Build once: frontend, images, release

**Frontend.** One `frontend:build` job per pipeline. Lanes, native e2e, visual
and smoke jobs take its artifact. Today the frontend is built separately in
`ci.yml`, three e2e workflows, two visual workflows and the Ruby preview.

**Image.** One `image:build` job runs the bake group with a registry cache and
pushes to `$CI_REGISTRY_IMAGE/build:<sha>`. Container validation, the three
container e2e lanes and the full-stack compose smoke pull that image. Merge
request pipelines build `linux/amd64` only. The Dockerfile keeps its own
frontend build stage; the image stays self-contained.

**Multi-arch.** Tag, nightly and manual pipelines build each architecture on a
native runner and merge the manifests. QEMU goes away. GitLab's docs: "Running
jobs on their respective architectures avoids performance issues from CPU
instruction translation."

**Publish.** `image:publish` needs container validation and e2e in the same
pipeline, then copies the tested digests to the public registries with the
tags from `bin/oci plan`. Today the publish workflow and CI start
independently on a tag, so `latest` can be pushed while CI is failing.
`bin/oci plan` is the tag logic from `build-and-publish-oci-images.yml:254-332`
as tested code. Three edge cases to check while porting (inferred): a
prerelease tag without `-rc` gets `latest`; `next` has two meanings; a
dispatch with `source_branch` can label one commit and build another.

**Signing and attestation.** New. The publish job signs with cosign using a
GitLab ID token (available on GitLab.com on every tier) and attaches the
buildx SBOM and provenance. The signing identity is public interface once
published; document it in the release notes of the first signed release.

**Sentry.** Same steps and the same best-effort behavior, called through
`bin/sentry`.

**Release.** A `release:` job (GitLab's `glab`-based keyword) creates the
release on a tag with the scriv section for that version. No workflow creates
a release today.

**Visual archive.** Same `oras push`, to the registry chosen in D3.

**Not touched:** the Gitolite and podman build path described by
`.oci-build.json`. It remains a second image build path.

### 4.7 Reporting

| Today | GitLab | Note |
|---|---|---|
| Job summaries (45 uses of `$GITHUB_STEP_SUMMARY`) | collapsible log sections and the reports below | no equivalent exists |
| RSpec JSON, aggregated into a unified report | JSON kept; `bin/ci results junit` converts it for `artifacts:reports:junit` | the lane runner refuses `SPEC_OPTS` formatters, so conversion happens in CI (C3) |
| Vitest | JUnit reporter | the pilot does this |
| Playwright `github` reporter | JUnit, and the HTML report through `artifacts:expose_as` | reporter chosen by an environment variable, not by provider |
| Visual regression PR comment | `expose_as` link to the diff report | |
| Migration results PR comment | JUnit | |
| CI metrics PR comment (tier budgets, per-job change against `main`) | ported in Phase 6 as `bin/ci metrics` reading GitLab's jobs API | a gap until then (D10) |
| Ruby 4 outcome table | `allow_failure` jobs show as warnings | script deleted |
| tmate debug session | none on hosted runners | lost; lane log artifacts remain |

Coverage is not reported today. `coverage_report` with Cobertura output would
add diff annotations; it is optional and not part of parity.

### 4.8 Security scanning and supply chain

| Area | Today | Proposal |
|---|---|---|
| Ruby dependencies | bundler-audit on every PR | keep |
| JavaScript dependencies | no audit in CI | add `osv-scanner` over both lockfiles |
| SAST | none | GitLab SAST |
| Secrets | `detect-private-key` hook only | GitLab pipeline secret detection |
| Container image | none | GitLab container scanning on the `image:build` output |
| CI config lint | actionlint with a baseline | pipeline creation validates the config; `glab ci lint` locally |
| Signing, SBOM, provenance | none | §4.6 |
| Pinning | actions by SHA, images by digest | images by digest, components and includes by SHA |

The scanners are available on every tier, but on Free and Premium their
results are JSON artifacts only; showing findings in the merge request needs
Ultimate. Without Ultimate, add a ratchet in the style of the existing
shellcheck baseline: fail on findings that are not in a committed baseline.
New scanners start non-blocking and gate after their baseline is triaged
(Phase 6).

### 4.9 Dependency updates

- Renovate continues. Host it as a scheduled pipeline in a separate project
  using `renovate-bot/renovate-runner`, with one bot account for every
  migrated repository (D11).
- Config changes: drop `helpers:pinGitHubActionDigests`; replace
  `vulnerabilityAlerts`, which depends on GitHub's alerts, with
  `osvVulnerabilityAlerts`; point the custom regex manager at the new YAML.
- Tool versions that no manager tracks today (shellcheck, actionlint, uv,
  bump-cli) move into the toolchain Dockerfile where Renovate can see them.
- Dependabot security pull requests stop when GitHub stops being the source.
  The OSV alerts above cover that.
- Every Renovate merge request is a pipeline. The current settings
  (`prCreation: immediate`, 10 concurrent, 10 an hour) are a cost on metered
  runners; a schedule window and grouping reduce it.

### 4.10 Repository automation and review

- **Templates.** Issue forms become Markdown templates in
  `.gitlab/issue_templates/`; GitLab has no YAML forms. The PR template
  becomes `.gitlab/merge_request_templates/Default.md`.
- **Stale and lock.** `gitlab-triage` policies on the triage schedule, with
  the current thresholds. Depends on where issues live (D12).
- **Path labels.** Drop them (D6). Nothing consumes them: Release Drafter is
  not running, and the labels that automation depends on (`ci:auth`,
  `security`, `auto-update`, `dependencies`) are set by other means.
- **AI review.** Greptile has a GitLab integration and its settings in
  `.greptile/` do not name a host. Claude review on merge request open can run
  as a CI job through the documented GitLab integration (beta, maintained by
  GitLab). `@claude` mentions need a webhook listener or Duo external agents
  (Premium, enabled per customer). Codex and Copilot review are tied to
  GitHub. See D8.
- **Translation rules.** `validate-register` and `resolved-derive-gate` run
  the same derive action from `onetimesecret/translation-rules` twice. They
  become one job. The action becomes a CI/CD component in that project when
  it moves; until then the job clones it at the pinned ref.

### 4.11 Secrets and access

All test jobs run without secrets, which is what allows pipelines from forks
and unprotected branches. Credentials become protected, masked and hidden
variables scoped to an environment, so only publish, Sentry and API docs jobs
on protected refs can read them. Pipeline variables are restricted; manual
runs use inputs.

Changes that widen access and need operator approval (C7):

| ID | Change | Why it widens |
|---|---|---|
| P1 | A stored token to push to GHCR | today the push uses the run's own short-lived token |
| P2 | Privileged job containers | on hosted runners each job has its own VM; on a self-hosted fleet this is root on the runner host |
| P3 | A bot token with API write for Renovate, triage and merge request notes | new long-lived credential |
| P4 | Push mirror to GitHub, if kept | needs a GitHub token with write access |
| P5 | "Run pipelines in the parent project" for fork merge requests | runs fork code with the parent's runners and variables; recommend disabling it |

Additive, not widening: the ID token for keyless signing.

### 4.12 Runners and compute

- GitHub's standard runner for public repositories has 4 vCPU (from memory,
  not re-checked). The matching GitLab hosted runner is `saas-linux-medium-amd64` (4 vCPU, 16 GB), cost
  factor 2. Small runners (2 vCPU, factor 1) suit the lint and guard jobs.
- Monthly quotas: 400 minutes on Free, 10,000 on Premium, 50,000 on Ultimate.
- Estimate: 18 main CI runs a day at about 40 job-minutes each on medium
  runners is on the order of 40,000 compute minutes a month for `ci.yml`
  alone. This is an upper-leaning estimate, because dependency-update PRs
  select fewer jobs and some runs are cancelled early. The other workflows add
  to it. Spike S6 replaces this estimate with a measurement.
- The GitLab for Open Source program halves the cost factor and grants
  Ultimate, but its terms say an organization "can't seek to make a profit by
  selling services, by charging for enhancements or add-ons, or by other
  means." Check eligibility before relying on it (D13).
- This design lowers consumption before any purchase: one image build in place
  of five, one frontend build, no repeated toolchain setup, cached
  dependencies, and fewer Renovate pipelines.
- **macOS.** Two jobs need it (`installer.yml` `macos`, `drift-guards.yml`
  `envref-macos`). GitLab's hosted macOS runners are Premium and Ultimate
  only, in beta, with cost factor 6 or 12 (D4).
- **Forks.** A fork's merge request pipeline runs in the fork, on the
  contributor's minutes, with the fork's variables. The toolchain image must
  be publicly readable for that to work.

## 5. Tool packages (ADR-042)

The consolidation happens in Phase 1, on GitHub, one domain per change. Each
change moves the code and its tests, adds the `bin/` shim, and switches the
GitHub workflows to the `bin/` command. Green GitHub CI is the evidence that
behavior is preserved. A file on the delete list in §6 is not moved; it stays
in `.github/scripts/` until the workflows that call it are removed.

Package names below are proposals.

| Package | Entry point | Absorbs | Used by |
|---|---|---|---|
| `tools/ci/` | `bin/ci` | `run-test-lane`, `generate-test-secrets`, `wait-for-http-service` actions; `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh`; the readiness loops and flaky gate copied across the e2e workflows; later `check-ci-metrics` and `ci-metrics-breakdown.sh` | every test job |
| `tools/oci/` | `bin/oci` | `update-version.sh`, `extract-frontend-dist.sh`, the `test-docker-container` action, the tag logic inlined in the publish workflow | image, e2e and publish jobs |
| `tools/sentry/` | `bin/sentry` | `sentry-sourcemap-preflight.sh`, `sentry-status.sh`, `sentry-verify-artifacts.sh`, the three inline copies of `log_cli_output` | publish jobs |
| `tools/checks/` | `bin/check` | `scripts/check-version-pins.sh`, `check-ci-secrets.sh`, `check-shell-lint.sh` with its baselines, `adr-lint.rb`; `check-docs-commands.sh` from `tools/testsuite-installer/` | guard job, pre-commit |
| `tools/envref/` (exists) | `bin/envref` | `scripts/check-env-reference.sh` | guard job |
| `tools/testsuite/` (exists) | `bin/testsuite` | no new code; its suites move to each package's `tests/` directory, which `bin/testsuite run` already discovers | lint stage |
| `tools/testsuite-installer/` (exists) | `bin/testsuite-installer` | unchanged; `seed-compose-env.sh` and `ttfhw-chart.sh` lose their GitHub variables | smoke jobs |

Details:

- **One output layer.** `tools/ci/` provides a small reporter (notice,
  warning, error, group, summary, output) that writes GitHub workflow commands
  under GitHub Actions, GitLab log sections under GitLab CI, and plain text
  elsewhere. Scripts stop writing to `$GITHUB_OUTPUT`, `$GITHUB_ENV` and
  `$GITHUB_STEP_SUMMARY` directly. Much of the Sentry scripts' bulk is this
  layer written three times.
- **`bin/ci lane`** is the `run-test-lane` action as a command: the capture
  profile, the results path and the log paths. It calls `tests/lanes/run` and
  changes nothing in it.
- **`bin/ci e2e-env`** writes the server, worker, seed and Playwright settings
  to one env file. Today `$GITHUB_ENV` is the mechanism that keeps those
  processes on one configuration.
- **`clean_databases.rb`** is called by `package.json` and the smoke lane, not
  by any workflow. Move it to `tests/lanes/support/`.
- **Single-file guards.** ADR-042 lets small adapters stay in `scripts/`.
  `tools/checks/` is proposed anyway because the guards share a baseline
  format and a caller, and one `bin/check all` serves both pre-commit and CI.
  If that grouping is not wanted, they stay where they are and the guard job
  calls them there.
- **`scripts/README.md`** describes a `scripts/ci/` directory that does not
  exist on `develop`. Correct it in the first Phase 1 change.
- **`ci/typescript-pilot/`** (on `main`) sits outside the ADR-042 layout. Most
  of `run.py` installs and verifies Node, which the toolchain image makes
  unnecessary. Retire it when the `frontend.yml` jobs replace the pilot job.
- **Tests that read `.github/` as text** are rewritten as each target moves:
  tests of moved scripts follow them, tests of the `run-test-lane` action
  become tests of `bin/ci lane`, and tests of deleted logic are deleted with
  it.

## 6. Disposition of every existing file

### 6.1 Workflows

| Workflow | Disposition |
|---|---|
| `ci.yml` | `lint.yml`, `frontend.yml`, `ruby.yml`, `images.yml`. `changes` and `ci-verdict` deleted. Aggregate becomes a report job. `ci-metrics` ported in Phase 6. |
| `static-analysis.yml` | `lint.yml`. actionlint dropped at Phase 6. |
| `drift-guards.yml` | one guard job in `lint.yml`. The macOS job follows D4. |
| `docs-command-drift.yml` | folded into the guard job. |
| `validate-config.yml` | its three guards duplicate `drift-guards.yml`; its unique steps (schema generation, `bin/ots config validate`) become a job selected by path. It is dispatch-only today. |
| `validate-register.yml`, `resolved-derive-gate.yml` | one job (§4.10). |
| `bump-api-docs.yml` | `release.yml`: generate, diff on merge requests, deploy on `main`. Fix: each `bump diff` failure, including an auth or network error, is reported as "breaking changes" today. |
| `generate-translation-request.yml` | retire (D9). Its paths `src/locales` and `src/scripts/locales` do not exist in the tree. |
| `housekeeping-github-issues.yml`, `housekeeping-lock-threads.yml` | `gitlab-triage` (§4.10, D12). |
| `pr-labeler.yml` | drop (D6). |
| `secret-rotation.yml` | `smoke.yml`. |
| `claude.yml`, `claude-code-review.yml` | D8. |
| `build-and-publish-oci-images.yml` | `images.yml` and `release.yml`. Its `pull_request` trigger can never fire and is not ported. |
| `debug-oci.yml` | delete in Phase 1. Its header calls it temporary. |
| `compose-smoke.yml`, `baremetal-boot.yml`, `fresh-clone.yml`, `installer.yml`, `devcontainer-ci.yml` | `smoke.yml`, on the weekly schedule and on the same path triggers. The devcontainer job uses the devcontainer CLI. The `macos` job follows D4. |
| `e2e.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml` | `e2e.yml`, sharing one template for setup, readiness, flaky gate and artifacts. |
| `visual.yml` | `e2e.yml`. |
| `visual-archive.yml` | `release.yml`, on tags. |
| `migration-tests.yml` | `ruby.yml`. The concurrent-boot job stays CI orchestration, as the lane spec describes it. |
| `ruby-4-preview.yml` | `ruby.yml`: the lane templates run again on the nightly with the preview toolchain and `allow_failure`. Job bodies are not copied. |

### 6.2 Composite actions

| Action | Disposition |
|---|---|
| `build-and-publish-oci-image` | delete in Phase 1; no caller. |
| `check-ci-metrics` | port to `bin/ci metrics` in Phase 6. |
| `detect-auth-changes` | delete at Phase 6 (rules). |
| `download-frontend-assets` | delete at Phase 6 (artifacts through `needs`). |
| `generate-test-secrets` | `bin/ci secrets`; stop printing the values to the log. |
| `run-test-lane` | `bin/ci lane`. |
| `setup-node-env`, `setup-ruby-test-env` | delete at Phase 6 (toolchain image, caches). |
| `test-docker-container` | `bin/oci smoke`. |
| `wait-for-http-service` | `bin/ci wait-http`. |

### 6.3 `.github/scripts/`

| Script | Disposition |
|---|---|
| `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh` | move to `tools/ci/` |
| `update-version.sh`, `extract-frontend-dist.sh` | move to `tools/oci/` |
| `sentry-sourcemap-preflight.sh`, `sentry-status.sh`, `sentry-verify-artifacts.sh` | move to `tools/sentry/` |
| `clean_databases.rb` | move to `tests/lanes/support/` |
| `ci-metrics-breakdown.sh` | port in Phase 6; its input is GitHub's jobs listing |
| `ci-verdict.sh`, `compute-auth-selection.sh`, `compute-path-filter-outputs.sh`, `detect-ci-flags.sh`, `read-pr-labels.sh`, `post-pr-metrics.cjs`, `ruby4-step-outcomes.sh` | delete at Phase 6 |

### 6.4 Other `.github/` files

| File | Disposition |
|---|---|
| `renovate.json5` | move and adapt (§4.9) |
| `auth-paths.yml` | becomes a fragment in `.gitlab/ci/rules.yml` |
| `ISSUE_TEMPLATE/`, `pull_request_template.md` | `.gitlab/` templates |
| `lint-baseline/shellcheck.tsv` | moves with the shell lint check |
| `lint-baseline/actionlint.tsv`, `actionlint.yaml` | delete at Phase 6 |
| `labeler.yml` | delete (D6) |
| `release-drafter.yml` | delete after the ADR-009 amendment (D7) |
| `dependabot.yml.disabled` | delete in Phase 1 |
| `copilot-instructions.md` | delete at Phase 6; AGENTS.md has the same rules |
| `FUNDING.yml`, `pr-assets/` | keep while GitHub is a mirror (D2) |

### 6.5 Dependencies

- **Removed:** the 21 third-party actions, the cross-repository derive action
  (as an action), actionlint.
- **Added:** the toolchain image; `glab`; cosign; `gitlab-triage`; the
  devcontainer CLI; `osv-scanner`; GitLab's SAST, secret detection and
  container scanning; a self-hosted Renovate runner; a rule evaluator for
  tests if S3 selects one.
- **Changed:** Renovate config; Playwright reporters; `oras` moves from an
  action to the toolchain image; `GITHUB_JOB` detection in
  `lib/onetime/application/auth_strategies/dev_worker_identity.rb` and
  `GITHUB_BASE_REF` in `tools/envref/` gain provider-neutral equivalents.

## 7. Phases

Implementation changes target `develop`. The pilot on `main` reaches
`develop` through the next `main` to `develop` sync; do that first.

### Phase 0: decisions and spikes

No change to CI behavior. Spikes run on a throwaway branch on GitLab.

| Spike | Question | Changes the plan if |
|---|---|---|
| S1 | Does a Docker daemon inside the job work on hosted runners for the `unit` and `full-pg` lanes, a native e2e boot and `bin/visual`? How long do jobs take against GitHub? | it fails: use the `docker:dind` fallback, or self-hosted runners |
| S2 | What does a fork merge request pipeline do under the project's settings? | forks cannot pull the toolchain image or run privileged jobs |
| S3 | Can a rule evaluator resolve the job list for fixture scenarios offline, including `rules:changes` and labels? | no: selection moves to a tested script that generates a child pipeline |
| S4 | Native arm64 build, manifest merge, registry cache hit rate | arm64 hosted runners are too slow or unavailable on the tier |
| S5 | macOS runner availability and cost on the tier | feeds D4 |
| S6 | Compute minutes for one full merge request pipeline and one nightly | feeds D1 |

Exit: the decisions in §8 are recorded, with an ADR for the ones that are
expensive to reverse (runner model and loopback approach, publishing
destinations and signing identity, gate model). Spike results are appended
here.

### Phase 1: provider-neutral tooling, on GitHub

1. Remove dead code: the unused composite action, `debug-oci.yml`,
   `dependabot.yml.disabled`, unused workflow inputs.
2. `tools/ci/` with the reporter, then `lane`, `results`, `secrets`,
   `wait-http`, `pin-ruby`, `services`, `e2e-env`.
3. `tools/oci/`, `tools/sentry/`, `tools/checks/`, in that order.
4. Fixes that belong to the code being moved, each verified first: `pnpm lint`
   runs ESLint with `--fix` (`package.json:57`), so fixable problems pass CI;
   the aggregate report fills its `file` field from the RSpec seed; shellcheck
   skips extensionless scripts such as `tests/lanes/run`; adr-lint runs in CI
   only when a PR touches `docs/adr/`.

Exit: everything the GitLab pipeline will call exists behind a `bin/`
command and is exercised by the GitHub workflows; every file left in
`.github/scripts/` is on the delete list; `bin/testsuite run` and GitHub CI
are green on `main`.

### Phase 2: GitLab foundation

Toolchain image and its guard; the root file with workflow rules, stages and
defaults; `lint.yml` and `frontend.yml`; project settings, variables and
environments; the Renovate runner project; retire the pilot job and
`ci/typescript-pilot/`.

Exit: 20 consecutive merge request pipelines green with results equal to the
matching GitHub jobs.

### Phase 3: test parity

`ruby.yml` with all lanes, selection rules and their tests, reports,
`images.yml`, `e2e.yml`.

Exit, measured on the same commits on both hosts:

- the selected job set matches for each fixture scenario;
- per lane, RSpec example counts are equal (the pilot's inventory comparison,
  applied per lane);
- no failure appears on one host only without an explanation;
- median wall time for a merge request pipeline is recorded against GitHub's.

### Phase 4: nightly, weekly, release

Schedules; Ruby preview; billing lanes; `smoke.yml`; `release.yml` with
publish, signing, Sentry, release creation, visual archive and API docs.

Exit: one manual pipeline publishes all three variants to the custom registry
only, as a rehearsal; then one release candidate tag is published from GitLab
with the GitHub publish workflow disabled for that tag.

### Phase 5: cutover

Enable "Pipelines must succeed" and, on Premium, merge trains. Activate the
schedules. Disable Actions in the GitHub repository settings and leave the
files in place. Switch Renovate. Add the templates and triage. Update
`.agents/skills/merge/SKILL.md` and the "Running tests" section of AGENTS.md,
which both name `.github/` paths.

Exit: one release shipped from GitLab. Until Phase 6, rollback is re-enabling
Actions.

### Phase 6: decommission and hardening

Delete `.github/workflows/`, `.github/actions/`, the delete-list scripts and
their suites. Rewrite `docs/development/auth-ci.md`, the "CI integration"
section of the lane spec, `tests/lanes/README.md`, CONTRIBUTING.md, the e2e
READMEs, `scripts/README.md` and `tools/testsuite/README.md`. Four tracked
documents contain invisible provenance markers that defeat literal search
(`scripts/README.md`, `tools/testsuite/README.md`, `tools/logship/README.md`,
`docs/development/frontend-diagnostics.md`); read them, do not grep them.
Port CI metrics. Turn the scanners into gates.

## 8. Decisions needed

| ID | Decision | Recommendation | What it changes |
|---|---|---|---|
| D1 | GitLab tier and runner fleet: hosted, self-hosted, or both | Start on hosted runners through Phase 3 to get real numbers from S6, then decide before Phase 5. Keep runner tags in variables. | cost; whether S1's daemon is needed; P2 |
| D2 | GitHub after cutover: read-only push mirror, or archive | Mirror | GHCR access, Dependabot, Codex, `FUNDING.yml`, existing links |
| D3 | Where images are published | Keep Docker Hub and GHCR. Use the GitLab registry for CI images, the toolchain image and visual baselines, not as an announced pull location. | P1; the `org.opencontainers.image.source` label; user docs |
| D4 | macOS coverage | GitLab hosted macOS if the tier allows it, since the two jobs run weekly and on a few paths. Otherwise keep them on the GitHub mirror for now. | D1, D2 |
| D5 | Merge trains on `main` and `develop` | Yes, if Premium | replaces the merge queue |
| D6 | Path-based labels | Drop | removes the labeler with no replacement |
| D7 | Release notes inventory (ADR-009) | Amend the ADR: scriv stays the narrative; the release job lists the milestone's merged merge requests | unblocks deleting `release-drafter.yml` |
| D8 | Which AI reviewers continue | Greptile through its GitLab integration; Claude review as a CI job on merge request open; defer `@claude` mentions | Codex and Copilot review end with GitHub |
| D9 | Translation request workflow | Retire. Re-specify on `locales/scripts` if it is still wanted. | removes 812 lines that cannot run against the current tree |
| D10 | CI metrics port before or after cutover | After | between Phase 5 and the port there is no per-job regression flag on merge requests. The tier budget check is advisory today (`fail-on-violation` is false). |
| D11 | Renovate hosting | Self-hosted runner project | works on any tier and serves every repository |
| D12 | Where issues live | Outside this plan; needed before triage is configured | §4.10 |
| D13 | GitLab for Open Source application | Check the profit clause first | cost factor and tier |

Two questions I could not answer from the repository:

- **Q1. Which host merges today?** The merge skill on `main` merges through
  GitLab and says mirroring is outside its workflow. The promotion PR (#4927)
  and Renovate run on GitHub. Phases 2 to 4 need the same commits on both
  hosts; the mechanism depends on the answer.
- **Q2. What is the branch model?** CONTRIBUTING.md says "Target the `main`
  branch." The pre-commit hook blocks commits to `develop` and `rel/*`, scriv
  lists `main, develop`, and workflow filters name `feature/*`, `fix/*`,
  `wip/*` and `rel/*`. `workflow:rules` and branch protection need one
  statement of which branches are protected and which get pipelines.

## 9. Risks

| ID | Risk | Check |
|---|---|---|
| R1 | The in-job Docker daemon is unproven on hosted runners. Docs confirm privileged mode, not this use. | S1 |
| R2 | Selection as `rules` is less tested than today's scripts until a rule evaluator is in place. | S3 |
| R3 | Compute cost exceeds the quota. | S6, D1 |
| R4 | `rules:changes` limits. I recall a cap of 50 patterns per `changes` section but did not confirm it; the auth list has 47. | confirm in Phase 2 |
| R5 | Fork contributors pay for their own pipelines and need the toolchain image to be public. | S2 |
| R6 | Docker Hub rate limits: PostgreSQL, RabbitMQ, Mailpit and Caddy images are pulled in every job that uses them. | Dependency Proxy, or copies in the project registry |
| R7 | The translation-rules action lives in another repository on its own migration schedule. | clone at the pinned ref until it is a component |
| R8 | Keyless signing must be defined in the project's own root file, per the docs. | reflected in §4.2 |
| R9 | The dependency caches were disabled for a reason that is not recorded. | Phase 2 |

## 10. Adjacent work, not in this plan

These are outside CI but several choices above depend on them:

- Import of issues, pull requests and releases. GitLab's importer does not
  import required status checks or outside collaborators.
- Product links to GitHub: four footer components link to
  `github.com/.../releases/tag/v<version>` and Vitest specs assert those URLs.
- 206 lines in 103 files reference `github.com/onetimesecret`, mostly issue
  and pull request links in comments and docs.
- `gh` usage in `locales/scripts/pr-per-locale.sh` and
  `scripts/corporate-branch-report.*`.
- The `add-msg-issue-prefix` commit hook assumes GitHub issue numbers.
- Git-sourced gems and the pre-commit hook repositories fetched from
  github.com.
- The other repositories being moved. The toolchain image pattern, the
  Renovate runner and the triage policies are candidates for a shared
  component project once a second repository needs them.

## Appendix A. Findings ledger

Four delegated read-only inventories produced the findings below. IDs: `A`
core CI, `B` build, release and install (the inventory's own `S` numbers, no
`S11`), `C` e2e, visual, migrations and Ruby preview (`F` numbers), `D`
hygiene and automation (`H` numbers, plus `D-A1` to `D-A6` for security
gaps). The `A` numbers were assigned here, in the order that inventory listed
its findings; the others are the inventories' own. Findings marked "inferred"
in the inventories were not observed.

Dispositions: **Design** means the target design removes it. **Phase 1**
means fix while moving the code. **Kept** means the behavior is ported
unchanged. **Open** means this plan does not fix it and it remains as
described.

| IDs | Finding | Disposition |
|---|---|---|
| A1, A27, C-F9, D-H3, D-H4, D-H6 | Toolchain setup repeated per job, with version skew and padded timeouts | Design §4.3 |
| A2 | Node installed in Ruby jobs only for locale codegen | Design §4.3; switching lanes to the Python codegen token is a lane change, Open |
| A3 | Dependency caches disabled with `DEBUG` notes | Design §4.3, R9 |
| A4, C-F19 | `generate-test-secrets` runs where it has no effect and prints the values | Phase 1 |
| A5 | Smoke test repeats unit and simple-integration work | Kept; lane content is lane policy (C3) |
| A6, B-S4, B-S10, C-F7, C-F8 | Image and frontend built several times per change | Design §4.6 |
| A7, A9, A13, A20 to A24, A33, C-F2, C-F22 to C-F25, D-H20 | Verdict jobs, change-detection jobs and the workarounds around them | Design §4.4, §4.5 |
| A8, A10, A18, A28 to A31 | CI metrics: stale lists, name-based tiers, unpaginated comment lookup, never gates | Phase 6 port (D10) |
| A11, B-S16, C-F21 | Stale docs and comments | Phase 6 docs |
| A12 | README says CI never runs `--only`; the API schema check does | Open; whether it becomes a lane is for the lane owners |
| A14 | Hash-mismatch probe runs outside the lane runner, non-blocking | Not ported unless its owner asks |
| A15, B-S12 | `download-frontend-assets` output wiring (inferred) | Design; action deleted |
| A16 | No-op `continue-on-error`; report-only i18n audit step | Kept as a non-blocking job |
| A17 | tmate wired for two lanes only | Design §4.7; lost |
| A19 | Commit flags do not act on pull requests (inferred) | Design §4.4 |
| A25, C-F29 | `services:` exception and host-published Valkey for container jobs | Design §4.3, §4.6 |
| A26 | `sysctl vm.overcommit_memory=1` on the runner | Kept in `bin/ci services`; confirm in S1 |
| A32 | `pnpm lint` autofixes in CI | Phase 1 |
| A34 | Aggregate report `file` field filled from the seed | Phase 1 |
| A35 | Compose services depend on files mounted from the checkout | Design §4.3; S1 |
| A36, D-H16 | Suites that parse `.github/` text | §5 |
| A37, C-F30, B-S19 | Schedule collisions; nightly cancelled by a push (inferred) | Design §4.1, §4.3 |
| A38, D-H5, B-S22 | Tools fetched unpinned or pinned in two places | Design §4.3, §4.9 |
| B-S1, B-S3, D-H12 | Dead action, temporary workflow, dead config | Phase 1; `release-drafter.yml` waits for D7 |
| B-S2, C-F16 | Triggers and inputs that cannot fire or are never read | Design; not ported |
| B-S5 | Publish is not gated on a boot test | Design §4.6 |
| B-S6 | arm64 built under QEMU | Design §4.6 |
| B-S7, B-S8 | Tag logic edge cases; registry mode defaults repeated (inferred) | Phase 1, in `bin/oci plan` |
| B-S9 | Sentry scripts larger than the build, much of it GitHub output handling | Phase 1 reporter |
| B-S13 | Action inputs interpolated into shell | Design; replaced by commands that take arguments |
| B-S14 | "Verbatim" README smoke differs from the README | Phase 1: fix the label or the test |
| B-S15 | `seed-compose-env.sh` requires `GITHUB_ENV` | Phase 1 |
| B-S17 | Nightly image pushed with no change detection | Kept |
| B-S18 | Caddy compiled on every qualifying PR | Design; registry cache |
| B-S20 | ADR-009 names a system nothing runs; scriv resolves `0.0.0-rc0` | D7; the release job passes the version |
| B-S21 | Two image build paths | Open |
| C-F1, C-F3, C-F4, C-F5, C-F6 | Copied e2e skeleton, Ruby preview job bodies, repeated pins, two comment scripts, double uploads | Design §6.1, §4.7 |
| C-F10 | `bin/visual` runs twice in `visual.yml` | Open |
| C-F11, C-F12, C-F14, C-F15 | Retries with a flaky gate, single worker, rate limiter off, shared `SECRET` | Kept |
| C-F13 | Sleep-poll readiness loops copied four times | Phase 1, `bin/ci wait-http` |
| C-F17, C-F18 | `e2e/full-billing` and dormant auth specs run nowhere; Firefox and WebKit projects commented out | Open; these are coverage gaps |
| C-F20 | `bin/setup` dev-lane work in e2e jobs | Kept |
| C-F26 | `ubuntu-26.04` chosen for podman | Design; the image defines the runtime |
| C-F27, C-F28, D-H7, D-H19 | Fork comment failure (inferred), broad token permissions, missing timeouts | Design §4.7, §4.11, defaults |
| D-H1, D-H2 | Two derive runs; `validate-config` repeats the guards | Design §6.1 |
| D-H8 | Translation request workflow stale | D9 |
| D-H9 | `bump diff` masks errors; secrets on fork PRs (inferred) | Design §6.1, §4.11 |
| D-H10, D-H11 | Claude workflow trigger noise and constraints | D8 |
| D-H13 | Checks in both hooks and CI; pre-commit unpinned in CI | Kept; pinned in the toolchain image |
| D-H14, D-H15 | adr-lint has no full CI run; shellcheck skips extensionless scripts | Phase 1 |
| D-H17 | `check-ci-secrets.sh` parses GitHub syntax | Rewritten for GitLab variables in Phase 2 |
| D-H18 | No single statement of the branch model | Q2 |
| D-A1 to D-A6 | No JavaScript audit, SAST, secret scanning, image scanning, license check or SBOM | §4.8; license checks Open |

## Appendix B. GitLab facts relied on

Retrieved from docs.gitlab.com, about.gitlab.com, code.claude.com and the
Renovate and Mend docs on 2026-11-10 by a delegated research pass. Quoted
wording in this plan comes from that pass; re-read the source before acting
on a tier, limit or maturity statement.

| Fact | Source |
|---|---|
| GitLab 19.5 is current | docs.gitlab.com/releases/19/ |
| Hosted Linux runner sizes, tags and privileged mode | docs.gitlab.com/ci/runners/hosted_runners/linux/ |
| Compute quotas and cost factors; 3 hour job limit | about.gitlab.com/pricing/, docs.gitlab.com/ci/pipelines/compute_minutes/ |
| Open Source program terms | about.gitlab.com/solutions/open-source/join/ |
| Mergeability is per pipeline; skipped pipelines block | docs.gitlab.com/user/project/merge_requests/auto_merge/ |
| Merged results and merge trains are Premium and Ultimate | docs.gitlab.com/ci/pipelines/merge_request_pipelines/ |
| Fork merge request pipelines run in the fork | same |
| Services use hostnames on the Docker executor; localhost only on Kubernetes | docs.gitlab.com/ci/services/ |
| Pipeline inputs: up to 20, root file only, not settable on merge request pipelines | docs.gitlab.com/ci/inputs/ |
| Lint simulation models a push to the default branch | docs.gitlab.com/ci/yaml/lint/ |
| Report types by tier; scanner results are JSON only below Ultimate | docs.gitlab.com/ci/yaml/artifacts_reports/, pricing page |
| Keyless signing on GitLab.com, all tiers | docs.gitlab.com/ci/yaml/signing_examples/ |
| `release:` requires `glab` | docs.gitlab.com/ci/yaml/#release |
| Push mirroring is Free; pull mirroring is Premium | docs.gitlab.com/user/project/repository/mirror/push/ |
| macOS hosted runners: Premium and Ultimate, beta | docs.gitlab.com/ci/runners/hosted_runners/ |
| Claude Code for GitLab CI/CD is beta, maintained by GitLab | code.claude.com/docs/en/gitlab-ci-cd |
| No job summary equivalent, no YAML issue forms, no native path labeler | not found in doc searches |
| GitHub Actions cannot run inside a GitLab job | docs.gitlab.com/ci/functions/ (experiment; the `action` step is no longer documented) |

Not confirmed: whether the `cache:key:files` limit of 10 is live on
GitLab.com (assume 2); the `rules:changes` pattern cap (R4); whether Mend's
hosted Renovate app accepts Free or program namespaces; whether Duo external
agents are enabled for program namespaces; that compose-published ports are
reachable at the `docker` hostname under a `docker:dind` service (follows
from the docs, not stated in them).
