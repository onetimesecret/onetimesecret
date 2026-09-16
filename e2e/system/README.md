# Tenant Connect system test

`connected-identities-custom-host.spec.ts` is a dedicated security-acceptance journey. It is excluded from the normal Playwright projects and appears only when `E2E_TENANT_CONNECT_ARMED=1`.

The target must be a disposable full-auth test process with:

- domains and organization SSO enabled;
- one custom domain with password and OIDC sign-in enabled;
- two open accounts with unsuspended Customers and active exact-domain memberships;
- no identity on either account before the run;
- one test OIDC tuple that the first account can bind and the second account then conflicts with.

Load `tenant_connect_test_boot.rb` into that server process to enable OmniAuth test mode and open the otherwise hard-coded tenant gate only in the explicitly armed test process:

```sh
RACK_ENV=test \
E2E_TENANT_CONNECT_ARMED=1 \
E2E_TENANT_CONNECT_PROVIDER=oidc \
E2E_TENANT_CONNECT_UID=system-connect-subject \
E2E_TENANT_CONNECT_IDP_EMAIL=victim@example.test \
E2E_TENANT_CONNECT_ISSUER=https://idp.example.test \
RUBYOPT=-r./e2e/system/tenant_connect_test_boot.rb \
bundle exec puma config.ru
```

Run Playwright against the prepared target:

```sh
E2E_TENANT_CONNECT_ARMED=1 \
E2E_TENANT_CONNECT_ORIGIN=http://tenant.example.com:7143 \
E2E_TENANT_CONNECT_PROVIDER=oidc \
E2E_TENANT_CONNECT_UID=system-connect-subject \
E2E_TENANT_CONNECT_PASSWORD='test password' \
E2E_TENANT_CONNECT_OWNER_EMAIL=owner@example.test \
E2E_TENANT_CONNECT_SECOND_EMAIL=member@example.test \
pnpm test:playwright --project=tenant-connect
```

The first browser test covers panel → `/reauth` → Connect initiation → callback success and asserts that the session cookie is host-only. The second account then attempts the same full tuple and proves the ownership refusal leaves its session unchanged and creates no identity.
