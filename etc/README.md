# Configuration

This directory contains configuration files and processing logic for the application, following Unix convention where `/etc` holds system configuration regardless of format.

## Directory Structure

- **Configuration Data**: YAML files defining application behavior
- **Processing Logic**: Ruby code that transforms configuration into runtime state
- **Validation**: JSON Schema ensuring configuration correctness

## Files

### Core Configuration
- `examples/config.example.yaml` - Template with example values
- `config.yaml` - Main application configuration
- `config.schema.json` - Validation schema and defaults

### System Configuration
- `system_settings.example.yaml` - Default system settings
- `redis.conf` - Redis server configuration

### Application Data
- `fortunes` - Messages used in signup verification process

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

The Ruby backend uses the schema at startup for validation and default application. The Vue frontend references it for API interactions and the Colonel administrative interface.
