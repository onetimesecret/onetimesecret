# Configuration

This directory contains configuration files and processing logic for the application, following Unix convention where `/etc` holds system configuration regardless of format.

## Configuration Architecture

The application uses a **two-part configuration system**:

### Static Configuration
- **Source**: YAML files (`config.yaml`, defaults)
- **Contains**: Essential application settings that require restart to change
  - Database connections (Redis, etc.)
  - Site identity (name, domain)
  - Authentication providers
  - Core system settings
  - Diagnostic settings
- **Loading**: Processed at startup by `init.d/` Ruby modules
- **Modification**: Requires application restart

### Dynamic Configuration
- **Source**: Redis storage via `SystemSettings` model
- **Contains**: Runtime-modifiable settings
  - Interface customization
  - Secret handling options
  - Email configuration
  - Rate limits
- **Loading**: Retrieved at runtime, supersedes static config when present
- **Modification**: Via Colonel administrative interface, no restart required

The system merges both configurations at runtime, with dynamic settings taking precedence over static ones for overlapping sections.

## Directory Structure

- `etc/` - **Configuration Data**: YAML files defining application behavior.
- `etc/init.d` - **Processing Logic**: Ruby code that transforms configuration into runtime state.
- `etc/defaults` - **Default Config Files**: Used as the starting point for new installs.
- `etc/examples` - **Example Snippets**: Individual sections of the configuration demonstrating specific features.

## Files

### Core/Static Configuration
- `config.yaml` - Main application configuration
- `config.schema.yaml` - Validation schema and defaults
- `defaults/config.defaults.yaml` - Template with example values
- `defaults/system_settings.defaults.yaml` - Default system settings template

### System/Dynamic Configuration
- `system_settings.yaml` - Runtime system settings

### Initialization scripts

Each file corresponds to a section in the static config. It's responsible for any normalization or runtime changes for its section. And also has access to all the other sections as a frozen hash named globals. The globals hash is updated with all of the previous sections' modifications so they can observe each other's changes in a safe and constructive manner. After all the init scripts have run, the static configuration is frozen for the rest of the lifetime of the process. The next stage of the boot up routine is for the service providers.

- `init.d/BOOT.rb` - Bootstrap initialization
- `init.d/CONFIG.rb` - Configuration processing
- `init.d/development.rb` - Development environment setup
- `init.d/diagnostics.rb` - System diagnostics
- `init.d/experimental.rb` - Experimental features
- `init.d/i18n.rb` - Internationalization setup
- `init.d/logging.rb` - Logging configuration
- `init.d/mail.rb` - Email system setup
- `init.d/site.rb` - Site-specific configuration
- `init.d/storage.rb` - Storage backend setup

### Configuration Examples
- `examples/limit-signups-by-domain.yaml` - Domain-based signup restrictions
- `examples/local-dev-mail.yaml` - Local development email setup
- `examples/redis-db-zero.yaml` - Redis database configuration
- `examples/ses-mail.yaml` - AWS Simple Email Service email configuration
- `examples/smtp-mail.yaml` - SMTP email configuration


## Configuration Schema

The `config.schema.yaml` provides:
- **Validation** of configuration structure
- **Documentation** of available options
- **Defaults** for missing settings
- **Cross-platform** compatibility (Ruby backend, Vue frontend)

### Usage Examples

**Ruby** (validation and defaults):
```ruby
schema = YAML.load_file('etc/config.schema.yaml')
config = YAML.load_file('etc/config.yaml')

# Validate and apply defaults
JSON::Validator.validate!(schema, config, insert_defaults: true)
```

**Vue** (schema access):
```javascript
import schema from '../etc/config.schema.yaml'
```

The Ruby backend uses the schema at startup to validate the static configuration (config.yaml) and to apply default values where needed. The Vue frontend references it for API interactions and the Colonel administrative interface.

## Configuration Flow

1. **Startup**: Static configuration loaded from YAML files
2. **Runtime**: Dynamic configuration retrieved from Redis via SystemSettings
3. **Merging**: Dynamic settings override static ones for managed sections
4. **Colonel UI**: Provides interface to modify dynamic configuration sections

The SystemSettings model manages these dynamic sections:
- `interface` - UI customization and site branding
- `secret_options` - Secret handling policies
- `mail` - Email delivery configuration
- `limits` - Rate limiting and usage controls
