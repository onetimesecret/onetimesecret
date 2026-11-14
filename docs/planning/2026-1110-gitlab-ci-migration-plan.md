# GitLab CI/CD migration plan

**Status (2026-11-13):** proposal. The GitLab to GitHub push mirror and its
GitHub settings are in place (§2.4); nothing else in this document is
implemented. Spikes S1 and S3 have first-pass results (§7, "Spike results").
§8 records the maintainer's decisions. 2026-11-10: runners are both hosted
and self-hosted. 2026-11-13: development is on GitLab, release tags are
created there, and GitHub stays as a push mirror that keeps building and
publishing the Docker Hub and GHCR images. GitHub is not archived.

**Evidence base:** `develop` at b8a13618 (2026-11-09) for the GitHub side,
`main` at 82cd4348 for the GitLab pilot, GitHub Actions run history read on
2026-11-10, and GitLab documentation retrieved on 2026-11-10 (GitLab 19.5),
with additions on 2026-11-11 that Appendix B marks. The mirror configuration,
the GitHub settings and the workflow triggers in §2.4 are as of 2026-11-13.
Appendix B lists the GitLab facts this plan depends on and which of them were
not confirmed.

**Scope:** the 29 workflows in `.github/workflows/` at b8a13618, plus
`github-release.yml` (§2.4), the composite actions and scripts they call, and
the repository automation configured under `.github/`.
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

1. **One pipeline replaces most of the 29 workflows.** A single GitLab
   pipeline definition, split across about ten include files, with pipeline
   types chosen by `workflow:rules`. The image publisher, the visual archive,
   `github-release.yml` and, until its deploy moves, the API docs workflow
   stay on GitHub (§6.1).
2. **Consolidate first, migrate second.** The CI logic in `.github/scripts/`
   and the shell embedded in workflows and composite actions moves into tool
   packages under `tools/` behind `bin/` entry points (ADR-042) while GitHub
   Actions still runs them on the mirrored commits. The GitLab YAML then
   calls `bin/` commands and `tests/lanes/run`.
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
   image three times today. Publishing stays on GitHub and still waits for
   nothing; §4.6 proposes a gate in the GitHub publish workflow.
6. **New capabilities worth adopting:** merge trains, GitLab's SAST, secret
   detection and container scanning, test reports in the merge request, and
   a warning state for best-effort jobs. Keyless image signing with SBOM and
   provenance, and native arm64 builds, are questions for the GitHub publish
   workflow (§4.6).
7. **Compute is the main cost question.** GitHub Actions is free for this
   public repository, and the image builds and publishing stay there on that
   basis (decided 2026-11-13). GitLab hosted runners are metered, and the
   current run volume is above the Premium quota on main CI alone. With heavy
   jobs on self-hosted runners, the metered share is the light jobs (§4.12).
8. **What is lost or changes:** job summaries, tmate debug sessions, the path
   labeler, picking up a `ci:auth` label by re-running an existing run, the
   time-to-first-test history, and, until it is ported, the CI metrics
   comment. The macOS jobs can stay on GitHub's schedule (D4,
   recommendation).
9. **Seven phases; the release path is the mirror.** Release tags are created
   on GitLab, the push mirror delivers them to GitHub, and the existing
   GitHub image workflow publishes them (§2.4, §4.6). Development is on
   GitLab and GitLab has no merge gate yet (Phase 3). Until it has one, the
   GitHub runs on mirrored `main` and `develop` commits are the test signal,
   after the merge, and the workflows that run only on pull requests run
   nowhere (§2.4). GitHub is not archived, so its workflows can be enabled
   again at any point (Phase 5).

## 2. Where things stand

### 2.1 GitHub Actions today

The inventory below is `develop` at b8a13618. §2.4 describes what runs on
GitHub now that it is a push mirror.

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

- The project exists at `gitlab.com/onetimesecret/onetimesecret` (project id
  88874403). Development is there (§8). `main` and `develop` are protected
  branches, and `v*` is a protected tag that only Maintainers can create.
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

### 2.4 GitHub as a push mirror

Set up on 2026-11-13 after the maintainer's decision of that day (§8). These
are settings, not files, except where a file is named.

**The mirror.** GitLab push mirror 4157219 on project
`onetimesecret/onetimesecret` (id 88874403) pushes to
`ssh://git@github.com/onetimesecret/onetimesecret.git` with SSH public key
authentication. GitHub's host keys are pinned (ed25519 and ECDSA, from
`api.github.com/meta`). "Only mirror protected branches" and "Keep divergent
refs" are on, and the protected branches are `main` and `develop`. The first
sync succeeded at 2026-11-13T18:09:46Z: GitHub `develop` moved from
340473a80b to 03620959ca. GitLab's push mirror page: the mirror receives a
push "in five minutes, or one minute if the setting Only mirror protected
branches is on."

**What the mirror pushes.** Read from Gitaly's
`internal/gitaly/service/remote/update_remote_mirror.go` (`master`,
2026-11-13), not run:

- The protected-branch filter is a regular expression that begins
  `^refs/tags/.+$|^refs/heads/(` and continues with the branch patterns, so
  every tag is mirrored, not only `v*`.
- The push sets `Force: !firstRequest.GetKeepDivergentRefs()`. With "Keep
  divergent refs" on, the mirror never force-pushes.
- With "Keep divergent refs" on, the list of refs to delete is emptied, so
  the mirror deletes nothing on GitHub.

Consequences: a branch or tag deleted on GitLab stays on GitHub. A ref that
has diverged on GitHub makes the update fail; GitLab's page says "The update
is marked as failed." (R11, R13).

**GitHub settings.**

- Deploy key 169800417, with write access, is the mirror's public key.
  GitHub: "Deploy keys only grant access to a single repository."
- Ruleset 27221050, "GitLab mirror: main and develop", and ruleset 27221051,
  "GitLab mirror: release tags" (target tag, `refs/tags/v*`), each have the
  rules creation, update, deletion and non_fast_forward, and the deploy key
  (`DeployKey`) as the only bypass actor. Nobody can merge or push to
  `main` or `develop` on GitHub, or create, move or delete a `v*` tag there,
  except the mirror.
- The earlier rulesets are disabled, not deleted: "Default" (895349, on
  `main`: pull request, the required checks `notify-results` and
  `ci-verdict`, code scanning) and "Develop" (11465009: pull request,
  `Analyze (ruby)`, code scanning, code quality). Enabled again, they would
  reject the mirror's pushes, since the deploy key does not bypass them
  (inferred).
- Disabled with `gh workflow disable`: `claude.yml`,
  `claude-code-review.yml`, `pr-labeler.yml`,
  `housekeeping-github-issues.yml`, `housekeeping-lock-threads.yml`.
  Dependabot security updates are off. The repository description points to
  GitLab.
- Open for the operator: removing the Renovate GitHub app from the
  repository failed with HTTP 403. While it is installed it can still open
  pull requests on GitHub; those run the `pull_request` workflows and cannot
  be merged (inferred). Whether GitHub Issues are turned off is not decided.
  Turning them off hides the existing issue pages and breaks links to them;
  leaving them on lets people file issues there.

**On GitLab.** `v*` is a protected tag; only Maintainers can create one. A
`v*` tag reaches GitHub and publishes images tagged `latest` or `next`, so
creating that tag is the permission to publish (§4.11, P4).

