# SAML review resolutions

All ten items from `review-itms-opus55.txt` are resolved. No PR was created.

## Dispositions

| Item                                   | Resolution                                                                                                                                                                                                                              | Commit                     |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| 1. Platform fallback assertion capture | Platform SAML stays on its registered ACS host; custom-domain fallback is refused in runtime, advertising and callback Origin policy. Unavailable SSO does not reopen restricted password routes. Native tenant SAML remains supported. | `83d1a339a5`               |
| 2. Global SameSite=None requirement    | Bound, short-lived POST staging followed by a 303 GET recovers the original Lax session; authentication remains session/request-bound and single-use.                                                                                   | `63682d9736`               |
| 3. Persistent-only NameID              | Validated platform and tenant NameID policy settings, including explicit omission; identity-stability checks retained.                                                                                                                  | `bc25c76b37`               |
| 4. Callback Origin interoperability    | Tenant-specific exact HTTPS origins; separately, default-deny operator-only `SAML_ALLOW_NULL_ORIGIN=true` for eligible SAML callbacks.                                                                                                  | `bc25c76b37`, `27fd791893` |
| 5. Unsupported ECDSA                   | RSA public-key validation at setup and runtime RSA-only algorithm allowlist; legacy configuration recovery retained.                                                                                                                    | `69fe681de8`               |
| 6. Optional Conditions expiry          | Replay retention uses signed bearer confirmation expiry, including successive windows, capped by Conditions when present.                                                                                                               | `262d92dc5f`               |
| 7. Repeated certificate parsing        | Bounded parsed-certificate cache; both certificate validity bounds and other configuration remain live. No performance gain is claimed without a benchmark.                                                                             | `8bf8814c88`               |
| 8. Repeated origin decryption          | Request-scoped reuse, not persistent plaintext policy or cross-request stale caching.                                                                                                                                                   | `c1ce0f66f7`               |
| 9. Repeated exclusivity rule           | Shared provider-field builder, preserving PATCH omission and provider-switch behavior.                                                                                                                                                  | `2ea7d8af7e`               |
| 10. Repeated URL redaction             | One dependency-free primitive shared by banner, utilities and standalone database loading; distinct masking policies retained.                                                                                                          | `5cfecd2b42`               |

Additional review findings resolved: successive-window replay, password-route reopening, Sentry datastore capture, and Caddy callback query/Location logging (`19a8049a87`). Formatting is separate (`f32a3334b6`).

## Validation of completed code

All Ruby tests used `tests/lanes/run` with `.test-mode` already present.

- Complete unit lane: 8,422 Tryouts cases; RSpec legs 6,786 + 6,438 + 64 examples, zero failures, 79 pending across the RSpec legs.
- Complete full-SQLite lane: 2,210 examples, zero failures, 28 pending.
- Complete platform-SAML lane: 29 examples, zero failures.
- Domain SSO API integration: 196 examples, zero failures.
- Final targeted frontend contracts/composable: 139 tests passed; type-check passed. Earlier broader SSO frontend sweep: 445 passed, 18 skipped.
- Real Chromium transport harness: Lax and None complete; Strict refuses; POST cookie isolation, replay and no-referrer controls pass.
- Real Caddy example adaptation and live redaction regression passed on Caddy 2.11.4.
- Normal commit hooks passed. Intermediate commits received syntax/patch inspection and hooks, not isolated complete test runs.

The initially failing Origin fixture was aligned with classified-host requirements without relaxing the guard. The standalone database regression was fixed by keeping the shared redactor outside the application namespace. New lint warnings were removed. Full unit and SQLite runs above are after these fixes.

## Explicit limits and deployment actions

- Firefox/WebKit were unavailable. Deployed proxy/APM configuration and remote Sentry ingestion were not tested. PostgreSQL/MFA/billing overlays were not run.
- Staging has an aggregate memory/write bound and returns 429 under saturation. Multi-source exhaustion is an accepted fixed-capacity limitation, not a claim of tenant availability isolation. Existing handles remain redeemable. See `docs/authentication/saml-callback-transport.md` for capacities and ingress controls.
- Remove tenant ACS registrations from the platform IdP. Custom domains need their own SAML provider.
- Apply equivalent callback-query/body/Location filtering to deployed ingress logs; updating an example does not update production.
- Null-Origin admission requires explicit operator opt-in; defaults remain unchanged.

## History and ownership

Work started at `eb0732996d`. Another workflow advanced the branch to `ea819f00ef` during implementation; that history was preserved. The focused commit series appends to it. No amend, rebase, restore, branch creation or force push was used by this workflow. Temporary agent handoffs were removed after consolidation; ignored test logs remain under `tmp/`.
