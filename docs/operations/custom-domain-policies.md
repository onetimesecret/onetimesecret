# Custom-domain homepage and signup policies

Enable per-domain homepage network rules and base-domain signup allowlisting.
These policies differ in scope and behavior when flags or entitlements change.

## Enable workspace configuration

Both flags in the [application configuration](../../etc/config.yaml) live under
`features.organizations`, default to off, and require literal `true`:

| Environment setting | Configuration key | Organization entitlement |
| --- | --- | --- |
| `ORGS_HOMEPAGE_NETWORK_RULES_UI_ENABLED=true` | `homepage_network_rules_ui_enabled` | `homepage_network_rules` |
| `ORGS_BASE_DOMAIN_SIGNUP_ENABLED=true` | `base_domain_signup_enabled` | `base_domain_signup` |

Workspace editing also requires `homepage_secrets` for homepage settings or
`custom_signup_validation` for signup settings. The editor needs `manage_org`
in the owning organization and access to the domain.

### Provision entitlements

For billing-enabled installations, check your `etc/billing.yaml`, synchronized
catalog, and effective organization entitlements. A flag does not provision a
plan, update Stripe metadata, or refresh existing organization entitlements.
In the [billing example](../../etc/examples/billing.example.yaml):
- `homepage_network_rules` is included in Identity Plus (`identity_plus_v1`),
  not Free; the commented-out Team Plus example also lists it.
- `base_domain_signup` is defined but **no example plan grants it**. Add it
  explicitly to the plans intended to offer it; a definition is not a grant.

Follow the [billing CLI guide](../../apps/web/billing/docs/cli-usage.md) for
catalog synchronization. Re-materialize existing organizations after changing
plan entitlements; catalog changes alone do not refresh materialized grants.
The [materialization command](../../apps/web/billing/cli/plans_materialize_command.rb)
previews by default, writes with `--run`, and can cascade to active memberships
with `--include-memberships`. Do not infer deployed grants from plan names or
the generated [catalog reference](../../apps/web/billing/docs/plan-definitions.md).

With billing disabled (standalone mode), both entitlements need no paid plan.
Installation flags, membership/domain permissions, and per-domain setup still apply.
Do not treat an unavailable billing catalog as standalone mode.

## Configure homepage network rules

Enable the custom domain's homepage, choose `secrets_mode` (`create` or
`incoming`), and set `allowed_cidrs` and/or `denied_cidrs` in homepage settings.
Each list accepts up to 100 distinct IPv4/IPv6 addresses or CIDR ranges.
Entries are normalized and deduplicated; invalid or oversized lists return 422.
- Both lists empty: no network restriction.
- A deny match always wins, including over an allow match.
- With a nonempty allow list, visitors must match an allowed range.
- Otherwise, visitors are admitted subject to the other endpoint gates.

### Scope and exemptions

These rules are **not a WAF or whole-domain access control**:
- In `create` mode, refused visitors see the private landing page; anonymous
  secret creation on that custom domain returns 403 “Public sharing disabled”.
- In `incoming` mode, rules control whether the **homepage** shows the incoming
  form. They do not restrict `/incoming` or `POST /api/incoming/secret`, which
  use incoming-secret configuration and authorization. Incoming mode does not
  authorize anonymous creation through the regular create API.
- Owners and organization members retain their secret-creation permissions.
  Authenticated non-members gain no domain-use permission from an open homepage.
  These rules do not gate management pages, sign-in, or secret retrieval.

See the [domain-permissions specification](../specs/domain-permissions/domain-permissions.md)
for the endpoint permission matrix. For whole-domain restrictions, configure
access controls at your reverse proxy or edge rather than relying on these rules.

### Configure trusted proxies first

Rules match the resolved client address at full IPv4/IPv6 precision, not the
privacy-masked address displayed elsewhere. Configure `site.network.trusted_proxy`
in the [canonical configuration reference](../../etc/config.yaml):
- Direct connections: leave `TRUSTED_PROXY_ENABLED` off; the peer address is used.
- Behind a trusted proxy: set `TRUSTED_PROXY_ENABLED=true` and firewall the origin
  against direct client access. Otherwise, visitors may be judged by proxy IP.
- Default `filter` mode: the edge must overwrite client-supplied `X-Forwarded-For`
  with the real peer address. Add public proxy/CDN ranges to `TRUSTED_PROXY_CIDRS`;
  private proxy ranges are already trusted.
- If the edge cannot overwrite the header, use `TRUSTED_PROXY_MODE=depth` and set
  `TRUSTED_PROXY_DEPTH` to the actual trusted hop count: 1 for a single proxy,
  2 for CDN → proxy → application. Prevent shorter routes to the origin.
- `TRUSTED_PROXY_HEADER` defaults to `X-Forwarded-For`; depth mode also accepts
  `Forwarded` or `Both`. Filter mode rejects those alternatives at boot.
  Vendor headers such as `CF-Connecting-IP` are not selectable client-IP sources.

Use the [proxy-header diagnostic guide](proxy-header-diagnostic.md) to investigate
resolution. Stored rules deny visitors if lists are unreadable or the request
cannot supply a usable client-IP matcher/address, including matcher errors.

### Downgrades, disabled editing, and repair

Turning the homepage flag off or removing `homepage_network_rules` freezes
workspace list edits; **stored rules remain enforced**. Changing or clearing
lists requires both gates again. Omitted or `null` lists preserve stored values;
`[]` clears a list. Unchanged normalized lists can round-trip, and unrelated
homepage edits remain available under normal authorization. Unreadable lists
cannot count as unchanged. Deleting a homepage config with nonempty or unreadable
lists requires the same flag and entitlement; deletion cannot bypass the freeze.

Colonel's domain-config upsert can repair homepage CIDRs **without the workspace
feature flag or network-rule entitlement**. Model validation, Colonel authorization,
confirmation, and auditing still apply. See the [Colonel guide](colonel-admin-guide.md).

## Configure base-domain signup

1. Enable the base-domain installation flag and provision `base_domain_signup`
   plus `custom_signup_validation` for workspace editing.
2. Keep global authentication and signup enabled (`AUTH_ENABLED` and `AUTH_SIGNUP`
   must not be `false`). Set the domain's **SignupConfig** to `enabled: true`
   and `signup_enabled: true`; HomepageConfig's deprecated signup field is not used.
3. Choose `validation_strategy: domain_allowlist`, set `allow_base_domain: true`,
   and retain additional domains in `allowed_signup_domains` as needed.

The effective list adds the domain's registrable base: `secrets.acme.com` admits
`@acme.com`, and `secrets.acme.co.uk` admits `@acme.co.uk`. Matching is exact and
case-insensitive, not wildcard subdomain matching. The option has no effect under
`passthrough`, `mx`, or `smtp`; `autoverify` remains a separate setting.

Unlike homepage rules, disabling the flag or losing the entitlement stops the
base domain from counting, without erasing the stored option. Explicit entries
still apply. Turning the option on requires both gates; preserving a stored true
or turning it off still requires normal authorization and a valid resulting list.
An empty explicit list is valid only while the effective option supplies a base
domain. Missing base-domain data, an empty effective list, or a corrupt explicit
list admits nobody. Required datastore reads or entitlement catalog lookups that
fail make signup return **503**, not unrestricted signup or an ordinary rejection.
An address already admitted explicitly does not need the extra base-domain lookup.
