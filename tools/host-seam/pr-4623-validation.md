# PR #4623: four-item review follow-up

Execution record for the HTTPS, tenant OAuth, SAML transport, and mounted-gem
review items. Baseline: `f19c15426e0a816e835be8836da6747b52332274` plus the
uncommitted changes described here. This record reports observed local results;
it is not an accepted security policy, live deployment approval, or a claim
that every authentication feature was exercised.

The earlier [follow-up record](follow-up-validation.md) describes a different
baseline. In particular, its unresolved H-02/H-05 dispositions are not the final
state of this work.

## Original items

| ID   | Item                                    | Technical disposition                                       | Evidence                                                                                                                                                                                                                                                                                                                                                                                                    |
| ---- | --------------------------------------- | ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| R-01 | HTTPS normalization and Secure sessions | Fixed; mounted regression coverage added                    | `AssumeHttps` policy fix is in `abe790e6d5`. Eighteen unit examples and eight `HP-HTTPS-01` full-app examples cover policy off/on, accepted/rejected proxy peers, rewrite off/on, actual Secure-cookie emission and persisted login sessions.                                                                                                                                                               |
| R-02 | Tenant SSO                              | New mounted callback coverage implemented and run           | Twenty-two OIDC callback examples verify real code exchange, PKCE, nonce/signature/issuer validation, wrong-state refusal, tenant-cookie replay, colliding subjects across issuers, identity/membership/session persistence, active organization and HTTPS public ports. Only provider HTTP/DNS responses are fixtures; OmniAuth test mode is off. The sixteen existing Entra initiation examples also run. |
| R-03 | SAML transport                          | Signed negative and transition matrices implemented and run | Eighty-three tenant-SAML and thirty-four staged-Connect examples cover cross-tenant signatures and handles, issuer impersonation, replay, revoked verification/configuration, signed ACS/audience/Recipient scheme-port binding, and both rewrite-setting transitions between POST and GET. Cryptographic verification, SQL and Valkey are real.                                                            |
| R-04 | Mounted consumers                       | Audited with full application and browser execution         | Session, cookie, Origin, recovery, SSO and failure-response suites run through the mounted application. Browser transport adds real host classification, domain resolution, sessions and rewriting to a production-middleware/strategy fixture. Unsafe authentication URL fallback was reproduced and fixed rather than retained as characterization.                                                       |

None of these technical dispositions substitutes for a human's final acceptance
of a deployment or for real-provider testing.

## Findings ledger

| ID                 | Finding                                                                                            | Final disposition                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| ------------------ | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| F-01 / H-05        | Missing `site.host` allowed request-derived credential-bearing reset URLs                          | Fixed. Rodauth and OmniAuth require the shared allowlisted origin. Optional inspection helpers retain their nil contract. Reset preflight runs after the request limiter but before account lookup/key writes; direct key creation is protected too. Nineteen integration examples cover missing/blank configuration, unreadable/unverified tenants, safe canonical/verified tiers, limiter ordering, enumeration parity and unchanged existing keys. H05 emitter rows now require no email or reset key. |
| QA-01              | Reset preflight introduced an unapproved prepended route-hook wrapper                              | Fixed at the owning hook. The sole registered reset-request hook performs limiter then origin resolution; its ownership guard is unchanged. Five runtime hook tests cover ordering, disabled limiter, limiter refusal, GET and disabled feature.                                                                                                                                                                                                                                                          |
| B-01               | Rewrite-off non-default-port Origin refusal                                                        | Characterized, not newly introduced. The merge-base already uses the port-less HTTPS display-host exception; the unit test explicitly expects appended-port refusal. Existing O05/O09 rows and the operations guide document off/refused, on/admitted. Browser controls retain the 403. Preserve public Host or enable the existing rewrite setting; no Origin policy expansion was made.                                                                                                                 |
| B-02               | WebKit could miss binding-probe navigation                                                         | Fixed. IdP navigation and bounded server synchronization ensure all twelve binding probes execute, with structured per-case evidence.                                                                                                                                                                                                                                                                                                                                                                     |
| B-03               | A descendant retained output pipes after the Node parent exited                                    | Reproduced and fixed. The deadline includes pipe reads, teardown kills the process group and bounds reader joins. A failure-injection example verifies it.                                                                                                                                                                                                                                                                                                                                                |
| B-04               | Partial browser fixture setup could leave a persisted domain/listener                              | Reproduced and fixed. Cleanup covers partial setup, listeners, proxy workers, callback gate, run-scoped records and manually changed global state. A failure-injection example verifies it.                                                                                                                                                                                                                                                                                                               |
| S:G-01–04          | Signed SAML isolation, replay, revocation, authority and transition coverage gaps                  | Addressed by the new mounted matrices. No production defect was reproduced in these paths.                                                                                                                                                                                                                                                                                                                                                                                                                |
| O:T-01–03 / S:T-01 | Fictional DNS, URI matching/SQL cleanup, session-metadata assertion and scheme-test fixture errors | Corrected in test fixtures and retested. Initial failures are not counted as passing evidence.                                                                                                                                                                                                                                                                                                                                                                                                            |
| L-01 / O:V-01      | Existing-spec RuboCop RSpec/style findings                                                         | Baseline findings are retained; explicitly passing lint checks below do not claim full style compliance for existing integration specs.                                                                                                                                                                                                                                                                                                                                                                   |
| O:V-02             | Baseline advanced during the first delegated runs                                                  | Revalidated against `f19c15426e` and the combined working tree. No commits were created by this follow-up session.                                                                                                                                                                                                                                                                                                                                                                                        |

