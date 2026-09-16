# Tenant Connect system test

`connected-identities-custom-host.spec.ts` is a dedicated security-acceptance journey. It is excluded from the normal Playwright projects and appears only when `E2E_TENANT_CONNECT_ARMED=1`.

The target must be a disposable full-auth test process with:

- domains and organization SSO enabled;
- one custom domain with password and OIDC sign-in enabled;
- two open accounts with unsuspended Customers and active exact-domain memberships;
- no identity on either account before the run;
- one test OIDC tuple that the first account can bind and the second account then conflicts with.

Three files in this directory are the whole harness:

| File                                       | Role                                                                                                                                                                                                                                                               |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `tenant_connect_test_boot.rb`              | Boot shim for the **server** process only (`RUBYOPT=-r`). Enables OmniAuth test mode with the `E2E_TENANT_CONNECT_*` tuple and opens the otherwise hard-coded tenant Connect release gate in that one process. Refuses to load outside an armed test env.          |
| `tenant_connect_seed.rb`                   | Seeds the organization, custom domain, `SsoConfig` + `SigninConfig`, the two password accounts, their exact-domain memberships, and clears any identity for the tuple. Also migrates the authdb (the `RodauthMigrations` initializer skips under `RACK_ENV=test`). |
| `connected-identities-custom-host.spec.ts` | The journey. Runs under the `tenant-connect` project, which maps `*.example.com` / `*.example.org` to `127.0.0.1` via Chromium's host resolver.                                                                                                                    |

## Local run

Prerequisites: the test Valkey on `127.0.0.1:2163` (`podman compose -f compose.test.yml up --wait -d valkey`), seeded `etc/*.yaml` (`bin/setup` copies them from `etc/defaults/`), built assets (`pnpm run build`), and the pinned Chromium (`pnpm exec playwright install chromium`). Nothing listening on `:7143`.

One environment for all three processes. Pick a Valkey DB index that is not shared with another checkout (`ruby try/support/datastore_db.rb` prints this checkout's tryouts index):

```sh
export RACK_ENV=test LANG=en_US.UTF-8 SSL=false
export HOST=canonical.example.org:7143 DEFAULT_DOMAIN=canonical.example.org
export DOMAINS_ENABLED=true ORGS_SSO_ENABLED=true
export AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite://tmp/e2e-tenant-connect.db
export REDIS_URL="redis://127.0.0.1:2163/$(ruby try/support/datastore_db.rb)"
export EMAILER_MODE=logger JOBS_ENABLED=false BILLING_ENABLED=false
# Deterministic test dummies (tests/lanes/base.env): SECRET, SESSION_SECRET,
# AUTH_SECRET, ARGON2_SECRET, ACCOUNT_ID_SECRET. ARGON2_SECRET must be the
# same for the seed and the server — it is the password pepper.
export E2E_TENANT_CONNECT_ARMED=1
export E2E_TENANT_CONNECT_ORIGIN=http://tenant.example.com:7143
export E2E_TENANT_CONNECT_PROVIDER=oidc
export E2E_TENANT_CONNECT_UID=system-connect-subject
export E2E_TENANT_CONNECT_IDP_EMAIL=victim@example.test
export E2E_TENANT_CONNECT_ISSUER=https://idp.example.test
export E2E_TENANT_CONNECT_PASSWORD='TestPassword123!'
export E2E_TENANT_CONNECT_OWNER_EMAIL=owner@example.test
export E2E_TENANT_CONNECT_SECOND_EMAIL=member@example.test
```

Boot the armed server (the shim goes into this process and nowhere else; `bundle exec` puts `bundler/setup` ahead of it in `RUBYOPT`):

```sh
rm -f tmp/e2e-tenant-connect.db
RUBYOPT=-r./e2e/system/tenant_connect_test_boot.rb bundle exec bin/ots server --port=7143
```

Seed, then run. Seed **before every run**: the first journey binds the tuple, and a second run against the same datastore fails its own precondition (`connections-connect` is hidden once the identity exists) rather than passing vacuously. `PLAYWRIGHT_BASE_URL` stops the config's `webServer` from booting a second, un-armed server:

```sh
bundle exec ruby e2e/system/tenant_connect_seed.rb
PLAYWRIGHT_BASE_URL="$E2E_TENANT_CONNECT_ORIGIN" pnpm test:playwright --project=tenant-connect
```

The first browser test covers panel → `/reauth` → Connect initiation → callback success and asserts that the session cookie is host-only. The second account then attempts the same full tuple and proves the ownership refusal leaves its session unchanged and creates no identity.

Two facts the spec is written around:

- The Connect initiation that spends the login-time proof is issued from inside the page (`fetch` with `redirect: 'manual'`), not via `page.context().request`: the synthetic host resolves only through Chromium's `--host-resolver-rules`, which Playwright's Node-side request context does not consult.
- The callback's landing page is not asserted. Nothing in the auth app consumes the `redirect` field the panel posts with the SSO form, so a completed Connect lands on Rodauth's `login_redirect` (`/`); the spec observes the callback's 302 (no `auth_error`) and then opens the panel explicitly. `GET /auth/identities` masks the subject to `first4…last4`, and that masked form is what the panel assertions match.

## CI

`.github/workflows/e2e-tenant-connect.yml` runs this project on `workflow_dispatch` and on pull requests touching `e2e/system/**`, `e2e/support/**`, `e2e/playwright.config.ts`, `apps/web/auth/**`, `src/apps/workspace/account/**` or `src/shared/utils/sso-link-evidence.ts`. It is the same bare-metal shape as `e2e-full-auth.yml` (Valkey from `compose.test.yml`, `bin/setup`, `pnpm run build`, `bin/ots server` on the runner) with the lane env above provisioned once into `$GITHUB_ENV`, the shim injected through the boot step's `RUBYOPT`, a log assertion that the placeholder OIDC route registered, the seed script, the Playwright run, the shared flaky gate, and the report / traces / server log uploaded as artifacts. The production gate is never opened anywhere else.
