# v0.26.5 release readiness

**Baseline:** `v0.26.4` (2026-08-05) · **Analysed at:** `58df007ee` (= `origin/main`,
2026-08-16) · **Prior tag in this line:** `v0.26.5-rc1` (`21c3f6a`, 2026-08-13)

`v0.26.5-rc1` is three days behind the commit this assessment covers. Everything
below describes `58df007ee`, not the RC.

**Updated 2026-08-18.** `main` has since moved to `03277fa36`, which carries #4196 —
the three High authorization findings are now closed. The risk register below
reflects that; the volume figures still describe the `58df007ee` window.

**`v0.26.5-rc1` has been running in production for several days.** That is the
most valuable single input to this assessment, and it moves the picture — but it
covers the RC's tree, not this one. The section below draws the line.

> **Correction to the first version of this document.** It named the otto
> 2.6.0 → 2.8.0 jump as the release's largest unknown and asked for a staging
> soak. That was wrong in a way worth being explicit about: the bump and the
> entire trusted-proxy rewrite landed **before** the RC tag
> (`git show v0.26.5-rc1:Gemfile.lock` → `otto (2.8.0)`), so production has
> already soaked it under real traffic behind a real proxy. That risk is
> retired. The unsoaked surface is the rc1 → HEAD delta, which is a different
> and smaller set of changes — but not an empty one.

## Verdict: ship with conditions

Nothing in the release window argues for holding the tag on its own merits.
There is no schema migration and no bulk data transform, so rollback is a tag
swap — the single biggest de-risker available. Test churn ran close to 1:1 with
code churn (28,974 test lines against 34,819 code lines, 59 new test files),
which is the strongest evidence in the metadata that this was developed with
tests rather than tested afterward. The heaviest single change in the release —
otto 2.8.0 under the proxy and host-detection rewrite — now has days of
production behind it.

One condition remains. The three High authorization findings carried from the
2026-08-14 review are **closed** — #4196 landed H-1, H-2 and H-3, and each was
verified in the merged code. What remains is the rc1 → HEAD delta, which is where
the unknown now sits. Note that two of the three fixes fail closed in ways an
operator will notice on day one; they are covered in the upgrade guide and the
deployment notes rather than left to be discovered.

## What production has soaked, and what it hasn't

`v0.26.5-rc1` → `58df007ee` is **3,387 insertions and 421 deletions of runtime
code across 47 files**, excluding tests, docs and locales. Grouped by what it
touches:

| Group | Size | Unsoaked risk |
|---|---|---|
| Middleware registry + per-app profiles (`application/registry.rb`, `middleware_profile.rb`, `middleware_stack.rb`, `middleware/registry.rb`, `security.rb`, `http_origin_options.rb`, and the auth/ACME/core app boots) | 515 / 174 | **Highest.** This is a request-path rewrite applied to every app, including how security middleware is selected per profile. It is the change most likely to fail in a way rc1's soak says nothing about. |
| Full-mode per-domain auth gates (`signin_enabled.rb`, `signup_enabled.rb`, `signin_gate.rb`, `restrict_to.rb`, the `before_rodauth` hooks, `signin_config.rb`, `config_serializer.rb`) | 1,307 / 118 | **High.** New fail-closed gates on live auth routes. The failure mode is a customer who cannot sign in, and it is config-dependent, so a synthetic check on the canonical host will not see it. |
| Session metadata, geo country, `SafeDumpable` (`session_metadata.rb`, the `sessions/` operations, the Colonel session surfaces, sign-in alert templates) | 232 / 39 | Moderate. Mostly additive and read-path; the join-key change alters what a signed-in user sees on their sessions list. |
| SSO JIT verification (`omniauth.rb`, `create_customer.rb`, customer status) | — | Moderate. Changes what an SSO signup writes at creation. |
| Test harness, lanes, rake tasks | ~1,300 | None at runtime. |

