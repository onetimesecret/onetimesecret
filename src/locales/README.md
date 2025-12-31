# Locales Directory

This directory contains internationalization (i18n) files for all supported languages.

## Translation Guidelines

### Standard Translation Process

1. **Use `en.json` as reference** - All translations should match the English structure
2. **Preserve key names** - Only translate the values, never the keys
3. **Maintain placeholders** - Keep `{variable}` syntax intact (e.g., `{count}`, `{email}`)

### Special Rules for Security Messages

**Security-critical messages** in any `*.security.*` require special handling:

- **Read first**: `SECURITY-TRANSLATION-GUIDE.md` and `UX-TRANSLATION-GUIDE.md` in this directory
- **Follow OWASP/NIST guidelines**: Messages must remain generic to prevent information disclosure
- **NO creative rewording**: Semantic meaning must be identical across languages
- **Validation required**: Run `pnpm test:unit security-messages` to verify compliance

### DO NOT Translate: Underscore-Prefixed Keys

Keys starting with `_` are **metadata/documentation only**:

```json
{
  "_README": "⚠️ SECURITY-CRITICAL...",      // ← Keep in English
  "_safe_information": { ... },              // ← Keep in English
  "authentication_failed": "..."             // ← Translate this
}
```

### DO NOT Translate: This README

- **This README.md**: Keep in **English** (canonical version)
- **SECURITY-TRANSLATION-GUIDE.md**: Keep in **English** (canonical version)
- Optional: Teams may create localized copies (e.g., `README.es.md`) if helpful

## File Structure

```
src/locales/
├── scripts/                            ← Scripts for managing translations
├── README.md                           ← You are here
├── SECURITY-TRANSLATION-GUIDE.md       ← Security translation rules
├── en.json                             ← Base language (English)
├── fr_FR.json                          ← French (France)
├── fr_CA.json                          ← French (Canada)
├── de.json                             ← German
├── ...
```

## Testing Translations

```bash
# Run security message validation
pnpm test:unit security-messages

# Type check (ensures no syntax errors in JSON)
pnpm run type-check

# Run full test suite
pnpm test
```

**Key Principle**: Preserve security while enabling accessibility. Thank you for helping make Onetime Secret available to users worldwide! 🌍
