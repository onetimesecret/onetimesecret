# docs/architecture/email-validation.md
---

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

The duplicate Truemail call at signup is defense in depth: the Rodauth hook validates independently of the API logic class.

Incoming has two phases: config-time (admin adds recipients, full validation) and create-time (submitter provides hash, regex-only corruption guard). The create-time check uses `:regex` mode (no DNS) since it runs on every submission.

## When to Use BASIC_FORMAT

`EmailFormat::BASIC_FORMAT` is a fallback for contexts where Truemail cannot run:

1. **Model-layer validation** -- Truemail may not be configured
2. **Pre-boot code** -- runs before `configure_truemail.rb` executes

CLI commands boot the application, so they use Truemail. The no-boot subclass (`Onetime::CLI::BaseBoot`) is an explicit opt-out for commands that need to run without full initialization.

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
