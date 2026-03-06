> Part of the [Brand Customization System](brand-customization-system.md) product bible.

# Part 4: Implementation Specifics

---

## 4.1 Email Branding

### Current State

- 9 HTML email templates use `brand_color` helper for inline hex (correct approach)
- `logo_alt` resolves to product name (correct)
- **Logo image URL** is hardcoded to `/img/onetime-logo-v3-xl.svg` in all 9 templates
- `support_email` is mostly configurable (one hardcoded instance in `error.rue`)

### Email-Specific Challenges

1. **No CSS variable support** — Email clients require inline styles. The backend
   correctly outputs hex, not CSS vars. This must remain.

2. **Dark mode in email** — Three behaviors across clients:
   - Gmail web: no change
   - Apple Mail: partial inversion (inverts light backgrounds)
   - Outlook dark: full inversion

3. **Logo dark mode** — Transparent PNG logos with padding survive both light and dark.
   OTS's current SVG logo has a solid background, which may look odd when inverted.

### Recommendations

- Add `brand.logo_url` config → wire into email templates
- Use transparent logos where possible
- Brand color for accents/buttons only (survives inversion better than large backgrounds)
- Consider `@media (prefers-color-scheme: dark)` blocks where supported
- Test with Litmus or Email on Acid for cross-client rendering

### Custom Email Sender Name and Domain

Currently, all transactional emails (secret share notifications, verification, password
reset) are sent from the installation's default sender address. Operators cannot customize
the sender name or domain.

**Proposed config fields:**

| Field                 | Type   | Default               | ENV Override                | Purpose                           |
| --------------------- | ------ | --------------------- | --------------------------- | --------------------------------- |
| `email_sender_name`   | string | (product_name)        | `BRAND_EMAIL_SENDER_NAME`   | Display name in email From header |
| `email_sender_domain` | string | (installation domain) | `BRAND_EMAIL_SENDER_DOMAIN` | Domain portion of From address    |

**Requirements:**

- Sender domain must have valid SPF, DKIM, and DMARC records aligned with the sending
  infrastructure (see [Section 3.2](brand-part3-cross-cutting-concerns.md#32-security-considerations) for security implications)
- `email_sender_name` falls back to `brand.product_name` if not explicitly set
- Validation: domain ownership should be confirmed via DNS TXT record before activation
- This is an install-time-only feature — per-domain email sender customization introduces
  significant deliverability and abuse risks

---

## 4.2 Operator Documentation

### Current State

**✅ Completed (v0.24):** [Self-Hosting Brand Customization Guide](SELF-HOSTING-GUIDE.md) provides:
- Quick-start (3 environment variables)
- Complete configuration reference
- SITE_NAME deprecation migration guide
- Logo options (PNG vs Vue component)
- Troubleshooting common issues
- Real-world examples

The guide is now the primary reference for self-hosters. The `brand:` section in
`config.defaults.yaml` remains as inline documentation for developers.

### What Operators Need

1. **Quick-start guide** — "Set these 3 ENV vars to customize your brand":
   - `BRAND_PRIMARY_COLOR` — hex color
   - `BRAND_PRODUCT_NAME` — your product name
   - `BRAND_SUPPORT_EMAIL` — your support email
   - Expected behavior: restart → brand applied everywhere

2. **Full reference** — All 9+ config fields with descriptions, defaults, examples, and
   which lifecycle level they affect (install-time vs page-load-time)

3. **Troubleshooting** — Common issues:
   - "My color changed but emails still show the old color" (email caching)
   - "My logo doesn't appear" (URL validation, CORS, CSP)
   - "The page flashes default colors before my brand loads" (FOUC)

4. **Brand validation CLI** — `bin/ots brand validate` command that checks:
   - Hex format valid
   - Logo URL reachable (if configured)
   - WCAG contrast warnings for chosen color
   - All brand fields resolved (no fallback to OTS defaults)

---
