# SPA / Frontend Security Assessment — OneTimeSecret

**Scope:** Vue 3 + TypeScript + Vite SPA (`src/`), server-rendered bootstrap via `rhales`
(`apps/web/core/templates/`), security middleware (`lib/onetime/`, `apps/api/v1/`).
**Branch:** `claude/vigilant-goldberg-97ijfl`
**Date:** 2026-06-22
**Method:** READ-ONLY source review. No files modified. Evidence cited as `file_path:line`.
Findings marked **CONFIRMED** (verified in source) or **NEEDS-VALIDATION** (requires runtime
confirmation or third-party dependency review).

---

## Executive Summary

The SPA is, on the whole, well-built from a frontend-security standpoint. The core product
surface — displaying a decrypted secret — renders the secret value as **text** (safe binding),
never as HTML, never in the URL, and never in persistent storage. There is exactly one `v-html`
in the application code, and it is DOMPurify-sanitized. Auth/session is HttpOnly-cookie based;
the CSRF token lives in in-memory Pinia state, not in JS-accessible storage. A dedicated
open-redirect validator exists and is used. No external/CDN scripts; everything is bundled
same-origin.

The most material issues are **defense-in-depth defaults that ship OFF**: CSP, X-Frame-Options,
HSTS and all other `Rack::Protection` security headers default to **disabled** in the shipped
config. A secondary issue is that production **source maps are generated** and decrypted secret
values are **not explicitly cleared from SPA memory** after viewing.

| # | Finding | Severity |
|---|---------|----------|
| 1 | CSP disabled by default (`CSP_ENABLED` default `false`) | **HIGH** |
| 2 | X-Frame-Options / HSTS / all Rack::Protection headers disabled by default | **HIGH** |
| 3 | Production source maps generated (`sourcemap: true`) | **MEDIUM** |
| 4 | Decrypted secret value not cleared from SPA memory after view | **MEDIUM** |
| 5 | `v-html` in GlobalBroadcast (DOMPurify-mitigated) | **LOW** |
| 6 | DNS widget script injected without CSP nonce | **LOW / NEEDS-VALIDATION** |
| 7 | `__BOOTSTRAP_ME__` server-side JSON encoding relies on rhales (dep) | **INFO / NEEDS-VALIDATION** |
| - | XSS sinks, token storage, open-redirect, i18n-HTML, SRI | **No issue found (positive)** |

---

## 1. CSP Disabled by Default — HIGH (CONFIRMED)

**Evidence:**
- `etc/defaults/config.defaults.yaml:352-353`
  ```yaml
  csp:
    enabled: <%= ENV['CSP_ENABLED'] == 'true' || false %>
  ```
- CSP header is only emitted when `site.security.csp.enabled == true`:
  `apps/api/v1/controllers/helpers.rb:171` → `return if OT.conf.dig('site','security','csp','enabled') != true`

