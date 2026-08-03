# Onetime Secret - API Documentation

The authoritative API documentation is published at [api.onetimesecret.com](https://api.onetimesecret.com).

## API Versions

Onetime Secret provides three versions of its API:

* **v1**: The original API for creating and viewing secrets. Requests are form-encoded and responses are JSON. This version receives limited support mainly to keep parity with new fields but in general does not receive new features (new or renamed fields are added but existing fields are not removed or renamed). For new integrations, we recommend using v2 or v3.
* **v2**: A modern, fully JSON REST API. All field values are returned as strings which can be both a blessing because it eliminates guesswork about field types but also a curse because it requires more parsing on the client side. This version has been superseded by v3 but is still maintained for backward compatibility.
* **v3**: Our most recent API version, used by the UI (Vue-based frontend). The API is substantially similar to v2 but field values are returned as JSON primitive types (strings, numbers, booleans, arrays, objects). This version is the most actively developed and receives all new features and updates.

## Authentication

The REST API uses HTTP Basic auth. The **username is the account email or the customer external ID** (`ur…` prefix); the **password is the API token** (generated on the Account > API settings page or via `bin/ots apitoken`).

The username is **not** the organization ID (`on…` prefix) and **not** the UUIDv7 `owner_id` that appears in API responses — neither resolves to a customer.

```bash
curl -u 'user@example.com:APITOKEN' https://us.onetimesecret.com/api/v2/receipt/recent
```

## Response Field Notes

These conventions apply to secret and receipt responses. Field value *types* differ by version (see [API Versions](#api-versions)); the field *meanings* below are the same across versions unless noted.

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

* **Anonymous (unauthenticated) secrets are capped at 7 days by default.** The ceiling is read on every deployment, whether or not billing is enabled. Self-hosted operators can raise or lower it via `TTL_MAX_ANONYMOUS` (config key `site.secret_options.ttl_max_anonymous`), bounded by the configured `ttl_options` maximum and a 365-day hard limit. On deployments with billing enabled the free-tier `secret_lifetime` limit applies as an additional ceiling, so an anonymous caller never receives a longer TTL than an authenticated free-tier user. **onetimesecret.com enforces 7 days.**
* A value below the configured minimum is raised to that minimum.
* Authenticated callers are governed separately. A free-tier request above 14 days is *rejected* with an entitlement error rather than clamped, so the caller gets an explicit upgrade path instead of a shortened secret.

## OpenAPI Definitions

Generated OpenAPI definitions are available at:
- `generated/openapi/openapi.v1.json`
- `generated/openapi/openapi.v2.json`
- `generated/openapi/openapi.v3.json`

Run `pnpm run openapi:generate` to regenerate from source schemas.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
