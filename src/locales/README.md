# Locales Directory

This directory contains internationalization (i18n) files for all supported languages.

## Quick Reference

- **Base language**: `en.json` (English - canonical reference)
- **30+ languages supported**: See individual `.json` files
- **Security messages**: Special handling required (see below)

## Translation Guidelines

### Standard Translation Process

1. **Use `en.json` as reference** - All translations should match the English structure
2. **Preserve key names** - Only translate the values, never the keys
3. **Maintain placeholders** - Keep `{variable}` syntax intact (e.g., `{count}`, `{email}`)
4. **Test thoroughly** - Verify translations in the UI before committing

### ⚠️ Special Rules for Security Messages

**Security-critical messages** in `web.auth.security.*` require special handling:

- **Read first**: `SECURITY-TRANSLATION-GUIDE.md` in this directory
- **Follow OWASP/NIST guidelines**: Messages must remain generic to prevent information disclosure
- **NO creative rewording**: Semantic meaning must be identical across languages
- **Validation required**: Run `pnpm test:unit security-messages` to verify compliance

### 🔒 DO NOT Translate: Underscore-Prefixed Keys

Keys starting with `_` are **metadata/documentation only**:

```json
{
  "_README": "⚠️ SECURITY-CRITICAL...",     // ← Keep in English
  "_meta": { ... },                          // ← Keep in English
  "_translation_guidelines": { ... },        // ← Keep in English
  "_safe_information": { ... },              // ← Keep in English

  "authentication_failed": "..."             // ← Translate this
}
```

**Why?**
- Not displayed to users
- Vue-i18n ignores these by convention
- English ensures consistent understanding across all translation teams
- Contains technical OWASP/NIST references and security notes

### 🔒 DO NOT Translate: This README

- **This README.md**: Keep in **English** (canonical version)
- **SECURITY-TRANSLATION-GUIDE.md**: Keep in **English** (canonical version)
- Optional: Teams may create localized copies (e.g., `README.es.md`) if helpful

## File Structure

```
src/locales/
├── README.md                           ← You are here (keep in English)
├── SECURITY-TRANSLATION-GUIDE.md       ← Security translation rules (keep in English)
├── en.json                             ← Base language (English)
├── es.json                             ← Spanish
├── fr_FR.json                          ← French (France)
├── fr_CA.json                          ← French (Canada)
├── de.json                             ← German
├── ... (30+ languages)
```

## Adding a New Language

1. Copy `en.json` to `{language_code}.json` (e.g., `it.json` for Italian)
2. Translate all user-facing strings (values only, not keys)
3. **Keep all `_` prefixed keys in English**
4. For security messages, read `SECURITY-TRANSLATION-GUIDE.md` first
5. Run validation: `pnpm test:unit security-messages`
6. Test in the UI to ensure proper rendering
7. Submit PR with the new locale file

## Testing Translations

```bash
# Run security message validation
pnpm test:unit security-messages

# Type check (ensures no syntax errors in JSON)
pnpm run type-check

# Run full test suite
pnpm test
```

## Questions?

- **General i18n**: Ask maintainers
- **Security messages**: Read `SECURITY-TRANSLATION-GUIDE.md` first, then ask if unclear
- **Technical issues**: Open a GitHub issue

---

**Key Principle**: Preserve security while enabling accessibility. Thank you for helping make Onetime Secret available to users worldwide! 🌍
