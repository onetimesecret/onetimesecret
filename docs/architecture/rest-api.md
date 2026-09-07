# Onetime Secret API

The authoritative endpoint reference is published at [api.onetimesecret.com](https://api.onetimesecret.com). This README explains version selection, authentication, and response-field compatibility for API users and contributors.

## Choose an API version

| Version | Status | Use it when |
| ------- | ------ | ----------- |
| **v1** | Frozen legacy API. It accepts form-encoded requests and returns JSON. | You must maintain an existing v1 integration. Do not use it for a new integration. |
| **v2** | Stable, JSON-based API. | You are building a new production integration. |
| **v3** | Alpha. It uses native JSON types and powers the web UI, but its external contract may change without deprecation. | You are evaluating pre-release behavior, not building an external production integration. |

V2 serializes some stored values as strings, while v3 returns native JSON values where its contract defines them. Parse every field according to the selected version's endpoint reference; do not assume all v2 values are strings.

## Authentication and public access

Authentication is defined per endpoint. V1 and v2 protected endpoints use HTTP Basic authentication. The **username is the account email or customer external ID** (`ur…` prefix); the **password is the API token**. Generate a token in **Account > API settings**, or on a self-hosted instance with `bundle exec bin/ots apitoken user@example.com`.

The username is **not** the organization ID (`on…` prefix) or the UUIDv7 `owner_id` returned in API responses. Neither identifies a customer for Basic authentication.

```bash
curl -u 'user@example.com:APITOKEN' https://us.onetimesecret.com/api/v2/receipt/recent
```

The standard v3 secret and receipt paths require a browser session. Some routes in every version allow anonymous access, including the versioned guest routes. Check the endpoint reference before choosing an authentication method.

## Response Field Notes

These conventions apply to secret and receipt responses. Field value *types* differ by version (see [Choose an API version](#choose-an-api-version)); the field *meanings* below are the same across versions unless noted.

### `custid` is deprecated — read `owner_id`

Secret creation writes `owner_id` only, so `custid` is null on every receipt created since the v0.24 identifier migration.

* **v3 receipt records omit the field entirely.** `owner_id` is the only creator identifier.
* **v2 still emits it** on the receipt record — null on post-migration records — for older clients.
* **v1 is the exception**: it translates `custid` back to an email address (`"anon"` for anonymous secrets). See `apps/api/v1/COMPAT.md`.
* `owner_id` is null on receipts with `source: "incoming"` (as is `custid` in v2). The creator identifier is withheld for guest-submitted provenance regardless of migration state.

A `custid` key does still appear at the top level of receipt-list responses, alongside `records` rather than inside them. That is the identifier of the customer making the request, not of a receipt's creator — a different field that happens to share the name.

### `metadata` is a v2 alias of `receipt`

"Receipt" is the current name for the record the secret's creator keeps. Conceal and generate responses emit the same serialized receipt under both names in v2:

| Version | Keys under `record`                                                     |
| ------- | ----------------------------------------------------------------------- |
| v1      | `metadata` only                                                         |
| v2      | `receipt` and `metadata` — identical objects, not two views of a record |
| v3      | `receipt` only                                                          |

Write new integrations against `receipt`.

The alias covers the record object only. Receipt responses (`GET /receipt/:key`) also return `metadata_path` and `metadata_url` as aliases of `receipt_path` and `receipt_url`; those aliases are still present in v3.

### Three distinct recipient fields

`recipients`, `recipient`, and `recipient_name` are separate fields with separate meanings — not spelling variants of one another.

| Field            | Location                                   | Value                                                                                                                                                                                            |
| ---------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `recipients`     | receipt record                             | Who the secret link was emailed to, obscured at serialization (`al***@e***.com`). In v2, a single string — `, `-joined for multiple addresses, `""` when the secret was never emailed. In v3, an array of obscured addresses, or `null` when there are none — never `""`, never `[]`. |
| `recipient`      | `details` of a conceal/generate response    | Echo of the sanitized `recipient` values submitted with the request. Always an array, `[]` when none was submitted, in every version. Not obscured — `details.recipient_safe` is the obscured form. |
| `recipient_name` | receipt record                             | Display name of the configured Incoming recipient. Set only on `source: "incoming"` receipts; null for standard secrets.                                                                            |

`show_recipients` is a convenience boolean on the receipt: true when `recipients` is non-empty.

### A requested `ttl` is clamped, not rejected

The `ttl` submitted when creating a secret is a request, not a guarantee. An out-of-range value is silently adjusted and the secret is created with the adjusted value, so clients should read the effective TTL back from the response (`secret_ttl` on the receipt) rather than assume the requested value was honored.

* **Canonical-host guests are capped at 7 days by default.** This is the policy for unaccountable traffic creating against the platform's own storage boundary. Self-hosted operators can raise or lower it via `TTL_MAX_ANONYMOUS` (config key `site.secret_options.ttl_max_anonymous`). On billing-enabled deployments the free-tier `secret_lifetime` limit is an additional ceiling.
* **Custom-domain guests use the domain owner's organization policy instead.** Although the caller is unauthenticated, the tenant owns the storage boundary. The effective ceiling is normally 14 days for a free organization or 30 days for an organization with extended expiration, still bounded by the configured `ttl_options` maximum and the 365-day software-safety limit.
* A value below the configured minimum is raised to that minimum.
* Authenticated callers are governed separately. A free-tier request above 14 days is *rejected* with an entitlement error rather than clamped, so the caller gets an explicit upgrade path instead of a shortened secret.

## Generate OpenAPI definitions

OpenAPI definitions are generated build artifacts in `generated/openapi/`; they are not committed to the repository. Generate the non-frozen definitions with:

```bash
pnpm run openapi:generate
```

This writes the v2 and v3 definitions. V1 is frozen and is generated only when explicitly requested:

```bash
pnpm run openapi:generate -- --force
```

The generator also produces an internal-only definition. Do not publish it. For generator options and output details, see [OpenAPI generation](../../scripts/openapi/README.md).

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
