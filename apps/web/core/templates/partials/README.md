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
- PWA configuration (manifest, theme-color, apple-mobile-web-app settings)
- Modern favicon strategy
- Cache control
- Vite asset links

**Usage**: Always included as the base template via `{{> partials/head-base}}`

### head.rue
**Purpose**: Default head content for general pages (home, account, etc.)
**Contains**:
- Base head tags (via head-base.rue)
- Open Graph meta tags for social sharing
- Twitter Card meta tags

**Usage**: Default template used in index.rue and error.rue

### head-secret-share.rue
**Purpose**: Optimized head content for secret sharing pages
**Contains**:
- Base head tags (via head-base.rue)
- Dynamic Open Graph/Twitter meta for custom secret sharing
- `noindex, nofollow` robots meta for secret pages

**Usage**: To be used when rendering secret view/burn pages
**Variables needed**:
- `current_url` - The URL of the secret page
- `og_title` - Custom title for social sharing (e.g., "Someone shared a secret with you")
- `og_description` - Custom description for social sharing
- `is_secret_page` - Boolean to trigger robots noindex directive

## Modernization Changes

### Security Improvements
- Added `X-Frame-Options: SAMEORIGIN`
- Added `X-Content-Type-Options: nosniff`
- Added `Permissions-Policy` to disable unnecessary features
- Upgraded referrer policy from `no-referrer` to `strict-origin-when-cross-origin`

### PWA/Mobile Enhancements
- Uncommented web app manifest
- Added dark mode theme-color support
- Enhanced apple-mobile-web-app configuration

### Icon Strategy
- Removed versioning query params (`?v=3`)
- Consolidated to SVG + PNG fallback approach
- Simplified to essential icon types

### Removed Deprecated
- `keywords` meta tag (unused by search engines since 2009)
- `msapplication-TileColor` (legacy Windows 8)
- Redundant favicon declarations

## Future Enhancements

### For Secret Pages
Update the secret viewing controller/view to:
1. Set `og_title`, `og_description`, and `current_url` variables
2. Use `{{> partials/head-secret-share}}` instead of `{{> partials/head}}`
3. Set `is_secret_page: true` for proper robots meta

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
