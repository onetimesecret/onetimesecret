# V1 API Compatibility Reference

V1 is **frozen**. It emits v0.23.x field names and values for backward
compatibility. No new fields or endpoints will be added. New functionality
targets V2/V3.

## Field Names

V1 responses use legacy field names. Both old and new names may coexist,
but old names are always present.

| v0.24 internal       | V1 response name       | Notes                          |
|----------------------|------------------------|--------------------------------|
| `identifier`         | `metadata_key`         |                                |
| `secret_identifier`  | `secret_key`           | Omitted when state=received    |
| `has_passphrase`     | `passphrase_required`  |                                |
| `recipients`         | `recipient`            | Array (singular key name)      |
| `receipt_ttl`        | `metadata_ttl`         | Actual seconds remaining (TTL) |
| `secret_value`       | `value`                |                                |
| `share_domain` nil   | `share_domain` `""`    | Empty string, never null       |
| `owner_id`           | `custid`               | Email address, not UUID        |

## State Values

| v0.24 internal | V1 response |
|----------------|-------------|
| `shared`       | `new`       |
| `previewed`    | `viewed`    |
| `revealed`     | `received`  |

When `state=received`, the response omits `secret_key` and `secret_ttl`,
and includes the `received` timestamp. The `received` timestamp falls back
to the `revealed` value when the deprecated `received` field is empty.

## Authentication

V1 uses HTTP Basic Auth exclusively. The username is the account email;
the password is the API token. Session/cookie auth is rejected.

Anonymous access is allowed on these endpoints:

- `GET /status`
- `POST /share`
- `POST /generate`
- `POST /create`
- `POST /secret/:key`
- `GET /private/:key` (aliases: `/metadata/:key`, `/receipt/:key`)
- `POST /private/:key` (aliases: `/metadata/:key`, `/receipt/:key`)
- `POST /private/:key/burn` (aliases: `/metadata/:key/burn`, `/receipt/:key/burn`)

Anonymous secrets set `custid` to `"anon"`.

## Auth Modes

The server-wide `AUTHENTICATION_MODE` setting controls V1 behavior:

| Mode       | Effect                                                     |
|------------|------------------------------------------------------------|
| `disabled` | All V1 endpoints return 404                                |
| `simple`   | Basic Auth works; anonymous allowed where configured       |
| `full`     | Same as `simple` for V1 (V1 does not require PG/RabbitMQ) |

## Known Differences from v0.23.x

- **`share_domain`**: Always an empty string in V1 responses (v0.23.x could
  return the configured domain). Behavior is functionally identical for
  single-domain deployments.
- **`custid` format**: v0.24 stores UUIDs internally. V1 translates back to
  email via `opts[:custid]`, falling back to `v1_custid` and `custid` fields.
  The resolution chain: caller-supplied email > `v1_custid` (migrated) >
  `custid` (legacy) > `"anon"`.
- **Key length**: v0.24 generates ~63-character keys (v0.23 used ~31 chars).
  This is intentional — v0.24 uses a more secure identifier algorithm.
  `secret_shortkey` (burn responses) is 8 chars (was 6). Clients must treat
  keys as opaque, variable-length strings.
- **Passphrase minimum**: Configurable via `site.secret_options.passphrase.minimum_length`
  (v0.23 hardcoded 8 chars). The lower bound is acceptable; operators can
  raise it via config if their security policy requires longer passphrases.
- **`shrimp` field removed**: v0.23 included a `shrimp` CSRF token in error
  responses. v0.24 omits it — V1 uses Basic Auth exclusively, so the
  session-based CSRF token was never part of the API contract.
- **Max TTL**: v0.23 capped at 14 days (plan-based). v0.24 enforces
  plan-aware limits: 14 days for free tier (billing enabled), 30 days for
  paid plans or when billing is disabled (self-hosted). See `process_ttl`
  in `base_secret_action.rb`.

## New Endpoints (v0.24)

These endpoints are additive — they did not exist in v0.23 and do not
affect existing clients. They provide semantic parity with the rest of
the application, which no longer uses the term "metadata" (too vague).

- **`POST /create`**: Alias for `/share`. Matches the web UI action name.
- **`GET/POST /receipt/:key`**: Alias for `/private/:key` and `/metadata/:key`.
- **`GET /receipt/recent`**: Alias for `/private/recent` and `/metadata/recent`.
- **`POST /receipt/:key/burn`**: Alias for `/private/:key/burn`.

## Validation Tooling

Capture baseline responses from a running instance, then diff against a
candidate build:

```bash
# Capture from v0.23.x baseline
scripts/api-validation/bin/v1-capture.sh http://localhost:3000 ./captures/v0.23.6 user@example.com TOKEN --form

# Capture from v0.24.x candidate
scripts/api-validation/bin/v1-capture.sh http://localhost:3000 ./captures/v0.24.0 user@example.com TOKEN

# Diff the two runs
scripts/api-validation/bin/v1-diff.sh ./captures/v0.23.6/RUN_ID ./captures/v0.24.0/RUN_ID ./diffs/report.json
```

The `--form` flag sends POST data as `application/x-www-form-urlencoded`
(required for v0.23.x, which lacks `Rack::JSONBodyParser`).

The diff report flags: status code changes, field additions/removals, type
changes, header changes, and value changes in key fields.

## Related Commits

- `56bc83dfe` Document V1 compat policy decisions inline
- `f9e4bd9e7` Map V1 state values to v0.23.x vocabulary
- `789edff55` Restore V1 custid (email) and secret_shortkey fields
- `50d5f4267` V1 API compat: match v0.23 contract; fix validation tooling (#2626)
