# setup

The shell package behind `bin/setup`: the shared spine its lanes source,
and the opt-in hook that sets up new worktrees.

| File | Role |
| --- | --- |
| `lib.sh` | Sourced by `bin/setup`: output helpers, version gates, connectivity probes, dependency installs, `.envrc` generation, new-worktree helpers. Never executed. |
| `new-worktree.sh` | post-checkout hook (`.pre-commit-config.yaml`, id `new-worktree-setup`). Runs `bin/setup --dev` or `--test` in a worktree git just created, once a clone opts in. See [New worktrees (opt-in)](../../docs/development/README.md#new-worktrees-opt-in). |
| `tests/*-test.sh` | Shell tests, run by `scripts/tests/run.sh` (the `shell tests` job in `static-analysis.yml`). |

## Entry point

`bin/setup` is the public command (ADR-042); `bin/install` and `bin/doctor`
are thin wrappers over it. Only `bin/setup` and `new-worktree.sh` source
`lib.sh`, and git (through pre-commit) is the only caller of
`new-worktree.sh`.

## Constraints

- **Bash 3.2.** macOS ships 3.2, and the old install-dev.sh hard-failed
  there over one associative array (DX-15). No `declare -A`, `${var,,}`,
  `mapfile` or `readarray`. `installer.yml` parses `lib.sh` and
  `new-worktree.sh` under `bash:3.2`.
- **The image ships `lib.sh`.** The container images include `bin/`, so
  `bin/setup` and its wrappers need their spine: the `Dockerfile` copies
  `tools/setup/lib.sh`, and nothing else from this package, into both
  final stages (`final`, `final-s6`).
- **CI path filters.** A change here triggers `fresh-clone.yml`,
  `installer.yml` and `devcontainer-ci.yml` (`tools/setup/**`).

## Departure from ADR-042

ADR-042 says `bin/<domain>` "must not contain business logic". `bin/setup`
still holds every lane (dev, test, init, reconcile, doctor). Moving them
into this package is its own behavior-preserving migration; until then
`bin/setup` is both the entry point and most of the implementation.
