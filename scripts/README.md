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

## Config version annotations

`.env.reference` and `etc/defaults/*.yaml` carry inline `# Since vX.Y.Z`
markers on each setting's own line.
[`docs/development/config-version-annotations.md`](../docs/development/config-version-annotations.md)
is the contract: the marker grammar, the v0.24.0 baseline, and the
immutability rule live there, and every script below breaks if it drifts from
what that document says.

- `check-config-versions.sh` - the ratchet, run by `drift-guards.yml` and
  `validate-config.yml`. New keys need a marker, shipped markers are frozen.
- `resolve-unreleased-versions.sh` - rewrites `Since unreleased` to the version
  being cut. Run it before tagging, not after.
- `config-version-archaeology.sh` - derives first-release versions by scanning
  the release-tag trees. Backfill and audit only; not a build step.
- `config-yaml-version-map.py` - resolves YAML settings to versions, inheriting
  from the env var each one reads.
- `annotate-config-versions.py` - applies markers from that map. Idempotent,
  and refuses to re-date an existing marker.
- `generate-env-docs.py` - generates the docs-site environment-variables page
  from `.env.reference`. Its `--check` guard runs from the docs repo.

[ADR-042](../docs/adr/adr-042-repository-tooling-packages.md) names
`tools/envref/` behind `bin/envref` as where this tooling belongs. These six
predate that decision by five weeks and are stdlib-only; moving them is a
separate behaviour-preserving change, which is the migration shape the ADR
itself asks for.
