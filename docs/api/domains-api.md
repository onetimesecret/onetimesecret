---
labels: api, custom-domains
---
# Domains API Reference

**Last Updated:** 2025-12-21
**Base Path:** `/api/domains`
**Related Issue:** #1887

> **Note:** This is an internal API, not part of the versioned public API.

## Authentication

All endpoints require authentication via one of:

| Method | Header | Description |
|--------|--------|-------------|
| Session | Cookie: `onetime.session` | Browser-based authentication |
| HTTP Basic | `Authorization: Basic <credentials>` | API client authentication |

## Organization Context

Domains are owned by organizations, not individual customers. Organization context is determined by priority:

1. **Explicit selection** - Organization ID stored in session (from org switcher)
2. **Domain-based routing** - Inferred from custom domain in request
3. **Default organization** - Customer's workspace marked `is_default = true`
4. **First available** - First organization the customer belongs to
5. **Auto-created workspace** - Self-healing fallback for legacy accounts

This allows customers to belong to multiple organizations while ensuring one is always selected for each request.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/` | List all domains for organization |
| POST | `/add` | Add a new domain |
| GET | `/:extid` | Get domain details |
| POST | `/:extid/remove` | Remove domain from organization |
| POST | `/:extid/verify` | Verify domain DNS configuration |
| GET | `/:extid/brand` | Get domain branding settings |
| PUT | `/:extid/brand` | Update domain branding |
| GET | `/:extid/logo` | Get domain logo |
| POST | `/:extid/logo` | Upload domain logo |
| DELETE | `/:extid/logo` | Remove domain logo |
| GET | `/:extid/icon` | Get domain icon |
| POST | `/:extid/icon` | Upload domain icon |
| DELETE | `/:extid/icon` | Remove domain icon |

## Endpoint Details

### POST /add

Add a new custom domain to the authenticated user's organization.

**Request:**
```json
{
  "domain": "secrets.acme.com"
}
```

**Response (201 Created):**
```json
{
  "success": true,
  "record": {
    "extid": "cd1a2b3c4d",
    "display_domain": "secrets.acme.com",
    "verified": false,
    "resolving": false,
    "txt_validation_host": "_onetime-challenge.secrets.acme.com",
    "txt_validation_value": "ots-verify-abc123..."
  }
}
```

**Errors:**
| Code | Message | Cause |
|------|---------|-------|
| 400 | Please enter a domain | Empty domain field |
| 400 | Not a valid public domain | Invalid domain format |
| 400 | Domain already registered in your organization | Duplicate in same org |
| 400 | Domain is registered to another organization | Domain belongs to different org |

### GET /:extid

Get details for a specific domain by external ID.

**Response (200 OK):**
```json
{
  "success": true,
  "record": {
    "extid": "cd1a2b3c4d",
    "display_domain": "secrets.acme.com",
    "base_domain": "acme.com",
    "subdomain": "secrets.acme.com",
    "trd": "secrets",
    "tld": "com",
    "sld": "acme",
    "verified": true,
    "resolving": true,
    "status": "active"
  }
}
```

### POST /:extid/verify

Trigger DNS verification for the domain's TXT record.

**Response (200 OK):**
```json
{
  "success": true,
  "record": {
    "extid": "cd1a2b3c4d",
    "display_domain": "secrets.acme.com",
    "verified": true,
    "resolving": true
  }
}
```

### PUT /:extid/brand

Update branding settings for a custom domain.

**Request:**
```json
{
  "primary_color": "#dc4a22",
  "font_family": "sans",
  "corner_style": "rounded",
  "locale": "en",
  "button_text_light": false,
  "allow_public_homepage": false,
  "allow_public_api": false
}
```

**Response (200 OK):**
```json
{
  "success": true,
  "record": {
    "extid": "cd1a2b3c4d",
    "brand": {
      "primary_color": "#dc4a22",
      "font_family": "sans",
      "corner_style": "rounded",
      "locale": "en"
    }
  }
}
```

## Common Response Fields

| Field | Type | Description |
|-------|------|-------------|
| `extid` | string | External identifier (e.g., `cd1a2b3c4d`) |
| `display_domain` | string | Full domain name |
| `verified` | boolean | TXT record validation status |
| `resolving` | boolean | DNS A/CNAME record resolves correctly |
| `status` | string | Domain status (pending, active, etc.) |

## Error Response Format

```json
{
  "success": false,
  "message": "Error description"
}
```

## Key Files

| File | Description |
|------|-------------|
| `apps/api/domains/routes.txt` | Route definitions |
| `apps/api/domains/logic/domains/add_domain.rb` | AddDomain logic |
| `apps/api/domains/logic/domains/get_domain.rb` | GetDomain logic |
| `apps/api/domains/logic/domains/verify_domain.rb` | VerifyDomain logic |
