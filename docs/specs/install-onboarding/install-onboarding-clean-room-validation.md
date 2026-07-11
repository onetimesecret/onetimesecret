---
title: Install Onboarding — Clean-Room Validation of fix/onboarding-hell
type: assessment
status: current
updated: 2026-07-10
---

# Clean-Room Validation: fix/onboarding-hell (C1–C3)

Live re-run of the [current-state audit](./install-onboarding-current-state.md)
§1 empirical suite against `fix/onboarding-hell` @ d0747c0eb (13 commits over
main @ bb72b88c2), 2026-07-10. This closes the "verified static, unproven
live" gap for most of the branch, and found two live bugs static analysis
missed — plus one deliberate scope deviation worth recording.

**Environment** (matches the audit's fresh-contributor profile): fresh Ubuntu
24.04 container, Ruby 3.4.9 via ruby-build (system Ruby 3.3.6 kept for gate
probes), Node 22.22.2, pnpm 11.10.0 via corepack, redis-server 7.0.15, GNU
coreutils 9.4, **no direnv/overmind/pre-commit, empty `LANG` (POSIX
locale)**. Branch transferred by git bundle; each run in a separate pristine
clone to avoid the audit's run-10 experiment-ordering contamination (gems and
pnpm store shared across clones, mirroring an rbenv machine).

**Boundaries, stated honestly:** no Docker daemon (compose *runtime* and
`docker run` untested — same boundary as the audit); no booted systemd (units
verified with `systemd-analyze verify` only, no real `systemctl start`); no
macOS/bash-3.2 leg.

## 1. Results vs the audit's §1 table

| # | Path (audit result on main) | On fix/onboarding-hell |
| --- | --- | --- |
| 1 | `./install.sh init`, Node 22 (**DIED**: Node gate) | ✅ **GREEN** — full init completes on Node 22 + Ruby 3.4.9, under `LANG=C`, exit 0; configs seeded, secrets generated, doctor runs. With Ruby 3.3.6: clear `Ruby too old: have 3.3.6, need 3.4.9+`, exit 1. ⚠️ one new bug: NF-2 below |
| 2 | `install.sh doctor` (worked) | ✅ still works; connectivity-based Redis check confirmed (`Valkey/Redis responding (127.0.0.1:6379)` — BM-05 fixed) |
| 3 | `./install-dev.sh` (**DIED**: direnv) | 🟡 **still dies without direnv** — now a documented prerequisite (README:102), i.e. deliberate scope-down of C3's "gates → fallbacks" (see §3). With direnv present: ✅ completes — SECRET generated (DX-1 half fixed), `RACK_ENV=development` in `.envrc` (DX-2 fixed), maintainer symlink farm reduced to a one-line skip. 🔴 **but the app still cannot boot on a clean fork** — NF-1 below |
| 4 | compose quick start (**DIED**: empty SECRET) | ✅ client-side path fixed: `cp -n` portable, README one-liner (`echo "SECRET=$(openssl rand -hex 32)" >> .env`) → `docker compose config` passes; empty SECRET still aborts pre-Docker by design. ⚠️ error text still says "run ./install.sh" (NF-3). ❌ runtime untestable here |
| 4b | `bin/dev`, `bin/backend` (**DIED**: overmind) | 🟡 both still hard-require overmind (`bin/dev` now also accepts hivemind). Resolved the alternate way C3 allowed: README "Option B" rewritten to production-style `pnpm run build` + puma — commands that demonstrably work (runs 8b/9) |
| 5 | install-test on Ruby 3.3.6 (**DIED**: kanayago) | ✅ flipped to clear message: `Your Ruby version is 3.3.6, but your Gemfile specified 3.4.9` (`ruby file: '.ruby-version'` working) |
| 7 | install-test on 3.4.9 (green, 76s) | ✅ **EXIT=0 in 110s** on a pristine clone; graceful direnv skip; Valkey→Redis fallback exercised |
| 8 | `rake ots:secrets` + boot, POSIX locale (**DIED**: Encoding::CompatibilityError) | ✅ **GREEN under `LANG=C`** — secrets generate, puma boots, `GET /` 200, `/api/v2/status` nominal. The locale crash is dead |
| 8b/9 | `pnpm run build`, Node 22 (blocked by gate) | ✅ build in 24s incl. `schemas:json:generate` prebuild; page references `/dist/assets/*` and they serve 200 — full working UI |
| 10 | `test:rspec:fast` clean fork (**TR-01**: poisoned-well pass) | ✅ **TR-01 fixed** — 260/260 in 2.5s on a pristine clone with **no build ever run**; install-test generates schemas itself |
| — | proof-of-life (core loop) | ✅ v1 API: create → reveal returns the value → second attempt `Unknown secret` (at-most-once enforced by construction, confirmed live) |
| — | `scripts/check-version-pins.sh` | ✅ PASS ×4, pins in sync |
| — | systemd units | 🟡 `systemd-analyze verify` clean ×3. `StateDirectory=onetimesecret/tmp onetimesecret/log` is structurally correct (creates + whitelists exactly `./tmp` and `./log` since WorkingDirectory *is* `/var/lib/onetimesecret`) — BM-02's mount failure is fixed on paper. Residual risks only a real boot settles: §2 |
| — | ghost `.env.sh` | ✅ purged from all live code paths (comments/CHANGELOG/specs only) |

**Headline: 9 of the audit's 10 first-run rows now pass or fail-with-clear-message
in a clean room. The one red is the contributor dev path (run 3), which
completes setup but still cannot boot the app (NF-1).**

