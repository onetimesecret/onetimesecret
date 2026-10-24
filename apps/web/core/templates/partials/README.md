# Head Partial Templates

This directory contains modernized HTML `<head>` templates for the Onetime Secret application.

## Files

### head-base.rue
**Purpose**: Core head content shared across all pages
**Contains**:
- Character encoding and viewport
- Security headers (X-Frame-Options, X-Content-Type-Options, Permissions-Policy)
- CSRF token
- SEO metadata (canonical URL, title, description)
- Modern favicon strategy (mask-icon with brand color)
- Cache control
- Vite asset links

**Usage**: Always included as the base template via `{{> partials/head-base}}`

### head.rue
**Purpose**: Default head content for general pages (home, account, etc.)
**Contains**:
- Base head tags (via head-base.rue)
- Open Graph meta tags for social sharing
- Twitter Card meta tags

**Usage**: Default template used in index.rue

### head-secret-share.rue
**Purpose**: Optimized head content for secret sharing pages
**Contains**:
- Base head tags (via head-base.rue)
- Dynamic Open Graph/Twitter meta for custom secret sharing
- `noindex, nofollow` robots meta for secret pages

**Usage**: index.rue includes it instead of head.rue when `is_secret_page`
is true. The view sets that flag for `/secret/*`, `/receipt/*` and
`/incoming/:receiptKey` requests (`SECRET_PAGE_PATH` in
`initialize_view_vars.rb`), the same paths robots.rue disallows. `/incoming`
itself, the submission form, is not one.
**Variables**:
- `page_url` - The page URL (served host, its public port when one is
  known, plus path, no query string); also the canonical link in
  head-base.rue and og:url in head.rue
- `display_domain` - The served host, for twitter:domain
- `og_title`, `og_description` - Neutral text from `web.COMMON.secret_og_*`,
  so a link pasted into a chat unfurls without naming the page or sender

## Modernization Changes

### Security Improvements
- Added `X-Frame-Options: SAMEORIGIN`
- Added `X-Content-Type-Options: nosniff`
- Added `Permissions-Policy` to disable unnecessary features
- Upgraded referrer policy from `no-referrer` to `strict-origin-when-cross-origin`

### Icon Strategy
- Removed versioning query params (`?v=3`)
- Consolidated to SVG + PNG fallback approach
- Simplified to essential icon types

### Removed Deprecated
- `keywords` meta tag (unused by search engines since 2009)
- `msapplication-TileColor` (legacy Windows 8)
- Redundant favicon declarations

## Future Enhancements

### Content Security Policy
Consider adding CSP meta tag or HTTP headers:
```html
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'nonce-{{app.nonce}}';">
```

### Performance
Add preconnect hints for external resources:
```html
<link rel="preconnect" href="https://fonts.googleapis.com" crossorigin>
<link rel="dns-prefetch" href="https://cdn.example.com">
```

### i18n
Add language alternatives for internationalized content:
```html
<link rel="alternate" hreflang="es" href="https://app.onetimesecret.com/es/...">
<link rel="alternate" hreflang="fr" href="https://app.onetimesecret.com/fr/...">
```
