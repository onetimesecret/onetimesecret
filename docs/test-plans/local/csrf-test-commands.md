# CSRF Protection Verification Commands

These commands verify that SameSite=Lax still blocks cross-site POST
requests while allowing cross-site GET redirects (Stripe checkout).

## Test 1: HTML Form (Cross-Site POST to V1 API)

Open `docs/test-plans/local/csrf-test.html` in browser via `file://` path,
then click "Submit Cross-Site POST".

Note: The HTML form targets the V1 API which accepts form-encoded data.

Expected: 401 Unauthorized or 403 Forbidden


## Test 2: cURL with Spoofed Origin (V2 JSON API)

```bash
curl -X POST https://dev.onetimesecret.com/api/v2/secret \
  -H "Content-Type: application/json" \
  -H "Origin: https://evil-site.com" \
  -d '{"secret":"test","ttl":"3600"}'
```

Expected: 401/403 - Origin header mismatch caught by Rack::Protection::HttpOrigin


## Test 3: cURL without Session (V2 JSON API)

```bash
curl -X POST https://dev.onetimesecret.com/api/v2/secret \
  -H "Content-Type: application/json" \
  -d '{"secret":"test","ttl":"3600"}'
```

Expected: 401 Unauthorized - no session cookie


## Test 4: cURL without Session (V3 JSON API)

```bash
curl -X POST https://dev.onetimesecret.com/api/v3/secret \
  -H "Content-Type: application/json" \
  -d '{"secret":"test","ttl":3600}'
```

Expected: 401 Unauthorized - no session cookie

Note: V2 API expects all fields as strings, V3 API uses JSON primitives (ttl as integer).
