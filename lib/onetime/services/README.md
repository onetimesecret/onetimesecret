## System Design: Init Scripts, Service Providers, and Dynamic Configuration - rev2

### Architecture Overview
Your two-phase initialization cleanly separates concerns that Rails conflates:

**Phase 1: Init Scripts** (`etc/init.d/*.rb`)
- Run during config processing (before freeze)
- One script per config section
- Normalize/validate configuration
- Set derived config values
- Cannot start services

**Phase 2: Service Providers** (`lib/onetime/services/system/*.rb`)
- Run after config freeze
- Initialize services using final config
- Register with ServiceRegistry
- Set application state
- **Load dynamic configuration from Redis**

### ServiceRegistry Pattern
Replaces scattered `Onetime.locales`, `Onetime.d9s_enabled` globals:

```ruby
module Onetime::ServiceRegistry
  @providers = Concurrent::Map.new    # Service instances/connections
  @app_state = Concurrent::Map.new    # Runtime state values

  def self.register_provider(name, provider)
  def self.set_state(key, value)      # Used for dynamic config storage
  def self.state(key)                 # Access dynamic config/state
  def self.reload_all(new_config)     # Hot reload capability
end
```

### Dynamic Configuration
- **Static config**: YAML file (database URLs, core settings)
- **Dynamic config**: Redis-stored (footer links, runtime settings)
- **Unified access**: `Onetime.conf[:key]` for both types

```ruby
module Onetime
  def self.conf
    @conf ||= ConfigProxy.new
  end
end

class ConfigProxy
  def [](key)
    # Static first to avoid dynamic config overrides
    @static_config[key] || ServiceRegistry.state(key)
  end
end
```

### Service Provider Types
- **Instance providers**: Return objects (LocaleService instance)
- **Connection providers**: Configure modules (EmailerService sets up mailer)
- **Dynamic config provider**: Loads Redis settings into ServiceRegistry state
- All register via ServiceRegistry instead of polluting Onetime namespace

### Orchestration Flow
```ruby
def boot!
  run_init_scripts(config)           # Phase 1: Config normalization
  freeze_config()
  Onetime::Services::System.start_all(config)  # Phase 2: Service providers
end

def Onetime::Services::System.start_all(config)
  start_database_connections(config)  # Essential connections first
  load_dynamic_configuration()        # Load Redis config early
  start_remaining_providers(config)   # Other services
end
```

### Configuration Access Patterns
```ruby
# All config accessed via same interface:
Onetime.conf[:database_url]    # Static from YAML
Onetime.conf[:footer_links]    # Dynamic from Redis (via ServiceRegistry.state)
Onetime.conf[:locales]         # Service state

# Internal implementation routes to:
# - ServiceRegistry.state() for dynamic/runtime values
# - Static YAML config for traditional settings
```

### Benefits Over Rails
- Clear config finalization point
- Hot reload capability via ServiceRegistry
- No global state pollution
- Explicit service lifecycle management
- Better separation of concerns than Rails initializers
- **Unified config interface hiding static/dynamic complexity**

This architecture enables config reloading without restart while maintaining cleaner boundaries than Rails' single-phase approach. Dynamic configuration integrates seamlessly through the existing ServiceRegistry pattern.
