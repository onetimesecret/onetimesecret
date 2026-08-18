# Upgrading to v0.26.5

v0.26.5 tightens several gates that previously degraded permissively. Nothing in
this release adds a schema migration or a bulk data transform, so **rollback is a
tag swap** — but three of the tightened gates produce the *same* symptom (a
`404`), one config-parsing change starts honouring a flag that was previously
ignored, and SSO installs need a one-time repair afterwards. Those are the
reasons to read this before upgrading rather than after.

Coming from a version older than v0.26.0? Work through the earlier upgrade
guides first; this one only covers the v0.26.4 → v0.26.5 step.

## Before You Start

1. Back up your datastore. There is no migration, but there is no substitute
   either.
2. Record the tag you are on (`docker image inspect`, or your deploy manifest).
   Rollback is pinning it again.
3. Gather these four facts — every step below needs at least one of them:
   - The hostname you use to reach `/colonel`.
   - Whether your origin sits behind a proxy or CDN, and which one.
   - The exact values of `BILLING_ENABLED`, `STRIPE_AUTOMATIC_TAX` and
     `RABBITMQ_VERIFY_PEER` in your environment, if set.
   - Whether any custom domain in your install serves password or magic-link
     sign-in.
   - Whether any of your admins or colonels were provisioned through SSO.

## What Changes

| Area | Change | Action required? |
|---|---|---|
| Admin host gate | `/colonel` and `/api/colonel` are restricted to the canonical `HOST`/`DEFAULT_DOMAIN` (+ `www.`) unless `ADMIN_ALLOWED_HOSTS` says otherwise | **Yes**, if you reach Colonel by any other hostname |
| Admin network gate | `ADMIN_ALLOWED_CIDRS` with no parseable entry now denies both admin surfaces instead of ignoring the setting | **Yes**, if the variable is set at all |
| Per-domain sign-in / sign-up | Full mode now enforces each custom domain's own opt-in on password and magic-link routes, and the sign-up opt-in on account creation | **Yes**, if a custom domain relies on password or email sign-in |
| Operator-host classification | Global sign-in/sign-up defaults apply only to hosts positively classified `:canonical` or `:subdomain`; anything else takes the default-OFF resolver | Only if you serve on an operator **subdomain** — see the caution below |
| Boolean parsing | `BILLING_ENABLED`, `STRIPE_AUTOMATIC_TAX`, `RABBITMQ_VERIFY_PEER` accept the full `1/true/yes/on/y/t` vocabulary and **raise at boot** on anything unrecognized | **Yes**, if any of the three is set to something other than `true`/`false` |
| Geo | `GEO_HEADER` is honoured only in `TRUSTED_PROXY_MODE=filter`; depth-mode and direct-connect installs need `GEO_DB_PATH` | Only to keep session country resolving |
| Passkey flag names | `WEBAUTHN_VERIFY_ACCOUNT` / `WEBAUTHN_AUTOFILL` renamed to `AUTH_WEBAUTHN_*` | Rename when convenient — the old names log a warning and are ignored |
| Tenant SSO `allowed_domains` | The per-tenant SSO email-domain allowlist is now enforced on the callback. It was never called at runtime before, so every allowlist was inert | **Yes**, if any tenant has one configured — a stale list now locks its users out |
| Org-scope receipts | `GET /receipt/recent?scope=org` now requires the `audit_logs` entitlement | **Yes** on billing-enabled installs — the shipped catalog grants it in no plan |
| SSO-provisioned admins | Customers created just-in-time through SSO were written unverified, which blocks their role. New signups are fixed; existing records need a one-time repair | **Yes**, if you use SSO — see After Upgrading |
| V1 API anonymous TTL | Anonymous secret creation through the V1 API is capped at the configured anonymous ceiling (default 7 days) instead of falling through to the 30-day global one | Only if anonymous V1 clients request longer expiries |
| Custom-domain `HttpOrigin` | 403s on custom domains are fixed; middleware is assembled from a registry with per-app profiles and `MIDDLEWARE_AUTH_*` toggles | Remove any workaround you added for those 403s |
| Sessions list | The account "active sessions" list starts showing IP, browser and country | No — it fills in as users re-authenticate |

