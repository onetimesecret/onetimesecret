# Email Validation

## Flow

All email inputs follow the same path:

```
sanitize_email(input) → valid_email?(email) [Truemail.validate]
```

Sanitization strips HTML, prevents header injection (`\r\n`), lowercases. Validation calls Truemail with the configured validation type (regex, mx, or smtp).

## Signup vs Recipient vs Incoming

|                  | Signup                            | Recipient                 | Incoming (config)         | Incoming (create)         |
| ---------------- | --------------------------------- | ------------------------- | ------------------------- | ------------------------- |
| Sanitization     | `sanitize_email`                  | `sanitize_email`          | `sanitize_email`          | none (hash lookup)        |
| Validation       | `valid_email?` (Truemail)         | `valid_email?` (Truemail) | `valid_email?` (Truemail) | Truemail `:regex` only    |
| Domain allowlist | `allowed_signup_domain?`          | none                      | none                      | none                      |
| Truemail calls   | 2x (CreateAccount + Rodauth hook) | 1x                        | 1x                        | 1x (corruption guard)     |

The duplicate Truemail call at signup is defense in depth: the Rodauth hook validates independently since there's no guarantee of which codepath is calling it.

Incoming has two phases: config-time (admin adds recipients, full validation) and create-time (submitter provides hash, regex-only corruption guard). The create-time check uses `:regex` mode (no DNS) since it runs on every submission.

### Choosing a Validation Method

| Context | Method |
| ------- | ------ |
| Signup, invitation, share boundaries | `Logic::Base#valid_email?` (full Truemail) |
| Corruption guards in booted contexts | `Truemail.validate(email, with: :regex).result.valid?` |
| Model-layer or pre-boot code | `EmailFormat::BASIC_FORMAT` regex |

**Full Truemail** (`valid_email?`) for user-input boundaries -- validates format, MX records, optionally SMTP depending on config.

**Truemail `:regex` mode** for corruption guards -- format-only, no DNS, fast enough to run on every request. Use when the email was already validated at config time.

**BASIC_FORMAT** in pre-boot code (code that runs before `configure_truemail.rb` executes).

CLI commands boot the application, so they use Truemail. Unless subclassed from `Onetime::CLI::DelayBootCommand` in which case you know what you doing.

## Entry Points

- `Onetime::Logic::Base#valid_email?` -- shared Truemail wrapper
- `Onetime::Logic::Base#sanitize_email` -- input sanitization (via `InputSanitizers`)
- `Onetime::Utils::EmailFormat::BASIC_FORMAT` -- regex for model/pre-boot contexts
- `AccountAPI::Logic::Account::CreateAccount#allowed_signup_domain?` -- signup domain allowlist
- `V2::Logic::Secrets::BaseSecretAction#validate_recipient` -- recipient validation
- `DomainsAPI::Logic::IncomingConfig::PutIncomingConfig` -- incoming recipient config (full Truemail)
- `Incoming::Logic::CreateIncomingSecret#raise_concerns` -- incoming secret creation (`:regex` corruption guard)

## Configuration

Truemail reads from `OT.conf['mail']['truemail']`. Common settings:

- `verifier_email` -- required, used as MAIL FROM in SMTP checks
- `default_validation_type` -- `:regex`, `:mx`, or `:smtp`
- `validation_type_for` -- per-domain overrides (hash of domain => type)

Runtime state is tracked in `Onetime::Runtime.email.truemail_configured`.
