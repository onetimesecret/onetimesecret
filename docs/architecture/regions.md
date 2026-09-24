---
labels: regions, jurisdictions, data-sovereignty
---

# Regions Architecture

> Terminology (fleet vs. federation vs. region vs. deployment): see [terminology.md](./terminology.md#deployment-topology-terminology).

Regions enable multi-jurisdiction deployments where each geographic instance runs independently with its own domain, billing catalog, and data store. Users can see which region they're on and switch between them.

## Use Cases

- Data sovereignty compliance (GDPR, PIPEDA, regional privacy laws)
- Geographic isolation of secrets and customer data
- Region-scoped billing catalogs with jurisdiction-specific pricing
- Observability segmentation via Sentry jurisdiction tags

## Configuration

Three environment variables control the feature:

| Variable | Purpose |
| --- | --- |
| `REGIONS_ENABLED` | Set to `true` to activate region features. |
| `JURISDICTION` | Current instance's identifier (for example, `EU`). |
| `JURISDICTIONS` | Comma-separated region destinations as `ID:domain` pairs. |

Configure each deployment with its own current jurisdiction and the shared destination list:

```bash
REGIONS_ENABLED=true
JURISDICTION=EU
JURISDICTIONS=EU:eu.onetimesecret.com,CA:ca.onetimesecret.com
```

`features.regions.jurisdictions` is derived from `JURISDICTIONS` at configuration load time. A structured YAML array at that path is deprecated and emits a deprecation warning.

### Region names and icons

The region selector resolves a name from the locale key `web.regions.jurisdictions.<identifier>.name`. The `display_name` field from the former structured YAML format is not sent to the frontend. Add the corresponding locale entry for a custom identifier; otherwise the selector can show the unresolved key. Icons are optional and fall back to the frontend's identifier-to-icon mapping.

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
