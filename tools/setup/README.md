# setup

The shell package behind `bin/setup`: every setup lane, the shared spine
they source, and the opt-in hook that sets up new worktrees.

| File | Role |
| --- | --- |
| `setup.sh` | The lanes: dev (default), `--test`, `--init`, `--reconcile`, `--doctor` (with `--bundle`), `--console`, `--help`. |
| `lib.sh` | Sourced by `setup.sh` and `new-worktree.sh`: output helpers, version gates, connectivity probes, dependency installs, `.envrc` generation, new-worktree helpers. Never executed. |
| `new-worktree.sh` | post-checkout hook (`.pre-commit-config.yaml`, id `new-worktree-setup`). Runs `bin/setup --dev` or `--test` in a worktree git just created, once a clone opts in. See [New worktrees (opt-in)](../../docs/development/README.md#new-worktrees-opt-in). |
| `tests/*-test.sh` | Shell tests, run by `scripts/tests/run.sh` (the `shell tests` job in `static-analysis.yml`). |

## Entry points

`bin/setup` is the public command (ADR-042). It finds the repository root
and runs `setup.sh` with the arguments unchanged. It holds no lane logic
and parses nothing.

The shim starts `setup.sh` with `"$BASH"`, the interpreter running the
shim, rather than through `setup.sh`'s own shebang. `installer.yml`'s macOS
job runs `/bin/bash bin/setup` to prove the lanes work under stock bash
3.2. Going through the shebang would run them under whichever bash comes
first on PATH instead. `tests/entry-point-test.sh` covers this.

`bin/install` (operator) and `bin/doctor` (support) are older public front
doors. Each keeps its own `--help` text and argument check, and runs
`bin/setup --init`, `--reconcile` or `--doctor`. ADR-042 would name them
after the domain. They are documented operator commands, so they keep
their names and stay thin.

`new-worktree.sh` calls `bin/setup`, the public command, not `setup.sh`.

## Constraints

- **Bash 3.2.** macOS ships 3.2, and the old install-dev.sh hard-failed
  there over one associative array (DX-15). No `declare -A`, `${var,,}`,
  `mapfile` or `readarray`. `installer.yml` parses every file here under
  `bash:3.2` and runs the dev and test lanes under `/bin/bash` on macOS.
- **The image ships the lanes.** The container images include `bin/`, so
  the `Dockerfile` copies `setup.sh` and `lib.sh`, and nothing else from
  this package, into both final stages (`final`, `final-s6`).
- **CI path filters.** A change here triggers `fresh-clone.yml`,
  `installer.yml` and `devcontainer-ci.yml` (`bin/setup`,
  `tools/setup/**`).
