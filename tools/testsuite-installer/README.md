# Installation validation tooling

Installation and onboarding harnesses, behind `bin/testsuite-installer` under
[ADR-042](../../docs/adr/adr-042-repository-tooling-packages.md). This package owns
the scripts formerly in `scripts/install-tests/`; it is separate from the
[offline repository tooling suite](../testsuite/).

## Commands

Run commands from the repository root, or invoke the shim by absolute path from
another directory. The shim resolves the package by location; the dispatcher
runs operations from the repository root and passes arguments and exit codes
through. No operation runs when the command is omitted.

```sh
bin/testsuite-installer --help
bin/testsuite-installer run --lane baremetal
bin/testsuite-installer run --lane posix
bin/testsuite-installer run --lane ruby-old
bin/testsuite-installer run --lane all
bin/testsuite-installer baremetal-boot
bin/testsuite-installer secret-rotation
bin/testsuite-installer proof-of-life http://127.0.0.1:3000
bin/testsuite-installer check-docs-commands
bin/testsuite-installer seed-compose-env
bin/testsuite-installer ttfhw-chart
```

The clean-room `run` command archives **committed `HEAD`**, not the working tree,
into Docker containers. Commit changes before using it to validate them. It
retains the existing `ruby:3.4.10-slim` installer floor and `ruby:3.3-slim`
expected-failure image, and checks installation idempotency.

`proof-of-life` is also available as a standalone script for an image without
this package. CI streams the same implementation through the public command:

```sh
set -o pipefail
bin/testsuite-installer proof-of-life --print-script |
  docker compose -f docker/compose/docker-compose.full.yml \
    exec -T app bash -s -- http://127.0.0.1:3000
```

`--print-script` only emits the script; it does not contact the application.

## Runtime and dependencies

The shim, dispatcher and harnesses use Bash 3.2-compatible syntax. This is a
shell package, so it introduces no language package dependencies or separate
package manager. Application dependencies remain managed by the root
`Gemfile.lock`, `pnpm-lock.yaml`, `.ruby-version`, `.node-version` and
`package.json` (`packageManager`). The existing container images and toolchain
setup remain in `run.sh`; this migration does not change their pins or replace
image tags with digest pins. Run `bin/setup` before the bare-metal app lanes.

| Command               | Prerequisites and effects                                                                                                                                                                                                                                 |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `run`                 | Git and a working Docker daemon; downloads images/toolchains and runs installs in disposable containers.                                                                                                                                                  |
| `baremetal-boot`      | Installed gems and Node/pnpm dependencies, generated locales/schemas, curl and Redis/Valkey server + CLI. Generates scratch secrets, builds assets and boots a throwaway datastore/app. `BM_APP_PORT=3214`, `BM_DB_PORT=2130` by default.                 |
| `secret-rotation`     | Installed gems, generated locales/schemas and app config, Ruby, OpenSSL, curl and Redis/Valkey server + CLI. Boots a throwaway datastore/app. `ROT_APP_PORT=3213`, `ROT_DB_PORT=2129` by default.                                                         |
| `proof-of-life`       | curl and a running app with built assets. Creates and consumes a short-lived secret. `POL_CREATE_ACCOUNT=1` also creates a fresh account via `bin/ots`; `POL_EXEC` optionally selects a container command prefix, and `POL_ACCOUNT_EMAIL` sets its email. |
| `check-docs-commands` | Node and the repository checkout; checks executable entry points and documented pnpm targets without booting the app.                                                                                                                                     |
| `seed-compose-env`    | OpenSSL and `GITHUB_ENV` (GitHub Actions). Appends secrets to that file and **overwrites the root `.env`**; use only in a disposable checkout.                                                                                                            |
| `ttfhw-chart`         | gh, jq, `GH_TOKEN` with Actions read permission and `GITHUB_REPOSITORY`. Calls the Actions API; writes to `GITHUB_STEP_SUMMARY` or stdout. Missing prerequisites skip the chart without failing.                                                          |

`ttfhw-chart` keeps its existing `TTFHW_WORKFLOW`, `TTFHW_JOB_NAME`,
`TTFHW_HISTORY` and `TTFHW_REGRESSION_PCT` overrides. Each implementation's header
contains its detailed environment contract.

## Offline regression tests

```sh
bin/testsuite run testsuite-installer
```

Package tests live in `tests/` and are discovered by the existing offline suite.
They use temporary checkouts and stubs; they do not run installs, boot services,
contact APIs or write the real checkout's `.env`. The offline runner needs Bash
4+; that requirement does not change the install harnesses' Bash 3.2 floor.

CI install lanes invoke `bin/testsuite-installer`, not package-private scripts.
Repository callers have migrated, so no legacy `scripts/install-tests` wrappers
are retained.