**Files in the same merge request** (branch `ci/github-push-mirror` into
`develop`). They act on GitHub once merged and mirrored. `github-release.yml`
acts only once it is on `main`: GitHub's `workflow_run` event "will only
trigger a workflow run if the workflow file exists on the default branch."

- `.github/workflows/github-release.yml` (new). Trigger: completion of "Build
  and Publish OCI Images" for a `push` event with conclusion success, or a
  dispatch with a tag. It checks the tag format and that the tag still points
  at the commit the images were built from, and leaves an existing GitHub
  release unchanged. Otherwise it creates the GitHub release page. The
  page links to the GitLab release
  (`https://gitlab.com/onetimesecret/onetimesecret/-/releases/<tag>`) and to
  `CHANGELOG.rst` at the tag, and lists the image names. A tag that contains
  `-` is a prerelease and is not marked latest. It then dispatches
  `visual-archive.yml` at the tag, because a release created with
  `GITHUB_TOKEN` starts no `release: published` workflow. GitHub: "events
  triggered by the `GITHUB_TOKEN` will not create a new workflow run, with
  the following exceptions:", the first being "`workflow_dispatch` and
  `repository_dispatch` events always create workflow runs." When the
  existing release is the workflow's own, a re-run dispatches the archive
  again, so a failed dispatch is recovered by re-running the job.
- `visual-archive.yml`: a dispatch from a tag ref archives under the tag
  name; a dispatch from a branch archives as `sha-<short>`.
- `ci.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml`: the push trigger
  covers `main` and `develop`, and `v*` tags. Every mirrored `develop` commit
  gets a full post-merge run on GitHub until GitLab gates merges. On
  `develop` the concurrency group includes the commit SHA, so a later push
  does not cancel the run for an earlier one.
- A README notice and a contact link in `.github/ISSUE_TEMPLATE/config.yml`
  point to GitLab; a changelog fragment.

**What still runs on GitHub.** Read from the trigger blocks in
`.github/workflows/*.yml`, with the changes above. A push from the mirror
starts these like any other push; GitHub suppresses only events triggered by
`GITHUB_TOKEN` (not yet observed for a mirrored push, Appendix B). GitHub
runs schedules on the default branch, `main`.

| Trigger | Workflows |
|---|---|
| Push to `main` or `develop` | `ci.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml`; `resolved-derive-gate.yml` and `validate-register.yml` on their paths |
| Push to `main` only | `static-analysis.yml`; `bump-api-docs.yml` on its paths, which deploys the API docs |
| Push of a `v*` tag | `build-and-publish-oci-images.yml`, `ci.yml`, both e2e suites; then `github-release.yml`, which dispatches `visual-archive.yml` |
| Daily schedule | `ci.yml`, `build-and-publish-oci-images.yml` (the nightly image), `migration-tests.yml`, `ruby-4-preview.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml` |
| Weekly schedule | `compose-smoke.yml`, `devcontainer-ci.yml`, `fresh-clone.yml`, `installer.yml` (including its macOS job), `secret-rotation.yml`, `baremetal-boot.yml`, `validate-register.yml` |
| Dispatch | every workflow with a `workflow_dispatch` trigger that is not disabled |

**What runs nowhere.** No pull requests are opened on GitHub (the Renovate
app aside, above), so the workflows that have only `pull_request` and
dispatch triggers run nowhere, unless dispatched by hand, until GitLab has
their equivalents: `drift-guards.yml` (including its
`envref-macos` job), `docs-command-drift.yml`, `e2e.yml` (container e2e) and
`visual.yml`. The pull request runs of the other workflows stop as well:
path-selected runs of the install and smoke workflows and of
`migration-tests.yml`, the Bump.sh diff, `static-analysis.yml` on pull
requests (it still runs on pushes to `main`, not on `develop`), and the
register gates' pull request scans. The merge queue (`merge_group`) has
nothing to run. What remains is post-merge: the push and schedule runs in
the table above.

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
| Tag | a pushed tag matching `v*` (`$CI_COMMIT_TAG`, source `push`) | the `main` set, billing, the validation image build, container e2e, the GitLab release (§4.6). It runs while GitHub publishes the same tag and does not gate that publish. |
| Nightly | schedule input `schedule: nightly` | the `main` set, billing, migrations, Ruby preview; on `main` also container e2e. GitHub's own schedule builds and publishes the nightly image (§4.6). |
| Weekly | schedule input `schedule: weekly` | install and boot lanes, published-image smoke, full register scan |
| Triage | schedule input `schedule: triage` | `gitlab-triage` |
| Manual | web or API with inputs, on a branch or a tag | selected by inputs |

Notes:

- Schedules select the type through a pipeline input, not a variable.
  Schedule variables are pipeline variables, and GitLab.com's default for new
  projects is to allow none; schedules accept inputs.
- Inputs live in the root file (`spec:inputs`, at most 20) and each needs a
  default, because merge request pipelines cannot set them. Proposed inputs:
  `schedule`, `run_all`, `ruby_preview`, `rules_ref`, `debug`. A manual
  publish stays a dispatch of the GitHub workflow (§4.6), so there is no
  `publish`, `platforms` or `version_tag` input. `ruby_preview` is an on/off
  switch; the preview version is a literal in the job (§4.3).
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
  which matches GitHub (`ci.yml` runs on pushes to `main`, `develop` and
  tags, §2.4, and on pull requests). The rule keeps its `"push"` condition, so it never
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
  GitLab tag pipelines and the `main` nightly, which tests the commits that
  GitHub publishes from but does not gate the publish (§4.6), and a nightly
  schedule on `develop`, because a change to shared code can break an
  auth-only job that its pull request did not select. The `develop` nightly
  builds the staging image that container validation needs (§4.6), as a
  merge request pipeline does. It publishes nothing; no GitLab pipeline
  does (§4.6).

### 4.2 File layout

