# Frontend i18n

Localize Vue components using vue-i18n with keys from source locale files.

## Quick Start

```vue
<script setup lang="ts">
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
</script>

<template>
  <button>{{ t('web.COMMON.submit_with') }}</button>

  <!-- Or via global injection ($t) -->
  <span>{{ $t('web.COMMON.tagline') }}</span>
</template>
```

## Locale File Structure

Source files live in `locales/content/{locale}/` with `{text, content_hash}` structure:

```json
"web.COMMON.button_create_secret": {
  "text": "Create a secret link",
  "content_hash": "abc123"
}
```

These compile to flat `generated/locales/{locale}.json` for runtime:

```json
{
  "web": {
    "COMMON": {
      "button_create_secret": "Create a secret link"
    }
  }
}
```

Run `pnpm run locales:generate` after editing source files.

## Key Naming

| Prefix | Use |
|--------|-----|
| `web.*` | Frontend UI strings |
| `api.*` | Backend API messages |
| `email.*` | Email templates |

Organize by feature area: `web.COMMON.*`, `web.homepage.*`, `web.billing.*`, `web.organizations.*`.

## Adding New Strings

1. Add to appropriate source file in `locales/content/en/`
2. Run `pnpm run locales:generate`
3. Use `t('web.feature.key_name')` in component

## Common Patterns

### Interpolation

```json
"web.COMMON.creating_secrets_in": {
  "text": "Creating secrets in {domain}",
  "content_hash": "..."
}
```

```vue
<template>
  {{ t('web.COMMON.creating_secrets_in', { domain: 'example.com' }) }}
</template>
```

### Positional Arguments

```json
"web.layout.current_language_is_currentlocal": {
  "text": "Current language is {0}",
  "content_hash": "..."
}
```

```vue
<template>
  {{ t('web.layout.current_language_is_currentlocal', [localeName]) }}
</template>
```

### Pluralization

```json
"web.COMMON.secret": {
  "text": "Secret | Secrets",
  "content_hash": "..."
}
```

```vue
<template>
  {{ t('web.COMMON.secret', 1) }}  <!-- "Secret" -->
  {{ t('web.COMMON.secret', 5) }}  <!-- "Secrets" -->
</template>
```

### Literal Special Characters

Use `{'@'}` to escape special characters:

```json
"web.COMMON.email_placeholder": {
  "text": "e.g. tom{'@'}myspace.com",
  "content_hash": "..."
}
```

## Locale Switching

Managed via `useLanguage` composable and `languageStore`:

```ts
import { useLanguage } from '@/shared/composables/useLanguage';

const { currentLocale, updateLanguage, supportedLocalesWithNames } = useLanguage();

// Change locale (persists to session + API)
await updateLanguage('fr_FR');
```

The `LanguageToggle` component (`src/shared/components/ui/LanguageToggle.vue`) provides the UI.

## Fallback Behavior

Configured in `src/i18n.ts`:

- Missing keys fall back per `fallbackLocale` config (from `etc/config.yaml`)
- Supported locales come from `getBootstrapValue('supported_locales')`
- Default locale: `getBootstrapValue('default_locale')` or `'en'`
- All locales are pre-loaded at build time via `import.meta.glob`

## Isolated i18n Instances

For preview/sandbox scenarios that need independent locale state:

```ts
import { createI18nInstance } from '@/i18n';

const { instance, composer, setLocale } = createI18nInstance('de');
await setLocale('fr_FR');  // Only affects this instance
```

## Testing

Mock `useI18n` in tests:

```ts
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));
```
