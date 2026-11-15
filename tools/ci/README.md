# tools/ci

The steps of a CI job that runs a test lane, behind one command, `bin/ci`
(ADR-042). The GitLab `smoke-lane` job (`.gitlab/ci/ruby.yml`) calls them,
one `script:` entry each:

```console
$ bin/ci toolchain              # apt packages, Docker Engine, Node, pnpm (interim)
$ bin/ci docker up              # a Docker daemon inside the job container
$ bin/ci services up valkey rabbitmq
$ bin/ci prepare                # etc/ from etc/defaults, bundle and pnpm installs
$ bin/ci lane smoke             # tests/lanes/run smoke with the CI log profile
```

The design is in `docs/planning/2026-1110-gitlab-ci-migration-plan.md`:
§4.3 for the execution environment, §5 for this package. The package has
only the commands a GitLab job calls today. The GitHub workflows still use
their composite actions.

## What runs where

| Command | Outside a GitLab CI job | In a GitLab CI job |
|---|---|---|
| `toolchain` | refuses | installs system packages as root |
| `docker up` | nothing to do when `docker info` answers; refuses to start a daemon | starts `dockerd` in the job container unless one answers |
| `services up <name>...` | `docker compose -f compose.test.yml up --wait -d <name>...` | the same, after `sysctl vm.overcommit_memory=1` |
| `prepare` | refuses | rewrites the checkout's `.bundle/config`, installs gems and node modules |
| `lane <lane>` | runs the lane | runs the lane |

The refusals key on `GITLAB_CI=true`. `toolchain`, `prepare` and the daemon
start mount filesystems, move cgroups, switch the iptables backend, install
packages or rewrite `.bundle/config`. Each of those is harmless in a job
container that is discarded afterwards, and harmful on a workstation.

## The daemon inside the job

`bin/ci docker up` follows what spike S1 ran on GitLab.com's hosted Linux
runners (plan §7, "S1, first pass"). The data root is under `CI_BUILDS_DIR`,
off the container's overlay root filesystem. The bridge MTU is copied from
the job's `eth0`. Docker Hub pulls go through `mirror.gcr.io`. The daemon
logs to `tmp/ci/dockerd.log`.

The job container is replaced before `after_script`, so the daemon and the
services are gone there. `bin/ci services up` and `bin/ci lane` write
`tmp/ci/services.log` themselves when they fail.

## The toolchain command

`bin/ci toolchain` is a stand-in for the toolchain image (plan §4.3). A job
on that image does not call it, and the command goes away with the last job
that does.

## Tests

`tools/ci/tests/ci-test.sh` runs under `bin/testsuite run`, offline. It
covers dispatch, the refusals outside a GitLab job, and the commands that can
run against stand-in `docker` and lane-runner executables. The daemon start
and the installs run only in a GitLab job, which is where they are tested.