## 2. New findings (live-only; static review missed all of these)

- **NF-1 [B, contributor path] `install-dev.sh` succeeds but the app can't
  boot on a clean fork.** Without `$OTS_DEV_CONFIG`, config symlinking is
  skipped and nothing falls back to seeding from `etc/defaults/` — so
  `etc/config.yaml`, `etc/auth.yaml`, `etc/logging.yaml`, and `etc/puma.rb`
  never exist. The script's own closing message ("start services manually:
  `bundle exec puma -C etc/puma.rb`") therefore fails twice: no puma.rb, and
  boot dies with `Onetime::ConfigError: Config path not set`. Verified
  minimal fix: seeding the three defaults + `etc/examples/puma.example.rb`
  makes dev-mode boot work **and confirms the DX-2 fix functions** (page
  wires `@vite/client` / `localhost:5173`). This is DX-1's other half —
  the audit's six-seeding-paths DUP item biting the one path that has no
  seeding at all. Fix shape: fall back to the same defaults-glob seeding
  install-test.sh uses (or delegate to a shared function). Small patch,
  squarely C3.
- **NF-2 [M] `install.sh init`'s `bin/ots install mark` step always fails on
  first run**: it executes *without sourcing the `.env` it just generated*, so
  boot dies with `Global secret cannot be nil` (warn-level; init still exits
  0 and prints "install mark failed (exit 1)"). Verified: same command
  succeeds with `set -a; . ./.env; set +a` prefixed. One-line fix in the
  subshell.
- **NF-3 [minor] Compose's empty-SECRET error still routes Docker users to
  `./install.sh`** — the persona-crossover advice the audit flagged (CP-1
  residue). The message text lives in `docker-compose.yml`'s `${SECRET:?…}`;
  it should point at the README one-liner instead.
- **NF-4 [minor] `cp -n` is deprecated in GNU coreutils ≥ 9.4**: every run
  prints `cp: warning: behavior of -n is non-portable and may change in
  future; use --update=none instead` — the exact flag C1 removed for macOS
  portability. Both work today; the durable portable form is
  `[ -f .env ] || cp .env.example .env`.
- **NF-5 [observation] The two Ruby gates disagree on semantics**: install.sh
  floor-compares (`3.4.9+`) while `ruby file: '.ruby-version'` makes bundler
  enforce **exactly** 3.4.9 — a contributor on 3.4.10 passes install.sh and
  then gets rejected by bundle. Rails-convention trade-off (Mastodon accepts
  it too), but worth a conscious decision; VER-06's exact-match concern
  resurfaces here in bundler clothing.

**Residual gaps this environment cannot close** (candidates for C7 lanes or a
one-off VM check): real `systemctl start` — specifically whether
`ProtectHome=true` coexists with "Ruby in the onetime user's PATH via rbenv"
when that home is under `/home`, and whether `./data` SQLite writes survive
`ProtectSystem=strict` when full auth is enabled; compose *runtime* +
`docker run` networking (QS-1); macOS / bash 3.2.

## 3. One reconciliation item: the plan and the branch disagree about gates

C3-as-written says "gates → fallbacks: direnv optional… bin/dev falls back
without overmind." The branch instead **documents direnv as a prerequisite**
(commit d0747c0eb) and keeps both hard gates. That may well be the right
call (direnv is load-bearing for the env-loading story the branch
standardized on) — but the work-chunks doc still promises the fallback
version, and its C3 proof criterion ("runs 3, 4b… flip to green") is
therefore unmeetable as specced. Either implement D1.1's fallbacks in a
follow-up or amend the plan to record the decision. The audit's central
lesson was docs and reality drifting apart; don't let the *plan docs* start
the same pattern.

## 4. Recommended sequencing for fix/onboarding-hell-contd1

1. **Fix NF-1 and NF-2 now** (plus NF-3/NF-4 if touching those files anyway)
   — they are C3 loose ends, small, and NF-1 is a Blocker on the very persona
   C3 targeted. Re-verify with the recipe below.
2. **Record the direnv/overmind decision** (§3): one paragraph in
   work-chunks + a C3 status note, or a small D1.1 follow-up chunk.
3. **Build the C7 slice next, before C4/C5.** Today's run is effectively the
   fresh-clone lane's dry run, and the recipe is now proven end-to-end:
   Ubuntu 24.04 + ruby-build 3.4.9 + corepack pnpm + redis + `LANG=C`,
   pristine clone per lane, then: `install.sh init` (Node 22) →
   `install-test.sh` + `test:rspec:fast` (no build — the TR-01 guard) →
   `rake ots:secrets` + puma boot + proof-of-life under `LANG=C` →
   `pnpm run build` + asset probe → `check-version-pins.sh`. Wall-clock
   ~15 min excluding Ruby install (cacheable). Add the compose-smoke and
   docker-run lanes there too — they're the two runtime gaps this container
   couldn't reach.
4. **Then C4/C5** on a foundation that's demonstrably green and guarded.

With NF-1/NF-2 fixed and the C7 slice landed, the branch's honest status
moves from "verified static, unproven live" to "demonstrably works and
stays working" — which was the whole point.

## Related

- [install-onboarding-current-state.md](./install-onboarding-current-state.md) — the audit this validates against
- [install-onboarding-work-chunks.md](./install-onboarding-work-chunks.md) — C1–C3 (validated here), C7 (next)
- [dev-onboarding-problem-space.md](./dev-onboarding-problem-space.md) — D1.1 (the gate decision, §3)
