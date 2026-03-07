# Zod Schema Comparison: v0.23 → v0.24

> Comparing `rel/0.23` (v0.23) and `main` (v0.24) schema surfaces.

---

## Phase 1: Topological Breadth Comparison

### File Counts

| Category | v0.23 | v0.24 | Delta |
|----------|-------|-------|-------|
| `models/` | 10 | 14 | +4 |
| `api/` | 12 | 20 | +8 |
| `errors/` | 7 | 7 | 0 |
| `i18n/` | 2 | 2 | 0 |
| `utils/` | 1 | 3 | +2 |
| `config/` | — | 16 | +16 (NEW) |
| `ui/` | — | 5 | +5 (NEW) |
| Root files | 2 | 4 | +2 |
| **Total** | **34** | **71** | **+37** |

### Entity Map: Models

| Entity | v0.23 | v0.24 | Status |
|--------|-------|-------|--------|
| `base` | `models/base.ts` | `models/base.ts` | SAME |
| `customer` | `models/customer.ts` | `models/customer.ts` | CHANGED |
| `secret` | `models/secret.ts` | `models/secret.ts` | CHANGED |
| `metadata` | `models/metadata.ts` | — | REMOVED |
| `receipt` | — | `models/receipt.ts` | NEW (replaces metadata) |
| `feedback` | `models/feedback.ts` | `models/feedback.ts` | SAME |
| `plan` | `models/plan.ts` | — | MOVED → `config/billing.ts` |
| `jurisdiction` | `models/jurisdiction.ts` | `models/jurisdiction.ts` | SAME |
| `public` | `models/public.ts` | `models/public.ts` | CHANGED |
| `domain/*` | 3 files | 3 files | SAME |
| `auth` | — | `models/auth.ts` | NEW |
| `billing` | — | `models/billing.ts` | NEW |
| `diagnostics` | — | `models/diagnostics.ts` | NEW |
| `organization` | — | `models/organization.ts` | NEW |

### Entity Map: API Endpoints

| Endpoint | v0.23 | v0.24 | Status |
|----------|-------|-------|--------|
| Base response | `api/base.ts` | `api/v3/base.ts` | CHANGED |
| Account | `api/endpoints/account.ts` | `api/account/endpoints/account.ts` | CHANGED |
| Colonel | `api/endpoints/colonel.ts` | `api/account/endpoints/colonel.ts` | EXPANDED |
| Conceal | `api/endpoints/conceal.ts` | `api/v3/endpoints/conceal.ts` | CHANGED |
| Recent | `api/endpoints/recent.ts` | `api/account/endpoints/recent.ts` | CHANGED |
| Incoming | `api/incoming.ts` | `api/incoming.ts` | SAME |
| Responses | `api/responses.ts` | `api/v3/responses.ts` | EXPANDED |
| Requests | `api/requests.ts` | `api/v3/requests.ts` | SAME |
| Payloads | `api/payloads/*` | `api/v3/payloads/*` | SAME |
| Auth | — | `api/auth/endpoints/auth.ts` | NEW |
| Organizations | — | `api/organizations/endpoints/organizations.ts` | NEW |
| Stripe types | — | `api/account/stripe-types.ts` | NEW |

### New Categories (v0.24 only)

| Category | Files | Purpose |
|----------|-------|---------|
| `config/` | 16 files | YAML config validation (site, mail, storage, billing, auth, etc.) |
| `ui/` | 5 files | Form types, layout schemas, local receipts, notifications |
| `registry.ts` | 1 | Centralized schema registry for JSON Schema generation |
| `openapi-setup.ts` | 1 | Zod-to-OpenAPI extension layer |
| `utils/identifiers.ts` | 1 | ObjId/ExtId branded type validation |

---

## Phase 2: Deep-Dive Comparison

### 2.1 `models/base.ts` — IDENTICAL

No changes. `baseModelSchema` has `{ identifier, created, updated }` with `createModelSchema()` helper in both versions.

