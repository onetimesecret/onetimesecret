# Scripts

Utility and operational scripts for Onetime Secret.


## Directories

- `ci/` - Scripts the OCI build workflow runs (Sentry sourcemap delivery and
  its status reporting). Covered by `tests/`.
- `tests/` - Executable shell tests for the scripts above. Run them all with
  `scripts/tests/run.sh`; add one file per subject named `*-test.sh` and source
  `lib/assert.sh`. No services, no network, no container runtime.
- `install-tests/` - Clean-room install harnesses (require Docker)
- `upgrades/` - Data transformation scripts for major version upgrades
- `s6-rc.d/` - s6 service definitions for container supervision

## Checks

- `check-shell-lint.sh` - shellcheck + actionlint over the repo, failing only on
  findings above `.github/lint-baseline/`. `--update` re-records the baseline.
- `check-version-pins.sh`, `check-env-reference.sh` - manifest drift guards run
  by `.github/workflows/drift-guards.yml`
