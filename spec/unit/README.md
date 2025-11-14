# Unit Tests

This directory contains unit tests for the Onetime Secret application.

## I18n Tests

The i18n test suite covers the migration to ruby-i18n gem:

### Test Files

1. **`lib/onetime/initializers/load_locales_spec.rb`**
   - Tests the I18n gem configuration
   - Verifies locale file loading
   - Tests backward compatibility with OT.locales
   - Tests error handling and fallback configuration

2. **`apps/web/core/views/helpers/i18n_spec.rb`**
   - Tests the Core::Views::I18nHelpers module
   - Verifies view-level i18n functionality
   - Tests caching behavior
   - Tests fallback to default locale

3. **`apps/api/v2/logic/helpers/i18n_spec.rb`**
   - Tests the V2::Logic::I18nHelpers module
   - Verifies API-level i18n functionality
   - Tests email and web translation access
   - Tests locale switching

4. **`apps/web/core/middleware/request_setup_spec.rb`**
   - Tests the RequestSetup middleware
   - Verifies I18n.locale synchronization with Otto locale
   - Tests nonce generation
   - Tests content-type handling

## Running Tests

Run all unit tests:
```bash
bundle exec rspec spec/unit
```

Run only i18n tests:
```bash
bundle exec rspec spec/unit --pattern "**/i18n*"
```

Run specific test file:
```bash
bundle exec rspec spec/unit/lib/onetime/initializers/load_locales_spec.rb
```

Run with documentation format:
```bash
bundle exec rspec spec/unit --format documentation
```

## Test Coverage

The test suite covers:
- ✓ Locale file loading from JSON files
- ✓ I18n gem configuration (default locale, available locales, fallbacks)
- ✓ Translation access via I18n.t()
- ✓ Helper methods for views and API logic
- ✓ Middleware locale synchronization
- ✓ Backward compatibility with legacy code
- ✓ Error handling and graceful degradation
- ✓ Caching behavior
- ✓ Locale switching
