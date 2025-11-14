# Migration to ruby-i18n Gem

This document describes the migration from the custom i18n implementation to the standard ruby-i18n gem.

## Overview

Migrated from a custom JSON-based internationalization system to the industry-standard ruby-i18n gem (https://github.com/ruby-i18n/i18n).

## Changes Made

### 1. Added ruby-i18n Gem

**File:** `Gemfile`
- Added `gem 'i18n', '~> 1.14'` to the Data Processing & Utilities section

### 2. Using Existing JSON Locale Files

**Note:** JSON is valid YAML, so the I18n gem can load the existing JSON files directly without conversion.

- Kept existing 30 locale files in `src/locales/*.json`
- No conversion or duplication needed
- I18n gem loads them directly as-is

**Example structure:**
```json
// src/locales/en.json (unchanged)
{
  "web": { ... },
  "email": { ... }
}
```

### 3. Updated Locale Loading Initializer

**File:** `lib/onetime/initializers/load_locales.rb`

**Changes:**
- Replaced `require 'familia/json_serializer'` with `require 'i18n'`
- Removed custom JSON parsing and loading logic
- Configured I18n gem with:
  - `I18n.load_path` - Points to existing JSON files in `src/locales/`
  - `I18n.default_locale` - Set from configuration
  - `I18n.available_locales` - Set from supported locales list
  - Fallback support using `I18n::Backend::Fallbacks`
- Maintained backward compatibility by keeping `@locales` hash populated

### 4. Updated i18n Helper Modules

**File:** `apps/web/core/views/helpers/i18n.rb`
- Replaced `OT.locales.fetch()` with `I18n.t()` calls
- Updated to set `I18n.locale` for each request
- Maintained same return structure for backward compatibility
- Updated comments to reflect ruby-i18n usage

**File:** `apps/api/v2/logic/helpers/i18n.rb`
- Replaced `OT.locales[locale]` with `I18n.t()` calls
- Updated to use `I18n.locale` for locale management
- Maintained cache structure for performance
- Preserved the same API interface

### 5. Updated Direct Locale Access

**File:** `apps/api/v2/logic/secrets/burn_secret.rb`
- Line 70: Changed from:
  ```ruby
  message = OT.locales.dig(locale, :web, :COMMON, :error_passphrase) || 'Incorrect passphrase'
  ```
  To:
  ```ruby
  message = I18n.t('web.COMMON.error_passphrase', locale: locale, default: 'Incorrect passphrase')
  ```

### 6. Updated Middleware

**File:** `apps/web/core/middleware/request_setup.rb`
- Added `I18n.locale` synchronization with Otto locale middleware
- Ensures I18n.locale is set to match the detected locale from request

## Backward Compatibility

The migration maintains full backward compatibility:

1. **Existing API unchanged** - Helper methods (`i18n[:page]`, `i18n[:COMMON]`, etc.) work exactly as before
2. **OT.locales still populated** - The `@locales` hash is still maintained for any legacy code
3. **Same locale detection** - Still uses Otto::Locale::Middleware for locale detection
4. **Configuration unchanged** - Same config structure in `config.yaml`

## Benefits

1. **Industry Standard** - Using a well-tested, widely-adopted gem
2. **Better Maintainability** - Standard approach familiar to Ruby developers
3. **Rich Features** - Access to I18n features like pluralization, interpolation, etc.
4. **Active Support** - Maintained by the Ruby community
5. **Extensibility** - Easy to add custom backends, fallbacks, etc.

## Testing

All Ruby files passed syntax validation. The following should be tested:

1. View rendering with different locales
2. API responses with localized messages
3. Email templates in various languages
4. Fallback behavior when translations are missing
5. Locale switching in user sessions

## Migration Path for Future Development

Going forward, developers can use standard I18n methods directly:

```ruby
# Simple translation
I18n.t('web.COMMON.tagline')

# With interpolation
I18n.t('email.welcome.greeting', name: user.name)

# With pluralization
I18n.t('secrets.count', count: secret_count)

# With locale override
I18n.t('web.TITLES.signin', locale: :fr)
```

## Files Modified

- `Gemfile` - Added i18n gem
- `lib/onetime/initializers/load_locales.rb` - I18n configuration
- `apps/web/core/views/helpers/i18n.rb` - View helper updates
- `apps/api/v2/logic/helpers/i18n.rb` - API helper updates
- `apps/api/v2/logic/secrets/burn_secret.rb` - Direct locale access update
- `apps/web/core/middleware/request_setup.rb` - Locale synchronization

## Files Unchanged

- `src/locales/*.json` - All 30 locale files remain in their original location and format
