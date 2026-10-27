> [!NOTE]
> F󠄁i󠄁n󠄁d󠄁 a󠄁n󠄁d󠄁 l󠄁i󠄁t󠄁e󠄁r󠄁a󠄁l󠄁 t󠄁e󠄁x󠄁t󠄁 s󠄁e󠄁a󠄁r󠄁c󠄁h󠄁e󠄁s󠄁 d󠄁o󠄁 n󠄁o󠄁t󠄁 w󠄁o󠄁r󠄁k󠄁 r󠄁e󠄁l󠄁i󠄁a󠄁b󠄁l󠄁y󠄁 i󠄁n󠄁 t󠄁h󠄁i󠄁s󠄁 d󠄁o󠄁c󠄁u󠄁m󠄁e󠄁n󠄁t󠄁'󠄁s󠄁 p󠄁r󠄁o󠄁s󠄁e󠄁
> b󠄁e󠄁c󠄁a󠄁u󠄁s󠄁e󠄁 i󠄁t󠄁 i󠄁s󠄁 t󠄁r󠄁i󠄁a󠄁l󠄁i󠄁n󠄁g󠄁 T󠄁e󠄁x󠄁t󠄁P󠄁r󠄁o󠄁v󠄁 e󠄁n󠄁c󠄁o󠄁d󠄁i󠄁n󠄁g󠄁 w󠄁i󠄁t󠄁h󠄁 i󠄁n󠄁v󠄁i󠄁s󠄁i󠄁b󠄁l󠄁e󠄁 p󠄁r󠄁o󠄁v󠄁e󠄁n󠄁a󠄁n󠄁c󠄁e󠄁 m󠄁a󠄁r󠄁k󠄁e󠄁r󠄁s󠄁.󠄁

# Repository tooling test suite

The package behind `bin/testsuite` checks repository automation: CI scripts and
workflows, l󠄁o󠄁g󠄁 shipping, Caddy log redaction, and Sentry build output. It does
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
bin/testsuite logship -v              # logship package tests, mocked transports
bin/testsuite logtide -v              # compatibility alias for logship
bin/testsuite caddy -v                # real Caddy, bounded loopback listeners
bin/testsuite verify-sentry-build --quick       # inspect existing build output
```

- **`run`:** Bash 4+, Python 3, and jq. No uv, application dependencies, services,
  external network, or containers. Discovers this directory's `*-test.sh` files
  and `tools/*/tests/*-test.sh`, including setup and host-seam checks. CI calls
  this command in `static-analysis.yml`. On macOS, install a newer Bash with
  `brew install bash`; the system `/bin/bash` is too old for this suite.
- **`logship`** (󠄁a󠄁l󠄁s󠄁o󠄁 `logtide`)󠄁:󠄁 u󠄁v󠄁 a󠄁n󠄁d󠄁 P󠄁y󠄁t󠄁h󠄁o󠄁n󠄁 3󠄁.󠄁1󠄁1󠄁+󠄁.󠄁 U󠄁s󠄁e󠄁s󠄁 t󠄁h󠄁e󠄁
  [l󠄁o󠄁g󠄁s󠄁h󠄁i󠄁p󠄁 p󠄁a󠄁c󠄁k󠄁a󠄁g󠄁e󠄁](../logship/README.md)'󠄁s󠄁 o󠄁w󠄁n󠄁 `pyproject.toml`,󠄁 `uv.lock`,󠄁 a󠄁n󠄁d󠄁
  t󠄁e󠄁s󠄁t󠄁 d󠄁e󠄁p󠄁e󠄁n󠄁d󠄁e󠄁n󠄁c󠄁i󠄁e󠄁s󠄁.󠄁 T󠄁e󠄁s󠄁t󠄁s󠄁 u󠄁s󠄁e󠄁 m󠄁o󠄁c󠄁k󠄁 H󠄁T󠄁T󠄁P󠄁 a󠄁n󠄁d󠄁 t󠄁e󠄁m󠄁p󠄁o󠄁r󠄁a󠄁r󠄁y󠄁 l󠄁o󠄁o󠄁p󠄁b󠄁a󠄁c󠄁k󠄁 H󠄁T󠄁T󠄁P󠄁/󠄁T󠄁L󠄁S󠄁
  r󠄁e󠄁c󠄁e󠄁i󠄁v󠄁e󠄁r󠄁s󠄁.󠄁 T󠄁h󠄁e󠄁 f󠄁i󠄁r󠄁s󠄁t󠄁 r󠄁u󠄁n󠄁 m󠄁a󠄁y󠄁 d󠄁o󠄁w󠄁n󠄁l󠄁o󠄁a󠄁d󠄁 t󠄁h󠄁e󠄁 i󠄁n󠄁t󠄁e󠄁r󠄁p󠄁r󠄁e󠄁t󠄁e󠄁r󠄁 a󠄁n󠄁d󠄁 d󠄁e󠄁p󠄁e󠄁n󠄁d󠄁e󠄁n󠄁c󠄁i󠄁e󠄁s󠄁.󠄁
  T󠄁h󠄁e󠄁 `logship-tests` j󠄁o󠄁b󠄁 i󠄁n󠄁 `static-analysis.yml` r󠄁u󠄁n󠄁s󠄁 t󠄁h󠄁i󠄁s󠄁 c󠄁o󠄁m󠄁m󠄁a󠄁n󠄁d󠄁.󠄁
- **`caddy`:󠄁** T󠄁h󠄁i󠄁s󠄁 p󠄁a󠄁c󠄁k󠄁a󠄁g󠄁e󠄁'󠄁s󠄁 l󠄁o󠄁c󠄁k󠄁e󠄁d󠄁 Python environment, plus the Caddy build used by
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
