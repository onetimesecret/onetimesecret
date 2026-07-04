# Backend i18n

Localize user-facing strings in Ruby API code using `I18n.t` with keys from source locale files.

## Quick Start

```ruby
# Instead of hardcoded strings:
raise_form_error('Email is required', field: :email)

# Use I18n:
raise_form_error(I18n.t('api.invitations.errors.email_required'), field: :email)
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
"api.invitations.errors.email_required": {
  "text": "Email is required",
  "content_hash": "a1b2c3d4"
}
```

The `content_hash` is for translation tooling (change detection).

## Adding New Strings

1. Add to the appropriate source file in `locales/content/en/`
2. Run locale generation: `pnpm run locales:generate`
3. Use `I18n.t('your.key')` in Ruby code

## Fallback Behavior

Configured in `lib/onetime/initializers/setup_i18n.rb`:

- Missing translations fall back to the default locale (typically `en`)
- Locale is set per-request from session/header
- For background jobs, pass locale explicitly or fall back to `OT.default_locale`

## Common Patterns

```ruby
# API logic classes
raise_form_error(I18n.t('api.invitations.errors.already_member'), field: :email)

# With interpolation
I18n.t('api.quota.limit_reached', count: limit, current: current)

# Email jobs (pass locale from inviter/recipient)
Onetime::Jobs::Publisher.enqueue_email(
  :organization_invitation,
  { locale: cust.locale || OT.default_locale, ... }
)
```

## Existing Examples

See `workspace-organizations.json` for invitation UI strings (`web.organizations.invitations.*`). Backend API errors should mirror the structure under `api.*` prefix.
