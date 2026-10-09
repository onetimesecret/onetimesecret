# Repository tooling test suite

The package behind `bin/testsuite` checks repository automation: CI scripts and
workflows, LogTide shipping, Caddy log redaction, and Sentry build output. It does
not run application tests; those remain under `tests/`, with Ruby tests invoked
through `tests/lanes/run`.

## Commands and prerequisites

Run tests only in a checkout where `.test-mode` is already present, as required
by [AGENTS.md](../../AGENTS.md#running-tests).

```bash
bin/testsuite --help
bin/testsuite run                     # all offline shell suites (also the default)
bin/testsuite run sentry-status       # filename substring filter
UPDATE_GOLDEN=1 bin/testsuite run sentry-status  # deliberately rewrite fixtures
bin/testsuite logtide -v              # LogTide tests, mocked HTTP transport
bin/testsuite caddy -v                # real Caddy, bounded loopback listeners
bin/testsuite verify-sentry-build --quick       # inspect existing build output
```

- **`run`:** Bash 4+, Python 3, and jq. No uv, application dependencies, services,
  external network, or containers. Discovers this directory's `*-test.sh` files
  and `tools/*/tests/*-test.sh`, including setup and host-seam checks. CI calls
  this command in `static-analysis.yml`. On macOS, install a newer Bash with
  `brew install bash`; the system `/bin/bash` is too old for this suite.
- **`logtide`:** uv and Python 3.11+. Uses `pyproject.toml` and `uv.lock` via
  `uv run --locked`; installs the locked pytest, httpx, and Cyclopts dependencies
  into this package's `.venv`. The first run may download the interpreter and
  dependencies. Tests still target `scripts/logtide-ship.py`, not a copied
  implementation.
- **`caddy`:** The same managed Python environment, plus the Caddy build used by
  [the SAML transport guide](../../docs/authentication/saml-callback-transport.md#validation-coverage)
  (2.11.4 with transform-encoder). It launches Caddy and a temporary HTTP backend
  on loopback; it does not need a Ruby lane or datastore.
- **`verify-sentry-build`:** jq and the repository's installed Node/pnpm
  toolchain and dependencies. Without `--quick`, it removes `public/web/dist`
  and builds again. It is opt-in, not part of `run`.

The shim finds the repository root and preserves the invoking Bash and arguments.
Command parsing lives in `testsuite.sh`. The build check runs from the repository
root; the Python checks resolve their inputs by file location.

## Package layout

The migration from `scripts/tests/` preserves the existing shell/Python scripts,
fixtures, and assertion library rather than rewriting them. This is a shell-led,
polyglot package: `pyproject.toml` manages the Python checks' dependencies, with
`package = false`; there is no installable Python library or Python CLI requiring
a `src` layout. Shell dispatch uses the same pattern as `tools/setup` and
`tools/host-seam`.

Add offline shell checks as `*-test.sh` and source `lib/assert.sh`. Tool packages
may keep their checks in their own `tests/` directory and source the same helper
at `tools/testsuite/lib/assert.sh`. `scripts/check-shell-lint.sh` holds this
package to ShellCheck's `style` floor without a baseline.

## Why installation checks remain separate

[`tools/testsuite-installer/`](../testsuite-installer/) owns installation and
onboarding validation, not offline checks of repository automation. Its
clean-room runner archives committed `HEAD` into Docker images; other scripts
boot the application, test secret rotation, seed throwaway Compose secrets, or
check documented commands. Those scripts have different prerequisites and side
effects, and share no runtime code with this package.

They are intentionally not discovered by `bin/testsuite run`. Following
[ADR-042](../../docs/adr/adr-042-repository-tooling-packages.md)'s incremental
migration rule, this change moves one domain only. A later installation-tooling
migration should retain its own package boundary rather than making the offline
suite start services or modify `.env`.
