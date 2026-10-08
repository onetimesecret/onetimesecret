# Scripts

Utility and operational scripts for Onetime Secret.


## Directories

- `ci/` - Scripts the OCI build workflow runs (Sentry sourcemap delivery and
  its status reporting). Covered by `tools/testsuite/` via `bin/testsuite run`;
  see the [testsuite package README](../tools/testsuite/README.md).
- `install-tests/` - Clean-room install harnesses (require Docker), separate
  from the offline CI-script test suite in `tools/testsuite/`.
- `upgrades/` - Data transformation scripts for major version upgrades
- `s6-rc.d/` - s6 service definitions for container supervision

## Checks

- `check-shell-lint.sh` - shellcheck + actionlint over the repo, failing only on
  findings above `.github/lint-baseline/`. `--update` re-records the baseline.
- `check-version-pins.sh`, `check-env-reference.sh` - manifest drift guards run
  by `.github/workflows/drift-guards.yml`

## Config version annotations

`.env.reference` and `etc/defaults/*.yaml` carry inline `# Since vX.Y.Z`
markers on each setting's own line. The tooling that writes and enforces them
is not here: ADR-042 makes it a tool package, `tools/envref/`, reached through
`bin/envref`.

```bash
bin/envref --help          # the subcommands
bin/envref check           # the CI ratchet, also run by drift-guards.yml
bin/envref resolve v0.26.4 # release step: unreleased -> a real version
```

See [`docs/development/config-version-annotations.md`](../docs/development/config-version-annotations.md)
for the marker contract and
[`tools/envref/README.md`](../tools/envref/README.md) for the package.
