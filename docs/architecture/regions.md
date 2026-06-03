---
labels: regions, jurisdictions, data-sovereignty
---

# Regions Architecture

Regions enable multi-jurisdiction deployments where each geographic instance runs independently with its own domain, billing catalog, and data store. Users can see which region they're on and switch between them.

## Use Cases

- Data sovereignty compliance (GDPR, PIPEDA, regional privacy laws)
- Geographic isolation of secrets and customer data
- Region-scoped billing catalogs with jurisdiction-specific pricing
- Observability segmentation via Sentry jurisdiction tags

## Configuration

Two environment variables control the feature:

| Variable         | Purpose                                      |
| ---------------- | -------------------------------------------- |
| `REGIONS_ENABLED`| Set to `true` to activate region features    |
| `JURISDICTION`   | Current instance's identifier (e.g., `EU`)   |

The jurisdictions list lives in `config.yaml`:

```yaml
features:
  regions:
    enabled: <%= ENV['REGIONS_ENABLED'] == 'true' || false %>
    current_jurisdiction: <%= ENV['JURISDICTION'] || nil %>
    jurisdictions:
      - identifier: EU
        display_name: European Union
        domain: eu.onetimesecret.com
        icon:
          collection: fa6-solid
          name: earth-europe
      # Additional regions...
```

When disabled, no region UI surfaces appear and billing operates globally.

## Data Flow

```
config.yaml
    ↓
OT.conf (Ruby hash)
    ↓
ConfigSerializer (filters for frontend)
    ↓
/bootstrap/me endpoint (JSON payload)
    ↓
window.__BOOTSTRAP_ME__
    ↓
jurisdictionStore (Pinia - client source of truth)
```

The serializer always emits `regions_enabled` as a boolean, but only includes the full `regions` object (with domain list) when enabled. This prevents leaking jurisdiction domains when the feature is off.

## Backend Behavior

**Billing integration**: `Billing::Metadata.current_region` reads `current_jurisdiction` and raises `ConfigError` if regions are enabled but the value is blank. The `RegionNormalizer` enforces fail-closed matching—products and customers stay within their designated region.

**Diagnostics**: On startup, the diagnostics initializer tags Sentry with the current jurisdiction. Every error from that deployment carries the region tag.

**Log banner**: The boot banner prints region status for operational visibility.

## Frontend Behavior

**JurisdictionToggle**: A dropdown in footers that navigates to `https://{jurisdiction.domain}/`—a full cross-origin redirect, not an SPA route change. Appears in transactional, management, and branded footer variants.

**Visibility gates**: The toggle only renders when `regions_enabled && regions && !isCustom`. Custom domains suppress the toggle since they're locked to a single deployment.

**Account settings**: The `/account/region/*` routes provide region info pages showing current jurisdiction, available regions, and data sovereignty context. A region tab also appears in the settings modal.

**Auth screens**: The login/signup views display the current jurisdiction's icon as a visual indicator.

## Switching Regions

Region switching is a full navigation to another domain. There is no session transfer—users must authenticate again on the target region. Secrets and account data do not sync between regions; each is an independent deployment.

## Related

- [Secret Lifecycle](../product/secret-lifecycle.md) - How secrets behave within a region
- [Authentication Strategies](./authentication-strategies.md) - Auth context for region-switching sessions