## The Upgrade Checklist

Ordered by dependency: the proxy answer decides the admin-host answer, and both
decide which `404` you are looking at if something goes wrong.

### 1. Settle proxy trust first

Forwarded-host trust is what makes the admin host gate see the hostname your
users type rather than the one your proxy dials. If `TRUSTED_PROXY_ENABLED` is
not `true`, `TRUSTED_PROXY_MODE`, `TRUSTED_PROXY_CIDRS` and `TRUSTED_PROXY_DEPTH`
are inert regardless of what they contain.

```bash
TRUSTED_PROXY_ENABLED=true
TRUSTED_PROXY_MODE=filter            # or depth
TRUSTED_PROXY_CIDRS=10.0.0.0/8       # filter mode: your proxy/CDN ranges
```

> **Caution.** `filter` mode with no CIDRs trusts nothing, so forwarded hosts
> stay untrusted and the admin gate sees only the connecting host. If you cannot
> enumerate your proxy's ranges, have the proxy forward the original `Host`
> header instead.

If you were working around the pre-0.26.5 depth miscount by inflating
`TRUSTED_PROXY_DEPTH`, restore the real value — the `+1` that double-counted the
connecting peer is gone (#4024).

### 2. Set `ADMIN_ALLOWED_HOSTS` if Colonel is not on the canonical host

| Your Colonel hostname | Result after upgrade |
|---|---|
| `HOST` / `DEFAULT_DOMAIN`, or its `www.` sibling | Works unchanged |
| An internal hostname, a `LINK_DOMAINS` entry, a tenant custom domain | **404** until you list it |
| A bare IP or `localhost` | Gate self-disables — see the caution |

```bash
ADMIN_ALLOWED_HOSTS=admin.example.com,secrets.example.com
# ADMIN_ALLOWED_HOSTS=*   # disables the host restriction entirely
```

> **Caution.** The host gate needs a routable anchor. With `HOST=localhost:3000`
> or a bare IP, boot logs `Admin host allowlist INACTIVE: no routable hostname
> configured` and **no host gate applies at all**. That is deliberate — it keeps
> such installs from locking themselves out — but do not read "the gate is now
> active" as universal. Set a routable `site.host`, or an explicit
> `ADMIN_ALLOWED_HOSTS`, if you want the gate.

### 3. Only if `ADMIN_ALLOWED_CIDRS` is set: verify every entry parses

An allowlist whose entries are all unparseable used to mean "no network
restriction". It now denies both admin surfaces.

```bash
ADMIN_ALLOWED_CIDRS=100.64.0.0/10,10.0.0.0/8
```

Boot logs one `WARN` per rejected entry and an `ERROR` if none survive. Unset the
variable entirely if you did not mean to restrict by network.

### 4. Only if custom domains serve password or magic-link sign-in: confirm the opt-ins

ADR-024 makes custom domains default-OFF for password and email sign-in; the
domain owner opts in with an enabled `SigninConfig`. That was already enforced in
simple mode, on the display surfaces and in the settings API — full mode (where
Rodauth serves those routes) did not consult it, so a domain that had never
opted in could still complete a password sign-in. It is enforced now.

Registration is gated separately, on the sign-up opt-in. An SSO-only tenant with
open self-service registration keeps a working `create-account` route.

SSO is deliberately not gated by these flags, so tenant SSO sign-in is
unaffected.

### 5. Only if you use tenant SSO or org-scope receipts: check the two newly enforced controls

Both closed High findings from the 2026-08-14 security review (#4196), and both fail
closed — an install that was quietly relying on the gap sees the change immediately.

**Tenant SSO `allowed_domains`.** The allowlist existed in the model, the UI, the API
and the docs, but nothing called it at runtime, so no tenant's list was ever applied.
It is enforced on the OmniAuth callback now.

> **Caution.** If a tenant's allowlist is stale, incomplete or was configured
> aspirationally while it was inert, **their users stop being able to sign in on
> upgrade.** Review each tenant SSO allowlist first.

An empty allowlist remains the documented allow-all state. An unreadable one denies
rather than degrading to allow-all. Denials surface as
`auth_error=domain_not_allowed` and emit `:omniauth_tenant_domain_rejected`, distinct
from the signup-domain denial, so you can tell the two apart in the audit trail.

**Org-scope receipts.** `GET /receipt/recent?scope=org` returns receipts created by
*other* org members, so it is now gated at the same `audit_logs` entitlement as the
sibling org-wide audit surface.

| Your install | Result |
|---|---|
| Standalone / billing disabled | Unaffected — `STANDALONE_ENTITLEMENTS` already includes `audit_logs` |
| Billing enabled | **403 for every role, owners included**, until a plan grants `audit_logs` |

On a billing-enabled install, entitlements come from the plan catalog, and the shipped
example catalog defines `audit_logs` without granting it in any plan. Grant it on the
plans that should have org-wide visibility.

### 6. Normalize the three strict-parsed booleans

```bash
BILLING_ENABLED=true          # was: only the literal 'true' counted
STRIPE_AUTOMATIC_TAX=false
RABBITMQ_VERIFY_PEER=true
```

Two distinct consequences, and only one of them is a boot failure:

- **A truthy token you set deliberately is no longer ignored.**
  `BILLING_ENABLED=1` (or `yes`, `on`, `TRUE`) was **off** in v0.26.4 and is
  **on** in v0.26.5. Same for `STRIPE_AUTOMATIC_TAX`. Billing itself is still
  **disabled by default and unconditionally**: unset, blank, and a missing
  `billing.yaml` all resolve to off, and an unrecognized value raises rather than
  enabling. Nothing turns on by itself — but if your config has said billing is
  on while your install behaved as though it were off, it will now behave as
  configured.
- **A typo now stops the boot.** `BILLING_ENABLED=enabled` raises
  `Onetime::ConfigError`. The message names the flag, the character count and a
  truncated SHA-256 — never the value, since these variables sometimes hold
  secrets.

`RABBITMQ_VERIFY_PEER` moves in the safe direction: it defaults ON, and values
like `1`, `yes` or `TRUE` previously **disabled** TLS peer verification. They now
enable it. If you were relying on that to talk to a RabbitMQ node with an
untrusted certificate, set `RABBITMQ_VERIFY_PEER=false` explicitly and plan to
fix the certificate.

> **Caution.** This vocabulary covers **only these three variables.** Every other
> `*_ENABLED`-style flag is still read in the template as a literal string
> comparison, and the two classes behave differently in opposite directions:
> flags written `== 'true'` (for example `AUTH_WEBAUTHN_AUTOFILL`) are enabled by
> the literal `true` and nothing else, while flags written `!= 'false'` (for
> example `API_ENABLED`, `CSP_ENABLED`, `AUTH_LOCKOUT_ENABLED`) are disabled by
> the literal `false` and nothing else — so `API_ENABLED=no` leaves the API
> **on**. Use `true` and `false` everywhere and none of this can bite you.

### 7. Only if you rely on geo: point it at the right source

| Deployment | Setting |
|---|---|
| Behind a CDN, `filter` mode, CDN ranges in `TRUSTED_PROXY_CIDRS` | `GEO_HEADER` works |
| `depth` mode, or direct-connect | `GEO_DB_PATH=/path/to/country.mmdb` — `GEO_HEADER` is ignored |

A bad `GEO_DB_PATH` fails at boot rather than per request. Unresolved country
renders as "Unknown" and is never stored as if it were a country.

Organization Secret Activity country is **off by default**
(`SECRET_ACTIVITY_GEO_COUNTRY_ENABLED`), pending the legal review tracked in
ADR-021. Do not enable it without that review.

### 8. Rename the passkey variables

```bash
AUTH_WEBAUTHN_VERIFY_ACCOUNT=true     # was WEBAUTHN_VERIFY_ACCOUNT
AUTH_WEBAUTHN_AUTOFILL=true           # was WEBAUTHN_AUTOFILL
```

The old names are ignored and log a `CONFIG DEPRECATION` line. They are
registered as soft deprecations, so they will not fail your boot even under the
default `DEPRECATED_CONFIG_MODE=strict`. Only the literal `true` enables either
flag.

## After Upgrading

### Only if you use SSO: repair provisioned admins

Customers provisioned just-in-time through SSO were created unverified and nothing
ever flipped the flag — the flag is normally set by the emailed verify-account flow,
which an SSO user never traverses. The visible consequence is that an
SSO-provisioned colonel or admin **cannot exercise their role**: the system role
check refuses an unverified customer before it looks at the role at all, even after
a promotion from the CLI.

New SSO signups are marked verified at creation. Existing records need a one-time
repair:

```bash
bin/ots customers doctor --all              # reports :sso_customer_unverified
bin/ots customers doctor --all --repair     # heals them
```

The repair is limited to records whose provisioning origin is literally SSO and
whose Rodauth account is already Verified. It writes only the customer mirror and
preserves any verification provenance already present. (#3973)

### Optional: reconcile the role index

```bash
bin/ots customers role reconcile            # dry-run report
bin/ots customers role reconcile --apply --force
```

This repairs drift between the authoritative `role` field and the derived
`customer:role_index:*` sets that `role list` and `colonel_count` read. The drift
predates this release — targeted field writers retain the previous role's bucket
member, and TTL expiry deletes the customer hash while its index members persist,
permanently inflating `colonel_count`. The repair is an incremental SADD/SREM diff
rather than a delete-and-repopulate rebuild, so an interrupted run cannot leave the
index emptier than it started. (#3974)

### Expect the active-sessions list to fill in gradually

The account "active sessions" list previously showed no IP address, browser or
country for anyone — it joined Rodauth's session rows on a value Rodauth never
stores. Sessions that already exist at deploy time have no join key until their
next sign-in, so they keep listing without those details. No migration or backfill
is needed. (#3989)

## Verify

Run these in order — each one isolates a different gate that answers `404`.

1. **Colonel reachable.** `curl -sI -H 'Host: <your-colonel-host>' https://…/colonel`
   → `302` to `/signin` (or `200` if signed in). A `404` means the host gate or
   the CIDR gate denied it; check the boot log for `Admin host allowlist` and
   `Admin CIDR allowlist` lines.
2. **Admin API alive.** `/api/colonel/status` from an allowed host and an
   allowed network.
3. **Public surface unaffected.** `/` and `/api/v2/status` should be `200`
   regardless — the admin gates are scoped to the two admin surfaces, and a
   public `404`/`503` is a different problem.
4. **Custom-domain sign-in.** On each custom domain that serves passwords, load
   `/signin` and complete one sign-in. A `404` means the domain has not opted in;
   a `503` means the per-domain policy could not be read (a datastore problem,
   not a policy decision).
5. **Tenant SSO sign-in.** If any tenant has an `allowed_domains` allowlist, sign
   in once through that tenant's IdP. A denial shows `auth_error=domain_not_allowed`
   and logs `:omniauth_tenant_domain_rejected` — the allowlist is now enforced where
   it previously was not.
6. **Org-scope receipts.** On a billing-enabled install, `GET /receipt/recent?scope=org`
   as an org owner. A 403 means no plan grants `audit_logs` yet.
7. **Boot log clean.** No `CONFIG DEPRECATION`, no `Invalid CIDR`, no
   `INACTIVE: no routable hostname` you did not intend.

## Config Mapping Reference

### Renamed

| Old | New |
|---|---|
| `WEBAUTHN_VERIFY_ACCOUNT` | `AUTH_WEBAUTHN_VERIFY_ACCOUNT` |
| `WEBAUTHN_AUTOFILL` | `AUTH_WEBAUTHN_AUTOFILL` |

### New

| Variable | Default | Notes |
|---|---|---|
| `ADMIN_ALLOWED_HOSTS` | canonical anchors + `www.` | `*` disables |
| `LINK_DOMAINS` | unset | Comma-separated |
| `GEO_DB_PATH` | unset | MaxMind country `.mmdb`; all proxy modes |
| `SECRET_ACTIVITY_GEO_COUNTRY_ENABLED` | `false` | Opt-in; see ADR-021 |
| `MIDDLEWARE_AUTH_*` | `true` | Auth-app middleware profile toggles |
| `SMTP2GO_API_KEY`, `SMTP2GO_BASE_URL` | unset | New mail provider |

### Changed behaviour

| Variable | Before | After |
|---|---|---|
| `ADMIN_ALLOWED_CIDRS` | No valid entries → no restriction | No valid entries → both admin surfaces denied |
| `GEO_HEADER` | Honoured in all modes | `filter` mode only |
| `TRUSTED_PROXY_MODE` | Invalid value accepted | Validated at boot; falls back to `filter` with a warning |
| `BILLING_ENABLED`, `STRIPE_AUTOMATIC_TAX`, `RABBITMQ_VERIFY_PEER` | `== 'true'`; anything else false | Full boolean vocabulary; unrecognized value raises |

## Troubleshooting

### `/colonel` returns 404 after upgrade

Check in this order: (1) is the hostname in `ADMIN_ALLOWED_HOSTS` or a canonical
anchor; (2) does `ADMIN_ALLOWED_CIDRS` have at least one parseable range and does
your client fall inside it; (3) behind a proxy, is `TRUSTED_PROXY_ENABLED=true`
with usable CIDRs, so the forwarded host is trusted at all. The boot log names
whichever gate is active.

### Sign-in on a custom domain returns 404

The domain has no enabled sign-in opt-in. Enable it in the domain's settings.
This is the ADR-024 default-OFF rule now reaching full mode.

### Tenant SSO users suddenly cannot sign in

That tenant's `allowed_domains` allowlist is now enforced and does not list the
domain the IdP asserted. Look for `:omniauth_tenant_domain_rejected` in the audit
trail. Fix the allowlist, or clear it — an empty allowlist is allow-all.

### `/receipt/recent?scope=org` returns 403

The `audit_logs` entitlement is now required for org-scope receipts and no plan in
your catalog grants it. Grant it on the plans that should have org-wide visibility.
Standalone installs do not hit this.

### Sign-in returns 503

The per-domain policy could not be read. This is an outage signal, not a policy
decision — check datastore connectivity.

### Boot fails with `is set to an unrecognized boolean`

One of the three strict-parsed flags holds a value outside
`1/true/yes/on/y/t` / `0/false/no/off/n/f`. The message names the flag; set it to
`true` or `false`.

### Billing surfaces appeared after upgrade

`BILLING_ENABLED` was already set to a truthy token — `1`, `yes`, `on`, `TRUE` —
that v0.26.4 ignored and v0.26.5 honours. Billing does not enable itself from an
unset, blank or invalid value. Set it to the literal `false` if off was the
intent.

### Session country shows "Unknown" everywhere

`GEO_HEADER` in `depth` mode is ignored. Set `GEO_DB_PATH`, or move to `filter`
mode with your CDN's ranges listed.

## Rollback

There is no schema migration and no bulk data transform in this release, so
rollback is pinning the previous tag and restarting.

Config written for v0.26.5 is inert or harmless on v0.26.4 — `ADMIN_ALLOWED_HOSTS`
and the new geo variables are simply unread — with one exception worth knowing:
the three strict-parsed booleans revert to `== 'true'`, so `BILLING_ENABLED=yes`
becomes **off** again on the old tag.
