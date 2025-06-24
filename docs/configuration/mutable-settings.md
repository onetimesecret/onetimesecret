# Mutable Settings Documentation

## Overview

Mutable settings define operational parameters for OneTimeSecret that can be modified at runtime. These settings are loaded initially from `etc/mutable_settings.yaml` and after that from Redis. They control application features, user interface behavior, and operational limits. Unlike core configuration in `config.yaml` (which handles system-critical parameters like database connections and security settings), mutable settings focus on user-facing features and operational tweaks with lower blast radius.

## Configuration Structure

### User Interface (`user_interface`)

Controls frontend appearance and behavior.

#### Header Configuration (`header`)
- `enabled`: Toggle header customization (default: true)
- `branding.logo.url`: Logo image path or component name
- `branding.logo.alt`: Logo alt text for accessibility
- `branding.logo.href`: Logo click destination
- `branding.site_name`: Override site name (falls back to i18n)
- `navigation.enabled`: Toggle header navigation (default: true)

#### Footer Links (`footer_links`)
- `enabled`: Toggle footer links display
- `groups`: Array of link groups with i18n keys and external URL configuration

#### Authentication
- `signup`: Enable user registration (default: true)
- `signin`: Enable user login (default: true)
- `autoverify`: Email verification behavior

### API Configuration (`api`)
- `enabled`: Toggle API access (default: true)

### Secret Options (`secret_options`)
- `default_ttl`: Default time-to-live in seconds when none specified
- `ttl_options`: Available TTL options for secret creation

### Features (`features`)

#### Incoming Email (`incoming`)
- `enabled`: Toggle incoming email processing
- `email`: Processing email address
- `passphrase`: Email processing passphrase
- `regex`: Validation pattern for incoming content

#### Analytics (`stathat`)
- `enabled`: Toggle StatHat integration
- `apikey`: StatHat API key
- `default_chart`: Default chart configuration

#### Regions (`regions`)
- `enabled`: Toggle multi-region support
- `current_jurisdiction`: Current jurisdiction identifier
- `jurisdictions`: Array of available regions with domains and icons

#### Plans (`plans`)
- `enabled`: Toggle subscription plans
- `stripe_key`: Stripe integration key
- `webhook_signing_secret`: Stripe webhook validation
- `payment_links`: Tier-specific payment link configuration

#### Domains (`domains`)
- `enabled`: Toggle custom domain support
- `default`: Default domain for link generation
- `cluster`: Multi-domain cluster configuration with API keys and proxy settings

### Diagnostics (`diagnostics`)

Error tracking and monitoring configuration.

#### Sentry Integration (`sentry`)
- `defaults`: Shared configuration for DSN, sample rate, breadcrumbs, and logging
- `backend`: Ruby-specific Sentry configuration
- `frontend`: Vue-specific Sentry configuration with component tracking

### Rate Limits (`limits`)

Per-user limits for various operations over 20-minute rolling windows:

#### Core Operations
- `create_secret`: Secret creation limit (100,000)
- `show_secret`: Secret viewing limit (2,000)
- `burn_secret`: Secret destruction limit (2,000)
- `show_metadata`: Metadata access limit (2,000)

#### Authentication
- `create_account`: Account creation limit (10)
- `authenticate_session`: Login attempt limit (50)
- `failed_passphrase`: Failed passphrase attempts (15)

#### Account Management
- `update_account`: Profile update limit (10)
- `destroy_account`: Account deletion limit (2)
- `forgot_password_request`: Password reset requests (20)
- `forgot_password_reset`: Password reset completions (30)

#### Domain Management
- `add_domain`: Domain addition limit (30)
- `remove_domain`: Domain removal limit (30)
- `list_domains`: Domain listing limit (100)
- `verify_domain`: Domain verification limit (100)

### Mail Validation (`mail.validation`)

Email validation configuration for recipients and account creation.

#### Recipients (`recipients`)
- `default_validation_type`: Primary validation method (`:mx`)
- `verifier_email`: SMTP verification sender
- `verifier_domain`: SMTP verification domain
- `connection_timeout`: SMTP connection timeout (1s)
- `response_timeout`: SMTP response timeout (1s)
- `connection_attempts`: Retry attempts (2)
- `allowed_domains_only`: Restrict to allowed domains only
- `dns`: DNS servers for MX lookup
- `smtp_port`: SMTP connection port (25)
- `smtp_fail_fast`: Skip retry on first failure
- `logger`: Validation event logging configuration

#### Accounts (`accounts`)
Identical structure to recipients with separate configuration for account email validation.

## Environment Variable Integration

Configuration values support ERB templating with environment variable fallbacks:

```yaml
enabled: <%= ENV['FEATURE_ENABLED'] != 'false' %>
api_key: <%= ENV['API_KEY'] || 'default_value' %>
timeout: <%= ENV['TIMEOUT'] || 30 %>
```

## Configuration Layering

Following the [Config vs Settings architecture](../architecture/config-vs-settings.md):

1. **Base Layer**: `mutable_settings.defaults.yaml` provides operational defaults
2. **Environment Layer**: Environment variables override defaults
3. **Runtime Layer**: Database settings can override configuration values

Mutable settings complement core configuration (`config.yaml`) which handles system-critical parameters requiring deploy-time changes.

## Security Considerations

- Sensitive values (API keys, secrets) should use environment variables
- File-based configuration requires deploy-time changes
- Rate limits prevent abuse and ensure system stability
- Email validation prevents spam and invalid registrations

## Validation

Configuration validation occurs at application startup. Invalid values will prevent application launch with descriptive error messages.
