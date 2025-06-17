# Configuration

This directory contains configuration files and processing logic for the application, following Unix convention where `/etc` holds system configuration regardless of format.

## Directory Structure

- `etc/` - **Configuration Data**: YAML files defining application behavior.
- `etc/init.d` - **Processing Logic**: Ruby code that transforms configuration into runtime state.
- `etc/defaults` - **Default Config Files**: Used as the starting point for new installs.
- `etc/examples` - **Example Snippets**: Individual sections of the configuration demonstrating specific features.

## Files

### Core/Static Configuration
- `defaults/config.defaults.yaml` - Template with example values
- `config.yaml` - Main application configuration
- `config.schema.json` - Validation schema and defaults

### System/Dynamic Configuration
- `system_settings.example.yaml` - Default system settings


## Configuration Schema

The `config.schema.json` provides:
- **Validation** of configuration structure
- **Documentation** of available options
- **Defaults** for missing settings
- **Cross-platform** compatibility (Ruby backend, Vue frontend)

### Usage Examples

**Ruby** (validation and defaults):
```ruby
schema = JSON.parse(File.read('etc/config.schema.json'))
config = YAML.load_file('etc/config.yaml')

# Validate and apply defaults
JSON::Validator.validate!(schema, config, insert_defaults: true)
```

**Vue** (schema access):
```javascript
import schema from '../etc/config.schema.json'
```

The Ruby backend uses the schema at startup to validate the static configuration (config.yaml) and to apply default values where needed. The Vue frontend references it for API interactions and the Colonel administrative interface.
