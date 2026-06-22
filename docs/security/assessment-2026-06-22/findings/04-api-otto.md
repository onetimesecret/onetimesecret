# Security Assessment — REST API + Otto Web Framework

**Scope:** REST API security of OneTimeSecret (`/home/user/onetimesecret`) and the Otto web framework (`/home/user/otto`, v2.3.1).
**Mode:** READ-ONLY source review. Synthetic/local only. Owner-authorized.
**Date:** 2026-06-22
**Branch:** claude/vigilant-goldberg-97ijfl

Evidence is cited as `file:line`. Each finding is tagged **CONFIRMED** (verified in code) or **NEEDS-VALIDATION** (suspected; depends on deploy config or unread code). Severity reflects realistic impact for a default-ish deployment.

---

## Executive summary

The **Otto framework itself is in good shape**. The client-IP / trusted-proxy / X-Forwarded-For logic (the harmonization target) is carefully designed: a single canonical resolver (`Otto::Utils.resolve_client_ip`), CIDR-walk and count-based depth modes, IPv4/IPv6-aware, forwarded headers honored **only** behind a trusted proxy, and a leak-free `env['otto.via_trusted_proxy']` recorded before masking. Dynamic dispatch (`send` to route handlers) is driven by the trusted routes file, not user input, and is guarded by `ConstantResolver` (allowlist regex + forbidden-class blocklist). Static file serving has path-traversal protection. Error handling is generic in production with correlation IDs. No CORS is shipped (safe default).

The **highest-impact issues are in the OneTimeSecret integration layer**, not Otto:

| # | Finding | Severity |
|---|---|---|
| 1 | Security headers (HSTS, X-Frame-Options, CSP, Origin-CSRF) are **off by default**; CSP/nosniff absent entirely from the rack-protection stack | High |
| 2 | Cookie-authenticated `/api/*` state-changing endpoints are **exempt from token CSRF**; only fallback is `HttpOrigin`, which is **off by default** | High |
| 3 | `Rack::DetectHost` trusts forwarded **Host** headers from any RFC1918/loopback peer — an **un-harmonized** second trusted-proxy model; host-header injection from an internal/SSRF vantage | Medium |
| 4 | No app-layer rate limiting on **auth/login** and on **V2/V3 secret creation**; V1 limiter is fail-open + exempts authenticated users | Medium |
| 5 | V1 Basic Auth is **timing-distinguishable** for username enumeration (no dummy-hash mitigation, unlike V2/V3) | Low/Medium |
| 6 | No explicit request-body size / JSON depth limits in OTS app/middleware (Otto's own limits are not in OTS's path for parsed bodies) | Low/Medium |
| 7 | Multiple independent client-IP trust readers (otto, DetectHost, HealthAccessControl, rack-protection IPSpoofing) — drift risk | Low |
| 8 | V1 logs attacker-controlled `custid` (Basic Auth username) without newline sanitization (log injection, debug-level) | Low |

---

## 1. Otto framework

### 1.1 Client IP / X-Forwarded-For / trusted-proxy (CONFIRMED — strong)

The harmonization (commit "Harmonize IP / trusted-proxy handling via otto 2.3.1") is well-built.