---

### 2.2 `models/secret.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **States** | `NEW, RECEIVED, BURNED, VIEWED` | `NEW, RECEIVED, REVEALED, BURNED, VIEWED, PREVIEWED` |
| **Base fields** | `key, shortkey, state, is_truncated, has_passphrase, verification, secret_value?` | `identifier, key, shortid, state, has_passphrase, verification, secret_value?` |
| **Renamed** | `shortkey` | `shortid` |
| **Removed** | `is_truncated` | — |
| **Added** | — | `identifier` (in base), `REVEALED`, `PREVIEWED` states |
| **Details** | Same | Same |

**Key change**: State terminology migration — `viewed→previewed`, `received→revealed` (both old and new values accepted). Field rename `shortkey→shortid`. Removed `is_truncated` from base.

---

### 2.3 `models/metadata.ts` (v0.23) → `models/receipt.ts` (v0.24)

This is the biggest model rename in the migration.

| Aspect | v0.23 metadata | v0.24 receipt |
|--------|----------------|---------------|
| **States** | `NEW, SHARED, RECEIVED, BURNED, VIEWED, EXPIRED, ORPHANED` | `NEW, SHARED, RECEIVED, REVEALED, BURNED, VIEWED, PREVIEWED, EXPIRED, ORPHANED` |
| **ID field** | `shortkey` | `shortid` |
| **Related ID** | `secret_shortkey` | `secret_shortid` |
| **TTL field** | `metadata_ttl` | `receipt_ttl` |
| **Timestamps** | `received, burned, viewed` | `received, viewed` (deprecated) + `previewed, revealed, shared, burned` (new) |
| **Booleans** | `is_viewed, is_received, is_burned, is_destroyed, is_expired, is_orphaned` | Same (deprecated) + `is_previewed, is_revealed` (new, optional during migration) |
| **New fields** | — | `memo`, `kind` (generate/conceal), `recipients` now nullable |
| **Created/updated** | `transforms.fromString.date` (inherited from base) | `transforms.fromNumber.secondsToDate` (overrides base) |
| **Full record paths** | `secret_key, metadata_path, metadata_url` | `secret_identifier, receipt_path, receipt_url` |
| **Expiration** | `transforms.fromString.date` | `transforms.fromNumber.secondsToDate` |

**Details schema changes**:

| v0.23 metadataDetailsSchema | v0.24 receiptDetailsSchema |
|----------------------------|---------------------------|
| `maxviews, has_maxviews` | REMOVED |
| `show_metadata_link, show_metadata` | `show_receipt_link, show_receipt` |

---

### 2.4 `models/customer.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **ID fields** | `custid` | `objid, extid` (dual-ID pattern) |
| **Email** | `z.string().email()` | `z.email()` (Zod v4 shorthand) |
| **Plan** | `plan: planSchema` (embedded) | REMOVED (moved to org-level billing) |
| **Plan ID** | `planid: z.string().nullable().optional()` | REMOVED |
| **Stripe fields** | `stripe_customer_id, stripe_subscription_id, stripe_checkout_email` | REMOVED (moved to org-level) |
| **New fields** | — | `notify_on_reveal: boolean (default: false)` |
| **Import** | `import { planSchema } from './plan'` | No plan import |

**Key change**: Customer is now a leaner entity. Billing/plan/Stripe fields moved to the organization level. Dual-ID pattern (`objid` + `extid`) replaces single `custid`.

---

### 2.5 `models/feedback.ts` — IDENTICAL

No changes between versions.

---

