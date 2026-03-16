# Test Accounts and API Credentials

Create customer accounts and generate Basic Auth API tokens from the CLI for development and testing.

## Quick Start

```bash
# Create a test account and get curl-ready API credentials
bin/ots apitoken test@example.com --create

# Output:
#   API Token: k3j8f...
#   Authorization: Basic dGVzdEBleGFtcGxlLmNvbTprM2o4Zi4uLg==
#
#   curl -u 'test@example.com:k3j8f...' https://localhost:3000/api/v2/account
#   curl -H 'Authorization: Basic dGVzdEBleGFtcGxlLmNvbTprM2o4Zi4uLg==' https://localhost:3000/api/v2/account
```

## API Token Management

```bash
# Regenerate token for an existing customer
bin/ots apitoken user@example.com

# Show current token without regenerating
bin/ots apitoken user@example.com --show

# Create account with a specific role
bin/ots apitoken user@example.com --create --role colonel

# Create with an explicit password (otherwise random)
bin/ots apitoken user@example.com --create --password s3cret
```

Regenerating a token invalidates the previous one immediately.

## Auth Modes

The command auto-detects the active auth mode from config:

- **Simple mode** (`authentication.mode: simple`): Creates a Redis-only customer record.
- **Full mode** (`authentication.mode: full`): Creates both a Redis customer and a Rodauth SQL account. Requires a running auth database.

The API token itself is stored in Redis regardless of mode.

## Customer Management

```bash
# Create a customer without generating an API token
bin/ots customers --create user@example.com

# Create an admin account
bin/ots customers --create admin@example.com --role colonel

# List all customers
bin/ots customers --list
```

## Billing and Entitlements

Billing is only available in full auth mode. When billing is enabled, new accounts start at the free tier with default entitlements. The `apitoken` command notes this in its output.

To test with a specific plan, assign it through the web UI or Stripe dashboard after account creation.

## How Basic Auth Works

The REST API accepts credentials via the standard `Authorization: Basic` header. The value is `base64(email:apitoken)`.

```
GET /api/v2/account HTTP/1.1
Authorization: Basic dGVzdEBleGFtcGxlLmNvbTprM2o4Zi4uLg==
```

Routes that accept Basic Auth are marked with `auth=basicauth` (or `auth=sessionauth,basicauth` for dual-mode) in the route definitions under `apps/api/*/routes.txt`.

Not all API endpoints accept Basic Auth. Token generation (`POST /apitoken`) requires session auth only.