- Single canonical resolver: `Otto::Utils.resolve_client_ip` (`/home/user/otto/lib/otto/utils.rb:112-140`). Forwarded headers (`X-Forwarded-For`, `X-Real-IP`, `X-Client-IP` — `utils.rb:15-19`) are honored **only** when `REMOTE_ADDR` is a trusted proxy (`utils.rb:124`). It walks the chain left-to-right and returns the first hop that is not itself a trusted proxy (`utils.rb:130-139`). With no config, `REMOTE_ADDR` is returned unchanged — forwarded headers from untrusted peers are ignored. This is the correct anti-spoofing model.
- Count-based depth mode ("trust last N hops", Express `trust proxy = N`): `resolve_client_ip_by_depth` (`utils.rb:172-187`) counts positions from the right and is robust to forwarded-header padding (a forged leftmost entry is never reached). RFC 7239 `Forwarded` parsing correctly handles quoted strings / IPv6 brackets and refuses to truncate at a `;` inside DQUOTEs (`utils.rb:235-262`). The two modes are mutually exclusive and validated at config time and at freeze (`config.rb:149-166,227-234,531-537`).
- `trusted_proxy?` uses real `IPAddr` CIDR containment, IPv4-mapped-IPv6 folding (`config.rb:181-201`), parsed once at registration (`config.rb:558-564`).
- `IPPrivacyMiddleware` resolves once into `env['otto.client_ip']`, is idempotent (`ip_privacy_middleware.rb:49`), records `env['otto.via_trusted_proxy']` from the **original peer before masking** (`ip_privacy_middleware.rb:59`), then masks `REMOTE_ADDR` and the forwarded headers (`ip_privacy_middleware.rb:119-135,164-172`). `Request#secure?` authorizes `X-Forwarded-Proto`/`X-Scheme` only via this leak-free flag (`request.rb:180-209`).

**Residual notes (NEEDS-VALIDATION, deployment-dependent):**
- Depth mode "ASSUMES ORIGIN LOCKDOWN" — the app must be unreachable except through the proxy tier, or a direct client can pad the forwarded header (documented at `utils.rb:152-156`). This is an inherent property of count-based trust, not a bug; verify the deployment firewalls direct access when `trusted_proxy.mode: depth`.
- OTS's filter mode trusts the broad `PRIVATE_PROXY_RANGES` regex (all RFC1918/loopback/link-local) as proxies by default (`/home/user/onetimesecret/lib/onetime/application/middleware_stack.rb:72-83,237`). For a chain like `X-Forwarded-For: <attacker-spoofed-public>, <real proxy private>`, the resolver returns the spoofed public value if the real proxy hop is private and the spoofed value is the first non-private entry. This is the standard filter-mode trade-off; it only matters if an attacker can inject XFF and reach a trusted proxy — generally not directly exploitable behind a header-stripping ingress, but worth confirming the ingress overwrites (not appends) XFF.

### 1.2 Routing / dispatch / dynamic `send` (CONFIRMED — safe)

- Routes are loaded from a trusted plaintext file (`core/router.rb:11-64`); the class/method strings come from that file, never from request data.
- Dispatch uses `send(method_name, req, res)` (`route_handlers/class_method.rb:26`, `route.rb:146-153`) where `method_name` is parsed from the route definition at load (`route_definition.rb:192-209`).
- Class resolution goes through `Otto::Security::ConstantResolver.safe_const_get` (`security/constant_resolver.rb:46-70`): allowlist regex `\A[A-Z][a-zA-Z0-9_]*(?:::...)*\z`, a `FORBIDDEN_CLASSES` blocklist (Kernel, File, Dir, Process, etc.), AND an identity check against resolved `FORBIDDEN_CONSTANTS` to catch namespace-prefix / trailing-segment inheritance bypasses (`constant_resolver.rb:62-67`). Strong.
- URL route params are merged into `req.params` (`route.rb:117-118`) but never used to select the method — no parameter-driven dispatch.

### 1.3 Static file serving / path traversal (CONFIRMED — safe)

`FileSafety#safe_file?` (`core/file_safety.rb:9-32`): strips null bytes, `File.expand_path`-normalizes, and **requires the resolved path to start with `public_dir + File::SEPARATOR`** (`file_safety.rb:25`) — blocks `../` traversal. Also requires the file be owned/group-owned and not a directory. `handle_request` unescapes `PATH_INFO` and replaces invalid UTF-8 before matching (`core/router.rb:71-89`).

### 1.4 Security headers in Otto (CONFIRMED)