### 2.6 `models/public.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **Schema names** | `secretOptionsSchema, authenticationSchema` | `publicSecretOptionsSchema, publicAuthenticationSchema` (prefixed) |
| **Auth mode** | — | `mode: z.enum(['simple', 'full']).optional()` |
| **Plans section** | `plansSchema` (stripe_key, webhook, payment_links) | REMOVED |
| **Domains/regions** | Inline in `publicSettingsSchema` | Extracted to `publicFeaturesSchema` |
| **publicSettingsSchema** | `host, domains, ssl, authentication, authenticity, plans, support, regions, secret_options` | `host, ssl, authentication, authenticity, support, secret_options` (slimmed) |
| **New export** | — | `publicFeaturesSchema { regions, domains }` |
| **Cluster fields** | `cluster_ip, cluster_host, cluster_name` | `proxy_ip, proxy_host, proxy_name` (renamed) |

---

### 2.7 `models/plan.ts` (v0.23 only) → `config/billing.ts` (v0.24)

v0.23 had a simple `planSchema` with `{ identifier, planid, price, discount, options: { ttl, size, api, name, email?, custom_domains?, dark_mode?, cname?, private? } }`.

v0.24 replaces this with a comprehensive billing catalog system in `config/billing.ts` with entitlement-based plans, Stripe metadata schemas, pricing tiers, and plan definitions. The scope expanded from ~25 lines to ~500+ lines.

---

### 2.8 API Base Response (`api/base.ts` → `api/v3/base.ts`)

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **Base fields** | `success: boolean, custid?: string, shrimp?: string` | `user_id?: string, shrimp?: string` |
| **Success field** | `transforms.fromString.boolean` (explicit) | REMOVED (HTTP status codes) |
| **User ID** | `custid` | `user_id` |
| **Error schema** | `{ message, code: number, record: unknown, details? }` | `{ message, code?: string, details? }` |
| **Error code type** | `transforms.fromString.number` | `z.string().optional()` (machine-readable like `VALIDATION_ERROR`) |
| **List count** | `transforms.fromString.number.optional()` | `z.number().int().optional()` |
| **Transforms import** | Yes | No (pure Zod) |

**Key change**: v0.24 drops the `success` boolean — uses pure REST semantics with HTTP status codes. Error codes changed from numeric to string-based machine-readable codes.

---

### 2.9 `api/endpoints/conceal.ts` → `api/v3/endpoints/conceal.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **Response key** | `metadata: metadataSchema` | `receipt: concealReceiptSchema` |
| **Receipt type** | Full metadataSchema | `receiptBaseSchema.extend({ identifier })` (lighter) |
| **share_domain** | `z.string()` | `z.string().nullable()` |

---

### 2.10 `api/endpoints/account.ts` → `api/account/endpoints/account.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **apitoken** | `z.string().optional()` | `z.string().nullable()` |
| **Stripe fields** | `z.custom<Stripe.Customer>().nullable()`, `z.array(z.custom<Stripe.Subscription>()).nullable()` | `z.any().optional()` (loosened, Stripe types removed) |
| **Stripe import** | `import type Stripe from 'stripe'` | No Stripe import |

---

### 2.11 `api/endpoints/colonel.ts` → `api/account/endpoints/colonel.ts`

v0.24 massively expands the colonel schemas:

| v0.23 schemas | v0.24 schemas |
|---------------|---------------|
| `systemSettingsSchema` | Moved to `config/config.ts`, re-exported |
| `recentCustomerSchema` | Same (minus `planid` field) |
| `colonelStatsDetailsSchema` | Same (`metadata_count` → `receipt_count`) |
| `colonelInfoDetailsSchema` | Same (`redis_info` → `dbclient_info`, `plans_enabled` → `billing_enabled`, `metadata_count` → `receipt_count`) |

**New in v0.24**:
- `colonelUserSchema` + `colonelUsersDetailsSchema` (paginated user list)
- `colonelSecretSchema` + `colonelSecretsDetailsSchema` (paginated secret list)
- `databaseMetricsDetailsSchema` (Redis INFO + memory stats)
- `redisMetricsDetailsSchema` (raw Redis INFO)
- `bannedIPSchema` + `bannedIPsDetailsSchema`
- `usageExportDetailsSchema` (date ranges, daily stats)
- `colonelCustomDomainSchema` + `colonelCustomDomainsDetailsSchema`
- `colonelOrganizationSchema` + `colonelOrganizationsDetailsSchema` (with billing sync health)
- `investigateOrganizationResultSchema` (billing investigation with Stripe comparison)
- `queueMetricSchema` + `queueMetricsDetailsSchema` (message queue health)
- `paginationSchema` (shared pagination metadata)
- `systemSettingsSchema` extracted to `config/config.ts` (much richer)

