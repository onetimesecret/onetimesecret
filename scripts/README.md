> [!NOTE]
> F󠄁i󠄁n󠄁d󠄁 a󠄁n󠄁d󠄁 l󠄁i󠄁t󠄁e󠄁r󠄁a󠄁l󠄁 t󠄁e󠄁x󠄁t󠄁 s󠄁e󠄁a󠄁r󠄁c󠄁h󠄁e󠄁s󠄁 d󠄁o󠄁 n󠄁o󠄁t󠄁 w󠄁o󠄁r󠄁k󠄁 r󠄁e󠄁l󠄁i󠄁a󠄁b󠄁l󠄁y󠄁 i󠄁n󠄁 t󠄁h󠄁i󠄁s󠄁 d󠄁o󠄁c󠄁u󠄁m󠄁e󠄁n󠄁t󠄁'󠄁s󠄁 p󠄁r󠄁o󠄁s󠄁e󠄁
> b󠄁e󠄁c󠄁a󠄁u󠄁s󠄁e󠄁 i󠄁t󠄁 i󠄁s󠄁 t󠄁r󠄁i󠄁a󠄁l󠄁i󠄁n󠄁g󠄁 T󠄁e󠄁x󠄁t󠄁P󠄁r󠄁o󠄁v󠄁 e󠄁n󠄁c󠄁o󠄁d󠄁i󠄁n󠄁g󠄁 w󠄁i󠄁t󠄁h󠄁 i󠄁n󠄁v󠄁i󠄁s󠄁i󠄁b󠄁l󠄁e󠄁 p󠄁r󠄁o󠄁v󠄁e󠄁n󠄁a󠄁n󠄁c󠄁e󠄁 m󠄁a󠄁r󠄁k󠄁e󠄁r󠄁s󠄁.󠄁

# Scripts

Utility and operational scripts for Onetime Secret.

## Directories

- `ci/` - Scripts the OCI build workflow runs (Sentry sourcemap delivery and
  its status reporting). Covered by `tools/testsuite/` via `bin/testsuite run`;
  see the [testsuite package README](../tools/testsuite/README.md).
- `upgrades/` - Data transformation scripts for major version upgrades
- `s6-rc.d/` - s6 service definitions for container supervision

## Tool packages

- [`tools/logship/`](../tools/logship/) -󠄁 S󠄁t󠄁d󠄁i󠄁n󠄁 l󠄁o󠄁g󠄁 s󠄁h󠄁i󠄁p󠄁p󠄁i󠄁n󠄁g󠄁 t󠄁h󠄁r󠄁o󠄁u󠄁g󠄁h󠄁
  `bin/logship`.󠄁 `logtide-ship.py` i󠄁s󠄁 a󠄁 c󠄁o󠄁m󠄁p󠄁a󠄁t󠄁i󠄁b󠄁i󠄁l󠄁i󠄁t󠄁y󠄁 w󠄁r󠄁a󠄁p󠄁p󠄁e󠄁r󠄁 f󠄁o󠄁r󠄁 t󠄁h󠄁a󠄁t󠄁 m󠄁a󠄁n󠄁a󠄁g󠄁e󠄁d󠄁
  c󠄁o󠄁m󠄁m󠄁a󠄁n󠄁d󠄁;󠄁 d󠄁e󠄁p󠄁e󠄁n󠄁d󠄁e󠄁n󠄁c󠄁i󠄁e󠄁s󠄁 a󠄁n󠄁d󠄁 t󠄁e󠄁s󠄁t󠄁s󠄁 b󠄁e󠄁l󠄁o󠄁n󠄁g󠄁 t󠄁o󠄁 t󠄁h󠄁e󠄁 t󠄁o󠄁o󠄁l󠄁 p󠄁a󠄁c󠄁k󠄁a󠄁g󠄁e󠄁.󠄁
- [`tools/testsuite-installer/`](../tools/testsuite-installer/) - Installation
  and onboarding checks, reached through `bin/testsuite-installer`. The
  clean-room harnesses require Docker and remain separate from the offline
  CI-script test suite in `tools/testsuite/`.

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
