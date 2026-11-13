# GitLab CI/CD migration plan

**Status (2026-11-12):** proposal. Nothing in this document is implemented.
Spikes S1 and S3 have first-pass results (§7, "Spike results").
Three decisions were made by the maintainer on 2026-11-10 and are recorded in
§8: runners are both hosted and self-hosted, GitHub is archived with a link
to GitLab, and v0.26.20 is the last release cut from GitHub.

**Evidence base:** `develop` at b8a13618 (2026-11-09) for the GitHub side,
`main` at 82cd4348 for the GitLab pilot, GitHub Actions run history read on
2026-11-10, and GitLab documentation retrieved on 2026-11-10 (GitLab 19.5),
with additions on 2026-11-11 that Appendix B marks.
Appendix B lists the GitLab facts this plan depends on and which of them were
not confirmed.

**Scope:** the 29 workflows in `.github/workflows/`, the composite actions and
scripts they call, and the repository automation configured under `.github/`.
Moving issues, pull request history and product links is adjacent work (§10).

**How statements are marked:** text in double quotes is exact wording from the
named file or page. "Proposal" marks a design choice made here. "Inferred"
marks a finding that was reasoned from the files and not observed; verify it
on the current baseline before applying a fix (AGENTS.md, "Security-posture
decisions"). The first draft was checked against the files by the same five
research passes that produced the inventory; this revision includes their
corrections.

Delete this document once Phase 6 is complete.

## 1. Summary

1. **One pipeline replaces 29 workflows.** A single GitLab pipeline definition,
   split across about ten include files, with pipeline types chosen by
   `workflow:rules`.
2. **Consolidate first, migrate second.** The CI logic in `.github/scripts/`
   and the shell embedded in workflows and composite actions moves into tool
   packages under `tools/` behind `bin/` entry points (ADR-042) while GitHub
   Actions is still the gate. The GitLab YAML then calls `bin/` commands and
   `tests/lanes/run`.
3. **Lanes do not change.** The lane spec requires loopback test endpoints, so
   GitLab's `services:` hostnames cannot serve them. Jobs that need services
   run a Docker daemon inside the job and use `compose.test.yml` as it is.
   GitLab does not document that arrangement; it is the first spike.
4. **The pipeline status is the gate.** GitLab decides mergeability per
   pipeline, and a job excluded by `rules` does not exist. The four verdict
   jobs, the four change-detection jobs and six of the eighteen
   `.github/scripts/` files are deleted and not ported.
5. **Less repeated work.** The runner-side frontend build happens once per
   pipeline and the `main` image once, where a pull request can build that
   image three times today. Publishing waits for the boot and e2e checks of
   the image it publishes; today it waits for nothing.
6. **New capabilities worth adopting:** merge trains, keyless image signing
   with SBOM and provenance, GitLab's SAST, secret detection and container
   scanning, test reports in the merge request, and a warning state for
   best-effort jobs. Native arm64 builds are possible only if the frontend
   stage is shared between architectures (§4.6).
7. **Compute is the main cost question.** GitHub Actions is free for this
   public repository. GitLab hosted runners are metered, and the current run
   volume is above the Premium quota on main CI alone. With heavy jobs on
   self-hosted runners, the metered share is the light jobs (§4.12).
8. **What is lost or changes:** job summaries, tmate debug sessions, the path
   labeler, picking up a `ci:auth` label by re-running an existing run, the
   time-to-first-test history, and, until it is ported, the CI metrics
   comment. macOS jobs need a decision.
9. **Seven phases, release path first.** Every release after v0.26.20 comes
   from GitLab, so the build and publish path is the first thing built there
   (Phase 2). A merge gate is needed as well before merges move (Phase 3).
   GitHub can be restored as the gate until it is archived, and with more
   work after that (Phase 5).

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
| Lines that write to `$GITHUB_STEP_SUMMARY` under `.github/` | 94 |

Facts that shape the design:

- No test job needs a stored secret. Lane jobs use the committed dummy values
  in `tests/lanes/base.env`; the e2e and container jobs generate random
  values in the job. Two pull request jobs do read stored credentials: the
  Bump.sh diff and the Claude review.
- Ruby tests enter through `tests/lanes/run`, with services from
  `compose.test.yml` on `127.0.0.1` ports. The exceptions are the devcontainer
  and macOS install jobs, which run the fast suite directly.
- `e2e-full-auth.yml`, `e2e-tenant-connect.yml` and `bin/visual` boot the app
  natively on the runner. `e2e.yml` runs the built image with `docker run`.
  All of them address the app and its services on loopback.
- The image workflow builds three variants (`main`, `-s6`, `-lite`) for
  `linux/amd64` and `linux/arm64` with QEMU on one runner and pushes to GHCR
  and Docker Hub, or to one custom registry. Names and tags come from
  `tags()` in `docker/bake.hcl`. There is no layer cache, signing, SBOM or
  image scan, and only `main` is ever booted by a test.
- Reviewers on pull requests: Renovate, Dependabot security updates, Greptile,
  Codex and Claude.
- `tools/testsuite/` tests the CI scripts offline. 14 of its 15 suites depend
  on paths under `.github/`: most read workflow or action text, and about five
  only execute a script by path.

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
is a GitHub Action. The same ADR says: "Domain labels (`frontend`, `backend`)
remain useful for PR filtering but no longer drive release note sections."
Both sentences need an amendment before the config and the labeler are
removed (D6, D7).

**C6. Selection policy.** `docs/development/auth-ci.md` describes which jobs
run on which event. It is a development guide, not an ADR. This plan keeps
the behavior it describes, with the changes named in §4.4, and rewrites the
guide at cutover.

**C7. Access changes need approval.** AGENTS.md: "Changes that widen access,
including on error paths, require explicit operator approval." §4.11 lists
the changes in this plan that fall under that rule.

**C8. Install lanes test the path from zero.** The fresh-clone, baremetal,
installer and devcontainer workflows exist to prove the documented setup
works on a machine that has nothing prepared. Their headers say so (for
example, fresh-clone asserts the fast suite is green with no frontend build
ever run). They cannot share the job template the other jobs use (§4.3).

## 4. Target design

Everything in this section is a proposal.

### 4.1 Pipeline types

| Type | Selected by | Runs |
|---|---|---|
| Merge request | `$CI_PIPELINE_SOURCE == "merge_request_event"` | always-on checks, plus jobs selected by path or label (§4.4); the full register scan when the source branch is `develop` and locale content changed |
| Merge train | `$CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"` | what `merge_group` runs today: all main CI jobs except billing, full-auth and tenant-connect e2e |
| `main` | push to `main` | the merge train set, static analysis, API docs deploy, register gates on locale changes |
| `develop` | push to `develop`, unless `develop` is the source of an open merge request | register gates on locale changes, as today |
| Tag | a pushed tag matching `v*` (`$CI_COMMIT_TAG`, source `push`) | the `main` set, billing, image build for release, container e2e, the `s6` and `lite` boot, publish, release |
| Nightly | schedule input `schedule: nightly` | the `main` set, billing, migrations, Ruby preview; on `main` also the nightly image, published after container e2e and the `s6` and `lite` boot |
| Weekly | schedule input `schedule: weekly` | install and boot lanes, published-image smoke, full register scan |
| Triage | schedule input `schedule: triage` | `gitlab-triage` |
| Manual | web or API with inputs, on a branch or a tag | selected by inputs |

Notes:

- Schedules select the type through a pipeline input, not a variable.
  Schedule variables are pipeline variables, and GitLab.com's default for new
  projects is to allow none; schedules accept inputs.
- Inputs live in the root file (`spec:inputs`, at most 20) and each needs a
  default, because merge request pipelines cannot set them. Proposed inputs:
  `schedule`, `run_all`, `publish` (`none`, `custom`, `public`),
  `platforms`, `version_tag`, `ruby_preview`, `rules_ref`, `debug`. A manual
  publish today defaults to the custom registry; `publish` keeps that choice
  explicit. `ruby_preview` is an on/off switch; the preview version is a
  literal in the job (§4.3).
- `workflow:rules` sets `RUN_ALL` and `NIGHTLY` per type so jobs test one
  variable. Using workflow variables in job rules is part of spike S3.
- One pipeline per push to `develop` while a promotion is open. A promotion
  merge request has `develop` as its source and stays open for days. If a
  push then created both a `develop` pipeline and a merge request pipeline,
  the merge check could read either one. GitLab says that with both present
  "the merge request pipelines are checked, not the branch pipelines.", and
  then: "These conditions are not enforced." and "A race condition
  determines which pipeline's result is used to either block or pass merge
  requests." A green two-job `develop` pipeline could pass a promotion whose
  own pipeline failed. The pilot's duplicate-pipeline rule is therefore
  kept, narrowed to `develop`:

  ```yaml
  - if: '$CI_PIPELINE_SOURCE == "push" && $CI_COMMIT_BRANCH == "develop" && $CI_OPEN_MERGE_REQUESTS'
    when: never
  ```

  GitLab defines `CI_OPEN_MERGE_REQUESTS` as the merge requests "that use the
  current branch and project as the merge request source."
- The work of the dropped pipeline moves into the merge request pipeline.
  When the source branch is `develop` and the merge request changes locale
  content or the gate's own files, the merge request pipeline runs the full
  register scan. `validate-register.yml:23` runs it "On push to
  main/develop" today, for pushes that touch those paths (`:60-64`). The
  full scan then gates the promotion. Today it reports on the `develop`
  commit, and the pull request runs the narrower scan of the locales it
  changed. The workflow header expects full scans to fail (§4.10), so D14
  has to be settled before the first promotion on GitLab.
- `main` is exempt from the rule. Its push pipeline is the test after a
  merge and the API docs deploy, and dropping it would lose both. A merge
  request with `main` as its source would have two pipelines and the race
  above, so a back-merge comes from a branch cut from `main`.
- Pushes create pipelines for `main`, `develop` and release tags only, as in
  the table. A topic branch gets its pipeline through its merge request,
  which matches GitHub today (`ci.yml` runs on pushes to `main` and tags, and
  on pull requests). The rule keeps its `"push"` condition, so it never
  drops a scheduled, manual or triggered pipeline.
- The rule does not drop a scheduled or manual pipeline on `develop`, and
  this plan proposes a nightly there. GitLab's source (19.5) counts
  scheduled and manual pipelines on the source branch among the pipelines
  that the merge check of a merge request can pick, and for one commit it
  picks a merge request pipeline ahead of any branch pipeline
  (`pipelines_for_merge_request_finder.rb`, `find_diff_head_pipeline` in
  `merge_request.rb`). So a nightly should not displace the promotion's own
  pipeline. That is read from source, not run, and GitLab's page above says
  the order is not enforced.
- GitLab has a project setting for the same problem, in beta since 19.2:
  "Skip branch pipelines for merge requests". With it on, "Mergeability
  checks, like Pipelines must succeed, only consider merge request
  pipelines. Branch pipelines do not affect merge readiness." The page
  names no exception for `main`, and says "Only push-triggered pipelines
  are affected." Spike S8 tests scheduled and manual pipelines with and
  without the setting. The rule above stays in both cases: it is reviewed
  with the code, and the setting is beta.
- Container e2e, visual and migration tests do not run on `main`, tag or
  merge-queue events today. Two additions are proposed: container e2e in
  every pipeline that publishes (tag, `main` nightly, manual publish),
  because publishing should wait for it (§4.6), and a nightly
  schedule on `develop`, because a change to shared code can break an
  auth-only job that its pull request did not select. The `develop` nightly
  builds the staging image that container validation needs (§4.6), as a
  merge request pipeline does. It does not build the release group and it
  publishes nothing: those jobs run on a pushed tag, on the `main` nightly
  and in a manual run with `publish` set, and it is none of the three.

### 4.2 File layout

```text
.gitlab-ci.yml          inputs, workflow rules, stages, defaults, includes,
                        and the signing job (id_tokens)
.gitlab/ci/
  rules.yml             path lists and rule fragments
  base.yml              job templates: images, caches, prepare, lane
  lint.yml              linters, hygiene, guards, audits, tooling tests
  frontend.yml          build, Vitest, type checks, i18n
  ruby.yml              lanes, host proxy wire, migrations, Ruby preview
  images.yml            toolchain image, OCI build, container validation
  e2e.yml               container e2e, full-auth, tenant-connect, visual
  smoke.yml             install and boot lanes
  release.yml           publish, Sentry, release, visual archive, API docs
  automation.yml        triage and review jobs
.gitlab/issue_templates/, .gitlab/merge_request_templates/
docker/ci/toolchain.dockerfile
tools/<domain>/ and bin/<domain>      (§5)
```

A `script:` entry is a single command. Anything with a branch, a loop or a
wait lives in a `bin/` command. During the dual run that keeps one
implementation under both hosts, and it keeps the logic under shellcheck and
`bin/testsuite`. Today actionlint runs shellcheck over workflow `run:` blocks
and two suites execute them; neither reads GitLab YAML.

Stages follow the existing tiers (lint and build, test, image, e2e, publish,
report) and jobs use `needs` so that tests start when lint and build finish,
as they do now.

### 4.3 Execution environment

**Toolchain image.** One Dockerfile, four stages, stored in the project
registry and referenced by digest as a literal in `base.yml`. GitLab advises
against image references built from variables: "When possible, avoid using
variables in container references as they can be modified to point to
malicious images."

| Stage | Contents | Used by |
|---|---|---|
| `runtime` | Ruby from `.ruby-version`, Node from `.node-version`, pnpm from `package.json`, Python, bash 5, git, curl, sudo, the Docker engine with compose and buildx | install lanes (C8) |
| `ci` | `runtime` plus uv, jq, a PostgreSQL client, shellcheck, actionlint (until Phase 6), pre-commit, `glab`, cosign, oras, `bump-cli`, and the small tools the scripts call (`lsof`, `shasum`, `openssl`, `bc`) | most jobs |
| `browsers` | `ci` plus the Playwright browsers, tied to `@playwright/test` | browser lane, native e2e |
| `review` | `ci` plus the Claude CLI at a pinned version | the Claude review job only (§4.11) |

- `runtime` replaces what `setup-ruby`, `setup-node`, `pnpm/action-setup` and
  `setup-python` provide. It has no project dependencies, caches or browsers.
- A guard job compares the pin files with the image and fails on drift. This
  extends `scripts/check-version-pins.sh`.
- The Ruby preview uses the same Dockerfile with another Ruby version. Its
  image is referenced by a digest literal like every other image; the rule
  quoted above has no exception. The preview Ruby version is a second literal
  next to it, passed to the pin step. The pin-file guard exempts that
  variant, and the preview job itself checks that the running Ruby is the
  requested version before it tests anything (§4.5).
- The logship tests run on two Python versions today; uv supplies the second.
- Lanes that need a Redis or Valkey binary on the host (baremetal boot, secret
  rotation) keep their own `apt` install step.

**Docker inside the job.** `bin/ci docker up` starts a Docker daemon inside
the job container when none is reachable. `bin/ci services up` then runs
`docker compose` with `compose.test.yml`, and with `compose.e2e.yml` for
Mailpit. Published ports are on the job's own `127.0.0.1`, bind mounts resolve
in the job's own filesystem, and `LANES_NO_AUTOSTART=1` works as it does
today. GitLab's docs confirm hosted Linux runners "are configured to run in
privileged mode to support Docker-in-Docker", but describe only the
`docker:dind` service, not a daemon in the job container. Spike S1 ran it
on `saas-linux-medium-amd64` for the `unit` and `full-pg` lanes (S1
results, §7). It works when the daemon's data root is off the job
container's root filesystem. The daemon is gone by `after_script`, so
service logs are collected in `script`, or by a daemon restarted in
`after_script` with the data root under `/builds`. The native e2e boot
and `bin/visual` have not been run this way.

Jobs that need the daemon but not the test services call only
`bin/ci docker up`: fresh-clone (which must show that `bin/setup --test`
starts the services itself), the compose smoke jobs, the clean-room matrix,
the bash 3.2 gate, the devcontainer job and `bin/visual`.

Alternatives considered:

- `services:` with hostnames. Rejected: it breaks C1 and moves image tags and
  service configuration out of `compose.test.yml`, which breaks C2.
- A `docker:dind` service with the test process in a second container on the
  daemon's host network. Untested. It would not serve `bin/visual`, which
  starts the server itself on loopback and bind-mounts the checkout.
- A self-hosted runner with the `instance` executor needs neither, because
  jobs run on the VM as they do on GitHub (§4.12, S7).

**Container jobs.** Container validation and container e2e run the app image
next to a Valkey container on a Docker network inside the job's daemon. They
cannot use `compose.test.yml`, which publishes on loopback only; its own
comment says so. `bin/oci smoke` owns that Valkey reference, which leaves two
pins (compose and container jobs) where there are five copies today.

**Job preparation.** `bin/ci prepare` does what the `setup-ruby-test-env`
action does beyond installing Ruby: seed `etc/` from `etc/defaults`, check
that the frontend artifact is present where a lane needs it, and run a frozen
`bundle install`. The native e2e and visual jobs use it in place of
`bin/setup`, because `bin/setup` runs `pnpm run clean`, which deletes the
frontend build they would receive as an artifact. `bin/setup` stays covered by
the install lanes.

**Caches and artifacts.**

- Bundler cache keyed on `Gemfile.lock` and the Ruby version, so the preview
  toolchain does not share gems with the default one. pnpm store keyed on
  `pnpm-lock.yaml`. Pre-commit environments. Consumers use `policy: pull`.
- Today the Bundler cache is on for lane jobs and off in the lint jobs; the
  pnpm store cache is off in the test workflows (`bump-api-docs.yml:95-101`
  still caches it). Both have the comment "disabled to rule
  out stale cache". The incident behind that is not recorded (R9).
- The frontend build, lane logs, RSpec results and reports stay artifacts with
  their current retention.
- Install lanes get no cache and no artifact, and nothing may be written into
  their checkout: fresh-clone ends by requiring a clean `git status`.

**Cancellation.** `interruptible: true` by default with
`workflow:auto_cancel:on_new_commit: interruptible` replaces the concurrency
groups. Schedule, tag and publish pipelines set `auto_cancel` to `none`
through `workflow:rules`. Today a push to `main` cancels a running nightly in
the same concurrency group (inferred), and the nightly is the only scheduled
run with billing coverage. GitLab's docs do not say whether a schedule
pipeline is cancelled by a later push; its source code indicates it is unless
the pipeline opts out.

**Runner tags** come from variables, so the fleet can change without editing
jobs (§4.12).

### 4.4 Selection

| Today | GitLab |
|---|---|
| `changes` job with `dorny/paths-filter` (`ruby`, `typescript`, `frontend`, `oci`, `harness`) | `rules:changes` fragments in `rules.yml`, shared with `!reference` |
| `.github/auth-paths.yml` (47 lines) and the `ci:auth` label read through the API | `rules:changes` plus `$CI_MERGE_REQUEST_LABELS =~ /ci:auth/` |
| `paths:` filters in `e2e.yml` (25 patterns), `visual.yml` (10), `migration-tests.yml` (9, plus a base-branch filter) and the install, docs and locale workflows | one `rules:changes` fragment each |
| `run_all` on push, schedule and merge queue, and on dispatch when its input is set | `RUN_ALL` from `workflow:rules:variables` and the `run_all` input |
| `billing_nightly` | `NIGHTLY`, set for schedule, tag and manual `run_all` |
| `[ci-all]` commit flag | label `ci:all` |
| `[ci-skip]` commit flag, which must not produce a passing verdict | GitLab's skip: `[skip ci]` in a commit message for push pipelines, in the merge request title for merge request pipelines. A skipped pipeline does not satisfy the gate (§4.5). |
| A change under `.github/workflows/**` or `.github/actions/**` forces every path-selected job; billing stays on the nightly, tags and a manual `run_all` | A change to `.gitlab-ci.yml`, `.gitlab/ci/**`, `docker/ci/**`, `tools/ci/**` or `bin/ci` does the same |
| The `oci` filter (`ci.yml:230-235`): `Dockerfile*`, `docker/**`, `scripts/entrypoint.sh`, `etc/**`, `config.ru` | the same list plus `tools/oci/**` and `bin/oci`; the container e2e fragment gets `tools/oci/**` (its list already has `bin/**`, `e2e.yml:126`) |

- In a merge request pipeline `rules:changes` compares against the target
  branch, which matches the documented policy that the detector evaluates the
  whole diff. In tag, schedule and manual pipelines it is always true, which
  matches run-everything on those events. `compare_to` is avoided; the docs
  call it unreliable with merged results pipelines and in forks.
- Limits: "A maximum of 50 patterns or file paths can be defined per
  rules:changes section." The auth list is 47 lines, four of which use brace
  alternation or character classes (`.github/auth-paths.yml:27`, `:28`, `:36`
  and `:87`), so it is split across rules. GitLab matches with Ruby's
  `File.fnmatch` and the extended-glob flag; all four match under that
  function (S3 results, §7). The fourth selects the auth lanes when a lane
  definition changes. If it stopped matching, nothing would fail.
- A pattern that ends in `/**` matches one directory level on GitLab, not
  the whole tree (S3 results, §7). 20 of the 47 patterns in the auth list
  end that way, `:28` and `:87` among them. Each becomes `/**/*` in the
  fragment. The same applies to every other path list that is ported.
- **Release tooling selects the image jobs.** The `test-docker-container`
  action, the tag logic and the post-push audit are under
  `.github/actions/` or inside a workflow file today, so a change to them
  forces every path-selected `ci.yml` job. Once they are in `tools/oci/` (§5)
  no pattern matches them, and a merge request that edits only that package
  would select no image job. `tools/oci/**` and `bin/oci` therefore join the
  `oci` fragment (image build, container validation). `tools/oci/**` also
  joins the container e2e fragment, which is ported from `e2e.yml`'s own
  list: those jobs take their Valkey reference from `bin/oci smoke` (§4.3).
- **The image jobs do not check the tag computation.** They build with
  development version arguments, and the publish workflow's `pull_request`
  trigger ignores every path, so the tag logic is first exercised by a tag,
  nightly or manual run. What checks it before a merge is the `tools/oci/`
  suite: `bin/oci plan` against fixture refs (release tag, prerelease,
  nightly, manual), in the shell test job. That job is always-on, as
  `static-analysis.yml` is on pull requests today. The `tools/sentry/` suite
  runs there too. No merge request job can exercise Sentry delivery; the
  manual `publish: custom` run is its end-to-end check (Phase 2).
- **Behavior change.** Today the label is read live, so re-running an
  existing run picks up a `ci:auth` label added later. On GitLab labels are
  read when the pipeline is created. Adding the label and choosing "Run
  pipeline" on the merge request creates a new pipeline that sees it; retrying
  jobs does not.
- The commit flags are replaced by labels because they appear not to work on
  pull requests today (inferred: the detector reads the message of the
  synthetic merge commit).
- Deleted: `detect-ci-flags.sh`, `compute-path-filter-outputs.sh`,
  `compute-auth-selection.sh`, `read-pr-labels.sh`, the `detect-auth-changes`
  action, and the `changes` jobs in `ci.yml`, `e2e.yml`, `e2e-full-auth.yml`
  and `e2e-tenant-connect.yml`.

Testing: the selection scripts have offline suites today. Selection written as
`rules` needs tests that assert the resolved job list for fixture scenarios
(docs-only change, auth path, label, tag, schedule). GitLab's lint simulation
accepts a branch or tag but has no merge request, label or schedule context,
so this needs a third-party evaluator (S3). Until S3 passes, selection has
less test coverage than it has now (R2).

### 4.5 Gate

- Project settings: "Pipelines must succeed" on, "Skipped pipelines are
  considered successful" off.
- Every merge request pipeline has always-on jobs (lint, guards). GitLab:
  "A merge request with no pipelines at all is not considered to have a
  successful pipeline, and cannot merge."
- A job that depends on a job that may be absent uses `needs: optional: true`.
  This replaces the `always() && (success || skipped)` conditions that every
  downstream job has today.
- `allow_failure` is limited to four cases: the Ruby preview; Sentry
  delivery (§4.6); scanners during their baseline period; and a dedicated
  exit code for a notice that must not look green, such as a compose smoke
  that skipped a bring-up (§4.7). D14 can add one more with an end date:
  the register full scan, if it is confirmed that the scan fails today.
- The Ruby preview job allows one dedicated exit code and no other. GitLab:
  "The job is `allow_failure: true` for any of the listed exit codes, and
  `allow_failure` false for any other exit code." Exit code 1 cannot be the
  allowed one: the pin script exits 1 on failure
  (`.github/scripts/pin-ruby-version.sh:23`), and `tests/lanes/run` documents
  1 as "generic failure" and otherwise passes the task's status through, so
  a failed test is also 1. With 1 allowed, a job whose pin failed would show
  a warning without having tested the preview Ruby.
- `bin/ci ruby-preview` therefore pins, checks that the running Ruby is the
  requested version, and only after both succeed maps a failed install, a
  failed rubocop run or a failed lane to the dedicated code. Each of those
  is advisory today (`continue-on-error` on the step in
  `ruby-4-preview.yml`). A failed pin, the wrong Ruby, and the lane runner's
  own errors (its 64 to 78 range, for example 69 for an unavailable service)
  keep their codes and fail the pipeline. The dedicated code is outside 1
  and that range.
- A warning on the preview job cannot hide a harness fault in the nightly.
  After a successful pin and version check, any exit 1 maps to the warning,
  including one raised before an example runs, such as a rake `abort` when
  a lane selects no files (`lib/tasks/spec.rake:477`). A cause of that kind
  does not depend on the Ruby version, and the nightly pipeline runs the
  same ten lane and overlay pairs under the default Ruby, where exit 1
  fails the pipeline. The fault then shows on the twin job, whatever the
  preview job reports.
- Results are not inspected to decide the mapping. The preview jobs write
  no RSpec results, as today (`ruby-4-preview.yml:23`: "no RSpec JSON is
  written or uploaded"), so the report job does not count their suites with
  the main ones. A load error under the preview Ruby also reports zero
  examples and exits 1, and that is a failure the job exists to show as a
  warning. This is read from the locked rspec-core 4.0.0.beta1, not run: a
  load error sets `wants_to_quit`, and the runner then calls `exit_early`,
  which the source describes as "Reports a run that exited early without
  having run any examples." None of the ten preview lanes runs only
  tryouts: all run an RSpec leg, and four run tryouts as well.
- Two cases have no twin. The first is a defect in the preview image other
  than its Ruby version. The command runs `tests/lanes/run --list` before
  the lane, and that fails outside the mapped step when the image lacks the
  bash version the runner requires; `--list` checks nothing else. Another
  defect, such as a missing Node, fails inside the mapped step and shows as
  a warning. The second case is a manual run with only `ruby_preview` set:
  its warnings have to be read with the log. A failed install maps to the
  warning whatever its cause, as today.
- With Premium: merged results pipelines and merge trains replace the merge
  queue. GitLab enables merge trains per project, not per branch (D5).
- Deleted: `ci-verdict` and `ci-verdict.sh` with its suite, and the three e2e
  verdict jobs. The script states why it exists: "A required status check sees
  only one job's conclusion, and GitHub counts a skipped job as passing."

### 4.6 Frontend, images, release

**Frontend.** One `frontend:build` job per pipeline. Lanes, native e2e and
visual jobs take its artifact; today each of those workflows builds its own.
Two things do not take it: the install lanes (C8), and the image, which keeps
its own frontend stage so that it stays self-contained.

**Image build.**

- Merge request pipelines build the bake target `main` once, for
  `linux/amd64`, with the development version arguments the workflows use
  today (`ALLOW_DEV_VERSION=true`, `VERSION=ci-test`), and push it to the
  project registry. Container validation, the three container e2e lanes and
  the full-stack compose smoke pull it. The compose smoke re-tags it to the
  name its compose file expects.
- The staging reference is unique per pipeline, and consumers pull by
  digest. Today each job builds its own image and loads it into its own
  daemon (`main.tags=onetime-test` with `load: true`, `ci.yml:1158-1160`), so
  two runs cannot see each other's image. A shared staging tag would remove
  that isolation: with about 18 main CI runs a day, pipelines overlap, and a
  consumer could pull the other pipeline's image and pass on code that is
  not under review. The build job tags with `$CI_PIPELINE_ID` and exports
  the pushed digest through a dotenv report. Every consumer pulls
  `name@digest` and fails when the variable is empty. A registry cleanup
  policy removes the staging tags.
- Tag, `main` nightly and manual pipelines build the bake group `ci`
  (`main`, `s6`, `lite`) in one bake call, because `lite` is built from
  `main` and all three need the `base` target.
- The version is compiled into the image, so one digest has one version. The
  image that gets published is built in the pipeline that publishes it; an
  image built for the same commit in another pipeline cannot be promoted.
- `docker/bake.hcl` keeps ownership of image names and tags. `tags()` has two
  modes today; staging in the project registry needs a third mode or
  per-target overrides that take the per-pipeline tag, and the file needs
  cache and attestation settings.
  `bin/oci plan` computes only the version and tag values, which is what
  `build-and-publish-oci-images.yml:254-332` does inline. Three edge cases to
  check while porting (inferred): a prerelease tag without `-rc` gets
  `latest`; `next` has two meanings; a dispatch with `source_branch` can label
  one commit and build another. The unreachable branch-push rule in that
  range is dropped.
- A registry layer cache helps less than it might: the version rewrite
  changes `package.json` before `pnpm install`, and `COMMIT_HASH` is written
  before the frontend build. The Dockerfile has a build-argument path that
  leaves `package.json` alone; prefer it.

**Multi-arch.** Today one job builds both architectures under QEMU, and one
frontend build serves both because the frontend stages run on the build
platform. Native per-architecture jobs would compile the frontend once per
architecture. The Sentry step extracts the bundle from the amd64 image on the
premise that both images serve the same files, so two builds would leave
arm64 without matching sourcemaps (inferred). Proposal: move to native arm64
runners only if S4 shows the frontend stage can be built once and passed to
both architecture builds as a named context. Otherwise keep the single
multi-platform build and add the registry cache.

**Publish.** Three pipeline types publish, as today
(`build-and-publish-oci-images.yml:125-139`, `:400`): a tag, the `main`
nightly, and a manual run with `publish` set. The gate is the same in each.
`image:publish` needs container validation and container e2e from its own
pipeline, and a `bin/oci smoke` boot of `s6` and `lite`, which are published
today without ever being booted. Container e2e therefore runs in all three
(§4.1). Today the publish workflow and CI start independently, so `latest`
or `nightly` can be pushed while CI is failing.

The published image is the tested image. The build job pushes the group to
the project registry under the per-pipeline tag, the test jobs pull those
digests, and `image:publish` copies the same digests to the registries
selected by `publish`, under the tags that `bake.hcl` computes (read with
`bake --print`). It does not build again: a second build can resolve a
dependency or a base image differently, and its digest would be one that no
job booted. The Sentry job gets the same digest. To check in Phase 2: that
the copy keeps the SBOM and provenance attached to the image index. One
smaller fix belongs here: the post-push audit prints the expected and
actual versions without comparing them.

**Signing and attestation.** New. The publish job signs with cosign using a
GitLab ID token (available on GitLab.com on every tier) and attaches the
buildx SBOM and provenance. The signing identity is public interface once
published; document it in the release notes of the first signed release.

**Sentry.** Same steps, through `bin/sentry`. Three differences:

- The image digest is handed from the build job to the Sentry job as an
  artifact; today both run in one job.
- `set-commits --auto` needs full history (`GIT_DEPTH: 0`).
- The job exits non-zero when delivery is FAILED or BLOCKED and is marked
  `allow_failure`, so the pipeline shows a warning. The workflow header says
  of today's arrangement that the annotations and the summary table "are the
  signal, and the green check is not".

**Release.** A `release:` job (GitLab's `glab`-based keyword) creates the
release on a tag. No workflow creates a release today. The scriv section for
a version exists only after someone runs `scriv collect` and commits it
before tagging, and it is reStructuredText. The job fails if `CHANGELOG.rst`
has no section for the tag, and the release description links to it. The
product's footers link each version to a GitHub release page; they must point
at GitLab before the first release from GitLab.

**Visual archive.** Its trigger today is a published GitHub release. It
becomes a job in the tag pipeline after the release job. Its registry is part
of D3: the consumer commands in `bin/visual`, `e2e/visual/README.md` and the
workflow header name `ghcr.io`.

**Not touched:** the Gitolite and podman build path described by
`.oci-build.json`. It remains a second image build path.

### 4.7 Reporting

| Today | GitLab | Note |
|---|---|---|
| Job summaries | collapsible log sections and the reports below | I found no equivalent in GitLab's docs |
| RSpec JSON, aggregated into a unified report | JSON kept; `bin/ci results junit` converts it for `artifacts:reports:junit` | the lane runner refuses `SPEC_OPTS` formatters, so conversion happens in CI (C3) |
| Aggregate job with a hand-kept `needs` list and an artifact name pattern that excludes rubocop, run with `if: always()` (`ci.yml:1206`) | a report job in the last stage with `when: always`, which receives earlier jobs' artifacts without a list; test jobs upload their results with `artifacts:when: always` | The default is `on_success`, "Run the job only when no jobs in earlier stages fail.", which would drop the report from every pipeline that failed. RSpec results go in their own directory; the aggregate script would otherwise count `rubocop_results.json` as a suite |
| Vitest | JUnit reporter | the pilot does this |
| Playwright `github` reporter | JUnit, and the HTML report through `artifacts:expose_as` | reporter chosen by an environment variable, not by provider |
| Visual regression PR comment | pass or fail, with an `expose_as` link to the diff report | `bin/visual` does not pass `CI` into its container, so there is no JUnit |
| Migration results PR comment | JUnit for the two lane jobs | the concurrent-boot job writes to the job log only |
| CI metrics PR comment | ported in Phase 6 (D10) | a gap until then |
| Ruby 4 outcome table | warning state per job, with the failing step named in the log | script deleted |
| Notices in summaries (compose smoke skipped a bring-up, fresh-clone duration) | job log, or a warning exit code where it matters | |
| tmate debug session | none | GitLab: "Instance runners on GitLab.com do not provide an interactive web terminal." Lane log artifacts remain. |

The metrics port should take lane timings from the lane runner's own phase
timing line, which is provider-neutral, and job durations from GitLab's jobs
API. Today's version selects tiers and steps by display name and reads
per-step records that GitLab does not have. The comment logic in
`post-pr-metrics.cjs` is rewritten against GitLab's notes API.

Coverage is not reported today. `coverage_report` with Cobertura output would
add diff annotations; it is optional and not part of parity.

### 4.8 Security scanning and supply chain

| Area | Today | Proposal |
|---|---|---|
| Ruby dependencies | bundler-audit on every PR, with no ignore list by policy | keep as is |
| JavaScript dependencies | no audit in CI | add `osv-scanner` on `pnpm-lock.yaml`; re-record the advisories accepted in `pnpm-workspace.yaml` |
| SAST | CodeQL through GitHub's default setup, which has no workflow file: `Analyze` checks for Ruby, JavaScript and TypeScript, Python and Actions on pull requests | GitLab SAST. CodeQL ends with the archive; compare the two sets of findings before then |
| Secrets | `detect-private-key` hook only | GitLab pipeline secret detection |
| Container image | none | GitLab container scanning on the built image |
| CI config lint | actionlint with a baseline | pipeline creation validates the config; `glab ci lint` locally |
| Signing, SBOM, provenance | none | §4.6 |
| Pinning | actions by SHA, most images by digest | images by digest, components and includes by SHA |

The scanners are available on every tier, but on Free and Premium their
results are JSON artifacts only; showing findings in the merge request needs
Ultimate. Without Ultimate, add a ratchet in the style of the existing
shellcheck baseline for the new scanners only. They start non-blocking and
gate after their baseline is triaged (Phase 6).

### 4.9 Dependency updates

- Renovate continues. Host it as a scheduled pipeline in a separate project
  using `renovate-bot/renovate-runner`, with one bot account for every
  migrated repository (D11).
- Config changes: drop `helpers:pinGitHubActionDigests`; replace
  `vulnerabilityAlerts`, which depends on GitHub's alerts, with
  `osvVulnerabilityAlerts`; point the custom regex manager at the new YAML.
- Tool versions that no manager tracks today (shellcheck, actionlint, uv,
  bump-cli, bundler-audit) move into the toolchain Dockerfile where Renovate
  can see them.
- Dependabot security pull requests stop when GitHub stops being the source.
  The OSV alerts above cover that.
- Renovate has to be running on GitLab at cutover; the hosted GitHub app
  cannot open pull requests on an archived repository.
- Every Renovate merge request is a pipeline. The current settings
  (`prCreation: immediate`, 10 concurrent, 10 an hour) are a cost on metered
  runners; a schedule window and grouping reduce it.

### 4.10 Repository automation and review

- **Templates.** Issue forms become Markdown templates in
  `.gitlab/issue_templates/` (I found no YAML forms in GitLab's docs). The PR
  template becomes `.gitlab/merge_request_templates/Default.md`.
- **Stale and lock.** `gitlab-triage` policies on the triage schedule, with
  the current thresholds, the `Stale Boetticher` label and the exemption
  labels. Issues live on GitLab after the archive (§8).
- **Path labels.** Drop them (D6). No automation reads them: the labels that
  automation depends on (`ci:auth`, `claude-review`, `security`,
  `auto-update`, `dependencies`, the stale and issue-template labels) are set
  by other means. ADR-009 calls them useful for filtering, so the decision
  goes with the ADR amendment.
- **AI review.** Greptile has a GitLab integration and its settings in
  `.greptile/` do not name a host. Claude review can run as a CI job through
  the documented GitLab integration (beta, maintained by GitLab). The job
  is not a copy of that page's example. The example installs packages and
  the CLI in `before_script` of the job that reads the key, and runs
  `claude` with `--permission-mode acceptEdits` and with `Bash`, `Edit` and
  `Write` allowed. Here the CLI comes from the image (§4.11), and the job
  keeps today's review prompt and tool allowlist
  (`claude-code-review.yml:94`: an inline comment tool and three `gh pr`
  commands, which need GitLab equivalents). With unrestricted `Bash` the
  job could install packages while the credential is in its environment.
  Today's
  workflow also re-reviews when the `claude-review` label is added and skips
  bot authors, forks and locale-only changes; D8 decides which of that is
  kept. `@claude` mentions need a webhook listener or Duo external agents
  (Premium, enabled per customer). Codex and Copilot review are tied to
  GitHub and end with the archive.
- **Review rules.** `.github/copilot-instructions.md` contains review rules
  that AGENTS.md does not (what not to comment on, a cap per review). The
  Claude review prompt and `.greptile/rules.md` repeat parts of them. Put them
  in one place before deleting the file.
- **Register gates.** `validate-register` and `resolved-derive-gate` run the
  same derive action from `onetimesecret/translation-rules`, one with the
  authority lint off and one with it on. They stay two jobs with two verdicts
  and share a template; their inline shell moves behind a command. Both
  linters are called with `--format github` today; one has a text format, the
  other lives in the translation-rules repository and needs one. The
  action becomes a CI/CD component in that project when it moves; until then
  the jobs clone it at the pinned ref. The workflow header says full scans
  fail until existing findings in three locales are fixed (not verified). A
  failing full scan would turn `main` and weekly pipelines red, and block a
  promotion that changes locale content (§4.1, D14).

### 4.11 Secrets and access

- Test jobs run without stored credentials, which is what allows pipelines
  from forks and unprotected branches.
- Publish, Sentry and API docs deploy credentials become protected, masked
  and hidden variables scoped to an environment, readable only on protected
  refs. Environment scope on project variables is available on every tier.
- Protected variables and the protected runner both depend on the ref being
  protected. GitLab: protected variables are "available only to pipelines
  that run on protected branches or protected tags." A release tag is
  protected only when a protected tag rule matches it, so `v*` becomes a
  protected tag (Phase 2). Without that rule the publish job in a tag
  pipeline would wait for a runner that never takes it, or run without
  registry credentials. A manual publish has to start from a protected
  branch or tag for the same reason.
- Two jobs read credentials in merge request pipelines today: the Bump.sh
  diff and the Claude review. On GitLab only the Claude review does. Its
  variable cannot be protected, because merge request pipelines get
  protected variables only when the source and the target branch are both
  protected, and that setting is turned off here (Phase 2). It stays
  unavailable to fork pipelines, as now.
- The Bump.sh diff runs without a token. Today the diff job reads two:
  `BUMP_TOKEN`, which `bump-api-docs.yml:21` describes as a "hub token with
  deploy access", and `BUMP_INTERNAL_TOKEN` for the internal hub (`:245`).
  Each is also the token that its hub is deployed with (`:153`, `:184`).
  Bump.sh's CLI page: "While some commands don’t need any API token
  (preview or diff) you will need an access key if you want to interact
  with your Bump.sh documentation." and "From any two API documents or
  URLs, you can retrieve a comprehensive changelog of what has changed
  between them." The diff job therefore compares two generated documents
  per API, the one from the merge request and the one from its target
  branch, and declares no environment. The comparison base changes from
  the version deployed on Bump.sh to the target branch's source, at the
  cost of a second generator run in a job without credentials. Both tokens
  become protected and are read only by the deploy job. All four documents
  are generated from this public repository, the internal one included.
- The Claude credential gets an environment scope of its own, and only the
  review job declares that environment, with `environment:action: access`.
  Without a scope it would be in every job of every merge request pipeline,
  including the jobs that install packages and run tests. GitLab: "By
  default, all CI/CD variables are available to all jobs in a pipeline."
  and "you should limit the environment scope of sensitive variables to
  only the jobs that require them." On GitHub the secret is passed to the
  step that uses it (`claude-code-review.yml:71`). On `access` jobs GitLab
  says: "This gives you access to environment-scoped variables, and can be
  used to protect builds from unauthorized access." The action creates no
  deployment.
- What the scope does not do: it decides which jobs receive the variable,
  not who can reach it. Anyone who can push a branch to the project can add
  that environment to a job in a merge request. GitLab: "Code pushed to the
  `.gitlab-ci.yml` file could compromise your variables." A workflow edit in
  a same-repository pull request gives the same reach today. The scope is a
  defense against code that other jobs run, such as a compromised
  dependency.
- A job that can read a credential does not run a package install, and this
  includes the Claude review job. The publish workflow installs Node
  dependencies before any registry login for this reason; its comment says
  "pnpm lifecycle scripts run arbitrary package code". On GitLab the install
  happens in a job without credentials and its output is passed on. The
  Bump.sh CLI and the Claude CLI come from the toolchain image at pinned
  versions; today the deploy and diff jobs install `bump-cli` with npm
  before the step that reads the token. The OpenAPI documents are generated
  in an earlier job without credentials, as now.
- The same two rules (own environment scope, no install) apply to any
  credential added to merge request pipelines later, such as a token for
  posting the CI metrics note (P3, D10).
- `SENTRY_PROJECTS` is a space-separated list. It is not a secret; store it
  unmasked. GitLab requires a masked value to "Be a single line with no
  spaces."
- Pipeline variables are restricted; manual and scheduled runs use inputs.
- The keyless signing job stays in this project's own configuration. GitLab:
  "The id_tokens portion of the CI/CD configuration file must be located in
  the project that is being built and signed. AutoDevOps, CI files included
  from another repository, and child pipelines are not supported."

Changes that widen access and need operator approval (C7):

| ID | Change | Why it widens |
|---|---|---|
| P1 | A stored token to push to GHCR | today the push uses the run's own short-lived token |
| P2 | Privileged job containers | on hosted runners each job has its own VM; on a self-hosted fleet this is root on the runner host |
| P3 | A bot token with API write for Renovate, triage and merge request notes | new long-lived credential |
| P4 | An automated push of `main` and tags to GitHub until the archive, if one is set up | needs a GitHub token with write access |
| P5 | "Run pipelines in the parent project" for fork merge requests | runs fork code with the parent's runners and variables; recommend disabling it |
| P6 | The Claude credential is visible to every command of its job in merge request pipelines. | today it is passed to one step; the environment scope limits it to one job, not to one step |

Additive, not widening: the ID token for keyless signing. Narrowing: the two
Bump.sh tokens leave merge request pipelines.

### 4.12 Runners and compute

- **Fleet (decided: both).** Proposed split: self-hosted runners on ephemeral
  VMs take the heavy jobs (lanes, e2e, image builds, install lanes). Jobs
  there can run on the VM as they do on GitHub, and they are not metered.
  Hosted runners take the light jobs (lint, guards, Vitest, scanners). Publish
  jobs run on a protected runner, which accepts jobs from protected refs
  only. `bin/ci docker up` does nothing where a daemon is already reachable,
  so one job definition serves both fleets. Spike S7 picks the executor.
- Self-hosted runners do not run fork code: fork pipelines run in the fork,
  and P5 stays disabled.
- GitHub's standard runner for public repositories has 4 vCPU (from memory,
  not re-checked). The matching GitLab hosted runner is
  `saas-linux-medium-amd64` (4 vCPU, 16 GB), cost factor 2. Small runners
  (2 vCPU, factor 1) suit the lint and guard jobs.
- Monthly quotas: 400 minutes on Free, 10,000 on Premium, 50,000 on Ultimate.
- Estimate: 18 main CI runs a day at about 40 job-minutes each on medium
  runners is on the order of 40,000 compute minutes a month for `ci.yml`
  alone. This is an upper-leaning estimate, because dependency-update PRs
  select fewer jobs and some runs are cancelled early. The other workflows add
  to it. The estimate assumes every job on hosted runners; with the split
  above, only the light jobs are metered. Spike S6 measures both.
- The GitLab for Open Source program grants Ultimate and lists a cost factor
  of 0.5 for public projects (the page does not say how that combines with
  runner size). Its terms say an organization "can't seek to make a profit by
  selling services, by charging for enhancements or add-ons, or by other
  means." Check eligibility before relying on it (D13).
- This design lowers consumption before any purchase: fewer image builds per
  change, one runner-side frontend build, no repeated toolchain setup, cached
  dependencies, and fewer Renovate pipelines.
- **macOS.** Two jobs need it (`installer.yml` `macos`, `drift-guards.yml`
  `envref-macos`). GitLab's hosted macOS runners are Premium and Ultimate
  only, in beta, with cost factor 6 or 12. A self-hosted macOS runner is the
  other option now that GitHub will be archived (D4).
- **Forks.** A fork's merge request pipeline runs in the fork, on the
  contributor's minutes, with the fork's variables. The toolchain image must
  be publicly readable for that to work.

## 5. Tool packages (ADR-042)

The consolidation happens in Phase 1, on GitHub, one domain per change. Each
change moves the code and its tests, adds the `bin/` shim, and switches the
GitHub workflows to the `bin/` command. Green GitHub CI is the evidence that
behavior is preserved. A file on the delete list in §6.3 is not moved; it
stays in `.github/scripts/` until the workflows that call it are removed.

Package names are proposals.

| Package | Entry point | Absorbs |
|---|---|---|
| `tools/ci/` | `bin/ci` | the `run-test-lane`, `setup-ruby-test-env`, `generate-test-secrets` and `wait-for-http-service` actions; `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh`; the inline e2e steps (container and server boot, per-lane environment, worker start and log gate, seed, log assertions, flaky gate, failure forensics); the migration concurrent-boot script; later, CI metrics |
| `tools/oci/` | `bin/oci` | `update-version.sh`, the `test-docker-container` action, the tag logic inlined in the publish workflow, the post-push audit |
| `tools/sentry/` | `bin/sentry` | `extract-frontend-dist.sh`, `sentry-sourcemap-preflight.sh`, `sentry-status.sh`, `sentry-verify-artifacts.sh`, and the inline release, upload and deploy steps with their three copies of `log_cli_output` |
| `tools/testsuite/` (exists) | `bin/testsuite` | its suites move to each package's `tests/` directory, which `bin/testsuite run` already discovers |
| `tools/testsuite-installer/` (exists) | `bin/testsuite-installer` | stays as it is, including `check-docs-commands` |
| `tools/host-seam/` (exists) | `bin/host-seam` | the Caddy fixture provisioning inlined in the `host-proxy-wire` job |

What each move has to handle:

- **One output layer.** `tools/ci/` provides a small reporter (notice,
  warning, error, group, summary, output, env export) that writes GitHub
  workflow commands under GitHub Actions, GitLab log sections and env files
  under GitLab CI, and plain text elsewhere. Scripts stop writing to
  `$GITHUB_OUTPUT`, `$GITHUB_ENV` and `$GITHUB_STEP_SUMMARY` directly. In the
  Sentry scripts this layer already exists once, in `sentry-status.sh`.
- **Composite actions stay as wrappers until Phase 6.** `bin/ci lane` is the
  logic of the `run-test-lane` action: the capture profile, the results path
  and the log paths. The action's tmate and artifact upload steps are `uses:`
  steps that a command cannot perform, so on GitHub the action remains a thin
  wrapper around the command at its 19 call sites.
- **GitHub's filters must move with the code.** Today a change under
  `.github/actions/**` forces every path-selected job, and `run-test-lane`
  is in the
  `harness` filter. No GitHub filter matches `tools/ci/**`. Without an update
  in the same change, a pull request that edits only `tools/ci/` would select
  no test job and pass. `ci.yml:189-190` and
  `tools/testsuite/api-v3-fresh-schemas-test.sh` name script paths that also
  change. The same applies to `tools/oci/**`: the `test-docker-container`
  action and the tag logic leave paths that force every path-selected job
  for a path that
  the `oci` filter (`ci.yml:230-235`) does not list. Add `tools/oci/**` and
  `bin/oci` to that filter, and `tools/oci/**` to `e2e.yml`'s path list, in
  the change that moves the code. The GitLab rules get the same entries
  (§4.4).
- **`bin/ci e2e`** writes the server, worker, seed and Playwright settings to
  one env file and runs the steps for a profile. Today `$GITHUB_ENV` is what
  keeps those processes on one configuration. `bin/ci wait-http` replaces the
  HTTP readiness loops; the Valkey wait, the worker-log gate and the loop
  inside `bin/visual` are separate cases. The flaky gate must run after a
  failed Playwright run, and logs must be collected after any failure; the
  command does the first, and `after_script` with `artifacts: when: always`
  does the second.
- **Smaller inline steps in `ci.yml`** also need a home: the i18n audit with
  its exit-status handling, the pre-commit hygiene run (which needs full
  history and the merge request's base and head SHAs), and the metrics
  outcome table.
- **Suites that move need more than a new directory.** They compute the
  repository root from their own depth, source `lib/assert.sh` by relative
  path, and two read fixtures beside them. Suites that only execute a script
  need a path change; suites that read workflow or action text are rewritten
  against the command, or deleted with the logic they test.
- **Shell lint.** `scripts/check-shell-lint.sh` names five `.github/scripts/`
  paths and the `tools/testsuite/` globs in its strict tier, and skips a glob
  with no match without a message. Update the list in the same commits as the
  moves, or the moved files fall to the lower lint floor silently.
- **`clean_databases.rb`** is called by `package.json` and the smoke lane, not
  by any workflow. Move it to `tests/lanes/support/`.
- **`seed-compose-env.sh`** aborts without `GITHUB_ENV`; give it the env file
  output. **`ttfhw-chart.sh`** reads its history from the GitHub Actions API
  and exits 0 on every degraded path, so on GitLab it would stop charting
  without failing. It needs a new data source, and its history starts over.
- **`scripts/README.md`** describes a `scripts/ci/` directory that does not
  exist on `develop`. Correct it in the first Phase 1 change.
- **`ci/typescript-pilot/`** (on `main`) sits outside the ADR-042 layout. Most
  of `run.py` installs and verifies Node, which the toolchain image makes
  unnecessary. Retire it when the `frontend.yml` jobs replace the pilot job.

**The guard scripts stay in `scripts/`.** `check-version-pins.sh`,
`check-env-reference.sh`, `check-ci-secrets.sh`, `check-shell-lint.sh` and
`adr-lint.rb` do not meet ADR-042's test for a tool package today: they share
no code, have no dependency metadata and no tests, and the ADR lets such
scripts remain. Moving them also breaks callers outside CI: the `bin/setup`
doctor checks for `scripts/check-version-pins.sh` and would drop the check
without a message, and `.oss-scanner/Dockerfile`, `docker/README.md`, the
pre-commit config and ADR-036 name these paths. If consolidating `scripts/`
is wanted anyway, do it as its own change with those callers, not as part of
this migration (D15). Two of them need work regardless:

- `check-ci-secrets.sh` keys on the `secrets.NAME` syntax in workflow files.
  GitLab has no such marker. It needs a new design in Phase 2; proposal: a
  manifest of credential variables with their purpose and environment,
  checked against what `tools/` reads.
- The envref ratchet behind `bin/envref check` needs full history and reads
  release tags from a remote hard-wired to the GitHub URL. At cutover that
  remote must point at the host that has the tags.

## 6. Disposition of every existing file

### 6.1 Workflows

| Workflow | Disposition |
|---|---|
| `ci.yml` | `lint.yml`, `frontend.yml`, `ruby.yml`, `images.yml`. `changes` and `ci-verdict` deleted. Aggregate becomes a report job. `host-proxy-wire` calls `bin/host-seam`, with Caddy pulled by digest. `ci-metrics` ported in Phase 6. The `i18n-validate` job keeps one report-only step and two blocking ones. |
| `static-analysis.yml` | `lint.yml`. actionlint dropped at Phase 6, with an edit to the lint script, which requires both tools today. |
| `drift-guards.yml` | one guard job in `lint.yml`, with full history. The macOS job follows D4. |
| `docs-command-drift.yml` | folded into the guard job, still calling `bin/testsuite-installer check-docs-commands`. |
| `validate-config.yml` | its three guards duplicate `drift-guards.yml`; its unique steps (schema generation, `bin/ots config validate`) become a job selected by path. It is dispatch-only today. |
| `validate-register.yml`, `resolved-derive-gate.yml` | two jobs with a shared template (§4.10). |
| `bump-api-docs.yml` | `release.yml`: generate, diff on merge requests, deploy on `main`. The deploy from `develop`, which only a manual dispatch reaches today (`bump-api-docs.yml:137`), is not ported. The diff compares two generated documents and reads no token (§4.11). Fix: each `bump diff` failure, including an auth or network error, is reported as "breaking changes" today. |
| `generate-translation-request.yml` | retire (D9). Its paths `src/locales` and `src/scripts/locales` do not exist in the tree. |
| `housekeeping-github-issues.yml`, `housekeeping-lock-threads.yml` | `gitlab-triage` (§4.10). |
| `pr-labeler.yml` | drop (D6). |
| `secret-rotation.yml` | `smoke.yml`. |
| `claude.yml`, `claude-code-review.yml` | D8. |
| `build-and-publish-oci-images.yml` | `images.yml` and `release.yml`. Its `pull_request` trigger ignores every path, so it cannot fire (inferred); it is not ported. Its version-pin gate before the build is kept. |
| `debug-oci.yml` | delete in Phase 1. Its header calls it temporary. |
| `compose-smoke.yml`, `baremetal-boot.yml`, `fresh-clone.yml`, `installer.yml`, `devcontainer-ci.yml` | `smoke.yml`, on the weekly schedule and on the same path triggers, on the `runtime` image with no cache or artifact (C8). The devcontainer job uses the devcontainer CLI. The `macos` job follows D4. |
| `e2e.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml` | `e2e.yml`, sharing one template. |
| `visual.yml` | `e2e.yml`. Valkey comes from `compose.test.yml` on port 2163, not from a service on 6379. |
| `visual-archive.yml` | `release.yml`, in the tag pipeline (§4.6). |
| `migration-tests.yml` | `ruby.yml`. The concurrent-boot job stays CI orchestration, as the lane spec describes it. |
| `ruby-4-preview.yml` | `ruby.yml`: its rubocop job and its ten SQLite lane runs use the same job templates as main CI with the preview image, except that they declare no results artifact (§4.5), on the nightly and through the `ruby_preview` input. Job bodies are not copied. |

### 6.2 Composite actions

| Action | Disposition |
|---|---|
| `build-and-publish-oci-image` | delete in Phase 1; no caller. |
| `check-ci-metrics` | port to `bin/ci metrics` in Phase 6. |
| `detect-auth-changes` | delete at Phase 6 (rules). |
| `download-frontend-assets` | delete at Phase 6 (artifacts through `needs`). |
| `generate-test-secrets` | `bin/ci secrets`; stop printing the values to the log. |
| `run-test-lane` | logic to `bin/ci lane`; the action stays a wrapper until Phase 6. |
| `setup-node-env` | delete at Phase 6 (toolchain image, cache). |
| `setup-ruby-test-env` | `bin/ci prepare`; delete at Phase 6. |
| `test-docker-container` | `bin/oci smoke`. |
| `wait-for-http-service` | `bin/ci wait-http`. |

### 6.3 `.github/scripts/`

| Script | Disposition |
|---|---|
| `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh` | move to `tools/ci/` |
| `update-version.sh` | move to `tools/oci/` |
| `extract-frontend-dist.sh`, `sentry-sourcemap-preflight.sh`, `sentry-status.sh`, `sentry-verify-artifacts.sh` | move to `tools/sentry/` |
| `clean_databases.rb` | move to `tests/lanes/support/` |
| `ci-metrics-breakdown.sh`, `post-pr-metrics.cjs` | stay until Phase 6, then replaced by the metrics port |
| `ci-verdict.sh`, `compute-auth-selection.sh`, `compute-path-filter-outputs.sh`, `detect-ci-flags.sh`, `read-pr-labels.sh`, `ruby4-step-outcomes.sh` | delete at Phase 6 |

### 6.4 Other files

| File | Disposition |
|---|---|
| `.github/renovate.json5` | move and adapt (§4.9) |
| `.github/auth-paths.yml` | becomes a fragment in `.gitlab/ci/rules.yml` |
| `.github/ISSUE_TEMPLATE/`, `pull_request_template.md` | `.gitlab/` templates |
| `.github/lint-baseline/shellcheck.tsv` | stays with the shell lint script; new location chosen at Phase 6 |
| `.github/lint-baseline/actionlint.tsv`, `actionlint.yaml` | delete at Phase 6 |
| `.github/labeler.yml` | delete (D6) |
| `.github/release-drafter.yml` | delete after the ADR-009 amendment (D7) |
| `.github/dependabot.yml.disabled` | delete in Phase 1 |
| `.github/copilot-instructions.md` | delete at Phase 6, after its rules have one home (§4.10) |
| `.github/FUNDING.yml`, `pr-assets/` | delete with the rest of `.github/` at Phase 6; the archived repository keeps its copy |
| `docker/bake.hcl` | gains a staging mode, cache and attestation settings (§4.6) |
| `scripts/ci-secrets-ignore.txt` | replaced with the guard's redesign (§5) |

### 6.5 Dependencies

- **Removed:** the 21 third-party actions, the cross-repository derive action
  (as an action), actionlint at Phase 6.
- **Added:** the toolchain image; `glab`; cosign; `gitlab-triage`; the
  devcontainer CLI; `osv-scanner`; the Claude CLI as a pinned install (the
  action bundles it today); GitLab's SAST, secret detection and
  container scanning; a self-hosted Renovate runner; a rule evaluator for
  tests if S3 selects one.
- **Changed:** Renovate config; Playwright reporters; `docker/bake.hcl`;
  `oras` moves from an action to the toolchain image, and `bump-cli` from an
  install step; `GITHUB_JOB` detection
  in `lib/onetime/application/auth_strategies/dev_worker_identity.rb` and
  `GITHUB_BASE_REF` in `tools/envref/` gain provider-neutral equivalents.

## 7. Phases

Implementation changes target `develop`. The pilot on `main` reaches
`develop` through the next `main` to `develop` sync; do that first.

v0.26.20 is the last release cut from GitHub (decided 2026-11-10; its release
prep is #4943). Every later release, starting with the v0.27.0 promotion
(#4927), is built and published from GitLab. Two things have to exist on
GitLab before that release: the build and publish path (Phase 2) and a merge
gate (Phase 3). The build workflows alone are not enough, because merges that
go through GitLab need tests in front of them. The order below puts the
release path first. Phases 1 to 3 overlap. Phase 4 can finish after cutover.

Do not change `build-and-publish-oci-images.yml` or the scripts it calls
until v0.26.20 is tagged and published.

### Phase 0: decisions and spikes

No change to CI behavior. Spikes run on a throwaway branch on GitLab.

| Spike | Question | Changes the plan if |
|---|---|---|
| S1 | Does a Docker daemon inside the job work on hosted runners? Cover: the `unit` and `full-pg` lanes; a native e2e boot with Chromium; `bin/visual` (host network, `/dev/shm`, bind mount); `host.docker.internal` to a sibling container; ports 80 and 443; `network_mode: service`; image builds; a non-root user with sudo; file ownership in the devcontainer job; MTU. Compare job times with GitHub. | it fails: hosted runners take only the light jobs, and the self-hosted fleet has no overflow |
| S2 | What does a fork merge request pipeline do under the project's settings? | forks cannot pull the toolchain image or run privileged jobs |
| S3 | Can a rule evaluator resolve the job list for fixture scenarios offline, including `rules:changes`, labels and workflow variables? Do the four brace and class patterns in the auth list match under `File.fnmatch`? | no: selection moves to a tested script that generates a child pipeline. The signing job would then stay in the parent pipeline. |
| S4 | Can the frontend stage be built once and passed to per-architecture builds? Registry cache hit rate. | no: keep the single multi-platform build |
| S5 | macOS: hosted runner availability and cost on the tier, or a self-hosted macOS runner | feeds D4 |
| S6 | Compute minutes for one full merge request pipeline and one nightly, in total and for the light jobs alone | feeds the tier decision |
| S7 | Which executor for the self-hosted fleet: `instance` on ephemeral VMs, or Docker with privileged containers? Do `compose.test.yml`, the native e2e boot and `bin/visual` run unchanged on it? | with `instance`, heavy jobs need no in-job daemon, and S1 only decides whether hosted runners can take overflow |
| S8 | With a merge request open from `develop`, which pipeline does the merge check read after a scheduled or manual pipeline runs on `develop`? Does "Skip branch pipelines for merge requests" (beta) change the answer, and does it keep creating push pipelines on `develop` once earlier promotions are merged or closed? | the merge request pipeline wins without the setting: keep the rule alone. The branch pipeline can win: turn the setting on if it leaves `develop` its push pipelines; otherwise pause the `develop` nightly while a promotion is open, or promote from a branch cut from `develop` |

Exit: the open decisions in §8 are recorded, with an ADR for the ones that
are expensive to reverse (runner model and loopback approach, publishing
destinations and signing identity, gate model). Spike results are appended
here.

#### Spike results

Evidence status per spike: "run" means observed in a GitLab.com pipeline,
"local" means run on a workstation and not on GitLab. S2 and S4 to S8 have
no result.

**S1, first pass (2026-11-12, run). The in-job daemon works on
`saas-linux-medium-amd64` for the `unit` and `full-pg` lanes when its data
root is off the job container's root filesystem.**

Runs: project 88480081 (`onetimesecret/onetimesecret-ci-pilot`), branch
`spike/s1-docker-in-job` at 78121fcdbe, pipelines 3062442077, 3062481694
and 3062500153. The branch changes `.gitlab-ci.yml` and adds
`ci/spike-s1/`; `compose.test.yml`, `tests/lanes/` and application code
are as on `main` at 82329178.

- **Data root.** With `/var/lib/docker` on the job container's overlay
  root filesystem the daemon is unusable, in two ways. The hosted runner
  exports `DOCKER_DRIVER=overlay2`, and with it `dockerd` exits: "failed to
  mount overlay: invalid argument" (job 17990498506). With the variable
  unset the daemon starts and the first image pull fails: "failed to
  convert whiteout file", "operation not permitted" (job 17990833961).
  Three data roots work: a directory under `/builds` (ext4), a tmpfs, and
  a volume declared by the job image, tried with `docker:29-dind` as the
  job image.
- **Services.** `docker compose -f compose.test.yml up --wait -d` starts
  all three. Ports 2163, 2154, 2156 and 12156 answer on the job's
  `127.0.0.1` and are bound to loopback only. Both bind mounts work: the
  init SQL created `onetime_user` and `onetime_migrator`, and the RabbitMQ
  management API answers (job 17990833958).
- **Lanes.** `LANES_NO_AUTOSTART=1 tests/lanes/run unit`: 17,004 examples,
  0 failures, in each of three runs. Lane time 198 s, 179 s and 182 s; job
  375 s with a cold bundle, 277 s and 282 s with the bundle cached.
  `full-pg`: 100 examples, 0 failures, lane 22 to 27 s, job 124 to 189 s.
  On GitHub, for the same commit, the unit lane step took 156 s and 175 s
  and the full-pg lane step 19 s (runs 43153452302 and 43124109841). The
  unit lane is about 13% slower on the GitLab medium runner.
- **After the script.** The job container is replaced between `script` and
  `after_script`; the daemon and its containers are gone in every job.
  With the data root under `/builds`, a daemon restarted in `after_script`
  finds the three containers exited and their logs readable. With a tmpfs
  data root it finds nothing.
- **Network.** The job's interface has MTU 1360; the daemon's bridge and
  the compose network default to 1500. Downloads of 4 to 34 MB inside
  containers completed at 1500 in two runs, which does not show that every
  path is safe. `--mtu 1360 --default-network-opt
  bridge=com.docker.network.driver.mtu=1360` on `dockerd` gives 1360 on
  the compose network with no change to `compose.test.yml`.
- **Probes, one job each, all passed.** `host.docker.internal` through
  `host-gateway`, from the default bridge and from a compose network;
  publishing on `127.0.0.1` ports 80 and 443; `network_mode: service:`;
  `docker buildx build` with the docker and docker-container drivers; the
  compose bring-up as a non-root user with sudo.
- **Other facts.** `sysctl -w vm.overcommit_memory=1` succeeds; the value
  was already 1, so a change taking effect was not observed (A26).
  `/dev/shm` is 64M in the job and in containers, and can be remounted to
  2G in the job. The job runs as root with 4 vCPU and 16 GB, cgroup v2.
- **Setup cost without a toolchain image, per job.** apt packages and the
  Docker engine about 20 s, Node, pnpm, uv and Python about 6 s, a cold
  `bundle install` 65 to 75 s (under 6 s from the cache), the test service
  image pulls 18 to 25 s.
- **What this changes.** Hosted runners can take the lane jobs, so they
  can serve as overflow for the self-hosted fleet. `bin/ci docker up` puts
  the data root off the root filesystem and does not depend on
  `DOCKER_DRIVER`. Service logs are collected in `script`, or the daemon
  is restarted in `after_script`. R8's MTU concern applies on amd64. Lane
  time is budgeted above GitHub's, not below.
- **Not covered.** The native e2e boot with Chromium, `bin/visual`, the
  devcontainer job, arm64, self-hosted runners, lanes as a non-root user,
  and Docker Hub pull limits under load. Read from the lane runner's
  environment scrub and not reproduced: the official Ruby image sets
  `GEM_HOME` and `BUNDLE_APP_CONFIG`, which `tests/lanes/run` clears; the
  spike used the checkout's `.bundle/config` with `vendor/bundle`.

**S3, first pass (2026-11-12). Evaluator: partly. Patterns: yes, with one
rewrite.**

- **Brace and class patterns (local, and run for two shapes).** Under
  `File.fnmatch` with `FNM_PATHNAME | FNM_DOTMATCH | FNM_EXTGLOB`, against
  the tracked files of `main` at 82329178, the four patterns match:
  `.github/auth-paths.yml:27` 710 files, `:28` 210, `:36` 17, `:87` 10.
  On GitLab.com, a push that changed only `lib/deep/dir/my_session_store.rb`
  and `tests/lanes/full-mfa/env` created the jobs guarded by
  `{apps,lib,etc,spec,src}/**/*{[Aa]uth,[Ss]ession,[Ss]so}*` and by
  `tests/lanes/{full-pg-agnostic,full-mfa}/**/*` (pipeline 3062408171 in
  project 88480081, branch `spike/s3-changes-glob`).
- **A trailing `/**` is one level deep (local and run).** `File.fnmatch`
  treats `**` as recursive only in the form `**/`. `apps/api/account/**`
  matches 4 of the 36 files under that directory; `apps/api/account/**/*`
  matches all 36. On GitLab.com, a push that changed only
  `apps/api/account/logic/nested.rb` created the job guarded by
  `apps/api/account/**/*` and not the one guarded by `apps/api/account/**`
  (pipeline 3062406862, same branch). In the auth list, 20 of 47 patterns
  end in `/**`; ported unchanged they would stop matching 925 file and
  pattern pairs, and no job would fail. `:28` is one of them: 210 files as
  written, 623 as `/**/*`. `:87` is another, with 10 files either way
  because the four lane directories have no subdirectories today.
- **Evaluator (local).** `glci show --json` resolved the job list for a
  fixture pipeline in each scenario tried: a merge request with a path
  change, a docs-only merge request, the same with
  `CI_MERGE_REQUEST_LABELS` set through `--env`, a branch, a tag, a pipeline
  input, and a variable set by `workflow:rules`. It needs no token.
- **The evaluator does not match globs the way GitLab does.** In the
  fixture, `glci` selected the job guarded by `apps/api/account/**` for a
  change two levels down. GitLab did not. A selection suite built on `glci`
  alone would pass a fragment that under-selects on GitLab.
- **What this changes.** Selection can stay in `rules`; no generated child
  pipeline is needed for the reasons S3 tests. The selection suite needs
  two parts: the fixture scenarios through the evaluator, and a check that
  runs every pattern in `rules.yml` through `File.fnmatch` with the flags
  above against fixture paths, and rejects a pattern that ends in `/**`.
- **Not covered.** The 50-pattern split, the 50,000-check limit (R4),
  `$CI_MERGE_REQUEST_LABELS` in a real merge request pipeline, and
  `rules:changes` in a merged results pipeline.

### Phase 1: provider-neutral tooling, on GitHub

1. After v0.26.20 is published: `tools/oci/`, then `tools/sentry/`, with the
   publish workflow switched to the commands. A manual run to the custom
   registry checks that behavior is preserved.
2. Remove dead code: the uncalled composite action, `debug-oci.yml`,
   `dependabot.yml.disabled`, the unread `environment` input of `e2e.yml`,
   the stale merge driver in `.gitattributes`, the reference to a
   nonexistent `bin/adr-lint`.
3. `tools/ci/` with the reporter, then `docker`, `services`, `prepare`,
   `lane`, `results`, `secrets`, `wait-http`, `pin-ruby`,
   `api-v3-fresh-schemas`, `e2e`. Update the GitHub path filters and the
   shell-lint strict list in each change.
4. Fixes that belong to the code being moved, each verified first:
   - `pnpm lint` runs ESLint with `--fix` (`package.json:57`), so fixable
     problems pass CI.
   - The aggregate report fills its `file` field from the RSpec seed.
   - shellcheck skips extensionless scripts such as `tests/lanes/run`.
   - adr-lint runs in CI only when a PR touches `docs/adr/`.
   - `generate-test-secrets` prints the generated values.

Exit: everything the GitLab pipeline will call exists behind a `bin/`
command and is exercised by the GitHub workflows; every file left in
`.github/scripts/` is on the delete list or waits for the metrics port;
`bin/testsuite run` and GitHub CI are green on `main`.

### Phase 2: GitLab foundation and the release path

- The toolchain image and its guard; the root file with inputs, workflow
  rules, stages and defaults; project settings, variables and environments; a
  protected runner for publish jobs; the redesigned credential guard.
- Protection settings (§4.11): `main` and `develop` as protected branches
  (who may push to them directly is part of Q2); `v*` as a protected tag
  that only maintainers can create; one environment per credential group,
  including one for the Claude credential alone.
- `develop` is protected for the merge gate, not for publishing. GitHub
  protects it today: its API lists `main` and `develop` as protected. The
  rules behind that are settings, not files, and were not read for this
  plan. "Pipelines must succeed" checks merge requests only, so a direct
  push to an unprotected `develop` would pass no gate. The publish path
  does not need the protection: the nightly image stays on the `main`
  schedule, where it runs today (GitHub runs scheduled workflows on the
  default branch, which is `main`), and the `develop` nightly publishes
  nothing (§4.1).
- What protecting `develop` costs: protection is one flag per branch, so
  every pipeline on `develop` can read protected variables and use the
  protected runner. Environment scope and job rules select the jobs that
  get the publish credentials; the people who can reach them are all who
  can push or merge to `develop`. A promotion merge request also has two
  protected branches, so the setting "Allow merge request pipelines to
  access protected variables and runners" is turned off. GitLab's page
  does not state its default. GitLab's source turns it on for every newly
  created project (`app/services/projects/create_service.rb`, 19.5), so
  expect it on.
- `images.yml` and `release.yml`: build, container validation, publish,
  Sentry, release creation, visual archive. Multi-arch stays one
  multi-platform build unless S4 has passed. Signing and attestation can
  follow the first release.
- Release prerequisites outside CI: the product's footer links point at
  GitLab release pages; the envref release remote points at GitLab; Sentry's
  repository integration, which `set-commits` relies on, points at GitLab;
  Renovate runs on GitLab.
- `lint.yml` and `frontend.yml`; retire the pilot job and
  `ci/typescript-pilot/`.

Exit:

- A manual pipeline with `publish: custom` pushes all three variants to the
  custom registry. Its `main` image is compared with the v0.26.20 image that
  GitHub built: labels, version, platforms and file list. The run starts
  from a protected branch, `develop` or `main`, because the publish job
  needs a protected ref. It does not start from a `v*` tag: pushing one
  starts the tag pipeline, which publishes a release.
- One release candidate tag is published from GitLab.
- 20 consecutive merge request pipelines are green for lint and frontend,
  with results equal to the matching GitHub jobs.

### Phase 3: the merge gate

`ruby.yml` with all lanes (billing on tags and the nightly), selection rules
and their tests, reports, migrations, and `e2e.yml` with container e2e,
full-auth and tenant-connect. `docs/development/auth-ci.md` asks for CI,
full-auth e2e and tenant-connect e2e to be green on a commit before it is
tagged.

Exit, measured on the same commits on both hosts:

- the selected job set matches for each fixture scenario, for the events on
  which each workflow runs today;
- per lane, RSpec example counts are equal (the pilot's inventory comparison,
  applied per lane);
- per Playwright suite, tests run and skipped are equal and the flaky gate
  gives the same result;
- no failure appears on one host only without an explanation;
- median wall time for a merge request pipeline is recorded against GitHub's.

If the next release cannot wait for this phase: keep pushing `main` and tags
to GitHub so that its workflows still test them. That is a weaker gate than
today's, because nothing beyond the GitLab jobs that already exist runs
before a merge, and GitHub cannot be archived while it is in use.

### Phase 4: the remaining jobs

The nightly schedule with the Ruby preview; the weekly schedule with
`smoke.yml`; visual regression; API docs; triage; review jobs; templates.

This phase can finish after cutover. Until it does, these are not covered:
the install and boot paths, visual regressions, Ruby preview, and the API
docs deploy.

### Phase 5: cutover

Prerequisites: Phases 2 and 3 have exited; issues, pull requests and releases
are imported, because an archived repository is read-only.

1. Enable "Pipelines must succeed" and, on Premium, merge trains. Activate
   the schedules. On GitHub, disable each workflow that runs on a schedule,
   publishes or deploys (`gh workflow disable`, which turns off every
   trigger of the workflow): the nightly would otherwise keep publishing
   the `nightly` image, and a `main` pushed there under P4 would deploy the
   API docs a second time. Stop merging on GitHub. Update
   `.agents/skills/merge/SKILL.md` and AGENTS.md ("Running tests" names
   `.github/scripts/` and the `Static analysis` workflow).
2. Ship one release from GitLab.
3. Archive GitHub: a last commit puts a notice with the GitLab link at the
   top of the README, the repository description gets the same link, Actions
   is disabled, and the repository is archived. GitHub's archiving page: "We
   recommend that you close all issues and pull requests, as well as update
   the README file and description, before you archive a repository." Record
   first what exists only as GitHub settings: the names of the Actions
   secrets and variables, the branch rules of `main` and `develop`, and the
   code scanning setup.

Until step 3, rollback is to resume merging and releasing on GitHub and to
enable those workflows again.

After step 3 rollback is still possible, at a cost that grows with every
merge on GitLab. Archiving is reversible: the same GitHub page documents
"Unarchiving a repository" from the repository settings, and the archived
copy keeps its workflow files. Recovery would be to unarchive, re-enable
Actions, push the commits and tags that went to GitLab since, and re-enable
the scheduled workflows. Its limits:

- Issues and merge requests created on GitLab after the import are not on
  GitHub.
- Releases and images published from GitLab in the meantime stay published.
- GitHub: "In a public repository, scheduled workflows are automatically
  disabled when no repository activity has occurred in 60 days." An
  archived repository takes no pushes, so expect GitHub to have disabled
  every scheduled workflow by itself once the archive is older than that.
  Each one is enabled again by hand: "Enable workflow" on its Actions page,
  or `gh workflow enable`. GitHub's pages do not define "repository
  activity".
- GitHub's archiving page does not say what happens to Actions secrets and
  variables; check the settings page after an unarchive.
- The Phase 2 changes that point at GitLab have to be reversed: the footer
  links, the envref release remote and Sentry's repository integration.
- After Phase 6 the GitLab history no longer contains `.github/`. Pushing it
  to GitHub removes the workflows there. They would have to be restored from
  the last GitHub commit and checked against the `bin/` commands as they are
  by then. Rollback is cheap only before Phase 6.

Archiving only after one release has shipped from GitLab (step 2) is this
plan's ordering, not a platform limit.

Exit: one release shipped from GitLab and the GitHub repository archived.

### Phase 6: decommission and hardening

- Delete `.github/` and the suites of the deleted scripts.
- Rewrite the documents that describe the GitHub setup:
  `docs/development/auth-ci.md`, `docs/development/README.md`, the "CI
  integration" section of the lane spec, `tests/lanes/README.md`,
  CONTRIBUTING.md, `e2e/README.md`, `e2e/system/README.md`,
  `e2e/visual/README.md`, `docs/architecture/build-architecture.md`,
  `docker/README.md`, `docker/s6/README.md`, `docker/variants/README.md`,
  `scripts/README.md`, and the READMEs under `tools/testsuite/`,
  `tools/testsuite-installer/` and `tools/envref/`. ADR-042's implementation
  notes name `actions/setup-python` and two workflows; add a note there.
- Four tracked documents contain invisible provenance markers that defeat
  literal search (`scripts/README.md`, `tools/testsuite/README.md`,
  `tools/logship/README.md`, `docs/development/frontend-diagnostics.md`);
  read them, do not grep them.
- Port CI metrics. Turn the scanners into gates. Add signing if it did not
  ship in Phase 2.

## 8. Decisions

### Decided on 2026-11-10 (maintainer)

- **Runner fleet:** both hosted and self-hosted. §4.12 proposes the split.
- **GitHub after cutover:** archived, with a link to GitLab. Consequences:
  rollback after the archive means unarchiving and resynchronizing, and it
  gets more expensive with every merge on GitLab (Phase 5); issues, pull
  requests and releases must be imported first; Dependabot, Codex and Copilot
  review end; the macOS jobs cannot stay on GitHub; GHCR becomes the one
  place that would keep GitHub as a live dependency (D3).
- **Release cutover:** v0.26.20 is the last release from GitHub. Every later
  release is built and published from GitLab (§7).

### Open

| ID | Decision | Recommendation | What it changes |
|---|---|---|---|
| D1 | GitLab tier | Decide after S6, together with D4 and D5, which both need Premium. | merge trains, macOS runners, quota for the light jobs |
| D3 | Where images and visual baselines are published | Docker Hub stays the documented location; the quick start and compose files already use it. Push to GHCR through the 0.27 series with a deprecation note, then stop. Move the visual baselines to the GitLab registry and update the three places that name `ghcr.io`. Use the GitLab registry for CI images and the toolchain image. | P1 for as long as GHCR is pushed; the `org.opencontainers.image.source` label; `.oci-build.json`; user docs |
| D4 | macOS coverage | A self-hosted macOS runner or GitLab's hosted one, whichever S5 favors. The two jobs run weekly and on a few paths. If neither, the bash 3.2 parse gate is what remains. | D1 |
| D5 | Merge trains | Yes, if Premium. The setting is per project. | replaces the merge queue |
| D6 | Path-based labels | Drop, with the ADR-009 amendment | removes the labeler with no replacement |
| D7 | Release notes inventory (ADR-009) | Amend the ADR: scriv stays the narrative; the release job lists the milestone's merged merge requests | unblocks deleting `release-drafter.yml` |
| D8 | Which AI reviewers continue, and with which triggers | Greptile through its GitLab integration; Claude review as a CI job on merge request open and on the `claude-review` label, with the current skips; defer `@claude` mentions | |
| D9 | Translation request workflow | Retire. Re-specify on `locales/scripts` if it is still wanted. | with its default input it resolves no locales (inferred), because its paths are gone |
| D10 | CI metrics port before or after cutover | After | between cutover and the port there is no per-job regression flag on merge requests. The tier budget check is advisory today (`fail-on-violation` is false). |
| D11 | Renovate hosting | Self-hosted runner project | works on any tier and serves every repository |
| D13 | GitLab for Open Source application | Check the profit clause first | cost factor and tier |
| D14 | Register full scans that are expected to fail | Verify the claim first. If true, mark the full-scan job `allow_failure` until the findings are fixed. | whether `main` and weekly pipelines are red from day one, and whether a promotion that changes locale content can merge; needed before the first promotion on GitLab |
| D15 | Guard scripts in `scripts/` | Leave them (§5) | scope of the ADR-042 consolidation |

D2 (GitHub's role) and D12 (where issues live) are settled by the archive
decision: issues live on GitLab.

One question I could not answer from the repository:

- **Q2. What is the branch model?** CONTRIBUTING.md says "Target the `main`
  branch." The pre-commit config names `develop` and `rel/.*` as branches not
  to commit to, scriv lists `main, develop`, and workflow filters name
  `feature/*`, `fix/*`, `wip/*` and `rel/*`. `workflow:rules` and branch
  protection need one statement of which branches are protected and which get
  pipelines.

Q1 asked whether changes merge through GitHub pull requests or GitLab merge
requests, because the merge skill on `main` uses GitLab while the promotion
PR and Renovate are on GitHub. The release cutover answers it: GitHub until
v0.26.20, GitLab after. Until GitHub is archived, commits still need to reach
both hosts for the parity checks in Phases 2 and 3.

## 9. Risks

| ID | Risk | Check |
|---|---|---|
| R1 | The in-job Docker daemon is not documented by GitLab. On hosted amd64 runners it ran the `unit` and `full-pg` lanes; the native e2e boot and `bin/visual` are unproven there. | S1: first pass run, the rest open |
| R2 | Selection as `rules` is less tested than today's scripts until a selection suite is in place. The evaluator is not enough by itself: it matches a trailing `/**` deeper than GitLab does. | S3: first pass done; the suite is open |
| R3 | Compute cost exceeds the quota. | S6, D1 |
| R4 | `rules:changes` allows 50 patterns per section and stops evaluating globs after 50,000 checks. GitLab: "After the 50,000th check, rules with patterned globs always match." The fallback selects the job; it does not drop it. | split lists; S3 |
| R5 | Fork contributors pay for their own pipelines and need the toolchain image to be public. | S2 |
| R6 | Docker Hub rate limits. Images pulled from Docker Hub in jobs include PostgreSQL, RabbitMQ, Mailpit, the Ruby and Node bases for every image build, and several in the install and smoke lanes. The Dependency Proxy is per group and I found nothing on its use from forks. | copies in the project registry for the frequent ones |
| R7 | The translation-rules action lives in another repository on its own migration schedule. | clone at the pinned ref until it is a component |
| R8 | A daemon in the job may need the MTU setting that GitLab documents for `docker:dind` on arm64, and a larger `/dev/shm` for Chromium. On hosted amd64 the job interface has MTU 1360 against the bridge's default of 1500, and `/dev/shm` is 64M. | S1: measured; Chromium not run |
| R9 | The dependency caches were disabled "to rule out stale cache"; the incident is not recorded. | Phase 2 |
| R10 | The Claude credential is readable in merge request pipelines by any job that declares its environment, and anyone who can push a branch can add that declaration. The people who can reach it are the same as today; inside the job the exposure is wider (P6). | its own environment scope, no installs in that job, today's tool allowlist (§4.10, §4.11). The Bump.sh tokens leave merge request pipelines. |
| R11 | Rolling back after the GitHub repository is archived means unarchiving it and resynchronizing commits and tags. Work tracked on GitLab since the import is not on GitHub. | archive only after a release has shipped from GitLab; record secret names before archiving (Phase 5) |
| R12 | The next release depends on the release path. If Phase 2 slips, the release waits. | start Phase 2 as soon as v0.26.20 is published |

## 10. Adjacent work, not in this plan

These are outside CI but several choices above depend on them:

- Import of issues, pull requests and releases. GitLab's importer does not
  import required status checks or outside collaborators. This is a
  prerequisite for archiving GitHub (Phase 5).
- Product links to GitHub: three footers and the admin layout link each
  version to `github.com/.../releases/tag/v<version>`, and Vitest specs assert
  those URLs. This one is a Phase 2 prerequisite.
- 204 lines in 102 tracked files outside `.github/` reference
  `github.com/onetimesecret`, mostly issue and pull request links in comments
  and docs.
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
its findings; the others are the inventories' own. Findings marked
"inferred" in the inventories were not observed.

Dispositions: **Design** means the target design removes it. **Phase 1**
means fix while moving the code. **Kept** means the behavior is ported
unchanged. **Open** means this plan does not fix it and it remains as
described.

| IDs | Finding | Disposition |
|---|---|---|
| A1, A27, D-H3, D-H4 | Toolchain setup repeated per job, with version skew and padded timeouts | Design §4.3 |
| A2 | Node installed in Ruby jobs only for locale codegen | Design §4.3. That every job regenerates locales is lane behavior: Kept. |
| A3, C-F9 | pnpm cache off everywhere, Bundler cache off in lint and native jobs, uncached installs | Design §4.3, R9 |
| A4, C-F19 | `generate-test-secrets` runs where it has no effect and prints the values | Phase 1 |
| A5 | Smoke test repeats unit and simple-integration work | Kept; lane content is lane policy (C3) |
| A6, B-S4, C-F7, C-F8 | Image and frontend built several times per change | Design §4.6. The image still compiles its own frontend: Kept. |
| B-S10 | Frontend built in the image, then pulled back out of the registry for Sentry | Kept |
| A7 | Job list kept by hand in six places | Design §4.5 for the three verdict lists, §4.7 for the three reporting lists |
| A9, A13, A20, A21, A22, A33, C-F2, C-F22, C-F23 | Verdict jobs, change-detection jobs, skip propagation, the live label read | Design §4.4, §4.5. The label read changes behavior (§4.4). |
| A23 | Artifact names sanitized; aggregate relies on a name pattern | Design §4.7 |
| A24 | Sparse checkouts in tail jobs (one verdict, two aggregate) | Design; a report job checks out normally |
| A8, A10, A18, A28, A29, A30, A31 | CI metrics: stale lists, name-based tiers and steps, unpaginated comment lookup, never gates | Phase 6 port (§4.7, D10) |
| A11, C-F21 | Stale docs and comments | Phase 6 docs |
| B-S16 | Stale docs and comments in `docker/`; `docker/s6/build.sh` cannot build (inferred); an unused `redis-server` install in fresh-clone | Phase 6 docs. The script: Open. The install step: decide when the lane is ported. |
| A12 | README says CI never runs `--only`; the API schema check does | Open; whether it becomes a lane is for the lane owners |
| A14 | Hash-mismatch probe runs outside the lane runner, non-blocking | Not ported unless its owner asks |
| A15, B-S12 | `download-frontend-assets` reads an output from the wrong step | Design; action deleted |
| A16 | A no-op `continue-on-error: false`; a report-only audit step in a blocking job | Kept as is; the no-op flag is dropped |
| A17 | tmate wired for two lanes only | Design §4.7; lost |
| A19 | Commit flags do not act on pull requests (inferred) | Design §4.4 |
| A25, C-F29, C-F4 | `services:` exception and host-published Valkey for container jobs; the Valkey pin copied five times | Design §4.3; two pins remain |
| A26 | `sysctl vm.overcommit_memory=1` on the runner | Kept in `bin/ci services`. S1: the write succeeds on hosted runners. |
| A32 | `pnpm lint` autofixes in CI | Phase 1 |
| A34 | Aggregate report `file` field filled from the seed; summed duration exceeds wall clock | Phase 1 for the field; the duration: Open |
| A35 | Compose services depend on files mounted from the checkout | Design §4.3. S1: both bind mounts work with the in-job daemon. |
| A36, D-H16 | Suites that depend on `.github/` paths | §5 |
| A37, C-F30, B-S19 | Schedule collisions; nightly cancelled by a push (inferred) | Design §4.1, §4.3 |
| A38, D-H5 | Tools fetched unpinned or pinned in two places | Design §4.3, §4.9; Caddy pulled by digest (§6.1) |
| B-S22 | Version literals copied by hand (pnpm, the Valkey digest) | Open; the toolchain image adds one more copy, covered by the pin guard |
| B-S1, B-S3 | Dead action, temporary workflow | Phase 1 |
| D-H12 | Dead config: Release Drafter, disabled Dependabot, stale `.gitattributes` driver, a documented `bin/adr-lint` that does not exist | Phase 1; `release-drafter.yml` waits for D7 |
| B-S2, C-F16 | Triggers and inputs that cannot fire or are never read; the unreachable branch-push tag rule | Design; not ported |
| B-S5 | Publish is not gated on a boot test; the audit never compares | Design §4.6 |
| B-S6 | arm64 built under QEMU | S4; Kept unless the frontend stage can be shared |
| B-S7 | Tag logic edge cases (inferred) | Phase 1, in `bin/oci plan` |
| B-S8 | Registry and platform defaults repeated; custom mode with an empty host (inferred) | Phase 1 for the defaults. The routing is in `bake.hcl`: fix with the staging mode (§4.6). |
| B-S9 | Sentry plumbing larger than the build; inline helper copied three times | Phase 1 |
| B-S13 | Action inputs interpolated into shell | Design; replaced by commands that take arguments |
| B-S14 | "Verbatim" README smoke differs from the README; the image pin parsed by three separate greps | Phase 1 for the label; the greps: Open |
| B-S15 | `seed-compose-env.sh` requires `GITHUB_ENV` | Phase 1 |
| B-S17 | Nightly image pushed with no change detection | Kept |
| B-S18 | Caddy compiled on every qualifying PR | Open; the registry cache on the bake build does not reach `docker compose build proxy` |
| B-S20 | ADR-009 names a system nothing runs; scriv resolves `0.0.0-rc0` | D7. The scriv version: Open; `scriv collect` runs by hand before the tag. |
| B-S21 | Two image build paths | Open |
| C-F1, C-F3, C-F5 | Copied e2e skeleton, Ruby preview job bodies, two comment scripts | Design §6.1, §4.7 |
| C-F6 | RSpec JSON uploaded twice | Design; artifacts are declared once in the lane template |
| C-F10 | `bin/visual` runs twice in `visual.yml` | Open |
| C-F11, C-F12, C-F14, C-F15 | Retries with a flaky gate, single worker, rate limiter off, shared `SECRET` | Kept |
| C-F13 | Readiness loops copied at six sites | Phase 1 for the HTTP ones (`bin/ci wait-http`); the others move into `bin/ci e2e` unchanged |
| C-F17 | `e2e/full-billing` and dormant auth specs run nowhere | Open; a coverage gap |
| C-F18 | Firefox and WebKit projects commented out; blob reporter output never collected | Open |
| C-F20 | `bin/setup` dev-lane work in e2e and visual jobs | Design §4.3 (`bin/ci prepare`) |
| C-F24 | Ruby 4 reporting script exists because `continue-on-error` reports success | Design §4.5 |
| C-F25 | `GITHUB_ENV` as the configuration bus | Phase 1, `bin/ci e2e` |
| C-F26, D-H6 | Runner labels mixed; `ubuntu-26.04` chosen for podman | Design; the image defines the runtime |
| C-F27, C-F28, D-H7 | Fork comment failure (inferred), broad token permissions, missing timeouts and concurrency | Design §4.7, §4.11, defaults |
| D-H19 | A mislabelled `process-only` comment; no top-level permissions block in four workflows | Design; workflows replaced |
| D-H1, D-H2 | Two derive runs; `validate-config` repeats the guards | D-H1: Kept as two jobs with a shared template (§4.10). D-H2: Design §6.1. |
| D-H8 | Translation request workflow stale | D9 |
| D-H9 | `bump diff` masks errors; credentials on pull requests | The masking: Design §6.1. The credentials: the Bump.sh tokens leave merge request pipelines, because the diff needs none; the Claude credential is kept with its own environment scope (§4.11, R10, P6). |
| D-H10, D-H11 | Claude workflow trigger noise and constraints | D8 |
| D-H13 | Checks in both hooks and CI; pre-commit unpinned in CI; pre-push hygiene hooks with no CI equivalent | Kept; pinned in the toolchain image. The pre-push hooks: Open. |
| D-H14, D-H15 | adr-lint has no full CI run; shellcheck skips extensionless scripts | Phase 1 |
| D-H17 | `check-ci-secrets.sh` parses GitHub syntax | Redesign in Phase 2 (§5) |
| D-H18 | No single statement of the branch model | Q2 |
| D-H20 | Workarounds: full fetch and an extra remote for envref, `PIPESTATUS` handling, injection guards, reliance on preinstalled tools | Preinstalled tools: Design §4.3. The envref remote and history: §5. The rest move with their scripts. |
| D-A1 to D-A6 | No JavaScript audit, SAST, secret scanning, image scanning, license check or SBOM | §4.8, §4.6; license checks Open. The SAST part of the finding is wrong: CodeQL runs today through GitHub's default setup (§4.8). |

## Appendix B. GitLab facts relied on

Retrieved from docs.gitlab.com, about.gitlab.com, code.claude.com and the
Renovate and Mend docs on 2026-11-10 by a delegated research pass, and
re-checked by the same pass against this document. Re-read the source before
acting on a tier, limit or maturity statement.

| Fact | Source |
|---|---|
| GitLab 19.5 is current | docs.gitlab.com/releases/19/ |
| Hosted Linux runner sizes, tags and privileged mode | docs.gitlab.com/ci/runners/hosted_runners/linux/ |
| 3 hour job limit on hosted runners | docs.gitlab.com/ci/runners/hosted_runners/ |
| Compute quotas and cost factors | about.gitlab.com/pricing/, docs.gitlab.com/ci/pipelines/compute_minutes/ |
| Open Source program terms | about.gitlab.com/solutions/open-source/join/ |
| Mergeability is per pipeline; skipped or absent pipelines block | docs.gitlab.com/user/project/merge_requests/auto_merge/ |
| Merged results and merge trains are Premium and Ultimate; merge trains are a project setting | docs.gitlab.com/ci/pipelines/merged_results_pipelines/, docs.gitlab.com/ci/pipelines/merge_trains/ |
| Fork merge request pipelines run in the fork | docs.gitlab.com/ci/pipelines/merge_request_pipelines/ |
| Services use hostnames on the Docker executor | docs.gitlab.com/ci/services/ |
| Shared localhost is documented for the Kubernetes executor | docs.gitlab.com/runner/executors/kubernetes/ |
| `rules:changes`: 50 patterns, 50,000 checks, `File.fnmatch`, comparison base per pipeline type | docs.gitlab.com/ci/yaml/#ruleschanges |
| `$CI_MERGE_REQUEST_LABELS` is available before the pipeline is created | docs.gitlab.com/ci/variables/predefined_variables/ |
| `workflow:rules:auto_cancel`; `needs:optional`; variables in `tags` | docs.gitlab.com/ci/yaml/ |
| Pipeline inputs: up to 20, root file, not settable on merge request pipelines; schedules accept inputs | docs.gitlab.com/ci/inputs/, docs.gitlab.com/ci/pipelines/schedules/ |
| Schedule variables are pipeline variables and can be disallowed | docs.gitlab.com/ci/variables/#restrict-pipeline-variables |
| Skip in the merge request title for merge request pipelines | docs.gitlab.com/ci/pipelines/ |
| Lint simulation accepts a branch or tag reference only | docs.gitlab.com/api/lint/, docs.gitlab.com/ci/yaml/lint/ |
| Report types by tier; scanner results are JSON only below Ultimate | docs.gitlab.com/ci/yaml/artifacts_reports/, pricing page |
| Keyless signing on GitLab.com, all tiers; `id_tokens` placement | docs.gitlab.com/ci/yaml/signing_examples/ |
| `release:` requires `glab` | docs.gitlab.com/ci/yaml/#release |
| Push mirroring is Free | docs.gitlab.com/user/project/repository/mirror/push/ |
| Pull mirroring is Premium and Ultimate | docs.gitlab.com/user/project/repository/mirror/pull/ |
| macOS hosted runners: Premium and Ultimate, beta | docs.gitlab.com/ci/runners/hosted_runners/macos/ |
| No interactive web terminal on GitLab.com instance runners | docs.gitlab.com/ci/interactive_web_terminal/ |
| Claude Code for GitLab CI/CD is beta, maintained by GitLab | code.claude.com/docs/en/gitlab-ci-cd |
| `CI_OPEN_MERGE_REQUESTS` lists merge requests that have the current branch as source | docs.gitlab.com/ci/variables/predefined_variables/ |
| The duplicate-pipeline rule and its `push` variant | docs.gitlab.com/ci/yaml/workflow/ |
| `allow_failure:exit_codes`; the job `when` default is `on_success` | docs.gitlab.com/ci/yaml/ |
| Variables reach every job by default; environment scope; `environment:action: access` | docs.gitlab.com/ci/environments/ |
| Protected variables on protected branches and tags; merge request pipelines get them only when source and target branch are both protected | docs.gitlab.com/ci/variables/, docs.gitlab.com/ci/pipelines/merge_request_pipelines/ |
| Protected runners | docs.gitlab.com/ci/runners/configure_runners/ |
| Wildcard protected tags such as `v*`, on every tier | docs.gitlab.com/user/project/protected_tags/ |
| Dotenv report variables reach later jobs, and only the jobs in `needs` when `needs` is used | docs.gitlab.com/ci/variables/dotenv_variables/ |
| With branch and merge request pipelines both present, the merge check reads the merge request pipelines; the page notes the check can race | docs.gitlab.com/ci/pipelines/mr_pipeline_troubleshooting/ |
| Registry cleanup policies: per project, every tier, by tag regex and age | docs.gitlab.com/user/packages/container_registry/reduce_container_registry_storage/ |
| The Claude Code example installs the CLI in the job that reads the key | code.claude.com/docs/en/gitlab-ci-cd |
| "Skip branch pipelines for merge requests": beta since 19.2; merge checks then read only merge request pipelines; only push pipelines are affected | docs.gitlab.com/ci/pipelines/settings/ |
| A masked value is a single line with no spaces | docs.gitlab.com/ci/variables/ |
| `bump diff` needs no token and compares two documents or URLs | docs.bump.sh/help/continuous-integration/cli/ |

The last fourteen rows were added on 2026-11-11 in response to review of the
pull request, and were read directly, not by the research pass. Five GitLab
statements were also read in the `19-5-stable-ee` branch of GitLab's
repository: the skip setting, the protected-resources section, the merge
check race, the masked value rule and the `cache:key:files` limit. The
GitHub statements in Phase 5 are from
docs.github.com/en/repositories/archiving-a-github-repository/archiving-repositories,
read the same day. The 60-day rule, and the fact that scheduled workflows
run on the default branch, are from
docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows,
also read on 2026-11-11. How to enable a disabled workflow is from
docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows.

Read from source, not from documentation, and not run. GitLab at
`19-5-stable-ee`: scheduled and manual pipelines are among the branch
pipelines that a merge check can pick, and a merge request pipeline for the
same commit is picked first
(`app/finders/ci/pipelines_for_merge_request_finder.rb`,
`app/models/merge_request.rb`, `app/models/ci/pipeline.rb`,
`app/models/concerns/enums/ci/pipeline.rb`); a new project gets the
protected-resources setting turned on
(`app/services/projects/create_service.rb`). rspec-core 4.0.0.beta1 as
installed: a load error ends the run with zero examples and the failure
exit code (`lib/rspec/core/runner.rb`, `reporter.rb`, `configuration.rb`).

GitHub settings that are not files were read through its API on 2026-11-11:
the branch list marks `main` and `develop` as protected, and the checks on
pull request 4944 include CodeQL's `Analyze` jobs. The branch rules
themselves were not read.

Absence findings, from doc searches that found nothing: a job summary
equivalent, YAML issue forms, a native path labeler, a release-drafter
equivalent, a daemon inside the job container on hosted runners, the
Dependency Proxy from forks. Running GitHub Actions inside a GitLab job is not
documented or supported in current docs.

Not confirmed: whether the `cache:key:files` limit of 10 is live on
GitLab.com (assume 2: the 19.5 docs put it behind the feature flag
`increase_ci_cache_key_files_limit`, "Disabled by default."); whether Mend's
hosted Renovate app accepts Free or program namespaces; whether Duo external
agents are enabled for program namespaces; whether Bump.sh's tokenless diff
limits document size or request rate; how "Skip branch pipelines for merge
requests" treats a long-lived source branch (S8); that a later push cancels
a scheduled pipeline (read from GitLab's source, not its docs).
