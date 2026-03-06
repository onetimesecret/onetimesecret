> Part of the [Brand Customization System](brand-customization-system.md) product bible.

# Part 3: Cross-Cutting Concerns

---

## 3.1 Accessibility & Contrast

### The Problem

Users pick arbitrary brand colors. The system must ensure text remains readable.

### Current Approach

Manual `button_text_light` boolean toggle in config. Works but:

- Requires the operator to understand contrast
- Only covers buttons, not all brand-colored surfaces
- Binary (light/dark) rather than per-shade

### Recommended Approach

Auto-compute text color per shade using oklch lightness:

```
For each generated shade:
  if L > 0.623 → assign dark text (#1a1a1a)
  if L <= 0.623 → assign light text (#ffffff)
```

This produces CSS variables like `--color-brand-500-text` alongside each `--color-brand-500`,
enabling components to always use readable text without manual configuration.

### Future: APCA

The Accessible Perceptual Contrast Algorithm accounts for font size and weight, producing
more nuanced contrast decisions than WCAG 2.1's simple luminance ratio. Worth considering
when the system needs to handle arbitrary typography.

---

## 3.2 Security Considerations

Brand customization introduces user-controlled inputs that render in HTML, CSS, email
templates, and PWA manifests. Each input is an attack surface.

### Input Validation Requirements

| Field                                | Threat                                                                                                                                    | Mitigation                                                                                                                                                            |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `primary_color`                      | CSS injection via malformed hex (e.g., `#fff; background: url(...)`)                                                                      | Strict hex regex: `/^#[0-9a-fA-F]{3,8}$/` — already validated by Zod schema                                                                                           |
| `product_name`                       | XSS in HTML contexts, email header injection                                                                                              | HTML-escape on render. Max length 100 chars. No newlines.                                                                                                             |
| `logo_url` (planned)                 | SSRF via `file://`, `data:`, internal IPs. Tracking pixels in emails.                                                                     | Scheme allowlist: `https://` only. No redirects. Validate reachable. Max size 2MB. CSP `img-src` directive.                                                           |
| `support_email`                      | Email header injection, phishing                                                                                                          | Validate email format. No newlines or special chars.                                                                                                                  |
| `font_family`                        | Enum — no injection risk                                                                                                                  | Already constrained to `sans`/`serif`/`mono`                                                                                                                          |
| `corner_style`                       | Enum — no injection risk                                                                                                                  | Already constrained to `rounded`/`square`/`pill`                                                                                                                      |
| Per-domain theme extension (planned) | Values flow through CSS custom properties, same as `primary_color`. Risk is limited to property values, not arbitrary selectors or rules. | Validate values with the same pipeline used for `primary_color` (strict format regex per property type). No raw CSS blocks — only named properties with typed values. |
| Font file upload (planned)           | Executable code in font files. License violations.                                                                                        | Format allowlist (woff2 only). Size limit (500KB). No server-side font parsing. Serve via CDN with `Content-Type: font/woff2`.                                        |
| PWA manifest (planned)               | XSS if `name`/`description` rendered in admin UI                                                                                          | JSON-encode all values. Never render manifest fields as raw HTML.                                                                                                     |
| Email sender name/domain (planned)   | SPF/DKIM/DMARC misconfiguration leading to email delivery failures or spoofing. Phishing via impersonated sender addresses.               | Validate domain ownership via DNS TXT record. Require SPF/DKIM alignment before enabling custom sender. Restrict to verified domains only. See [Section 4.1](brand-part4-implementation.md#41-email-branding).           |

### Content Security Policy (CSP) Implications

Adding configurable logos and fonts means CSP directives must be updated:

```
img-src 'self' https:;       ← allow external logo URLs (https only)
font-src 'self' https:;      ← allow external font URLs (when supported)
style-src 'self' 'unsafe-inline';  ← required for runtime CSS var injection
```

The `style-src 'unsafe-inline'` is already required by the current `useBrandTheme`
composable (it sets inline styles on `:root`). This is an acceptable tradeoff — the
alternative (nonce-based CSP) would require server-side rendering coordination.

### Email-Specific Security

- `brand_color` helper must validate hex format before outputting into inline styles
  (prevents CSS injection in email HTML)
- `logo_url` in email templates must be scheme-validated (no `javascript:`, `data:`)
- `product_name` in email subject/body must be HTML-escaped and free of newlines
  (prevents email header injection)

### Per-Domain Brand Validation

For page-load-time customization, brand settings come from Redis (set by custom domain
owners). These users are authenticated but potentially untrusted:

- All brand fields must be validated on write (domain settings API) not just on read
- Rate limit brand settings changes (prevent abuse of palette generation CPU)
- Log brand setting changes for audit trail

---

## 3.3 Quality Assurance: Linting & Visual Regression

### CSS Linting

The brand system's goal of eliminating hardcoded `#dc4a22` occurrences ([Section 1.1](brand-part1-context.md#11-problem-statement)) benefits
from automated enforcement. **Stylelint** can catch regressions at commit time:

- **Token naming conventions** — Custom rules to flag CSS values that should use
  `--color-brand-*` variables instead of raw hex (e.g., disallow `#dc4a22`, `#c43d1b`,
  or any hex matching the generated palette)
- **Variable usage patterns** — Enforce that brand-colored elements reference CSS custom
  properties, not Tailwind color utilities like `bg-orange-600`
- **Plugin architecture** — Extend with `stylelint-order` for property ordering or custom
  plugins for project-specific conventions

Recommended baseline config: `stylelint-config-standard` with project-specific overrides
for the `--color-brand-*` and `--color-brandcomp-*` namespaces.

### Visual Regression Testing

The brand system accepts arbitrary hex input from operators and custom domain owners. A color
that passes Zod validation can still produce a palette that breaks visual layouts (e.g., very
light primaries where brand-50 and brand-100 become indistinguishable from white backgrounds).
Visual regression testing catches these failures before they reach users.

| Tool           | Approach                                      | Fit                                                                                                     |
| -------------- | --------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| **Playwright** | Screenshot comparison with browser automation | Already in the stack (`pnpm run playwright`). Extend existing E2E suite with brand-variant screenshots. |
| **Lost Pixel** | Full-page and component-level visual testing  | Lower setup cost for component-level coverage without full E2E harness                                  |

**Recommended approach**: Extend the existing Playwright E2E suite to capture screenshots
under 3–4 representative brand colors (the default `#dc4a22`, a very light color, a very
dark color, and a cool-toned color). Compare against baselines on each PR that touches
`brand-palette.ts`, `useBrandTheme.ts`, or `style.css`.

For email templates ([Section 4.1](brand-part4-implementation.md#41-email-branding)), Litmus and Email on Acid remain the right tools — visual
regression via Playwright does not cover email client rendering differences.

---