Otto applies conservative defaults: `x-content-type-options: nosniff`, `x-xss-protection`, `referrer-policy` (`security/config.rb:630-636`). HSTS/CSP/X-Frame-Options are **off by default by design** and must be enabled explicitly (`otto.rb:46-51`, `config.rb:324-411`). CSP supports static or per-request nonce policies (`config.rb:343-400`, `response.rb:123-150`). Note: OTS does **not** enable these otto features (see §4) and routes its own rack-protection stack instead.

### 1.5 CSRF in Otto (CONFIRMED — not used by OTS)

Otto ships a complete HMAC-SHA256, session-bound, constant-time CSRF implementation (`security/config.rb:286-312`, `security/middleware/csrf_middleware.rb`) that refuses a generated per-process secret in production (`config.rb:683-699`). **OTS does not use it** — it uses `Rack::Protection::AuthenticityToken` instead (see §6). Informational.

### 1.6 CORS in Otto (CONFIRMED — none)

No `Access-Control-*` handling anywhere in `/home/user/otto/lib`. Safe by default (no reflected origin, no wildcard+credentials). CORS would be entirely the host app's responsibility.

### 1.7 Otto input-validation middleware (CONFIRMED — present but NOT in OTS's path)

`ValidationMiddleware` (`security/middleware/validation_middleware.rb`) enforces request-size (`max_request_size` 10 MB default), param depth (32) and key count (64) limits (`validation_middleware.rb:103-129`, `config.rb:77-79`), rejects null bytes / control chars in param names and dangerous headers, and runs a Loofah whitewash + script-injection blocklist on all string values (`validation_middleware.rb:158-183`, `helpers/validation.rb:85-95`).

Two observations:
- The script-injection blocklist (`/on\w+\s*=/i`, `/javascript:/i`, etc.) is a global denylist applied to **every** param value. For an app that stores arbitrary secret content this would be both bypassable and prone to false-positives — but it is moot here because **OTS does not mount this middleware** (OTS uses `Rack::Parser` + per-field `InputSanitizers`; see §2). Informational for otto.
- Otto's own size/depth limits therefore do **not** protect OTS's parsed request bodies (see §7).

---

## 2. Input validation & sanitization (OTS) — CONFIRMED

- `Onetime::Security::InputSanitizers` (`/home/user/onetimesecret/lib/onetime/security/input_sanitizers.rb`): allowlist `sanitize_identifier` (`:34,53-55`), multi-pass decode+`Sanitize.fragment` `sanitize_plain_text` (`:73-91`, defeats multiply-encoded payloads), CR/LF-stripping `sanitize_email` (`:40,104-106`, prevents email-header injection), allowlist `sanitize_ip_address` (`:44,116-118`). Solid, but **opt-in per logic class** — coverage depends on each `process_params` calling the right sanitizer.
- Percent-encoding guard `Rack::HandleInvalidPercentEncoding` (`lib/middleware/handle_invalid_percent_encoding.rb`): triggers `request.params` parse and returns 400 on `invalid %-encoding` (`:46-75`). **Gate caveat:** `check_enabled?` inspects only `route_definitions.first` (`:82-91`) — if the first route's class lacks `check_uri_encoding`, the check is skipped for the whole app. Same pattern in `handle_invalid_utf8.rb:89-98`. NEEDS-VALIDATION: whether these are mounted at all (not found in the universal `MiddlewareStack`) and whether every app's first route enables the flag.
- **JSON Schema (json_schemer): NOT used for request bodies.** Only used to validate config YAML at boot (`lib/onetime/operations/config/validate.rb`) and the billing catalog. Route `request=`/`response=` schema names are OpenAPI-doc metadata only. **API request bodies are not schema-validated** — they rely entirely on per-logic `process_params` + sanitizers. (CONFIRMED via repo-wide grep; only `*.rb` matches are config/billing, not request handling.)
- Redis injection: all four limiters + error tracker use parameterized `redis.eval(..., keys:, argv:)` server-side Lua — no Ruby `eval`, no string-built commands. DNS limiter sanitizes the key (`dns_rate_limiter.rb:171-173`); invite limiter canonicalizes IP via `IPAddr` (`invite_token_rate_limiter.rb:201-211`). No Redis command injection found.

