# Zod Schema Comparison: v0.23 → v0.24

> Comparing `rel/0.23` (v0.23) and `main` (v0.24) schema surfaces.
>
> **How to read this document**: Start wherever makes sense for you.
> - Visual thinker? Start with the [Schema Dependency Graph](#schema-dependency-graph) and [Change Heatmap](#change-heatmap)
> - Need the big picture? Start with [Migration Vectors](#migration-vectors)
> - Looking for a specific entity? Use the [Cross-Reference Matrix](#cross-reference-matrix)
> - Want the executive summary? Jump to [Summary of Breaking Changes](#summary-of-breaking-changes)

---

## Quick Orientation

### Change Heatmap

Where did the change energy go? Sized by magnitude of change:

```
                        v0.23 → v0.24 Change Density
  ┌─────────────────────────────────────────────────────────┐
  │                                                         │
  │  ████████████████████  config/ (16 NEW files)           │
  │  ██████████████        colonel (3 → 20+ schemas)        │
  │  ████████████          metadata → receipt (full rename)  │
  │  ██████████            customer (billing extraction)    │
  │  ████████              api/base (REST semantics)        │
  │  ██████                auth endpoints (5 NEW)           │
  │  ██████                organizations (7 NEW)            │
  │  █████                 ui/ (5 NEW files)                │
  │  ████                  secret (state terminology)       │
  │  ███                   public (slimmed)                 │
  │  ██                    conceal (metadata→receipt)       │
  │  ██                    recent (scope filtering)         │
  │  █                     account (Stripe loosened)        │
  │  ░                     transforms (Zod v4 tweaks)       │
  │  ░                     base, feedback (identical)       │
  │  ░                     payloads (identical)             │
  │                                                         │
  └─────────────────────────────────────────────────────────┘
```

### Migration Vectors

Five forces drove v0.23 → v0.24. Every change traces back to one of these:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                                                                  │
  │  1. MULTI-TENANCY          Customer billing → Organization       │
  │     ├── customer loses plan/stripe fields                        │
  │     ├── organization model (NEW)                                 │
  │     ├── billing model + config/billing.ts (NEW)                  │
  │     └── colonel gets org management schemas                      │
  │                                                                  │
  │  2. TERMINOLOGY CLEANUP    metadata → receipt, viewed → previewed│
  │     ├── models/metadata.ts → models/receipt.ts                   │
  │     ├── secret states: +REVEALED, +PREVIEWED                     │
  │     ├── shortkey → shortid                                       │
  │     ├── custid → user_id (API) / objid+extid (model)            │
  │     └── all downstream: conceal, recent, responses               │
  │                                                                  │
  │  3. API MODERNIZATION      success boolean → HTTP status codes   │
  │     ├── api/base.ts → api/v3/base.ts                            │
  │     ├── error codes: number → string                             │
  │     ├── flat endpoints/ → domain-grouped api/{domain}/           │
  │     └── Rodauth auth endpoints (NEW)                             │
  │                                                                  │
  │  4. CONFIG VALIDATION      Runtime config gets schema coverage   │
  │     ├── config/ (16 NEW files)                                   │
  │     ├── systemSettings extracted from colonel → config/config.ts │
  │     └── auth, billing, logging configs (NEW)                     │
  │                                                                  │
  │  5. ADMIN EXPANSION        Colonel gets full observability       │
  │     ├── users, secrets (paginated lists)                         │
  │     ├── database/redis metrics                                   │
  │     ├── banned IPs, usage export                                 │
  │     ├── queue metrics                                            │
  │     └── org billing investigation                                │
  │                                                                  │
  └──────────────────────────────────────────────────────────────────┘
```

### Schema Dependency Graph

How schemas compose — read top-down for "depends on", bottom-up for "used by":

```
                    ┌─────────────────┐
                    │  baseModelSchema │
                    │  (base.ts)       │
                    └────────┬────────┘
                             │ .extend()
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
        ┌───────────┐ ┌───────────┐ ┌──────────────┐
        │ secretBase│ │receiptBase│ │ customerSchema│
        │  Schema   │ │  Schema   │ │              │
        └─────┬─────┘ └─────┬─────┘ └──────┬───────┘
              │              │              │
     ┌────────┤        ┌─────┤              │
     ▼        ▼        ▼     ▼              ▼
  ┌──────┐┌──────┐┌──────┐┌──────┐   ┌──────────┐
  │secret││secret││receipt││receipt│   │ account  │
  │Schema││Resps ││Schema││Recs  │   │ Schema   │
  └──┬───┘└──────┘└──┬───┘└──────┘   └──────────┘
     │               │
     └───────┬───────┘
             ▼
      ┌─────────────┐        ┌─────────────────────┐
      │ concealData  │        │  responseSchemas     │
      │ Schema       │───────▶│  (registry of all    │
      └─────────────┘        │   response types)    │
                              └─────────────────────┘
                                       ▲
                 ┌─────────────────────┤
                 │                     │
          ┌──────┴──────┐    ┌─────────┴──────┐
          │ auth        │    │ colonel        │
          │ responses   │    │ schemas        │
          │ (v0.24 NEW) │    │ (v0.24 expand) │
          └─────────────┘    └────────────────┘
```

### Cross-Reference Matrix

For any entity, find its model schema, API endpoint, payload, and response type:

```
  Entity        │ Model Schema      │ API Endpoint           │ Payload        │ Response Key
  ══════════════╪═══════════════════╪════════════════════════╪════════════════╪══════════════
  Secret        │ models/secret     │ v3/endpoints/conceal   │ payloads/      │ secret,
                │                   │                        │  conceal,      │ secretList,
                │                   │                        │  generate      │ concealData
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Receipt       │ models/receipt    │ account/endpoints/     │ —              │ receipt,
  (was Metadata)│ (was metadata)    │  recent                │                │ receiptList
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Customer      │ models/customer   │ account/endpoints/     │ —              │ customer,
                │                   │  account               │                │ checkAuth
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Organization  │ models/           │ organizations/         │ —              │ (custom)
  (v0.24 NEW)   │  organization     │  endpoints/orgs        │                │
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Auth          │ models/auth       │ auth/endpoints/auth    │ —              │ login,
  (v0.24 NEW)   │                   │                        │                │ createAccount,
                │                   │                        │                │ logout, ...
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Domain        │ models/domain/*   │ (via colonel)          │ —              │ customDomain,
                │                   │                        │                │ customDomainList
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Billing       │ models/billing    │ (via account +         │ —              │ account
  (v0.24 NEW)   │ config/billing    │  organizations)        │                │
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Feedback      │ models/feedback   │ (inline)               │ —              │ feedback
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Jurisdiction  │ models/           │ (inline)               │ —              │ jurisdiction
                │  jurisdiction     │                        │                │
  ──────────────┼───────────────────┼────────────────────────┼────────────────┼──────────────
  Settings      │ models/public     │ account/endpoints/     │ —              │ systemSettings
  (public +     │ config/config     │  colonel               │                │
   system)      │                   │                        │                │
```

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

**Why this matters**: The state rename reflects a conceptual clarification. "Viewed" was ambiguous — did the recipient see the secret link or the secret content? v0.24 disambiguates: `previewed` = link accessed (confirmation page), `revealed` = content decrypted. This distinction is critical for audit trails and receipt state machines.

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

**Rename ripple effect** — this rename propagates through:
```
  metadata.ts ──renamed──▶ receipt.ts
       │
       ├──▶ conceal endpoint:  metadata: metadataSchema  →  receipt: concealReceiptSchema
       ├──▶ recent endpoint:   metadataRecordsSchema     →  receiptRecordsSchema
       ├──▶ responses:         metadata, metadataList    →  receipt, receiptList
       ├──▶ colonel stats:     metadata_count            →  receipt_count
       └──▶ colonel info:      metadata_count            →  receipt_count
```

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

**Architectural shift** — where billing responsibility lives:
```
  v0.23:  Customer ──has──▶ Plan ──has──▶ Stripe IDs
                    (1:1 embedded)

  v0.24:  Customer ──belongs to──▶ Organization ──has──▶ Subscription
                                        │                    │
                                        ├── Plan (via catalog)│
                                        └── Stripe IDs ──────┘
```

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

**API response evolution**:
```
  v0.23 response shape:           v0.24 response shape:
  ┌─────────────────────┐         ┌─────────────────────┐
  │ success: true       │         │                     │
  │ custid: "abc123"    │         │ user_id: "abc123"   │
  │ shrimp: "csrf_tok"  │         │ shrimp: "csrf_tok"  │
  │ record: { ... }     │         │ record: { ... }     │
  │ details: { ... }    │         │ details: { ... }    │
  └─────────────────────┘         └─────────────────────┘

  v0.23 error shape:              v0.24 error shape:
  ┌─────────────────────┐         ┌───────────────────────────┐
  │ success: false      │         │                           │
  │ message: "Not found"│         │ message: "Not found"      │
  │ code: 404           │         │ code: "NOT_FOUND"         │
  │ record: null        │         │ details: { ... }          │
  └─────────────────────┘         └───────────────────────────┘
                                  (HTTP 404 carries the status)
```

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

**New in v0.24** (grouped by concern):

```
  Observability                    Management                   Investigation
  ─────────────                    ──────────                   ─────────────
  databaseMetricsDetails           colonelUsersDetails          investigateOrganization
  redisMetricsDetails              colonelSecretsDetails          ├── localState
  queueMetricsDetails              colonelCustomDomainsDetails    ├── stripeState
  usageExportDetails               colonelOrganizationsDetails    └── comparison
  bannedIPsDetails                 paginationSchema
```

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

### Field Renames (find-and-replace scope)

```
  v0.23 name              →  v0.24 name              Where
  ────────────────────────────────────────────────────────────
  metadata                →  receipt                  everywhere
  shortkey                →  shortid                  secret, receipt
  secret_shortkey         →  secret_shortid           receipt
  custid (API response)   →  user_id                  api/base
  custid (customer model) →  objid + extid            models/customer
  metadata_ttl            →  receipt_ttl              receipt
  metadata_path/url       →  receipt_path/url         receipt
  cluster_ip/host/name    →  proxy_ip/host/name       public settings
  secret_key (receipt)    →  secret_identifier        receipt
  redis_info (colonel)    →  dbclient_info            colonel
  plans_enabled           →  billing_enabled          colonel
  planid (recentCustomer) →  (removed)                colonel
```

### Structural Changes

1. `success` boolean removed from API responses (pure REST)
2. Error `code` changed from number to string
3. Plan/Stripe fields removed from customer (org-level now)
4. API endpoints reorganized: flat `api/endpoints/` → domain-grouped `api/account/`, `api/auth/`, `api/organizations/`, `api/v3/`
5. `is_truncated` removed from secret base
6. `maxviews`, `has_maxviews` removed from receipt details

### State Terminology

```
  v0.23 state   →  v0.24 state      Meaning
  ────────────────────────────────────────────────
  viewed        →  previewed        Link accessed, confirmation page shown
  received      →  revealed         Secret content decrypted/consumed
  (old values kept in schema enum for backward compat during migration)
```

### Zod v4 API Changes

1. `z.string().email()` → `z.email()`
2. Type predicates in refinements: `(val): val is Date =>`
3. `import { z } from 'zod/v4'` in some files (colonel)
