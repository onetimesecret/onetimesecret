# v0.26.5 release readiness

**Baseline:** `v0.26.4` (2026-08-05) · **Analysed at:** `58df007ee` (= `origin/main`,
2026-08-16) · **Prior tag in this line:** `v0.26.5-rc1` (`21c3f6a`, 2026-08-13)

`v0.26.5-rc1` is three days behind the commit this assessment covers. Everything
below describes `58df007ee`, not the RC.

## Verdict: ship with conditions

Nothing in the release window argues for holding the tag on its own merits.
There is no schema migration and no bulk data transform, so rollback is a tag
swap — the single biggest de-risker available. Test churn ran close to 1:1 with
code churn (28,974 test lines against 34,819 code lines, 59 new test files),
which is the strongest evidence in the metadata that this was developed with
tests rather than tested afterward.

The conditions are the three unfixed High authorization findings carried over
from the 2026-08-14 review (tracked separately), and the otto 2.6.0 → 2.8.0 jump
sitting underneath a trusted-proxy and host-detection rewrite. The largest
genuine unknown is the second one: only a staging tier behind a real proxy
exercises that combination, and no amount of commit reading substitutes for it.

## Shape of the window

| | |
|---|---|
| Commits since `v0.26.4` | 1,268 |
| PR merges | 238 |
| Contributors | 8 (545 commits delano, 99 claude, 5 renovate, 19 others) |
| Files changed | 1,414 |
| New test files | 59 |
| Migrations | **0** |
| Breaking markers (`!`) | 0 |

Churn by area: locales 75,344 lines (largely generated — it is why the raw
diffstat looks enormous), code 34,819, tests 28,974, docs 10,530.

Resolved dependency moves, from the lockfile rather than the manifest
constraints: `otto` 2.6.0 → **2.8.0**, `rodauth` 2.44.0 → 2.45.0, `rodauth-tools`
0.4.0 → 0.4.1, `tryouts` 3.7.1 → **4.0.0.pre1**, `json` 2.21.1 → 2.21.2,
`aws-sdk-sesv2` 1.103.0 → 1.105.0, `aws-partitions` 1.1270.0 → 1.1277.0.

Zero conventional `!` markers against a release that renames two env vars and
changes the semantics of five more: anything automating off commit metadata will
under-read this release's operator impact. Not a blocker; a note for whoever
builds that automation.

## Risk register