---

### 2.12 `api/endpoints/recent.ts` → `api/account/endpoints/recent.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **Schema names** | `metadataRecordsSchema`, `metadataRecordsDetailsSchema` | `receiptRecordsSchema`, `receiptRecordsDetailsSchema` |
| **Base import** | `metadataBaseSchema` | `receiptBaseSchema` |
| **Extension method** | `.merge(z.object({...}))` | `.extend({...})` |
| **ID fields** | `custid` | `custid?, owner_id?` + `secret_identifier?, secret_shortid?, key?` (all nullish) |
| **List details** | `type, since, now, has_items, received[], notreceived[]` | Same + `scope?, scope_label?` (org/domain filtering) |

---

### 2.13 Payloads (`api/payloads/*` → `api/v3/payloads/*`)

**base.ts**: IDENTICAL (both versions same shape)
**conceal.ts**: IDENTICAL (comment typo fix: "correleated" → "correlated", "compacetic" → "copacetic")
**generate.ts**: IDENTICAL (same comment fixes)

---

### 2.14 Response Registry (`api/responses.ts` → `api/v3/responses.ts`)

| Aspect | v0.23 (15 response types) | v0.24 (30+ response types) |
|--------|---------------------------|----------------------------|
| **Core** | account, apiToken, brandSettings, checkAuth, customer, feedback, imageProps, jurisdiction, secret | Same |
| **Metadata→Receipt** | metadata, metadataList | receipt, receiptList |
| **Colonel** | colonelInfo, colonelStats, systemSettings | Same + colonelUsers, colonelSecrets, customDomains, colonelOrganizations, investigateOrganization, databaseMetrics, redisMetrics, bannedIPs, usageExport, queueMetrics |
| **Auth** | — | login, createAccount, logout, resetPasswordRequest, resetPassword |
| **Special** | csrf, concealData | Same |

---

### 2.15 `transforms.ts`

| Aspect | v0.23 | v0.24 |
|--------|-------|-------|
| **date refine** | `z.date().refine((val) => val !== null, { message: '...' })` | `z.date().refine((val): val is Date => val !== null, '...')` (type predicate + inline message) |
| **optionalEmail** | `z.string().email().optional()` | `z.email().optional()` (Zod v4) |

Minimal changes — mainly Zod v4 API adjustments.

---

## Summary of Breaking Changes

### Naming
1. `metadata` → `receipt` (model, schema names, types, paths)
2. `shortkey` → `shortid` (secret and receipt)
3. `secret_shortkey` → `secret_shortid`
4. `custid` → `user_id` (API responses)
5. `custid` → `objid` + `extid` (customer model)
6. `metadata_ttl` → `receipt_ttl`
7. `metadata_path/url` → `receipt_path/url`
8. `cluster_ip/host/name` → `proxy_ip/host/name`

### Structural
1. `success` boolean removed from API responses (pure REST)
2. Error `code` changed from number to string
3. Plan/Stripe fields removed from customer (org-level now)
4. API endpoints reorganized: flat `api/endpoints/` → domain-grouped `api/account/`, `api/auth/`, `api/organizations/`, `api/v3/`
5. `is_truncated` removed from secret base

### State Terminology
1. `viewed` → `previewed` (link accessed)
2. `received` → `revealed` (content consumed)
3. Old values kept for backward compat during migration

### Zod v4 Usage
1. `z.string().email()` → `z.email()`
2. Type predicates in refinements
3. `import { z } from 'zod/v4'` in some files (colonel)
