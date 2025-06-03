# Core Configuration Documentation

## Overview

Core configuration manages OneTimeSecret's foundational infrastructure settings through `etc/config.yaml`. These parameters—including database connections, security middleware, authentication systems, and mail delivery—require application restart to modify and form the bedrock of system operations. This configuration layer focuses on infrastructure concerns that demand careful consideration during deployment, complementing the runtime-adjustable system settings that handle feature toggles and operational preferences.

## Configuration Structure

### Site Configuration (`site`)

Establishes core application identity and security framework.

#### Basic Settings
- `host`: Primary hostname and port (e.g., 'localhost:3000', 'onetimesecret.com')
- `ssl`: Enable HTTPS enforcement (boolean)
- `secret`: Application secret key for cryptographic operations (**CRITICAL: Change from default**)

#### Authentication (`authentication`)
- `enabled`: Toggle authentication system (default: true)
- `colonels`: Array of administrator email addresses with elevated privileges

#### Authenticity Protection (`authenticity`)
- `type`: Anti-bot protection method ('altcha' or alternative)
- `secret_key`: HMAC key for authenticity challenges (**CRITICAL: Replace default**)

#### Security Middleware (`middleware`)
Collection of security protections that can be toggled individually:

- `static_files`: Serve frontend Vue application assets
- `utf8_sanitizer`: Sanitize request parameters for proper UTF-8 encoding
- `http_origin`: CSRF protection via origin validation
- `escaped_params`: HTML entity escaping in request parameters
- `xss_header`: X-XSS-Protection browser header
- `frame_options`: Clickjacking protection via X-Frame-Options
- `path_traversal`: Block directory traversal attacks
- `cookie_tossing`: Prevent session fixation via cookie manipulation
- `ip_spoofing`: Validate IP addresses against spoofing
- `strict_transport`: Force HTTPS via HSTS headers

### Storage Configuration (`storage`)

Defines data persistence and caching infrastructure.

#### Database Connection (`db.connection`)
- `url`: Redis connection string (e.g., 'redis://localhost:6379')

#### Database Mapping (`db.database_mapping`)
Redis database allocation by data type:
- `session`: User session storage (DB 1)
- `splittest`: A/B testing data (DB 1)
- `custom_domain`: Custom domain configurations (DB 6)
- `customer`: Customer account data (DB 6)
- `subdomain`: Subdomain mappings (DB 6)
- `metadata`: Secret metadata (DB 7)
- `email_receipt`: Email delivery tracking (DB 8)
- `secret`: Encrypted secret storage (DB 8)
- `rate_limit`: Rate limiting counters (DB 2)
- `feedback`: User feedback submissions (DB 11)
- `exception_info`: Error tracking data (DB 12)
- `system_settings`: Runtime settings cache (DB 15)

### Mail Configuration (`mail`)

Configures email delivery infrastructure and routing.

#### Connection Settings (`connection`)
- `mode`: Email delivery method ('ses', 'smtp', etc.)
- `region`: AWS SES region for cloud email delivery
- `from`: Sender email address (**CRITICAL: Change from default**)
- `fromname`: Sender display name
- `host`: SMTP server hostname
- `port`: SMTP server port (typically 587 for TLS)
- `user`: SMTP authentication username
- `pass`: SMTP authentication password
- `auth`: SMTP authentication method ('login', 'plain', etc.)
- `tls`: TLS encryption configuration

### Internationalization (`i18n`)

Establishes multi-language support and locale handling.

#### Basic Settings
- `enabled`: Toggle internationalization features
- `default_locale`: Default language code ('en', 'fr', etc.)

#### Locale Fallbacks (`fallback_locale`)
Defines fallback chains when translations are missing:
- Regional variants fall back to base language then English
- Custom fallback chains for specific locales

#### Available Locales (`locales`)
Complete language codes with full translation support:
- European: bg, da_DK, de, de_AT, el_GR, en, es, fr_CA, fr_FR, it_IT, nl, pl, sv_SE, tr, uk
- Asian: ja, ko
- Pacific: mi_NZ
- Americas: pt_BR

#### Incomplete Locales (`incomplete`)
Language codes with partial translation coverage:
- ar, ca_ES, cs, he, hu, pt_PT, ru, sl_SI, vi, zh

### Development Configuration (`development`)

Optimizes application behavior for development workflows.

#### Basic Settings
- `enabled`: Auto-detect development environment from RACK_ENV
- `debug`: Enable debug logging and verbose output

#### Frontend Development (`frontend_host`)
Configuration for frontend development workflow:
- Set to 'http://localhost:5173' to use built-in Vite proxy
- Leave empty when using external reverse proxy (nginx, Caddy)
- Enables live-reloading during frontend development

### Experimental Features (`experimental`)

Toggles for experimental functionality and legacy compatibility.

- `allow_nil_global_secret`: Allow empty global secret (development only)
- `rotated_secrets`: Array of previous secret keys for rotation
- `freeze_app`: Emergency application freeze toggle

## Environment Variable Integration

All configuration values support ERB templating with environment variable overrides:

```yaml
host: <%= ENV['HOST'] || 'localhost:3000' %>
ssl: <%= ENV['SSL'] == 'true' || false %>
secret: <%= ENV['SECRET'] || 'CHANGEME' %>
```

## Security Critical Settings

### Must Change From Defaults
- `site.secret`: Application cryptographic key
- `site.authenticity.secret_key`: Anti-bot protection key
- `mail.connection.from`: Sender email address
- `site.authentication.colonels`: Administrator email list

### Security Middleware
Each middleware component provides specific protection. Disable only when:
- Behind a security proxy that provides equivalent protection
- In development environments with controlled access
- When conflicts with legitimate application functionality occur

## Configuration Layering

Following the [Config vs Settings architecture](../architecture/config-vs-settings.md):

1. **File Layer**: `config.yaml` provides system-critical defaults
2. **Environment Layer**: Environment variables override file values
3. **Deploy Layer**: Configuration changes require application restart

Core configuration complements system settings (`system_settings.defaults.yaml`) which handle operational parameters modifiable at runtime.

## Validation and Security

- Configuration validation occurs at application startup
- Invalid values prevent application launch with descriptive errors
- Sensitive values should use environment variables, not hardcoded values
- Default values marked 'CHANGEME' must be replaced before production deployment
- Database separation prevents data contamination and enables targeted backups

## Development vs Production

### Development Mode
- Enables frontend proxy for live-reloading
- Relaxes certain security constraints
- Provides verbose debugging output
- Allows experimental features

### Production Mode
- Enforces security middleware settings
- Requires valid SSL certificates when `ssl: true`
- Validates all critical configuration values
- Disables development-specific features