The security consequence deserves its own line. The 2026-08-14 review's release
addendum states that `v0.26.5-rc1` is "the exact commit the review was performed
against" and that there is "no delta to audit." **That guarantee expires at the
RC.** A stable tag cut at `58df007ee` ships ~3,400 lines of runtime code the
review has not seen, including two new authorization gates. That is not a reason
to hold — the gates are narrowing and well-documented — but the release should
not inherit the RC's clean-review framing.

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
| ~~Three unfixed High authorization findings ship~~ **Closed by #4196** | ~~High~~ **Low** | H-1, H-2 and H-3 all landed in `main` after this assessment was first written, and each was verified in the merged code: `ListReceipts` gates `scope=org` on the `audit_logs` entitlement and redacts non-owned capability tokens; `customer_portal_redirect` gates on ownership (with the reasoning that `default_org_id` is not proof of ownership — `JoinDomainOrganization` repoints it for plain members); and `enforce_tenant_email_domain!` now actually calls `valid_email_domain?` on the OmniAuth callback. **Two of the three carry operator impact and are documented in the upgrade guide (step 5) and the deployment notes:** an enforced tenant SSO allowlist can lock out users of a tenant whose list is stale, and org-scope receipts return 403 on billing-enabled installs until a plan grants `audit_logs`. |
| ~~otto 2.6.0 → 2.8.0 under a trusted-proxy / host-detection rewrite~~ **Retired** | ~~High~~ **Low** | Both the bump and the proxy rewrite are in `v0.26.5-rc1`, which has run in production for several days behind a real proxy. The soak this row asked for has happened. Retained struck through so a reader of the earlier version knows the assessment changed rather than wondering if they misremembered. |
| Middleware registry rewrite is unsoaked | **High** | 515 lines across the application-boot and middleware layers of every app, landed after the RC. It changes how the middleware stack is assembled and how security middleware is selected per app profile — the request path itself, on the one part of the release production has *not* exercised. Remedy: this is the change to put in front of real traffic before tagging, or the reason to cut the tag at rc1's tree instead. |
| New full-mode auth gates are unsoaked | **High** | 1,307 lines of new fail-closed gating on live sign-in, sign-up and account-creation routes, all after the RC. The failure mode is a paying customer who cannot sign in, it is config-dependent, and a synthetic check against the canonical host will not surface it — operator hosts are exactly the case the gates leave alone. Remedy: sign in once on each custom domain that serves passwords, per the upgrade guide's Verify step 4. |
| A stable tag at HEAD is outside the security review's scope | **Medium** | The 2026-08-14 addendum certifies `v0.26.5-rc1` as "the exact commit the review was performed against." A tag at `58df007ee` adds ~3,400 lines of unreviewed runtime code including two new authorization gates. Not a hold — but the release notes should not carry the RC's clean-review framing, and the next review should start from this delta. |
| Three gates now answer the same `404` | **Medium** | Admin host, admin CIDR, and the new per-domain sign-in/sign-up opt-ins all reject as not-found (per ADR-034). An operator seeing a `404` gets no signal about which fired. Remedy exists — the boot log names each active gate — but only if the upgrade guide tells them to look, which it now does. |
| ~~`BILLING_ENABLED` / `STRIPE_AUTOMATIC_TAX` can flip on at upgrade~~ **Reframed** | ~~Medium~~ **Low** | The earlier wording implied a default could flip. It cannot — **billing is disabled by default with no exception**, verified along the whole chain at HEAD: unset falls to `config['enabled']` with `default: false`; a blank or whitespace value resolves to `false` and deliberately does *not* fall back to the config file; a missing `billing.yaml` is `false`; an unrecognized token raises rather than enabling; and `billing_enabled?` rescues any `BillingConfig` failure to `false`. The real change is narrower: an operator who explicitly wrote `BILLING_ENABLED=1` **meaning to enable billing** was silently ignored on v0.26.4 and now gets what they asked for. That is the old behaviour being the surprising one. Worth a release note because an install may have been running with billing off despite a config that says on — not because anything turns on by itself. |
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

1. ~~Land or explicitly accept H-1, H-2 and H-3.~~ **Done** — #4196. Both
   operator-visible consequences (an enforced tenant SSO allowlist, and
   `audit_logs` now required for org-scope receipts) are documented.
2. Decide what to do about the unsoaked delta. Either put the middleware registry
   rewrite and the new full-mode auth gates in front of real traffic, or cut the
   stable tag at rc1's tree and ship the delta as v0.26.6. Production has soaked
   the RC, not this commit.
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
