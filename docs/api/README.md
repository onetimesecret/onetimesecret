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

These conventions apply to secret/receipt responses in v2 and v3:

* **`custid` is deprecated** — always null on post-migration records. Read `owner_id` instead. (v1 is the exception: it translates `custid` back to an email address; see `apps/api/v1/COMPAT.md`.)
* **`metadata` and `receipt` are duplicates in v2** — v2 responses carry both objects under `record` with identical content as an intentional backward-compat alias (`metadata` is the legacy name for `receipt`). v3 removes the alias and returns only `receipt`.
* **Recipient fields have three distinct meanings**: `recipients` on the receipt is a stored, obscured string (e.g. `to***@m***.com`); `details.recipient` is a request-echo array of what was submitted at creation; `recipient_name` is a display name used only for incoming secrets and is null for standard secrets.

## OpenAPI Definitions

Generated OpenAPI definitions are available at:
- `generated/openapi/openapi.v1.json`
- `generated/openapi/openapi.v2.json`
- `generated/openapi/openapi.v3.json`

Run `pnpm run openapi:generate` to regenerate from source schemas.

---

Remember to keep your API keys and sensitive information secure and never commit them to version control systems.