**Detail:** When enabled, the CSP itself is **strict and well-designed**
(`apps/api/v1/controllers/helpers.rb:176-208`):
- `default-src 'none'`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`,
  `frame-ancestors 'none'`.
- `script-src 'nonce-#{nonce}'` — **nonce-only, no `unsafe-inline`/`unsafe-eval`** for scripts
  (comment explicitly notes omitting `unsafe-inline` so CSP Level 1 agents can't bypass the nonce).
- The single-bundle Vite build (`vite.config.ts:249-280`, `codeSplitting: false`) exists
  specifically to make nonce management tractable.
- Caveat: `style-src 'self' 'unsafe-inline'` (`helpers.rb:180,196`) — inline styles allowed
  (needed for Vite/Vue style injection); minor, low risk for a secrets app.

**Impact:** Out of the box, there is **no CSP**. The single layer of strong mitigation against
XSS — should any sink be introduced or any dependency be compromised — is absent unless the
operator explicitly sets `CSP_ENABLED=true`. For a product whose entire value is confidentiality
of a secret displayed in the DOM, the strict CSP should be the default-on baseline.

**Remediation:** Default `CSP_ENABLED` to `true` (opt-out, not opt-in). Document the
dev-mode relaxation that already exists (`helpers.rb:176-191`). Consider enabling the
commented-out `require-trusted-types-for 'script'` (`helpers.rb:189,205`).

---

## 2. Clickjacking / Transport / Other Security Headers Disabled by Default — HIGH (CONFIRMED)

**Evidence — `etc/defaults/config.defaults.yaml`:**
- `frame_options` (X-Frame-Options, clickjacking) → `:322` default **false**
- `strict_transport` (HSTS) → `:338` default **false**
- `http_origin` (Origin-based CSRF) → `:314` default **false**
- `xss_header` → `:318` default **false**
- `path_traversal`, `cookie_tossing`, `ip_spoofing` → `:326,330,334` default **false**

These keys gate the corresponding `Rack::Protection` middleware in
`lib/onetime/middleware/security.rb:96-202` (each `use` is `next unless middleware_settings[key]`,
`security.rb:76`).

**Note on layering:** Clickjacking is partly covered *when CSP is on* via
`frame-ancestors 'none'` (`helpers.rb:187,203`), and a `Referrer-Policy` is set client-side via
meta tag (`apps/web/core/templates/partials/head-base.rue:7`,
`strict-origin-when-cross-origin`). `X-Content-Type-Options: nosniff` and a `Permissions-Policy`
are also set via meta (`head-base.rue:8-9`). But with **both** CSP and `frame_options` defaulting
off, a default install has **neither** `X-Frame-Options` nor `frame-ancestors` — i.e. it is
**framable / clickjackable by default**. HSTS being off by default also leaves transport
downgrade exposure for installs not already forcing HTTPS at a proxy.

**Impact:** Default deployment is embeddable in an attacker iframe (clickjacking / UI redress
against the reveal/burn buttons), and lacks HSTS. COOP/COEP are not set anywhere
(searched; none found).

**Remediation:** Default `frame_options` and `strict_transport` to `true`
(or DENY for frame options). Ship secure defaults; let operators opt out for niche embedding
needs. Consider adding `Cross-Origin-Opener-Policy: same-origin`.

---

## 3. Production Source Maps Generated — MEDIUM (CONFIRMED)

**Evidence:**
- `vite.config.ts:283` → `sourcemap: true` (main/production build).
- `vite.config.local.ts:38` → `sourcemap: true` (committed local build).

**Mitigating factors (CONFIRMED):**
- Sentry maps are uploaded via CI, not at build time (`vite.config.ts:219-220`), and the build
  drops `console`/`debugger` in prod (`vite.config.ts:272-277`, `dropConsole: true`).
- `public/web/dist/` is git-ignored (`.gitignore:52-53`), so maps are not committed to the repo.

**Impact / NEEDS-VALIDATION:** Whether `.map` files are publicly served depends on
deployment. If the static-file middleware serves `public/web/dist/assets/*.map`, the full
un-minified source (and inline comments) is exposed to anyone, easing discovery of any future
client-side weakness. The build emits maps unconditionally; there is no
`sourcemap: 'hidden'` and no post-build step observed that deletes `.map` files from the
served directory.

**Remediation:** Use `sourcemap: 'hidden'` for production (emit maps for Sentry upload but
omit the `//# sourceMappingURL` footer), or delete `*.map` from the served `dist` after CI
uploads them to Sentry. Confirm the static-file server (`MIDDLEWARE_STATIC_FILES`,
`config.defaults.yaml:302`) does not serve `.map` files.

---

## 4. Decrypted Secret Value Not Cleared From SPA Memory — MEDIUM (CONFIRMED)

**Evidence:**
- Secret value held in Pinia refs: `src/shared/stores/secretStore.ts:61-62`
  (`record`, `details`).
- `clear()`/`$reset()` exist and null the refs: `secretStore.ts:203-216`.
- **No caller** of `secretStore.clear()` / `$reset()` from the reveal/display flow
  (grep over `src/apps/secret/` and `src/shared/components/base/` returned none). The only
  `onUnmounted` hooks in the secret-display components remove a resize listener, not the secret
  (`src/apps/secret/components/branded/BaseSecretDisplay.vue:84-86`).

**Detail:** After a recipient reveals a secret, the plaintext `record.value.secret_value`
remains on the JS heap (and reachable via the live Pinia store) until navigation tears down the
store, the tab closes, or GC reclaims it — none of which is explicit or guaranteed promptly.

**Impact:** Extended in-memory residency of plaintext widens the window for memory-scraping,
heap-dump, or a chained XSS to read the already-revealed value. Lower severity because reading
it still requires code execution in the page (which CSP would block) and the secret is one-time.

**Remediation:** Call `secretStore.clear()` in `onBeforeUnmount` of the secret-display
container, and after a successful copy/burn, to proactively null the plaintext.

---

## 5. `v-html` in GlobalBroadcast (DOMPurify-mitigated) — LOW (CONFIRMED)

**Evidence:**
- The only application-code `v-html`: `src/shared/components/ui/GlobalBroadcast.vue:139`
  `<span v-html="sanitizedContent"></span>`.
- Sanitization: `GlobalBroadcast.vue:50-57` — DOMPurify with a tight allowlist
  (`ALLOWED_TAGS: ['a']`, `ALLOWED_ATTR: ['href','target','rel','class']`).
- Source of `content`: server bootstrap `global_banner` (admin/operator-set in Redis),
  passed `BaseLayout.vue:56` → `:content="global_banner ?? null"`, read from
  `bootstrapStore` (`BaseLayout.vue:20`). It is **not** end-user-controlled.

**Subtlety (worth noting):** `GlobalBroadcast.vue:43-47` runs `decodeHTMLEntities()` (assigns to
a detached `<textarea>.innerHTML` then reads `.value`) **before** `DOMPurify.sanitize()`. Order
is correct (decode → sanitize → bind), and DOMPurify with `ALLOWED_TAGS:['a']` strips scripts/
event handlers, so this is safe. The detached-textarea `innerHTML` write does not execute
scripts. No `href="javascript:"` filtering is explicit, but DOMPurify blocks that by default.

**Impact:** Low — requires operator/admin to set a malicious banner, and DOMPurify constrains
output to anchors. Defense-in-depth, not a direct user-facing XSS.

**Remediation:** Acceptable as-is. Optionally add `ALLOWED_URI_REGEXP` / `rel="noopener"`
enforcement and prefer rendering banners as plain text where HTML isn't required.

---

## 6. DNS Widget Script Injected Without CSP Nonce — LOW / NEEDS-VALIDATION (CONFIRMED behavior)

**Evidence:**
- `src/shared/composables/useDnsWidget.ts:155-163` dynamically creates a `<script>` element
  (`script.src = dnsWidgetJs`) and appends to `<head>` with **no `nonce` attribute**.
- The script is a **vendored, same-origin** asset (`src/assets/approximated/dnswidget.v1.js`,
  imported via Vite `?url` at `useDnsWidget.ts:14`) — not a remote CDN.
- That widget uses `innerHTML`/`insertAdjacentHTML` heavily
  (`dnswidget.v1.js:24,53,131,134,148,152,213,216,245`), but it is third-party vendor code
  operating on DNS-verification data, not on OTS secrets, and rendered only in the
  authenticated custom-domain admin flow.

**Impact / NEEDS-VALIDATION:** Dynamically-inserted (non-parser-inserted) scripts are generally
allowed under a nonce-based CSP even without a nonce, so this likely still loads under the strict
CSP — but this should be confirmed at runtime with `CSP_ENABLED=true`. If it is blocked, the
custom-domain widget breaks; if the CSP later adopts `strict-dynamic`, behavior changes again.
Separately, the widget's own `innerHTML` sinks are a vendor-code attack surface worth tracking.

**Remediation:** Attach the page nonce (`req.env['onetime.nonce']`, exposed to the SPA via
bootstrap) to the dynamically created `<script>`/`<link>`, or load the widget statically through
the rhales template where it receives a nonce. Track the vendored widget for upstream updates.

---

## 7. Server→SPA Bootstrap (`window.__BOOTSTRAP_ME__`) Encoding — INFO / NEEDS-VALIDATION

**Evidence:**
- Injection is performed by the `rhales` gem (v0.6.2, `Gemfile.lock`) via schema-driven
  hydration: `apps/web/core/templates/index.rue:1`
  (`<schema src="bootstrap.ts" ... window="__BOOTSTRAP_ME__">`), strategy `:earliest`
  (`lib/onetime/initializers/configure_rhales.rb:51`), authority `:schema`
  (`configure_rhales.rb:55`).
- Hydration script tags carry the CSP nonce (`configure_rhales.rb:45-47`,
  `config.nonce_header_name = 'onetime.nonce'`).
- The SPA consumes safely: reads `window.__BOOTSTRAP_ME__`, snapshots it, then **overwrites the
  window prop with `true`** (`src/services/bootstrap.service.ts:40-75`), and validates against a
  Zod schema (`src/schemas/contracts/bootstrap.ts`). Direct window access is ESLint-forbidden
  (`src/services/README.md:55`).
- Template variables are HTML-escaped by default in rhales (`{{ }}`); only `vite_assets_html`
  is explicitly allowlisted as raw (`configure_rhales.rb:67`, used at
  `apps/web/core/templates/partials/head-base.rue:52` as `{{{vite_assets_html}}}`), and that
  content is Vite-generated, not user data.

**NEEDS-VALIDATION:** The exact JSON serialization/escaping of `__BOOTSTRAP_ME__` (e.g. whether
`</script>`, `U+2028/2029`, `<!--` are escaped) is implemented inside the `rhales` gem, which is
a dependency and **out of this repo's tracked source**. If any user-influenced field reaches the
bootstrap payload (e.g. a custom-domain display name, locale, OG/title values), confirm rhales'
hydration encoder neutralizes `</script>` and line-separator sequences. Recommend a runtime test:
set a bootstrap-reachable field to `</script><script>alert(1)</script>` and inspect the rendered
HTML. This is the single highest-value runtime check for the server→SPA boundary.

---

## Positive Findings (No Issue) — CONFIRMED

**XSS sinks:** Searched `src/` for `v-html`, `innerHTML`, `outerHTML`,
`dangerouslySetInnerHTML`, `document.write`, `eval`, `new Function`, `insertAdjacentHTML`.
Only hits in app code are GlobalBroadcast (#5, sanitized) and the vendored DNS widget (#6).
The **secret value is rendered as text**, not HTML:
- `src/apps/secret/components/canonical/SecretDisplayCase.vue:158` →
  `:value="record?.secret_value"` inside a `readonly <textarea>` (Vue-escaped binding).
- `src/apps/secret/components/branded/SecretDisplayCase.vue:178` → same safe pattern.

**Secret never in URL / never logged / never persisted (CONFIRMED via sub-investigation):**
- URL path carries only the opaque `secretIdentifier`
  (`src/apps/secret/routes/secret.ts:60`, `/secret/:secretIdentifier`); passphrase is sent in
  the POST body, not the URL (`src/shared/stores/secretStore.ts` reveal call). No `location.hash`
  usage for secret material.
- No `localStorage`/`sessionStorage`/`IndexedDB` write of `secret_value`. `localReceiptStore`
  persists only receipt metadata to sessionStorage (`src/shared/stores/localReceiptStore.ts`).
- Copy uses the Clipboard API (`navigator.clipboard.writeText`,
  `src/shared/composables/useClipboard.ts:24`), not `execCommand`.

**Token / session storage:**
- CSRF token (`shrimp`) lives in in-memory Pinia (`src/shared/stores/csrfStore.ts`), attached to
  requests via `X-CSRF-Token` header (`src/plugins/axios/interceptors.ts:75`) and refreshed from
  response headers — **not** written to localStorage/sessionStorage.
- Session cookie is **HttpOnly** (`config.defaults.yaml:294-295`, `httponly: true`), so it is not
  exfiltratable via JS/XSS. SameSite is `lax` (`config.defaults.yaml:293`).
- The only items in JS-accessible storage are non-sensitive UI flags: `ots_auth_state` boolean
  in sessionStorage (`src/shared/stores/authStore.ts:226,260`), theme/`restMode`, banner-dismiss
  state, domain/org context, debug channel flags (`src/utils/debug.ts:19`). No tokens or secrets.

**Open redirect:** A dedicated validator (`src/utils/redirect.ts`) rejects protocol-relative
(`//`), absolute cross-origin, `javascript:`/`data:`/`vbscript:`/`file:` and `..` traversal
(`redirect.ts:63-121`). It is used for post-auth redirects:
`src/shared/composables/useAuth.ts:9,107` and `src/apps/session/views/MfaChallenge.vue:11,26`
(`isValidInternalPath`). The router auth-redirect param is also explicitly checked to start with
a single `/` (`src/router/guards.routes.ts:352-354`).

**SRI / external assets:** No external/CDN `<script>` and no `integrity=` needed — the build is a
single same-origin bundle (`vite.config.ts:249-280`); the only third-party JS (DNS widget) is
vendored locally (#6). No dynamic import of remote code (`codeSplitting: false`,
`preserveModules: false`, `vite.config.ts:263,268`).

**i18n / locale HTML:** vue-i18n is configured with `escapeHtml: true`
(`vite.config.ts:184-187`); no `v-html="t(...)"` / `v-html="$t(...)"` usages found, and no raw
HTML tags detected in the generated locale bundles. Translation strings are not rendered as HTML.

**Env var leakage:** Only `VITE_`-prefixed vars reach the client (`vite.config.ts:19-22,360-372`).
`__SENTRY_RELEASE__` is a git SHA (`vite.config.ts:42-65`); no secrets baked into `define`.

**Vite dev server:** `allowedHosts` is constrained to localhost + explicit env list, never `true`
(`vite.config.ts:321-346`), addressing GHSA-vg6x-rcgg-rjx6.

---

## Recommended Priority Order

1. **Default-on CSP** (`CSP_ENABLED=true`) — biggest single XSS mitigation for a secrets product (#1).
2. **Default-on `frame_options` + `strict_transport`** — close default clickjacking/transport gap (#2).
3. **Runtime-validate `__BOOTSTRAP_ME__` encoding** with a `</script>` payload (#7).
4. **`sourcemap: 'hidden'`** (or strip `.map` from served dist) for production (#3).
5. **Clear `secretStore` on unmount / after copy** to minimize plaintext residency (#4).
6. Attach nonce to the dynamically injected DNS widget script; track vendored widget (#6).