H-02's organization-selection changes were already committed separately in
`f3b6f672c6`, `8107626aac` and `f19c15426e`; the full unit lane exercises the
current selection/cache scope tests. This does not close the separate existing
organization-wide audit-list risk recorded in the security risk register.

H-03's matching invalid-display-host Origin admission remains characterized:
Origin admission alone does not establish protected-route access. The mounted
session/mutation, recovery, SSO and admin refusals remain tested. No general
unknown-host Origin-policy redesign or operator acceptance is inferred.

H-04's injected lookup errors still refuse credential emission and retain the
existing failure-response contract. Passing tests do not establish outage
frequency, natural unexpected-error triggers, or eliminate datastore outages.

## Final execution

All Ruby tests used `tests/lanes/run` with the existing `.test-mode` sentinel.
The runner isolates the lane datastores and environment. Commands were bounded;
none of the final runs timed out.

```sh
tests/lanes/run unit
tests/lanes/run full-sqlite --quiet
tests/lanes/run full-pg-agnostic --quiet
tests/lanes/run browser --quiet
```

| Final run                           |                            Examples/cases | Failures |                 Pending |
| ----------------------------------- | ----------------------------------------: | -------: | ----------------------: |
| Unit Tryouts                        |                   8,559 passed, 375 files |        0 | Not separately reported |
| Unit RSpec, all three tasks         |                                    15,427 |        0 |                      75 |
| Full SQLite, seed 46034             |                                     2,864 |        0 |                      28 |
| Full PostgreSQL-agnostic, seed 4008 |                                     2,828 |        0 |                      28 |
| Browser, seed 30330                 | 3 RSpec examples, 66 browser matrix cases |        0 |                       0 |

All final commands exited 0. The unit lane initially failed QA-01; the ownership
fix and complete rerun are reflected above. The new coverage has no pending
examples. Existing unit pending cases concern homepage/CIDR, billing, invite and
v1/v2 tests. Existing application-lane pending cases concern lockout/CSRF setup,
disabled billing, MFA, email-auth, WebAuthn, verification-email features and the
SSO-disabled-route branch. Those are not executed coverage.

The browser matrix reports 22 passed cases per engine: Chromium, Firefox and
WebKit. It includes twelve wrong-session/wrong-host probes, forty-two replay
checks, fifteen Strict-cookie refusals, six callback-policy refusals and three
B-01 compatibility controls. Counts overlap because a matrix case can contain
multiple assertions. The two extra RSpec examples test timeout and cleanup.

Execution logs are local, ignored artifacts:

- `tmp/lanes/unit/base/last.log`
- `tmp/lanes/full-sqlite/base/last.log`
- `tmp/lanes/full-pg-agnostic/base/last.log`
- `tmp/lanes/browser/base/last.log`

Additional final checks passed: `rubocop --lint` on all fourteen changed/new
Ruby files; scoped full RuboCop on the new specs and browser harness; Node syntax
and Prettier checks on `tests/browser/saml_callback.mjs`; local Markdown link
checks on this record and the operations guide; and `git diff --check`. The lint
result does not erase the existing integration specs' RSpec/style findings.

## Limits and deployment acceptance

- Browser evidence uses local TLS and production middleware/strategy components,
  not the full Rodauth application. Its lane has no auth SQL database; tenant
  strategy registration is fixture-provided, platform SSO availability is
  overridden, and initiation CSRF validation is disabled. Full-app SQL identity,
  tenant authorization and initiation protection are covered separately by the
  mounted Ruby suites, not established by this browser fixture.
- The signed local SAML fixture and mocked OIDC endpoints are not a real external
  IdP or Entra token exchange. External email delivery was not performed.
- This session did not exercise deployed ingress, multi-worker rollout, direct
  origin exclusion or HTTP/2–3 translation. No remote target, operator credentials
  or staging configuration was supplied. Live verification requires those inputs.
- The separate PostgreSQL-tagged `full-pg` lane and billing/MFA overlays were not
  run; `full-pg-agnostic` did run against PostgreSQL.
- Existing public-authority Origin differences remain documented. Enabling
  `ASSUME_HTTPS` treats requests as HTTPS by operator policy; this execution does
  not approve direct HTTP reachability or proxy trust configuration.

Use the [operations guide](../../docs/operations/proxy-authority-header.md) for
configuration, Origin differences and the SAML rollout order. Final human and
live-deployment acceptance remains separate from completed repository changes
and local automated validation.