---

## 3. Rate limiting — CONFIRMED (with coverage gaps)

Four dedicated limiters, all atomic-Lua, well-implemented:

| Limiter | File | Key | Limit / window | Notes |
|---|---|---|---|---|
| Passphrase | `lib/onetime/security/passphrase_rate_limiter.rb` | `passphrase:{attempts,locked}:{secret_id}` (`:134-139`) | 5 / 600s, 1800s lockout (`:28-34`) | **per-secret** (not IP) — cannot be IP-spoofed; minor lockout-DoS of a victim secret |
| Feedback | `feedback_rate_limiter.rb` | `feedback:{submissions,locked}:{ip}` (`:135-141`) | 10 / 1200s (`:28-34`) | IP-keyed |
| Invite token | `invite_token_rate_limiter.rb` | `invite_{attempts,locked}:{ip}` (`:191-197`) | 100 / 600s, 1200s lockout (`:32-38`) | IP canonicalized |
| DNS | `dns_rate_limiter.rb` | `dns:ratelimit:{domain_id}` (`:171-173`) | 100 / 3600s (`:34-37`) | per-domain |

**Coverage gaps (Medium):**
- **Auth/login: no app-layer rate limiting.** No limiter around session authentication or registration/reset (confirmed via subagent survey of `apps/web/core/controllers/authentication.rb`, `registration.rb`; no `RateLimit`/`throttle` in `lib/` beyond the four limiters + V1). Rodauth/advanced-auth mode may add its own — NEEDS-VALIDATION.
- **V2/V3 secret creation (`conceal`/`generate`): no app-layer rate limiting.** Only passphrase brute-force on retrieval is limited (V2 wires the passphrase limiter; `apps/api/v2/logic/secrets/show_secret.rb`, `reveal_secret.rb`). Anonymous `POST /api/v3/guest/secret/conceal` and `/api/v2/secret/conceal` are unthrottled in-app.
- **V1** has a general per-IP limiter (`apps/api/v1/controllers/base.rb:145-171`, key `v1:ratelimit:{event}:{ip}`, 1000/20 min for both create and read) but it **fails open if Redis errors** (`:165-168`) and **fully exempts authenticated paid users** (`:147`). The code itself calls this "vestigial — rate limits now enforced externally (infrastructure layer)" (`:124-126`).

**Key-derivation / bypass:** IP-keyed limiters use `env['otto.client_ip']` (the masked IP). Because OTS masks public IPs (typically /24 for IPv4), an entire /24 can share one bucket — accidental aggregation, but the limits are generous so practical impact is low. Spoofing requires the trusted-proxy preconditions in §1.1. The IP masking is applied uniformly, so this does not create an attacker-controlled key-rotation bypass unless XFF spoofing is possible.

---

## 4. Security headers / CSP (OTS) — CONFIRMED — High

OTS configures security via `Rack::Protection` in `lib/onetime/middleware/security.rb`, but **each component is opt-in via config** (`security.rb:73-82`: `next unless middleware_settings[middleware_key]`). The defaults in `etc/defaults/config.defaults.yaml:299-353` are:

| Protection | Default | Effect when off |
|---|---|---|
| `utf8_sanitizer` | **ON** (`!= 'false'`) | — |
| `authenticity_token` (token CSRF) | **ON** (`!= 'false'`) | — (but see §6 `/api/` bypass) |
| `http_origin` (Origin-CSRF) | **OFF** (`== 'true'`) | no Origin/Referer CSRF check |
| `xss_header` | **OFF** | no `X-XSS-Protection` |
| `frame_options` | **OFF** | **clickjacking possible** (no `X-Frame-Options`) |
| `path_traversal` | **OFF** | relies on otto's `safe_file?` only |
| `cookie_tossing` | **OFF** | subdomain cookie fixation |
| `ip_spoofing` | **OFF** | — |
| `strict_transport` (HSTS) | **OFF** | **no HSTS** — TLS-stripping / cookie over HTTP |
| `security.csp.enabled` | **OFF** (`config.defaults.yaml:352-353`) | **no Content-Security-Policy** |