```text
.gitlab-ci.yml          inputs, workflow rules, stages, defaults, includes
.gitlab/ci/
  rules.yml             path lists and rule fragments
  base.yml              job templates: images, caches, prepare, lane
  lint.yml              linters, hygiene, guards, audits, tooling tests
  frontend.yml          build, Vitest, type checks, i18n
  ruby.yml              lanes, host proxy wire, migrations, Ruby preview
  images.yml            toolchain image, OCI build for testing, container
                        validation
  e2e.yml               container e2e, full-auth, tenant-connect, visual
  smoke.yml             install and boot lanes
  release.yml           GitLab release, API docs diff, and the API docs
                        deploy once it moves from GitHub (§6.1)
.github/workflows/      the publisher, the GitHub release page and the
                        visual archive stay on GitHub (§4.6, §6)
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

Stages follow the existing tiers (lint and build, test, image, e2e, release,
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
| `ci` | `runtime` plus uv, jq, a PostgreSQL client, shellcheck, actionlint (for the workflows that stay on GitHub), pre-commit, `glab`, `bump-cli`, and the small tools the scripts call (`lsof`, `shasum`, `openssl`, `bc`) | most jobs |
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
groups. Schedule and tag pipelines set `auto_cancel` to `none` through
`workflow:rules`. Today a push to `main` cancels a running nightly in
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
  action is under `.github/actions/` today, so a change to it forces every
  path-selected `ci.yml` job. Once it is in `tools/oci/` (§5) no pattern
  matches it, and a merge request that edits only that package would select
  no image job. `tools/oci/**` and `bin/oci` therefore join the
  `oci` fragment (image build, container validation). `tools/oci/**` also
  joins the container e2e fragment, which is ported from `e2e.yml`'s own
  list: those jobs take their Valkey reference from `bin/oci smoke` (§4.3).
- **The tag computation stays on GitHub.** It is inline in the publish
  workflow (`build-and-publish-oci-images.yml:254-332`), whose
  `pull_request` trigger ignores every path, so the tag logic is first
  exercised by a tag, nightly or manual run, as today. No GitLab job
  computes publish tags, and the GitLab image jobs build with development
  version arguments. Testing the tag logic against fixture refs would need
  it moved out of the workflow file; that is a proposal for the GitHub
  workflow, outside this migration. Sentry delivery likewise runs only in
  the GitHub publish workflow.
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
- `allow_failure` is limited to three cases: the Ruby preview; scanners
  during their baseline period; and a dedicated exit code for a notice that
  must not look green, such as a compose smoke that skipped a bring-up
  (§4.7). Sentry delivery stays in the GitHub publish workflow (§4.6). D14
  can add one more with an end date: the register full scan, if it is
  confirmed that the scan fails today.
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

**Image build.** GitHub's `build-and-publish-oci-images.yml` stays the
publisher (decided 2026-11-13, §8): on a pushed `v*` tag, on its nightly
schedule on `main`, and on manual dispatch, as today. GitLab builds images
only to test them, in the project registry. It pushes nothing to Docker Hub
or GHCR.

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
- GitLab tag pipelines and the `main` nightly build the same `main` target
  for container e2e (§4.1). Only the GitHub workflow builds the bake group
  `ci` (`main`, `s6`, `lite`), in one bake call, because `lite` is built
  from `main` and all three need the `base` target.
- The version is compiled into the image, so one digest has one version. The
  image that GitHub publishes is built in the GitHub run that publishes it.
  An image that GitLab built for the same commit carries the development
  version arguments and cannot be promoted.
- `docker/bake.hcl` keeps ownership of image names and tags. `tags()` has two
  modes today; staging in the project registry needs a third mode or
  per-target overrides that take the per-pipeline tag. The file needs cache
  settings, and attestation settings if the GitHub workflow adopts the
  signing proposal below.
- The version and tag values stay computed inline in the GitHub workflow
  (`build-and-publish-oci-images.yml:254-332`). Three edge cases to check
  there (inferred): a prerelease tag without `-rc` gets `latest`; `next` has
  two meanings; a dispatch with `source_branch` can label one commit and
  build another. The range also has an unreachable branch-push rule. These
  are fixes to the GitHub workflow, outside this migration.
- A registry layer cache helps less than it might: the version rewrite
  changes `package.json` before `pnpm install`, and `COMMIT_HASH` is written
  before the frontend build. The Dockerfile has a build-argument path that
  leaves `package.json` alone; prefer it.

**Multi-arch.** The published images are built on GitHub as today: one job
builds both architectures under QEMU, and one frontend build serves both
because the frontend stages run on the build platform. The Sentry step
extracts the bundle from the amd64 image on the premise that both images
serve the same files, so per-architecture builds would leave arm64 without
matching sourcemaps unless the frontend stage is shared (inferred). Native
arm64 builds are a question for the GitHub workflow, not for this migration.
GitLab builds `linux/amd64` only, for testing, with the registry cache.

**Publish.** The GitHub workflow publishes in three cases, as today
(`build-and-publish-oci-images.yml:125-139`, `:400`): a pushed `v*` tag, the
nightly schedule (on `main`), and a manual dispatch. A release tag is created
on GitLab and reaches GitHub through the push mirror (§2.4). The publish
workflow and CI start independently, so `latest` or `nightly` can be pushed
while CI is failing, and `s6` and `lite` are published without ever being
booted. That does not change: the GitLab tag pipeline runs while GitHub
publishes and does not gate it.

Proposal, for the GitHub workflow or a follow-up: make the push wait for a
boot test of the images it pushes, and publish the digests that were booted,
not a second build. A second build can resolve a dependency or a base image
differently, and its digest would be one that no job booted. How to arrange
that inside the GitHub workflow is not designed here. If it copies digests
from a staging tag, check that the copy keeps the SBOM and provenance
attached to the image index. One smaller fix belongs here: the post-push
audit prints the expected and actual versions without comparing them.

**Signing and attestation.** Proposal, for the GitHub publish workflow and
outside this migration: sign with cosign keyless, using GitHub's OIDC token
(not a GitLab ID token, since GitLab does not publish), and attach the
buildx SBOM and provenance. The signing identity is public interface once
published; document it in the release notes of the first signed release.

**Sentry.** Stays in the GitHub publish workflow, with its scripts in
`.github/scripts/` (§6.3), and runs as today. Sentry's repository
integration, which `set-commits` relies on, can stay on GitHub, because the
commits are mirrored there (inferred).

**Release.** Each release has two pages.

- The GitLab release is created on GitLab, by hand or by a future `release:`
  job in the tag pipeline (GitLab's `glab`-based keyword). The scriv section
  for a version exists only after someone runs `scriv collect` and commits it
  before tagging, and it is reStructuredText. Proposal for that job: it fails
  if `CHANGELOG.rst` has no section for the tag, and the release description
  links to it.
- The GitHub release page is created by `github-release.yml` after the
  images for the tag are published (§2.4). It links to the GitLab release
  and to `CHANGELOG.rst` at the tag. A GitHub release that already exists,
  such as one written by hand, is left as it is. Apart from that workflow,
  no workflow creates a release.

The product's footers link each version to a GitHub release page. They keep
working while `github-release.yml` creates those pages, and need no change.

**Visual archive.** Stays on GitHub and GHCR. Its `release: published`
trigger does not fire for a release created with `GITHUB_TOKEN`, so
`github-release.yml` dispatches it at the tag, and a dispatch from a tag ref
archives under the tag name (§2.4). The consumer commands in `bin/visual`,
`e2e/visual/README.md` and the workflow header keep naming `ghcr.io`.

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
| SAST | CodeQL through GitHub's default setup, which has no workflow file: `Analyze` checks for Ruby, JavaScript and TypeScript, Python and Actions on pull requests | GitLab SAST. CodeQL's pull request checks stop with the pull requests on GitHub; whether its default setup keeps scanning mirrored pushes was not checked. Compare the two sets of findings while both run |
| Secrets | `detect-private-key` hook only | GitLab pipeline secret detection |
| Container image | none | GitLab container scanning on the built image |
| CI config lint | actionlint with a baseline | pipeline creation validates the config; `glab ci lint` locally; actionlint stays for the workflows that remain on GitHub |
| Signing, SBOM, provenance | none | §4.6 |
| Pinning | actions by SHA, most images by digest | images by digest, components and includes by SHA |

The scanners are available on every tier, but on Free and Premium their
results are JSON artifacts only; showing findings in the merge request needs
Ultimate. Without Ultimate, add a ratchet in the style of the existing
shellcheck baseline for the new scanners only. They start non-blocking and
gate after their baseline is triaged (Phase 6).

### 4.9 Dependency updates

- Renovate continues, on GitLab. GitHub `main` and `develop` accept pushes
  only from the mirror (§2.4), so Renovate on GitHub cannot merge anything.
  Until Renovate runs on GitLab there are no dependency update merge
  requests. Host it as a scheduled pipeline in a separate project using
  `renovate-bot/renovate-runner`, with one bot account for every migrated
  repository (D11).
- Config changes: drop `helpers:pinGitHubActionDigests`; replace
  `vulnerabilityAlerts`, which depends on GitHub's alerts, with
  `osvVulnerabilityAlerts`; point the custom regex manager at the new YAML.
- Tool versions that no manager tracks today (shellcheck, actionlint, uv,
  bump-cli, bundler-audit) move into the toolchain Dockerfile where Renovate
  can see them.
- Dependabot security updates are off on GitHub (§2.4). The OSV alerts
  above replace them.
- The Renovate GitHub app is still installed on the repository; removing it
  failed with HTTP 403 and is left to the operator. Its pull requests cannot
  be merged (§2.4).
- Every Renovate merge request is a pipeline. The current settings
  (`prCreation: immediate`, 10 concurrent, 10 an hour) are a cost on metered
  runners; a schedule window and grouping reduce it.

### 4.10 Repository automation and review

- **Templates.** Issue forms become Markdown templates in
  `.gitlab/issue_templates/` (I found no YAML forms in GitLab's docs). The PR
  template becomes `.gitlab/merge_request_templates/Default.md`.
- **Stale and lock.** `gitlab-triage` policies on the triage schedule, with
  the current thresholds, the `Stale Boetticher` label and the exemption
  labels. Issues live on GitLab (§8). The two GitHub housekeeping workflows
  are disabled, and whether GitHub Issues are turned off is an open operator
  decision (§2.4).
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
  GitHub pull requests and stop with them. The two Claude workflows are
  disabled on GitHub (§2.4).
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
- The registry and Sentry credentials stay GitHub Actions secrets, read by
  the GitHub publish workflow. The API docs deploy credentials become
  protected, masked and hidden variables scoped to an environment, readable
  only on protected refs, once the deploy moves to GitLab (§6.1).
  Environment scope on project variables is available on every tier.
- Protected variables and the protected runner both depend on the ref being
  protected. GitLab: protected variables are "available only to pipelines
  that run on protected branches or protected tags." `main` and `develop`
  are protected branches, and `v*` is a protected tag that only Maintainers
  can create (§2.4). A `v*` tag reaches GitHub through the mirror and
  publishes images, so creating one is the permission to publish (P4).
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

Changes that widen access and need operator approval (C7):

| ID | Change | Why it widens |
|---|---|---|
| P1 | A stored token to push to GHCR | Not needed: GHCR pushes stay in the GitHub workflow with the run's own short-lived token (decided 2026-11-13) |
| P2 | Privileged job containers | on hosted runners each job has its own VM; on a self-hosted fleet this is root on the runner host |
| P3 | A bot token with API write for Renovate, triage and merge request notes | new long-lived credential |
| P4 | The permanent push mirror from GitLab to GitHub, set up on 2026-11-13 after the maintainer's decision (§2.4) | a deploy key with write access (169800417), scoped to this one repository; the rulesets let only that key push `main`, `develop` and `v*` tags. Who can publish: GitLab Maintainers, by creating a `v*` tag; and whoever can push or merge to GitLab `main`, which the GitHub nightly publishes from. GitHub users with write access can still dispatch the publish workflow. |
| P5 | "Run pipelines in the parent project" for fork merge requests | runs fork code with the parent's runners and variables; recommend disabling it |
| P6 | The Claude credential is visible to every command of its job in merge request pipelines. | today it is passed to one step; the environment scope limits it to one job, not to one step |

Additive, not widening: an OIDC token for keyless signing, if the GitHub
publish workflow adopts it (§4.6). Narrowing: the two Bump.sh tokens leave
merge request pipelines.

### 4.12 Runners and compute

- **Fleet (decided: both).** Proposed split: self-hosted runners on ephemeral
  VMs take the heavy jobs (lanes, e2e, image builds, install lanes). Jobs
  there can run on the VM as they do on GitHub, and they are not metered.
  Hosted runners take the light jobs (lint, guards, Vitest, scanners). Jobs
  that read deploy credentials run on a protected runner, which accepts jobs
  from protected refs only. `bin/ci docker up` does nothing where a daemon is already reachable,
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
  dependencies, and fewer Renovate pipelines. The multi-platform release and
  nightly image builds stay on GitHub's free minutes (§4.6).
- **macOS.** Two jobs need it (`installer.yml` `macos`, `drift-guards.yml`
  `envref-macos`). GitLab's hosted macOS runners are Premium and Ultimate
  only, in beta, with cost factor 6 or 12. GitHub is not archived, so the
  recommendation for D4 is to keep both jobs on GitHub's schedule.
  `installer.yml` `macos` already runs weekly. `envref-macos` has only pull
  request and dispatch triggers, so it runs nowhere now (§2.4); Proposal:
  give it a schedule on GitHub. The maintainer has not decided D4.
- **Forks.** A fork's merge request pipeline runs in the fork, on the
  contributor's minutes, with the fork's variables. The toolchain image must
  be publicly readable for that to work.

## 5. Tool packages (ADR-042)

The consolidation happens in Phase 1, on GitHub, one domain per change. Each
change moves the code and its tests, adds the `bin/` shim, and switches the
GitHub workflows to the `bin/` command. Green GitHub CI on the mirrored
commit is the evidence that behavior is preserved; it runs after the merge
on GitLab, not before (§2.4). A file on the delete list in §6.3 is not
moved; it stays in `.github/scripts/` until the workflows that call it are
removed. The scripts that the GitHub publish workflow calls stay where they
are (§6.3).

Package names are proposals.

| Package | Entry point | Absorbs |
|---|---|---|
| `tools/ci/` | `bin/ci` | the `run-test-lane`, `setup-ruby-test-env`, `generate-test-secrets` and `wait-for-http-service` actions; `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh`; the inline e2e steps (container and server boot, per-lane environment, worker start and log gate, seed, log assertions, flaky gate, failure forensics); the migration concurrent-boot script; later, CI metrics |
| `tools/oci/` | `bin/oci` | the `test-docker-container` action. `update-version.sh`, the tag logic inlined in the publish workflow and the post-push audit stay with the GitHub publish workflow (§4.6). |
| `tools/sentry/` | none | Not created. Sentry delivery stays in the GitHub publish workflow, with `extract-frontend-dist.sh`, `sentry-sourcemap-preflight.sh`, `sentry-status.sh` and `sentry-verify-artifacts.sh` in `.github/scripts/` (§4.6, §6.3). |
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
- **Path filters must move with the code.** Today a change under
  `.github/actions/**` forces every path-selected job, and `run-test-lane`
  is in the `harness` filter. No filter matches `tools/ci/**`, and once the
  `test-docker-container` action is in `tools/oci/`, its path is one that
  the `oci` filter (`ci.yml:230-235`) does not list. On GitHub this no longer
  matters for selection: no pull requests run there, and a push runs every
  job (`ci.yml:158` sets `run_all` for `push`). The GitLab rules need the
  entries (§4.4): `tools/ci/**` in the harness fragment, `tools/oci/**` and
  `bin/oci` in the `oci` fragment, and `tools/oci/**` in the container e2e
  fragment. `ci.yml:189-190` and `tools/testsuite/api-v3-fresh-schemas-test.sh`
  name script paths that also change.
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
  release tags from a remote hard-wired to the GitHub URL. GitHub receives
  every tag through the mirror (§2.4), so the remote can stay. A tag reaches
  GitHub up to a minute after it is created on GitLab.

## 6. Disposition of every existing file

### 6.1 Workflows

A workflow that moves to GitLab keeps running on GitHub until its GitLab
equivalent runs. It is then disabled on GitHub (Phase 5) and deleted at
Phase 6. Four workflows stay on GitHub permanently: the publisher,
`github-release.yml`, `visual-archive.yml`, and `bump-api-docs.yml` unless
its deploy moves.

| Workflow | Disposition |
|---|---|
| `ci.yml` | `lint.yml`, `frontend.yml`, `ruby.yml`, `images.yml`. `changes` and `ci-verdict` deleted. Aggregate becomes a report job. `host-proxy-wire` calls `bin/host-seam`, with Caddy pulled by digest. `ci-metrics` ported in Phase 6. The `i18n-validate` job keeps one report-only step and two blocking ones. |
| `static-analysis.yml` | `lint.yml`. actionlint stays for the workflows that remain on GitHub. |
| `drift-guards.yml` | one guard job in `lint.yml`, with full history. The macOS job follows D4; the recommendation keeps it on GitHub with a schedule (§4.12). |
| `docs-command-drift.yml` | folded into the guard job, still calling `bin/testsuite-installer check-docs-commands`. |
| `validate-config.yml` | its three guards duplicate `drift-guards.yml`; its unique steps (schema generation, `bin/ots config validate`) become a job selected by path. It is dispatch-only today. |
| `validate-register.yml`, `resolved-derive-gate.yml` | two jobs with a shared template (§4.10). |
| `bump-api-docs.yml` | The diff moves to `release.yml` on merge requests; it compares two generated documents and reads no token (§4.11). The deploy keeps running on GitHub on mirrored pushes to `main` until it moves to `release.yml`; then the GitHub workflow is disabled, or the docs deploy twice. The deploy from `develop`, which only a manual dispatch reaches today (`bump-api-docs.yml:137`), is not ported. Fix: each `bump diff` failure, including an auth or network error, is reported as "breaking changes" today. |
| `generate-translation-request.yml` | retire (D9). Its paths `src/locales` and `src/scripts/locales` do not exist in the tree. |
| `housekeeping-github-issues.yml`, `housekeeping-lock-threads.yml` | `gitlab-triage` (§4.10). Disabled on GitHub (§2.4); deleted at Phase 6. |
| `pr-labeler.yml` | drop (D6). Disabled on GitHub (§2.4); deleted at Phase 6. |
| `secret-rotation.yml` | `smoke.yml`. |
| `claude.yml`, `claude-code-review.yml` | D8. Disabled on GitHub (§2.4); deleted at Phase 6. |
| `build-and-publish-oci-images.yml` | Stays on GitHub as the publisher (§4.6). `images.yml` builds `main` on GitLab for testing only. Its `pull_request` trigger ignores every path, so it cannot fire (inferred); it can be removed there. Its version-pin gate before the build stays. |
| `github-release.yml` | Stays on GitHub (§2.4, §4.6). |
| `debug-oci.yml` | delete in Phase 1. Its header calls it temporary. |
| `compose-smoke.yml`, `baremetal-boot.yml`, `fresh-clone.yml`, `installer.yml`, `devcontainer-ci.yml` | `smoke.yml`, on the weekly schedule and on the same path triggers, on the `runtime` image with no cache or artifact (C8). The devcontainer job uses the devcontainer CLI. The `macos` job follows D4; the recommendation keeps it on GitHub's weekly schedule (§4.12). |
| `e2e.yml`, `e2e-full-auth.yml`, `e2e-tenant-connect.yml` | `e2e.yml`, sharing one template. |
| `visual.yml` | `e2e.yml`. Valkey comes from `compose.test.yml` on port 2163, not from a service on 6379. |
| `visual-archive.yml` | Stays on GitHub, dispatched by `github-release.yml` (§4.6). |
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
| `setup-node-env` | stays: the GitHub publish workflow uses it (`build-and-publish-oci-images.yml:244`). Its other callers move to the toolchain image. |
| `setup-ruby-test-env` | `bin/ci prepare`; delete at Phase 6. |
| `test-docker-container` | `bin/oci smoke`. |
| `wait-for-http-service` | `bin/ci wait-http`. |

### 6.3 `.github/scripts/`

| Script | Disposition |
|---|---|
| `aggregate-test-results.sh`, `generate-test-summary.sh`, `pin-ruby-version.sh`, `check-api-v3-fresh-schemas.sh` | move to `tools/ci/` |
| `update-version.sh` | stays; the GitHub publish workflow calls it |
| `extract-frontend-dist.sh`, `sentry-sourcemap-preflight.sh`, `sentry-status.sh`, `sentry-verify-artifacts.sh` | stay; the GitHub publish workflow calls them, and the other three source `sentry-status.sh` by its `.github/scripts/` path |
| `clean_databases.rb` | move to `tests/lanes/support/` |
| `ci-metrics-breakdown.sh`, `post-pr-metrics.cjs` | stay until Phase 6, then replaced by the metrics port |
| `ci-verdict.sh`, `compute-auth-selection.sh`, `compute-path-filter-outputs.sh`, `detect-ci-flags.sh`, `read-pr-labels.sh`, `ruby4-step-outcomes.sh` | delete at Phase 6 |

### 6.4 Other files

| File | Disposition |
|---|---|
| `.github/renovate.json5` | move and adapt (§4.9) |
| `.github/auth-paths.yml` | becomes a fragment in `.gitlab/ci/rules.yml` |
| `.github/ISSUE_TEMPLATE/bug_report.yml`, `feature_request.yml`, `pull_request_template.md` | `.gitlab/` templates. Whether the two issue forms stay on GitHub follows the GitHub Issues decision (§2.4). |
| `.github/ISSUE_TEMPLATE/config.yml` | stays: it points GitHub's issue chooser at GitLab (§2.4) |
| `.github/lint-baseline/shellcheck.tsv` | stays with the shell lint script; new location chosen at Phase 6 |
| `.github/lint-baseline/actionlint.tsv`, `actionlint.yaml` | stay while workflow files remain on GitHub |
| `.github/labeler.yml` | delete (D6) |
| `.github/release-drafter.yml` | delete after the ADR-009 amendment (D7) |
| `.github/dependabot.yml.disabled` | delete in Phase 1 |
| `.github/copilot-instructions.md` | delete at Phase 6, after its rules have one home (§4.10) |
| `.github/FUNDING.yml` | stays: it configures the sponsor button of the GitHub repository |
| `.github/pr-assets/` | stays. The mirror would carry a deletion to GitHub `main`, and pull requests may link these images by branch path (not checked). |
| `docker/bake.hcl` | gains a staging mode and cache settings, and attestation settings if the GitHub workflow adopts signing (§4.6). The GitHub publish workflow keeps using it. |
| `scripts/ci-secrets-ignore.txt` | replaced with the guard's redesign (§5) |

### 6.5 Dependencies

- **Removed:** the third-party actions used only by workflows that move to
  GitLab, and the cross-repository derive action (as an action). The
  workflows that stay on GitHub keep theirs (§6.1).
- **Added:** the toolchain image; `glab`; `gitlab-triage`; the
  devcontainer CLI; `osv-scanner`; the Claude CLI as a pinned install (the
  action bundles it today); GitLab's SAST, secret detection and
  container scanning; a self-hosted Renovate runner; a rule evaluator for
  tests if S3 selects one.
- **Changed:** Renovate config; Playwright reporters; `docker/bake.hcl`;
  `bump-cli` moves from an install step to the toolchain image; `GITHUB_JOB`
  detection
  in `lib/onetime/application/auth_strategies/dev_worker_identity.rb` and
  `GITHUB_BASE_REF` in `tools/envref/` gain provider-neutral equivalents.

## 7. Phases

Implementation changes target `develop`. The pilot on `main` reaches
`develop` through the next `main` to `develop` sync; do that first.

Release model (decided 2026-11-13, §8): release tags are created on GitLab,
the push mirror delivers them to GitHub, and GitHub's
`build-and-publish-oci-images.yml` builds and publishes the images to Docker
Hub and GHCR (§2.4, §4.6). The decision says the next release is created from
GitLab. Whether v0.26.20 (release prep #4943) is tagged on GitLab or on
GitHub is not decided. The v0.27.0 promotion is #4927.

Development is on GitLab, and GitLab has no merge gate yet. Until Phase 3
exits, the GitHub runs on mirrored `main` and `develop` commits are the test
signal, after the merge. Phase 2 makes sure the release path works end to
end; Phase 3 puts tests in front of merges. Phases 1 to 3 overlap. Phase 4
can finish after cutover.

Do not change `build-and-publish-oci-images.yml` or the scripts it calls
until v0.26.20 is tagged and published. After that it stays the publisher.

### Phase 0: decisions and spikes

No change to CI behavior. Spikes run on a throwaway branch on GitLab.

| Spike | Question | Changes the plan if |
|---|---|---|
| S1 | Does a Docker daemon inside the job work on hosted runners? Cover: the `unit` and `full-pg` lanes; a native e2e boot with Chromium; `bin/visual` (host network, `/dev/shm`, bind mount); `host.docker.internal` to a sibling container; ports 80 and 443; `network_mode: service`; image builds; a non-root user with sudo; file ownership in the devcontainer job; MTU. Compare job times with GitHub. | it fails: hosted runners take only the light jobs, and the self-hosted fleet has no overflow |
| S2 | What does a fork merge request pipeline do under the project's settings? | forks cannot pull the toolchain image or run privileged jobs |
| S3 | Can a rule evaluator resolve the job list for fixture scenarios offline, including `rules:changes`, labels and workflow variables? Do the four brace and class patterns in the auth list match under `File.fnmatch`? | no: selection moves to a tested script that generates a child pipeline. |
| S4 | Registry cache hit rate for the merge request image build. The per-architecture question belongs to the GitHub publish workflow (§4.6). | low: drop the cache settings |
| S5 | macOS: hosted runner availability and cost on the tier, or a self-hosted macOS runner | feeds D4; needed only if the macOS jobs leave GitHub |
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

1. `tools/oci/` with `bin/oci smoke`, and the container validation in
   `ci.yml` switched to it. The publish workflow and the scripts it calls
   are not moved (§4.6, §6.3).
2. Remove dead code: the uncalled composite action, `debug-oci.yml`,
   `dependabot.yml.disabled`, the unread `environment` input of `e2e.yml`,
   the stale merge driver in `.gitattributes`, the reference to a
   nonexistent `bin/adr-lint`.
3. `tools/ci/` with the reporter, then `docker`, `services`, `prepare`,
   `lane`, `results`, `secrets`, `wait-http`, `pin-ruby`,
   `api-v3-fresh-schemas`, `e2e`. Update the shell-lint strict list in each
   change.
4. Fixes that belong to the code being moved, each verified first:
   - `pnpm lint` runs ESLint with `--fix` (`package.json:57`), so fixable
     problems pass CI.
   - The aggregate report fills its `file` field from the RSpec seed.
   - shellcheck skips extensionless scripts such as `tests/lanes/run`.
   - adr-lint runs in CI only when a PR touches `docs/adr/`.
   - `generate-test-secrets` prints the generated values.

Exit: everything the GitLab pipeline will call exists behind a `bin/`
command and is exercised by the GitHub workflows; every file left in
`.github/scripts/` is on the delete list, waits for the metrics port, or
stays with the GitHub publish workflow (§6.3); `bin/testsuite run` and
GitHub CI are green on `main`.

### Phase 2: GitLab foundation and the release path

- The toolchain image and its guard; the root file with inputs, workflow
  rules, stages and defaults; project settings, variables and environments; a
  protected runner for jobs that read deploy credentials; the redesigned
  credential guard.
- Protection settings (§4.11). In place since 2026-11-13: `main` and
  `develop` are protected branches, and `v*` is a protected tag that only
  Maintainers can create (§2.4). Who may push to the branches directly is
  part of Q2. Still to do: one environment per credential group, including
  one for the Claude credential alone.
- `develop` stays protected for two reasons. "Pipelines must succeed" checks
  merge requests only, so a direct push to an unprotected `develop` would
  pass no gate. And the mirror pushes only protected branches, so GitHub
  would stop receiving `develop` without it. On GitHub, the "Develop"
  ruleset (11465009) is disabled and the mirror ruleset protects the branch
  (§2.4). No GitLab pipeline publishes (§4.6).
- What protecting `develop` costs: protection is one flag per branch, so
  every pipeline on `develop` can read protected variables and use the
  protected runner. Environment scope and job rules select the jobs that
  get deploy credentials; the people who can reach them are all who can
  push or merge to `develop`. A promotion merge request also has two
  protected branches, so the setting "Allow merge request pipelines to
  access protected variables and runners" is turned off. GitLab's page
  does not state its default. GitLab's source turns it on for every newly
  created project (`app/services/projects/create_service.rb`, 19.5), so
  expect it on.
- `images.yml`: the `main` build for testing and container validation.
  `release.yml`: the GitLab release job. Publishing, Sentry, the GitHub
  release page and the visual archive stay on GitHub (§4.6).
- `github-release.yml` reaches GitHub `main`, because GitHub reads a
  `workflow_run` workflow from the default branch (§2.4).
- Release prerequisites outside CI: Renovate runs on GitLab (D11). The
  product's footer links, the envref release remote and Sentry's repository
  integration keep working through the mirror and need no change (§4.6,
  §5).
- `lint.yml` and `frontend.yml`; retire the pilot job and
  `ci/typescript-pilot/`.

Exit:

- A release candidate tag created on GitLab reaches GitHub through the
  mirror, its images are published, and `github-release.yml` creates its
  GitHub release page.
- 20 consecutive merge request pipelines are green for lint and frontend,
  with results equal to the GitHub runs on the same commits after the merge.

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

Until this phase exits, the arrangement is the one in §2.4: the mirror
pushes `main`, `develop` and tags to GitHub, and the GitHub workflows test
them after the merge. That is a weaker gate than a pull request gate,
because nothing beyond the GitLab jobs that already exist runs before a
merge, and the workflows that run only on pull requests run nowhere.

### Phase 4: the remaining jobs

The nightly schedule with the Ruby preview; the weekly schedule with
`smoke.yml`; visual regression; API docs; triage; review jobs; templates.

This phase can finish after cutover. Until it does, the GitHub schedules for
the install and boot lanes and the Ruby preview, and the API docs deploy on
mirrored pushes to `main`, keep running on GitHub (Phase 5 disables only
what GitLab covers). Visual regression runs only on pull requests, so it has
no coverage until its GitLab job exists (§2.4).

### Phase 5: cutover

Prerequisites: Phases 2 and 3 have exited. There is no archive step: GitHub
stays a mirror (decided 2026-11-13).

1. Enable "Pipelines must succeed" and, on Premium, merge trains. Activate
   the schedules. Update `.agents/skills/merge/SKILL.md` and AGENTS.md
   ("Running tests" names `.github/scripts/` and the `Static analysis`
   workflow).
2. On GitHub, disable each scheduled or push-triggered test workflow that a
   GitLab job now covers (`gh workflow disable`, which turns off every
   trigger of the workflow). Keep `build-and-publish-oci-images.yml`,
   `github-release.yml` and `visual-archive.yml`. Keep `bump-api-docs.yml`
   unless its deploy has moved to GitLab; if it has, disable it, or the API
   docs deploy twice. Keep the macOS jobs if D4 follows the recommendation.

Rollback is to enable the disabled workflows again (`gh workflow enable`).
Merges stay on GitLab either way. Merging on GitHub again would mean
stopping the mirror, disabling the two mirror rulesets and enabling
"Default" and "Develop" again (§2.4); a commit made on GitHub makes the
next mirror update fail (R11).

A risk that stays after cutover: GitHub: "In a public repository, scheduled
workflows are automatically disabled when no repository activity has
occurred in 60 days." The mirror keeps the repository active as long as
GitLab `main` or `develop` receives commits. If pushes stop for 60 days, the
nightly image stops without a failure. Each workflow is then enabled again
by hand: "Enable workflow" on its Actions page, or `gh workflow enable`.
GitHub's pages do not define "repository activity" (R16).

Exit: GitLab gates every merge and its schedules run; the GitHub workflows
that GitLab covers are disabled; the publisher and the release workflows
still run on GitHub.

### Phase 6: decommission and hardening

- Delete from `.github/` what no GitHub workflow uses any more, and the
  suites of the deleted scripts. Do not delete the whole directory: the
  mirror carries the deletion to GitHub `main` and to every later tag, and
  the publisher would go with it. What stays in `.github/`:
  `workflows/build-and-publish-oci-images.yml`,
  `workflows/github-release.yml`, `workflows/visual-archive.yml`,
  `workflows/bump-api-docs.yml` unless its deploy moved, the macOS jobs if
  D4 keeps them on GitHub, `actions/setup-node-env`,
  `scripts/update-version.sh`, `scripts/extract-frontend-dist.sh`,
  `scripts/sentry-status.sh`, `scripts/sentry-sourcemap-preflight.sh`,
  `scripts/sentry-verify-artifacts.sh`, `FUNDING.yml`,
  `ISSUE_TEMPLATE/config.yml`, `pr-assets/`, and the actionlint config and
  baseline (§6.4). Outside `.github/`, the publisher also calls
  `scripts/check-version-pins.sh` and `docker/bake.hcl`, and the visual
  archive calls `bin/setup` and `bin/visual`.
- Delete the five workflows disabled on 2026-11-13 (§2.4).
- Rewrite the documents that describe the GitHub setup:
  `docs/development/auth-ci.md`, `docs/development/README.md`, the "CI
  integration" section of the lane spec, `tests/lanes/README.md`,
  CONTRIBUTING.md, `e2e/README.md`, `e2e/system/README.md`,
  `e2e/visual/README.md`, `docs/architecture/build-architecture.md`,
  `docker/README.md`, `docker/s6/README.md`, `docker/variants/README.md`,
  `scripts/README.md`, and the READMEs under `tools/testsuite/`,
  `tools/testsuite-installer/` and `tools/envref/`. ADR-042's implementation
  notes name `actions/setup-python` and two workflows; add a note there.
  What these documents say about the publisher and the visual archive on
  GitHub stays true.
- Four tracked documents contain invisible provenance markers that defeat
  literal search (`scripts/README.md`, `tools/testsuite/README.md`,
  `tools/logship/README.md`, `docs/development/frontend-diagnostics.md`);
  read them, do not grep them.
- Port CI metrics. Turn the scanners into gates. Signing, if adopted, is a
  change to the GitHub publish workflow (§4.6).

## 8. Decisions

### Decided on 2026-11-10 (maintainer)

- **Runner fleet:** both hosted and self-hosted. §4.12 proposes the split.

The other two decisions of that day, that GitHub is archived after cutover
and that v0.26.20 is the last release from GitHub, are replaced by the
decision of 2026-11-13.

### Decided on 2026-11-13 (maintainer)

The maintainer's words: "We have switch development to GitLaband the next
release will be created from there. We would like the github repo to be a
mirror with the the ghcr images and docker images still being built there
(using the free workflow minutes since it's a public repo) so that we
maintain continuity with this distribution points."

Consequences, as this plan reads them:

- **GitHub is a push mirror and is not archived.** GitLab pushes `main`,
  `develop` and every tag to it (§2.4). Nobody merges or pushes there except
  the mirror.
- **Release model.** Release tags are created on GitLab. The mirror delivers
  them to GitHub, where `build-and-publish-oci-images.yml` builds and
  publishes the images on the free public-repository minutes, and
  `github-release.yml` creates the GitHub release page. The GitLab release
  is created on GitLab (§4.6). Whether v0.26.20 is tagged on GitLab or on
  GitHub is not decided.
- **Distribution.** Docker Hub and GHCR both continue under the same names
  and tags. The image builds, Sentry delivery and the visual archive stay
  on GitHub. GitLab builds images only to test them. This resolves D3.
- **Rollback** of a phase means enabling the GitHub workflows again; there is
  no unarchive (Phase 5). The product links to GitHub release pages and the
  envref release remote keep working, and so does Sentry's repository
  integration (inferred, §4.6).
- **What ends on GitHub:** Dependabot security updates, Codex and Copilot
  review, the Claude workflows, the path labeler and the GitHub housekeeping
  workflows (§2.4). No pull requests are opened on GitHub, so the workflows
  that run only on pull requests run nowhere until GitLab has their
  equivalents.
- **macOS:** the two jobs can stay on GitHub (D4, recommendation).

### Open

| ID | Decision | Recommendation | What it changes |
|---|---|---|---|
| D1 | GitLab tier | Decide after S6, together with D5, which needs Premium. D4 needs Premium only if the macOS jobs leave GitHub. | merge trains, quota for the light jobs, macOS runners if D4 moves them |
| D4 | macOS coverage | Recommendation (not decided): keep both jobs on GitHub. `installer.yml` `macos` already runs weekly. `envref-macos` in `drift-guards.yml` has only pull request and dispatch triggers and runs nowhere now; give it a schedule there (Proposal, §4.12). Otherwise a self-hosted macOS runner or GitLab's hosted one, whichever S5 favors. | D1, if the jobs leave GitHub |
| D5 | Merge trains | Yes, if Premium. The setting is per project. | replaces the merge queue |
| D6 | Path-based labels | Drop, with the ADR-009 amendment | removes the labeler with no replacement |
| D7 | Release notes inventory (ADR-009) | Amend the ADR: scriv stays the narrative; the release job lists the milestone's merged merge requests | unblocks deleting `release-drafter.yml` |
| D8 | Which AI reviewers continue, and with which triggers | Greptile through its GitLab integration; Claude review as a CI job on merge request open and on the `claude-review` label, with the current skips; defer `@claude` mentions | |
| D9 | Translation request workflow | Retire. Re-specify on `locales/scripts` if it is still wanted. | with its default input it resolves no locales (inferred), because its paths are gone |
| D10 | CI metrics port before or after cutover | After | between cutover and the port there is no per-job regression flag on merge requests. The tier budget check is advisory today (`fail-on-violation` is false). |
| D11 | Renovate hosting | Self-hosted runner project | works on any tier and serves every repository. Renovate on GitHub cannot merge, so until this runs there are no dependency update merge requests (§4.9). |
| D13 | GitLab for Open Source application | Check the profit clause first | cost factor and tier |
| D14 | Register full scans that are expected to fail | Verify the claim first. If true, mark the full-scan job `allow_failure` until the findings are fixed. | whether `main` and weekly pipelines are red from day one, and whether a promotion that changes locale content can merge; needed before the first promotion on GitLab |
| D15 | Guard scripts in `scripts/` | Leave them (§5) | scope of the ADR-042 consolidation |

Settled by the 2026-11-13 decision:

- D2 (GitHub's role): a push mirror that keeps building and publishing the
  images (§2.4).
- D3 (where images and visual baselines are published): Docker Hub and GHCR
  both continue, built on GitHub. The visual baselines stay on GHCR. The
  GitLab registry stores the CI staging images and the toolchain image.
- D12 (where issues live): on GitLab. Whether GitHub Issues are turned off
  is an open operator decision (§2.4).

One question I could not answer from the repository:

- **Q2. What is the branch model?** CONTRIBUTING.md says "Target the `main`
  branch." The pre-commit config names `develop` and `rel/.*` as branches not
  to commit to, scriv lists `main, develop`, and workflow filters name
  `feature/*`, `fix/*`, `wip/*` and `rel/*`. `workflow:rules` and branch
  protection need one statement of which branches are protected and which get
  pipelines.

Q1 asked whether changes merge through GitHub pull requests or GitLab merge
requests, because the merge skill on `main` uses GitLab while the promotion
PR and Renovate are on GitHub. The 2026-11-13 decision answers it: changes
merge through GitLab merge requests. The mirror delivers every commit on
`main` and `develop` to GitHub, which gives the parity checks in Phases 2
and 3 the same commits on both hosts.

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
| R11 | The mirror update fails when a ref on GitHub has diverged from GitLab. With "Keep divergent refs" on, GitLab does not force-push, and its page says "The update is marked as failed." Nothing fails on GitHub, so a release tag or the `main` that the nightly builds can stay behind without anyone noticing. | check the mirror status on GitLab (Settings, Repository, Mirroring repositories) after each release tag; the rulesets keep everyone but the mirror off `main`, `develop` and `v*` on GitHub (§2.4) |
| R12 | The release path is the mirror, the GitHub publish workflow and `github-release.yml` on GitHub `main`. If any of them fails, the release waits. | Phase 2 exit: a release candidate tag goes through the whole path |
| R13 | A branch or tag deleted on GitLab stays on GitHub: with "Keep divergent refs" on, the mirror deletes nothing (§2.4). A wrong release tag deleted on GitLab keeps its images and its GitHub release, and a new tag of the same name at another commit diverges (R11). | fix it on GitHub by hand; only the deploy key may delete a `v*` tag there, so that needs a ruleset change |
| R14 | GitHub creates no push event for tags "when more than three tags are pushed at once." A mirror update that carries more than three tags may start no image build (inferred). A tag push also runs the workflow files at the tagged commit, while `github-release.yml` is read from `main`; the two can drift apart. | push release tags one at a time, and check that the image workflow started; keep the two workflows compatible across a release |
| R15 | GitHub secret scanning push protection could reject a mirror push that contains a detected secret, and the update would fail (inferred, not tested). | GitLab secret detection before the merge (§4.8); the mirror status check in R11 |
| R16 | GitHub disables scheduled workflows in a public repository after 60 days without repository activity. The mirror keeps the repository active only while GitLab `main` or `develop` receives commits. The nightly image would stop without a failure. | if commits stop, check and re-enable the scheduled workflows (Phase 5) |

## 10. Adjacent work, not in this plan

These are outside CI but several choices above depend on them:

- Import of issues, pull requests and releases. GitLab's importer does not
  import required status checks or outside collaborators.
- Product links to GitHub: three footers and the admin layout link each
  version to `github.com/.../releases/tag/v<version>`, and Vitest specs assert
  those URLs. They need no change while `github-release.yml` creates the
  GitHub release pages (§4.6).
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
| B-S2, C-F16 | Triggers and inputs that cannot fire or are never read; the unreachable branch-push tag rule | Design; not ported. In the GitHub publish workflow, which stays, they remain until removed there (§6.1). |
| B-S5 | Publish is not gated on a boot test; the audit never compares | Open; §4.6 proposes a gate and the audit fix for the GitHub publish workflow |
| B-S6 | arm64 built under QEMU | Kept; a question for the GitHub publish workflow (§4.6) |
| B-S7 | Tag logic edge cases (inferred) | Open; fix in the GitHub publish workflow (§4.6) |
| B-S8 | Registry and platform defaults repeated; custom mode with an empty host (inferred) | The defaults: Open where they sit in the GitHub publish workflow. The routing is in `bake.hcl`: fix with the staging mode (§4.6). |
| B-S9 | Sentry plumbing larger than the build; inline helper copied three times | Open; Sentry stays in the GitHub publish workflow (§4.6) |
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
60-day rule, and the fact that scheduled workflows run on the default
branch, are from
docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows,
read on 2026-11-11. How to enable a disabled workflow is from
docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows.

Push mirror facts, read on 2026-11-13:

| Fact | Source |
|---|---|
| A push mirror receives a push "in five minutes, or one minute if the setting Only mirror protected branches is on." | docs.gitlab.com/user/project/repository/mirror/push/ |
| With "Keep divergent refs" on, a diverged ref fails the update: "The update is marked as failed." | docs.gitlab.com/user/project/repository/mirror/push/ |
| The protected-branch filter matches every tag; with Keep divergent refs there is no force push and no deletion | Gitaly, `internal/gitaly/service/remote/update_remote_mirror.go` on `master` (source, not run) |
| "Deploy keys only grant access to a single repository." | docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys |
| Events triggered by `GITHUB_TOKEN` create no workflow run, except `workflow_dispatch` and `repository_dispatch` | docs.github.com/en/actions/concepts/security/github_token |
| "Events will not be created for tags when more than three tags are pushed at once." | docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows (`push`) |
| `workflow_run` "will only trigger a workflow run if the workflow file exists on the default branch." | the same page (`workflow_run`) |
| GitHub's SSH host keys | api.github.com/meta |

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
pull request 4944 include CodeQL's `Analyze` jobs. The rulesets, the deploy
key and the disabled workflows as configured on 2026-11-13 are in §2.4.

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
a scheduled pipeline (read from GitLab's source, not its docs); that a
mirror push through the deploy key starts the push workflows on GitHub
(GitHub's page suppresses only events triggered by `GITHUB_TOKEN`, and no
mirrored push has been checked for runs yet); whether GitHub secret scanning push protection
applies to the mirror's pushes.
