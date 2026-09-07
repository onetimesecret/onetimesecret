# Backend i18n

Localize Ruby API errors with an `error_key` from the source locale files. The
HTTP error handler resolves that key for the request locale; API logic should
not call `I18n.t` itself.

## Quick Start

```ruby
# Instead of a string-only error:
raise_form_error('Is that a valid email address?', field: :login)

# Use a valid full key. The string remains an optional English fallback.
raise_form_error(
  'Is that a valid email address?',
  error_key: 'api.account.errors.invalid_email',
  field: :login,
  error_type: :invalid,
)
```

## Locale File Structure

Source files live in `locales/content/{locale}/` organized by feature:

```
locales/content/
├── en/
│   ├── workspace-organizations.json   # org/team/invitation strings
│   ├── session-auth.json              # login/signup/password
│   ├── email.json                     # email templates
│   └── ...
└── fr/
    └── ...
```

These compile to `generated/locales/{locale}.json` at build time.

## Key Naming

| Prefix | Use |
|--------|-----|
| `web.*` | Frontend UI strings |
| `api.*` | Backend API messages |
| `email.*` | Email templates |

API errors follow: `api.{feature}.errors.{error_name}`

```json
"api.account.errors.invalid_email": {
  "text": "Is that a valid email address?"
}
```

The `content_hash` is for translation tooling (change detection).

## Adding New Strings

1. Add a full `api.*` key to the appropriate source file in `locales/content/en/`
2. Run locale generation: `pnpm run locales:generate`
3. Pass that key as `error_key:` when raising the API error

## Fallback Behavior

Configured in `lib/onetime/initializers/setup_i18n.rb`:

- Missing translations fall back to the default locale (typically `en`)
- Locale is set per-request from session/header
- For background jobs, pass locale explicitly or fall back to `OT.default_locale`

## Common Patterns

```ruby
# API logic classes
raise_form_error(
  'Domain ID required',
  error_key: 'api.domains.errors.domain_id_required',
  field: :domain_id,
  error_type: :missing,
)

# With interpolation
raise_form_error(
  "Invalid secrets_mode: #{@secrets_mode}",
  error_key: 'api.domains.errors.homepage_secrets_mode_invalid',
  args: { secrets_mode: @secrets_mode },
  field: :secrets_mode,
  error_type: :invalid,
)

# Email jobs (pass locale from inviter/recipient)
Onetime::Jobs::Publisher.enqueue_email(
  :organization_invitation,
  { locale: cust.locale || OT.default_locale, ... }
)
```

## Existing Examples

See `workspace-organizations.json` for invitation UI strings (`web.organizations.invitations.*`). Backend API errors should mirror the structure under `api.*` prefix.