| Risk | Severity | Why it matters for this release |
|---|---|---|
| Three unfixed High authorization findings ship (H-1 org-member secret bearer-token harvest, H-2 non-owner reaches the org's Stripe portal, H-3 tenant SSO `allowed_domains` never enforced) | **High** | Verified still present at `58df007ee`: `customer_portal_redirect` is routed `auth=sessionauth` with no ownership check, and `SsoConfig#valid_email_domain?` has no runtime caller outside specs. H-3 is the worst kind — a control that exists in the UI, the API and the docs but not at runtime, so operators believe they have domain restriction and do not. Being fixed on a separate branch; the tag should wait for them or the release notes must say the controls are not in force. |
| otto 2.6.0 → 2.8.0 under a trusted-proxy / host-detection rewrite | **High** | The framework carrying routing, middleware and host detection moved a minor series, and this release's proxy work sits on its new tri-state peer-trust key (`otto.via_trusted_proxy`). Blast radius is every request. Metadata cannot tell you whether it holds; a staging tier behind a real proxy for a day can. |
| Three gates now answer the same `404` | **Medium** | Admin host, admin CIDR, and the new per-domain sign-in/sign-up opt-ins all reject as not-found (per ADR-034). An operator seeing a `404` gets no signal about which fired. Remedy exists — the boot log names each active gate — but only if the upgrade guide tells them to look, which it now does. |
| `BILLING_ENABLED` / `STRIPE_AUTOMATIC_TAX` can flip on at upgrade | **Medium** | Both moved from `== 'true'` to the strict parser. `BILLING_ENABLED=1`, `yes`, `on` or `TRUE` was **off** in v0.26.4 and is **on** in v0.26.5. Verified against `git show v0.26.4:lib/onetime/billing_config.rb`. Operators who wrote a truthy-looking token get billing surfaces they did not have. Remedy: set the literal `false`. |
| Boot now raises on an unrecognized boolean for those three flags | **Medium** | `BILLING_ENABLED=enabled` is a hard `Onetime::ConfigError` where v0.26.4 silently read it as false. Correct behaviour, and the error message is careful not to echo the value — but it turns a silent misconfiguration into a failed deploy, which is exactly when operators are least happy to discover it. |
| Admin host gate self-disables on a non-routable anchor | **Low–Med** | With `HOST=localhost:3000` or a bare IP, no host gate applies at all and boot says so loudly. Deliberate and correct, but it makes "the gate is now active" conditional, and an install on a bare IP gets none of the protection the release notes advertise. |
| Fail-closed operator-host classification can withhold sign-in on a subdomain | **Low–Med** | While the custom-domain datastore is unreachable, a recognized operator **subdomain** classifies too late and is held to the default-OFF custom-domain resolver. The canonical host is unaffected. Correct direction; worth knowing before diagnosing it live during a datastore incident. |
| `tryouts` 4.0.0.pre1 in the test harness | **Low** | A pre-release dependency runs part of the suite, so a green run means slightly less than it usually does. Not a runtime risk — it does not ship. |
| Renamed `WEBAUTHN_*` env vars | **Low** | Registered as soft (`:warn`) deprecations in `lib/onetime/config.rb`, so they log rather than fail the boot even under the default `DEPRECATED_CONFIG_MODE=strict`. Passkey features silently stay off until renamed. |

## What's working well

- **No migration, no bulk transform.** Rollback is pinning the old tag. This is
  the single largest de-risker in the release and it holds after checking both
  `bin/ots migrate` and `scripts/upgrades/`.
- **Test investment tracks the code.** 59 new test files and near-1:1 test churn.
- **The security work the release advertises is real.** The 2026-08-14 review
  verified all four of the release's own security claims against a booted
  instance at the RC commit, including the admin gates' unreadable-vs-unset
  sentinel — the distinction between failing closed and failing open, handled
  correctly.
- **Config errors do not leak secrets.** The strict boolean reader reports a
  character count and a truncated SHA-256 rather than the offending value,
  because these variables sometimes hold credentials.
- **Fail-closed choices are documented at the point of decision.** ADR-024 and
  ADR-034 state the availability cost rather than leaving it to be discovered.

## Recommended before tagging

1. Land or explicitly accept H-1, H-2 and H-3. If accepted, the release notes
   should say the tenant SSO domain allowlist is not enforced — operators
   currently believe it is.
2. Soak the otto 2.8.0 + trusted-proxy combination on a staging tier behind a
   real proxy. This is the only item metadata analysis genuinely cannot answer.
3. Confirm CI is green on `58df007ee`.
4. Boot once with `ADMIN_ALLOWED_CIDRS` set to a deliberately bad value and
   confirm the deny path and log lines still match what the upgrade guide
   promises.
5. Bump `package.json` `version` at build time as usual — it is `0.0.0-rc0` in
   the tree and `Onetime::VERSION` reads from it.

## What this rests on, and what it could not see

Derived from git metadata, the config surfaces (`etc/defaults/*.yaml`,
`.env.reference`, `lib/onetime/config.rb`, `lib/onetime/utils/strings.rb`), the
lockfiles, and `docs/security/2026-08-14-appsec-review/`. Every config claim above
was traced to a parser or an ADR rather than to the changelog, and the boolean
behaviour was diffed against `v0.26.4` directly rather than against an
intermediate commit.

Not checked: CI run status, PR review threads, and the contents of individual
diffs beyond the files named. The three High findings were re-verified as present
by reading the current code, not by re-running the review's proof-of-concept
scripts.