Additional gaps:
- **No CSP middleware exists at all** in the rack-protection component list (`security.rb:96-202`) — even when `csp.enabled` is set, that flag drives view-layer nonce injection, not a `Content-Security-Policy` response header from this stack. NEEDS-VALIDATION of the actual CSP header path.
- **No `X-Content-Type-Options: nosniff`** in OTS's rack-protection list. (Otto's per-route handler does set `x-content-type-options: nosniff` via `security/config.rb:632` for routes that flow through Otto's `Route#call`, so API JSON responses likely get it — but the OTS web/SPA path and error responses may not. NEEDS-VALIDATION.)

**Impact:** A default OTS deployment ships without HSTS, X-Frame-Options, CSP, and Origin-based CSRF. **Remediation:** Flip the secure defaults — set `frame_options`, `strict_transport`, `http_origin`, `xss_header`, `path_traversal` to default-on (or to on-in-production), add a CSP header, and add `X-Content-Type-Options: nosniff` globally. Document that operators must not disable HSTS/Frame-Options in production.

---

## 5. CORS (OTS) — CONFIRMED — none in app code

Repo-wide grep finds `Access-Control-*` only in test fixtures (Stripe VCR cassettes) and `Caddyfile-example`. No `Rack::Cors`, no reflected-origin, no wildcard+credentials in application code. The V3/V2 `OPTIONS` preflight routes (`apps/api/v3/routes.txt`) route to logic that returns JSON but do not emit CORS headers from app code. **Safe by default** (cross-origin browser calls simply fail). NEEDS-VALIDATION: confirm CORS is either intentionally absent or enforced at the proxy (Caddy) and not misconfigured there.

---

## 6. CSRF (OTS) — CONFIRMED — High

- Token CSRF via `Rack::Protection::AuthenticityToken` (param `shrimp`, masked-token BREACH mitigation) — `lib/onetime/middleware/security.rb:120-154`. Masked token exposed to the SPA via `X-CSRF-Token` response header (`lib/onetime/middleware/csrf_response_header.rb:29-39`), mounted before Security so even 403s carry a fresh token (`middleware_stack.rb:365-368`).
- **The `allow_if` lambda bypasses CSRF for the entire `/api/` prefix** (`security.rb:142`: `return true if req.path.start_with?('/api/')`), plus `/auth/sso/*`, `/auth/email-login`, `/billing/webhook`.
- **Problem:** Many `/api/*` POST/PATCH/DELETE endpoints accept **`auth=sessionauth`** (cookie auth) — V3 `POST /secret/conceal|generate`, `PATCH/POST /receipt/:id` (`apps/api/v3/routes.txt`), V2 equivalents, and `/api/account` mutations (destroy account, change password, apitoken rotation), `/api/organizations`, `/api/domains`. The `SessionAuthStrategy` authenticates from the session cookie (`apps/api/v3/auth_strategies.rb:39`). Because the shrimp-token check is skipped for all `/api/`, **the only remaining CSRF defense for these cookie-authenticated mutations is `Rack::Protection::HttpOrigin` — which is OFF by default (§4).**
- **Impact:** In a default deployment, a logged-in user visiting a malicious page can have state-changing API calls (e.g. account deletion, password/apitoken change, secret creation) executed with their session cookie, with no CSRF token and no Origin check. The comment "no session = no CSRF vector" (`security.rb:137-141`) is inaccurate for the session-auth `/api/*` routes.
- **Remediation:** Do not blanket-exempt `/api/`. Exempt only stateless auth (requests presenting Basic Auth / Bearer, or with no session cookie); require the shrimp token (or a verified custom header) for cookie-authenticated API mutations. At minimum, default `http_origin` to ON.

