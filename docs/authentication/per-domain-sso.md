# Per-Organization SSO Configuration

This document describes the conditions required for the SSO configuration tab to appear in organization settings.

## Prerequisites

The SSO tab visibility is controlled by the `manage_sso` entitlement. The following conditions must be met for the tab to appear.

### Billing Disabled (Standalone Mode)

When billing is disabled (`BILLING_ENABLED=false`), all entitlements are granted automatically via `STANDALONE_ENTITLEMENTS`. The SSO tab appears for all organizations without additional configuration.

### Billing Enabled

When billing is enabled, the organization must have the `manage_sso` entitlement. This requires proper configuration across multiple layers.

## Configuration Layers

### 1. billing.yaml

The `manage_sso` entitlement must be defined in two places:

**Root-level entitlements section** (defines valid entitlement keys):

```yaml
entitlements:
  manage_sso:
    category: advanced
    description: Single sign-on configuration and management
```

**Plan entitlements array** (assigns entitlement to plan):

```yaml
plans:
  identity_plus_v1:
    entitlements:
      - create_secrets
      - view_receipt
      - api_access
      - custom_domains
      - manage_sso      # Must match root-level key exactly
      - custom_branding
```

### 2. Stripe Product Metadata

After updating `billing.yaml`, push to Stripe:

```bash
bin/ots billing catalog push
```

The Stripe Product metadata should contain:

```
entitlements: "create_secrets,view_receipt,api_access,custom_domains,manage_sso,custom_branding"
```

### 3. Redis Plan Cache

Sync from Stripe to Redis:

```bash
bin/ots billing catalog pull
```

Verify the entitlement is cached:

```bash
redis-cli SISMEMBER 'billing_plan:identity_plus_v1_monthly:entitlements' 'manage_sso'
# Returns 1 if present, 0 if missing
```

### 4. Organization Assignment

The organization must be subscribed to a plan that includes `manage_sso`. The entitlements are computed dynamically at runtime:

```ruby
# Backend: lib/onetime/models/features/with_entitlements.rb
org.entitlements  # Returns plan entitlements from Redis cache
org.can?('manage_sso')  # Returns true/false
```

## Data Flow

### Entitlement Resolution (Tab Visibility)

```
billing.yaml
    │
    ▼ bin/ots billing catalog push
Stripe Product Metadata
    │
    ▼ bin/ots billing catalog pull
Redis Plan Cache (billing_plan:<plan_id>:entitlements)
    │
    ▼ org.entitlements (via Billing::Plan.load)
Organization API Response
    │
    ▼ can(ENTITLEMENTS.MANAGE_SSO)
SSO Tab Visibility
```

### Login Flow (Runtime)

**Prerequisite:** Organization must have a custom domain configured.

```
User visits https://{custom-domain}/signin
    │
    ▼
POST /auth/sso/{provider}
    │
    ▼
Host header → CustomDomain → Organization → OrgSsoConfig
    │
    ▼
Inject org credentials into OmniAuth strategy
    │
    ▼
Redirect to org's IdP
    │
    ▼
IdP callback → tenant validation → session created
```

Resolution chain (`apps/web/auth/config/hooks/omniauth_tenant.rb`):

| Step | Lookup | Result |
|------|--------|--------|
| 1 | `request.host` | `secrets.acme.com` |
| 2 | `CustomDomain.load_by_display_domain(host)` | CustomDomain record |
| 3 | `custom_domain.org_id` | Organization identifier |
| 4 | `OrgSsoConfig.find_by_org_id(org_id)` | SSO credentials |
| 5 | `org_config.to_omniauth_options` | OmniAuth strategy injection |

**Security:** Tenant context stored in session during request phase, validated on callback to prevent cross-tenant redirect attacks.

## Troubleshooting

### SSO Tab Not Appearing

1. **Check billing mode**:
   ```bash
   # If billing disabled, SSO should appear automatically
   echo $BILLING_ENABLED
   ```

2. **Verify Redis cache**:
   ```bash
   redis-cli SMEMBERS 'billing_plan:<plan_id>:entitlements'
   ```

3. **Check Stripe metadata**:
   ```bash
   bin/ots billing catalog pull --dry-run
   ```

4. **Verify organization's plan**:
   ```ruby
   # In console
   org = Organization.load(extid)
   org.planid
   org.entitlements
   org.can?('manage_sso')
   ```

5. **Check frontend debug logs** (if enabled):
   ```
   [OrganizationSettings] SSO visibility: ...
   [useEntitlements] can(): { entitlement: "manage_sso", ... }
   ```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| SSO tab missing | `manage_sso` not in plan entitlements | Add to billing.yaml, push, pull |
| Entitlement in YAML but not Redis | Push/pull not run | Run `bin/ots billing catalog push && pull` |
| Mismatch between YAML key and plan | Root uses `sso`, plan uses `manage_sso` | Use consistent naming (`manage_sso`) |
| SSO configured but login fails | No custom domain for organization | Add custom domain pointing to org |
| Platform SSO used instead of org SSO | Accessing via canonical domain | Use org's custom domain URL |

## Related Configuration

### Organization Switcher

The organization switcher (separate from SSO tab) requires:

```bash
ENABLE_ORGANIZATIONS=true
```

This controls `features.organizations.enabled` in the bootstrap response.

## See Also

- [SSO Configuration Guide](omniauth-sso.md) — platform-level SSO setup and provider configuration
- [OmniAuth Tenant Resolution](../../apps/web/auth/config/hooks/omniauth_tenant.rb) — runtime credential injection
- [OrgSsoConfig Model](../../lib/onetime/models/org_sso_config.rb) — per-org SSO storage
- [Billing Catalog Management](../billing/catalog-management.md)
- [Entitlements System](../billing/entitlements.md)
- [STANDALONE_ENTITLEMENTS](../../lib/onetime/models/features/with_entitlements.rb)
