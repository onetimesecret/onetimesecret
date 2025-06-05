# Configuration

This directory contains configuration files and schemas for the application (including Ruby and Vue).

## Files

### Core Configuration
- `config.yaml` - Main application configuration (runtime)
- `config.example.yaml` - Template configuration with example values
- `config.schema.json` - JSON Schema for validating configuration structure and defaults

### System Files
- `system_settings.example.yaml` - Default system settings
- `redis.conf` - Redis server configuration

### External Services
- `fortunes` - Fortune cookie messages, used in verification secrets during the signup process.


## Configuration Schema

The `config.schema.json` file serves as:
- **Validation**: Ensures configuration structure correctness
- **Documentation**: Defines expected configuration options
- **Defaults**: Provides fallback values for missing settings
- **Cross-platform**: Used by both Ruby backend and Vue frontend

The ruby code uses it at start time to validate and apply defaults to the core config; the Vue refers to it when interacting with the API -- including in the Colonel UI for modifying the settings.


### Usage
```ruby
# Ruby - validation and default extraction
require 'json'
require 'yaml'
require 'json-schema'

# Load the schema
schema = JSON.parse(File.read('etc/config.schema.json'))

# Load configuration from YAML
config_hash = YAML.load_file('etc/config.yaml')

# Validate the configuration against the schema
errors = JSON::Validator.fully_validate(schema, config_hash)
if errors.any?
  raise "Configuration validation failed: #{errors.join(', ')}"
end

# Apply defaults from schema for missing values
config_with_defaults = JSON::Validator.validate(schema, config_hash, insert_defaults: true)
```

```javascript
// Vue - build-time validation or runtime API access
import schema from '../etc/config.schema.json'
```