---

## 7. Request size / content-type / HPP — Low/Medium

- Content-Type: `Onetime::Middleware::NormalizeContentType` then `Rack::Parser` with explicit parsers for `application/json` and `application/x-www-form-urlencoded` only (`middleware_stack.rb:52-55,307-308`). Other content types are not parsed. Reasonable.
- **No explicit request-body size cap or JSON depth/key limit in OTS app or middleware** (CONFIRMED via grep; `Rack::ContentLength` at `middleware_stack.rb:293` only sets the header, does not reject). Otto's `ValidationMiddleware` size/depth caps are **not mounted by OTS**. So body-size and JSON-bomb protection rely on Rack/Puma/proxy defaults. NEEDS-VALIDATION: Puma/Caddy `client_max_body_size`; secret-length cap in the Secret model.
- HPP: form parsing via `Rack::Utils.parse_nested_query` (last-value-wins, Rack-standard); no custom multi-value handling that creates confusion was found.

---

## 8. Error handling / info disclosure / enumeration — mostly CONFIRMED-safe

- **No stack traces / internal paths to clients.** Typed errors render `error.to_h` = `{error, error_type, error_key, ...}` only (`lib/onetime/errors.rb:65-72,144-151,235-244`) with safe status codes via `otto_hooks`. Unhandled 500s return the SPA shell (web) or a hardcoded `{error:'Internal Server Error'}` (auth) — backtrace logged server-side only. `RACK_ENV` defaults to `production` (`config.ru:21`).
- Otto's own error handler is generic in production (`/home/user/otto/lib/otto/core/error_handler.rb:258-294`), uses `SecureRandom` correlation IDs, and sanitizes backtrace paths before logging (`logging_helpers.rb:152-271`). Error IDs and dev detail are gated on `Otto.env?(:dev)`.
- OTS error handler redacts sensitive headers (Authorization, Cookie, X-API-Key, X-Auth-Token) from Sentry debug logs (`lib/onetime/error_handler.rb:72-95`).
- **Enumeration — mitigated:** Secret retrieval raises the same `OT::MissingSecret`/404 for "does not exist" and "not viewable" (V1 `apps/api/v1/logic/secrets/show_secret.rb:27`; V2 equivalents). Login returns generic "Invalid credentials". V2/V3 Basic Auth uses a **dummy customer with a real BCrypt hash** for constant-time comparison to block username enumeration (`lib/onetime/application/auth_strategies/basic_auth_strategy.rb:42-91`). Account-creation/reset return identical messages for new vs existing accounts.
- **Enumeration — V1 exception (Low/Medium, CONFIRMED):** V1's controller-level `authorized` does **not** use the dummy-hash mitigation — `apps/api/v1/controllers/base.rb:68-71` loads the customer and only runs `apitoken?` when the customer exists, so a non-existent username skips the (expensive) token check. This makes **V1 Basic Auth timing-distinguishable for username enumeration**. Messages are uniform (`'Invalid credentials'`), so this is timing-only. Remediation: mirror the V2/V3 dummy-customer constant-time path in V1, or deprecate V1 auth.

---

## 9. Additional findings

### 9.1 `Rack::DetectHost` — un-harmonized trusted-proxy model (Medium, CONFIRMED)

`lib/middleware/detect_host.rb` decides whether to trust forwarded **Host** headers (`X-Forwarded-Host`, `X-Original-Host`, `Apx-Incoming-Host`, RFC7239 `Forwarded`) purely on `private_ip?(env['REMOTE_ADDR'])` (`detect_host.rb:156-165,240-263`) — its **own** RFC1918/loopback check, independent of the otto 2.3.1 trusted-proxy config that the IP path was harmonized onto. The detected host is reflected into routing (`DomainStrategy`), URL generation, and into response headers `O-Display-Domain` / `O-Domain-Strategy` (`lib/onetime/middleware/domain_strategy.rb:122-149`; reflection is guarded by `basically_valid?` at `:133`, which mitigates header injection but not host confusion).

