# Locales Directory

i18n files for 34+ languages.

## File Structure

```
src/locales/
├── en/                          ← Multi-file English (source of truth)
│   ├── _common.json             ← Shared strings (buttons, labels, errors)
│   ├── account.json             ← Account settings
│   ├── account-billing.json     ← Billing/subscription UI
│   ├── auth.json                ← Basic auth (login, signup)
│   ├── auth-full.json           ← Extended auth (MFA, recovery, WebAuthn)
│   ├── colonel.json             ← Admin panel
│   ├── email.json               ← Email templates
│   ├── error-pages.json         ← HTTP error pages
│   ├── feature-*.json           ← Feature-specific strings
│   ├── homepage.json            ← Landing page
│   └── layout.json              ← Navigation, footer, chrome
├── de/                          ← German (multi-file)
├── fr/                          ← French (multi-file)
├── ...                          ← Other languages
├── SECURITY-TRANSLATION-GUIDE.md
└── UX-TRANSLATION-GUIDE.md
```

## Precompile Cache

Multi-file locales are merged at boot time. Enable caching to skip recompilation:

```yaml
# etc/config.yaml
i18n:
  precompile_cache: true   # Default: enabled via I18N_PRECOMPILE_CACHE env
```

Cache files (`.merged-*.cache`) are created per-locale and invalidated when source files change. Disable for development with `I18N_PRECOMPILE_CACHE=false`.

The multi-file split optimizes for human editing, not performance. Translation contributors work on focused domain files rather than 2000-line monoliths.

## Translation Rules

1. Use `en/` as reference - match the structure exactly
2. Preserve keys - only translate values
3. Keep placeholders intact: `{count}`, `{email}`, `{name}`
4. Keys prefixed with `_` are metadata - do not translate

Security messages (`*.security.*` keys) require special handling - see `SECURITY-TRANSLATION-GUIDE.md`.

## Testing

```bash
pnpm test:unit security-messages   # Validate security message compliance
pnpm run type-check                # Check JSON syntax
```