**Impact:** Any client that reaches the app from a private/loopback source (sidecar, in-cluster pod, SSRF pivot, a misconfigured proxy that forwards from a private egress) can set `X-Forwarded-Host` to spoof the host → host-header injection affecting domain classification, generated links (password-reset / share URLs), and cache keys. Unlike otto's IP resolver, there is no operator-controlled CIDR allowlist here — "any private IP" is the trust boundary.

Compounding: because `IPPrivacyMiddleware` runs first and rewrites `REMOTE_ADDR` to the masked client IP, `DetectHost`'s `private_ip?(REMOTE_ADDR)` actually evaluates a **rewritten** value. For a public client this is a masked-public IP (forwarded host not trusted — safe); for a private/exempt client `REMOTE_ADDR` stays private (forwarded host trusted — the spoofing window). NEEDS-VALIDATION of the exact masked value in your deployment, but the trust model is the concern.

**Remediation:** Drive `DetectHost`'s trust decision from the same `Otto::Security::Config#trusted_proxy?` / `env['otto.via_trusted_proxy']` used by the IP path, and/or validate the detected host against an allowlist of configured canonical/custom domains rather than trusting any private peer.

### 9.2 Multiple independent client-IP trust readers — drift risk (Low, CONFIRMED)

At least four code paths make their own IP-trust decision: otto's resolver (`env['otto.client_ip']`), `DetectHost.private_ip?` (§9.1), `HealthAccessControl` using `Rack::Request#ip` directly instead of `env['otto.client_ip']` (`lib/onetime/middleware/health_access_control.rb:35,53-54`), and `Rack::Protection::IPSpoofing` (when enabled). They currently agree in the common cases because masking normalizes `REMOTE_ADDR`/XFF, but each is a separate place to get wrong on the next change. Recommend funnelling all client-IP trust reads through `env['otto.client_ip']` / `env['otto.via_trusted_proxy']`.

### 9.3 Log injection of attacker-controlled username (Low, CONFIRMED)

V1 `authorized` interpolates the Basic Auth username (`custid`) into log lines without newline sanitization: `OT.ld "[authorized] Attempt for '#{custid}' via #{req.client_ipaddress} (basic auth)"` (`apps/api/v1/controllers/base.rb:67`, also `:73,:81`). `custid` is fully attacker-controlled (decoded from the Authorization header). With a plain-text logger this allows CRLF log-injection / forged log lines. It is `OT.ld` (debug-level), so impact is limited to debug-enabled environments and a structured (JSON) logger neutralizes it. Remediation: strip CR/LF before logging untrusted identifiers (the codebase already has `NEWLINE_STRIP_PATTERN`).

### 9.4 Public unauthenticated APIs (informational)

`/api/incoming` is `noauth`-only (fully public secret submission) and V3 `/api/v3/guest/*` allows anonymous conceal/reveal/burn (`apps/api/v3/routes.txt`). These are intentional product features but, combined with §3 (no creation rate limit on V2/V3), are the surface most exposed to abuse/flooding. Pair with a creation rate limit.

---

## Verification status & method

- **CONFIRMED** items were read directly in the cited files in this assessment.
- **NEEDS-VALIDATION** items depend on runtime config (`config.defaults.yaml` overrides, `site.middleware.*`, `site.network.trusted_proxy.*`), the reverse-proxy (Caddy/Puma) config, or code paths not fully traced (Otto's default 500 for API apps, the exact CSP header emission path, whether the percent/utf8 middleware are mounted). Recommended next step: stand up the local app with synthetic data and confirm (a) which security headers are present on `/`, `/api/v3/...`, and an error response; (b) that a cross-origin POST with a stolen session cookie to `/api/v3/secret/conceal` succeeds without a shrimp token; (c) `X-Forwarded-Host` spoofing from a private source.
